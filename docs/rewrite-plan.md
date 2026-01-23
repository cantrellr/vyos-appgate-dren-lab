# Lab Rewire Plan (No VRFs, New Addressing)

## Goals
- Move entirely to the new 201.x/202.x/100.255.x plan; remove legacy 10/20/222/223 addressing.
- No VRFs anywhere.
- No NAT. Allow all ingress from WAN except to DREN.
- Default allow within a site between non-DREN zones; DREN highly restricted (only ARP/ICMP + TCP/UDP 443 + UDP 53, with SDPG/SDPT self/each-other blocks). No Azure↔On-Prem connectivity.
- Update Hyper-V automation, configs, docs, and diagrams to match.

## Target Addressing (from Network Description)
- **Azure (PROTON)**
  - WAN 201.255.0.0/24 gw 201.255.0.1
  - EXT 201.254.0.0/24 gw 201.254.0.1
  - DREN 100.255.0.0/24 gw 100.255.0.1
  - OUT 201.0.0.0/24 gw 201.0.0.1
  - SDPC 201.0.1.0/24 gw 201.0.1.1
  - SDPG 201.0.2.0/24 gw 201.0.2.1
  - SDPT 201.0.3.0/24 gw 201.0.3.1
  - AVD 201.0.4.0/24 gw 201.0.4.1
  - DOMAIN 201.1.0.0/24 gw 201.1.0.1
  - DOMSVC 201.1.1.0/24 gw 201.1.1.1
  - DEV 201.1.2.0/24 gw 201.1.2.1
  - DEVSVC 201.1.3.0/24 gw 201.1.3.1
  - SEG 201.1.4.0/24 gw 201.1.4.1
- **On-Prem (RCDN-U)**
  - EXT 202.254.0.0/24 gw 202.254.0.1
  - DREN 100.255.0.0/24 gw 100.255.0.2
  - OUT 202.0.0.0/24 gw 202.0.0.1
  - SDPC 202.0.1.0/24 gw 202.0.1.1
  - SDPG 202.0.2.0/24 gw 202.0.2.1
  - SDPT 202.0.3.0/24 gw 202.0.3.1
  - AVD 202.0.4.0/24 gw 202.0.4.1
  - DOMAIN 202.1.0.0/24 gw 202.1.0.1
  - DOMSVC 202.1.1.0/24 gw 202.1.1.1
  - DEV 202.1.2.0/24 gw 202.1.2.1
  - DEVSVC 202.1.3.0/24 gw 202.1.3.1
  - SEG 202.1.4.0/24 gw 202.1.4.1
  - HWIL 202.1.5.0/24 gw 202.1.5.1

## Nodes and Interface Roles (no VRF)
- **Azure**
  - az-ext: EXT (201.254.0.0/24), WAN (201.255.0.0/24); default route via WAN gateway.
  - az-out: WAN (201.255.0.0/24), DREN (100.255.0.0/24 gw .1), OUT (201.0.0.0/24); default via WAN.
  - az-grey: OUT uplink (201.0.0.0/24), SDPC/SDPG/SDPT/AVD per subnets; default via OUT.
  - az-inside: SDPC uplink (201.0.1.0/24), DOMAIN/DOMSVC/DEV/DEVSVC/SEG per subnets.
- **On-Prem**
  - onp-ext: EXT (202.254.0.0/24), optional WAN none; default via EXT or as required.
  - onp-out: DREN (100.255.0.0/24 gw .2), OUT (202.0.0.0/24), EXT (202.254.0.0/24 as needed); default via EXT/OUT per design.
  - onp-grey: OUT uplink (202.0.0.0/24), SDPC/SDPG/SDPT/AVD per subnets; default via OUT.
  - onp-inside: SDPC uplink (202.0.1.0/24), DOMAIN/DOMSVC/DEV/DEVSVC/SEG/HWIL per subnets.

## Routing Policy
- Remove all legacy 10/20/222/223 routes.
- Use default routes on egress nodes (az-ext via WAN; onp-ext via EXT). az-out/onp-out default via WAN/EXT respectively.
- Do not add inter-site (Azure↔On-Prem) reachability; keep sites isolated. Only local site routing is configured.

## Firewall Policy (simplified)
- Non-DREN zones: default allow within the same site (Azure-only or On-Prem-only). Explicitly block Azure↔On-Prem traffic on OUT/EXT as needed.
- DREN zone restrictions remain: allow only ARP, ICMP, TCP 443, UDP 443, and UDP 53 across DREN; block SDPG↔SDPG and SDPG↔SDPT; block SDPT↔SDPT and SDPT↔SDPG; SDPC may talk to SDPG/SDPT using only the allowed ports/protos; drop everything else on DREN.
- WAN ingress: allow all except any destination in DREN.
- No NAT anywhere.

## Config Rewrite Tasks
- Rewrite all VyOS configs in configs/azure and configs/onprem to new addressing and firewall stance; drop VRF files/references.
- Simplify/refresh address/port groups to match the new policy.
- Remove NAT rules; ensure zone-policy bindings match the new allow model and DREN constraints.

## Automation Updates
- Update create-hyperv-switches.ps1, deploy-hyperv-lab.ps1, remove-hyperv-lab.ps1 for new subnets, interface names, and node set (no VRF nodes). No VLAN tagging.

## Docs and Artifacts
- Regenerate: Network Description.txt, System-Design.md, Runbook.md, Work Lab Environment.csv, diagrams (topology, routing) to match the new plan and firewall posture.

## Validation Steps
1) Boot lab with new configs; verify interface IPs and defaults match the plan.
2) Connectivity: within-site non-DREN zones reach each other and WAN; Azure↔On-Prem is blocked; DREN only permits ARP/ICMP/443(TCP+UDP)/53(UDP) with SDPG/SDPT self/each-other blocks enforced.
3) Confirm no NAT rules and no legacy routes/addresses/VRF remnants.
4) Spot-check firewall counters for DREN rules, WAN ingress allow, and Azure↔On-Prem blocks.
