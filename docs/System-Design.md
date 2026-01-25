# System Design — VyOS Universal Router v1.4.4 (Azure + On‑Prem + DREN)

## Overview

This repository deploys a self-contained Hyper‑V lab that models two independent sites (Azure and On‑Prem) connected by a controlled transit called DREN. It is intended to validate AppGate SDP behavior, constrained inter-site transit policies, and deployment/runbook automation.

- Azure site: 201.x addressing and a small external WAN network (AZ‑WAN)
- On‑prem site: 202.x addressing and an external uplink (ONP‑EXT)
- DREN transit: 100.255.0.0/24 connecting `az-edge` and `onp-edge`

Design goals:
- Reproducible lab using deterministic NIC ordering (scripts attach NICs in eth0..ethN order)
- Paste‑ready VyOS configs (`configs/*.vyos`) so operators can apply, test, and iterate quickly
- Clear, minimal security posture for testing: default-allow with explicit, auditable restrictions for the transit and WAN

## Architecture and components

- Edge routers (`az-edge`, `onp-edge`) - site perimeter: connect to external uplinks, DREN, and the site core. Implement transit-level policies for DREN.
- External router (`az-external`) - Azure-facing WAN hop; currently configured to close AZ‑WAN.
- Core routers (`az-core`, `onp-core`) - hub routers for each site; host inter‑spoke routing and route distribution (static in this lab).
- Spokes (`inside`, `developer`, `segment1`) - protected segments behind the cores.
- Management network - `VYOS-OOB` interfaces on `eth0` are used for lab management and SSH dynamic-protection.

Logical flows:
- Client spokes default to their site `core`.
- `core` default-routes to `edge`.
- Azure `edge` default-routes to `external`.
- DREN is a dedicated transit; both edges peer to DREN with static next-hops.

## Addressing and routing

- Per-router static addressing is defined in `configs/*.vyos`. Each spoke and core has a static `ethX` address; management OOB addresses are static in the configs in this lab.
- Default route summary (configured by static routes in the configs): cores and spokes point toward their site edge/core as appropriate; `az-external` and `onp-edge` have explicit upstream next-hops defined in their respective files.

## Security controls and firewall design

This lab demonstrates layered controls and explicit enforcement points while remaining compact enough for iterative testing.

1) Transit restriction (DREN)
- Implemented as two chained firewall names on edges: `DREN-ALLOW` (used for forward/output) and `DREN-LOCAL` (used for input to router-local services).
- Policy: allow only ICMP, TCP/443, UDP/443, UDP/53, and established/related; drop everything else.
- Applied to packets that either ingress from or egress to the DREN interface (eth2) via jumps from the base input/forward/output chains.

2) AZ‑WAN closure
- `az-external` defines `AZWAN-DROP` and jumps to it for any traffic touching the AZ‑WAN interface (eth1) on input/forward/output, effectively isolating that network for the lab.

3) Management hardening
- SSH limited via VyOS `dynamic-protection` and `allow-from 10.255.255.0/24` (management jump host/subnet).
- Keep management on a separate OOB network (`VYOS-OOB` / eth0) and do not expose router control-plane across DREN/AZ‑WAN.

4) Firewall groups (reusable policy objects)
- `configs/common/firewall-groups.vyos` defines port-groups (e.g., `APPGATE_CLIENT_TCP`, `PROTECTED_TCP`) so policies can be expressed using logical names instead of port lists.

## Best practices demonstrated

- Keep per-router configuration contained in `configs/*.vyos` for paste-and-test workflows.
- Use explicit `jump` chains for transit restrictions (e.g., DREN) so the intent is auditable and testable.
- Limit management access using a single management subnet with dynamic-protection and source-limited SSH.
- Prefer least-privilege testing for transit (start closed/restricted; open necessary ports later).
- Use deterministic VM NIC ordering in `scripts/deploy-hyperv-lab.ps1` to avoid NIC mapping drift.

## Operational notes and validation

- To validate DREN behavior: ping and attempt TCP/443 between spokes across sites; non‑443, non‑ICMP flows should fail across DREN.
- To validate AZ‑WAN closure: attempt connectivity to/from `az-external` eth1; traffic should be dropped by `AZWAN-DROP`.
- Use `apply-config.sh` or SSH into a single VyOS VM and paste `configs/<router>.vyos` then `commit` and `save` to test changes.

## Diagrams

The repo contains multiple mermaid sources. The topology is in `diagrams/topology.mmd`. An embedded, simplified mermaid view is provided here for quick reference:

```mermaid
flowchart LR
	MGMT((VYOS-OOB\nDHCP / eth0))
	subgraph AZ[Azure (201.x)]
		AZ_EXT[az-external\nAZ-WAN eth1 201.255.0.2/24\nAZ-EXT eth2 201.254.0.2/24]
		AZ_EDGE[az-edge\nAZ-EXT eth1 201.254.0.1/24\nAZ-DREN eth2 100.255.0.1/24]
		AZ_CORE[az-core\nAZ-CORE eth1 201.0.0.1/24]
	end
	subgraph ONP[On-Prem (202.x)]
		ONP_EDGE[onp-edge\nONP-EXT eth1 202.254.0.1/24\nONP-DREN eth2 100.255.0.2/24]
		ONP_CORE[onp-core\nONP-CORE eth1 202.0.0.1/24]
	end
	DREN((DREN\n100.255.0.0/24\nALLOW: ICMP, 443/TCP+UDP, 53/UDP))
	MGMT --- AZ_EXT
	MGMT --- AZ_EDGE
	MGMT --- AZ_CORE
	MGMT --- ONP_EDGE
	MGMT --- ONP_CORE
	AZ_EDGE --- DREN --- ONP_EDGE
	AZ_EXT --- AZ_EDGE --- AZ_CORE
	ONP_EDGE --- ONP_CORE
```

For full, richly annotated diagrams see `diagrams/topology.mmd` and `diagrams/appgate-flows.mmd`.

## Next steps and extensibility

- Convert static routing to a routing protocol (BGP/OSPF) if you want to test control‑plane behaviors.
- Replace `default allow` posture with explicit spoke-to-spoke segmentation using the `PROTECTED_TCP` groups.
- Add logging/monitoring (syslog, NetFlow/sFlow) on `edge` routers to capture cross-site flows for testing and audit.

## Where to look

- Router configs: `configs/azure/*.vyos`, `configs/onprem/*.vyos`
- Shared firewall objects: `configs/common/firewall-groups.vyos`
- Deployment scripts: `scripts/deploy-hyperv-lab.ps1`, `scripts/create-hyperv-switches.ps1`

If you want, I can also add a step-by-step change example (patching one router, validating, rolling out) to `docs/Runbook.md`.
