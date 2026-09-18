# The coding loop

Self-hosted, GitOps-driven coding automation: GitHub issues go in, reviewed PRs come out.
Three systems, each with one job — **Dispatch** is the assignment layer (system of record,
pull-only), **LLMKube Foreman** is the execution layer, and the **foreman-dispatch-bridge**
CronJob is the only thing connecting them.

Nothing here is hand-run. `Workload`s and `AgenticTask`s are ephemeral runtime state and
are never committed; the durable configuration is the bridge's env and the `Agent` CRs
under `kubernetes/apps/base/llm/foreman/agents/`.

```
GitHub issue
    │  dispatch scheduled sync (15m)
    ▼
Dispatch cache ──► Groomer (glm-5.3-flash-local, response_format-constrained) ──► lane: local / backlog
    │  bridge CronJob (*/15)
    ▼
Workload (this bridge) ──► AgenticTasks (foreman-operator)
    │
    ├─ code    coder Agent (Job, polyglot image) — clone, fix, SELF-GATE, push branch
    │          local lane: coder (qwen3.8-27b, shared 3090); escalation: coder-frontier (MiniMax-M3, anthropic-native cloud)
    └─ review  reviewer Agent (gemma-4-12b-it-qat, read-only) — diff review, verdict
    │
    ▼ review GO
foreman opens the PR (summary grounded against the diff)
    ──► repo CI + AI PR-review action ──► human merge ──► dispatch sync marks done
    │
    ├─ 3 failed attempts in local ──► bridge re-lanes to frontier (MiniMax-M3)
    └─ PR gets red CI / CHANGES_REQUESTED ──► pr-fix loop (below)
```

## Stage by stage

**1. Sync.** Dispatch's in-app scheduler syncs tracked repos every 15m. Closed issues are
forced to `status/done` on GitHub itself; `renovate`-labeled issues are excluded.

**2. Groom.** The hosted groomer runs on `glm-5.3-flash-local` — a slower Q2 "smart" model
(~140 t/s prefill) picked for judgment over throughput. It grooms one issue per run,
`response_format`-constrained with `validateGroomerOutput` as the net. Grooming is binary:
ready → `local`, not → `backlog`. It never routes to `frontier`; tiering is decided by
*failure*, not prediction. The cost is prefill: the context is issue-guided (code searched
per issue, not a stable repo map), so nothing amortizes across runs and each new issue is a
~200s cold prefill. The backstops are `DISPATCH_GROOMER_TIMEOUT_MS=480000` (8m per call) and
a `DISPATCH_GROOMER_INTERVAL_MS=900000` (15m) cadence. dispatch#1017 (a stable per-repo
prefix so caching amortizes) was closed — it cannot help one-issue-per-run on a model shared
with other consumers; dispatch#1018 (bound the exploration budget so a slow model prefills
less) is the live lever.

**3. Claim → Workload.** This CronJob (`*/15`) retries failed Workloads first, then claims
one `status/ready` issue per lane. The Workload carries the coder Agent (picked from the
lane's list by `issue % len`, so retries stay on the same backend and its warm prompt
cache), the repo's `gateProfile`, and `issues: [<n>]` — which
survives retries (bridge 0.6.20; losing it once collided every third attempt onto a shared
`wl-<repo>-0` branch that retries force-pushed over).

**4. Execute.** The operator decomposes into `code → review` (verify Jobs are off:
`VERIFY_ENABLED=false`, repo CI is the verifier). The coder runs as its own Job on the
polyglot image, runs the `gateProfile` commands as a **self-gate** before submitting, and
pushes `foreman/<workload>/issue-<n>`. The reviewer (Gemma 4 12B-it QAT via `gemma-4-12b-it-qat`)
reads the diff and issues a verdict; deterministic rails ground its claims (filesTouched,
issueAsk, findings, and — since 0.9.15 — the PR-body summary against the diff).

**5. PR.** On review GO, foreman opens the PR itself (`Fixes #<n>`, idempotent). The repo's
own CI and the AI PR-review action take over; a human merges; the next sync marks the
issue done.

