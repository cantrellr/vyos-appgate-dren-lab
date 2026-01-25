# Copilot instructions — vyos-appgate-dren-lab

This file contains concise, actionable guidance for AI coding agents working in this repository.

Purpose
- Help a coding agent be immediately productive: understand the topology, deployment workflows, key files, and project-specific patterns.

Big picture (what to know first)
- This repo builds a deployable Hyper‑V lab of 11 VyOS routers (Azure + On‑prem) and a DREN transit. See `README.md` and `docs/System-Design.md` for diagrams and intent.
- Configs are plain VyOS `set ...` commands under `configs/azure/` and `configs/onprem/`. They are paste‑ready (not templated).
- Network ordering and NIC semantics are important: `scripts/deploy-hyperv-lab.ps1` attaches NICs deterministically; eth0 is OOB/DHCP, eth1..N follow switch lists. Use those scripts as the source of truth for VM/NIC mapping.

Critical developer workflows (explicit commands)
- Create switches (Windows/Hyper‑V host, admin PowerShell):
  - `.
    scripts\create-hyperv-switches.ps1` (see optional `-UseExternalAdapters` flags in `docs/Runbook.md`).
- Deploy lab VMs (as Admin PowerShell):
  - `.
    scripts\deploy-hyperv-lab.ps1 -RepoRoot (Get-Location)`
- Tear down:
  - `.
    scripts\remove-hyperv-lab.ps1`
- Apply router configs: connect to a VyOS VM, `configure`, paste the `configs/*.vyos` contents or `load /config/config.boot`, then `commit`/`save`.
- Validate: follow `docs/Validation-Checklist.md` and `docs/Runbook.md` (interfaces, DREN rules, AZ‑WAN closed tests).

Project-specific conventions and patterns
- Firewall posture: default = allow. Two explicit exceptions are enforced in configs:
  - DREN restriction (only ICMP, TCP/443, UDP/443, UDP/53) — see `configs/azure/edge.vyos` and `configs/onprem/edge.vyos`.
  - AZ‑WAN closed — see `configs/azure/external.vyos`.
- Config file style: files in `configs/` are lists of VyOS `set` commands (no templating). When changing behavior, update these files and test by pasting into a running VyOS instance.
- Shared firewall groups live under `configs/common/firewall-groups.vyos` — prefer referencing shared groups rather than duplicating lists.
- Image and build automation: `vyos-vm-images/` contains image-related manifests and `roles/` are Ansible roles used for image build pipelines. If modifying build logic, inspect `roles/*/tasks` and `vyos-vm-images/*`.

Integration points & external dependencies
- Hyper‑V host (Windows) and PowerShell (Admin) are required to deploy the lab.
- VyOS VHDX/ISO images are consumed in `vyos-vm-images/` and by `scripts/deploy-hyperv-lab.ps1`.
- AppGate SDP and DREN are logical dependencies in the topology — tests assume those services or simulated listeners for port/traffic validation.

Where to look for examples
- Topology and intent: `docs/System-Design.md`, `docs/Topology.mmd`.
- Deployment runbook: `docs/Runbook.md`.
- Router configs (authoritative): `configs/azure/*.vyos`, `configs/onprem/*.vyos`, `configs/common/firewall-groups.vyos`.
- Automation scripts: `scripts/create-hyperv-switches.ps1`, `scripts/deploy-hyperv-lab.ps1`, `scripts/remove-hyperv-lab.ps1`.

How to make safe edits (recommended steps)
1. Read the relevant `configs/*.vyos` to understand existing rules.
2. Test small edits on a single VyOS VM by pasting into `configure` and `commit`.
3. If changing VM/NIC mappings or deployment, update `scripts/deploy-hyperv-lab.ps1` and test deploy on a disposable host.
4. Update `docs/Validation-Checklist.md` with any new validation steps you introduce.

If uncertain, ask the maintainers for:
- Which local adapters to bind when using `-UseExternalAdapters`.
- Any planned topology changes that would affect NIC ordering or IP plan.

Done: create/update this file and run through the Runbook validation when making network or firewall changes.

If anything here is unclear or you want more/less detail (examples, links to specific config lines), tell me which areas to expand.
