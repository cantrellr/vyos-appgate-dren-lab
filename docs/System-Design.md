# System Design: VyOS + Appgate SDP + DREN (Azure + On-Prem)

## 1. Executive summary
This lab implements a **two-site segmented network** (Azure + On-Prem) with a dedicated **DREN** interconnect. The network is built to support an **Appgate SDP** pattern where:
- **SDPC** subnets host Appgate **Controllers**.
- **SDPG** and **SDPT** subnets host Appgate **Gateways**.
- **AVD** subnets host AVD clients where Appgate clients/agents run.
- **Inside / Developer / Sandbox (SEG)** subnets host **protected resources**.

The design goal is to:
- Keep all traffic **site-local** (Azure isolated from On-Prem) while retaining a DREN underlay for future use.
- Allow only the flows required inside each site for Appgate to function.
- Explicitly prevent **Gateway-to-Gateway** east/west traffic (SDPG ↔ SDPT).
- Restrict DREN to ICMP / TCP 443 / UDP 443 / UDP 53 only.
- Run with **no NAT**, simplifying traceability.
- Reserve `eth0` on every router for **management only** (DHCP via Hyper-V Default Switch) and bind management services to it; data-plane starts at `eth1`.

## 2. Source of truth
Network ranges are captured in `docs/addressing.csv` (single sheet, also mirrored in `docs/Network Description.txt`).

## 3. Network topology
### 3.1 Site roles
- **External (Azure only)**: upstream/WAN segment for BYOD reachability and/or egress simulation.
- **Outside**: DREN edge. Provides upstream default routing. Azure Outside has WAN + DREN + OUT. On-Prem Outside has DREN + OUT + EXT.
- **Grey**: distribution router for site internal segments (SDPC/SDPG/SDPT/AVD) and the policy enforcement point for intra-site traffic (cross-site is intentionally absent).
- **Inside / Developer**: downstream routers that host protected subnets.
- **Sandbox**: downstream router hosting `SEG` and optional `HWIL` (On-Prem only). Enforces **HWIL → SEG only**.

### 3.2 Diagrams
See (data-plane only; `eth0` mgmt not shown):
- `diagrams/topology.mmd`
- `diagrams/appgate-flows.mmd`
- `diagrams/routing-topology.mmd`

## 4. Addressing plan
### 4.1 Azure (PROTON)
| Zone | Subnet | Gateway | Note |
|---|---:|---:|---|
| MGMT | DHCP | DHCP | Hyper-V Default Switch (eth0 on all nodes) |
| WAN | 201.255.0.0/24 | 201.255.0.1 | az-out eth1 |
| EXT | 201.254.0.0/24 | 201.254.0.1 | az-ext eth1 |
| DREN | 100.255.0.0/24 | 100.255.0.1 (Outside) | az-out eth2 |
| OUT | 201.0.0.0/24 | 201.0.0.1 (Outside) | az-out eth3 ↔ az-grey eth1 |
| SDPC | 201.0.1.0/24 | 201.0.1.1 (Grey) | az-grey eth2 |
| SDPG | 201.0.2.0/24 | 201.0.2.1 (Grey) | az-grey eth3 |
| SDPT | 201.0.3.0/24 | 201.0.3.1 (Grey) | az-grey eth4 |
| AVD | 201.0.4.0/24 | 201.0.4.1 (Grey) | az-grey eth5 |
| DOMAIN | 201.1.0.0/24 | 201.1.0.1 (Inside) | az-inside eth2 |
| DOMSVC | 201.1.1.0/24 | 201.1.1.1 (Inside) | az-inside eth3 |
| DEV | 201.1.2.0/24 | 201.1.2.1 (Developer) | az-dev eth2 |
| DEVSVC | 201.1.3.0/24 | 201.1.3.1 (Developer) | az-dev eth3 |
| SEG | 201.1.4.0/24 | 201.1.4.1 (Sandbox) | az-sandbox eth2 |

