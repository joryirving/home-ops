# Home Operations - AI Assistant Guide

This is a **Home Kubernetes cluster monorepo** managed with GitOps (Flux, Renovate, GitHub Actions).

## Repository Structure

```
home-ops/
├── kubernetes/           # Kubernetes configurations (Flux-managed)
│   ├── apps/            # Application configs
│   │   ├── base/        # Shared base configs
│   │   ├── main/        # Main cluster overlay
│   │   ├── utility/     # Utility cluster overlay
│   │   └── test/        # Test cluster overlay
│   ├── clusters/        # Flux cluster definitions
│   └── components/      # Reusable k8s components
├── talos/               # Talos Linux machine configs
├── terraform/           # OpenTofu/Terraform IaC (cloud infra)
├── bootstrap/           # Bootstrap templates (helmfile.d, templates)
├── hack/                # Operational scripts
└── docs/                # mdBook documentation
```

## Cluster Architecture

- **main** - 3x MS-01 + 1x Bosgame M5 (i9-13900H x3, Ryzen AI Max+ 395 x1, 128GB RAM), hyper-converged storage
- **utility** - 1x Bosgame P1 (Ryzen 7 5700U), low-power services
- **test** - 1x Beelink Mini-S (Celeron N5095), testing

## Key Technologies

| Category   | Tool                         | Purpose                           |
|------------|------------------------------|-----------------------------------|
| GitOps     | Flux                         | Deploys configs from Git to k8s   |
| CI         | Renovate + GitHub Actions    | Dependency updates, automation    |
| Networking | cilium (eBPF)                | CNI, BGP, service mesh            |
| Ingress    | Envoy Gateway                | L7 proxy, ingress controller      |
| DNS        | external-dns                 | Syncs ingress to Cloudflare/UniFi |
| Secrets    | external-secrets + 1Password | Secret management                 |
| Storage    | Rook/Ceph + volsync          | Distributed storage + backups     |
| Images     | spegel                       | Local OCI mirror                  |
| IaC        | tofu-controller              | Terraform on k8s                  |

## GitOps Flow

```
Git push → Flux source sync → Kustomization → HelmRelease → k8s resources
```

Flux recursively searches `kubernetes/${cluster}/apps/` for `kustomization.yaml` files. Each must define a namespace and Flux kustomization (`ks.yaml`).

## Conventions

- Component READMEs stay with components (e.g., `kubernetes/apps/base/cilium/README.md`)
- Secrets stored in 1Password, referenced via `external-secrets`
- SOPS used for encrypting sensitive values in Git
- Apps use `HelmRelease` via Flux, rarely raw manifests
- Clusters are mostly identical except for app selections and sizing

## Common Operations

- **Add app**: Create in `kubernetes/apps/${cluster}/` with kustomization + HelmRelease
- **Update app**: Merge renovate PR or manually edit and push
- **Troubleshoot**: Check `flux get all -n <namespace>`, `kubectl get events --sort-by=.lastTimestamp`
- **Scripts**: `hack/` contains operational scripts (cert-extract.sh, delete-stuck-ns.sh, etc.)
- **Validate locally**: Run `flux-local` before pushing GitOps changes:
  ```bash
  /Users/joryirving/.local/share/mise/installs/pipx-flux-local/8.1.0/bin/flux-local test --enable-helm --path ./kubernetes/clusters/main
  ```
- **Gateway policy namespace rule**: `ClientTrafficPolicy` and `EnvoyPatchPolicy` that target a `Gateway` must live in the same namespace as that `Gateway`. For `envoy-internal`, put those resources in `kubernetes/apps/base/network/envoy-gateway/config/` with namespace `network`.

## Documentation

- Main docs: `/docs/src/` (mdBook)
- Component docs: README files co-located with components
- Terraform docs: `/terraform/tofu.md`
- Personal notes: `/docs/src/notes/`

## Adding Documentation

When adding architecture or operational docs, consider:
1. Put user-facing docs in `/docs/src/`
2. Keep component-specific docs with the component
3. Personal notes go in `/docs/src/notes/`

## PR Review Standards

When reviewing Renovate PRs, enforce these criteria:

### HelmRelease Requirements
- All applications MUST use `HelmRelease` via Flux, not raw manifests
- Must include `spec.chart.spec.version` for pinned chart versions outside of `app-template`
- Must include `spec.interval` for reconciliation frequency
- Resource limits (CPU/memory) SHOULD be specified for production workloads, but this is not a hard requirement
- `valuesFrom` should reference ConfigMaps/Secrets, not inline values

### Secret Management Rules
- **NEVER** commit plain-text secrets or credentials in Git
- All secrets MUST use `external-secrets` with 1Password backend
- SOPS encryption required for any sensitive values in Git
- If a PR introduces a new secret, verify it's external-secrets backed

### Image & Digest Policy
- Prefer `@sha256:` digests over version tags for reproducibility
- For tag-only updates, verify OCI metadata (revision/source/created)
- If revision changes between digests, ensure it's intentional
- Reject updates from untrusted registries (must be allowlisted)
- Preferred registries: GHCR.io, registry.k8s.io, Docker Hub (fallback)
- Avoid Docker Hub for critical infrastructure components

### Cluster-Specific Policies
- **main cluster** (production): Strict validation - all standards must be met
- **utility cluster** (low-power services, production): Strict validation - all standards must be met
- **test cluster** (testing): Can accept bleeding-edge versions, still enforce secrets policy

### Breaking Change Detection
Always `request_changes` if:
- API version changes (e.g., `apiVersion: apps/v1beta1` → `apps/v1`)
- Deprecated field usage introduced
- Major version bumps without justification
- CRD changes or custom resource modifications
- Network policy or security context relaxations

### Required Evidence for Approval
Before approving, verify:
1. Release notes/changelog mention the upgrade
2. GitHub compare shows expected changes
3. Version aligns with what Renovate reported
4. No breaking changes identified in release notes
5. Security advisories don't apply to this version

_Flux automatically reconciles changes once the PR is merged._
