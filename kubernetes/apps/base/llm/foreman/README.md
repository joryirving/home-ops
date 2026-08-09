# Foreman

Optional [LLMKube](https://llmkube.com/docs/foreman) add-on control plane that dispatches
agentic coder/reviewer workloads across the fleet, running in the `llm` namespace.
Depends on the `llmkube` core operator (its Flux Kustomization sets `dependsOn: llmkube`).

This folder installs the operator (the `foreman` Helm chart, which ships the `Workload`,
`AgenticTask`, `Agent`, and `FleetNode` CRDs) **and** the `Agent` CRs under `agents/`.
`FleetNode`s register themselves at runtime, and per-issue `Workload`s are materialized by
the [foreman-dispatch-bridge](https://github.com/misospace/foreman-dispatch-bridge) CronJob —
both are ephemeral runtime state and are not committed. The loop itself (dataflow, lanes,
retry/escalation, PR fixes) is documented in
[`../dispatch/foreman-dispatch-bridge/README.md`](../dispatch/foreman-dispatch-bridge/README.md);
this file covers the agents and how they get their runtimes.

Chart: `oci://ghcr.io/defilantech/charts/foreman`, pinned in `ocirepository.yaml`.

## One polyglot coder image

Every coder agent runs the same image: `ghcr.io/misospace/llmkube-coder` — Python 3.14,
Node, Go 1.26, Godot 4.7.1 (headless), and Elixir 1.18/OTP 27, plus each language's
linters (~475 MB compressed, amd64 only; the fleet is amd64). Rootless coders cannot
install anything at run time, so every runtime is baked in — the replacement for the old
root-and-apt-get Saffron pods.

This replaced four per-language images in 2026-08 (`llmkube-coder-{python,node,go,godot}`,
retired in misospace/llmkube-images#165). The Python/Node/Go ones were strict subsets of
the polyglot base, and `llmkube-coder-go` was *larger* than the base that already contained
Go. The published packages still exist on ghcr for old digest pins; nothing builds them.

**Rule of thumb:** stay on one image until a runtime is huge or conflicting (JVM, CUDA,
Android SDK class), and split only that one out.

## How an agent executes

`spec.execution` decides where an agent runs:

| `execution` | Runs | Consequence |
|---|---|---|
| `image: … / mode: Job` | one Job per task | survives `foreman-agent` restarts |
| empty | in-process inside the `foreman-agent` pods | dies on any restart |

All seven coders (`coder`, `coder-frontier`, `coder-revision`, `coder-python`,
`coder-node`, `coder-go`, `coder-godot`) are Job-based on the polyglot image. Only the
gates and reviewers are in-process — they need no language runtime, and their tasks are
short enough that a restart losing one is cheap.

The per-language agents survive as **prompt specializations of the same image**, not
different runtimes: `coder-godot`'s prompt carries GDScript traps (`assert_eq` arity is a
parse error that silently drops the whole test file), `coder-python`'s carries Python
gate specifics, and so on. `coder-frontier` differs only by model (`MiniMax-M3-chat`).

The bridge picks the agent per issue: `LANE_CODER_AGENTS` (escalation) →
`REPO_CODER_AGENTS` (exact repo — exists because `gateProfile.language` is an enum, so
GDScript/Elixir repos are both `generic` and indistinguishable by language) →
`BASE_CODER_AGENTS` (language) → wildcards.

## Why runtimes-in-the-coder matters

The coder **self-gate runs the repo's `GATEPROFILE_MAP` commands** before submitting.
With `VERIFY_ENABLED=false` (clean-room verify Jobs are off; repo CI is the verifier),
the self-gate is the only pre-PR test execution — and it silently no-ops when the
runtime is missing (`self-gate-deferred`, deferring to a backstop that is disabled).
That is how misospace/windowstead#321 shipped a test file that did not parse: no Godot
in the coder, no gate Job, reviewer GO'd anyway (LLMKube#1454). With the polyglot image
the self-gate has every runtime, so the gate profiles do their job inside the coder.

## Gotchas

- **Agent CRs are cached at startup.** Editing a `systemPrompt` or `maxOutputTokens`
  needs `kubectl rollout restart deployment/foreman-agent`. Since coders are Job-based,
  a restart now only interrupts in-flight reviews/gates (LLMKube#1438 tracks a drain).
- **Images are digest-pinned** (no `imagePullPolicy` in the CRD; tags are mutable).
  Renovate bumps digests — including inside `GATEPROFILE_MAP`'s JSON, via a custom
  regex manager in `.renovate/customManagers.json5` (the flux manager cannot see refs
  embedded in a JSON string; the godot-gate pin sat stale at 4.2.2 because of this).
- **Godot versions are pinned in three places** that must agree: the polyglot image, the
  `godot-gate` pin in `GATEPROFILE_MAP`, and each Godot repo's own `godot-toolchain.json`
  (which its CI reads). All three are 4.7.1 as of 2026-08.
