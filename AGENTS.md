# Home Operations - AI Assistant Guide

This is a **Home Kubernetes cluster monorepo** managed with GitOps (Flux, Renovate, GitHub Actions).

## Repository Structure

```
home-ops/
├── .agents/             # AI instructions & skills
│   ├── instructions/    # PR review system prompt, YAML sorting rules
│   └── skills/          # Reusable agent skills (e.g. add-app)
├── .github/             # GitHub Actions workflows & evidence providers
├── .renovate/           # Local Renovate config presets
├── .taskfiles/          # Task (taskfile.dev) operational commands
├── bootstrap/           # Bootstrap templates (helmfile, minijinja)
├── docs/                # mdBook documentation
├── hack/                # Operational scripts (see hack/README.md)
├── kubernetes/          # Kubernetes configurations (Flux-managed)
│   ├── apps/            # Application configs
│   │   ├── base/        # Shared base configs
│   │   ├── main/        # Main cluster overlay
│   │   ├── utility/     # Utility cluster overlay
│   │   └── test/        # Test cluster overlay
│   ├── clusters/        # Flux cluster definitions
│   └── components/      # Reusable k8s components
├── talos/               # Talos Linux machine configs
└── terraform/           # OpenTofu/Terraform IaC (cloud infra)
```

## Cluster Architecture

- **main** - 3x MS-01 + 1x Bosgame M5 (i9-13900H x3, Ryzen AI Max+ 395 x1, 128GB RAM), hyper-converged storage
- **utility** - 1x Bosgame P1 (Ryzen 7 5700U), low-power services
- **test** - 1x Beelink Mini-S (Celeron N5095), testing

## Key Technologies

| Category   | Tool                         | Purpose                                                                         |
| ---------- | ---------------------------- | ------------------------------------------------------------------------------- |
| GitOps     | Flux + flux-operator         | Deploys configs from Git to k8s; flux-operator manages the Flux instance itself |
| CI         | Renovate + GitHub Actions    | Dependency updates, automation                                                  |
| Networking | cilium (eBPF)                | CNI, BGP, service mesh                                                          |
| Ingress    | Envoy Gateway                | L7 proxy, ingress controller                                                    |
| DNS        | external-dns                 | Syncs ingress to Cloudflare/UniFi                                               |
| TLS        | cert-manager                 | TLS certificate automation                                                      |
| Secrets    | external-secrets + 1Password | Secret management                                                               |
| Storage    | Rook/Ceph + volsync          | Distributed storage + backups                                                   |
| Images     | spegel                       | Local OCI mirror                                                                |
| IaC        | tofu-controller              | Terraform on k8s                                                                |
| Charts     | app-template (bjw-s)         | Common Helm chart used by most apps                                             |
| Sources    | OCIRepository                | Flux source for OCI Helm charts (preferred)                                     |
| Reviews    | konflate                     | Rendered-diff evidence provider for PR reviews                                  |

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
- **AI instructions**: `.agents/instructions/pr-review.instructions.md` is the live system prompt for the AI PR reviewer. `.agents/instructions/sorting.instructions.md` defines YAML sorting rules (including `app-template`-specific ordering). When editing YAML, follow the sorting instructions.
- **Namespace component**: `kubernetes/components/namespace/` injects the Namespace resource, alerting rules, and the shared `app-template` `OCIRepository` into every app via kustomize components.
- **Namespace replacement**: `kubernetes/components/replacements/ks.yaml` propagates `spec.targetNamespace` into Flux Kustomizations automatically.

## Common Operations

