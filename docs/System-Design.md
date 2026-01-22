# System Design: VyOS + Appgate SDP + DREN (Azure + On-Prem)

## 1. Executive summary
This lab implements a **two-site segmented network** (Azure + On-Prem) with a dedicated **DREN** interconnect. The network is built to support an **Appgate SDP** pattern where:
- **SDPC** subnets host Appgate **Controllers**.
- **SDPG** and **SDPT** subnets host Appgate **Gateways**.
- **AVD** subnets host AVD clients where Appgate clients/agents run.
- **Inside / Developer / Sandbox(SEG)** subnets host **protected resources**.

The design goal is to:
- Allow only the flows required for Appgate to function.
- Explicitly prevent **Gateway-to-Gateway** east/west traffic (SDPG ↔ SDPT).
- Enable cross-site access strictly for approved paths.
- Restrict internet egress so **only the DOMAIN pool IP ranges** can reach the WAN.

## 2. Source of truth
Network ranges are based on the attached spreadsheet `Work Lab Environment.xlsx` (single sheet).

## 3. Network topology
### 3.1 Site roles
- **External (Azure only)**: upstream/WAN segment for BYOD reachability and/or egress simulation.
- **Outside**: DREN edge. Provides upstream default routing. In Azure, Outside has three interfaces (**WAN**, **AZ-OUT** to Grey, and **DREN**) and can provide NAT/egress toward External.
- **Grey**: distribution router for site internal segments (SDPC/SDPG/SDPT/AVD) and the policy enforcement point for intra-site and inter-site traffic.
- **Inside / Developer**: downstream routers that host protected subnets.
- **Sandbox**: downstream router hosting `SEG` and optional `HWIL` (On-Prem only). Enforces **HWIL → SEG only**.

### 3.2 Diagrams
See:
- `diagrams/topology.mmd`
- `diagrams/appgate-flows.mmd`

## 4. Addressing plan
### 4.1 Azure (PROTON)
| Zone | Subnet | Gateway |
|---|---:|---:|
| WAN (External) | 223.223.1.0/24 | 223.223.1.1 |
| AZ-EXT (Internet) | 10.255.255.0/24 | 10.255.255.1 |
| DREN | 222.222.1.0/24 | 222.222.1.1 (Outside) |
| AZ-OUT | 222.222.10.0/24 | 222.222.10.1 (Outside) |
| SDPC | 10.0.0.0/24 | 10.0.0.1 (Grey) |
| SDPG | 10.0.1.0/24 | 10.0.1.1 (Grey) |
| SDPT | 10.0.2.0/24 | 10.0.2.1 (Grey) |
| AVD | 10.0.3.0/24 | 10.0.3.1 (Grey) |
| DOMAIN | 10.1.0.0/24 | 10.1.0.1 (Inside) |
| DOMSVC | 10.1.1.0/24 | 10.1.1.1 (Inside) |
| DEV | 10.2.0.0/24 | 10.2.0.1 (Developer) |
| DEVSVC | 10.2.1.0/24 | 10.2.1.1 (Developer) |
| SEG | 10.3.0.0/24 | 10.3.0.1 (Sandbox) |

### 4.2 On-Prem (RCDN-U)
| Zone | Subnet | Gateway |
|---|---:|---:|
| WAN (External, optional) | 223.223.2.0/24 | 223.223.2.1 |
| DREN | 222.222.1.0/24 | 222.222.1.2 (Outside) |
| ONP-OUT | 222.222.20.0/24 | 222.222.20.1 (Outside) |
| SDPC | 20.0.0.0/24 | 20.0.0.1 (Grey) |
| SDPG | 20.0.1.0/24 | 20.0.1.1 (Grey) |
| SDPT | 20.0.2.0/24 | 20.0.2.1 (Grey) |
| AVD | 20.0.3.0/24 | 20.0.3.1 (Grey) |
| DOMAIN | 20.1.0.0/24 | 20.1.0.1 (Inside) |
| DOMSVC | 20.1.1.0/24 | 20.1.1.1 (Inside) |
| DEV | 20.2.0.0/24 | 20.2.0.1 (Developer) |
| DEVSVC | 20.2.1.0/24 | 20.2.1.1 (Developer) |
| SEG | 20.3.0.0/24 | 20.3.0.1 (Sandbox) |
| HWIL | 20.3.1.0/24 | 20.3.1.1 (Sandbox) |

