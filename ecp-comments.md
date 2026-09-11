Got it — this ECP should cover the **entire initial SEG1OPDEV deployment into the production air-gapped environment**, not today’s individual corrective action. I’d frame it as a **major platform implementation with moderate execution risk but controlled rollback**, since this is the first production instantiation of the architecture.

### Level of effort to execute the CR

**High.** Estimated **3–5 engineering days** for deployment, configuration, validation, troubleshooting, and operational turnover. The effort includes RKE2 cluster deployment/integration, Rancher/Fleet GitOps, storage, networking, ingress, PKI, monitoring, service mesh, identity services, database replication, and application/platform validation across the air-gapped environment.

### Performance risk/impact

**Moderate during implementation; Low after stabilization.** Initial deployment may generate elevated CPU, memory, storage I/O, and network utilization while container images are imported, Helm packages are deployed, Fleet reconciles bundles, and databases initialize or replicate.

No degradation to existing production services is expected because SEG1OPDEV is a new deployment. Capacity, storage performance, ingress routing, DNS, database replication, and cluster resource utilization will be verified before operational acceptance.

### Engineering team input

Platform Engineering recommends proceeding with the deployment using the validated GitOps-based architecture and deployment automation.

The implementation establishes the initial production SEG1OPDEV Kubernetes platform, including:

* RKE2 Kubernetes clusters
* Rancher and Fleet centralized management
* GitOps-controlled platform deployment
* MetalLB and ingress services
* Longhorn persistent storage
* Istio service mesh
* Kiali observability
* Prometheus/Grafana monitoring
* CloudNativePG PostgreSQL services
* Keycloak identity services
* GitLab Runner integration
* Certificate management and internal PKI integration
* Air-gap registry-hosted container images and Helm packages

Engineering will validate each platform layer before progressing to dependent services.

### Schedule analysis

The deployment should be performed during a planned implementation window with engineering resources available for Kubernetes, networking, storage, identity, and security support.

Estimated execution is **3–5 engineering days**, including deployment and stabilization. Additional observation time may be required before declaring the environment fully operational.

The deployment should follow a phased sequence so failures can be isolated before dependent components are introduced.

### Implementation plan

1. Validate production network, DNS, NTP, storage, registry, certificates, and air-gap prerequisites.
2. Validate all required container images and Helm packages are present in the approved internal registry/repository.
3. Deploy and validate the RKE2 Kubernetes clusters.
4. Register/import clusters into Rancher.
5. Deploy Rancher Fleet GitOps configuration.
6. Deploy namespace, security, storage, networking, ingress, and certificate-management components.
7. Deploy Longhorn and validate persistent storage.
8. Deploy Istio/Kiali and validate service-mesh functionality.
9. Deploy monitoring and observability services.
10. Deploy CloudNativePG database services and validate replication and failover readiness.
11. Deploy Keycloak identity services and validate authentication and ingress connectivity.
12. Deploy remaining platform services and GitLab Runner integration.
13. Validate all Fleet bundles and BundleDeployments.
14. Perform end-to-end platform, identity, storage, network, security, and failover testing.
15. Capture deployment evidence and transition the environment to operational support.

### Test and verification plan

Verification will include:

* All RKE2 nodes report `Ready`.
* All clusters are connected and healthy in Rancher.
* Fleet GitRepos, Bundles, and BundleDeployments report Ready.
* Required namespaces and security controls are applied.
* MetalLB VIPs respond as designed.
* Ingress endpoints and DNS records resolve correctly.
* TLS certificates validate against approved trust chains.
* Longhorn volumes provision, mount, and recover correctly.
* Istio control plane and gateways are healthy.
* Kiali and monitoring services are accessible.
* Prometheus metrics and Grafana dashboards are populated.
* CloudNativePG database clusters are healthy and replication is operational.
* Planned database/identity failover procedures are validated.
* Keycloak authentication and application integration function correctly.
* GitLab Runner successfully executes approved validation workloads.
* Kubernetes security and policy validation completes successfully.
* Deployment-package validation completes without critical errors.
* No unexpected Failed, Pending, CrashLoopBackOff, or degraded platform workloads remain.
* Operational documentation and recovery procedures are verified against the deployed environment.

### Rollback plan

Because this is a **new production platform deployment**, rollback primarily consists of halting the implementation and returning the new environment to its pre-deployment state rather than restoring an existing production workload.

If a critical issue occurs:

1. Stop Fleet reconciliation or suspend the affected GitRepo.
2. Revert the Git repository to the last validated commit where applicable.
3. Remove or roll back the affected Helm/Fleet deployment.
4. Restore configuration from the approved Git repository and deployment artifacts.
5. Restore persistent data from snapshots/backups if data-bearing services have been initialized.
6. If platform integrity cannot be assured, remove the affected cluster and rebuild it from the approved deployment baseline.
7. Existing production systems remain unchanged and continue operating independently.

No operational workload will be migrated to SEG1OPDEV until acceptance criteria are successfully completed.

### Story points

**13 story points**

This represents a high-complexity infrastructure implementation involving multiple Kubernetes clusters, GitOps orchestration, air-gap dependencies, storage, networking, PKI, service mesh, monitoring, database replication, identity services, and end-to-end verification.

### Comments

This CR authorizes the **initial deployment of the SEG1OPDEV platform into the production air-gapped environment**.

This deployment establishes the production Kubernetes and GitOps foundation that subsequent application and mission-service deployments will consume.

Because this is the first deployment of the architecture in the production air-gap environment, additional engineering attention will be placed on dependency validation, deployment sequencing, troubleshooting, failover testing, security controls, operational documentation, and evidence collection.

The deployment will be considered complete only after all clusters and platform services are healthy, GitOps reconciliation is stable, identity/database failover procedures have been validated, and operational acceptance criteria have been satisfied.

For Jira, I’d stick with **13 story points**. This is well beyond a normal application change: it’s essentially standing up the production Kubernetes platform, its management plane, storage, networking, identity, observability, PKI, and GitOps operating model in one controlled implementation.
