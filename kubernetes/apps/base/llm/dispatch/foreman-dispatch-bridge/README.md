# Foreman ⇄ Dispatch coding loop

Self-hosted, GitOps-driven coding automation: GitHub issues go in, reviewed PRs
come out. Dispatch is the assignment layer (system of record, pull-only),
LLMKube Foreman is the execution layer, and this bridge is the only thing that
connects them.

```
GitHub issue
    │  (dispatch scheduled sync, 15m)
    ▼
Dispatch cache ──► Groomer (vision 4B) ──► lane: local (ready) / backlog
    │  (bridge CronJob, hourly at :30)
    ▼
Workload (this bridge) ──► AgenticTasks (foreman-operator)
    │
    ├─ code    coder Agent (llama-nvidia)  — clone, fix, test, push branch
    ├─ verify  gate Job (generic no-op)    — would run fmt/lint/test per language
    └─ review  reviewer Agent (Ornith/strix) — read-only diff review, verdict
    │
    ▼
reviewed branch pushed ──► PR (manual until LLMKube#937) ──► repo CI + MiniMax review ──► human merge
    │
    └─ 3 failed attempts? ──► bridge re-lanes issue to frontier
                              ──► coder-frontier (cloud-proxy → litellm → MiniMax-M3)
```

## Stage by stage

### 1. Issue created → Dispatch picks it up

Dispatch's **in-app scheduler** (`DISPATCH_SCHEDULER_ENABLED`, dispatch 0.5.16+)
runs a GitHub **sync every 15m** against tracked repos — no external cronjobs
(the old `dispatch-heartbeat` app is retired). Sync also enforces the terminal
state: any **closed** issue is forced to `status/done` (labels reconciled on
GitHub itself), so closed issues can never linger claimable.

Issues labeled `renovate` are excluded (`DISPATCH_EXCLUDED_LABELS`).

### 2. Groomed

The **hosted groomer** runs every 10m on **`vision`** (Qwen3.5-9B via litellm →
llama.cpp). Small model, made reliable by grammar: dispatch sends a
`json_schema` response_format and llama.cpp grammar-constrains decoding — lane
ids, label allowlist, and title/body length bounds are enforced at the token
level (dispatch 0.5.17+), with `validateGroomerOutput` as the safety net and a
`json_object` fallback if a backend rejects the schema.

Grooming is intentionally **binary**: an issue is either ready → **`local`**
lane, or not → **`backlog`**. The groomer never routes to `frontier` — model
tiering is decided by *failure*, not by upfront prediction (a 4B is not asked
to guess difficulty). It may also rewrite the title / enrich the body.

Lanes (`DISPATCH_LANE_CONFIG_JSON` on the dispatch HelmRelease):

| Lane | Claimable | Fed by | Executor |
|---|---|---|---|
| `local` | yes (default) | groomer | `coder` Agent → llama-nvidia |
| `frontier` | yes (escalation) | bridge give-up path | `coder-frontier` Agent → litellm → MiniMax-M3 |
| `backlog` | no | groomer | — (needs grooming) |

### 3. Bridge creates a Workload

This CronJob (hourly at :30) does one tick:

1. **Retry pass** — for every `Failed` Workload it created:
   - attempt < `RETRY_MAX_ATTEMPTS` (3): delete + recreate at attempt+1 with
     the *current* config.
   - attempts exhausted, lane ≠ `frontier`: **escalate** — re-classify the
     issue's lane to `frontier` (`model: bridge-escalation`), release the
     claim, delete the dead Workload. The next tick re-claims it from
     `frontier`.
   - attempts exhausted in `frontier`: leave a Failed tombstone for a human.
2. **Claim pass** — for each lane in `DISPATCH_LANES` (`local,frontier`), claim
   one `status/ready` issue from the dispatch queue and create a `Workload`:
   - `spec.repo` = the issue's own repo (per-task clone, foreman ≥ 0.8.25)
   - `spec.coderAgentRef` from `LANE_CODER_AGENTS` (lane → Agent map)
   - `spec.gateProfile` from `GATEPROFILE_MAP` (currently `generic` no-op for
     every repo — see the HelmRelease comment for why)

### 4. AgenticTasks execute

The foreman-operator decomposes each Workload into `code → verify → review`
AgenticTasks; the single shared **foreman-agent** (roles: worker, coder,
verifier) claims and executes them serially:

- **code** — coder Agent (llama-nvidia) clones the repo, makes the smallest
  correct change, runs verification, commits as **Saffron**
  (`commitAuthorName/Email` on the foreman HelmRelease) and pushes
  `foreman/<workload>/issue-<n>`.
