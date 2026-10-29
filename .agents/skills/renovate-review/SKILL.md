---
name: renovate-review
description: Review Renovate dependency updates in this Flux/GitOps home-ops repository, including Helm OCI charts, container tags/digests, Talos/Kubernetes, GitHub Actions, Terraform/OpenTofu, Docker Compose, and Renovate presets. Investigate rendered impact, upstream changes and actual repository dependencies before recommending a merge.
---

# Review a Renovate PR in home-ops

Determine **what changes on deployment and whether this repository relies on the old behavior**. Flux can reconcile `kubernetes/` changes soon after merge. The native reviewer catalogs this skill from the trusted base. Read it for Renovate PRs; it adds repository-specific investigation steps to the bundled reviewer. The repository's trusted AGENTS.md standards and home-ops-gitops-review skill remain authoritative.

## 1. Establish the update and deployment footprint

- Identify every dependency and old/new version, digest or chart tag. Renovate groups may contain several independent upgrades. A shared base under `kubernetes/apps/base/<namespace>/<app>/` can deploy to **main, utility and/or test** via overlays in `kubernetes/apps/<cluster>/`; look for every consuming overlay before judging impact.
- Distinguish **OCIRepository chart tag** updates, **container image/digest** updates, **HelmRelease values** changes, **Talos/Kubernetes** upgrades, **GitHub Actions**, **OpenTofu providers/modules**, **Docker Compose** and Renovate configuration. An OCI chart is pinned by `ref.tag` rather than a container-style `@sha256:` digest. Do not flag that as missing image pinning.
- The actual rendered resources, not the one-line git diff, determine most Helm/Flux compatibility risks.

## 2. Inspect the rendered change (when applicable)

The reviewer is configured with the **Konflate evidence provider and read-only MCP tools**, rather than the upstream example repository's `flate` setup. Prefer evidence already included in the review corpus:

- `mcp__konflate__get_pr_summary` with this PR number: affected resources and clusters, additions/removals, image changes, data-loss, immutable field, RBAC, `suspend`/`prune`, and render errors.
- `mcp__konflate__get_pr_diff` with this PR number when chart defaults, templates, selectors or Helm values could change rendered manifests while the git diff looks trivial.
- `mcp__konflate__list_pull_requests` only if necessary to establish whether this PR has render evidence. If Konflate did not render it, say **unverified**, never "unchanged" or "safe".
- For a local manual investigation the repository documents `flate diff all --path ./kubernetes/clusters/<cluster> --base origin/main`; do **not** claim to have run this command unless an independently allowed tool actually did. A SKILL.md does **not** grant shell or Kubernetes execution rights.

Pay special attention to changes in resource names, label **values** as well as keys, selectors, ports, services, RBAC, storage classes, CRDs, probes, immutable fields and persistent-volume behavior. Konflate may omit CRDs/Secret data; their absence from a render is not evidence of no change. One unrelated rendering failure is not proof that the upgraded chart fails.

For a digest-only container refresh with unchanged repository/tag, still verify upstream provenance and security; keep the final assessment short when the evidence is consistent. Don't invent Kubernetes breaking changes.

## 3. Verify upstream changes and security for EVERY update

**Mandatory, including patch and digest-only updates:** Independently identify the upstream project and inspect the actual upstream release or compare for the exact old → new range. Renovate's changelog, update-type label, package link, and a passing image-pull job are leads, not proof of safety. Scale the *depth and length* of the review to risk, not whether the checks happen.

1. **Provenance:** Distinguish the artifact registry/publisher, image build repository, and application's canonical source repository. Follow verified OCI `org.opencontainers.image.source` / revision metadata, chart metadata, Dockerfiles/build workflows, official project links or documented package mappings. Do not assume GHCR image and source share an owner/repository; don't treat a misleading Renovate homepage link as authoritative. For third-party rebuilt/mirrored images, determine which upstream source version/commit was packaged and whether the target digest corresponds to the published artifact. A pullable digest is not evidence of source identity, an authentic build, or security. If mapping cannot be established, say so and do not claim provenance was verified.
2. **Release delta:** Read upstream release notes/changelog for the target version **even when Renovate supplies none**. If the release has no notes, read upstream tags, compare commits, merged PRs and relevant changelog/history between old and new versions. Follow linked fixes/issues. For chart releases inspect both chart changes and application `appVersion`; for a separate image-build repository inspect the image changes *and* the underlying app release. If there is no trustworthy source/compare, clearly state that the delta remains unverified.
3. **Security:** Check upstream GitHub Security Advisories/GHSA, CVEs (including NVD or OSV where accessible), upstream security announcements and the relevant release/issue/PR discussions for vulnerabilities **fixed, introduced, disclosed, or still unfixed** in the target version and versions crossed. Match affected-version ranges, vulnerable component/code path, exploit prerequisites and the deployment's exposure; distinguish confirmed findings from allegations or vague issue titles. Check whether a claimed fix is actually present in the target release/branch. For components handling secrets, auth, network ingress, proxying, code execution, supply-chain builds or infrastructure control, prioritize these checks and follow security-linked commits.
4. **Deployment relevance:** Match security and breaking changes to the repository's actual configuration and blast radius. A security fix may make upgrading urgent; a new vulnerability or unverified origin may justify holding the update. Do not label an update safe purely because it is a patch or because no advisory appears in the Renovate PR.
5. **Evidence:** Give direct upstream links (release/compare and relevant advisory or issue) and explicitly distinguish *checked, not found* from *could not check*. Never assert there are no vulnerabilities on the basis of a single search, or imply an unperformed registry signature/attestation verification happened.

