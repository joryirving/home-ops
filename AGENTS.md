# Home Operations - AI Assistant Guide

This is a **Home Kubernetes cluster monorepo** managed with GitOps (Flux, Renovate, GitHub Actions).

## Repository Structure

```
home-ops/
├── .agents/             # AI instructions & skills
│   ├── instructions/    # YAML sorting rules
│   └── skills/          # Reusable agent skills (e.g. add-app)
├── .github/             # GitHub Actions workflows & evidence providers
├── .renovate/           # Local Renovate config presets
├── .taskfiles/          # Task (taskfile.dev) operational commands
├── ansible/             # Ansible for the Columbina VPS
├── bootstrap/           # Bootstrap templates (helmfile, minijinja)
├── docker/              # Compose apps on the Columbina VPS (towonel, gatus, ...)
├── docs/                # Markdown docs (mdBook-style SUMMARY.md)
├── hack/                # Operational scripts (see hack/README.md)
├── kubernetes/          # Kubernetes configurations (Flux-managed)
│   ├── apps/            # Application configs
│   │   ├── base/        # Shared base configs
│   │   ├── main/        # Main cluster overlay
│   │   ├── utility/     # Utility cluster overlay
│   │   └── test/        # Test cluster overlay
│   ├── clusters/        # Flux cluster definitions
│   └── components/      # Reusable k8s components
├── scripts/             # CI check scripts
├── talos/               # Talos Linux machine configs
└── terraform/           # OpenTofu IaC (external/infra services)
```

## Cluster Architecture

- **main** - 3x MS-01 + 1x Bosgame M5 (i9-13900H x3, Ryzen AI Max+ 395 x1, 128GB RAM), hyper-converged storage
- **utility** - 1x Bosgame P1 (Ryzen 7 5700U), low-power services
- **test** - 1x Beelink Mini-S (Celeron N5095), testing

## Key Technologies

| Category   | Tool                         | Purpose                                                                           |
| ---------- | ---------------------------- | --------------------------------------------------------------------------------- |
| GitOps     | Flux + flux-operator         | Deploys configs from Git to k8s; flux-operator manages the Flux instance itself   |
| CI         | Renovate + GitHub Actions    | Dependency updates, automation                                                    |
| Networking | cilium (eBPF)                | CNI, kube-proxy replacement, LB IPs via BGP (main, utility) or L2 (test)          |
| Networking | multus                       | Secondary pod networks (main, utility)                                            |
| Ingress    | Envoy Gateway                | Gateway API L7 ingress via `envoy-internal` / `envoy-external` (HTTPRoutes)       |
| Tunnel     | towonel-operator             | Public ingress via the Towonel edge on the Columbina VPS                          |
| DNS        | external-dns                 | Syncs HTTPRoutes to UniFi (`unifi-dns`) and Cloudflare (`cloudflare-dns`)         |
| TLS        | cert-manager                 | TLS certificate automation                                                        |
| Secrets    | external-secrets + 1Password | Secret management                                                                 |
| Storage    | Rook/Ceph (main)             | Distributed block storage                                                         |
| Storage    | openebs / democratic-csi     | `local-hostpath` storage class (openebs on main; democratic-csi on utility, test) |
| Backups    | kopiur                       | Kopia PVC backups to a filesystem repository on NFS (Voyager)                     |
| Images     | spegel (main)                | Local OCI mirror                                                                  |
| Upgrades   | tuppr                        | Talos and Kubernetes upgrades from `TalosUpgrade`/`KubernetesUpgrade` CRs         |
| IaC        | tofu-controller (utility)    | Runs the OpenTofu in `terraform/` on k8s                                          |
| Charts     | app-template (bjw-s)         | Common Helm chart used by most apps                                               |
| Sources    | OCIRepository                | Flux source for OCI Helm charts (preferred)                                       |
| Reviews    | konflate                     | Rendered-diff evidence provider for PR reviews                                    |

## GitOps Flow

```
Git push → Flux source sync → Kustomization → HelmRelease → k8s resources
```

Flux starts from `kubernetes/apps/<cluster>/` overlays. App manifests live in `kubernetes/apps/base/<namespace>/<app>/`; each cluster overlay is a Flux `Kustomization` at `kubernetes/apps/<cluster>/<namespace>/<app>.yaml` pointing to that base directory. Namespace is declared once per namespace in `kubernetes/apps/<cluster>/<namespace>/kustomization.yaml`; `kubernetes/components/replacements/ks.yaml` copies it to each overlay's `spec.targetNamespace`. A change under `kubernetes/apps/base/` can affect every cluster that includes the app.

