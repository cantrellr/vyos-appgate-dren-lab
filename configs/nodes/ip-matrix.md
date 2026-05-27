# Network IP Matrix — Simplified (selected nodes)
Version: 2.0 (subset)
Date: 2026-04-29

This file summarizes the IPs assigned to the simplified 2-node-per-cluster topology used for bootstrap yaml files in `configs/nodes/`.

## j64manager
- j64manager-ctrl01: kubes-domain 10.0.4.131, netapp-1001 172.16.0.101, segment1 1.0.0.131
- j64manager-work01: kubes-domain 10.0.4.135, netapp-1001 172.16.0.105, segment1 1.0.0.135
Service CIDR: 10.93.0.0/16, Pod CIDR: 10.243.0.0/16

## j64domain
- j64domain-ctrl01: kubes-domain 10.0.4.141, netapp-1001 172.16.0.109, segment1 1.0.0.141
- j64domain-work01: kubes-domain 10.0.4.145, netapp-1001 172.16.0.113, segment1 1.0.0.145
Service CIDR: 10.94.0.0/16, Pod CIDR: 10.244.0.0/16

## j52domain
- j52domain-ctrl01: kubes-domain 10.0.4.161, netapp-1001 172.16.0.116, segment1 1.0.0.161
- j52domain-work01: kubes-domain 10.0.4.165, netapp-1001 172.16.0.120, segment1 1.0.0.165
Service CIDR: 10.96.0.0/16, Pod CIDR: 10.246.0.0/16

## r01domain
- r01domain-ctrl01: kubes-domain 10.0.4.181, netapp-1001 172.16.0.123, segment1 1.0.0.181
- r01domain-work01: kubes-domain 10.0.4.185, netapp-1001 172.16.0.127, segment1 1.0.0.185
Service CIDR: 10.98.0.0/16, Pod CIDR: 10.248.0.0/16

Notes:
- These files are scaffolds for a pre-production lab. Adjust adapter names and routing when applying VyOS fragments or creating Hyper-V switches.
