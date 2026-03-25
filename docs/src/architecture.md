# Architecture

## High-Level Overview

This repository is a **Home Operations monorepo** managing 3 Kubernetes clusters via GitOps:

| Cluster | Purpose | Hardware |
|---------|---------|----------|
| `main` | Production workloads + hyper-converged storage | 3x MS-01 + 1x Bosgame M5 (i9-13900H x3, Ryzen AI Max+ 395 x1, 128GB RAM each) |
| `utility` | Low-power services | Bosgame P1 (Ryzen 7 5700U) |
| `test` | Testing changes | Beelink Mini-S (Celeron N5095) |

---

## GitOps Flow

```
Git Repository → Flux (GitOps Operator) → Kubernetes Clusters
```

1. **Code pushed** to GitHub
2. **Renovate** scans for dependency updates, creates PRs
3. **PRs merged** to main branch
4. **Flux** detects changes via Git source
5. **Flux** recursively searches `kubernetes/${cluster}/apps` for kustomizations
6. **Flux** applies `HelmRelease` and other resources to the cluster

### Directory Structure (Apps)

```
kubernetes/apps/
├── base/           # Common app configs (shared across clusters)
├── main/           # Main cluster overlay
├── utility/        # Utility cluster overlay
└── test/           # Test cluster overlay
```

Each app directory contains a `kustomization.yaml` that references Flux kustomizations (`ks.yaml`), which in turn contain `HelmRelease` resources.

### Flux Reconciliation Chain

```
Git Repository
    ↓ (source.toolkit.fluxcd.io)
HelmRepository / GitRepository
    ↓ (kustomize.toolkit.fluxcd.io)
Kustomization (ks.yaml)
    ↓ (helm.toolkit.fluxcd.io)  
HelmRelease
    ↓
Kubernetes Resources (Deployment, Service, etc.)
```

---

## Core Components

### Networking (cilium)

- **cilium** provides eBPF-based CNI networking
- Replaces kube-proxy for service load balancing
- BGP peering with UniFi UDM-SE for external access
- Hubble for observability

### Ingress & DNS

```
Internet → Cloudflare → cloudflared (tunnel) → Ingress Controllers
                                                    ↓
                              external-dns (public) → Cloudflare
                              external-dns (internal) → UniFi UDMP
```

- **Envoy Gateway** handles L7 proxying and ingress
- **external-dns** syncs ingress annotations to DNS providers
- Two DNS classes: `internal` (private) and `external` (public)

### Secrets Management

```
1Password → external-secrets → Kubernetes Secrets
                   ↑
            1Password Connect (onepassword-sync)
```

- **external-secrets** fetches secrets from 1Password via Connect
- **SOPS** encrypts sensitive config values stored in Git
- **cert-manager** handles automatic TLS certificates

### Storage

- **Rook/Ceph** provides distributed block storage (RBD)
- **volsync** handles persistent volume backups
- **spegel** provides local OCI image mirror for reliability
- Voyager NAS serves NFS/SMB shares via Unraid

### CI/CD

- **actions-runner-controller** runs self-hosted GitHub Actions runners
- **tofu-controller** runs Terraform from within Kubernetes (IaC)

---

## Network Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                    ┌─────▼─────┐
                    │ Cloudflare│ (WAF, DNS, R2)
                    └─────┬─────┘
                          │ Tunnel (cloudflared)
          ┌───────────────┼───────────────┐
          │               │               │
    ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
    │   Main    │   │  Utility  │   │   Test    │
    │  Cluster  │   │  Cluster  │   │  Cluster  │
    └─────┬─────┘   └───────────┘   └───────────┘
          │
    ┌─────▼─────┐
    │  Cilium   │ (eBPF CNI)
    │   BGP     │
    └─────┬─────┘
          │
    ┌─────▼─────┐
    │  UniFi    │ (Router/DHCP/DNS)
    │  UDMP-SE  │
    └───────────┘
```

---

## Cluster Bootstrap

1. **Talos Linux** installed on bare metal via talosctl
2. **Flux** bootstrapped via `flux bootstrap`
3. **Apps** deployed via Flux kustomizations

The `bootstrap/` directory contains helmfile templates used during initialization.

---

## Terraform/OpenTofu

Infrastructure-as-code for cloud resources:

- `terraform/authentik/` - Identity provider infra
- `terraform/garage/` - S3 storage infra (R2 clone)
- `terraform/uptimerobot/` - Monitoring infra

See [tofu.md](../../tofu.md) for usage.

---

## Adding a New Application

1. Create app config in `kubernetes/apps/${cluster}/`
2. Add `kustomization.yaml` with namespace + Flux kustomization reference
3. Create `ks.yaml` referencing `HelmRelease`
4. Add any secrets to 1Password, reference via `external-secrets`
5. Commit and push - Flux will auto-apply

---

## Key Files

| Path | Purpose |
|------|---------|
| `kubernetes/apps/base/` | Shared app configurations |
| `kubernetes/clusters/` | Flux cluster-specific configs |
| `kubernetes/components/` | Reusable k8s components |
| `talos/` | Talos machine configurations |
| `bootstrap/` | Bootstrap templates |
| `hack/` | Operational scripts |
