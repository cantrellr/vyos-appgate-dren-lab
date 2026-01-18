# Runbook: Build, Validate, Troubleshoot

## 1) Before you touch anything
- Confirm Hyper-V NIC mapping (MACs) and set `hw-id` in each config.
- Confirm which IPs will be used as the **IPsec underlay** between Outside routers.
- Decide whether On-Prem External/WAN exists (optional).

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

### IPsec + VTI
```bash
show vpn ipsec sa
show vpn ipsec status
show interfaces vti
ping 172.31.255.2
traceroute 20.0.1.11
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

## 5) Common failure modes
- Asymmetric routing: ensure both sides have routes for remote prefixes and that Grey points to Outside via DREN.
- NAT leaking into tunnel: ensure NAT exemptions exist (Azure Outside if you do WAN NAT).
- MTU/MSS: if you see intermittent TLS issues, clamp MSS on VTI.

