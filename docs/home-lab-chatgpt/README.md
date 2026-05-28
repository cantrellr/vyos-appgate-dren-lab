# Home‑Lab Multicluster Environment (ChatGPT Edition)

## Overview

This sub‑directory defines a minimalist home‑lab environment that mirrors the
architecture of the `ingress‑monitoring‑redesign` branch of the
`k8s‑mystical‑mesh` repository.  The goal is to provide a reproducible lab on
Hyper‑V with four Kubernetes clusters spread across three sites.  Each cluster
is limited to a **single control node** and **two worker nodes** to fit within
the available hardware (1 vCPU and 4 GiB RAM per VM).  A central VyOS router
provides NAT to the Internet through the Hyper‑V switch `cotpa_vlans_vsw`
on VLAN 9 so that all nodes can pull container images.

### Cluster summary

| Cluster | Site | Purpose | Nodes | Service CIDR | Pod CIDR |
| --- | --- | --- | --- | --- | --- |
| **j64manager** | dc1 | Central control-plane services (MongoDB Operator, Istio primary, monitoring) | 1 control<br/>2 workers | `10.93.0.0/16` | `10.243.0.0/16` |
| **j64domain** | dc1 | Application workloads (Rocket.Chat, Keycloak, MongoDB member, NATS) | 1 control<br/>2 workers | `10.94.0.0/16` | `10.244.0.0/16` |
| **j52domain** | dc2 | Application workloads (Rocket.Chat, MongoDB member, NATS) | 1 control<br/>2 workers | `10.96.0.0/16` | `10.246.0.0/16` |
| **r01domain** | dc3 | Application workloads (Rocket.Chat, MongoDB member, NATS) | 1 control<br/>2 workers | `10.98.0.0/16` | `10.248.0.0/16` |

The clusters are designed to run with minimal resources while still exposing
service mesh, storage and monitoring components.  Pods and services use the
same CIDR ranges as the pre‑production environment to ease migration of
manifest files.

## Network design

Each site has four dedicated networks:

* **kubes‑domain** – primary network used for Kubernetes API, node IPs and
  service endpoints.
* **storage** – optional iSCSI/NFS network reserved for persistent volumes.
* **domain management** – general management network for SSH and API access.
* **segment1** – alternate ingress network (e.g. for devlocal/segment1 isolation).

Site routers (one per site) connect these internal networks to a **transit
network** (`10.254.0.0/24`).  The **central router** sits on this transit and
performs source NAT for all internal networks via the external switch
`cotpa_vlans_vsw` on VLAN 9.  Nodes set their default gateway to the site
router, which in turn defaults to the central router.  The central router
publishes static routes for all subnets back to the appropriate site router.

### Topology diagram

The diagram below shows the relationships between clusters, site routers, the
transit network, the central router and the Internet.  `<br/>` is used in
labels to improve readability.

![Home‑lab multicluster network diagram]({{file:file-6zjxpXjMQQofNhzGz52FUE}})

## IP allocations

The following table summarizes the IP assignments for each node.  All
addresses are static; the default gateway for the `eth0` (kubes‑domain) interface
is the first address in the respective subnet (e.g. `10.1.4.1` for dc1).

