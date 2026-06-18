# LLM Strategy

How the LLM fleet is subscribed, wired, and used — and where smart-routing is headed.

Everything funnels through **LiteLLM** (`kubernetes/apps/base/llm/litellm/app/configmap.yaml`) at
`http://litellm.llm:4000`. Clients address stable aliases; LiteLLM forwards to the upstream a given
subscription or local server expects. This doc is the reference for keeping those aliases meaningful
and for designing intent-based routing on top of them.

## Subscriptions

Almost everything is flat-rate. The only metered/API-billed token is Moonshot.

| Plan | Price | Cap | Reset | Models | Primary use |
|---|---|---|---|---|---|
| **ChatGPT Plus** | ~$25 CAD/mo | GPT-5.5 Thinking 3,000 msg/wk; Codex 5h ranges + an unpublished weekly total | rolling (3h chat) + weekly (Codex) | gpt-5.5, gpt-5.4, gpt-5.4-mini (Codex line) | Frontier escalation; the weekly cap gets maxed every week |
| **MiniMax Plus** | ~$200 USD/yr ($20/mo, annual = 2mo free) | 300 prompts / 5h | rolling 5h | M3 and M2.7, via the Anthropic endpoint | Agentic reasoning workhorse |
| **Opencode Go** | $10 USD/mo | $12 / 5h, $30 / wk, $60 / mo (dollar-denominated) | rolling 5h / wk / mo | 14 models incl. DeepSeek V4 Flash/Pro, GLM-5.x, Kimi, MiMo, Qwen3.7, MiniMax | High-volume cheap lane (dsv4f) + grab-bag access |
| **GLM Coding Lite** | ~$151 USD/yr (promotional, region-dependent) | ~80 prompts / 5h | rolling 5h | GLM-5.2, GLM-5.1 (added 2026-06-17), GLM-4.7, GLM-4.5-Air | GLM coding access; fallback lane |
| **Moonshot (Kimi)** | pay-per-use | none (per-key RPM/TPM only) | n/a | kimi-k2.6 | Only metered token; deliberate paid fallback |

Caveats worth remembering:
- **MiniMax M3 is covered by the flat plan** (both M3 and M2.7), reached via the direct Anthropic
  endpoint. LiteLLM still logs ~$239/30d "phantom" spend against it — the plan is flat, the metric is
  not, so don't chase that number.
- **ChatGPT** was direct-through-Codex until recently; LiteLLM token history is light, but the
  weekly Codex cap is hit every week. OpenAI does not publish the exact weekly number.
- **GLM Lite's** annual USD price is promotional and not cleanly published.
- All 5h caps are **rolling windows** (oldest usage falls off continuously), not calendar resets.

## Model inventory

Aliases as defined in the LiteLLM configmap, grouped by where they run.

### Local (self-hosted, $0 marginal)

| Alias | Backend | Model | Ctx (in) | Role |
|---|---|---|---|---|
| `self-hosted` | Strix ROCm / Mac LM Studio | Qwen3.6-35B-A3B | 262k | Default local brain; vision + tools |
| `review` | ROCm / 3090 (llmkube) / Mac | GLM-4.7-Flash-REAP-23B / Gemma-4-26B | 204.8k | Second-opinion reviewer — don't let Qwen grade Qwen's homework |
| `nvidia` | 3090 | Qwen (CUDA) | 145k | General local, no vision |
| `ryzen` | Ryzen CPU (Vulkan) | Qwen3.5-9B-heretic | 8.2k | Tiny/edge tasks |
| `qwen3-embedding-0-6b` | llama.cpp | Qwen3-Embedding-0.6B | — | Embeddings (1024-dim) |

### Cloud (flat-rate subscriptions)

| Alias | Subscription | Upstream model | Ctx (in) | Role |
|---|---|---|---|---|
| `MiniMax` | MiniMax Plus | MiniMax-M3 (Anthropic endpoint) | 1M | Big-context generation |
| `MiniMax-M2.7` | MiniMax Plus | MiniMax-M2.7 | 204.8k | Agentic reasoning workhorse |
| `glm-5.1` | GLM Coding Lite | glm-5.1 (z.ai) | 203k | GLM coding |
| `glm-5.2` | GLM Coding Lite | glm-5.2 (z.ai) | 1M | GLM big-context lane |
| `chatgpt/gpt-5.5` | ChatGPT Plus | gpt-5.5 (Codex/OAuth) | — | Frontier |
| `chatgpt/gpt-5.4` | ChatGPT Plus | gpt-5.4 | — | Frontier (cheaper) |
| `chatgpt/gpt-5.4-mini` | ChatGPT Plus | gpt-5.4-mini | — | Cheap fallback |
| `kimi-k2.6` | Moonshot (metered) | kimi-k2.6 | 262k | Paid fallback (until balance runs out) |

