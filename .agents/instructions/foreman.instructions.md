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
- **foreman-dispatch-bridge** — every 30 min claims ready issues for
  `foreman-coder`, builds a Foreman `Workload` per issue, handles escalation,
  revision, and PR-fix. Pure glue; owns no execution.
- **Foreman** — the LLMKube operator decomposes each `Workload` into
  `AgenticTask`s (code → verify → review), schedules them onto `FleetNode`s, and
  runs the coder/gate/reviewer agents. It commits, DCO-signs, and opens the PR.

Everything here is GitOps-managed in this repo **except ad-hoc `llmkube foreman
dispatch` runs**, which are intentionally off-git (see below).

## Where things live

| Concern | Location |
| --- | --- |
| Agents, fleet HelmRelease | `kubernetes/apps/base/llm/foreman/` (this repo) |
| Bridge deploy + all routing env | `kubernetes/apps/base/llm/dispatch/foreman-dispatch-bridge/helmrelease.yaml` |
| dispatch app | `kubernetes/apps/base/llm/dispatch/` (this repo); code repo `misospace/dispatch` |
| Bridge code | `misospace/foreman-dispatch-bridge` (Python, pytest; tag-driven releases `v0.6.x`) |
| Coder toolchain images | `joryirving/containers` → `apps/llmkube-coder{,-python,-node}` |
| Upstream Foreman + CLI | `defilantech/LLMKube` |

**kubeconfig:** always
`export KUBECONFIG=/Users/jory.irving/git/personal/home-ops/kubernetes/clusters/main/kubeconfig`.
**Namespace:** `llm`. **CRDs** (`foreman.llmkube.dev/v1alpha1`): `workloads`,
`agentictasks`, `agents`, `fleetnodes`, `modelprofiles`, `agentreleases`.

## Agents and images

Two orthogonal axes: **model** (`providerConfig.model` or `inferenceServiceRef`,
served via litellm) and **toolchain** (InProcess = the fleet pod image; Job =
per-Agent `execution.image`).

| Agent | Model | Cost | Execution | Image / toolchain |
| --- | --- | --- | --- | --- |
| `coder` | `nvidia` (local) | free | InProcess (fleet) | polyglot `llmkube-coder` (Py+Node); generic/`*` + pr-fix fallback |
| `coder-python` | `nvidia` (local) | free | **Job** | `ghcr.io/joryirving/llmkube-coder-python` |
| `coder-node` | `nvidia` (local) | free | **Job** | `ghcr.io/joryirving/llmkube-coder-node` |
| `coder-go` | `llama-nvidia` (local) | free | **Job** | `ghcr.io/defilantech/llmkube-foreman-agent-coder` |
| `coder-frontier` | `MiniMax-M3-chat` (cloud) | **$ — the only cloud spend** | InProcess (fleet) | polyglot |
| `coder-revision` | `nvidia` (local) | free | InProcess (fleet) | polyglot (pr-fix / revision) |
| `gate` | none (deterministic) | free | Job (per-task) | `GATEPROFILE_MAP.image` per language |
| `reviewer` | `self-hosted` (local) | free | InProcess (fleet) | — |

**Cost model.** Everything runs on **local** models (nvidia / self-hosted) except
`coder-frontier` (**MiniMax, cloud**), which is the escalation tier only. The
groomer defaults ready work to the `local` lane; `frontier` is reached only by
bridge escalation or a deliberately-hard grooming decision, so cloud spend is
bounded to genuinely-hard work. Reviews run on the local `self-hosted` model
(they used to be cloud `dsv4f`) — reviews are now free regardless of volume.

**Coder tuning** (all coder Agents): `maxTurns: 160`,
`stuckLoopDetection.editFreeTurnsLimit: 100`, and context caps sized to the model
— nvidia (131k window): soft 100k / hard 120k; `coder-frontier` (MiniMax ~1M):
soft 500k / hard 800k. These let a coder explore a multi-file change *and*
implement it before the turn/edit/context budget trips (the old 80-turn / 24-edit
defaults were force-concluding coders mid-exploration with no diff).

**Fork fleet.** A second deployment `foreman-llmkube-agent` runs `reviewer-fork` +
`gate-fork` (roles pinned so they only take fork work) for PRs into
`defilantech/LLMKube` opened from the `joryirving/LLMKube` fork.

