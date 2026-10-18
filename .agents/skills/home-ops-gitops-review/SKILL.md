---
name: home-ops-gitops-review
description: Review home-ops Flux, HelmRelease, OCIRepository, image, secret, cluster-upgrade, Talos/Kubernetes compatibility, and rendered-manifest changes.
---

# Home-ops GitOps review

AGENTS.md is the general repository guide. Use this skill for changes under kubernetes/, talos/, Terraform/OpenTofu, or deployment workflows. Flux reconciles merged changes automatically, so assess the actual rendered cluster effect, not only the raw YAML diff.

## Flux and Helm conventions

- New application workloads should use a Flux HelmRelease, not a raw Deployment or StatefulSet. Existing config-only and operator-CR directories may intentionally use raw manifests; inspect the repository's documented exceptions before flagging them.
- A HelmRelease uses spec.chartRef to point to an OCIRepository with a pinned ref.tag. Each app normally owns an adjacent ocirepository.yaml named after the app and includes it from its kustomization.yaml. Do not inline the OCIRepository in helmrelease.yaml or rely on an injected shared repository.
- Known exceptions: cluster flux-instance HelmReleases may define their OCIRepository inline, and blackbox-exporter-vpn intentionally reuses blackbox-exporter's OCIRepository.
- HelmRelease and Flux Kustomization resources intentionally omit metadata.namespace. Namespace overlays set kustomize's namespace, and the replacements component supplies targetNamespace. Do not report the missing inline namespace as a defect.
- Include spec.interval. Resource requests/limits are recommended for production workloads but are not a hard gate. Inline spec.values is the norm; use valuesFrom only when a ConfigMap or Secret is needed.

## Secrets, images, and cluster policy

- Never commit plaintext credentials. Application secrets use external-secrets with the 1Password backend. Talos machine configs intentionally store op:// references that are resolved at runtime by op inject; do not replace that pattern with external-secrets.
- Prefer sha256 digests for container images. OCI chart artifacts are pinned by tag/version, not container-style digests. For tag-only updates, verify upstream OCI revision/source/created metadata; confirm any revision difference between digests is intentional.
- Reject untrusted registries. Preferred registries are GHCR and registry.k8s.io, with Docker Hub as fallback; avoid Docker Hub for critical infrastructure.
- Main and utility are production clusters and require strict validation. The test cluster may accept bleeding-edge versions, but secret policy still applies.

## Blocking change detection

Request changes for unjustified major upgrades, introduced deprecated APIs, breaking API-version changes, CRD/custom-resource changes without compatibility evidence, network-policy or security-context relaxation, and rendered diffs that introduce a new Flux suspend/prune artifact. Do not mistake documented exceptions for regressions.

## Evidence required before approval

For Helm chart and container-image upgrades, verify the actual upstream release notes or changelog, GitHub compare, reported version, breaking changes, and relevant security advisories. Do not rely on the Renovate PR description alone. Use Konflate's rendered manifest diff and upgrade-impact evidence to establish the real blast radius. Missing advisory or rendered evidence is Unknown, not a clean result; treat render failures as blockers when the manifests may not apply.

For Kubernetes/Talos upgrades, identify every affected cluster, read its Talos installer version from the UnattendedInstallConfig document in talos/<cluster>/machineconfig.yaml.j2, and verify the proposed Kubernetes version against the published Talos support matrix. Cite the matrix in the review. A patch-version bump is not proof of compatibility; if the matrix cannot be checked, report Unknown rather than approving by assumption.