**Decision policy:** A confirmed, applicable high-severity regression, exploitable security issue, malicious/untrusted artifact, or serious compatibility break is a blocker. Missing release notes alone are **not** a blocker if upstream commits provide adequate evidence. Unresolved provenance for a security-sensitive artifact, credible material security uncertainty, or inability to establish what code is being deployed requires **manual verification before approval**, not a fabricated clean verdict. Routine evidence gaps without a concrete risk should be explained briefly and proportionately. Do not invent findings to fill a quota.

- **OCI chart:** Find its source in the app's `ocirepository.yaml`, follow the publisher's chart releases/templates and compare versions. For mirrored `ghcr.io/home-operations/charts-mirror/<chart>`, use `home-operations/charts-mirror` metadata to locate the real chart source. When the chart's `appVersion` changes, inspect the underlying application's release notes too.
- **Container image:** Resolve upstream from the image owner or `org.opencontainers.image.source` metadata. For `ghcr.io/home-operations/*`, also inspect `home-operations/containers` build definitions/history for digest-only changes. Check image revision/source/created metadata when available.
- **Talos / Kubernetes:** Check each affected cluster's `talos/<cluster>/machineconfig.yaml.j2` installer image and the `TalosUpgrade`/`KubernetesUpgrade` resources managed by tuppr. Verify the **specific Talos release supports the target Kubernetes version** against the published Sidero/Talos compatibility matrix before concluding compatibility. A patch bump alone is not proof.
- **GitHub Action / Renovate preset / OpenTofu:** Read the upstream release/compare, then verify this repository's `.github/workflows/` inputs/outputs, `.renovate/` rules, `terraform/` constraints/state/migrations, or `docker/` runtime configuration as applicable.
- Follow referenced upstream issues/PRs when a changelog only says "See #123". Don't infer changed defaults or a migration solely from a release-note headline.

Check raised minimum versions, removed APIs or fields, changed auth/storage/network defaults, one-way migrations, and security advisories relevant to the deployed configuration. If an upstream source cannot be verified, label the evidence gap honestly.

## 4. Search for repository-specific exposure

Search the **actual consumers** of anything removed or renamed, not just whether the new value is explicitly set:

- Under `kubernetes/`, inspect selectors and labels in Prometheus/ServiceMonitors, alerts and dashboards, NetworkPolicies, HTTPRoutes/Gateway policies, PDBs, Flux `dependsOn`/`healthChecks`, `values`/`valuesFrom`/`postRenderers`, service DNS and CRD instances.
- Trace base-to-overlay usage across **main / utility / test**. Cilium, Envoy Gateway, external-secrets, Rook/Ceph, PostgreSQL and storage-provider updates merit close inspection for compatibility and data safety where affected.
- For `app-template` or shared chart changes, look for multiple affected HelmReleases. Chart defaults can change even when values in this repo do not.
- In `terraform/`, `ansible/`, `docker/`, `.github/` and `.renovate/`, search the corresponding consumers rather than assuming everything is a Kubernetes release.

A documented home-ops convention is **not** a finding. In particular, `metadata.namespace` intentionally comes from namespace overlays/replacements, not inline on HelmReleases or Flux Kustomizations, and OCI chart tags are not container image digests. Existing exceptions in `AGENTS.md` remain valid.

## 5. Verdict and evidence

- Respect `AGENTS.md` and the reviewer's deterministic `must_check` requirements. Do not replace or weaken review gates. A breaking change with **no affected consumer in this repository** is a brief observation, not an invented blocker.
- A finding must identify the **changed line**, the **affected consumer/path**, the concrete failure mode, and supporting rendered or upstream evidence. Confirm a replacement name/value from upstream manifests rather than guessing an auto-fix.
- Escalate documented risks: unsupported Talos/Kubernetes pairings, CRD/schema incompatibilities, data-loss/storage mutations, new security relaxations, unexpected suspend/prune, and resource/selector renames that break live consumers. For uncertain evidence, report **Unknown / needs verification** instead of asserting a failure or successful test.
- For an ordinary same-tag digest refresh, perform the required upstream/security checks but keep the review **compact**: recommendation, what changed, and any meaningful caveat. Skip empty Standards Compliance, Linked Issue Fit, Tool Harness or evidence sections, and don't dump internal planner diagnostics.
- No fabricated Konflate results, upstream comparisons, tool calls or post-merge checks. A skill describes how to review; **only configured tools may be used**, and nothing here authorizes shell commands or writes.