**The fleet pods stay polyglot on purpose.** The `foreman-agent` Deployment
(`replicaCount: 2`, `mode: native`) runs `ghcr.io/joryirving/llmkube-coder`. Those
pods (a) run the InProcess tiers (`coder`/`coder-frontier`/`coder-revision`/`reviewer`)
and (b) **orchestrate** the Job-mode agents — when a `coder-python`/`node`/`go`
task is claimed, a fleet pod spawns an ephemeral Job on that Agent's
`execution.image`. Minimal per-language images only ever appear as short-lived
Job pods, never on the fleet. Do not "upgrade" the fleet pods to a per-language
image.

Agent version alignment: image `VERSION` is Renovate-tracked to
`defilantech/LLMKube` releases; the fleet chart image tag rides the chart
AppVersion. Keep coder images and the deployed operator on the same LLMKube
release.

## Routing (all in the bridge HelmRelease `env`)

- `DISPATCH_AGENT_NAME: foreman-coder` — the dispatch-side identity the bridge
  claims as (dash, not slash — a `/` breaks the queue URL).
- `DISPATCH_LANES: local,frontier` · `ESCALATION_LANE: frontier` — base work
  grooms into `local`; exhausted issues get re-laned to `frontier`.
- `MAX_IN_PROGRESS: "10"` — cap on concurrent non-terminal Workloads.
- `LANE_CODER_AGENTS: {"*":"coder","frontier":"coder-frontier"}` — explicit
  per-lane coder; **wins outright** and is language-agnostic (keeps escalation on
  polyglot `coder-frontier`).
- `BASE_CODER_AGENTS: {"python":"coder-python","node":"coder-node","go":"coder-go","*":"coder"}`
  — base-lane routing by the repo's language. Resolution order in
  `coder_agent_for`: explicit lane match → base map by language → base map `*` →
  lane wildcard → default `coder`. Empty map = legacy behavior.
- `GATEPROFILE_MAP` — repo → `{language, image, commands{format,lint,build,test}}`.
  Defines a repo's language (used by BASE_CODER_AGENTS) and its clean-room gate.
  **Each `test` command mirrors the repo's own CI: install deps + run the real
  suite** (e.g. `pip install -r requirements.txt && pytest`, `npm run test`), not
  a no-op. A weak gate (`test: "true"`) rubber-stamps GATE-PASS on changes that
  then fail real CI — the root cause of the pr-fix churn we removed. Add a repo
  here to onboard it, and match its CI's test/lint commands.
- `REVISION_CODER_AGENTS: {"*":"coder-revision"}` — reviewer-requested revisions.
- `PR_FIX_ENABLED: "true"`, `PR_FIX_MAX_ATTEMPTS: "3"`,
  `PR_FIX_LANE_AGENTS: {"NORMAL":"coder","ESCALATED":"coder-frontier"}` — PR-fix
  loop: when an open PR fails CI or gets `CHANGES_REQUESTED`, it re-pushes a fix.
  **Escalation ladder (bridge 0.6.6+):** a fix exhausts `max_attempts` on the
  base coder (`NORMAL`) → auto-escalates to `ESCALATED` (`coder-frontier`) with a
  fresh budget → only marks `NEEDS_HUMAN` when *every* coder tier is exhausted. A
  human is the last resort, not the first, for a fix a coder couldn't do.

To onboard a new language coder: build a minimal image in `containers`
(`apps/llmkube-coder/` is the pattern — one runtime + git + that language's
linters), add a Job-mode Agent here, and map the language in `BASE_CODER_AGENTS`.
Requires a bridge release (`v0.6.x`) only if you change routing *code*; config
changes are HelmRelease-only.

## Ad-hoc dispatch (off-git, bypasses dispatch + bridge)

`llmkube foreman dispatch` creates `AgenticTask`s directly against the cluster —
no git, no dispatch, no bridge. Use it to dogfood a specific PR (e.g. an LLMKube
issue) or force work through a chosen Agent. These runs are **never committed**;
only the Agent definitions are GitOps config.

