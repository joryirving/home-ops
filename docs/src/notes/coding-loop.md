# The coding loop

Self-hosted, GitOps-driven coding automation: GitHub issues go in, reviewed PRs come out.
Two systems, each with one job:

- **Dispatch** is the assignment layer and system of record. It syncs issues, grooms them
  into lanes, hands work out, and tracks PR follow-ups.
- **Courier** is the execution layer: a Kubernetes operator that runs one coordinator pod
  (OpenCode on a local model) per unit of work.

Courier core has no Dispatch dependency; the Dispatch source adapter is optional and enabled
here. The durable configuration is Courier's HelmRelease, its `LaneProfile`
(`kubernetes/apps/base/llm/courier/config/laneprofile.yaml`), and Dispatch's HelmRelease env.
`CoderRun`s are runtime state and are never committed.

```
GitHub issue
    │  Dispatch scheduled sync (15m)
    ▼
Dispatch cache ──► hosted groomer (qwen3.8-flash-next) ──► lane: local / frontier / backlog
    │  Courier polls next-task (30s, lane local)
    ▼
CoderRun ──► coordinator pod (OpenCode, qwen3.8-flash-next)
    │          ├─ coder-local   (qwen3.8-27b)        narrow, file-scoped questions and changes
    │          └─ agentic-local (qwen3.8-flash-next) large recon (summaries) + adversarial review
    ▼
push courier/<owner>/<repo>/issue-<n>, open/update the PR, never merge
    ──► repo CI + AI PR-review action ──► human merge ──► Dispatch sync marks done
    │
    └─ red CI / CHANGES_REQUESTED on the PR ──► PR-fix queue ──► fix-pr CoderRun
```

This replaced LLMKube Foreman and the `foreman-dispatch-bridge` CronJob in 2026-09. Git
history has the old version of this page. Dates on this page are UTC.

## Stage by stage

**1. Sync.** Dispatch's in-app scheduler syncs tracked repos every 15m. Closed issues are
forced to `status/done` on GitHub itself, and `renovate`-labelled issues are excluded.

**2. Groom.** The hosted groomer grooms one issue every 15m on `qwen3.8-flash-next`
(256k context, repository context enabled, 8m per-call timeout). A run produces a validated
grooming plan: labels, lane, readiness, and optionally a close. The plan is applied
idempotently. Readiness is derived and re-checked for freshness when the default branch
moves. The groomer closes an issue on its own only as `already_done`, and only when every
acceptance criterion is grounded in repository content read at a pinned SHA; duplicate and
superseded stay recommendations. Dispatch's `docs/groomer-close-policy.md` is the policy.

**3. Claim.** Courier's Dispatch adapter polls `next-task` every 30s for lane `local`. It gets
either an issue (`resolve-issue`) or a queued PR-fix item (`fix-pr`), and creates a
`CoderRun`. Follow-ups are deduplicated on the PR-fix item's id and generation, so the
same attempt never runs twice.

**4. Run.** The operator admits the run when the lane has capacity and isn't suspended, and
starts one coordinator pod. The executor provisions the workspace (base-synced; merge
conflicts are handed to the coordinator to resolve), writes an OpenCode config from the
LaneProfile's roles, and runs the coordinator. The coordinator plans and delegates: large
recon (surveying a subsystem, reading many files) goes to `agentic-local`, which returns a
summary so the coordinator's own context stays clean; narrow, file-scoped questions and
changes go to `coder-local`; and after a substantive change `agentic-local` does an
independent review pass over the diff. The coordinator does all forge work itself (subagents
have no GitHub MCP tools).

**5. Publish and verify.** The coordinator pushes the run branch and opens or updates the
PR after local validation and independent review, then exits without waiting for CI or
new review feedback. The run moves to `Verifying`, which does not reserve lane capacity.
The controller watches the PR's checks. Two consecutive all-green observations with
the same check fingerprint settle `AwaitingReview`; a merge settles `Done`. It never merges.
Publication must be verified on a non-draft PR before successful coordinator exit.
The PR handoff records decisions, local checks, and pending external verification for
follow-up runs, which cannot recover the exited coordinator's session.

**6. Merge.** A human merges. The next Dispatch sync marks the issue done.

## The Courier lane

One `LaneProfile`, `local`, with `concurrency: 1`:

| Role | Model | Where | Job |
|---|---|---|---|
| `coordinator` | `qwen3.8-flash-next` | Strix Halo | plans, delegates, integrates, verifies, does all forge work; never implements |
| `agentic-local` | `qwen3.8-flash-next` | Strix Halo | large recon (262k window, returns a summary) and the adversarial review of the diff; one at a time |
| `coder-local` | `qwen3.8-27b` | ganyu's 3090 | narrow, file-scoped questions and changes (147k window, 24k reserved for output; split work before a sub passes ~50k); at most two in flight |

