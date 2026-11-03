# Coding loop

Dispatch assigns GitHub work. Courier runs it and publishes changes for human review. Neither system merges pull requests.

Courier can run without Dispatch. This installation enables its optional Dispatch source adapter. Durable configuration lives in the Courier HelmRelease, LaneProfiles, and Dispatch HelmRelease. A LaneProfile defines the models and concurrency for an execution lane. A CoderRun records one execution attempt and is runtime state, not committed configuration.

## Evidence and configuration

This page was refreshed on 2026-11-03 against home-ops `origin/main`, Courier `v0.1.18`, and Dispatch `v0.5.73`. A runtime read during the refresh showed those controller images deployed. This is a dated observation, not a health guarantee.

The working checkout can lag the deployed configuration. Compare the desired chart pin, actual container image, and relevant upstream release before diagnosing behavior.

Primary configuration paths:

- `kubernetes/apps/base/llm/courier/helmrelease.yaml`
- `kubernetes/apps/base/llm/courier/config/laneprofile.yaml`
- `kubernetes/apps/base/llm/courier/externalsecret.yaml`
- `kubernetes/apps/base/llm/dispatch/helmrelease.yaml`
- `kubernetes/apps/base/llm/litellm/models/`

Inspect secret references and access metadata, never secret values.

## Stage by stage

### Sync and groom

Dispatch's scheduler syncs tracked repositories every 15 minutes. The hosted groomer assesses one candidate per scheduled run. It proposes labels, a lane, readiness, and sometimes closure. Dispatch validates the plan before application.

Current manifests select `grooming-pool`, a 245760-token context budget, repository context, and a maximum of 18 exploration rounds. The exploration timeout is 480000 ms. The model timeout is 840000 ms, and the scheduled interval is 900000 ms. These are separate limits, not one eight-minute run budget.

An `already_done` closure requires evidence for the issue's acceptance criteria at a pinned repository revision. Model confidence or a free-form success statement does not authorize closure. Dispatch's `docs/groomer-close-policy.md` describes the policy.

### Discover and claim

Courier polls Dispatch every 30 seconds. The configured bindings are:

| Dispatch queue | Courier profile | Agent identity |
|---|---|---|
| `local` | `local` | `courier-local` |
| `local` | `minimax` | `courier-cloud` |
| `local` | `hyper` | `courier-hyper` |
| `escalated` | `frontier` | `courier-frontier` |

Local, MiniMax, and Hyper share the normal queue. Frontier is the exclusive escalation lane. These bindings select consumers; they do not reserve normal work for a particular model.

Dispatch aliases `normal` and `cloud` to `local`, and `escalated` to `frontier`. Compare the authenticated identity with the configured binding during authorization investigations.

Issue work becomes `resolve-issue`. Ordinary PR follow-up work becomes `fix-pr`. PR-fix identity includes the queue item and generation. A new generation is a new attempt, not a duplicate of retained history. The chart enables `prFixExclusions: true` to avoid repeated offers of attempts Courier already retains.

Discovery reservations and execution capacity are different. In Courier 0.1.18, Pending, Claimed, and Running reserve discovery capacity. Only Claimed and Running consume execution slots. Retained identities can still suppress duplicate work even when they consume no slot.

### Execute

Courier admits work when its profile has capacity and is not suspended. The current four profiles each have concurrency one. It starts a coordinator pod and builds the OpenCode role configuration from the profile.

The legacy OpenCode path first runs an independent workspace observer initializer. It records a trusted starting revision before the model starts. A missing work branch is normal for a new issue; the observer then fetches the base branch. Failure here can prevent all model execution.

Ordinary PR repair prepares the existing branch against its actual base. Preparation can leave a merge conflict for the coordinator to resolve. Do not apply those merge instructions to the separate mechanical rebase path.

The coordinator makes small, understood changes directly. It delegates only when bounded independent work justifies the extra context and execution cost. It owns GitHub actions itself; configured workers do not receive its GitHub MCP tools.

### Publish and verify

After local checks and any required independent review, the coordinator pushes its branch and opens or updates a non-draft PR. It exits without polling CI or waiting for another review round. Its handoff records decisions, check results, and pending external verification.

The controller then verifies the publication and PR checks. `Verifying` does not consume an execution slot. Two matching all-green observations settle `AwaitingReview`. A merged PR settles `Done`. Failed checks can enter bounded repair or handoff paths; they do not all imply a human design decision.

Successful tool execution alone is not publication evidence. Make sure that the expected remote head and non-draft PR exist before claiming publication.

A human merges the PR. Dispatch subsequently reconciles the linked issue.

## Models and delegation

Current profile bindings are:

