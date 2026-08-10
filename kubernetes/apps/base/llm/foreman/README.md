# Foreman

Optional [LLMKube](https://llmkube.com/docs/foreman) add-on control plane that dispatches
agentic coder/reviewer workloads across the fleet, running in the `llm` namespace.
Depends on the `llmkube` core operator (its Flux Kustomization sets `dependsOn: llmkube`).

This folder installs the operator (the `foreman` Helm chart, which ships the `Workload`,
`AgenticTask`, `Agent`, and `FleetNode` CRDs) **and** the `Agent` CRs under `agents/`.
`FleetNode`s register themselves at runtime and per-issue `Workload`s are materialized by
the [foreman-dispatch-bridge](../dispatch/foreman-dispatch-bridge/) CronJob — both are
ephemeral runtime state and are not committed.

Chart: `oci://ghcr.io/defilantech/charts/foreman`, pinned in `ocirepository.yaml`.

> **How the whole loop works — agents, models, fleet capacity, gates, retry and
> escalation — is documented in [docs/src/notes/coding-loop.md](../../../../../docs/src/notes/coding-loop.md).**
> Read that before changing an `Agent` CR or `agent.replicaCount`.
