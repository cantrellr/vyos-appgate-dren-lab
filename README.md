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
- Diagrams: `diagrams/Network-Topology.mmd`, `diagrams/System-Design.mmd`

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
- Router VHDX clones default to `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<router-name>\<router-name>.vhdx`.
- Node default sizing is 1 vCPU and 4 GB RAM.