| Profile | Coordinator | Other roles |
|---|---|---|
| `local` | `litellm/qwen3.8-flash-next` | `agentic-local`: Flash-Next; `coder-local`: 27B; `free`: `free-pool` |
| `minimax` | `litellm-anthropic/MiniMax-M3.1-Flash` | Explorer, implementer, oracle, and reviewer use the same model |
| `hyper` | `litellm/glm-5.3-flash-hyper` | Explorer, implementer, oracle, and reviewer use the same model |
| `frontier` | `litellm/glm-5.3-flash` | Explorer: 27B; implementer: `implementation-pool`; reviewer: MiniMax; oracle: `reasoning-pool` |

The local framing permits at most two `coder-local` workers and one `agentic-local` worker at once. These are ceilings, not targets. The 27B service is shared with other consumers. Do not infer spare GPU capacity from a free Courier slot.

MiniMax framing serializes delegation to one worker. Its roles share provider allowance. A separate review session provides an independent assessment, but not model-family diversity.

Require one independent review for consequential behavior changes, including authority, destructive recovery, financial operations, and concurrency. Understood low-risk mechanical changes need self-verification, not automatic delegation. Dependency updates require an upstream impact assessment before treating them as low risk.

Record each relevant check once per change state: command, working directory, revision or identifiable state, result, compact output, and limitations. Reuse valid evidence across workers and review. Rerun only after relevant changes or for a specific coverage concern.

Pool membership can change without a Courier profile change. The current reasoning order is K2.7, GPT-6.1 Sol, GLM-5.3-Flash Hyper, GLM-5.3-Flash Z.AI, then Flash-Next. The implementation pool configures Luna at effort `high`; that does not change the direct Luna alias. Read the pool manifests for the complete current routes.

## How runs end

The executor emits a `COURIER_TERMINATION` record. The controller combines that result with publication, source ownership, and external checks. A local exit and accepted source settlement are different facts.

| Result or condition | Current behavior or interpretation |
|---|---|
| Successful coordinator exit | Enters `Verifying`; publication still needs controller verification |
| Declared no-change PR repair or rebase | Enters `Verifying`; the declaration alone does not prove completion |
| Declared no-change issue work | Can enter `AwaitingReview` without a PR; issue closure integration remains tracked in Courier #720 |
| Declared human decision | Enters `NeedsHuman` |
| Recognized external block or confirmed capacity exhaustion | Enters recoverable `BlockedExternal` handling |
| Other failed executor exit | Enters `Failed`, subject to recovery rules |
| Repeated infrastructure failure | Can reach the restart ceiling and enter `NeedsHuman` before a model starts |

`NeedsHuman` is therefore not proof that the model found a design decision. Inspect the recorded failure category before deciding what action is needed.

A production example on November 3 failed in `workspace-observer-seed` before model startup. The observer reported `observer base fetch failed`, exhausted restarts, and blocked the issue. The observer uses a 30-second seed deadline and a full-history fetch. Timing supports a timeout explanation, but discarded Git stderr prevents a confirmed diagnosis. Do not present the suspected timeout as proven.

For issue work already satisfied by existing code, the result belongs on the GitHub issue. Dispatch already supports evidence-gated `already_done` closure. Courier #720 tracks delivery of the no-change conclusion into that path. A successful lifecycle status update does not establish that an issue closed or a PR was published.

## PR follow-up and rebase

Dispatch observes bot-authored PRs for changes-requested reviews, failing checks, merge conflicts, and actionable comments. Its queue preserves evidence and attempt ownership separately.

Current safeguards include:

- Attempt accounting: Dispatch 0.5.73 defaults to five fix attempts. Exhaustion parks work instead of retrying forever.
- Publication evidence: a normal fixed report requires movement from the attempt's head baseline, unless a supported no-change settlement applies.
- Terminal state: merged or closed PRs stay stale rather than reopening on old evidence.
- Evidence identity: repeated observations do not create fresh attempts merely because sync ran again.
- In-flight evidence: new evidence after handout is recorded for settlement and can require a fresh attempt. It is not automatically delivered into the running model session.
- Ownership: generations and handout receipts prevent stale reports from settling a different attempt. Do not reset them to force progress.

### Mechanical rebase status

Courier #715 and Dispatch #1532 are closed. Courier 0.1.18 includes a distinct rebase mode and documents a versioned rebase-only intake contract in upstream `docs/rebase-lane.md`.

The contract uses `work_scope=rebase-only`, `work_scope_version=1`, and `capabilities=rebase-executor:1`. Supported peers must acknowledge the contract. Missing or unknown acknowledgment must not broaden intake into ordinary implementation or PR repair.

This does not establish production readiness by itself. During this refresh, Dispatch remained on 0.5.73 and the configured Courier consumers contained no rebase lane. Make sure that the deployed Dispatch release includes the paired contract before enabling a consumer.

The intended profile has one `litellm/qwen3.8-27b` coordinator, concurrency one, and no delegation. Enablement also needs a dedicated binding, Courier's rebase declaration, and Dispatch's explicit agent allowlist. Neither a model profile nor allowlisting alone provides task isolation.

