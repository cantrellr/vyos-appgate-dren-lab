# Runbook: Build, Validate, Troubleshoot

## 1) Before you touch anything
- Confirm Hyper-V NIC mapping (MACs) and set `hw-id` in each config.
- Confirm the DREN addressing between Outside routers.
- Decide whether On-Prem External/WAN exists (optional).

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
From AZ SDPC subnet (10.0.0.0/24):
- Reach AZ SDPG (10.0.1.0/24) and AZ SDPT (10.0.2.0/24) on TCP 443/444
- Reach ONP SDPG (20.0.1.0/24) and ONP SDPT (20.0.2.0/24) on TCP 443/444

From AZ SDPG/SDPT:
- Reach AZ protected subnets (10.1.0.0/24, 10.1.1.0/24, 10.2.0.0/24, 10.2.1.0/24, 10.3.0.0/24) on protected ports only
- Reach ONP protected subnets (20.1.0.0/24, 20.1.1.0/24, 20.2.0.0/24, 20.2.1.0/24, 20.3.0.0/24) on protected ports only

From AVD subnet:
- Reach local gateways on TCP 443, UDP 443, UDP 53
- Reach SDPC (Controllers) on TCP 443 (and optionally UDP 443/53 if enabled)

Negative tests:
- SDPG ↔ SDPT should fail
- HWIL should only reach SEG (On-Prem)
- Any host **outside** the DOMAIN pool ranges should **fail** to reach the Internet

## 5) Common failure modes
- Asymmetric routing: ensure both sides have routes for remote prefixes and that Grey points to Outside via DREN.
- Internet egress blocked: confirm az-out WAN firewall only allows the DOMAIN pools (NAT happens upstream on 10.255.255.0/24).
- MTU/MSS: if you see intermittent TLS issues, clamp MSS on the DREN link.

## 6) Cleanup
Remove lab VMs and switches:
```powershell
powershell .\scripts\remove-hyperv-lab.ps1
```