### 4.2 On-Prem (RCDN-U)
| Zone | Subnet | Gateway | Note |
|---|---:|---:|---|
| MGMT | DHCP | DHCP | Hyper-V Default Switch (eth0 on all nodes) |
| WAN | N/A | N/A | Not used in lab |
| EXT | 202.254.0.0/24 | 202.254.0.1 (External) | onp-out eth3 |
| DREN | 100.255.0.0/24 | 100.255.0.2 (Outside) | onp-out eth2 |
| OUT | 202.0.0.0/24 | 202.0.0.1 (Outside) | onp-out eth1 ↔ onp-grey eth1 |
| SDPC | 202.0.1.0/24 | 202.0.1.1 (Grey) | onp-grey eth2 |
| SDPG | 202.0.2.0/24 | 202.0.2.1 (Grey) | onp-grey eth3 |
| SDPT | 202.0.3.0/24 | 202.0.3.1 (Grey) | onp-grey eth4 |
| AVD | 202.0.4.0/24 | 202.0.4.1 (Grey) | onp-grey eth5 |
| DOMAIN | 202.1.0.0/24 | 202.1.0.1 (Inside) | onp-inside eth2 |
| DOMSVC | 202.1.1.0/24 | 202.1.1.1 (Inside) | onp-inside eth3 |
| DEV | 202.1.2.0/24 | 202.1.2.1 (Developer) | onp-dev eth2 |
| DEVSVC | 202.1.3.0/24 | 202.1.3.1 (Developer) | onp-dev eth3 |
| SEG | 202.1.4.0/24 | 202.1.4.1 (Sandbox) | onp-sandbox eth2 |
| HWIL | 202.1.5.0/24 | 202.1.5.1 (Sandbox) | onp-sandbox eth3 |

## 5. Key design assumptions (must validate)
### 5.1 Router-to-router transit IPs (not in the spreadsheet)
Downstream uplinks into SDPC are allocated as:
- Azure SDPC uplinks: `201.0.1.2/24` (Inside), `201.0.1.3/24` (Developer), `201.0.1.4/24` (Sandbox)
- On-Prem SDPC uplinks: `202.0.1.2/24` (Inside), `202.0.1.3/24` (Developer), `202.0.1.4/24` (Sandbox)

### 5.2 Cross-site transit
Cross-site routing is **deliberately absent**. DREN exists only for restricted testing (ICMP/443 TCP+UDP/53 UDP) and does not carry inter-site prefixes.

## 6. Routing architecture
### 6.1 Inside the site
- Grey is the default gateway for SDPC/SDPG/SDPT/AVD.
- Inside/Developer/Sandbox default route points to Grey SDPC IP.

### 6.2 Cross-site
- No remote-site routes are installed. Azure and On-Prem are isolated by design. DREN remains for tightly constrained diagnostics only.

### 6.3 Management
- `eth0` on every node is MGMT via Hyper-V Default Switch (DHCP).
- SSH/HTTPS are permitted only on MGMT; data-plane interfaces drop those ports via `LOCAL-DROP-MGMT`.

## 7. Security policy model
### 7.1 High-level traffic matrix
**SDPG ↔ SDPT**: **DENY** (no requirement).

**SDPC (Controllers)** needs access to local Gateways:
- SDPC → SDPG/SDPT: allow Appgate control plane ports.

**AVD clients** need access to local Gateways:
- AVD → SDPG/SDPT: allow Appgate client tunnel ports.

**AVD clients** also need access to Controllers (SDPC):
- AVD → SDPC: allow Appgate client/control-plane ports used for enrollment/auth and policy updates.

**Gateways** must proxy to protected resources (local site only):
- SDPG/SDPT → Inside/Developer/Sandbox (SEG): allow least-privilege protected ports.

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
- Only the **DOMAIN pool** ranges are intended to egress to the WAN (adjust pools as needed in DHCP/AAA):
  - Azure: `201.1.0.21-201.1.0.29`
  - On-Prem: `202.1.0.21-202.1.0.29`
- No NAT is configured in this lab; egress shaping (if used) must be done upstream of the lab.

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

