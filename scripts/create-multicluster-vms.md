# create-multicluster-vms.ps1 - Technical README

- **Location:** scripts/create-multicluster-vms.ps1
- **Purpose:** Create home-lab multicluster node VMs for dc1/dc2/dc3 using a provided base OS VHDX.

Behavior summary

- Creates 12 node VMs:
  - `dc1manager-ctrl01`, `dc1manager-work01`, `dc1manager-work02`
  - `dc1domain-ctrl01`, `dc1domain-work01`, `dc1domain-work02`
  - `dc2domain-ctrl01`, `dc2domain-work01`, `dc2domain-work02`
  - `dc3domain-ctrl01`, `dc3domain-work01`, `dc3domain-work02`
- VM sizing for each node:
  - Generation 2
  - 1 vCPU
  - 4 GB startup memory
  - 4 NICs (`eth0..eth3`)
- Secure boot:
  - Enabled with the Microsoft UEFI Certificate Authority template (`MicrosoftUEFICertificateAuthority`).
- NIC mapping per node:
  - `eth0 -> vSwitch-<site>-kubes`
  - `eth1 -> vSwitch-<site>-storage`
  - `eth2 -> vSwitch-<site>-domain`
  - `eth3 -> vSwitch-<site>-seg1`

Parameters

- `-VhdPath` (required): Base OS VHDX to copy for each VM.
- `-VirtualDiskRoot` (optional): Parent folder for per-node cloned VHDX files. Default: `D:\Production_Data\HyperV\Virtual Hard Disks\K8S`.
- `-SwitchPrefix` (optional, default `vSwitch-`): Prefix for switch names.

Usage

```powershell
.\scripts\create-multicluster-vms.ps1 -VhdPath "C:\images\ubuntu-server.vhdx"
```

Notes

- Script expects vSwitches to exist before VM creation.
- VM files are created under `configs\home-lab\vms\nodes\<vm-name>`.
- Node VHDX clones are created at `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<vm-name>\<vm-name>.vhdx` by default.
- Existing VMs are skipped.

Diagram integration

What it is:

- Node provisioning script that materializes the cluster/node layer represented in the systems and topology diagrams.

What it does in the diagrams:

- Creates the node inventory shown in `diagrams/Clusters-and-Workloads.mmd`.
- Populates the site switch segments and node-group expectations used by `diagrams/Network-Topology.mmd`.
- Implements the cluster layout assumed by `diagrams/Architecture-Overview.mmd` and `diagrams/System-Design.mmd`.

How it works with the full design:

1. Consumes the switch fabric built by `create-vyos-routers.ps1`.
2. Creates all 12 node VMs with deterministic `eth0..eth3` mapping.
3. Clones per-node disks under the K8S VHDX root path.
4. Produces the VM layer that receives node YAML manifests from `configs/home-lab/nodes/`.
