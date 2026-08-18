#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# -----------------------------------------------------------------------------
# k8mm Remaining GitOps Issue Log Collector
#
# Collects evidence for:
#   - Rancher / Fleet reconciliation
#   - Elastic Agent DaemonSet rollout failures
#   - Istiod rollout failures
#   - Contour rollout/render/runtime failures
#   - Keycloak operator rollout failures
#   - CloudNativePG / PostgreSQL cluster readiness failures
#
# It intentionally DOES NOT dump Kubernetes Secret data or kubeconfig contents.
#
# Defaults match the k8mm Segment1 deployment. Override as needed:
#
#   MGMT_CONTEXT=j64seg1opman \
#   MANAGED_CONTEXTS="j64seg1opdev j52seg1opdev r01seg1opdev" \
#   SINCE=6h \
#   ./collect-remaining-gitops-logs.sh
# -----------------------------------------------------------------------------

MGMT_CONTEXT="${MGMT_CONTEXT:-j64seg1opman}"
MANAGED_CONTEXTS="${MANAGED_CONTEXTS:-j64seg1opdev j52seg1opdev r01seg1opdev}"
SINCE="${SINCE:-6h}"
TAIL_LINES="${TAIL_LINES:-5000}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
ROOT="${PWD}/k8mm-gitops-diagnostics-${STAMP}"
ARCHIVE="${ROOT}.tar.gz"

mkdir -p "$ROOT"

log() {
  printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2
}

safe_name() {
  printf '%s' "$1" | tr '/: @' '____' | tr -cd 'A-Za-z0-9._-'
}

capture() {
  local outfile="$1"
  shift
  mkdir -p "$(dirname "$outfile")"
  {
    printf '# UTC: %s\n' "$(date -u --iso-8601=seconds)"
    printf '# CMD:'
    printf ' %q' "$@"
    printf '\n\n'
    "$@"
  } >"$outfile" 2>&1 || {
    local rc=$?
    printf '\n# COMMAND EXIT CODE: %s\n' "$rc" >>"$outfile"
    return 0
  }
}

has_context() {
  kubectl config get-contexts -o name 2>/dev/null | grep -Fxq "$1"
}

resource_exists() {
  local ctx="$1"
  local resource="$2"
  kubectl --context "$ctx" api-resources -o name 2>/dev/null | grep -Fxq "$resource"
}

namespace_exists() {
  local ctx="$1"
  local ns="$2"
  kubectl --context "$ctx" get namespace "$ns" >/dev/null 2>&1
}

collect_pod_logs_in_namespace() {
  local ctx="$1"
  local ns="$2"
  local base="$3"

  namespace_exists "$ctx" "$ns" || return 0

  mkdir -p "$base/logs"

  local pods
  pods="$(kubectl --context "$ctx" -n "$ns" get pods -o name 2>/dev/null || true)"

  while IFS= read -r podref; do
    [[ -n "$podref" ]] || continue

    local pod="${podref#pod/}"
    local podsafe
    podsafe="$(safe_name "$pod")"

    capture "$base/logs/${podsafe}.current.log" \
      kubectl --context "$ctx" -n "$ns" logs "$pod" \
      --all-containers=true --timestamps=true --since="$SINCE" --tail="$TAIL_LINES"

    # Previous container logs are extremely useful for CrashLoopBackOff/restarts.
    capture "$base/logs/${podsafe}.previous.log" \
      kubectl --context "$ctx" -n "$ns" logs "$pod" \
      --all-containers=true --timestamps=true --previous --tail="$TAIL_LINES"

    capture "$base/pods/${podsafe}.describe.txt" \
      kubectl --context "$ctx" -n "$ns" describe pod "$pod"
  done <<<"$pods"
}

collect_namespace() {
  local ctx="$1"
  local ns="$2"
  local ctxdir="$3"
  local nsdir="$ctxdir/namespaces/$(safe_name "$ns")"

  namespace_exists "$ctx" "$ns" || return 0
  mkdir -p "$nsdir"

  log "[$ctx] namespace $ns"

  capture "$nsdir/workloads-wide.txt" \
    kubectl --context "$ctx" -n "$ns" get deploy,ds,sts,rs,pods -o wide

  capture "$nsdir/services-ingress.txt" \
    kubectl --context "$ctx" -n "$ns" get svc,ingress,endpoints,endpointslices -o wide

  capture "$nsdir/storage.txt" \
    kubectl --context "$ctx" -n "$ns" get pvc -o wide

  capture "$nsdir/configmaps.txt" \
    kubectl --context "$ctx" -n "$ns" get configmap

  # Metadata only: no Secret values are exported.
  capture "$nsdir/secrets-metadata.txt" \
    kubectl --context "$ctx" -n "$ns" get secrets \
    -o custom-columns='NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp'

  capture "$nsdir/events.txt" \
    kubectl --context "$ctx" -n "$ns" get events \
    --sort-by=.lastTimestamp

  capture "$nsdir/deployments.describe.txt" \
    kubectl --context "$ctx" -n "$ns" describe deployment

  capture "$nsdir/daemonsets.describe.txt" \
    kubectl --context "$ctx" -n "$ns" describe daemonset

  capture "$nsdir/statefulsets.describe.txt" \
    kubectl --context "$ctx" -n "$ns" describe statefulset

  capture "$nsdir/replicasets.describe.txt" \
    kubectl --context "$ctx" -n "$ns" describe replicaset

  collect_pod_logs_in_namespace "$ctx" "$ns" "$nsdir"
}

