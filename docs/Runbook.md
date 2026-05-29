# Runbook - Home-Lab Multicluster

Related architecture reference: `docs/System-Design.md`.

## Prerequisites

- Windows host with Hyper-V enabled
- Elevated PowerShell session
- VyOS VHDX for routers
- Linux VHDX for Kubernetes nodes
- External Hyper-V switch already present: `cotpa-vlans_vsw`

## 1) Create routers and vSwitches

```powershell
.\scripts\create-vyos-routers.ps1 -ExternalSwitchName "cotpa-vlans_vsw" -ExternalVlanId 9
```

Expected result:

- Routers created: `router-center`, `router-dc1`, `router-dc2`, `router-dc3`
- Router disks cloned to: `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<router-name>\<router-name>.vhdx`
- Site switches created as internal (`vSwitch-dcX-kubes`, `-storage`, `-domain`, `-seg1`)
- Transit switch created as internal (`vSwitch-transit`)
- Only `router-center` has external uplink and VLAN 9 on `eth0`

## 2) Create cluster node VMs

```powershell
.\scripts\create-multicluster-vms.ps1 -VhdPath "C:\images\ubuntu-server.vhdx"
```

Expected result:

- 12 node VMs total
- Per cluster: 1 controller + 2 workers
- Per node: 1 vCPU, 4 GB RAM, 4 NICs (`eth0`..`eth3`)
- Node disks cloned to: `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<node-name>\<node-name>.vhdx`

## 3) Apply configs/manifests

- Router config fragments: `configs/home-lab/routers/`
- Node manifests: `configs/home-lab/nodes/`

## 4) Quick verification

```powershell
Get-VMSwitch | Where-Object Name -like 'vSwitch-*' | Sort-Object Name
Get-VM -Name router-center,router-dc1,router-dc2,router-dc3 | Select-Object Name,State
Get-VM -Name dc1manager-ctrl01,dc1manager-work01,dc1manager-work02 | Select-Object Name,State
```
