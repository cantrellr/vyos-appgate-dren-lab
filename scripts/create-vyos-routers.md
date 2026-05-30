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
- Boot policy: hard drive first, automatic checkpoints disabled.
- Secure boot: disabled for VyOS so the router image can boot correctly.
- Uplink policy:
  - Only `router-center` attaches to the external switch.
  - `router-center` `eth0` is set to VLAN 9 access mode.
- Config media:
  - Creates a per-router NoCloud seed ISO from `configs/home-lab/routers/<router-name>.vyos`.
  - The seed ISO contains `user-data`, empty `meta-data`, and a minimal `network-config`.
  - The ISO is labeled `CIDATA` and attached as a DVD drive to the corresponding VM.

Parameters

- `-VhdPath` (optional): Source VyOS VHDX to clone per VM. Default: `D:\Production_Data\HyperV\Hard Disk Templates\vyos-1.4.4-hyperv-amd64.vhdx`.
- The default image is the last known bootable Hyper-V template on this host. If you have a cloud-init-capable VyOS 1.5.x Hyper-V VHDX, pass it explicitly with `-VhdPath`.
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
- Router NoCloud seed ISOs are created at `D:\Production_Data\HyperV\Virtual Hard Disks\K8S\<vm-name>\<vm-name>-seed.iso` by default.

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
3. Builds a per-router NoCloud seed ISO (`user-data`, `meta-data`, `network-config`) from the matching VyOS config fragment and attaches it as DVD media.
4. Applies external uplink behavior to `router-center` (`eth0`, VLAN 9).
5. Forces hard-drive boot order and disables automatic checkpoints so the seed ISO is data/config media only.
6. Provides the network foundation that node VM and manifest layers consume.