Never enable an old Courier consumer for REBASE work. Courier 0.1.16 maps that work to ordinary PR repair. Consult the current upstream compatibility matrix and test both release orders before changing production configuration.

## Shared local inference

The 27B coder and Muse-glimmer share ganyu's RTX 3090 through the `nvidia` ModelPool. A ModelPool selects which model occupies the GPU.

Current desired configuration sets `default: qwen3.8-27b`, `swapPolicy: reclaim`, `reclaimAfter: 5m`, and `swapBudget: 240s`. These replace the former Muse default and 900-second budget.

The router defaults to `qwen38-27b`. Its one-way Muse fallback can serve a Muse request with 27B. A coding request does not fall back to Muse. Do not confuse the router's fallback with the pool's default model.

The 27B deployment uses `dbirks/Qwen3.8-27B-W4A16-AutoRound` through HyperQwen. Manifest values are `MAX_LEN=147456`, `MAX_SEQS=8`, `GPU_UTIL=0.985`, and `SPEC=mtp`. Eight server sequences do not authorize eight Courier workers.

The Model Management session reported live startup evidence for `int8_per_token_head` KV cache and MTP3 on November 3. The manifest still contains an older fp8 rollback comment. Treat the startup evidence as a dated runtime observation, not a guarantee from that comment or a separately pinned cache setting.

Flash-Next runs on Strix Halo. Its configured slots are shared with the coding pipeline and other consumers. Extra workers can displace cached prompts and increase prompt processing time. OpenCode auto-compaction limits session growth but does not eliminate that contention.

## Operations and evidence

Suspend a profile for a temporary pause. Existing work finishes, while discovery and admission stop for that profile. This is an operational annotation, not a GitOps change:

```sh
kubectl --context main -n llm annotate laneprofile local courier.misospace.dev/suspend=true \
  --overwrite --field-manager=flux-client-side-apply
kubectl --context main -n llm annotate laneprofile local courier.misospace.dev/suspend- \
  --field-manager=flux-client-side-apply
```

The field manager prevents the next Flux apply from removing the operational annotation. Scaling the operator to zero stops reconciliation; it is not a guarantee that existing worker pods stop.

Do not delete a CoderRun as a general stop or recovery procedure. First establish whether a writer is active, whether work is published, and who owns the source attempt. Preserve diagnostics before any authorized cleanup. Use exact resource identity protections for deletion, and settle the source without creating a competing writer.

Retention settings are `done: 5m`, `failed: 3h`, `needsHuman: 3h`, and `auditKeep: -1`. These are not universal TTLs for every phase. Unsettled lifecycle reports and unsafe workspace holds can prevent cleanup. An old record alone does not prove a capacity problem.

Before requeueing one PR-fix item, inspect its current PR, queue status, generation, ownership, and evidence. The Dispatch requeue operation resets attempt accounting. Do not apply it as a blanket queue repair.

Useful log searches in VictoriaLogs include:

- `kubernetes.pod_namespace:llm "COURIER_TERMINATION"` for executor endings.
- `kubernetes.container_name:coordinator type:step_finish` for model call token records.
- `kubernetes.container_name:coordinator type:tool_use part.tool:task` for delegated work.

Do not assume every deleted pod's logs remain available. Preserve required evidence while it exists. Courier also records run telemetry and lifecycle conditions; the old claim that it exports no run metrics is obsolete. Distinguish worker-reported test results from independently repeated checks.

## Issue requirements

File issues with an explicit ask, actual evidence, and `priority/pN`, `status/*`, and `type/*` labels. Label presence alone does not establish readiness. Dispatch also evaluates dependencies, freshness, lane classification, and ownership.

Name relevant file paths when known. Do not invent paths to make a brief look complete. An already-satisfied conclusion needs evidence for the actual issue, not merely similar code in a sibling feature.

## Configuration reference

| Setting | Current desired value |
|---|---|
| Courier polling | Enabled, 30 seconds, four bindings listed above |
| Courier ownership | `ownership.namespaces: [llm]` |
| PR-fix exclusions | `prFixExclusions: true` |
| Local profile concurrency | `1` |
| OpenCode provider timeout | 1800000 ms |
| 27B OpenCode limits | 147456 context, 24576 output |
| Flash-Next OpenCode limits | 262144 context, 16384 output |
| OpenCode compaction | Automatic, keep 20000 tokens, buffer 16384 |
| Tool output cap | 800 lines, 16384 bytes |
| Groomer model | `grooming-pool` |
| Groomer context | 245760 tokens, repository context enabled |
| Groomer rounds and exploration timeout | 18 rounds, 480000 ms |
| Groomer model timeout and interval | 840000 ms, 900000 ms |
| NVIDIA pool default and swap budget | `qwen3.8-27b`, 240 seconds |

Pool routes and deployed versions change independently. Re-read their configuration when those details affect an operational decision.