collect_cluster() {
  local ctx="$1"

  if ! has_context "$ctx"; then
    log "WARNING: kubectl context '$ctx' not found; recording and skipping."
    printf 'kubectl context not found: %s\n' "$ctx" >"$ROOT/MISSING-CONTEXT-$(safe_name "$ctx").txt"
    return 0
  fi

  local ctxdir="$ROOT/clusters/$(safe_name "$ctx")"
  mkdir -p "$ctxdir"

  log "Collecting cluster evidence from $ctx"

  capture "$ctxdir/cluster-info.txt" \
    kubectl --context "$ctx" cluster-info

  capture "$ctxdir/version.txt" \
    kubectl --context "$ctx" version

  capture "$ctxdir/nodes-wide.txt" \
    kubectl --context "$ctx" get nodes -o wide

  capture "$ctxdir/nodes-describe.txt" \
    kubectl --context "$ctx" describe nodes

  capture "$ctxdir/all-pods-wide.txt" \
    kubectl --context "$ctx" get pods -A -o wide

  capture "$ctxdir/all-deployments.txt" \
    kubectl --context "$ctx" get deployments -A -o wide

  capture "$ctxdir/all-daemonsets.txt" \
    kubectl --context "$ctx" get daemonsets -A -o wide

  capture "$ctxdir/all-statefulsets.txt" \
    kubectl --context "$ctx" get statefulsets -A -o wide

  capture "$ctxdir/all-services.txt" \
    kubectl --context "$ctx" get services -A -o wide

  capture "$ctxdir/all-pv-pvc.txt" \
    kubectl --context "$ctx" get pv,pvc -A -o wide

  capture "$ctxdir/all-events.txt" \
    kubectl --context "$ctx" get events -A --sort-by=.lastTimestamp

  capture "$ctxdir/nonrunning-pods.txt" \
    sh -c "kubectl --context $(printf %q "$ctx") get pods -A --no-headers 2>/dev/null | awk '\$4 !~ /Running|Completed/ {print}'"

  capture "$ctxdir/image-pull-and-scheduling-events.txt" \
    sh -c "kubectl --context $(printf %q "$ctx") get events -A --sort-by=.lastTimestamp 2>/dev/null | grep -Ei 'FailedScheduling|FailedMount|FailedAttach|ImagePull|ErrImage|BackOff|Unhealthy|ProgressDeadline|FailedCreate|Failed|Warning' || true"

  # Helm inventory is useful when ownership or rollback-on-failure is involved.
  if command -v helm >/dev/null 2>&1; then
    capture "$ctxdir/helm-list.txt" \
      helm --kube-context "$ctx" list -A
  fi

  # Discover namespaces related to the current failures plus common platform namespaces.
  local namespaces
  namespaces="$(
    {
      printf '%s\n' \
        cattle-fleet-system \
        cattle-system \
        fleet-default \
        fleet-local \
        elastic-agent-system \
        istio-system \
        contour \
        projectcontour \
        opkeycloak \
        keycloak \
        oppostgres \
        cnpg-system \
        postgresql \
        metallb-system
      kubectl --context "$ctx" get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
        | grep -Ei 'fleet|cattle|elastic|istio|contour|keycloak|postgres|cnpg|metallb' || true
    } | awk 'NF && !seen[$0]++'
  )"

  while IFS= read -r ns; do
    [[ -n "$ns" ]] || continue
    collect_namespace "$ctx" "$ns" "$ctxdir"
  done <<<"$namespaces"

  # --- CloudNativePG / PostgreSQL ------------------------------------------------
  if resource_exists "$ctx" "clusters.postgresql.cnpg.io"; then
    capture "$ctxdir/cloudnativepg-clusters.yaml" \
      kubectl --context "$ctx" get clusters.postgresql.cnpg.io -A -o yaml

    capture "$ctxdir/cloudnativepg-clusters.describe.txt" \
      kubectl --context "$ctx" describe clusters.postgresql.cnpg.io -A
  fi

  if resource_exists "$ctx" "poolers.postgresql.cnpg.io"; then
    capture "$ctxdir/cloudnativepg-poolers.yaml" \
      kubectl --context "$ctx" get poolers.postgresql.cnpg.io -A -o yaml
  fi

  if resource_exists "$ctx" "backups.postgresql.cnpg.io"; then
    capture "$ctxdir/cloudnativepg-backups.yaml" \
      kubectl --context "$ctx" get backups.postgresql.cnpg.io -A -o yaml
  fi

  # --- Keycloak CRs, if present --------------------------------------------------
  for r in \
    keycloaks.k8s.keycloak.org \
    keycloakrealmimports.k8s.keycloak.org \
    keycloaks.keycloak.org
  do
    if resource_exists "$ctx" "$r"; then
      capture "$ctxdir/$(safe_name "$r").yaml" \
        kubectl --context "$ctx" get "$r" -A -o yaml
    fi
  done

  # --- MetalLB confirmation ------------------------------------------------------
  if resource_exists "$ctx" "ipaddresspools.metallb.io"; then
    capture "$ctxdir/metallb-address-pools.yaml" \
      kubectl --context "$ctx" get ipaddresspools.metallb.io -A -o yaml
  fi
  if resource_exists "$ctx" "l2advertisements.metallb.io"; then
    capture "$ctxdir/metallb-l2advertisements.yaml" \
      kubectl --context "$ctx" get l2advertisements.metallb.io -A -o yaml
  fi
}

