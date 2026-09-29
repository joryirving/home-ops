# Architecture

## High-Level Overview

This repository is a **Home Operations monorepo** managing 3 Kubernetes clusters via GitOps:

| Cluster   | Purpose                                        | Hardware                                                                      |
| --------- | ---------------------------------------------- | ----------------------------------------------------------------------------- |
| `main`    | Production workloads + hyper-converged storage | 3x MS-01 + 1x Bosgame M5 (i9-13900H x3, Ryzen AI Max+ 395 x1, 128GB RAM each) |
| `utility` | Low-power services                             | Bosgame P1 (Ryzen 7 5700U)                                                    |
| `test`    | Testing changes                                | Beelink Mini-S (Celeron N5095)                                                |

---

## GitOps Flow

```
Git Repository → Flux (GitOps Operator) → Kubernetes Clusters
```

1. **Code pushed** to GitHub
2. **Renovate** scans for dependency updates, creates PRs
3. **PRs merged** to main branch
4. **Flux** detects changes via Git source
5. **Flux** applies `kubernetes/apps/${cluster}`: one Flux `Kustomization` per app, each pointing at `kubernetes/apps/base/<namespace>/<app>`
6. **Flux** applies `HelmRelease` and other resources to the cluster

### Directory Structure (Apps)

```
kubernetes/apps/
├── base/           # Common app configs (shared across clusters)
├── main/           # Main cluster overlay
├── utility/        # Utility cluster overlay
└── test/           # Test cluster overlay
```

Each namespace directory in a cluster overlay (`kubernetes/apps/<cluster>/<namespace>/`) has a `kustomization.yaml` that pulls in `kubernetes/components/namespace` and lists one Flux `Kustomization` per app (`<app>.yaml`). Each of those points at `kubernetes/apps/base/<namespace>/<app>/`, which holds the app's `HelmRelease`, its `OCIRepository` (`ocirepository.yaml`) and any other manifests.

### Flux Reconciliation Chain

```
GitRepository flux-system (kubernetes/clusters/<cluster>)
    ↓ (kustomize.toolkit.fluxcd.io)
Kustomization kubernetes/apps/<cluster>/<namespace>/<app>.yaml
    ↓ applies kubernetes/apps/base/<namespace>/<app>/
OCIRepository (source.toolkit.fluxcd.io) ← HelmRelease spec.chartRef
    ↓ (helm.toolkit.fluxcd.io)
Kubernetes Resources (Deployment, Service, etc.)
```

---

## Core Components

### Networking (cilium)

- **cilium** provides eBPF-based CNI networking
- Replaces kube-proxy for service load balancing
- LoadBalancer IPs: BGP peering with the UniFi UDM-SE on main and utility; L2 announcements on test
- **multus** adds secondary pod networks on main and utility
- Hubble for observability

### Ingress & DNS

```
Internet → Cloudflare → Columbina (OVH VPS, Towonel edge) → Towonel tunnel → envoy-external Gateway
LAN      → UDM-SE DNS → envoy-internal / envoy-external Gateway

cloudflare-dns (external-dns): envoy-external HTTPRoutes + DNSEndpoints → Cloudflare
unifi-dns (external-dns):      HTTPRoutes + Services                   → UniFi UDM-SE
```

- **Envoy Gateway** implements the Gateway API for L7 ingress via the `envoy-internal` and `envoy-external` Gateways; there are no `Ingress` objects
- Apps attach an `HTTPRoute` to `envoy-internal` (private) or `envoy-external` (public)
- **towonel-operator** creates the cluster's Towonel tunnel and routes `envoy-external` traffic through it

### Secrets Management

```
1Password → external-secrets → Kubernetes Secrets
                   ↑
            1Password Connect (onepassword-connect)
```

- **external-secrets** fetches secrets from 1Password via Connect
- No encrypted secrets live in Git: Talos machine configs hold `op://` references resolved with `op inject`, and bootstrap secrets come from `bootstrap/kustomize/secrets.yaml.tpl` the same way
- **cert-manager** handles automatic TLS certificates

