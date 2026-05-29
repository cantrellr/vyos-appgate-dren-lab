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

- `-VhdPath` (optional): Source VyOS VHDX to clone per VM. Default: `D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.4.4-hyperv-amd64.vhdx`.
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