collect_fleet_control_plane() {
  local ctx="$MGMT_CONTEXT"

  if ! has_context "$ctx"; then
    log "Management context '$ctx' is not available; Fleet control-plane evidence skipped."
    return 0
  fi

  local d="$ROOT/fleet-control-plane"
  mkdir -p "$d"

  log "Collecting Rancher/Fleet control-plane evidence from $ctx"

  for resource in \
    gitrepos.fleet.cattle.io \
    bundles.fleet.cattle.io \
    bundledeployments.fleet.cattle.io \
    clusters.fleet.cattle.io \
    clusterregistrations.fleet.cattle.io \
    clusterregistrationtokens.fleet.cattle.io
  do
    if resource_exists "$ctx" "$resource"; then
      capture "$d/$(safe_name "$resource").yaml" \
        kubectl --context "$ctx" get "$resource" -A -o yaml

      capture "$d/$(safe_name "$resource").txt" \
        kubectl --context "$ctx" get "$resource" -A -o wide
    fi
  done

  # Focused Bundle descriptions for the known remaining problem chain.
  for ns in fleet-default fleet-local; do
    namespace_exists "$ctx" "$ns" || continue
    for bundle in \
      contour-segment1 \
      elastic-agent \
      istiod \
      istio-eastwestgateway \
      kiali-operator \
      kiali \
      opkeycloak-operator \
      opkeycloak \
      oppostgres \
      oppostgres-operator \
      metallb \
      metallb-config
    do
      if kubectl --context "$ctx" -n "$ns" get bundle "$bundle" >/dev/null 2>&1; then
        capture "$d/${ns}-bundle-$(safe_name "$bundle").describe.txt" \
          kubectl --context "$ctx" -n "$ns" describe bundle "$bundle"
      fi
    done
  done

  # Rancher/Fleet namespaces with controller, GitJob, HelmOps, agent, webhook logs.
  for ns in cattle-fleet-system cattle-system fleet-default fleet-local; do
    collect_namespace "$ctx" "$ns" "$ROOT/clusters/$(safe_name "$ctx")"
  done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

{
  echo "k8mm GitOps diagnostics"
  echo "UTC timestamp: $STAMP"
  echo "Management context: $MGMT_CONTEXT"
  echo "Managed contexts: $MANAGED_CONTEXTS"
  echo "Log lookback: $SINCE"
  echo "Log tail limit: $TAIL_LINES"
  echo
  echo "Security note:"
  echo "- Kubernetes Secret DATA is intentionally not exported."
  echo "- Pod logs may still contain application-generated sensitive information."
  echo "- Review the archive before sharing outside your trusted environment."
} >"$ROOT/README.txt"

capture "$ROOT/local-kubectl-contexts.txt" kubectl config get-contexts
capture "$ROOT/local-kubectl-version.txt" kubectl version --client

if command -v helm >/dev/null 2>&1; then
  capture "$ROOT/local-helm-version.txt" helm version
fi

collect_fleet_control_plane
collect_cluster "$MGMT_CONTEXT"

for ctx in $MANAGED_CONTEXTS; do
  collect_cluster "$ctx"
done

# Create a concise index of error/warning lines to make first-pass triage faster.
log "Building error index"
grep -RniE \
  'error|failed|failure|notready|not ready|crashloop|backoff|timeout|deadline|unhealthy|denied|forbidden|unschedulable|imagepull|errimage' \
  "$ROOT" \
  --exclude='error-index.txt' \
  >"$ROOT/error-index.txt" 2>/dev/null || true

log "Creating archive"
tar -C "$(dirname "$ROOT")" -czf "$ARCHIVE" "$(basename "$ROOT")"

printf '\n'
printf 'Diagnostics complete.\n'
printf 'Directory: %s\n' "$ROOT"
printf 'Archive:   %s\n' "$ARCHIVE"
printf '\nUpload the .tar.gz archive back to ChatGPT for analysis.\n'