| Node | Cluster | Site | eth0 – kubes | eth1 – storage | eth2 – domain | eth3 – segment1 |
| --- | --- | --- | --- | --- | --- | --- |
| **j64manager-ctrl01** | j64manager | dc1 | 10.1.4.131 | 172.16.10.101 | 192.168.1.131 | 1.1.0.131 |
| j64manager-work01 | j64manager | dc1 | 10.1.4.132 | 172.16.10.102 | 192.168.1.132 | 1.1.0.132 |
| j64manager-work02 | j64manager | dc1 | 10.1.4.133 | 172.16.10.103 | 192.168.1.133 | 1.1.0.133 |
| **j64domain-ctrl01** | j64domain | dc1 | 10.1.4.141 | 172.16.10.109 | 192.168.1.141 | 1.1.0.141 |
| j64domain-work01 | j64domain | dc1 | 10.1.4.142 | 172.16.10.110 | 192.168.1.142 | 1.1.0.142 |
| j64domain-work02 | j64domain | dc1 | 10.1.4.143 | 172.16.10.111 | 192.168.1.143 | 1.1.0.143 |
| **j52domain-ctrl01** | j52domain | dc2 | 10.2.4.161 | 172.16.20.116 | 192.168.2.161 | 1.2.0.161 |
| j52domain-work01 | j52domain | dc2 | 10.2.4.162 | 172.16.20.117 | 192.168.2.162 | 1.2.0.162 |
| j52domain-work02 | j52domain | dc2 | 10.2.4.163 | 172.16.20.118 | 192.168.2.163 | 1.2.0.163 |
| **r01domain-ctrl01** | r01domain | dc3 | 10.3.4.181 | 172.16.30.123 | 192.168.3.181 | 1.3.0.181 |
| r01domain-work01 | r01domain | dc3 | 10.3.4.182 | 172.16.30.124 | 192.168.3.182 | 1.3.0.182 |
| r01domain-work02 | r01domain | dc3 | 10.3.4.183 | 172.16.30.125 | 192.168.3.183 | 1.3.0.183 |

## Deployment instructions

1. **Prepare the environment.**  Enable Hyper‑V on your Windows host and
   download a suitable guest OS image (e.g. Ubuntu Server cloud image).  Obtain
   a VyOS v1.4.4 image for the routers.
2. **Create vSwitches and routers.**  Run the existing script
   `scripts/create-vyos-routers.ps1` with a path to your VyOS VHDX template
   and the external switch name (e.g. `cotpa_vlans_vsw`).  This script
   creates the central and site routers and the internal vSwitches.
3. **Create cluster VMs.**  Use the provided script
   `scripts/home-lab-chatgpt/create-home-lab-vms.ps1` with the path to your
   Ubuntu base image.  It will create 12 VMs with consistent NIC ordering.
4. **Apply node manifests.**  After cloning this repository to your build
   machine, copy the files under `configs/home-lab-chatgpt/nodes` to
   `/rke2-node-init/configs/home-lab-chatgpt/` on each node or adjust
   accordingly.  The manifests use the **rkeprep** format to bootstrap
   RKE2; refer to the `rke2-node-init` repository for instructions.
5. **Configure routers.**  From each VyOS VM, enter configuration mode
   (`configure`), paste the corresponding `configs/home-lab-chatgpt/routers/*.vyos`
   file, then `commit` and `save`.  Central NAT must be committed before the
   clusters can reach the Internet.
6. **Deploy services.**  Follow the standard install flow documented in
   `k8s‑mystical‑mesh` (`build/install/core/*`, `build/install/istio/*`, etc.).
   Use the domain values in `j64manager`, `j64domain`, `j52domain`, and
   `r01domain` directories as a baseline, but adjust replica counts and
   resources downward to reflect the limited memory of each node.

## Registry authentication

Many scripts expect a Docker registry secret to pull images from a private
registry.  An example Kubernetes secret is shown below; replace the
`username` and `password` fields with your own credentials.  Apply this
manifest to each cluster namespace where images are pulled.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: altregistry-auth
  namespace: kube-system
data:
  .dockerconfigjson: <base64-encoded-auth>
type: kubernetes.io/dockerconfigjson
```

## Resource tuning

Because each node only has 4 GiB of RAM and a single vCPU, be mindful of
resource requests and limits when deploying workloads.  Reduce replica counts
and tune CPU/memory requests for services like Grafana, Prometheus and
MongoDB.  Disable components that are not required for testing (e.g. HA
Controllers, multiple replicas).  The configuration baseline in
`k8s‑mystical‑mesh` provides guidance on which workloads can be scaled back.

---

*Last updated: May 28, 2026.*