### Cloud (Opencode Go gateway, `opencode.ai/zen/go/v1`)

| Alias | Upstream model | Ctx (in) | Role |
|---|---|---|---|
| `dsv4f` | deepseek-v4-flash | 1M | High-volume cheap lane; OpenClaw subagent/heartbeat |
| `dsv4p` | deepseek-v4-pro | 1M | Heavier DeepSeek |
| `go-glm-5.1` | glm-5.1 | 203k | GLM via gateway |
| `go-kimi-k2.6` | kimi-k2.6 | 262k | Kimi via gateway (flat, vs metered direct) |
| `go-minimax-m3` / `go-minimax-m2.7` | minimax-m3 / m2.7 | 1M / 204.8k | MiniMax via gateway |
| `mimo-v2.5` / `mimo-v2.5-pro` | mimo-v2.5(-pro) | 262k | Lighter analysis lane |
| `qwen3.7-plus` | qwen3.7-plus | 1M | Big-context Qwen via gateway |

## Model capability ranking

Benchmark snapshot as of **2026-06-17** — perishable. Numbers are mostly **vendor
self-reported on non-overlapping harnesses** (SWE-bench Pro ≠ Verified; Terminal-Bench
2.0 ≠ 2.1; GPT SWE-Pro drops ~15pts under standardized scaffolding), so treat deltas as
**directional**, not precise, and re-pull when models bump. `n/p` = not published.

| Model | Alias | Arch (total/active) | Ctx | SWE-V | SWE-Pro | LiveCodeB | Term-B | GPQA | AIME |
|---|---|---|---|---|---|---|---|---|---|
| GPT-5.5 | `chatgpt/gpt-5.5` | proprietary | 1M | 80.6 | 58.6¹ | n/p | 84.7 | 94.0 | n/p |
| DeepSeek-V4-Pro | `dsv4p` | MoE 1.6T/49A | 1M | 80.6 | 55.4 | 93.5 | 67.9 | 90.1 | n/p |
| GLM-5.2 | `glm-5.2` | MoE ~753B/40A | 1M | n/p | 62.1 | n/p | 81.0 | 91.2 | 99.2 |
| Kimi K2.6 | `go-kimi-k2.6` | MoE 1T/32A | 256k | 80.2 | 58.6 | 89.6 | 66.7 | 90.5 | 96.4 |
| MiniMax-M3 | `MiniMax` | MoE ~229B/9.8A² | 1M | 80.5¹ | 59.0 | n/p | 66.0 | 92.9 | n/p |
| GPT-5.4 | `chatgpt/gpt-5.4` | proprietary | ~922k | 76.9 | 59.1 | n/p | 81.8 | 94.6 | n/p |
| DeepSeek-V4-Flash | `dsv4f` | MoE 284B/13A | 1M | 79.0 | n/p | 91.6 | 56.9 | 88.1 | n/p |
| Qwen3.6-27B dense | `nvidia` | dense 27B | 145k³ | 77.2 | 53.5 | 83.9 | 59.3 | 87.8 | 94.1 |
| GLM-5.1 | `glm-5.1` | MoE 754B | 200k | n/p | 58.4 | n/p | 63.5 | 86.2 | 95.3 |
| MiMo-V2.5-Pro | `mimo-v2.5-pro` | MoE 1.02T/42A | 1M | 78.9⁴ | 57.2 | 39.6⁴ | n/p | 66.7⁴ | 37.3⁴ |
| MiniMax-M2.7 | `MiniMax-M2.7` | ~229B/n_p | n/p | n/p | 56.2 | n/p | 57.0 | n/p | n/p |
| MiMo-V2.5 | `mimo-v2.5` | MoE 310B/15A | 1M | n/p | 56.1 | n/p | 65.8 | n/p | n/p |
| Qwen3.6-35B-A3B | `self-hosted` | MoE 35B/3A | 262k | 73.4 | 49.5 | n/p | 51.5 | 86.0 | 92.7 |
| Qwen3.7-Plus | `qwen3.7-plus` | MoE undisclosed | 1M | n/p | ~60 | n/p | n/p | n/p | n/p |
| GPT-5.4-mini | `chatgpt/gpt-5.4-mini` | proprietary | 400k | n/p | 54.4 | n/p | n/p | n/p | n/p |
| Gemma-4-26B-A4B | `review` | MoE 25.2B/3.8A | 256k | n/p⁵ | n/p | 77.1 | n/p | 82.3 | 88.3 |