- **verify** — gate Job submitted into this namespace (`--foreman-namespace=llm`,
  postRenderer-patched until LLMKube#933 exposes it in the chart). The generic
  profile makes it a no-op; real per-language gates wait on the upstream
  self-gate fix (LLMKube#929).
- **review** — Ornith (llama-strix), read-only tool whitelist, approves or
  requests changes against the issue.

A failed upstream task cascade-fails its dependents; the Workload goes
`Failed` and re-enters the bridge's retry pass.

### 5. PR opened — currently the missing hop

**Foreman does not open PRs** ([LLMKube#937](https://github.com/defilantech/LLMKube/issues/937)):
a fully-green Workload (`code GO -> verify GATE-PASS -> review GO`) ends as a
pushed `foreman/<workload>/issue-<n>` branch, reviewed and unopened. Until the
upstream feature lands (agent/operator opens the PR with the same token it
pushed with, `Fixes #<n>` body, skip-if-exists), a human opens the PR from the
branch. Once open, the external controls take over: the repo's own CI and the
MiniMax PR-review action; a human merges.

## Revisiting blocked PRs (request-changes, failed CI)

**What works today — detection.** Dispatch's scheduler runs **pr-followup
every 15m** (`POST /api/pr-followup/sync`). It scans tracked repos for PRs
authored by `PR_FOLLOWUP_BOT_IDENTITIES` (= `itsmiso-ai`, so all foreman PRs)
and files a `PrFixQueueItem` (deduped per repo+PR, with feedback + history)
whenever it sees:

- a `CHANGES_REQUESTED` review
- failing check runs (`failure`, `cancelled`, `timed_out`, `action_required`)
- new non-self comments on the PR
- problematic merge states (`behind`, `dirty`, `unstable`)

**What's missing — the actuator.** Nothing currently turns a `PrFixQueueItem`
into Foreman work; the fix queue predates the bridge and was consumed by the
openclaw workers. The intended completion of the loop:

> The bridge grows a third pass: poll dispatch's PR-fix queue, and for each
> `QUEUED` item create a **fix Workload** — same repo, `spec.intent` carrying
> the review feedback / CI failure text, and the coder instructed to check out
> the *existing* `foreman/*` branch and amend it (push --force-with-lease,
> pending LLMKube#934) rather than start fresh. `FIXED`/`BLOCKED` status flows
> back to the queue item. Escalation applies the same way: a fix that
> exhausts retries re-lanes to `frontier` so MiniMax-M3 gets the harder
> review feedback.

Until that lands, blocked PRs surface in the dispatch UI (`/pr-followup`) and
in the fix queue API, but a human (or an openclaw worker) has to push the
actual fix.

## Failure & escalation semantics

| Failure | Handled by | Behavior |
|---|---|---|
| Task flake (model error, transient infra) | bridge retry pass | delete + recreate Workload, ≤ 3 attempts |
| Persistently failing issue in `local` | bridge escalation | re-lane → `frontier` → MiniMax-M3 coder |
| Persistently failing issue in `frontier` | tombstone | Failed Workload kept for human triage |
| Closed issue still claimable | dispatch sync | forced to `status/done` on GitHub every sync |
| PR gets CHANGES_REQUESTED / red CI | pr-followup ingestion | `PrFixQueueItem` filed (actuator TBD, see above) |

## Config quick reference

Everything is env on this HelmRelease unless noted:

| Env | Value | Meaning |
|---|---|---|
| `DISPATCH_URL` | `http://dispatch.llm:3000` | assignment layer |
| `DISPATCH_AGENT_NAME` | `foreman-coder` | queue identity (dash, not slash) |
| `DISPATCH_LANES` | `local,frontier` | lanes polled per tick |
| `ESCALATION_LANE` | `frontier` | give-up target (bridge ≥ 0.4.0) |
| `LANE_CODER_AGENTS` | `{"*":"coder","frontier":"coder-frontier"}` | lane → coder Agent |
| `GATEPROFILE_MAP` | `{"*":{"language":"generic"}}` | no-op gate everywhere (for now) |
| `RETRY_MAX_ATTEMPTS` | 3 (default) | attempts before escalate/tombstone |

Related manifests: dispatch app + lanes (`../helmrelease.yaml`), foreman agents
(`../../foreman/agents/`: `coder`, `coder-frontier`, `gate`, `reviewer`),
foreman chart values incl. the `--foreman-namespace=llm` postRenderer
(`../../foreman/helmrelease.yaml`), MiniMax-M3 + the rest of the model catalog
(`../../litellm/app/configmap.yaml`).

## Known upstream issues

- [LLMKube#933](https://github.com/defilantech/LLMKube/issues/933) — chart
  doesn't expose the gate-Job namespace (postRenderer workaround here).
- [LLMKube#934](https://github.com/defilantech/LLMKube/issues/934) — coder
  push isn't idempotent across Workload re-runs (stale `foreman/*` branch ⇒
  non-fast-forward NO-GO); also "push to fork" wording.
- [LLMKube#935](https://github.com/defilantech/LLMKube/issues/935) — empty
  assistant message poisons the loop history (`400: Assistant message must
  contain either 'content' or 'tool_calls'`).
- [LLMKube#929](https://github.com/defilantech/LLMKube/issues/929) — coder
  self-gate should defer to a Job when the runtime is missing (blocks real
  per-language gate profiles).
