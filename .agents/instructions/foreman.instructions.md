# Foreman coding-automation operations

Operational guide for the self-hosted GitOps coding loop that turns GitHub
issues into reviewed, self-opened PRs. Hand this to an agent that needs to run,
extend, or debug the loop.

## The loop

```
dispatch (Next.js)  --groom/claim-->  foreman-dispatch-bridge (Python CronJob)  --Workload CR-->  LLMKube Foreman (operator + agents)  --PR-->  GitHub
```

- **dispatch** — hosted-LLM groomer labels issues `status/ready` and assigns a
  `currentLane` (`local` | `frontier`). Exposes a per-agent queue the bridge polls.
- **foreman-dispatch-bridge** — every 15 min claims ready issues for
  `foreman-coder`, builds a Foreman `Workload` per issue, handles escalation,
  revision, and PR-fix. Pure glue; owns no execution.
- **Foreman** — the LLMKube operator decomposes each `Workload` into
  `AgenticTask`s (**code → review**, no verify gate: the `gate` agent and the
  `VERIFY_ENABLED` flag are both gone — verification is the coder's own in-loop
  self-test plus the repo's real CI on the opened PR), schedules them onto
  `FleetNode`s, and runs the coder/reviewer agents. It commits, DCO-signs, and
  opens the PR.

Everything here is GitOps-managed in this repo **except ad-hoc `llmkube foreman
dispatch` runs**, which are intentionally off-git (see below).

## Where things live

| Concern | Location |
| --- | --- |
| Agents, fleet HelmRelease | `kubernetes/apps/base/llm/foreman/` (this repo) |
| Bridge deploy + all routing env | `kubernetes/apps/base/llm/dispatch/foreman-dispatch-bridge/helmrelease.yaml` |
| dispatch app | `kubernetes/apps/base/llm/dispatch/` (this repo); code repo `misospace/dispatch` |
| Bridge code | `misospace/foreman-dispatch-bridge` (Python, pytest; release-please tags `v0.9.x`) |
| Coder toolchain images | `misospace/llmkube-images` |
| Upstream Foreman + CLI | `defilantech/LLMKube` |

**Namespace:** `llm`. **CRDs** (`foreman.llmkube.dev/v1alpha1`): `workloads`,
`agentictasks`, `agents`, `fleetnodes`, `modelprofiles`, `agentreleases`.

## Agents and images

Two orthogonal axes: **model** (`providerConfig.model`, served via litellm) and
**execution** (InProcess = runs inside the fleet pod; Job = an ephemeral
per-task pod on the Agent's `execution.image`). All three coders run **Job**;
both reviewers run **InProcess**. The per-language coder split
(`coder-python`/`node`/`go`) and the deterministic `gate` agent are both gone —
one polyglot `llmkube-coder` image serves every coder.

| Agent | Model | Cost | Execution | Toolchain |
| --- | --- | --- | --- | --- |
| `coder` | `qwen3.8-27b` (local) | free | **Job** | polyglot `llmkube-coder`; base lane + generic `*` + pr-fix fallback |
| `coder-frontier` | `MiniMax-M3-chat` (cloud) | **$** | **Job** | polyglot; escalation lane + pr-fix |
| `coder-revision` | `MiniMax-M3-chat` (cloud) | **$** | **Job** | polyglot; reviewer-requested revisions |
| `reviewer` | `gemma-4-12b-it-qat` (local) | free | InProcess (fleet) | — |
| `reviewer-fork` | `gemma-4-12b-it-qat` (local) | free | InProcess (fork fleet) | — |

Every LLM agent (all coders + both reviewers) has `spec.mcp` enabled with the
hosted context7 server (`resolve-library-id`, `query-docs`) for up-to-date
library docs mid-task; auth rides the `CONTEXT7_API_KEY` header from the
`foreman-agent` Secret (1Password `context7` item, `OPENCODE_API_KEY`
field). Adding another MCP server = add a `servers` entry per agent + any
header secret.

**Cost model.** Only the base `coder` (`qwen3.8-27b`, local) is free. Escalation
(`coder-frontier`), reviewer-requested revisions (`coder-revision`), and the
**entire pr-fix loop** run on **MiniMax-M3-chat (cloud)** — the only cloud spend.
The groomer defaults ready work to the `local` lane; `frontier` is reached only
by bridge escalation or a deliberately-hard grooming decision, so cloud spend is
bounded to genuinely-hard work plus fixes. Reviews run on the local
`gemma-4-12b-it-qat` — free regardless of volume, and a deliberate family split
from the Qwen coder so the reviewer does not inherit the coder's blind spots.

**Coder tuning.** `coder` (qwen3.8-27b, 80k window): `maxTurns: 160`,
`editFreeTurnsLimit: 90`, `repeatedToolThreshold: 5`, context soft 85k / hard
98k, `contextStrategy: session`. `coder-frontier` / `coder-revision`
(MiniMax ~1M, 480k window): same turn/edit budgets, context soft 500k / hard
800k. Wall-clock is a backstop, not the limit that bites — the turn/edit/context
caps bound the loop semantically.

**The fleet.** The `foreman` HelmRelease runs two `native`-mode deployments off
`ghcr.io/misospace/llmkube-coder`: **`foreman-default-agent`** (`replicaCount: 2`,
roles worker/coder/verifier) for misospace work, and **`foreman-llmkube-agent`**
(the fork fleet, below). Reviewers run **InProcess** on these pods; coders run as
**Job**-mode pods that select a node without reserving it (LLMKube#1496), so
coder concurrency is capped by the bridge's `CODER_AGENT_SLOTS`, not by replicas
— one FleetNode was observed carrying two Job coders and a review at once.

**Fork fleet.** `foreman-llmkube-agent` (`replicaCount: 1`) is role-pinned to
`coder-fork` / `verifier-fork` / `reviewer-fork` so the whole pipeline for a PR
into `defilantech/LLMKube` runs there, clones+pushes the `joryirving/LLMKube`
fork, and opens a cross-repo PR upstream. It commits as Jory
(`jory@jory.dev`); the default fleet commits as Saffron. misospace work
(roles worker/coder/verifier) never lands here.

Agent version alignment: coder images are Renovate-tracked to `defilantech/LLMKube`
releases; the fleet chart image tag rides the chart AppVersion. Keep coder images
and the deployed operator on the same LLMKube release (both `0.9.25` as of this
snapshot).

## Routing (all in the bridge HelmRelease `env`)

- `DISPATCH_AGENT_NAME: foreman-coder` — the dispatch-side identity the bridge
  claims as (dash, not slash — a `/` breaks the queue URL).
- **Lanes are discovered, not hardcoded.** `DISPATCH_LANES` / `ESCALATION_LANE`
  are gone: the bridge reads the lane set from dispatch's `GET /api/lanes` and
  resolves the escalation lane by **role**. Base work grooms into the
  `default`-role lane (`local`); exhausted issues re-lane to the
  `escalation`-role lane (`frontier`). Explicit config still wins if set; unset =
  discovered.
- `LANE_CODER_AGENTS: {"*":["coder"],"escalation":["coder-frontier"]}` —
  **role-keyed** (not lane-id-keyed) coder routing; the value is a list.
  Precedence in `lanes.lookup`: exact lane id → lane's role → `*` wildcard. Keeps
  escalation on cloud `coder-frontier` however the lane is named.
- `CODER_AGENT_SLOTS: {"coder":1,"coder-frontier":4}` — per-coder concurrency
  cap. Job-mode coders are not capped by fleet replicas, so this is the real
  limit: a lane's work goes to the coder with the most idle slots, and when every
  candidate is full the lane does not claim that tick. Empty = legacy
  issue-number hash split.
- `MAX_IN_PROGRESS: "14"` — cap on concurrent non-terminal Workloads. Each lane
  drains up to the remaining headroom, so a backlog fills capacity in one tick.
- `VERDICT_SELF_GO: "code-fix,docs,packaging,config,ci-policy"` — work classes
  stamped onto every Workload's `spec.verdictPolicy.selfGO`, letting the coder
  self-GO (skip the separate review stage) for those change classes. Widen only
  for fleets whose PRs run the changed workflow, get an AI review, and are merged
  by hand; empty leaves Foreman's default policy untouched.
- `GATEPROFILE_MAP` — repo → `{testLayout, sourceExtensions}`. Gates never run,
  so the old `language` / `commands` / `image` keys are gone; what survives:
  - `testLayout` (`{testRoot, sourceRoot}`) tells the coder self-gate where the
    repo's tests and source live.
  - `sourceExtensions` (e.g. `[".gd"]` for windowstead, `[".ex",".exs",".heex"]`
    for pinchflat) tells the reviewer's scope-overlap check which files count as
    the repo's source (LLMKube#1120). The `*` entry carries the Go/HCL default.
  Onboarding a repo = add `{testLayout, sourceExtensions}` here.
- `REVISION_CODER_AGENTS: {"*":"coder-revision"}` — reviewer-requested revisions
  (cloud MiniMax).
- `PR_FIX_ENABLED: "true"`, `PR_FIX_MAX_ATTEMPTS: "4"`,
  `PR_FIX_LANE_AGENTS: {"NORMAL":"coder-frontier","ESCALATED":"coder-frontier"}` —
  PR-fix loop: when an open PR fails CI or gets `CHANGES_REQUESTED`, it re-pushes
  a fix (both tiers on cloud `coder-frontier`). dispatch routes an AI-reviewer
  (Saffron) `CHANGES_REQUESTED` into this loop by parsing its structured
  `ai-pr-reviewer` findings instead of dead-ending at `needs-human`; a prose-only
  review with no parseable findings still escalates to a human.
  **Escalation ladder:** a fix exhausts `max_attempts` on `NORMAL` →
  auto-escalates to `ESCALATED` with a fresh budget → only marks `NEEDS_HUMAN`
  when every coder tier is exhausted. A human is the last resort.

Terminal-Workload GC is on by default (`PRUNE_COMPLETED_AFTER_HOURS`,
`PRUNE_FAILED_AFTER_HOURS` unset = 6h / 48h): each tick after reconcile the
bridge deletes Completed Workloads older than 6h (the PR already lives on GitHub)
and Failed ones older than 48h, so terminal Workloads no longer need manual
`kubectl delete`.

Onboarding a repo is config-only (`GATEPROFILE_MAP` + labels); a bridge release
(`v0.9.x`) is needed only when you change routing *code*.

## Ad-hoc dispatch (off-git, bypasses dispatch + bridge)

`llmkube foreman dispatch` creates `AgenticTask`s directly against the cluster —
no git, no dispatch, no bridge. Use it to dogfood a specific PR (e.g. an LLMKube
issue) or force work through a chosen Agent. These runs are **never committed**;
only the Agent definitions are GitOps config.

```bash
export GITHUB_TOKEN=<token>            # reads issue title/body from GitHub

# Dogfood LLMKube issue 892 on the coder — dry-run first to preview the task:
llmkube foreman dispatch --repo defilantech/LLMKube --agents coder -n llm --dry-run 892
# then run it for real:
llmkube foreman dispatch --repo defilantech/LLMKube --agents coder -n llm 892

# Fan several issues across coders (round-robins the --agents list):
llmkube foreman dispatch --repo defilantech/LLMKube --agents coder,coder-frontier -n llm 892 901 905

# Force a misospace issue onto the cloud coder, custom base branch, no wait:
llmkube foreman dispatch --repo misospace/KubeTix --agents coder-frontier -n llm \
  --base-branch main --no-wait 153
```

Flags: `--repo owner/repo` (req), `--agents a,b` (req, round-robin), `-n/--namespace`
(default `default`; use `llm`), `--dry-run`, `--no-wait`, `--timeout`,
`--base-branch`, `--branch-prefix`, `--prompt-file ISSUE=PATH`, `--poll-interval`.

**Caveat:** `dispatch` creates **standalone coder tasks** (code → PR), *not* the
full `Workload` pipeline (code → review). For a self-reviewing,
self-reviewed run go through dispatch/bridge instead.

## Common operations

```bash
# Fleet + agents + operator health
kubectl -n llm get pods | grep -E 'foreman|agent'
kubectl -n llm get agents
kubectl -n llm get fleetnodes

# What did each Workload dispatch to, and its phase
kubectl -n llm get workloads -o custom-columns=\
'NAME:.metadata.name,CODER:.spec.coderAgentRef.name,PHASE:.status.phase'

# Bridge: it's a CronJob (schedule "*/15 * * * *"), not a Deployment
kubectl -n llm get cronjob foreman-dispatch-bridge \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}{"\n"}'
# Force a bridge tick now (same as the :30 run); inspect its log:
kubectl -n llm create job --from=cronjob/foreman-dispatch-bridge bridge-manual
kubectl -n llm logs job/bridge-manual
kubectl -n llm delete job bridge-manual
```

### Retrigger a failed Workload (issue-state first!)

**Deleting a Workload does NOT reset its issue.** The issue stays
`status/in-progress` + claimed (`agent/foreman-coder` label + lease), which the
queue never serves again — a stranded issue (this bit twice: 17 strands on
2026-07-21, 24 on 2026-07-29). The claim label and the lane both gate
claimability: `ready` + still-labeled is dead, and `ready` without a
`currentLane` is equally dead (lanes are only assigned by the groomer, whose
candidates are `backlog`).

The correct re-run flow:

1. **Unclaim via dispatch** — the `unclaim_issue` MCP tool or the dispatch UI
   (NOT raw `gh` label edits): removes the agent label, releases the lease,
   flips `in-progress → ready`, and **keeps the groomed lane**, so the next
   bridge tick re-claims it.
2. Delete the Workload CR. The bridge rebuilds it with **current** routing/
   config (a re-rendered old Workload would reuse its baked `coderAgentRef`).

Most of this now self-heals: a per-tick reconcile resets issues that are
in-progress with no live Workload and no open PR, and the Failed-workload GC
unclaims at prune time, so manual strands recover within a tick. And when a coder
judges an issue **already resolved** on the base branch (`NO-GO` +
`extra.modelExtra.outcome: ALREADY-RESOLVED`), the bridge now closes the GitHub
issue with the coder's evidence instead of stranding it — no hand-reconcile
needed. A NO-GO is still a *model claim*, so the close comment carries the
evidence for a human to reopen if it was wrong.

Dispatch MCP tools for manual surgery when you do need it: `unclaim_issue`,
`get_queue`, `list_issues`, `list_pr_fixes`, `mark_pr_fix`, `run_groomer`
(groom now instead of waiting out the cron).

### Apply an Agent prompt/config change

The **InProcess** agents — `reviewer` and the fork `reviewer-fork` — load their
Agent CR `spec.systemPrompt` **at pod startup and cache it**. Editing the Agent
CR — even committed, Flux-reconciled, and confirmed live via
`kubectl -n llm get agent <name> -o jsonpath='{.spec.systemPrompt}'` — does
**not** touch the running fleet pods. You must restart the fleet:

```bash
kubectl -n llm rollout restart deployment/foreman-default-agent deployment/foreman-llmkube-agent
kubectl -n llm rollout status deployment/foreman-default-agent
```

- Symptom when forgotten: reviews *hours after* a reviewer-prompt change still
  show the old behavior. Diagnose by comparing the review time to the fix commit
  and the agent pod age (`kubectl -n llm get pods | grep foreman.*agent`) — a pod
  older than the fix has the stale prompt.
- **Coders do not need this.** They run as Job-mode pods that load the Agent CR
  fresh at task start, so a coder `systemPrompt` / `model` / `maxTurns` /
  `stuckLoopDetection` change takes effect on the **next** coder task with no
  restart. The restart only re-reads the InProcess reviewers, and it doesn't kill
  in-flight coder Jobs — time it while Workloads are pre-review so you don't
  interrupt a running review (it requeues, but wastes a run).

## Gotchas

- **Reviewer CR changes need a fleet restart** — see "Apply an Agent prompt/config
  change" above. Editing an InProcess reviewer's `systemPrompt` /
  `providerConfig.model` silently no-ops on the running pods until a
  `rollout restart`. (Job-mode coders reload per task and do *not* need this.)
  This is the #1 way a reviewer change appears applied but isn't.
- **Reviewer prompt must keep "Step 1: navigate to the branch."** Foreman does
  NOT check out the PR branch for the reviewer or inject a diff — it hands over
  the branch name and relies on the reviewer system prompt to
  `git fetch origin <branch> && git checkout origin/<branch>` first. Drop that
  step (easy to do when trimming the prompt) and every review diffs `main` →
  phantom diffs → false NO-GOs. `reviewer.yaml` / `reviewer-fork.yaml` carry it.
- **Review throughput ceiling.** Reviews run InProcess on the 2
  `foreman-default-agent` replicas (and the reviewer backend runs `--parallel 2`),
  so a flood of review-ready Workloads queues behind that cap. It self-drains and
  reviews are local/free, so it's latency not cost. Coders are unaffected — they
  are Job-mode and capped separately by `CODER_AGENT_SLOTS`. Levers if review
  latency matters: raise `foreman-default-agent` replicas or lower `MAX_IN_PROGRESS`.
- **Long runs can hit the wall-clock budget.** With `maxTurns: 160`, a genuinely
  large change can exhaust the loop's wall-clock timeout before finishing
  (`loop wall-clock budget exhausted`) — surfaces as a Failed Workload the
  escalation ladder then retries on the stronger coder.
- **Never edit via bash in a coder prompt** — the harness only sees `write_file` /
  `str_replace` edits; bash edits (`sed`/`echo`/`git apply`) count as no progress
  and trip the stuck-loop detector. Coders must also leave changes uncommitted
  (the harness stages/commits/DCO-signs/pushes).

## Open items

- **Agent-config hot-reload (upstream nice-to-have).** The "Reviewer CR changes
  need a fleet restart" gotcha is a papercut worth an upstream request (the
  InProcess reviewer should watch/reload its CR, or foreman should signal a
  restart is required). Coders already reload per Job.
- **FleetNode orphaning (upstream LLMKube#1778).** FleetNode CRs carry no
  `ownerReferences`, so a pod replacement (node reboot, rollout, eviction)
  strands the old CR — its heartbeat freezes and `ForemanFleetNodeHeartbeatStale`
  fires forever. Restarting does not clear it; `kubectl delete fleetnode <orphan>`
  does. Check with: for each FleetNode, `kubectl -n llm get pod <name>` — a
  NotFound is an orphan. The stale-alert annotation is also wrong (`$labels.node`
  vs the metric's `name`): LLMKube#1779.

## Change conventions

- **Config** (Agents, HelmRelease env, `GATEPROFILE_MAP`): edit YAML in this repo,
  PR → Flux reconciles. **Remember the fleet restart** for Agent CR changes.
- **Bridge code** (`misospace/foreman-dispatch-bridge`, Python/pytest): PR →
  release-please cuts `v0.9.x` → CI publishes the image → Renovate bumps the
  tag+digest in the bridge HelmRelease here.
- **dispatch** (`misospace/dispatch`, Next.js) is **chart-managed**: the
  `manual-release` workflow opens a version-bump release PR (auto-merge) →
  `publish-release` tags + publishes an OCI chart
  `ghcr.io/misospace/charts/dispatch:<ver>` → Renovate bumps the `dispatch`
  OCIRepository `ref.tag` here → Flux rolls it out. No image override in the
  HelmRelease anymore — bump = chart-tag bump.
- **Coder images** (`misospace/llmkube-images`): PR → CI publishes; Renovate-tracked
  to LLMKube releases. Grouped so golang + LLMKube-version bumps collapse into one
  `llmkube-coders` PR (`llmkube-images/.renovaterc.json5`); the foreman chart + coder
  images are the `LLMKube` group in this repo's `.renovate/groups.json5`.
- Keep config edits bare — no narration comments; rationale goes in the PR body.
- Ad-hoc runs (`llmkube foreman dispatch`, or the `task foreman:dispatch` /
  `foreman:revise` helpers in `.taskfiles/foreman/`) are never committed.

## Current versions (snapshot, 2026-09-08)

Bridge `0.9.0` · dispatch chart `0.5.57` · Foreman operator `0.9.25` / coder
images `0.9.25` (aligned). No verify gate (gateless is permanent — `gate` agent
and `VERIFY_ENABLED` both removed). Local base coder `qwen3.8-27b`; cloud
`MiniMax-M3-chat` for `coder-frontier` / `coder-revision` / pr-fix; local reviewer
`gemma-4-12b-it-qat`. Lanes discovered from dispatch, coders route by role +
`CODER_AGENT_SLOTS`. Update this line when you cut a release so the next operator
has a baseline.
