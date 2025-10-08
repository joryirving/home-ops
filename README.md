<div align="center">

<img src="https://avatars.githubusercontent.com/u/46251616?v=4" align="center" width="144px" height="144px"/>


### <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f680/512.gif" alt="🚀" width="16" height="16"> My Home Operations Repository <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f6a7/512.gif" alt="🚧" width="16" height="16">

_... managed with Flux, Renovate, and GitHub Actions_ <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f916/512.gif" alt="🤖" width="16" height="16">

</div>

<div align="center">

[![Discord](https://img.shields.io/discord/673534664354430999?style=for-the-badge&label&logo=discord&logoColor=white&color=blue)](https://discord.gg/home-operations)&nbsp;&nbsp;
[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Ftalos_version&style=for-the-badge&logo=talos&logoColor=white&color=blue&label=%20)](https://talos.dev)&nbsp;&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fkubernetes_version&style=for-the-badge&logo=kubernetes&logoColor=white&color=blue&label=%20)](https://kubernetes.io)&nbsp;&nbsp;
[![Flux](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fflux_version&style=for-the-badge&logo=flux&logoColor=white&color=blue&label=%20)](https://fluxcd.io)&nbsp;&nbsp;
[![Renovate](https://img.shields.io/github/actions/workflow/status/joryirving/admin/schedule-renovate.yaml?branch=main&label=&logo=renovatebot&style=for-the-badge&color=blue)](https://github.com/joryirving/joryirving/actions/workflows/scheduled-renovate.yaml)

</div>

<div align="center">

[![Home-Internet](https://img.shields.io/endpoint?url=https%3A%2F%2Fhealthchecks.io%2Fbadge%2Ff0288b6a-305e-4084-b492-bb0a54%2FKkxSOeO1-2.shields&style=for-the-badge&logo=ubiquiti&logoColor=white&label=Home%20Internet)](https://status.jory.dev)&nbsp;&nbsp;
[![Status-Page](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.jory.dev%2Fapi%2Fv1%2Fendpoints%2Fmain-external_gatus%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=statuspage&logoColor=white&label=Status%20Page)](https://status.jory.dev/endpoints/external_gatus)&nbsp;&nbsp;
[![Plex](https://img.shields.io/endpoint?url=https%3A%2F%2Fstatus.jory.dev%2Fapi%2Fv1%2Fendpoints%2Fmain-external_plex%2Fhealth%2Fbadge.shields&style=for-the-badge&logo=plex&logoColor=white&label=Plex)](https://status.jory.dev/endpoints/external_plex)

</div>

<div align="center">

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_age_days&style=flat-square&label=Age)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_uptime_days&style=flat-square&label=Uptime)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_node_count&style=flat-square&label=Nodes)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_pod_count&style=flat-square&label=Pods)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_cpu_usage&style=flat-square&label=CPU)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_memory_usage&style=flat-square&label=Memory)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Power-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_power_usage&style=flat-square&label=Power)](https://github.com/kashalls/kromgo)&nbsp;&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fkromgo.jory.dev%2Fcluster_alert_count&style=flat-square&label=Alerts)](https://github.com/kashalls/kromgo)
</div>

---

## Overview

This is a monorepository is for my home kubernetes clusters.
I try to adhere to Infrastructure as Code (IaC) and GitOps practices using tools like [Terraform](https://www.terraform.io/), [Kubernetes](https://kubernetes.io/), [Flux](https://github.com/fluxcd/flux2), [Renovate](https://github.com/renovatebot/renovate), and [GitHub Actions](https://github.com/features/actions).

The purpose here is to learn k8s, while practicing Gitops.

---

## ⛵ Kubernetes

My Kubernetes clusters are deployed with [Talos](https://www.talos.dev). One is a test clkuster, one is a low-power utility cluster, running important services, and the other is a semi-hyper-converged cluster, workloads and block storage are sharing the same available resources on my nodes while I have a separate NAS with ZFS for NFS/SMB shares, bulk file storage and backups.

There is a template over at [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) if you want to try and follow along with some of the practices I use here.

### Core Components

- **Networking & Service Mesh**: [cilium](https://github.com/cilium/cilium) provides eBPF-based networking, while [envoy](https://gateway.envoyproxy.io/) powers service-to-service communication with L7 proxying and traffic management. [cloudflared](https://github.com/cloudflare/cloudflared) secures ingress traffic via Cloudflare, and [external-dns](https://github.com/kubernetes-sigs/external-dns) keeps DNS records in sync automatically.
- **Security & Secrets**: [cert-manager](https://github.com/cert-manager/cert-manager) automates SSL/TLS certificate management. For secrets, I use [external-secrets](https://github.com/external-secrets/external-secrets) with [1Password Connect](https://github.com/1Password/connect) to inject secrets into Kubernetes, and [sops](https://github.com/getsops/sops) to store and manage encrypted secrets in Git.
- **Storage & Data Protection**: [rook](https://github.com/rook/rook) provides distributed storage for persistent volumes, with [volsync](https://github.com/backube/volsync) handling backups and restores. [spegel](https://github.com/spegel-org/spegel) improves reliability by running a stateless, cluster-local OCI image mirror.
- **Automation & CI/CD**: [actions-runner-controller](https://github.com/actions/actions-runner-controller) runs self-hosted GitHub Actions runners directly in the cluster for continuous integration workflows. For IaC, I use [tofu-controller](https://github.com/weaveworks/tf-controller) as additional Flux component used to run Terraform from within a Kubernetes cluster.

### GitOps

[Flux](https://github.com/fluxcd/flux2) watches the clusters in my [kubernetes](./kubernetes/) folder (see Directories below) and makes the changes to my clusters based on the state of my Git repository.

The way Flux works for me here is it will recursively search the `kubernetes/${cluster}/apps` folder until it finds the most top level `kustomization.yaml` per directory and then apply all the resources listed in it. That aforementioned `kustomization.yaml` will generally only have a namespace resource and one or many Flux kustomizations (`ks.yaml`). Under the control of those Flux kustomizations there will be a `HelmRelease` or other resources related to the application which will be applied.

[Renovate](https://github.com/renovatebot/renovate) watches my **entire** repository looking for dependency updates, when they are found a PR is automatically created. When some PRs are merged Flux applies the changes to my cluster.

### Directories

This Git repository contains the following directories under [Kubernetes](./kubernetes/).

```sh
📁 kubernetes
├── 📁 apps              # app configurations
│   ├── 📁 base          # base app configuration
│   ├── 📁 main          # cluster specific overlay
│   ├── 📁 utility
├── 📁 clusters          # Cluster flux configurations
│   ├── 📁 main
│   ├── 📁 utility
├── 📁 components        # re-useable components
```

### Networking

<details>
  <summary>Click to see a high-level network diagram</summary>

  <img src="https://raw.githubusercontent.com/joryirving/home-ops/main/docs/src/assets/network-topology.png" align="center" alt="dns"/>
</details>

---

## ☁️ Cloud Dependencies

While most of my infrastructure and workloads are self-hosted I do rely upon the cloud for certain key parts of my setup. This saves me from having to worry about two things. (1) Dealing with chicken/egg scenarios and (2) services I critically need whether my cluster is online or not.

The alternative solution to these two problems would be to host a Kubernetes cluster in the cloud and deploy applications like [HCVault](https://www.vaultproject.io/), [Vaultwarden](https://github.com/dani-garcia/vaultwarden), [ntfy](https://ntfy.sh/), and [Gatus](https://gatus.io/). However, maintaining another cluster and monitoring another group of workloads is a lot more time and effort than I am willing to put in.

| Service                                     | Use                                                               | Cost           |
|---------------------------------------------|-------------------------------------------------------------------|----------------|
| [1Password](https://1Password.com/)         | Secrets with [External Secrets](https://external-secrets.io/)     | ~$80/yr$       |
| [Cloudflare](https://www.cloudflare.com/)   | Domain, DNS, WAF and R2 bucket (S3 Compatible endpoint)           | ~$40/yr        |
| [GitHub](https://github.com/)               | Hosting this repository and continuous integration/deployments    | Free           |
| [Healthchecks.io](https://healthchecks.io/) | Monitoring internet connectivity and external facing applications | Free           |
|                                             |                                                                   | Total: ~$10/mo |

---

## 🌐 DNS

In my cluster there are two instances of [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) running. One for syncing private DNS records to my `UDM-SE` using [ExternalDNS webhook provider for UniFi](https://github.com/kashalls/external-dns-unifi-webhook), while another instance syncs public DNS to `Cloudflare`. This setup is managed by creating ingresses with two specific classes: `internal` for private DNS and `external` for public DNS. The `external-dns` instances then syncs the DNS records to their respective platforms accordingly.

---

## 🔧 Hardware

### Main Kubernetes Cluster

| Name  | Device | CPU       | OS Disk    | Local Disk | Rook Disk  | RAM   | OS    | Purpose           |
|-------|--------|-----------|------------|------------|------------|-------|-------|-------------------|
| Ayaka | MS-01  | i9-13900H | 960GB NVMe | 1TB NVMe   | 1.92TB U.2 | 128GB | Talos | k8s control-plane |
| Eula  | MS-01  | i9-13900H | 960GB NVMe | 1TB NVMe   | 1.92TB U.2 | 128GB | Talos | k8s control-plane |
| Ganyu | MS-01  | i9-13900H | 960GB NVMe | 1TB NVMe   | 1.92TB U.2 | 128GB | Talos | k8s control-plane |

OS Disk: m.2 Samsung PM9A3 960GB
Local Disk: m.2 WD SN770 1TB
Rook Disk: u.2 Samsung PM9A3 1.92TB

Total CPU: 60 Cores/60 Threads
Total RAM: 384GB

### Utility Kubernetes Cluster

| Name     | Device     | CPU           | OS Disk   | Local Disk | RAM  | OS    | Purpose           |
|----------|------------|---------------|-----------|------------|------|-------|-------------------|
| Celestia | Bosgame P1 | Ryzen 7 5700U | 500GB SSD | 1TB NVMe   | 32GB | Talos | k8s control-plane |

OS Disk: 2.5" Samsung 870 EVO SSD
Local Disk: m.2 WD SN770 1TB

Total CPU: 8 Cores/16 Threads
Total RAM: 32GB

### Supporting Hardware

| Name    | Device            | CPU        | OS Disk    | Data Disk      | RAM   | OS           | Purpose           |
|---------|-------------------|------------|------------|----------------|-------|--------------|-------------------|
| Voyager | MS-01             | i5-12600H  | 32GB USB   | -              | 96GB  | Unraid       | NAS/NFS/Backup    |
| DAS     | Lenovo SA120      | -          | -          | 6x14TB Raidz2  | -     | -            | ZFS               |
| Venti   | Raspberry Pi5     | Cortex A76 | 250GB NVMe | -              | 8GB   | Raspbian     | NUT/SSH (Main)    |
| Sayu    | Raspberry Pi5     | Cortex A76 | 500GB NVMe | -              | 8GB   | Raspbian     | NUT/SSH (Utility) |
| PiKVM   | Raspberry Pi4     | Cortex A72 | 64GB mSD   | -              | 4GB   | PiKVM (Arch) | KVM (Main)        |
| JetKVM  | JetKVM            | RV1106G3   | 8GB EMMC   | -              | 256MB | Linux 5.10   | KVM (Utility)     |
| PDU     | UniFi USP PDU Pro | -          | -          | -              | -     | -            | PDU               |
| TESmart | 8 port KVM        | -          | -          | -              | -     | -            | Network KVM       |

### Networking/UPS Hardware

| Device                      | Purpose              |
|-----------------------------|----------------------|
| Unifi UDM-SE                | Network - Router     |
| Back-UPS 600                | Network - UPS        |
| Unifi USW-Enterprise-24-PoE | Server - 2.5G Switch |
| Unifi USW-Aggregation       | Server - 10G Switch  |
| Tripp Lite 1500             | Server - UPS         |
| Ecoflow Delta 3 Plus        | Server - UPS         |

---

## ⭐ Stargazers

<div align="center">

[![Star History Chart](https://api.star-history.com/svg?repos=joryirving/home-ops&type=Date)](https://star-history.com/#joryirving/home-ops&Date)

</div>

---

## 🤝 Thanks

Big shout out to the [cluster-template](https://github.com/onedr0p/cluster-template), and the [Home Operations](https://discord.gg/home-operations) Discord community. Be sure to check out [kubesearch.dev](https://kubesearch.dev/) for ideas on how to deploy applications or get ideas on what you may deploy.