## Conventions

- Component READMEs stay with components (e.g., `kubernetes/apps/base/kube-system/cilium/README.md`)
- Secrets stored in 1Password, referenced via `external-secrets`
- Apps use `HelmRelease` via Flux, rarely raw manifests
- Clusters are mostly identical except for app selections and sizing
- **AI instructions**: The reviewer loads trusted-base repository skills. `.agents/instructions/sorting.instructions.md` defines YAML sorting rules (including `app-template`-specific ordering). When editing YAML, follow the sorting instructions. `docs/src/notes/coding-loop.md` documents the coding loop (Dispatch + Courier); read it before changing `kubernetes/apps/base/llm/courier/` or Dispatch configuration.
- **Namespace component**: `kubernetes/components/namespace/` injects the Namespace resource and alerting rules; each namespace overlay (`kubernetes/apps/<cluster>/<namespace>/kustomization.yaml`) includes it once for all apps it lists. Helm chart sources are per-app: each app declares its own `OCIRepository` in `ocirepository.yaml`.
- **Namespace replacement**: `kubernetes/components/replacements/ks.yaml` propagates `spec.targetNamespace` into Flux Kustomizations automatically.
- **New apps**: Follow `.agents/skills/add-app/SKILL.md` for the complete workflow; create manifests in `base/` and an overlay in each requested cluster.
- **Postgres**: `kubernetes/components/postgres/` is the CloudNativePG component. Its README defines recovery bootstrap and the `components.postgres/cnpg=init` label for net-new databases. Treat changes to CNPG `Cluster` resources or bootstrap labels as data-loss-relevant.

## Common Operations

- **Add app**: Create base manifests in `kubernetes/apps/base/<namespace>/<app>/`, then cluster overlay `Kustomization` files for the requested clusters
- **Update app**: Merge renovate PR or manually edit and push
- **Troubleshoot**: Check `flux get all -n <namespace>`, `kubectl get events --sort-by=.lastTimestamp`
- **Scripts**: `hack/` contains operational scripts. See `hack/README.md` for the full list and usage.
- **Task operations**: The repo is driven by Taskfile. Run `task --list` to see all commands. Common tasks:
    - `task talos:apply-node CLUSTER=main NODE=<node>` — apply Talos config
    - `task talos:upgrade-k8s CLUSTER=main VERSION=<ver>` — upgrade Kubernetes
    - `task kubernetes:reconcile CLUSTER=main` — force Flux reconciliation
    - `task kubernetes:hr-restart CLUSTER=main` — restart failed HelmReleases
    - `task bootstrap:cluster CLUSTER=main` — bootstrap a fresh Talos cluster end to end
    - `task op:push` / `task op:pull` — sync kubeconfig/talosconfig with 1Password
    - `task workstation:brew` — install local workstation tools
- **Tool management**: `.mise.toml` pins `flate`; run `mise install` to set it up. Other task preconditions identify their required tools.
- **Validate locally**: Run `flate` before pushing GitOps changes:

    ```bash
    # Test Kustomizations + HelmReleases for a cluster
    flate test all --path ./kubernetes/clusters/main

    # Diff Kustomizations + HelmReleases against a baseline rev (changed-only)
    flate diff all --path ./kubernetes/clusters/main --base origin/main
    ```

- **Gateway policy namespace rule**: `ClientTrafficPolicy` and `EnvoyPatchPolicy` that target a `Gateway` must live in the same namespace as that `Gateway`. For `envoy-internal`, put those resources in `kubernetes/apps/base/network/envoy-gateway/config/` with namespace `network`. See that directory for examples.

## Documentation

- Main docs: `/docs/src/` (Markdown, mdBook-style `SUMMARY.md`)
- Component docs: README files co-located with components
- Terraform docs: `/terraform/tofu.md`
- Personal notes: `/docs/src/notes/`

## Adding Documentation

When adding architecture or operational docs, consider:

1. Put user-facing docs in `/docs/src/`
2. Keep component-specific docs with the component
3. Personal notes go in `/docs/src/notes/`

## PR Review Standards

Detailed review policy lives in [.agents/skills/home-ops-gitops-review/SKILL.md](.agents/skills/home-ops-gitops-review/SKILL.md). Load it for Flux, HelmRelease, OCIRepository, secrets, image updates, rendered manifests, or Talos/Kubernetes compatibility reviews. For Renovate PRs, load [.agents/skills/renovate-review/SKILL.md](.agents/skills/renovate-review/SKILL.md). It owns the upstream provenance, release-delta, security, and Renovate-specific verdict policy; do not duplicate it here.
