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
- `scripts/` – helper scripts for automation (deploy, cleanup, SSH push)

## Quick start
1. Review **assumptions** in `docs/System-Design.md` (especially the underlay IPs for the IPsec tunnel and the SDPC transit IPs for Inside/Dev/Sandbox routers).
2. On each VyOS VM, map NICs deterministically using `hw-id` (MAC) per Hyper-V.
3. Apply configs:
   - External (Azure) → Outside → Grey → Inside/Developer/Sandbox
   - On-Prem Outside → On-Prem Grey → On-Prem Inside/Developer/Sandbox
4. Validate tunnel + routing + policy using the Runbook.

## Hyper-V deployment (one command)
The end-to-end Hyper-V deploy script creates switches, VMs, config ISOs, and DVD ordering.

Prerequisites:
- Hyper-V PowerShell module
- ISO tool: Windows ADK (`oscdimg.exe`) or `mkisofs` / `genisoimage`

Example:
```
powershell .\scripts\deploy-hyperv-lab.ps1
```

Optional overrides:
```
powershell .\scripts\deploy-hyperv-lab.ps1 -MemoryStartupBytes 1GB -CpuCount 1 -UseExternalAdapters -AzureExternalAdapterName "<adapter>" -OnPremUnderlayAdapterName "<adapter>"
```

## Hyper-V cleanup
Remove the lab VMs and switches:
```
powershell .\scripts\remove-hyperv-lab.ps1
```

## Generate hw-id mappings
To pin interfaces to MACs on each VM:
```
powershell .\scripts\export-vyos-hwids.ps1 -OutputPath .\artifacts\vyos-hwids.txt
```

## Automation note
VyOS config is best treated as **IaC**:
- Keep the desired-state config in Git
- Apply via SSH using `load merge` + `commit-confirm` + `save`

See `scripts/apply-config.sh`.

## First-boot config injection (NoCloud seed ISO)
If you want a router to **self-apply a .vyos config on first boot**, use the helper script.
It creates a **NoCloud** seed ISO (label `CIDATA`) with `user-data` and `meta-data` files and attaches it to the VM DVD.

Example:
1) Install VyOS on the VM and shut it down.
2) Run (PowerShell):
  `./scripts/bootstrap-vyos.ps1 -ConfigPath configs/azure/grey.vyos -VmName vyos-az-proton-grey`
   - Optional: add `-DisableDhcpEth0` to generate `network-config` that disables DHCP on `eth0`.
3) Start the VM; cloud-init applies the config during first boot via NoCloud.

Note: The script requires an ISO tool (`oscdimg.exe`, `mkisofs`, or `genisoimage`) and labels the ISO `CIDATA` per NoCloud requirements.
