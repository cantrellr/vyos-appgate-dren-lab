# Management Plane IP Schema (vyos-oob)

This table defines the **out-of-band (OOB) management network** addressing for the **vyos-oob management plane**.

## Address Map

| Role / Site | Device / Hostname | Management IP (vyos-oob) |
|---|---|---|
| Management / Admin | vyos-admin | 10.255.255.10 |
| Azure | az-external | 10.255.255.11 |
| Azure | az-edge | 10.255.255.12 |
| Azure | az-core | 10.255.255.13 |
| Azure | az-inside | 10.255.255.14 |
| Azure | az-developer | 10.255.255.15 |
| Azure | az-segment1 | 10.255.255.16 |
| On-Prem | onp-edge | 10.255.255.22 |
| On-Prem | onp-core | 10.255.255.23 |
| On-Prem | onp-inside | 10.255.255.24 |
| On-Prem | onp-developer | 10.255.255.25 |
| On-Prem | onp-segment1 | 10.255.255.26 |

## Notes

- **Network:** `10.255.255.0/24`
- **Purpose:** Dedicated OOB management plane for VyOS infrastructure (`vyos-oob`)
- **Naming convention:** `az-*` = Azure site, `onp-*` = On-Prem site
