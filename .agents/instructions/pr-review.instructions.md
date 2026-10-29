# Home-ops PR review conventions

This file is appended by the AI PR Review workflow as general home-ops review context. The action owns its default review instructions and output schema. Detailed GitOps policy lives in the home-ops-gitops-review skill; upstream-investigation steps for Renovate PRs live in the renovate-review skill and are loaded on demand by the native repository-skill loader.

## Home-ops conventions

The conventions in the repository's `AGENTS.md` are authoritative for this project. Repository-specific conventions documented there override generic Kubernetes, Helm, Flux, or GitOps linting heuristics.

If a pattern is explicitly documented as intentional in `AGENTS.md` (or in the conventions listed below), do not surface it as a concern, warning, or "for awareness" note in the review.

### Documented conventions to honour without flagging

Load the home-ops-gitops-review skill for HelmRelease, namespace propagation, OCI artifact pinning, secret management, image digests, and cluster-specific policy. Do not duplicate its rules here; keep that skill as the single detailed source of truth.

### Compact Renovate digest-only reviews

For Renovate digest-only container image updates where the repository and tag are unchanged and the diff only changes `@sha256:` values, keep `review_markdown` compact.

Prefer:

- short recommendation
- changed files summary
- non-blocking caveats, if any

Do not include separate Standards Compliance, Linked Issue Fit, Evidence Provider Findings, Tool Harness Findings, or Unknowns sections unless they contain an actual warning or blocker.

Do not include internal planner/tool-harness diagnostics such as missing `requests[]` unless they affect the recommendation.

Missing OCI revision/source labels are a non-blocking caveat for same-tag digest refreshes when repository, tag, and created timestamp evidence are consistent.

### Konflate rendered-diff tools

A Konflate MCP server is configured. Konflate renders Helm charts and Kustomizations into their final Kubernetes manifests, so its rendered diff shows the actual cluster impact of a PR — not just the raw git changes. A rendered-diff summary is usually already injected into the corpus by the konflate evidence provider; use the MCP tools when you need more than the summary provides.

- `mcp__konflate__get_pr_summary` — pass the current PR `number`. Blast radius (added/changed/removed resources), caution lint (data-loss, immutable-field, RBAC, suspend/prune), image changes, render failures. Cheap and high-value; call this first if the evidence section is missing or stale.
- `mcp__konflate__get_pr_diff` — pass the current PR `number`. The full rendered manifest diff (Kubernetes YAML at PR head vs merge-base). Use it when the raw git diff hides the real change — e.g. a HelmRelease version bump or a one-line `values` change that fans out across many resources.
- `mcp__konflate__list_pull_requests` — lists the PRs konflate is tracking. If the current PR is not listed, rendered-diff evidence is unavailable; treat it as Unknown, not a clean result.

Konflate signals in the review: surface cautions as caveats or blockers by severity; treat render failures as blockers (the manifests may not apply cleanly). For Renovate digest-only bumps where konflate shows only `@sha256:` changes, keep the review compact (see above).

For every Renovate PR, load the renovate-review skill and perform its mandatory upstream provenance, release-delta and security investigation even when Renovate omits notes or the change is only a patch/digest. Check canonical application upstream separately from an image build/mirror repository. Apply its evidence/uncertainty policy. Perform the checks without verbose boilerplate on routine upgrades. Do not convert speculation or missing release-note text alone into a blocker.
