# VyOS Universal Router v1.4.4 — AppGate SDP + DREN Lab (Azure + On-Prem)

This repo is a **deployable Hyper‑V lab** for an 11‑router VyOS topology:

- **Azure site (201.x)**: external, edge, core, inside, developer, segment1
- **On‑prem site (202.x)**: edge, core, inside, developer, segment1
- **DREN transit (100.255.0.0/24)** between Azure `edge` and On‑prem `edge`

## Ground rules (non-negotiable)

- **Default posture = allow** (we are not doing a full segmentation policy on every interface yet).
- The **only constrained path** is **DREN**:
  - Allowed across DREN: **ICMP**, **TCP/443**, **UDP/443**, **UDP/53**
  - Everything else across DREN: **dropped**
- **AZ‑WAN is closed** right now:
  - Azure `external.vyos` **drops all traffic on AZ‑WAN (eth1)** inbound/outbound/local

## Validation

Run the checklist: `docs/Validation-Checklist.md`.

## Router configuration (interfaces, addresses, routes)

The following per-router tables are generated from the `configs/*.vyos` files. The Default route column shows the configured 0.0.0.0/0 next-hop (if present).

 
### az-external

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.11/24 (static) | 201.255.0.1 |
| eth1 | AZ-WAN | 201.255.0.2/24 (static) | |
| eth2 | AZ-EXT | 201.254.0.2/24 (static) | |

 
### az-edge

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.12/24 (static) | 201.254.0.2 |
| eth1 | AZ-EXT | 201.254.0.1/24 (static) | |
| eth2 | AZ-DREN | 100.255.0.1/24 (static) | |
| eth3 | AZ-CORE | 201.0.0.2/24 (static) | |

 
### az-core

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.13/24 (static) | 201.0.0.2 |
| eth1 | AZ-CORE | 201.0.0.1/24 (static) | |
| eth2 | AZ-SDPC | 201.0.1.1/24 (static) | |
| eth3 | AZ-SDPG | 201.0.2.1/24 (static) | |
| eth4 | AZ-SDPT | 201.0.3.1/24 (static) | |

 
### az-inside

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.14/24 (static) | 201.0.0.1 |
| eth1 | AZ-CORE | 201.0.0.3/24 (static) | |
| eth2 | AZ-DOMAIN | 201.1.0.1/24 (static) | |
| eth3 | AZ-DOMSVC | 201.1.1.1/24 (static) | |
| eth4 | AZ-AVD | 201.1.2.1/24 (static) | |

 
### az-developer

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.15/24 (static) | 201.0.0.1 |
| eth1 | AZ-CORE | 201.0.0.4/24 (static) | |
| eth2 | AZ-DEV | 201.2.0.1/24 (static) | |
| eth3 | AZ-DEVSVC | 201.2.1.1/24 (static) | |

 
### az-segment1

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.16/24 (static) | 201.0.0.1 |
| eth1 | AZ-CORE | 201.0.0.5/24 (static) | |
| eth2 | AZ-SEG | 201.3.0.1/24 (static) | |
| eth3 | AZ-HWIL | 201.3.1.1/24 (static) | |

 
### onp-edge

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.22/24 (static) | 202.254.0.2 |
| eth1 | ONP-EXT | 202.254.0.1/24 (static) | |
| eth2 | ONP-DREN | 100.255.0.2/24 (static) | |
| eth3 | ONP-CORE | 202.0.0.2/24 (static) | |

 
### onp-core

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.23/24 (static) | 202.0.0.2 |
| eth1 | ONP-CORE | 202.0.0.1/24 (static) | |
| eth2 | ONP-SDPC | 202.0.1.1/24 (static) | |
| eth3 | ONP-SDPG | 202.0.2.1/24 (static) | |
| eth4 | ONP-SDPT | 202.0.3.1/24 (static) | |

 
### onp-inside

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.24/24 (static) | 202.0.0.1 |
| eth1 | ONP-CORE | 202.0.0.3/24 (static) | |
| eth2 | ONP-DOMAIN | 202.1.0.1/24 (static) | |
| eth3 | ONP-DOMSVC | 202.1.1.1/24 (static) | |
| eth4 | ONP-AVD | 202.1.2.1/24 (static) | |

 
### onp-developer

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.25/24 (static) | 202.0.0.1 |
| eth1 | ONP-CORE | 202.0.0.4/24 (static) | |
| eth2 | ONP-DEV | 202.2.0.1/24 (static) | |
| eth3 | ONP-DEVSVC | 202.2.1.1/24 (static) | |

 
### onp-segment1

