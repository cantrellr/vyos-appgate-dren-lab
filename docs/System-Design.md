# System Design - VyOS Home-Lab Multicluster

## Overview

This repository defines and automates a Hyper-V based multi-site home-lab.

It provisions:

- 4 VyOS routing tiers (1 central, 3 site routers)
- 4 Kubernetes clusters across 3 sites
- Site-local network segmentation per cluster node
- A transit path from each site to a central egress router
- Internet egress through router-center on VLAN 9

## What This Repository Is

This is an infrastructure and operations repository for a reproducible lab topology.

It includes:

- Hyper-V provisioning scripts for routers and cluster VMs
- VyOS configuration fragments for site and central routing
- Node manifest files for each cluster node
- Diagrams and runbook documentation for deployment and validation

## What It Does

At a high level, the repository performs three things:

1. Builds network and VM primitives in Hyper-V.
2. Applies routing intent with VyOS config fragments.
3. Provides repeatable node definitions for the Kubernetes clusters.

## How It Works

### Logical Architecture

```mermaid
flowchart LR
  subgraph DC1[dc1 site]
    d1c[dc1manager cluster]
    d1a[dc1domain cluster]
    r1[router-dc1]
    d1c --> r1
    d1a --> r1
  end

  subgraph DC2[dc2 site]
    d2[dc2domain cluster]
    r2[router-dc2]
    d2 --> r2
  end

  subgraph DC3[dc3 site]
    d3[dc3domain cluster]
    r3[router-dc3]
    d3 --> r3
  end

  t[vSwitch-transit]
  rc[router-center]
  ex[cotpa-vlans_vsw]
  net[(Internet)]

  r1 -->|transit| rc
  r2 -->|transit| rc
  r3 -->|transit| rc
  rc --- t
  ex --> rc
  rc -->|VLAN 9 egress| net
```

### Provisioning Sequence

```mermaid
flowchart TD
  A[Run create-vyos-routers.ps1] --> B[Ensure site switches and transit switch]
  B --> C[Create router-center and router-dc1/dc2/dc3 VMs]
  C --> D[Attach router VHDX files under K8S disk root]
  D --> E[Run create-multicluster-vms.ps1]
  E --> F[Create 12 node VMs with 4 NICs each]
  F --> G[Attach node VHDX files under K8S disk root]
  G --> H[Apply configs from configs/home-lab/routers]
  H --> I[Apply node manifests from configs/home-lab/nodes]
  I --> J[Validate VMs, switches, and routing]
```

### Router Script Logic

```mermaid
flowchart TD
  R0[Input parameters and path validation] --> R1[Ensure external switch exists]
  R1 --> R2[Create or verify internal site and transit switches]
  R2 --> R3[For each router VM: create VM shell]
  R3 --> R4[Remove default NIC and add deterministic eth adapters]
  R4 --> R5[Apply VLAN 9 on router-center eth0 only]
  R5 --> R6[Clone template VHDX to K8S disk root]
  R6 --> R7[Attach disk and set disk-first boot]
```

## Key Repository Paths

- Router configs: configs/home-lab/routers/
- Node manifests: configs/home-lab/nodes/
- VM metadata/runtime paths: configs/home-lab/vms/
- Router provisioning: scripts/create-vyos-routers.ps1
- Node provisioning: scripts/create-multicluster-vms.ps1
- Topology diagrams: diagrams/Network-Topology.mmd and diagrams/System-Design.mmd
- Operational guide: docs/Runbook.md

## Data and Traffic Intent

- Site routers are the default gateways for local node segments.
- router-center is the transit and egress convergence point.
- The external uplink path is cotpa-vlans_vsw to router-center.
- Internet egress is represented as VLAN 9 egress on the router-center to Internet edge.

## Operational Notes

- All VM disks are expected under D:\Production_Data\HyperV\Virtual Hard Disks\K8S.
- Only router-center should carry the external VLAN 9 access uplink.
- Site and transit switches are internal-only Hyper-V switches.
