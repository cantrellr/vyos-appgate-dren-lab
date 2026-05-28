# Runbook — Hyper‑V Deployment + Validation

## 0) Prereqs
- Windows host with **Hyper‑V** enabled
- PowerShell running **as Administrator**
- VyOS Universal Router v1.4.4 VHDX template (recommended) or ISO

## 1) Create vSwitches
From repo root:

```powershell
.\scripts\create-hyperv-switches.ps1
```

Optional: create external switches bound to real NICs:

```powershell
.\scripts\create-hyperv-switches.ps1 -UseExternalAdapters `
  -AzureExternalAdapterName "<YOUR AZURE NIC>" `
  -OnPremUnderlayAdapterName "<YOUR ONPREM NIC>"
```

## 2) Deploy the lab VMs
```powershell
.\scripts\deploy-hyperv-lab.ps1 -RepoRoot (Get-Location)
```

This deploys **11 VMs**:
- vyos-az-external / edge / core / inside / developer / segment1
- vyos-onp-edge / core / inside / developer / segment1

NIC order is deterministic:
- eth0 is always **Default Switch** (VYOS-OOB / DHCP)
- eth1..ethN follow the switch list per VM definition in the script.
 - eth0 is always **Default Switch** (VYOS-OOB). In this lab the `configs/*.vyos` files set static OOB addresses (10.255.255.x) for each router.
 - eth1..ethN follow the switch list per VM definition in the script.

## 3) Apply configs
Each config under `configs/**` is a list of VyOS `set ...` commands.

From VyOS:
```bash
configure
load /config/config.boot
# OR paste the set-commands, then:
commit
save
exit
```

## 4) Sanity checks (minimum viable confidence)

### A) Interfaces up
On each router:
```bash
show interfaces
show ip route
```

### B) DREN enforcement
From Azure edge (100.255.0.1) to On‑prem edge (100.255.0.2):
- ✅ `ping 100.255.0.2` should work
- ✅ `curl https://100.255.0.2` (or 443 test) should work if something listens
- ✅ DNS tests over UDP/53 if you stand up a resolver
- ❌ random ports (e.g., TCP/22) should fail across DREN

### C) AZ‑WAN closed
On Azure external:
- ❌ pinging or reaching anything on AZ‑WAN should fail (eth1 is drop in/out/local)

## 5) Tear down
```powershell
.\scripts\remove-hyperv-lab.ps1
```

## 6) Home-lab multicluster workflow (dc1/dc2/dc3)

Use this path for the multicluster lab with one central transit router and one site router per site.

1. Ensure the external Hyper-V switch that carries VLAN 9 exists.
Example switch name used by scripts: `cotpa-vlans_vsw`.

1. Create VyOS routers and internal vSwitches:

```powershell
.\scripts\create-vyos-routers.ps1 -VhdPath "C:\images\vyos.vhdx" -ExternalSwitchName "cotpa-vlans_vsw" -ExternalVlanId 9
```

1. Create node VMs (1 CPU, 4 GB RAM, 4 NICs per VM):

```powershell
.\scripts\create-multicluster-vms.ps1 -VhdPath "C:\images\ubuntu-server.vhdx"
```

1. Apply cluster node manifests from:

- `configs/home-lab/nodes/`

Notes:

- Only `central-router` gets the external uplink on VLAN 9.
- Site and transit switches are internal.
---

## Validation

Use `docs/Validation-Checklist.md` to prove routing + firewall behavior (DREN restricted, AZ-WAN closed).

