# create-multicluster-vms.ps1 - Technical README

- **Location:** scripts/create-multicluster-vms.ps1
- **Purpose:** Create home-lab multicluster node VMs for dc1/dc2/dc3 using a provided base OS VHDX.

Behavior summary

- Creates 8 node VMs:
  - `dc1manager-ctrl01`, `dc1manager-work01`
  - `dc1domain-ctrl01`, `dc1domain-work01`
  - `dc2domain-ctrl01`, `dc2domain-work01`
  - `dc3domain-ctrl01`, `dc3domain-work01`
- VM sizing for each node:
  - Generation 2
  - 1 vCPU
  - 4 GB startup memory
  - 4 NICs (`eth0..eth3`)
- NIC mapping per node:
  - `eth0 -> vSwitch-<site>-kubes`
  - `eth1 -> vSwitch-<site>-storage`
  - `eth2 -> vSwitch-<site>-domain`
  - `eth3 -> vSwitch-<site>-seg1`

Parameters

- `-VhdPath` (required): Base OS VHDX to copy for each VM.
- `-SwitchPrefix` (optional, default `vSwitch-`): Prefix for switch names.

Usage

```powershell
.\scripts\create-multicluster-vms.ps1 -VhdPath "C:\images\ubuntu-server.vhdx"
```

Notes

- Script expects vSwitches to exist before VM creation.
- VM files are created under `configs\nodes\vms\<vm-name>`.
- Existing VMs are skipped.