## The agents

`spec.execution` decides where an agent runs:

| `execution` | Runs | Consequence |
|---|---|---|
| `image: … / mode: Job` | one Job per task | survives `foreman-agent` restarts |
| empty | in-process inside the `foreman-agent` pods | dies on any restart |

All three coders (`coder`, `coder-frontier`, `coder-revision`) are Job-based on the polyglot
image. Only the reviewers are in-process — they need no language runtime, and their tasks are
short enough that a restart losing one is cheap.

Coders differ **only by model**, not by runtime or language:

| Agent | Model | Role |
|---|---|---|
| `coder` | `qwen3.8-27b` (shared 3090 `nvidia` pool, 1 slot, 120k ctx) | issue work in the `local` lane |
| `coder-frontier` | `MiniMax-M3` (`provider: anthropic`) | the `frontier` lane and every pr-fix |
| `coder-revision` | `MiniMax-M3` (`provider: anthropic`) | reworks a branch after reviewer findings |

`coder-frontier` and `coder-revision` moved to `provider: anthropic` in 0.9.27 (#1811): they
now dial MiniMax's Anthropic-native `/v1/messages` directly instead of the OpenAI-compat shim,
which was leaking reasoning inline as `<think>…</think>` and mis-counting usage. The reviewers
(`reviewer`, `reviewer-fork`) run `gemma-4-12b-it-qat`.

The old per-language agents (`coder-python`, `coder-go`, `coder-godot`, `coder-node`) were
deleted in 2026-08: once every runtime lived in one image, they differed only by a prompt
paragraph restating `GATEPROFILE_MAP`, which the self-gate already executes. The one
genuinely load-bearing piece — repo-specific traps like GDScript's `assert_eq` arity being
a parse error that silently drops a whole test file — is repo knowledge, so it moved to
each repo's `AGENTS.md`, which every coder prompt now opens by reading.

Routing collapsed with them. `LANE_CODER_AGENTS` is the only map: a lane's value may be a
list, and the bridge picks `list[issue % len(list)]` — deterministic, so a retry lands on
the backend that already holds that issue's prompt cache. Today it is
`{"*":["coder"],"escalation":["coder-frontier"]}` — one local backend, one escalation; the
list mechanism is still there for when a second throughput backend is added.
`REPO_CODER_AGENTS` and `BASE_CODER_AGENTS` no longer exist.

## The shared 3090

Neither `qwen3.8-27b` (foreman's coder) nor `muse-glimmer` (Sage and the personal consumers)
owns the RTX 3090 — they share it. `kubernetes/apps/base/llm/litellm/nvidia-pool.yaml`
defines a `nvidia` `ModelPool` / `ModelRouter` that swaps the one card between them
(`swapPolicy: reclaim`, `reclaimAfter: 5m`, `swapBudget: 900s`).

**Muse-glimmer is the pool default.** 27B moved onto the native vLLM runtime and muse became
resident by default (#10210), made safe by the upstream router fix in
[LLMKube#1838](https://github.com/defilantech/LLMKube/pull/1838), which bounds pool swaps and
stops a stale deactivate racing a new activation — the exact failure that killed the first
muse-home trial (wedge history below). The fall-through is deliberately one-way (#10211):

- **Coding requests never fall through to muse.** Muse is excellent at agentic tasks but a
  weaker coder, so a 27B request always queues for 27B — a late right answer beats a fast
  wrong-model one.
- **Muse requests may be served by 27B.** An IfIdle rule (#1787) lets a muse request fall
  through to 27B when muse is busy instead of forcing a swap-and-hold; reclaim (#1796)
  returns the slot to muse (the default) once 27B idles.

The consequences: a heavy coding week starves muse consumers (they wait or ride the
fall-through) but never degrades coding correctness; and with muse as default, a stuck swap
costs muse latency — not the coding loop.

**Wedge history.** The first muse-home trial was reverted because the activator could wedge:
the swap goroutine got stuck, the pool stopped reconciling (`context canceled`), muse requests
503'd `pool_incumbent_busy`, and 27B showed `Stopped` while a coder hung waiting on a swap
that never completes. Recovery is still `kubectl rollout restart deploy/nvidia-router-proxy
-n llm` (the state is in-memory), but #1838 removes the race that caused it, which is what
made muse-home safe to adopt.

### One polyglot coder image

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

## Fleet capacity is in-process work, not coders

A FleetNode is one `foreman-agent` **pod**, not a machine: `spec.nodeName` is the pod's own
name and `status.kubernetesNode` is the host it landed on.

This section used to say replicas cap concurrent coders, because Job-mode tasks reserved
their node for the Job's whole life. [LLMKube#1496](https://github.com/defilantech/LLMKube/issues/1496)
fixed that, so **Job-mode tasks now select a node without reserving it** and replica count
does not bound them at all. One FleetNode was observed carrying two Job-mode coder tasks
and an in-process review at the same time. Concurrent coders are bounded by the bridge's
`CODER_AGENT_SLOTS` and `MAX_IN_PROGRESS` instead.

What replicas still cap is **in-process** work. Every coder Agent runs `execution.mode: Job`,
so the only in-process consumer here is the reviewer — and its backend runs `--parallel 2`,
so a third concurrent review queues at the GPU regardless of how many slots exist. Hence
`replicaCount: 2`. Idle replicas are not free of consequence: a rollout orphans every
FleetNode at once (8 reaped in 48h from one rollout), and an in-flight in-process review
dies with its pod.

The historical incident is still worth knowing: at `replicaCount: 3`, when Job-mode *did*
reserve, three long coder Jobs held every node and reviews sat Pending for hours while the
operator looped `no free FleetNode matches; will retry`.

[#1497](https://github.com/defilantech/LLMKube/issues/1497) also landed, so `Agent.spec`
now has `maxConcurrentTasks` (present in the CRD). We do not set it; the bridge's slot
config is the bound today.

**Do not diagnose by FleetNode occupancy any more.** `status.currentTask` is empty on every
node now, because Job-mode never sets it — it reports only in-process reservations. If work
is not flowing, check whether the model is deferring requests instead:
`llamacpp:requests_deferred` (alerted as `LlamaCppRequestsDeferred`), since inference is
the real constraint at roughly 94% of pipeline wall clock.

## Gates: the coder verifies its own work

The coder's self-gate runs whatever the task's `GateProfile` declares. A Go repo gets the
hardcoded gate (gofmt / vet / build / test); anything else gets the profile's `commands` —
**but only if the `GATEPROFILE_MAP` entry actually sets `language` + `commands`.** Most
entries carried only `sourceExtensions` / `testLayout` (which feed the reviewer's scope
vouch, not a gate), so no gate ran at all for those repos: the coder self-reported and repo
CI was the only real verifier. pr-reviewer-action now carries `language: python` +
`pip install -r requirements.txt && pytest tests/`, so its in-loop gate genuinely runs — a
failing gate is fed back to the coder and, left unresolved, blocks the GO.

With `VERIFY_ENABLED=false` the clean-room verify Jobs are off, so the in-loop self-gate plus
repo CI are the whole verification story. The generic gate runs inside the coder image (the
`python:3.14` base ships ruff/black/flake8 but not pytest — the gate command installs it) and
defers to a clean-room Job only when a runtime is missing (`self-gate-deferred`, deferring to
a backstop that is disabled). That is how misospace/windowstead#321 shipped a test file that
did not parse: no Godot in the coder, no gate Job, reviewer GO'd anyway (LLMKube#1454, now
fixed).

**A gate profile must mirror what CI actually runs — no more, no less.** A check CI runs
but the gate does not is a blind failure the coder can only discover after pushing, which
costs a pr-fix cycle; a check the *gate* runs but CI does not is worse, because it fails
work that would have passed. Both halves are earned: three of the busiest repos sat on the
`*` wildcard (every command `true`, so no verification at all) until 2026-08, and a
`mix deps.audit` added to pinchflat's gate before the repo carried `mix_audit` broke every
pinchflat task until it was reverted. Verify a command exists in the repo before adding it,
and re-check parity when a repo's CI changes.

## The PR-fix loop

Dispatch's pr-followup sync (15m) watches PRs authored by `PR_FOLLOWUP_BOT_IDENTITIES`
and enqueues a `PrFixQueueItem` on real signals only:

- a `CHANGES_REQUESTED` review (dispatch trusts the verdict, not keyword-matching prose)
- failing check runs
- comments that carry **actionable signal or @-mention the bot** — chatter, CI tables,
  and status posts are ignored regardless of author (dispatch 0.5.38; an image-publish
  comment used to re-queue an item every sweep)

The bridge drains `QUEUED` items into `prfix-<repo>-<pr>` Workloads: the coder checks out
the existing `foreman/*` branch and amends it. Both lanes route to `coder-frontier`
(`PR_FIX_LANE_AGENTS={"NORMAL":"coder-frontier","ESCALATED":"coder-frontier"}`); after
`PR_FIX_MAX_ATTEMPTS` (4) distinct evidence keys, the item goes `BLOCKED` (a human) instead
of looping. Guard rails, each earned by an outage:

| Guard | Since | What it stops |
|---|---|---|
| No check runs ≠ passing CI | bridge 0.6.19 | GHA outages marked unverified fixes FIXED → force-push loops |
| merged/closed PR stays reaped | dispatch#1003 (#1000) | STALE/IGNORED are now sticky, so a fresh review can't re-QUEUE a merged PR — the loop that re-fired a prfix Workload every tick against already-merged PRs |
| attempt cap → needs-human | dispatch#1003 (#1001) | after `PR_FIX_MAX_ATTEMPTS` distinct evidence keys, an unconverging item routes to a human instead of churning the coder |
| duplicate evidence keeps item status | dispatch 0.5.38 | an undismissed review resurrected resolved items every sweep |

## Failure & escalation semantics

| Failure | Handled by | Behavior |
|---|---|---|
| Task flake | bridge retry pass | delete + recreate, ≤ 3 attempts, issue number preserved |
| Closed issue mid-retry | closed-issue guard | skip, no attempt burned |
| Coder declares a dead end | `DESIGN-DECISION` / `NO-TECHNICAL-FIX` | parked for a human without burning attempts |
| Persistent failure in `local` | escalation | re-lane → `frontier` → MiniMax-M3 (anthropic-native) |
| Persistent failure in `frontier` | tombstone | Failed Workload kept for human triage |
| Red CI / changes requested on a PR | pr-fix loop | see above |

A `Failed` Workload is **not proof the model failed** — audit before assuming. One night's
four Failed workloads were: two merged-PR retries (bug), one closed-issue tombstone, and
one real. The real one turned out to be a reviewer false-NO-GO with 1,104 lines of good
tests stranded on the branch (LLMKube#1447).

## What an issue must contain

The reviewer runs two deterministic rails against the issue body, and an issue that
satisfies neither gets **correct work rejected**:

- It must be able to **quote the ask verbatim** to prove it read the issue. If it can only
  paraphrase, its GO is demoted to NO-GO.
- That demotion is waived only if **scope-overlap vouches** — the issue names at least one
  file path that the diff actually touches.

So every filed issue should carry one imperative sentence stating the ask, plus the
concrete paths the fix is expected to touch. The trap: naming files the diff does *not*
touch reads as scope drift and rejects the change too, so name none rather than guess.
Each repo carries this contract in its `AGENTS.md` and as an `Agent task` issue form.

## Config quick reference

Env on this HelmRelease unless noted:

| Env | Meaning |
|---|---|
| `DISPATCH_LANES` = `local,frontier` | lanes polled per tick |
| `ESCALATION_LANE` = `frontier` | give-up target |
| `LANE_CODER_AGENTS` | lane → Agent, or a **list** split by `issue % len`. Live: `{"*":["coder"],"escalation":["coder-frontier"]}` — one local backend, one escalation. The only routing map — `REPO_CODER_AGENTS` / `BASE_CODER_AGENTS` were removed with the per-language coders |
| `CODER_AGENT_SLOTS` = `{"coder":1,"coder-frontier":4}` | concurrent tasks per coder Agent — one local (single 3090 slot), four frontier |
| `GATEPROFILE_MAP` | per-repo gate: `language` + `commands` + gate image + `sourceExtensions` (which also feed the reviewer's scope vouch). An entry with no `language`/`commands` runs no gate. Digest pins inside this JSON are Renovate-managed via a custom regex manager |
| `DISPATCH_GROOMER_MODEL` / `_TIMEOUT_MS` / `_INTERVAL_MS` | groomer backend (`glm-5.3-flash-local`), per-call timeout (`480000` = 8m), cadence (`900000` = 15m) |
| `VERIFY_ENABLED` = `false` | no clean-room verify Jobs; coder self-gate + repo CI verify |
| `PR_FIX_ENABLED` / `PR_FIX_MAX_ATTEMPTS` (`4`) / `PR_FIX_LANE_AGENTS` | the pr-fix loop above; both lanes → `coder-frontier` |
| `MAX_IN_PROGRESS` = `14` | cap on concurrently-worked issues (0 = uncapped). Counts every non-terminal Workload, so one sitting in review or revision limbo holds a slot while using no backend; pr-fix Workloads consume backends but are **not** counted. It over- and under-counts at the same time |

## Known upstream issues

- [LLMKube#1438](https://github.com/defilantech/LLMKube/issues/1438) — no drain-before-roll
  for `foreman-agent`; restarts kill in-process (reviewer/gate) tasks. Coders are Job-based
  and unaffected.
- [LLMKube#1447](https://github.com/defilantech/LLMKube/issues/1447) — reviewer
  scope-overlap can false-NO-GO test-coverage issues (diff touches `X.test.ts`, issue
  names `X.ts`).
- [LLMKube#1839](https://github.com/defilantech/LLMKube/issues/1839) — a pr-fix / revision
  whose branch conflicts on rebase is abandoned: `RebaseOntoBase` fails loud on any conflict
  with no path for the coder to resolve it, so a batch of overlapping PRs that conflict-on-
  rebase once one merges all get parked as needs-human. Fix in
  [#1840](https://github.com/defilantech/LLMKube/pull/1840) — the coder resolves the conflict
  in-loop, guarded by a deterministic check that a `git rebase --abort` (reverting merged
  work) still lands as INCOMPLETE.
- ~~[LLMKube#1496](https://github.com/defilantech/LLMKube/issues/1496)~~ — **resolved.**
  Job-mode tasks no longer reserve a FleetNode, so long coder Jobs cannot starve in-process
  reviewers. This is why `replicaCount` no longer bounds coders; see the fleet-capacity
  section above.
- ~~[LLMKube#1497](https://github.com/defilantech/LLMKube/issues/1497)~~ — **resolved.**
  `Agent.spec.maxConcurrentTasks` exists in the CRD. We do not set it; the bridge's
  `CODER_AGENT_SLOTS` is the bound today.
- [LLMKube#1634](https://github.com/defilantech/LLMKube/issues/1634) — Job-mode placement
  picks the alphabetically first eligible node without reserving it, so tasks concentrate
  on one node while others idle. [#1669](https://github.com/defilantech/LLMKube/pull/1669)
  proposes round-robin, but derives the rotation from a live in-flight count that collapses
  to zero when tasks are dispatched serially, so it does not fix the trickle case.
- [LLMKube#1481](https://github.com/defilantech/LLMKube/issues/1481) — `fetch_pull_request`
  reports which check failed but not its error text, so a CI-failure fix still works from
  the re-dispatcher's summary rather than the actual output.
- *(resolved)* LLMKube#1434 — `fetch_pull_request` shipped in 0.9.16, though the webhook
  catalog omitted it (#1482) until 0.9.17.
- ~~[LLMKube#1454](https://github.com/defilantech/LLMKube/issues/1454)~~ — **resolved** in
  0.9.27 (#1801, now deployed). A reviewer that admits "cannot verify" is demoted GO → NO-GO
  instead of opening a PR.
