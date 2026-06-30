# Foreman

Optional [LLMKube](https://llmkube.com/docs/foreman) add-on control plane that dispatches
agentic coder/verifier/reviewer workloads across the fleet, running in the `llm` namespace.
Depends on the `llmkube` core operator (its Flux Kustomization sets `dependsOn: llmkube`).

This folder installs the **operator only** (the `foreman` Helm chart, which ships the
`Workload`, `AgenticTask`, `Agent`, and `FleetNode` CRDs). The cluster-wide CRs that drive
it — `FleetNode` (hardware registration) and `Agent` (role definitions), plus per-issue
`Workload`s materialized at runtime by the
[foreman-dispatch-bridge](https://github.com/joryirving/containers/tree/main/apps/foreman-dispatch-bridge)
CronJob — are added separately and are **not** committed here (Workloads are ephemeral
runtime state).

Chart: `oci://ghcr.io/defilantech/charts/foreman`, pinned in `ocirepository.yaml`.
