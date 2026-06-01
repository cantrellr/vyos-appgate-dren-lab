# Runbook - Home-Lab Multicluster

Related architecture reference: `docs/System-Design.md`.

Diagram order for operations context:

1. `diagrams/Architecture-Overview.mmd`
2. `diagrams/Clusters-and-Workloads.mmd`
3. `diagrams/Network-Topology.mmd`

How to use the diagrams during operations:

- `Architecture-Overview.mmd`: Understand what components exist and how traffic/control domains connect.
- `Clusters-and-Workloads.mmd`: Validate what clusters/nodes are expected and how interfaces map to site networks.
- `Network-Topology.mmd`: Troubleshoot specific switch/subnet/router path issues.
- `System-Design.mmd`: Quick cross-domain summary when reviewing control vs data-plane flow.

## Prerequisites

- Windows host with Hyper-V enabled
- Elevated PowerShell session
- VyOS VHDX for routers (cloud-init-capable if you want NoCloud first-boot config application)
- Linux VHDX for Kubernetes nodes
- External Hyper-V switch already present: `cotpa-vlans_vsw`

## 1) Create routers and vSwitches

```powershell
.\scripts\create-vyos-routers.ps1 -ExternalSwitchName "cotpa-vlans_vsw" -ExternalVlanId 9
```

Expected result:

- Routers created: `router-center`, `router-dc1`, `router-dc2`, `router-dc3`
- Router NoCloud seed ISO created for each router and attached as DVD media: `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<router-name>\<router-name>-seed.iso`
- Router disks cloned to: `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<router-name>\<router-name>.vhdx`
- Site switches created as internal (`vSwitch-dcX-kubes`, `-storage`, `-domain`, `-seg1`)
- Transit switch created as internal (`vSwitch-transit`)
- Only `router-center` has the external uplink; VLAN 9 is applied on the Hyper-V adapter, while VyOS keeps `eth0` on DHCP
- Router firmware still boots from hard drive first and automatic checkpoints are disabled.
- Router secure boot is disabled so VyOS can boot; node VMs still use the Microsoft UEFI Certificate Authority template.

## 2) Create cluster node VMs

```powershell
.\scripts\create-multicluster-vms.ps1 -VhdPath "C:\images\ubuntu-server.vhdx"
```

Expected result:

- 12 node VMs total
- Per cluster: 1 controller + 2 workers
- Per node: 1 vCPU, 4 GB RAM, 4 NICs (`eth0`..`eth3`)
- Node disks cloned to: `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<node-name>\<node-name>.vhdx`
- Node secure boot is enabled with the Microsoft UEFI Certificate Authority template.

## 3) Apply configs/manifests

- Router config fragments: `configs/home-lab/routers/`
- The router configs are converted into NoCloud `user-data` and `meta-data` with a unique `instance-id`/`local-hostname` on the fly, packed into a `cidata` seed ISO, and attached as DVD media. VyOS cloud-init applies the matching config automatically on first boot.
- Node manifests: `configs/home-lab/nodes/`

## 4) Quick verification

```powershell
Get-VMSwitch | Where-Object Name -like 'vSwitch-*' | Sort-Object Name
Get-VM -Name router-center,router-dc1,router-dc2,router-dc3 | Select-Object Name,State
Get-VM -Name dc1manager-ctrl01,dc1manager-work01,dc1manager-work02 | Select-Object Name,State
```