```bash
export KUBECONFIG=/Users/jory.irving/git/personal/home-ops/kubernetes/clusters/main/kubeconfig
export GITHUB_TOKEN=<token>            # reads issue title/body from GitHub

# Dogfood LLMKube issue 892 on the Go coder — dry-run first to preview the task:
llmkube foreman dispatch --repo defilantech/LLMKube --agents coder-go -n llm --dry-run 892
# then run it for real:
llmkube foreman dispatch --repo defilantech/LLMKube --agents coder-go -n llm 892

# Fan several issues across coders (round-robins the --agents list):
llmkube foreman dispatch --repo defilantech/LLMKube --agents coder-go -n llm 892 901 905

# Force a misospace issue onto a specific coder, custom base branch, no wait:
llmkube foreman dispatch --repo misospace/KubeTix --agents coder-python -n llm \
  --base-branch main --no-wait 153
```

Flags: `--repo owner/repo` (req), `--agents a,b` (req, round-robin), `-n/--namespace`
(default `default`; use `llm`), `--dry-run`, `--no-wait`, `--timeout`,
`--base-branch`, `--branch-prefix`, `--prompt-file ISSUE=PATH`, `--poll-interval`.

**Caveat:** `dispatch` creates **standalone coder tasks** (code → PR), *not* the
full `Workload` pipeline (code → verify → review). For a self-verifying,
self-reviewed run go through dispatch/bridge instead.

## Common operations

```bash
export KUBECONFIG=/Users/jory.irving/git/personal/home-ops/kubernetes/clusters/main/kubeconfig

# Fleet + agents + operator health
kubectl -n llm get pods | grep -E 'foreman|agent' | grep -v gate
kubectl -n llm get agents
kubectl -n llm get fleetnodes

# What did each Workload dispatch to, and its phase
kubectl -n llm get workloads -o custom-columns=\
'NAME:.metadata.name,CODER:.spec.coderAgentRef.name,PHASE:.status.phase'

# Bridge: it's a CronJob (schedule "30 */1 * * *"), not a Deployment
kubectl -n llm get cronjob foreman-dispatch-bridge \
  -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}{"\n"}'
# Force a bridge tick now (same as the :30 run); inspect its log:
kubectl -n llm create job --from=cronjob/foreman-dispatch-bridge bridge-manual
kubectl -n llm logs job/bridge-manual
kubectl -n llm delete job bridge-manual
```

### Retrigger a failed Workload

There is no retry verb. The `WorkloadReconciler` re-renders and recreates the
pipeline whenever a Workload has **zero** child `AgenticTask`s (independent of
phase). So delete *all* children:

```bash
WL=wl-misospace-kubetix-153
kubectl -n llm get agentictasks -o name | grep "${WL#wl-}" \
  | xargs -r kubectl -n llm delete
```

- Deleting only the failed children does **not** re-run — any surviving child
  makes the reconciler roll up instead of re-render.
- The re-run uses the Workload's baked `coderAgentRef` (e.g. an old Workload
  still says `coder`, not `coder-python`). To pick up current routing you must
  recreate the *Workload* via the bridge: delete the Workload CR and re-open the
  issue in dispatch so the next tick rebuilds it.

### Apply an Agent prompt/config change

InProcess agents (`reviewer`, `coder*`, and the fork `reviewer-fork`/`gate-fork`)
load their Agent CR `spec.systemPrompt` **at pod startup and cache it**. Editing
the Agent CR — even committed, Flux-reconciled, and confirmed live via
`kubectl -n llm get agent <name> -o jsonpath='{.spec.systemPrompt}'` — does
**not** touch the running pods. You must restart the fleet:

```bash
kubectl -n llm rollout restart deployment/foreman-agent deployment/foreman-llmkube-agent
kubectl -n llm rollout status deployment/foreman-agent
```

- Symptom when forgotten: PRs opened *hours after* a prompt change still show the
  old behavior. Diagnose by comparing the PR `createdAt` to the fix commit time
  and the agent pod age (`kubectl -n llm get pods | grep foreman-agent`) — a pod
  older than the fix has the stale prompt.
- Coders run as Job-mode pods (separate), so the restart doesn't kill in-flight
  coder Jobs. Time it while Workloads are pre-review to avoid interrupting
  InProcess review/gate tasks (they requeue, but it wastes a run).

## Gotchas

- **Agent CR changes need a fleet restart** — see "Apply an Agent prompt/config
  change" above. Editing `systemPrompt` / `providerConfig.model` / `maxTurns` /
  `stuckLoopDetection` silently no-ops on the running pods until a
  `rollout restart`. This is the #1 way a change appears applied but isn't.
