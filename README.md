# VyOS Home-Lab Multicluster

This repository is now scoped to a Hyper-V home-lab with:

- One central router: `router-center`
- Three site routers: `router-dc1`, `router-dc2`, `router-dc3`
- Four Kubernetes clusters (`dc1manager`, `dc1domain`, `dc2domain`, `dc3domain`)
- Per-cluster node layout: 1 controller + 2 workers

## Key paths

- Node manifests: `configs/home-lab/nodes/`
- Router configs: `configs/home-lab/routers/`
- Router provisioning: `scripts/create-vyos-routers.ps1`
- Node VM provisioning: `scripts/create-multicluster-vms.ps1`
- Runbook: `docs/Runbook.md`
- System design: `docs/System-Design.md`
- Diagrams:
  - `diagrams/Architecture-Overview.mmd` (overview)
  - `diagrams/Clusters-and-Workloads.mmd` (systems view)
  - `diagrams/Network-Topology.mmd` (detail view)
  - `diagrams/System-Design.mmd` (cross-domain control and traffic summary)

## Diagram reading order

1. `diagrams/Architecture-Overview.mmd`
2. `diagrams/Clusters-and-Workloads.mmd`
3. `diagrams/Network-Topology.mmd`

## Diagram guide

What they are:

- `diagrams/Architecture-Overview.mmd`: Component-complete overview of sites, routers, transit fabric, Internet egress, workloads, and shared services.
- `diagrams/Clusters-and-Workloads.mmd`: 1-foot engineering systems view with node hostnames, interface/IP mapping, and workload/service relationships.
- `diagrams/Network-Topology.mmd`: Hyper-V network wiring and routing detail view, including switch/subnet design and central transit path.
- `diagrams/System-Design.mmd`: Cross-domain control/traffic summary for fast understanding of control, app, and egress paths.

What they do:

- Provide progressive detail from architecture to systems to network implementation.
- Make routing intent and VLAN 9 egress behavior explicit.
- Link architecture directly to source-of-truth manifests and automation scripts.

How it all works:

1. Start with `Architecture-Overview.mmd` to understand major building blocks and service mesh overlay.
2. Move to `Clusters-and-Workloads.mmd` to inspect cluster-level behavior, node roles, and NIC/IP assignments.
3. Use `Network-Topology.mmd` for Hyper-V switch and router path troubleshooting.
4. Use `System-Design.mmd` as a quick cross-domain mental model when operating or reviewing the lab.

## Hyper-V workflow

1. Create/ensure routers and required vSwitches:

```powershell
.\scripts\create-vyos-routers.ps1 -ExternalSwitchName "cotpa-vlans_vsw" -ExternalVlanId 9
```

1. Create node VMs:

```powershell
.\scripts\create-multicluster-vms.ps1 -VhdPath "C:\images\ubuntu-server.vhdx"
```

## Notes

- `router-center` is the only router with external uplink (`cotpa-vlans_vsw`, VLAN 9).
- Site and transit switches are internal.
- Router default sizing is 1 vCPU and 256 MB RAM.
- `scripts/create-vyos-routers.ps1` creates a per-router NoCloud seed ISO from `configs/home-lab/routers/*.vyos`, attaches it as a DVD drive, boots from hard drive, and disables automatic checkpoints.
- The seed ISO contains `user-data`, empty `meta-data`, and a minimal `network-config` so VyOS cloud-init can apply router config on first boot.
- Router VMs disable secure boot so VyOS can boot; node VMs keep secure boot enabled with the Microsoft UEFI Certificate Authority template (`MicrosoftUEFICertificateAuthority`).
- Router VHDX clones default to `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<router-name>\<router-name>.vhdx`.
- Node VHDX clones default to `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<node-name>\<node-name>.vhdx`.
- Node default sizing is 1 vCPU and 4 GB RAM.
