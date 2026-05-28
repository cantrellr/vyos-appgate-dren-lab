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
  - `central-router`
  - `dc1manager-router`
  - `dc2domain-router`
  - `dc3domain-router`
- VM sizing: Generation 2, 1 vCPU, 4 GB startup memory.
- Uplink policy:
  - Only `central-router` attaches to the external switch.
  - `central-router` `eth0` is set to VLAN 9 access mode.

Parameters

- `-VhdPath` (required): Source VyOS VHDX to clone per VM.
- `-SwitchPrefix` (optional, default `vSwitch-`): Prefix used for internal switches.
- `-ExternalSwitchName` (optional, default `cotpa-vlans_vsw`): Existing external Hyper-V switch used by central router.
- `-ExternalVlanId` (optional, default `9`): VLAN ID applied to `central-router` `eth0`.

Usage

```powershell
.\scripts\create-vyos-routers.ps1 -VhdPath "C:\images\vyos.vhdx" -ExternalSwitchName "cotpa-vlans_vsw" -ExternalVlanId 9
```

Notes

- The external switch must already exist.
- The script is idempotent for switches and skips VMs that already exist.
- VM files are created under `configs\nodes\vyos\<vm-name>`.
