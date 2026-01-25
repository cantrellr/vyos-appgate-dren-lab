# Lab Rewire Plan — Status

This repo has been realigned to the **final 201.x / 202.x / 100.255.0.0/24** design.

## What’s implemented now
- 11 VyOS routers (6 Azure, 5 On‑prem)
- Shared DREN transit:
  - Azure edge: **100.255.0.1/24**
  - On‑prem edge: **100.255.0.2/24**
- Firewall posture:
  - Default = allow
  - DREN only allows **ICMP**, **TCP/UDP 443**, **UDP 53**
  - Azure **AZ‑WAN is closed** (drop in/out/local)

## Source of truth
- Router configs: `configs/**`
- Hyper‑V automation: `scripts/**`
- Diagrams: `diagrams/**` and `docs/Topology.mmd`