### Storage

- **Rook/Ceph** provides distributed block storage (RBD) on main
- **openebs** (main) and **democratic-csi** (utility, test) provide the `local-hostpath` storage class
- **kopiur** backs up PVCs with Kopia into a filesystem repository on an NFS share from Voyager
- **spegel** provides a local OCI image mirror on main
- Voyager NAS serves NFS/SMB shares via Unraid

### CI/CD

- **flux-operator** manages each cluster's Flux install through a `FluxInstance`
- **actions-runner-controller** runs self-hosted GitHub Actions runners
- **tuppr** runs Talos and Kubernetes upgrades from `TalosUpgrade`/`KubernetesUpgrade` resources
- **tofu-controller** runs OpenTofu from within the utility cluster (IaC)

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
                          │
                    ┌─────▼─────┐
                    │ Columbina │ (OVH VPS, Towonel edge)
                    └─────┬─────┘
                          │ Towonel tunnel (towonel-operator)
          ┌───────────────┼───────────────┐
          │               │               │
    ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
    │   Main    │   │  Utility  │   │   Test    │
    │  Cluster  │   │  Cluster  │   │  Cluster  │
    └─────┬─────┘   └─────┬─────┘   └─────┬─────┘
          │ Cilium BGP    │ Cilium BGP    │ Cilium L2
    ┌─────▼───────────────▼───────────────▼─────┐
    │     UniFi UDM-SE (Router/DHCP/DNS)        │
    └───────────────────────────────────────────┘
```

---

## Cluster Bootstrap

`task bootstrap:cluster CLUSTER=<cluster>` runs the whole sequence (`.taskfiles/bootstrap/Taskfile.yaml`):

1. Applies Talos configs to the nodes and bootstraps etcd via `talosctl`
2. Fetches the kubeconfig
3. Applies namespaces and secrets (`bootstrap/kustomize/secrets.yaml.tpl`, rendered with `minijinja-cli` and piped through `op inject`) and the CRDs from `bootstrap/helmfile/crds.yaml`
4. Syncs the core apps in `bootstrap/helmfile/apps.yaml`: cilium, coredns, cert-manager, external-secrets, onepassword-connect, flux-operator and flux-instance
5. The `FluxInstance` syncs `kubernetes/clusters/<cluster>` and Flux takes over

---

## Terraform/OpenTofu

External and infrastructure services managed with OpenTofu:

- `terraform/authentik/` - Identity provider config
- `terraform/garage/` - S3 buckets and keys (R2 clone)
- `terraform/uptimerobot/` - External monitors

tofu-controller on the utility cluster applies these from an OCI artifact published whenever `terraform/` changes on `main`. See [tofu.md](../../terraform/tofu.md) for usage.

---

## Adding a New Application

Follow `.agents/skills/add-app/SKILL.md`. In short:

1. Create `kubernetes/apps/base/<namespace>/<app>/` with `kustomization.yaml`, `helmrelease.yaml` and `ocirepository.yaml`
2. Add a Flux `Kustomization` at `kubernetes/apps/<cluster>/<namespace>/<app>.yaml` pointing at that directory, for each target cluster
3. List `./<app>.yaml` in `kubernetes/apps/<cluster>/<namespace>/kustomization.yaml`
4. Add any secrets to 1Password, reference via `external-secrets`
5. Commit and push - Flux will auto-apply

---

## Key Files

| Path                     | Purpose                       |
| ------------------------ | ----------------------------- |
| `kubernetes/apps/base/`  | Shared app configurations     |
| `kubernetes/clusters/`   | Flux cluster-specific configs |
| `kubernetes/components/` | Reusable k8s components       |
| `talos/`                 | Talos machine configurations  |
| `bootstrap/`             | Bootstrap templates           |
| `hack/`                  | Operational scripts           |
| `terraform/`             | OpenTofu configurations       |
| `.taskfiles/`            | Task (taskfile.dev) commands  |
| `.agents/`               | AI instructions and skills    |
| `docs/`                  | Documentation                 |
