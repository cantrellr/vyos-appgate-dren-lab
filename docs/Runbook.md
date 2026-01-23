# Runbook: Build, Validate, Troubleshoot

## 1) Before you touch anything
- Confirm Hyper-V NIC mapping (MACs) and set `hw-id` in each config.
- **eth0 is MGMT** for every router: DHCP from Hyper-V **Default Switch**. Ensure this switch exists.
- Confirm the DREN addressing between Outside routers (100.255.0.0/24, Azure .1 / On-Prem .2).
- Decide whether On-Prem External (202.254.0.0/24) is used; it is optional.

## 1.1) One-command Hyper-V build
Prerequisites:
- Hyper-V PowerShell module
- ISO tool: Windows ADK (`oscdimg.exe`) or `mkisofs` / `genisoimage`

Command:
```powershell
powershell .\scripts\deploy-hyperv-lab.ps1
```

Optional overrides:
```powershell
powershell .\scripts\deploy-hyperv-lab.ps1 -MemoryStartupBytes 1GB -CpuCount 1 -RebuildConfigIsos -ReattachDvds
```

Notes:
- VM NIC 0 = MGMT (DHCP) on Hyper-V Default Switch.
- NIC order in configs starts at `eth1` for data plane.

## 1.2) Generate `hw-id` snippets
```powershell
powershell .\scripts\export-vyos-hwids.ps1 -OutputPath .\artifacts\vyos-hwids.txt
```

## 2) Apply order (recommended)
Azure:
1. External
2. Outside
3. Grey
4. Inside
5. Developer
6. Sandbox

On-Prem:
1. Outside
2. Grey
3. Inside
4. Developer
5. Sandbox

## 3) Validation commands (VyOS)
### Interfaces + routes
```bash
show interfaces
show ip route
```

### Firewall hit counts
```bash
show firewall ipv4 name <RULESET>
```

## 4) Traffic tests (must-pass)
Site-local (Azure):
- From AZ SDPC (201.0.1.0/24): reach AZ SDPG (201.0.2.0/24) and AZ SDPT (201.0.3.0/24) on TCP 443/444.
- From AZ SDPG/SDPT: reach AZ protected subnets (201.1.0.0/24, 201.1.1.0/24, 201.1.2.0/24, 201.1.3.0/24, 201.1.4.0/24) on approved ports only.
- From AZ AVD (201.0.4.0/24): reach local gateways on TCP 443 / UDP 443 / UDP 53 and AZ SDPC on TCP 443 (optionally UDP 443/53).

Site-local (On-Prem):
- From ONP SDPC (202.0.1.0/24): reach ONP SDPG (202.0.2.0/24) and ONP SDPT (202.0.3.0/24) on TCP 443/444.
- From ONP SDPG/SDPT: reach ONP protected subnets (202.1.0.0/24, 202.1.1.0/24, 202.1.2.0/24, 202.1.3.0/24, 202.1.4.0/24, 202.1.5.0/24 for HWIL) on approved ports only.
- From ONP AVD (202.0.4.0/24): reach local gateways on TCP 443 / UDP 443 / UDP 53 and ONP SDPC on TCP 443 (optionally UDP 443/53).

Cross-site / DREN constraints:
- Azure ↔ On-Prem prefixes should be unreachable (no inter-site routes).
- DREN interfaces should only pass ICMP, TCP 443, UDP 443, UDP 53.

Negative tests:
- SDPG ↔ SDPT should fail (both sites).
- HWIL should only reach SEG (On-Prem).

## 5) Common failure modes
- Asymmetric routing: ensure both sides have routes for remote prefixes and that Grey points to Outside via DREN.
- Internet egress blocked: confirm az-out WAN firewall only allows the DOMAIN pools (NAT happens upstream on 10.255.255.0/24).
- MTU/MSS: if you see intermittent TLS issues, clamp MSS on the DREN link.

## 6) Cleanup
Remove lab VMs and switches:
```powershell
powershell .\scripts\remove-hyperv-lab.ps1
```

