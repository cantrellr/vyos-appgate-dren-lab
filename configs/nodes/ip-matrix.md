# Network IP Matrix — Simplified (selected nodes)
Version: 2.0 (renamed clusters to dc*)
Date: 2026-05-27

This file summarizes the IPs assigned to the simplified 2-node-per-cluster topology used for bootstrap yaml files in `configs/nodes/` after renaming clusters to `dc1*`, `dc2*`, `dc3*`.

Each site has four networks per stakeholder request: `kubes-domain` (primary cluster network), `netapp-1001` (storage/iSCSI), `domain` (management/domain), and `segment1` (secondary app network). Node VMs will have four NICs attached to those networks.

## dc1 (site for `dc1manager` and `dc1domain` clusters)
- dc1manager-ctrl01: kubes-domain 10.1.4.131, netapp-1001 172.16.10.101, domain 192.168.1.131, segment1 1.1.0.131
- dc1manager-work01: kubes-domain 10.1.4.135, netapp-1001 172.16.10.105, domain 192.168.1.135, segment1 1.1.0.135
- dc1domain-ctrl01: kubes-domain 10.1.4.141, netapp-1001 172.16.10.109, domain 192.168.1.141, segment1 1.1.0.141
- dc1domain-work01: kubes-domain 10.1.4.145, netapp-1001 172.16.10.113, domain 192.168.1.145, segment1 1.1.0.145
Service CIDR (dc1manager): 10.93.0.0/16, Pod CIDR: 10.243.0.0/16
Service CIDR (dc1domain): 10.94.0.0/16, Pod CIDR: 10.244.0.0/16

## dc2 (site for `dc2domain` cluster)
- dc2domain-ctrl01: kubes-domain 10.2.4.161, netapp-1001 172.16.20.116, domain 192.168.2.161, segment1 1.2.0.161
- dc2domain-work01: kubes-domain 10.2.4.165, netapp-1001 172.16.20.120, domain 192.168.2.165, segment1 1.2.0.165
Service CIDR: 10.96.0.0/16, Pod CIDR: 10.246.0.0/16

## dc3 (site for `dc3domain` cluster)
- dc3domain-ctrl01: kubes-domain 10.3.4.181, netapp-1001 172.16.30.123, domain 192.168.3.181, segment1 1.3.0.181
- dc3domain-work01: kubes-domain 10.3.4.185, netapp-1001 172.16.30.127, domain 192.168.3.185, segment1 1.3.0.185
Service CIDR: 10.98.0.0/16, Pod CIDR: 10.248.0.0/16

Notes:
- A Central Transit Router will provide Internet egress (SNAT/masquerade) for all site networks.
- Transit network: `10.254.0.0/24` — central transit router at `10.254.0.1`, assign site router transit IPs like `10.254.0.11` (dc1), `10.254.0.12` (dc2), `10.254.0.13` (dc3).
- Site routers should configure a default route via `10.254.0.1` and remove local uplink NAT rules. Adjust public uplink IPs and adapter names on the central router before applying.

