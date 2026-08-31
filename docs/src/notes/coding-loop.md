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
Dispatch cache ──► Groomer (self-hosted 35B, json_schema-constrained) ──► lane: local / backlog
    │  bridge CronJob (*/15)
    ▼
Workload (this bridge) ──► AgenticTasks (foreman-operator)
    │
    ├─ code    coder Agent (Job, polyglot image) — clone, fix, SELF-GATE, push branch
    │          issues split deterministically: coder (nvidia) / coder-strix (self-hosted)
    └─ review  reviewer Agent (Nemotron 3.5 Lightning, read-only) — diff review, verdict
    │
    ▼ review GO
foreman opens the PR (summary grounded against the diff)
    ──► repo CI + AI PR-review action ──► human merge ──► dispatch sync marks done
    │
    ├─ 3 failed attempts in local ──► bridge re-lanes to frontier (MiniMax-M3-chat)
    └─ PR gets red CI / CHANGES_REQUESTED ──► pr-fix loop (below)
```

## Stage by stage

**1. Sync.** Dispatch's in-app scheduler syncs tracked repos every 15m. Closed issues are
forced to `status/done` on GitHub itself; `renovate`-labeled issues are excluded.

**2. Groom.** The hosted groomer runs on `self-hosted` (the strix/mac litellm pool). It
sends a `json_schema` response_format — grammar-constrained decoding, with
`validateGroomerOutput` as the net. Grooming is binary: ready → `local`, not → `backlog`.
It never routes to `frontier`; tiering is decided by *failure*, not prediction. Both pool
members must honour `response_format` — a member that strips it returns prose and the
groomer fails validation (that was `additional_drop_params` on the mac, removed in #8898).

**3. Claim → Workload.** This CronJob (`*/15`) retries failed Workloads first, then claims
one `status/ready` issue per lane. The Workload carries the coder Agent (picked from the
lane's list by `issue % len`, so retries stay on the same backend and its warm prompt
cache), the repo's `gateProfile`, and `issues: [<n>]` — which
survives retries (bridge 0.6.20; losing it once collided every third attempt onto a shared
`wl-<repo>-0` branch that retries force-pushed over).

**4. Execute.** The operator decomposes into `code → review` (verify Jobs are off:
`VERIFY_ENABLED=false`, repo CI is the verifier). The coder runs as its own Job on the
polyglot image, runs the `gateProfile` commands as a **self-gate** before submitting, and
pushes `foreman/<workload>/issue-<n>`. The reviewer (Nemotron 3.5 Lightning via `llama-reviewer`)
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

All four coders (`coder`, `coder-strix`, `coder-frontier`, `coder-revision`) are Job-based
on the polyglot image. Only the gates and reviewers are in-process — they need no language
runtime, and their tasks are short enough that a restart losing one is cheap.

Coders differ **only by model**, not by runtime or language:

| Agent | Model | Role |
|---|---|---|
| `coder` | `nvidia` (3090, 1 slot) | issue work, and every `NORMAL` pr-fix |
| `coder-strix` | `self-hosted` (Strix + Mac pool) | issue work — the throughput half |
| `coder-revision` | `self-hosted` | reworks a branch after reviewer findings |
| `coder-frontier` | `MiniMax-M3-chat` | the `frontier` lane and escalated pr-fixes |

The old per-language agents (`coder-python`, `coder-go`, `coder-godot`, `coder-node`) were
deleted in 2026-08: once every runtime lived in one image, they differed only by a prompt
paragraph restating `GATEPROFILE_MAP`, which the self-gate already executes. The one
genuinely load-bearing piece — repo-specific traps like GDScript's `assert_eq` arity being
a parse error that silently drops a whole test file — is repo knowledge, so it moved to
each repo's `AGENTS.md`, which every coder prompt now opens by reading.

Routing collapsed with them. `LANE_CODER_AGENTS` is the only map: a lane's value may be a
list, and the bridge picks `list[issue % len(list)]` — deterministic, so a retry lands on
the backend that already holds that issue's prompt cache. `["coder","coder-strix","coder-strix"]`
therefore gives Strix two of every three issues. `REPO_CODER_AGENTS` and `BASE_CODER_AGENTS`
no longer exist.

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

The coder **self-gate runs the repo's `GATEPROFILE_MAP` commands** before submitting.
With `VERIFY_ENABLED=false` (clean-room verify Jobs are off; repo CI is the verifier),
the self-gate is the only pre-PR test execution — and it silently no-ops when the
runtime is missing (`self-gate-deferred`, deferring to a backstop that is disabled).
That is how misospace/windowstead#321 shipped a test file that did not parse: no Godot
in the coder, no gate Job, reviewer GO'd anyway (LLMKube#1454). With the polyglot image
the self-gate has every runtime, so the gate profiles do their job inside the coder.

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
the existing `foreman/*` branch and amends it. `NORMAL` lane → `coder`; after
`PR_FIX_MAX_ATTEMPTS` (3) → `ESCALATED` → `coder-frontier`; exhausted there → `BLOCKED`
(a human). Guard rails, each earned by an outage:

| Guard | Since | What it stops |
|---|---|---|
| No check runs ≠ passing CI | bridge 0.6.19 | GHA outages marked unverified fixes FIXED → force-push loops |
| merged/closed PR → resolve, never retry | bridge 0.6.21 | 3 attempts + frontier escalation burned on already-merged PRs |
| duplicate evidence keeps item status | dispatch 0.5.38 | an undismissed review resurrected resolved items every sweep |

## Failure & escalation semantics

| Failure | Handled by | Behavior |
|---|---|---|
| Task flake | bridge retry pass | delete + recreate, ≤ 3 attempts, issue number preserved |
| Closed issue mid-retry | closed-issue guard | skip, no attempt burned |
| Coder declares a dead end | `DESIGN-DECISION` / `NO-TECHNICAL-FIX` | parked for a human without burning attempts |
| Persistent failure in `local` | escalation | re-lane → `frontier` → MiniMax-M3-chat |
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
| `LANE_CODER_AGENTS` | lane → Agent, or a **list** split by `issue % len`. `{"*":["coder","coder-strix","coder-strix"],"frontier":"coder-frontier"}` gives Strix two of every three issues. The only routing map — `REPO_CODER_AGENTS` / `BASE_CODER_AGENTS` were removed with the per-language coders |
| `GATEPROFILE_MAP` | per-repo self-gate commands + gate image + `sourceExtensions` (feeds the reviewer's scope vouch). Digest pins inside this JSON are Renovate-managed via a custom regex manager |
| `VERIFY_ENABLED` = `false` | no clean-room verify Jobs; coder self-gate + repo CI verify |
| `PR_FIX_ENABLED` / `PR_FIX_MAX_ATTEMPTS` / `PR_FIX_LANE_AGENTS` | the pr-fix loop above |
| `MAX_IN_PROGRESS` = `7` | cap on concurrently-worked issues (0 = uncapped). Counts every non-terminal Workload, so one sitting in review or revision limbo holds a slot while using no backend; pr-fix Workloads consume backends but are **not** counted. It over- and under-counts at the same time |

## Known upstream issues

- [LLMKube#1438](https://github.com/defilantech/LLMKube/issues/1438) — no drain-before-roll
  for `foreman-agent`; restarts kill in-process (reviewer/gate) tasks. Coders are Job-based
  and unaffected.
- [LLMKube#1447](https://github.com/defilantech/LLMKube/issues/1447) — reviewer
  scope-overlap can false-NO-GO test-coverage issues (diff touches `X.test.ts`, issue
  names `X.ts`).
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
- [LLMKube#1454](https://github.com/defilantech/LLMKube/issues/1454) — a reviewer that says
  "cannot verify" can still return GO.