- **Add app**: Create in `kubernetes/apps/${cluster}/` with kustomization + HelmRelease
- **Update app**: Merge renovate PR or manually edit and push
- **Troubleshoot**: Check `flux get all -n <namespace>`, `kubectl get events --sort-by=.lastTimestamp`
- **Scripts**: `hack/` contains operational scripts. See `hack/README.md` for the full list and usage.
- **Task operations**: The repo is driven by Taskfile. Run `task --list` to see all commands. Common tasks:
    - `task talos:apply-node CLUSTER=main NODE=<node>` — apply Talos config
    - `task talos:upgrade-k8s CLUSTER=main VERSION=<ver>` — upgrade Kubernetes
    - `task kubernetes:reconcile CLUSTER=main` — force Flux reconciliation
    - `task kubernetes:hr-restart CLUSTER=main` — restart failed HelmReleases
    - `task volsync:snapshot CLUSTER=main NS=<ns> APP=<app>` — trigger VolSync snapshot
    - `task volsync:restore CLUSTER=main NS=<ns> APP=<app> PREVIOUS=<snap>` — restore from backup
    - `task bootstrap:talos CLUSTER=main` — bootstrap a fresh Talos cluster
    - `task op:push` / `task op:pull` — sync kubeconfig/talosconfig with 1Password
    - `task workstation:brew` — install local workstation tools
- **Tool management**: `.mise.toml` manages required tools (e.g. `flate`, `minijinja-cli`). Run `mise install` to set up the environment.
- **Validate locally**: Run `flate` before pushing GitOps changes:

    ```bash
    # Test Kustomizations + HelmReleases for a cluster
    flate test all --path ./kubernetes/clusters/main

    # Diff against a baseline (e.g., main branch)
    git worktree add --detach /tmp/baseline origin/main
    flate diff ks --path ./kubernetes/clusters/main --path-orig /tmp/baseline/kubernetes/clusters/main
    flate diff hr --path ./kubernetes/clusters/main --path-orig /tmp/baseline/kubernetes/clusters/main
    git worktree remove /tmp/baseline --force
    ```

- **Gateway policy namespace rule**: `ClientTrafficPolicy` and `EnvoyPatchPolicy` that target a `Gateway` must live in the same namespace as that `Gateway`. For `envoy-internal`, put those resources in `kubernetes/apps/base/network/envoy-gateway/config/` with namespace `network`. See that directory for examples.

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

When reviewing Renovate PRs, enforce these criteria. Reviews may include konflate rendered-diff evidence (cluster impact, data-loss cautions, image changes). Treat blocker-level findings as high-priority signals.

### HelmRelease Requirements

- All applications MUST use `HelmRelease` via Flux, not raw manifests
- HelmReleases MUST use `spec.chartRef` pointing to an `OCIRepository` with a pinned `ref.tag`. The only exception is `llmkube`, which uses the legacy `spec.chart` pattern.
- For `app-template`-based apps, reference the shared `OCIRepository` named `app-template` (injected by the namespace component). Do not create per-app `OCIRepository` resources for `app-template`.
- Per-app `OCIRepository` resources (for non-`app-template` charts) MUST live in a dedicated `ocirepository.yaml` file alongside the `HelmRelease`, not inline in `helmrelease.yaml`. Add `./ocirepository.yaml` to the app's `kustomization.yaml`.
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
- Talos machine configs (`talos/*/machineconfig.yaml.j2`) store `op://` references in Git that are resolved at runtime via `op inject`. This is the intended pattern for machine-level secrets; do not replace them with `external-secrets`

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

This cluster runs on **Talos Linux**, which pins the node OS and the kubelet together. The deployed Talos version is in `machine.install.image` inside `talos/main/machineconfig.yaml.j2` (format: `factory.talos.dev/metal-installer/<schematic>:<version>`). When a PR bumps the Kubernetes version (the kubelet image, a `KubernetesUpgrade` resource, or the `kubernetes` Renovate group), you MUST:

1. Read the deployed Talos version from `talos/main/machineconfig.yaml.j2`.
2. Confirm the new Kubernetes version is supported on that Talos release against Talos's published support matrix — search the web for "talos <version> kubernetes support matrix" (the docs live at `docs.siderolabs.com`; the old `talos.dev` matrix URLs 404) and fetch it.
3. Cite the matrix in the review. Do not approve a Kubernetes bump on "patch release" reasoning without confirming Talos supports it — an unchecked matrix is an Unknown, not an approval.

_Flux automatically reconciles changes once the PR is merged._
