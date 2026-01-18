# VyOS + Appgate SDP Lab (Azure + On-Prem DREN)

This repo is a **paste-ready** starting point for configuring a 2-site lab network using **VyOS 2025.11** on Hyper-V.

It implements:
- Two sites: **Azure (PROTON)** and **On-Prem (RCDN-U)**
- A routed **DREN-to-DREN** interconnect using **IPsec VTI** between the **Outside** routers
- Segmentation + least privilege flows for an **Appgate SDP** deployment:
  - **SDPC** = Appgate Controllers
  - **SDPG/SDPT** = Appgate Gateways
  - **AVD** = AVD client subnet (Appgate clients/agents live here)
  - **AVD clients are allowed to reach SDPC** for enrollment/auth/policy updates (in addition to reaching SDPG/SDPT for the data plane)
  - **Inside / Developer / Sandbox(SEG)** = protected resources
  - **HWIL** exists only on On-Prem and is isolated behind SEG

> NOTE: The original spreadsheet includes a typo where the **DEVSVC gateway** is listed as `10.2.1.0` / `20.2.1.0`. Gateways must be a host IP. This repo uses `10.2.1.1` / `20.2.1.1`.

## Repository layout
- `docs/System-Design.md` – detailed design + routing + security model
- `docs/Runbook.md` – build/validate/troubleshoot commands
- `configs/azure/*.vyos` – Azure site router configs
- `configs/onprem/*.vyos` – On-Prem site router configs
- `configs/common/*.vyos` – reusable groups/policies
- `diagrams/*.mmd` – Mermaid diagrams
- `scripts/` – helper scripts for automation (SSH push pattern)

## Quick start
1. Review **assumptions** in `docs/System-Design.md` (especially the underlay IPs for the IPsec tunnel and the SDPC transit IPs for Inside/Dev/Sandbox routers).
2. On each VyOS VM, map NICs deterministically using `hw-id` (MAC) per Hyper-V.
3. Apply configs:
   - External (Azure) → Outside → Grey → Inside/Developer/Sandbox
   - On-Prem Outside → On-Prem Grey → On-Prem Inside/Developer/Sandbox
4. Validate tunnel + routing + policy using the Runbook.

## Automation note
VyOS config is best treated as **IaC**:
- Keep the desired-state config in Git
- Apply via SSH using `load merge` + `commit-confirm` + `save`

See `scripts/apply-config.sh`.