- **Reviewer prompt must keep "Step 1: navigate to the branch."** Foreman does
  NOT check out the PR branch for the reviewer or inject a diff — it hands over
  the branch name and relies on the reviewer system prompt to
  `git fetch origin <branch> && git checkout origin/<branch>` first. Drop that
  step (easy to do when trimming the prompt) and every review diffs `main` →
  phantom diffs → false NO-GOs. `reviewer.yaml` / `reviewer-fork.yaml` carry it.
- **InProcess throughput ceiling.** All reviews + frontier coding + prfix
  revisions run InProcess on the 2 `foreman-agent` replicas, so a grooming flood
  queues tasks (`Pending`) behind that cap and workloads sit in `Dispatched` until
  a replica frees. It self-drains and reviews are local/free, so it's latency not
  cost. Levers if it matters: raise replicas (more local concurrency) or lower
  `MAX_IN_PROGRESS`.
- **Long runs can hit the wall-clock budget.** With `maxTurns: 160`, a genuinely
  large change can exhaust the loop's wall-clock timeout before finishing
  (`loop wall-clock budget exhausted`) — surfaces as a Failed Workload the
  escalation ladder then retries on the stronger coder.
- **Never edit via bash in a coder prompt** — the harness only sees `write_file` /
  `str_replace` edits; bash edits (`sed`/`echo`/`git apply`) count as no progress
  and trip the stuck-loop detector. Coders must also leave changes uncommitted
  (the harness stages/commits/DCO-signs/pushes).

## Open items

- **NO-GO "already-resolved" surfacing (not yet automated).** When a coder judges
  an issue already fixed, its `*-code-*` task returns `result.verdict: NO-GO` /
  `result.extra.outcome: MODEL-DECIDED` with a summary and no diff; verify/review
  cascade to `INCOMPLETE` and the Workload rolls up `Failed`. These are currently
  reconciled **by hand**: read the code task's summary, confirm the claim against
  the actual code, then `status/done` + close the issue — or re-dispatch if the
  claim is wrong. A NO-GO is a *model claim*, not a guarantee (a coder once matched
  unrelated code and falsely claimed "fixed"), so confirm before closing.
  Auto-handling (surface-first, opt-in auto-close) is not built.
- **Reviewer fork-base diff (upstream fix pending).** A fork reviewer diffing
  `main...HEAD` against a stale fork `main` sweeps in the upstream delta. Fixed
  upstream in `defilantech/LLMKube` #1006; arrives with the next Foreman
  release/image bump.
- **Agent-config hot-reload (upstream nice-to-have).** The "Agent CR changes need
  a fleet restart" gotcha is a papercut worth an upstream request (agent should
  watch/reload its CR, or foreman should signal a restart is required).

## Change conventions

- **Config** (Agents, HelmRelease env, `GATEPROFILE_MAP`): edit YAML in this repo,
  PR → Flux reconciles. **Remember the fleet restart** for Agent CR changes.
- **Bridge code** (`misospace/foreman-dispatch-bridge`, Python/pytest): PR → tag
  `v0.6.x` (patch-bump) → CI publishes the image → bump the tag+digest in the
  bridge HelmRelease here.
- **dispatch** (`misospace/dispatch`, Next.js) is **chart-managed**: the
  `manual-release` workflow opens a version-bump release PR (auto-merge) →
  `publish-release` tags + publishes an OCI chart
  `ghcr.io/misospace/charts/dispatch:<ver>` → Renovate bumps the `dispatch`
  OCIRepository `ref.tag` here → Flux rolls it out. No image override in the
  HelmRelease anymore — bump = chart-tag bump.
- **Coder images** (`joryirving/containers`): PR → CI publishes; Renovate-tracked
  to LLMKube releases. Grouped so golang + LLMKube-version bumps collapse into one
  `llmkube-coders` PR (containers `.renovaterc.json5`); the foreman chart + coder
  images are the `LLMKube` group in this repo's `.renovate/groups.json5`.
- Keep config edits bare — no narration comments; rationale goes in the PR body.
- Ad-hoc runs (`llmkube foreman dispatch`, or the `task foreman:dispatch` /
  `foreman:revise` helpers in `.taskfiles/foreman/`) are never committed.

## Current versions (snapshot, 2026-07-08)

Bridge `0.6.6` · dispatch chart `0.5.22` · Foreman/coder images `0.9.x` (nvidia
local base coders, MiniMax `coder-frontier`, self-hosted `reviewer`). Update this
line when you cut a release so the next operator has a baseline.
