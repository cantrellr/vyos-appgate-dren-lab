# Validation Checklist — VyOS + AppGate DREN Lab (v1.4.4)

This checklist verifies the lab is aligned with the **current `configs/*.vyos` design**:

- **Default posture:** allow (no broad east/west segmentation yet)
- **Only restricted path:** **DREN transit (100.255.0.0/24)** between Azure `edge` and On‑prem `edge`
  - **ALLOW:** ICMP, TCP/443, UDP/443, UDP/53
  - **DROP:** everything else
- **AZ‑WAN is closed:** Azure `external.vyos` **drops all traffic on eth1 (AZ‑WAN)**

---

## Quick reference (IPs that matter)

**DREN**
- Azure `edge.vyos` eth2: **100.255.0.1/24**
- On‑prem `edge.vyos` eth2: **100.255.0.2/24**

**AZ‑WAN (closed)**
- Azure `external.vyos` eth1: **201.255.0.2/24**
- Upstream gateway (lab placeholder): **201.255.0.1**

---

## 0) Pre-flight (2 minutes)

On each router (Hyper‑V console is fine):

1. Verify interface IPs:
   - `show interfaces`
   - `show interfaces ethernet eth2` (on edge routers for DREN)
2. Verify routes:
   - `show ip route`
   - Confirm each router has the expected **default route** and **static routes** per its role.

Expected:
- Azure edge shows `eth2` = **100.255.0.1/24**
- On‑prem edge shows `eth2` = **100.255.0.2/24**

---

## 1) Validate DREN connectivity + restrictions (10 minutes)

### 1.1 ICMP across DREN should work
Run on **Azure edge**:
- `ping 100.255.0.2 count 4`

Run on **On‑prem edge**:
- `ping 100.255.0.1 count 4`

Expected: **success** both directions.

---

### 1.2 TCP/22 across DREN should be blocked (negative test)
Run on **Azure edge**:
- `sudo timeout 4 bash -c "</dev/tcp/100.255.0.2/22"`

Run on **On‑prem edge**:
- `sudo timeout 4 bash -c "</dev/tcp/100.255.0.1/22"`

Expected: **timeout** (DROP).  
If it **fails fast** with *Connection refused*, that means 22 is reaching the far side (not expected).

---

### 1.3 TCP/443 across DREN should be allowed (even if nothing is listening)
Run on **Azure edge**:
- `sudo timeout 4 bash -c "</dev/tcp/100.255.0.2/443"`

Run on **On‑prem edge**:
- `sudo timeout 4 bash -c "</dev/tcp/100.255.0.1/443"`

Expected:
- If nothing is listening on 443: **fails fast** with *Connection refused* (this is GOOD — it proves the SYN reached the far side)
- If you later stand up AppGate on 443: **connect succeeds**

---

### 1.4 UDP/53 across DREN should be allowed (validate with counters or capture)

**Option A — Counters (recommended)**
1) On **On‑prem edge**, watch counters:
- `show firewall ipv4 name DREN-ALLOW`

2) On **Azure edge**, generate UDP/53 traffic:
- `sudo bash -c "echo test >/dev/udp/100.255.0.2/53"`
- Repeat 3–5 times.

3) Re-check counters on **On‑prem edge**:
- `show firewall ipv4 name DREN-ALLOW`
- Look for the **UDP/53 rule** incrementing.

**Option B — Packet capture**
1) On **On‑prem edge**:
- `sudo tcpdump -ni eth2 udp port 53 -c 5`

2) On **Azure edge** (in another console):
- `sudo bash -c "echo test >/dev/udp/100.255.0.2/53"`
- Repeat a few times.

Expected:
- Counters increment **OR** tcpdump sees UDP/53 packets.

---

### 1.5 Confirm “everything else” is dropped on DREN
Pick a random disallowed port (example: TCP/80). Run on **Azure edge**:
- `sudo timeout 4 bash -c "</dev/tcp/100.255.0.2/80"`

Expected: **timeout**.

---

## 2) Validate “default allow” inside each site (5–10 minutes)

These tests prove your hub-and-spoke routing works *within* Azure and within On‑prem.

### 2.1 Azure internal reachability
From **Azure core**:
- `ping 201.0.0.3 count 2`  (inside AZ-CORE)
- `ping 201.1.0.1 count 2`  (inside router AZ-DOMAIN)
- `ping 201.2.0.1 count 2`  (developer router AZ-DEV)
- `ping 201.3.0.1 count 2`  (segment1 router AZ-SEG)

Expected: **success**.

### 2.2 On‑prem internal reachability
From **On‑prem core**:
- `ping 202.0.0.3 count 2`
- `ping 202.1.0.1 count 2`
- `ping 202.2.0.1 count 2`
- `ping 202.3.0.1 count 2`

Expected: **success**.

---

## 3) Validate AZ‑WAN is CLOSED (5 minutes)

Run on **Azure external**:

1) Confirm the firewall drop chain exists:
- `show firewall ipv4 name AZWAN-DROP`

2) Negative tests (should fail):
- `ping 201.255.0.1 count 3`  (should NOT work)
- `traceroute 201.255.0.1`    (should NOT progress)

3) Confirm counters increment when you attempt traffic:
- `show firewall ipv4 name AZWAN-DROP`
- `show firewall ipv4 input filter`
- `show firewall ipv4 output filter`
- `show firewall ipv4 forward filter`

Expected:
- Pings/trace **fail**
- AZWAN-DROP counters **increment**

---

## 4) Cross-site “spoke to spoke” sanity checks (optional)

This proves that routed traffic can traverse spokes → core → edge → DREN → edge → core → spokes, and that DREN policy is the governing constraint.

Example from **Azure inside** (ICMP allowed across DREN):
- `ping 202.0.0.1 count 2` (On‑prem core ONP-CORE)
- `ping 100.255.0.2 count 2` (On‑prem edge DREN IP)

Example negative test from **Azure inside** (TCP/80 should drop at DREN):
- `sudo timeout 4 bash -c "</dev/tcp/202.0.0.1/80"`

---

## Troubleshooting (if anything deviates)

If a test fails:
- Verify interfaces/IPs: `show interfaces`
- Verify routes: `show ip route`
- Verify firewall hooks are active:
  - Azure/on‑prem edge: `show firewall ipv4 forward filter`, `show firewall ipv4 input filter`, `show firewall ipv4 output filter`
  - Azure external: same, plus `show firewall ipv4 name AZWAN-DROP`
- Use captures to confirm path:
  - `sudo tcpdump -ni eth2 icmp`
  - `sudo tcpdump -ni eth2 tcp port 443`
  - `sudo tcpdump -ni eth2 udp port 53`

