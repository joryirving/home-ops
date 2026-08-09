# Foreman ⇄ Dispatch coding loop

Self-hosted, GitOps-driven coding automation: GitHub issues go in, reviewed PRs come out.
Dispatch is the assignment layer (system of record, pull-only), LLMKube Foreman is the
execution layer, and this bridge is the only thing that connects them. Agents and their
runtimes are documented in [`../../foreman/README.md`](../../foreman/README.md).

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
    └─ review  reviewer Agent (Mellum2, read-only) — diff review, verdict
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
one `status/ready` issue per lane. The Workload carries the coder Agent
(lane → repo → language precedence), the repo's `gateProfile`, and `issues: [<n>]` — which
survives retries (bridge 0.6.20; losing it once collided every third attempt onto a shared
`wl-<repo>-0` branch that retries force-pushed over).

**4. Execute.** The operator decomposes into `code → review` (verify Jobs are off:
`VERIFY_ENABLED=false`, repo CI is the verifier). The coder runs as its own Job on the
polyglot image, runs the `gateProfile` commands as a **self-gate** before submitting, and
pushes `foreman/<workload>/issue-<n>`. The reviewer (Mellum2 via the `reviewer` alias)
reads the diff and issues a verdict; deterministic rails ground its claims (filesTouched,
issueAsk, findings, and — since 0.9.15 — the PR-body summary against the diff).

**5. PR.** On review GO, foreman opens the PR itself (`Fixes #<n>`, idempotent). The repo's
own CI and the AI PR-review action take over; a human merges; the next sync marks the
issue done.

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

## Config quick reference

Env on this HelmRelease unless noted:

| Env | Meaning |
|---|---|
| `DISPATCH_LANES` = `local,frontier` | lanes polled per tick |
| `ESCALATION_LANE` = `frontier` | give-up target |
| `LANE_CODER_AGENTS` | lane → Agent; frontier → `coder-frontier` |
| `REPO_CODER_AGENTS` | exact repo → Agent (prompt specialization; e.g. windowstead → `coder-godot`) |
| `BASE_CODER_AGENTS` | gate-profile language → Agent |
| `GATEPROFILE_MAP` | per-repo self-gate commands + gate image + `sourceExtensions` (feeds the reviewer's scope vouch). Digest pins inside this JSON are Renovate-managed via a custom regex manager |
| `VERIFY_ENABLED` = `false` | no clean-room verify Jobs; coder self-gate + repo CI verify |
| `PR_FIX_ENABLED` / `PR_FIX_MAX_ATTEMPTS` / `PR_FIX_LANE_AGENTS` | the pr-fix loop above |
| `MAX_IN_PROGRESS` | cap on concurrently-worked issues (0 = uncapped) |

## Known upstream issues

- [LLMKube#1438](https://github.com/defilantech/LLMKube/issues/1438) — no drain-before-roll
  for `foreman-agent`; restarts kill in-process (reviewer/gate) tasks. Coders are Job-based
  and unaffected.
- [LLMKube#1447](https://github.com/defilantech/LLMKube/issues/1447) — reviewer
  scope-overlap can false-NO-GO test-coverage issues (diff touches `X.test.ts`, issue
  names `X.ts`).
- [LLMKube#1434](https://github.com/defilantech/LLMKube/issues/1434) — coders cannot read
  the PR they are asked to fix (`fetch_pull_request` tool).
- [LLMKube#1454](https://github.com/defilantech/LLMKube/issues/1454) — a reviewer that says
  "cannot verify" can still return GO.