## 5. Key design assumptions (must validate)
### 5.1 Router-to-router transit IPs (not in the spreadsheet)
The spreadsheet does not define the uplink IPs from downstream routers into the SDPC subnet. This design allocates:
- Azure SDPC uplinks:
  - Inside uplink: `10.0.0.2/24`
  - Developer uplink: `10.0.0.3/24`
  - Sandbox uplink: `10.0.0.4/24`
- On-Prem SDPC uplinks:
  - Inside uplink: `20.0.0.2/24`
  - Developer uplink: `20.0.0.3/24`
  - Sandbox uplink: `20.0.0.4/24`

### 5.2 Cross-site transit
Outside routers exchange routes over the DREN interconnect.

## 6. Routing architecture
### 6.1 Inside the site
- Grey is the default gateway for SDPC/SDPG/SDPT/AVD.
- Inside/Developer/Sandbox default route points to Grey SDPC IP.

### 6.2 Cross-site
- Grey forwards remote-site traffic to its local **Outside** via DREN.
- Outside routers route remote-site prefixes over DREN.

## 7. Security policy model
### 7.1 High-level traffic matrix
**SDPG ↔ SDPT**: **DENY** (no requirement).

**SDPC (Controllers)** needs access to Gateways (both sites):
- SDPC → SDPG/SDPT: allow Appgate control plane ports.

**AVD clients** need access to local gateways:
- AVD → SDPG/SDPT: allow Appgate client tunnel ports.

**AVD clients** also need access to Controllers (SDPC):
- AVD → SDPC: allow Appgate client/control-plane ports used for enrollment/auth and policy updates.

**Gateways** must proxy to protected resources (both sites):
- SDPG/SDPT → Inside/Developer/Sandbox(SEG): allow least-privilege protected ports.

### 7.2 Allowed port sets
**Appgate client-to-gateway (baseline):**
- TCP 443
- UDP 443
- UDP 53

**Appgate client-to-controller (baseline):**
- TCP 443
- (Optional, depending on your Appgate build/feature use) UDP 443, UDP 53

**Controller-to-gateway (baseline):**
- TCP 443
- TCP 444 (include during validation; remove if your build does not require it)

**Protected resource ports (proxy traffic):**
- SSH: TCP 22
- Web: TCP 80, 443
- RDP: TCP 3389 (optional UDP 3389)
- SMB: TCP 445
- DB: TCP 1433, 1521, 3306, 5432, 27017

### 7.4 Internet egress policy
- Only the **DOMAIN pool** ranges are allowed to egress to the WAN:
  - Azure: `10.1.0.21-10.1.0.29`
  - On-Prem: `20.1.0.21-20.1.0.29`
- **az-out** enforces this restriction with a WAN firewall policy; NAT occurs upstream on the `10.255.255.0/24` network.

### 7.3 Policy enforcement points
- **Grey routers** enforce all inter-zone and inter-site policy (zone firewall).
- **Sandbox routers** enforce:
  - HWIL → SEG only
  - SEG egress constraints (optional; keep minimal to avoid breaking repo updates)

## 8. Operational best practices
### 8.1 VyOS config management
- Use `load merge` with a candidate config, then `commit-confirm`.
- Keep a rollback plan: `show system commit` and `rollback <n>`.
- Centralize logs and enable audit where feasible.

### 8.2 DREN best practices
- Pin MTU/MSS if you see fragmentation.
- Monitor DREN reachability with periodic pings and log events.

### 8.3 Hyper-V NIC stability
- Map interfaces by MAC using `hw-id` to prevent renumbering.

## 9. Files to apply
- Azure:
  - `configs/azure/external.vyos`
  - `configs/azure/outside.vyos`
  - `configs/azure/grey.vyos`
  - `configs/azure/inside.vyos`
  - `configs/azure/developer.vyos`
  - `configs/azure/sandbox.vyos`
- On-Prem:
  - `configs/onprem/outside.vyos`
  - `configs/onprem/grey.vyos`
  - `configs/onprem/inside.vyos`
  - `configs/onprem/developer.vyos`
  - `configs/onprem/sandbox.vyos`

