# create-vyos-routers.ps1 - Technical README

- **Location:** scripts/create-vyos-routers.ps1
- **Purpose:** Create the home-lab VyOS router VMs and required Hyper-V switches for dc1/dc2/dc3 multicluster networking.

Behavior summary

- Creates internal site switches for each site:
  - `vSwitch-dcX-kubes`
  - `vSwitch-dcX-storage`
  - `vSwitch-dcX-domain`
  - `vSwitch-dcX-seg1`
- Creates/ensures `vSwitch-transit` as an internal switch.
- Creates four router VMs from a base VHDX:
  - `router-center`
  - `router-dc1`
  - `router-dc2`
  - `router-dc3`
- VM sizing: Generation 2, 1 vCPU, 256 MB startup memory.
- Uplink policy:
  - Only `router-center` attaches to the external switch.
  - `router-center` `eth0` is set to VLAN 9 access mode.

Parameters

- `-VhdPath` (optional): Source VyOS VHDX to clone per VM. Default: `D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.5.0-hyperv-amd64.vhdx`.
- `-VirtualDiskRoot` (optional): Parent folder for per-router cloned VHDX files. Default: `D:\Production_Data\HyperV\Virtual Hard Disks\K8S`.
- `-SwitchPrefix` (optional, default `vSwitch-`): Prefix used for internal switches.
- `-ExternalSwitchName` (optional, default `cotpa-vlans_vsw`): Existing external Hyper-V switch used by central router.
- `-ExternalVlanId` (optional, default `9`): VLAN ID applied to `router-center` `eth0`.

Usage

```powershell
.\scripts\create-vyos-routers.ps1 -ExternalSwitchName "cotpa-vlans_vsw" -ExternalVlanId 9
```

Notes

- The external switch must already exist.
- The script is idempotent for switches and skips VMs that already exist.
- Router VHDX clones are created at `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<vm-name>\<vm-name>.vhdx` by default.

Diagram integration

What it is:

- Router/fabric provisioning script that creates the routing backbone used by all diagrams.

What it does in the diagrams:

- Builds the router components shown in `diagrams/Architecture-Overview.mmd` and `diagrams/System-Design.mmd`.
- Creates the transit and site switch structures represented in `diagrams/Network-Topology.mmd`.
- Enables the control and app cluster connectivity assumptions used in `diagrams/Clusters-and-Workloads.mmd`.

How it works with the full design:

1. Creates/ensures site and transit switches.
2. Creates center/site router VMs and deterministic NIC mapping.
3. Applies external uplink behavior to `router-center` (`eth0`, VLAN 9).
4. Provides the network foundation that node VM and manifest layers consume.