| Interface | Interface name | Address (DHCP/Static) | Default route (next-hop) |
| --- | --- | --- | --- |
| eth0 | VYOS-OOB | 10.255.255.26/24 (static) | 202.0.0.1 |
| eth1 | ONP-CORE | 202.0.0.5/24 (static) | |
| eth2 | ONP-SEG | 202.3.0.1/24 (static) | |
| eth3 | ONP-HWIL | 202.3.1.1/24 (static) | |


## Firewall rules (summary)

This repo implements two explicit, enforced firewall postures and a set of optional port groups in `configs/common/firewall-groups.vyos`.

- **DREN restricted (both sites)**: enforced by `DREN-ALLOW` (forward/output) and `DREN-LOCAL` (input) chains on both `az-edge` and `onp-edge`. Allowed:
  - ICMP
  - TCP port 443 (stateful)
  - UDP port 443 (stateful)
  - UDP port 53 (stateful)
  - Established/related traffic
  - Default for DREN chains: drop everything else.

- **AZ‑WAN closed (Azure external router)**: enforced by `AZWAN-DROP` on `az-external` that is jumped-to for any traffic touching `eth1` (AZ‑WAN) on input/forward/output chains.

- **Common port groups**: a convenience file `configs/common/firewall-groups.vyos` defines named port-groups such as `APPGATE_CLIENT_TCP/UDP`, `APPGATE_DNS_UDP`, and `PROTECTED_TCP`.

### Example (how rules are applied)

- `az-edge` forward/input/output chains jump into `DREN-ALLOW`/`DREN-LOCAL` for traffic touching `eth2` (DREN). The DREN policy is implemented as a restrictive whitelist.
- `az-external` jumps to `AZWAN-DROP` for any traffic on `eth1` (AZ-WAN), effectively isolating that network in this lab.

## Where the configs live

- `configs/azure/*.vyos`
- `configs/onprem/*.vyos`
- `configs/common/firewall-groups.vyos` (optional shared groups)

These are **paste‑ready `set ...` commands**. Prefer editing the `configs/*.vyos` that correspond to the router you want to change and testing the changes on a single VyOS VM before applying across the lab.

## Hyper‑V deployment

Scripts are in `scripts/`. See the per-script technical READMEs for in-depth behavior, invocation, and examples:

- `create-hyperv-switches.ps1` — creates the vSwitches used by the lab; details: [scripts/create-hyperv-switches.md](scripts/create-hyperv-switches.md)
- `deploy-hyperv-lab.ps1` — creates 11 VMs and attaches NICs in **eth0..ethN order**; details: [scripts/deploy-hyperv-lab.md](scripts/deploy-hyperv-lab.md)
- `remove-hyperv-lab.ps1` — tears down the lab; details: [scripts/remove-hyperv-lab.md](scripts/remove-hyperv-lab.md)
- `bootstrap-vyos.ps1` — builds config/cloud-init ISOs and can attach them to VMs; details: [scripts/bootstrap-vyos.md](scripts/bootstrap-vyos.md)
- `export-vyos-hwids.ps1` — extract VM MAC addresses and render VyOS `hw-id` lines; details: [scripts/export-vyos-hwids.md](scripts/export-vyos-hwids.md)
- `apply-config.sh` — simple SSH-based config apply helper; details: [scripts/apply-config.md](scripts/apply-config.md)
- `validate-dren.sh` — on-box DREN policy validation helper; details: [scripts/validate-dren.md](scripts/validate-dren.md)

See [docs/Runbook.md](docs/Runbook.md) for the exact commands and validation checks.

## Diagrams

- Topology diagram: [diagrams/topology.mmd](diagrams/topology.mmd)
- Additional mermaid sources: [diagrams/new-routing-topology.mmd](diagrams/new-routing-topology.mmd), [diagrams/appgate-flows.mmd](diagrams/appgate-flows.mmd)

For validation and design details see [docs/System-Design.md](docs/System-Design.md).
