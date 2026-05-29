# Copilot instructions — vyos-appgate-dren-lab

This file contains concise, actionable guidance for AI coding agents working in this repository.

Purpose
- Help a coding agent be immediately productive: understand the topology, deployment workflows, key files, and project-specific patterns.

Big picture (what to know first)
- This repo builds a deployable Hyper-V home-lab with one central router (`router-center`), three site routers (`router-dc1`/`router-dc2`/`router-dc3`), and four Kubernetes clusters.
- Router and node configs are under `configs/home-lab/` and are paste-ready VyOS `set ...` and rkeprep node YAML files.
- NIC ordering and switch naming are driven by `scripts/create-vyos-routers.ps1` and `scripts/create-multicluster-vms.ps1`.

Critical developer workflows (explicit commands)
- Create routers and required home-lab switches:
  - `.\scripts\create-vyos-routers.ps1 -ExternalSwitchName cotpa-vlans_vsw -ExternalVlanId 9`
- Create node VMs:
  - `.\scripts\create-multicluster-vms.ps1 -VhdPath <path-to-node.vhdx>`
- Apply router configs: connect to a router VM, `configure`, paste commands from `configs/home-lab/routers/*.vyos`, then `commit`/`save`.
- Apply node manifests from `configs/home-lab/nodes/`.

Project-specific conventions and patterns
- Router naming convention: `router-center`, `router-dc1`, `router-dc2`, `router-dc3`.
- Only `router-center` has external uplink (`cotpa-vlans_vsw`) and VLAN 9.
- Site and transit switches are internal.
- Config file style: home-lab router files are plain VyOS `set ...` commands; node files are rkeprep YAML.

Integration points & external dependencies
- Hyper-V host (Windows) and elevated PowerShell are required.
- A VyOS VHDX is required for router VM creation.
- A Linux node VHDX is required for cluster node VM creation.

Where to look for examples
- Deployment runbook: `docs/Runbook.md`.
- Home-lab diagrams:
  - `diagrams/Architecture-Overview.mmd` (component-complete architecture overview)
  - `diagrams/Clusters-and-Workloads.mmd` (engineering systems view with node/NIC/IP detail)
  - `diagrams/Network-Topology.mmd` (Hyper-V and routing topology detail)
  - `diagrams/System-Design.mmd` (cross-domain control and traffic summary)
- Router configs: `configs/home-lab/routers/*.vyos`.
- Node manifests: `configs/home-lab/nodes/*.yaml`.
- Automation scripts: `scripts/create-vyos-routers.ps1`, `scripts/create-multicluster-vms.ps1`.

How to reason about the design (for coding agents)
- What the diagram stack is:
  - A progressive zoom model from architecture -> systems -> topology, with a companion control/traffic summary.
- What the diagram stack does:
  - Keeps naming and routing intent consistent while exposing deeper implementation detail at each step.
- How the full design works:
  - Site clusters attach to site routers via site switches, site routers converge on transit, `router-center` provides Internet egress on VLAN 9, and shared platform services (mesh/obs/storage) span clusters.

How to make safe edits (recommended steps)
1. Read the relevant files under `configs/home-lab/`.
2. Test small router changes on a single router VM by pasting in `configure` and `commit`.
3. If changing VM/NIC mapping or deployment behavior, update the two home-lab scripts and run a disposable test deploy.
4. Keep `README.md` and `docs/Runbook.md` aligned with script behavior.

If uncertain, ask the maintainers for:
- Which external Hyper-V switch to use for `router-center`.
- Any planned IP plan changes for node manifests or router static routes.

Done: create/update this file and run through the Runbook checks when making network or VM mapping changes.

If anything here is unclear or you want more/less detail (examples, links to specific config lines), tell me which areas to expand.
