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
| ---------- | ---------------------------- | --------------------------------- |
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
- **Validate locally**: Run `flate` (auto-installed via `.mise.toml`) before pushing GitOps changes:

    ```bash
    # Test Kustomizations + HelmReleases for a cluster
    flate test ks --path ./kubernetes/clusters/main

    # Diff against a baseline (e.g., main branch)
    git worktree add --detach /tmp/baseline origin/main
    flate diff ks --path ./kubernetes/clusters/main --path-orig /tmp/baseline/kubernetes/clusters/main
    flate diff hr --path ./kubernetes/clusters/main --path-orig /tmp/baseline/kubernetes/clusters/main
    git worktree remove /tmp/baseline --force
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

### Namespace Convention

- `metadata.namespace` is **never** set inline on `HelmRelease` or `Kustomization` resources — this is intentional, not a violation
- The namespace is injected at build time by kustomize's `namespace:` directive in the per-app `kustomization.yaml` (e.g., `namespace: llm`)
- For Flux `Kustomization` resources, `spec.targetNamespace` is propagated automatically via the replacement component at `kubernetes/components/replacements/ks.yaml`
- Reviewers MUST NOT flag missing `metadata.namespace` on these resources as an issue

### Secret Management Rules

- **NEVER** commit plain-text secrets or credentials in Git
- All secrets MUST use `external-secrets` with 1Password backend
- SOPS encryption required for any sensitive values in Git
- If a PR introduces a new secret, verify it's external-secrets backed

### Image & Digest Policy

- Prefer `@sha256:` digests over version tags for reproducibility (container images only)
- OCI artifacts (e.g., Helm charts pulled via `OCIRepository`) are exempt: pin by tag/version, since they don't support SHA-tag references the same way container images do
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

For Helm chart and container image upgrades, you **must** use tool requests (e.g., `gh_api`) to fetch release notes, changelogs, and upstream metadata from the source repository. Do not rely on the PR description alone — verify against the actual upstream release.

### Kubernetes ↔ Talos compatibility

This cluster runs on **Talos Linux**, which pins the node OS and the kubelet together. The deployed Talos version is the installer image in `talos/main/machineconfig.yaml.j2` (the `factory.talos.dev/installer:<version>` reference). When a PR bumps the Kubernetes version (the kubelet image, a `KubernetesUpgrade` resource, or the `kubernetes` Renovate group), you MUST:

1. Read the deployed Talos version from `talos/main/machineconfig.yaml.j2`.
2. Confirm the new Kubernetes version is supported on that Talos release against Talos's published support matrix — search the web for "talos <version> kubernetes support matrix" (the docs live at `docs.siderolabs.com`; the old `talos.dev` matrix URLs 404) and fetch it.
3. Cite the matrix in the review. Do not approve a Kubernetes bump on "patch release" reasoning without confirming Talos supports it — an unchecked matrix is an Unknown, not an approval.

_Flux automatically reconciles changes once the PR is merged._
