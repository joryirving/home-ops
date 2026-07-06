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

Two orthogonal axes: **model tier** (`providerConfig.model`, remote via litellm)
and **toolchain** (InProcess = the fleet pod image; Job = per-Agent
`execution.image`). Models are always remote, so the image only supplies the
language toolchain.

| Agent | Tier / model | Execution | Image / toolchain |
| --- | --- | --- | --- |
| `coder` | base / `nvidia` | InProcess (fleet) | polyglot `llmkube-coder` (Py+Node). Generic/`*` + pr-fix fallback |
| `coder-python` | base / `nvidia` | **Job** | `ghcr.io/joryirving/llmkube-coder-python` |
| `coder-node` | base / `nvidia` | **Job** | `ghcr.io/joryirving/llmkube-coder-node` |
| `coder-go` | `MiniMax-M3-chat` | **Job** | `ghcr.io/defilantech/llmkube-foreman-agent-coder` (upstream) |
| `coder-frontier` | escalation / `MiniMax-M3-chat` | InProcess (fleet) | polyglot |
| `coder-revision` | reviewer-revision / `nvidia` | InProcess (fleet) | polyglot |
| `gate` | verifier (no LLM) | Job (per-task) | `GATEPROFILE_MAP.image` per language |
| `reviewer` | `dsv4f` (DeepSeek) | InProcess | — |

**The fleet pods stay polyglot on purpose.** The `foreman-agent-*` Deployment
(`replicaCount: 3`, `mode: native`) runs `ghcr.io/joryirving/llmkube-coder`. Those
pods (a) run the InProcess polyglot tiers (`coder`/`coder-frontier`/`coder-revision`)
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
  This is where a repo's language (used by BASE_CODER_AGENTS) and its clean-room
  gate image/commands are defined. Add a repo here to onboard it.
- `REVISION_CODER_AGENTS: {"*":"coder-revision"}` — reviewer-requested revisions.
- `PR_FIX_ENABLED: "true"`, `PR_FIX_MAX_ATTEMPTS: "3"`,
  `PR_FIX_LANE_AGENTS: {"NORMAL":"coder","ESCALATED":"coder-frontier"}` — PR-fix
  loop (re-pushes fixes onto an open PR when mergeability/CI fails).

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

## Known issues / gotchas

- **Escalation `unclaim` 400 (active blocker).** Failed Workloads try to escalate
  → the bridge calls dispatch `POST /api/issues/unclaim` → `400 Bad Request` → the
  issue stays wedged at its attempt cap and never re-lanes. Logs show
  `wl-…:escalate-error:400 … /api/issues/unclaim`. This starves the base lane, so
  the per-language coders can sit idle even when there's a backlog. Fixing this is
  the highest-value flow unblocker; look at the dispatch `unclaim` endpoint's
  expected payload vs what the bridge (0.6.4) sends.
- **Lane-less ready issues** were a past flow-blocker (groomer left `currentLane`
  unset → queue filtered them out). Fixed in dispatch; if idle-with-ready-issues
  recurs, re-check `currentLane` assignment.
- **pr-fix false FIXED** — older bridges marked a PR fixed without re-checking
  GitHub mergeability; fixed in bridge (verifies `mergeable_state`).
- **Stuck-loop (EditFreeStreak)** — coders (esp. MiniMax) burn turns without a
  structured edit. Interim mitigation: `stuckLoopDetection.editFreeTurnsLimit: 24`
  on the coder Agents. Durable fix is upstream (LLMKube harness: count bash edits).
- **Never edit via bash in a coder prompt** — the harness only sees `write_file`/
  `str_replace` edits; bash edits (`sed`/`echo`/`git apply`) count as no progress
  and trip the stuck-loop detector. Coders must also leave changes uncommitted
  (the harness stages/commits/DCO-signs/pushes).

## Next work: NO-GO / "already-resolved" handling (spec)

**Problem.** When a coder decides an issue is already fixed it returns a
*Succeeded* code task with `result.verdict: NO-GO` and
`result.extra.outcome: MODEL-DECIDED` (plus a summary citing the file/commit),
and makes no change. `verify` and `review` then return `INCOMPLETE`, so the
Workload rolls up to `Failed` — indistinguishable from a real failure, so
`retry.py` escalates it (→ frontier → attempt cap → the `unclaim` 400). A
genuinely-done issue burns cycles and wedges, silently. Worked example:
`wl-misospace-kubetix-152` (#152).

**Signal.** On the Workload's `*-code-*` AgenticTask:
`status.result.verdict == "NO-GO"` (equivalently `result.extra.outcome ==
"MODEL-DECIDED"` with no diff). Read it from the code task, not the Workload phase.

**Where.** `bridge/retry.py`, in the failure-reconciliation path, **before**
escalation: if a `Failed` Workload's code task is NO-GO, short-circuit — do not
escalate, do not retry.

**Behavior** — surface by default, auto-close opt-in via `NOGO_AUTOCLOSE`
(default `false`):

- Always: post the coder's `summary` as a comment on the GitHub issue (so the
  cited file/commit is visible) and unclaim the dispatch issue so it leaves the
  active queue.
- `NOGO_AUTOCLOSE=false` (default): set the dispatch issue to a distinct status
  (`status/needs-review`, or an `already-resolved?` label) and STOP. A human
  confirms and closes; do **not** close the GitHub issue.
- `NOGO_AUTOCLOSE=true`: set dispatch `status/done` and close the GitHub issue,
  using the coder summary as the closing comment.

**Why surface-first.** A NO-GO verdict is a model claim, not a guarantee. #256 is
the cautionary case: the coder falsely claimed "already fixed" by matching
unrelated code; auto-closing there would have buried a real bug. The coder prompt
guard ("confirm the code at the exact place the issue names already does what the
issue asks") raises trust but does not remove the risk — default to human
confirmation, let the operator opt into auto-close once the verdict is trusted.

**Tests.** NO-GO code task → surfaced, not escalated (default); `NOGO_AUTOCLOSE=true`
→ dispatch `status/done` + GitHub issue closed; a real `Failed` with no NO-GO →
still escalates as today. Bridge is Python/pytest; ship behind a `v0.6.x` release,
then bump the tag+digest in the bridge HelmRelease.

## Change conventions

- Config (Agents, HelmRelease env, `GATEPROFILE_MAP`): edit YAML in this repo,
  PR → Flux reconciles. Bridge *code* changes: PR to
  `misospace/foreman-dispatch-bridge`, then tag `v0.6.x` (patch-bump convention)
  to publish the image, then bump the tag+digest in the bridge HelmRelease.
- Coder images: PR to `joryirving/containers`; CI publishes; reference by
  `:<VERSION>` (Renovate-tracked to LLMKube releases).
- Keep config edits bare — no narration comments; rationale goes in the PR body.
- Ad-hoc `llmkube foreman dispatch` requests are never committed.