The two subagent models run on different machines, so up to two `coder-local` and one
`agentic-local` can be in flight at once. Independent briefs start together with disjoint
file ownership; each coder owns a bounded behavior and its targeted tests. Workers return
partial progress when scope expands instead of accumulating an unbounded transcript.
Agentic research or review can overlap implementation when it reads a stable snapshot,
not files being edited. The coder and the reviewer are deliberately
different models. `gemma-4-12b-it-qat` (the gaming PC, behind llm-wake) stays deployed but is
no longer part of coding; the Courier LiteLLM key still allows `local-pool` /
`local-pool-chat` (whose third rung is gemma), though no role uses them.

`qwen3.8-flash-next` serves two slots: **slot 1 is Courier's coordinator; slot 2 is shared**
with `agentic-local`, the home-ops PR reviewer and every other in-cluster consumer. Work that
lands on the coordinator's slot evicts its cached prompt and costs a full re-prefill on the
Strix Halo, which is why the coordinator keeps `agentic-local` to one at a time. OpenCode
auto-compaction is on in the executor config, so the coordinator's session is compacted
rather than growing without bound.

### Pausing the lane

Suspend is an annotation set **with kubectl**, not a commit. It's for ad-hoc pauses, like
lending Courier's slot to an eval run. Work in flight finishes; nothing new is admitted or
discovered. To stop Courier the GitOps way, scale the operator to 0.

```sh
kubectl -n llm annotate laneprofile local courier.misospace.dev/suspend=true \
  --overwrite --field-manager=flux-client-side-apply
kubectl -n llm annotate laneprofile local courier.misospace.dev/suspend- \
  --field-manager=flux-client-side-apply
```

The field manager matters: without it the next Flux apply (every home-ops commit, through the
webhook) strips the annotation. `kubectl get laneprofiles` shows a `Suspended` column.

## How runs end

The executor prints one `COURIER_TERMINATION {phase, result, exit_code, reason}` line when
the coordinator exits:

| Ending | Phase | Meaning |
|---|---|---|
| committed work on the run branch | `Verifying` | the controller takes over (above) |
| exited 0, no commit and no changes | `NeedsHuman` | usually the coordinator deciding the work was already done |
| exited 0 with uncommitted changes | `NeedsHuman` | it stopped before committing |
| resolve branch already has a PR | `NeedsHuman` | it refuses to adopt the existing PR |
| OpenCode exited non-zero, or workspace prep failed | `Failed` | crash or infrastructure |

After the push, the controller also terminalizes `NeedsHuman` on any failing check, or on no
PR or a draft PR.

None of those `NeedsHuman` endings is a decision: the coordinator's own route to a human
(OpenCode exit 2) had never fired as of 2026-09-28. The goal is that only real design
decisions and loops come back to a human. The work is tracked in the Courier issue tracker
(a coordinator-declared outcome; resuming the session on recoverable endings, with NeedsHuman
only on `looping`; adopting existing PRs and handing red CI back to the fix loop) and the
Dispatch issue tracker (an explicit `already_addressed` settlement).

## The PR-fix loop

Dispatch's pr-followup sync (15m) watches bot-authored PRs and queues a `PrFixQueueItem`
on real signals only: a `CHANGES_REQUESTED` review, failing check runs, and comments with
actionable signal or an @-mention of the bot. Courier picks items up as `fix-pr` runs
against the existing branch. The rules, as of Dispatch 0.5.66:

| Rule | What it does |
|---|---|
| Attempts, not evidence | `PR_FIX_MAX_ATTEMPTS` (default 5) bounds dispatched fix attempts (`fixAttempts`). All the inline comments of one review are one attempt. Past the cap the item goes `BLOCKED` (needs a human) |
| No-push guard | a FIXED report is refused when the PR head hasn't moved since the attempt's baseline (`attemptHeadSha`). Every new attempt records the newest head Dispatch has seen, so a sync that sees the worker's push first can't turn a real fix into a refusal |
| Sticky terminal states | a merged or closed PR's item stays `STALE`; a new review can't resurrect it |
| Known evidence doesn't churn | re-observing the same review never flips an item's status |
| `needs-human` is two-way | entering `BLOCKED` labels the PR and posts a marker; every exit from `BLOCKED` removes the label and folds the marker to "requeued" or "resolved" |
| Archived repos | their items are reaped `STALE` and can't be requeued |
| Item URL is the PR | write-once; CI job links are evidence, never the item's identity |

Known gap: evidence that lands **while an attempt is in flight** is folded into that
attempt, and nothing delivers it to the worker (tracked in the Dispatch issue tracker). A review posted
mid-run can be stranded behind a `BLOCKED` item until it's requeued.

## The frontier lane has no worker

Dispatch still defines a claimable `frontier` escalation lane (MiniMax-M3, for work that
needs a judgement call), and the groomer can route there. Courier polls only `local`, and
Foreman, which used to work `frontier`, is gone. Issues groomed to `frontier` sit until a
worker is pointed at that lane or they're re-laned.

## The shared 3090