¹ GPT/MiniMax SWE-Pro are vendor-reported; GPT-5.5 drops to ~41.8 on Scale's standardized
public set (scaffolding gap). ² MiniMax-M3 param count is contested across sources (also
cited ~428B/23B); most non-coding numbers are vendor-run, independent verification pending.
³ Qwen3.6-27B is 262k native but pinned to 145k on the 24GB 3090. ⁴ MiMo-Pro reasoning /
LiveCodeBench from HF-card scrape only — low confidence; LiveCodeBench slice not comparable
to others. ⁵ Gemma-4 SWE-Verified unpublished; independent reports put it **below**
Qwen3.5-27B on real-world SWE and note it degrades under tool harnesses.

Reading it for routing:
- **Frontier tier** (`gpt-5.5`, `dsv4p`, `glm-5.2`, `kimi-k2.6`, `MiniMax-M3`) — top SWE +
  reasoning. `gpt-5.5` is the all-rounder ceiling (kept manual to protect the weekly cap);
  `glm-5.2` leads long-horizon agentic coding + math; `dsv4p` is the raw-coding workhorse.
- **Cheap/fast** (`dsv4f`, `gpt-5.4-mini`, `mimo-v2.5`) — near-frontier coding at low cost;
  `dsv4f` is the standout (SWE-V 79, LiveCodeBench 91.6, cheapest).
- **Local** — `nvidia` (Qwen3.6-27B dense) is the local quality + speed pick; `self-hosted`
  (35B-A3B) trails it everywhere and earns its place only on the 262k context window.
- **`review` / Gemma-4** — strong one-shot codegen + math, but weak at *agentic/repo* SWE and
  tool-use; GHA-only. Kept for creative tasks per observed use (no public creative-writing
  benchmark to confirm or deny).
- **MiniMax-M2.7 / MiMo / Qwen3.7-Plus** — agentic workhorses with thin published reasoning
  numbers; rank on coding/agentic axes, not GPQA/AIME.

## Consumers

| Consumer | In repo? | Points at |
|---|---|---|
| **OpenClaw** | yes (`.../llm/openclaw/app/configmap.yaml`) | default `MiniMax`; subagent + heartbeat `dsv4f`; image `self-hosted`; cron jobs vary (below) |
| **Hermes** | yes (`.../llm/hermes/configmap.yaml`) | default `MiniMax`; compression/extract/approval/session-search `self-hosted` |
| **Opencode** (CLI/Zen) | no (workstation) | LiteLLM aliases directly; biggest single `user_agent` cluster after the agents |
| **Zed** | no (workstation) | LiteLLM aliases directly |

### OpenClaw cron fleet

Two agents (Miso, Saffron) run 16 scheduled jobs, plus two issue-worker pipelines. The model choice
per job already encodes an intent-lane pattern by hand.

| Job | Agent | Model | Schedule | Purpose |
|---|---|---|---|---|
| Afternoon Email/Finance Check | Miso | MiniMax-M2.7 | 4pm daily | Email + financial anomaly scan |
| Instagram Hourly Image Dispatch | Miso | self-hosted | 9am–8pm Mon–Thu | Publish one approved staged IG post per window |
| Image Category Creation | Miso | MiniMax | every 6h | Generate new image category + gallery |
| Evening Email/Finance Check | Miso | MiniMax-M2.7 | 9pm daily | End-of-day email + finance summary |
| Nightly Audit Decomposer | Saffron | self-hosted | 2am daily | Decompose audit umbrellas into child issues |
| Nightly Tech Sweep | Saffron | mimo-v2.5 | 6:20am daily | Overnight health check + low-risk fixes |
| Unified Morning Brief | Miso | MiniMax-M2.7 | 7:30am daily | Weather, calendar, inbox, IG pool, news, radon |
| Daily LLM + HN Digest | Miso | self-hosted | 8:30am daily | r/LocalLLaMA etc. + HN top stories |
| Daily Home-Ops Updates | Saffron | MiniMax-M2.7 | 9am daily | Commit watch on homelab k8s repos |
| Daily Image (Miso) | Miso | self-hosted | 9:15am daily | Character image generation |
| Alertmanager Health Digest | Saffron | mimo-v2.5 | 9:30am daily | Firing Prometheus alerts + investigation |
| Solar Daily Check | Miso | MiniMax-M2.7 | 9:35am daily | Solar generation + weather + guess tracking |
| Daily Image (Saffron) | Saffron | self-hosted | 10:15am daily | Character image generation |
| Weekly IG Posting Times | Miso | mimo-v2.5 | 11am Fri | Research optimal IG posting times |
| Weekly Audit | Saffron | MiniMax-M2.7 | 1am Wed | Spawn per-repo audit sub-agents |
| Weekly Prompt Hygiene | Saffron | mimo-v2.5 | 10:45am Wed | Audit prompt files for bloat/contradictions |

