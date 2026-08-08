# Foreman

Optional [LLMKube](https://llmkube.com/docs/foreman) add-on control plane that dispatches
agentic coder/verifier/reviewer workloads across the fleet, running in the `llm` namespace.
Depends on the `llmkube` core operator (its Flux Kustomization sets `dependsOn: llmkube`).

This folder installs the operator (the `foreman` Helm chart, which ships the `Workload`,
`AgenticTask`, `Agent`, and `FleetNode` CRDs) **and** the `Agent` CRs under `agents/`.
`FleetNode`s register themselves at runtime, and per-issue `Workload`s are materialized by
the [foreman-dispatch-bridge](https://github.com/misospace/foreman-dispatch-bridge) CronJob —
both are ephemeral runtime state and are not committed.

Chart: `oci://ghcr.io/defilantech/charts/foreman`, pinned in `ocirepository.yaml`.

## How an agent gets its runtime

This is the part that is easy to get wrong, because two different mechanisms decide it.

**`spec.execution.image` decides where the agent runs.**

| `execution` | Runs | Consequence |
|---|---|---|
| empty | in-process inside the `foreman-agent` pods | uses the Deployment's image; **dies on any `foreman-agent` restart** |
| `image: …` | its own Job, one per task | survives restarts; gets exactly that image |

Today `coder-go`, `coder-node`, `coder-python` (and `coder-godot`) run as Jobs. Everything
else — `coder`, `coder-frontier`, `coder-revision`, `gate*`, `reviewer*` — runs in-process
and therefore uses whatever image the `foreman-agent` Deployment runs, currently
`ghcr.io/misospace/llmkube-coder` (Python 3.14 + Node 22 + Go 1.26, "the polyglot image").

`coder-frontier` is a separate **agent**, not a separate image: it differs only by model
(`MiniMax-M3-chat` vs `nvidia`). It inherits the polyglot image like every other in-process
agent.

**The bridge decides which agent a repo gets**, in this precedence order:

1. `LANE_CODER_AGENTS` — lane, e.g. the frontier escalation tier
2. `REPO_CODER_AGENTS` — exact repo full name
3. `BASE_CODER_AGENTS` — the repo's gate-profile language
4. wildcards, then the default `coder`

The repo tier exists because `Workload.spec.gateProfile.language` is an **enum** —
`go|python|rust|node|generic` — so every repo outside those presets is `generic` and cannot
be told apart by language. windowstead (GDScript) and pinchflat (Elixir) are both `generic`
and need different runtimes.

## Why this matters

A coder without its repo's runtime cannot run the tests it just wrote. On
misospace/windowstead#321 foreman deferred its self-gate with `runtime missing in the coder
image`, deferring to a clean-room verify Job that is **disabled fleet-wide**
(`VERIFY_ENABLED=false`; repo CI is the verifier instead). The reviewer then returned GO
while stating it could not verify, and the PR opened with a test file that did not parse —
which drops the whole file, so the pre-existing tests in it silently stopped running too.
CI caught it. Nothing before CI did.

Escalation reintroduces the same gap: the lane tier outranks the repo tier, and
`coder-frontier` is in-process, so an escalated GDScript or Elixir task is back on the
polyglot image with no engine.

## Per-language images vs one polyglot image

Measured 2026-08-08, compressed, amd64:

| Image | Size | Contents |
|---|---|---|
| `llmkube-coder` (polyglot) | 265 MB | python3, node, go, ruff, black, flake8, yamllint, eslint, gofmt |
| `llmkube-coder-python` | 96 MB | python3 + the Python linters — a strict **subset** |
| `llmkube-coder-node` | 180 MB | node + JS linters — a strict **subset** |
| `llmkube-coder-go` | 388 MB | go only — **larger than the polyglot image that already contains Go** |
| `llmkube-coder-godot` | 112 MB | Godot 4.2.2 headless — genuinely additive |

The per-language images for Python/Node/Go add **no capability** the polyglot image lacks;
they are smaller, and `coder-go` is not even that. The images that earn their existence are
the ones carrying a runtime the polyglot image does not have.

Consolidating the three onto the polyglot image, and adding Godot/Elixir to it, would put
the base near ~377 MB — still smaller than `llmkube-coder-go` is today — and would fix the
escalation gap for free, since every in-process agent would then have every runtime. The
cost is that all three `foreman-agent` replicas pull it.

## Gotchas

- **Agent CRs are cached at startup.** Editing a `systemPrompt` or `maxOutputTokens` needs
  `kubectl rollout restart deployment/foreman-agent`, which kills in-flight in-process work
  (the Deployment is `Recreate`, with no drain — LLMKube#1438).
- **Coder images are digest-pinned** because the CRD has no `imagePullPolicy` and the tag is
  mutable. Renovate bumps the digests.
- **`gateProfile` without a verifier is decorative.** With `VERIFY_ENABLED=false` no gate Job
  is created, so the profile's commands never run; they exist for the coder's own self-gate
  and for whenever verification is re-enabled.