`qwen3.8-27b` (Courier's `coder-local`) and `muse-glimmer` (Sage in openclaw, memini,
hermes, and rung 1 of `local-pool` / `local-pool-chat`) share ganyu's RTX 3090.
`kubernetes/apps/base/llm/litellm/nvidia-pool.yaml` defines a `nvidia` `ModelPool` /
`ModelRouter` that swaps the card between them (`swapPolicy: reclaim`, `reclaimAfter: 5m`,
`swapBudget: 900s`).

**Muse-glimmer is the pool default** (#10210), made safe by an upstream LLMKube fix that
bounds pool swaps and stops a stale deactivate racing a new activation. Requests whose `model`
matches no backend go to the router's `defaultRoute`, `qwen38-27b`. The fall-through is
deliberately one-way (#10211):

- **Coding requests never fall through to muse.** Muse is a weaker coder, so a 27B request
  always queues for 27B: a late right answer beats a fast wrong-model one.
- **Muse requests may be served by 27B.** The `muse-fallthrough` rule
  (`poolActivation: IfIdle`) lets a muse request fall through to 27B when muse is busy;
  reclaim returns the card to muse once 27B idles. Both came in #10129.

So a heavy coding week starves muse consumers but never degrades coding, and a stuck swap
costs muse latency, not the coding loop. If the activator ever wedges again (pool stops
reconciling, muse 503s `pool_incumbent_busy`, 27B shows `Stopped`), recovery is
`kubectl -n llm rollout restart deploy/nvidia-router-proxy`; the state is in-memory.

## Operating it

- **Requeue a blocked PR-fix item:** the Dispatch MCP `requeue_pr_fix` tool (or
  `POST /api/pr-fix-queue/requeue`). It resets the attempt count and baselines from the
  current head; it refuses merged, closed or archived PRs.
- **Stop a run:** delete its `CoderRun`. Settle or close the Dispatch side first, or the next
  poll hands the same work out again.
- **Why did a run end the way it did:** the coordinator's logs outlive its pod in
  VictoriaLogs (`observability/victoria-logs-server`, port 9428). Useful LogsQL:
  - `kubernetes.pod_namespace:llm "COURIER_TERMINATION"`: every run's ending and reason
  - `kubernetes.container_name:coordinator type:step_finish`: model calls, with
    `part.tokens.{input,output,reasoning,cache.read,cache.write}` per step
  - `kubernetes.container_name:coordinator type:tool_use part.tool:task`: subagent
    dispatches, with `part.state.input.subagent_type`, `part.state.metadata.model.modelID`
    and `part.state.time.{start,end}`
- **Tokens by model:** LiteLLM spend logs for the `Courier` virtual key, grouped by
  `model_group` (the key exists from 2026-09-27; before that Courier shared another key).
  Courier doesn't export its own run metrics yet (tracked in the Courier issue tracker).

## What an issue must contain

- **Labels:** `priority/pN`, a `status/*` and a `type/*`. An unlabelled issue is invisible to
  the queue, not merely unprioritised. The groomer fills these in over time; set them when
  filing so the work is visible immediately.
- **The ask**, as one imperative sentence.
- **The real file paths** the fix is expected to touch. They focus the coordinator's recon,
  and a groomer `already_done` close needs files to ground in. Name none rather than guess:
  a wrong path sends recon the wrong way.

## Config quick reference

| Where | Setting | Value / meaning |
|---|---|---|
| Courier HelmRelease | `dispatch.enabled` / `laneProfile` / `queueLane` / `pollInterval` | `true` / `local` / `normal` (an alias of `local`) / `30s` |
| Courier HelmRelease | `executor.mcp.githubURL` | GitHub's hosted MCP (`https://api.githubcopilot.com/mcp/`) |
| LaneProfile `local` | `runtimeImage` | the coordinator image (`ghcr.io/misospace/courier-go`) |
| LaneProfile `local` | `concurrency` | `1`: one run at a time (Courier's flash-next slot) |
| LaneProfile `local` | `roles` / `framing` | the models above, and the coordinator's standing instructions |
| Courier ExternalSecret | `courier-executor` `OPENCODE_CONFIG_CONTENT` | the coordinator's OpenCode config: LiteLLM provider at `http://litellm.llm:4000/v1` (30m timeout); per-model limits `qwen3.8-27b` 147456 context / 24576 output, `qwen3.8-flash-next` 262144 / 16384; `compaction` auto (keep 20k tokens, 16k buffer); `tool_output` capped at 800 lines / 16 KiB |
| Dispatch env | `DISPATCH_GROOMER_MODEL` / `_TIMEOUT_MS` / `_INTERVAL_MS` | `qwen3.8-flash-next` / `480000` / `900000` |
| Dispatch env | `DISPATCH_GROOMER_MODEL_CONTEXT_TOKENS` / `DISPATCH_GROOMER_REPO_CONTEXT_ENABLED` | `262144` / `true` |
| Dispatch env | `DISPATCH_LANE_CONFIG_JSON` | lanes `local` (default), `frontier` (escalation), `backlog`; aliases `normal` and `cloud` → `local`, `escalated` → `frontier` |
| Dispatch env | `PR_FIX_MAX_ATTEMPTS` | unset, so the default `5` |