Issue-worker pipelines (pick up issues and open PRs):

- **MC Normal** → `review`
- **MC Escalated** → `gpt-5.5`

## Current routing + observed usage

Routing today is `least-busy` with hand-written availability fallbacks
(configmap `router_settings`). There is **no** complexity/auto router yet.

```yaml
routing_strategy: least-busy
fallbacks:
  - review:      [dsv4f, self-hosted]
  - self-hosted: [dsv4f, nvidia]
  - dsv4f:       [glm-5.1, go-minimax-m3]
  - MiniMax:     [glm-5.2, go-minimax-m3]
```

Observed 30-day traffic (Prometheus, `litellm_*_metric_total`), top models:

| Model | Tokens (30d) | Requests (30d) |
|---|---:|---:|
| self-hosted | 1.07B | 27,250 |
| MiniMax-M2.7 | 946M | 14,483 |
| MiniMax-M3 | 834M | 9,812 |
| deepseek-v4-flash (`dsv4f`) | 811M | 9,049 |
| nvidia | 161M | 4,798 |
| review | 52M | 2,614 |
| glm-5.1 | 36M | 320 |
| gpt-5.5 | 31M | 432 |

`gpt-5.4-mini` (cheap) and `kimi-k2.6` (paid, until balance runs out) are kept as fallbacks despite
negligible traffic. Real logged spend is MiniMax-M3 ($239, phantom) and kimi ($0.86, actual).

## Smart-routing: the `auto` alias

An opt-in `auto` alias routes for **opencode + Zed only**; every other consumer (crons, MC
workers, Hermes roles, MiniMax) stays pinned. It's LiteLLM's rule-based **complexity router**
(no embedding call, <1ms). Coding tools are a difficulty / context / cost axis — not a "what
kind of task" axis — and `review`/Gemma is GHA-only, which removes the one intent split that
would justify semantic routing, so complexity scoring alone carries it.

Tiers (capability-ordered; SIMPLE offloads the single-slot 3090 onto the Strix):

| Tier | Target | Why |
|---|---|---|
| SIMPLE | `self-hosted` (Strix 35B-A3B, 2 slots) | Trivia — keep the 3090 free |
| MEDIUM | `nvidia` (Qwen3.6-27B dense) | Best + fastest local |
| COMPLEX | `dsv4p` (DeepSeek-V4-Pro) | Raw-coding workhorse, 1M ctx |
| REASONING | group `{glm-5.2, go-minimax-m3, go-kimi-k2.6}` | Top reasoners; least-busy across plans |
| default (unscored) | `nvidia` | Best local |

Boundaries `0.45 / 0.65 / 0.85`, raised above LiteLLM defaults: opencode/Zed system prompts are
code-dense and get scored alongside the user message, so complexity skews high. Tune from
`verbose_router_logger` (`tier= score= signals=`) once real traffic lands.

Mechanics that shaped this (verified against LiteLLM source):
- Both routers are pre-routing hooks returning a model *name*, resolved once — **no chaining**,
  so semantic can't sit "in front of" complexity. A model *group* as a tier target works (least-busy).
- `token_thresholds` is a complexity *signal*, not a context cap. The 145k/262k local ceilings are
  guarded by `context_window_fallbacks` (`nvidia`→`self-hosted`→`dsv4p`) + `enable_pre_call_checks`.
- `go-minimax-m3` is MiniMax-M3 on the OpenAI chat endpoint (flat via Opencode Go) — its reasoning
  leaks into the harness, unlike the Anthropic `/messages` `MiniMax` alias.

Excluded from `auto` by design: `MiniMax` (messages-shape), `review`/Gemma (GHA-only), `chatgpt/*`
frontier (manual — the weekly cap is already maxed). A **semantic router** (`auto-semantic` +
`router.json`) is scaffolded but commented out: `from_json` builds an encoder at startup
(crashloop risk on the live gateway), so it's verify-then-enable later, not now.

Still ahead:
- Tune `tier_boundaries` from observed routes; add a busy-fallback for `nvidia` if its single slot
  bottlenecks under opencode parallelism.
- Harness-level quality escalation in OpenClaw/Hermes — escalate to cloud/frontier on tool failure,
  uncertainty markers, failed tests/lint, or explicit "are you sure". Supervision, not routing.

References: LiteLLM [Auto Routing](https://docs.litellm.ai/docs/proxy/auto_routing) ·
[Fallbacks](https://docs.litellm.ai/docs/proxy/reliability).
