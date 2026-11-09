# LLM Strategy

This document describes the configured LLM fleet, subscriptions, and routing policy.
Clients use stable aliases through LiteLLM at `http://litellm.llm:4000`.
The source of truth is `kubernetes/apps/base/llm/litellm/`, including `models/` and `litellmproxy.yaml`.

Reconciled against repository configuration on 2026-11-03. Repository configuration describes intended state, not proof of deployment or available quota.
The local inventory, ordered pools, and consumer tables describe current configuration.
Capability rankings, repo-bench results, and dated traffic measurements remain historical evidence, not current model comparisons.
Subscription prices and allowances are recorded account observations, not a fresh verification of provider terms.

## Subscriptions

Subscriptions remain the primary capacity. They are not unlimited: fixed-price cloud plans still have
rolling or shared usage limits, and temporary provider throttles can affect them before a published
allowance is clear. In particular, MiniMax Plus is not an inexhaustible work queue: on 2026-10-12,
MiniMax M3/M2.7 requests returned HTTP 429 (code 2056, token-plan usage reached). Interactive Opencode,
Pi, Courier, and review traffic can draw on the same plan; leave headroom and avoid speculative fan-out.
Do not infer provider quota units from LiteLLM token counters or add cached input a second time. A
2026-10-12 LiteLLM view attributed 53.8% of labeled MiniMax tokens to Pi and 35.7% to Courier between
13:04 and 18:04; this is observed proxy traffic, not a complete consumer ledger or provider quota
accounting.

Neuralwatt supplies energy-metered PAYG as `dsv4.1f` rung 2 behind Charm Hyper, capped at $1/day.

| Plan                | Price                                        | Cap                                                          | Reset                              | Models                                                | Primary use                                                                                               |
| ------------------- | -------------------------------------------- | ------------------------------------------------------------ | ---------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| **ChatGPT Plus**    | ~$25 CAD/mo                                  | unpublished rolling + weekly quota, with tier-weighted usage | rolling (3h chat) + weekly (Codex) | GPT-6 Astra, Sol, Luna                                | Astra `frontier-pool` rung 2; Sol `reasoning-pool` rung 2; Luna `implementation-pool` lead                |
| **MiniMax Plus**    | ~$200 USD/yr ($20/mo, annual = 2mo free)     | legacy Token Plan; observed quota rejections despite grandfathered benefit            | rolling 5h                         | M3.1 Flash (primary), M3, M2.7 (retires 2026-11-18) — Anthropic endpoint | Agentic reasoning workhorse (`MiniMax-M3.1-Flash`); M2.7 auto-reroutes to M3.1 from 2026-10-19     |
| **GLM Coding Lite** | ~$151 USD/yr (promotional, region-dependent) | ~80 prompts / 5h                                             | rolling 5h                         | GLM-5.3 and GLM-5.3-Flash on the Z.AI coding endpoint | `frontier-pool` rung 3 (GLM-5.3); `glm-5.3-flash` rung 2, behind Hyper rung 1 (Flash)                             |
| **Kimi Coding**     | ~$180 USD/yr ($15/mo; ~$261 CAD/12mo)        | plan allowance                                               | plan-defined                       | Kimi K2.7 Code, Kimi K3                               | `frontier-pool` lead (K3); `reasoning-pool` lead (K2.7)                                                   |
| **Charm Hyper**     | $20 USD/mo                                   | $12.50 of usage per 24h                                      | every 24h                          | GLM-5.3-Flash, DeepSeek V4.1 Flash (`HYPER_API_KEY`)  | `glm-5.3-flash` order 1; Hyper-only `glm-5.3-flash-hyper` for the whole `hyper` lane; `grooming-pool` rung 3; `dsv4.1f` order 1; `implementation-pool` rung 2; `reasoning-pool` rung 3         |
| **Neuralwatt**      | pay-per-use ($5/kWh energy billing)          | account credit; LiteLLM `max_budget` $1/day on its rung      | n/a                                | DeepSeek V4.1 Flash                                   | `dsv4.1f` rung 2, behind Hyper                                                                            |

Retired 2026-08-25: **Opencode Go** ($10 USD/mo gateway; DeepSeek V4 Flash/Pro, MiMo v2.5/Pro,
Qwen3.8-Max) and **Moonshot** (pay-per-use Kimi fallback behind Kimi Coding).

Caveats worth remembering:

- **MiniMax M3.1 Flash and M3 use the flat plan**, via configured endpoints, but flat pricing is not unlimited
  availability. A 2026-10-12 HTTP 429 with code 2056 reported token-plan usage reached; LiteLLM spend
  is not the provider's quota meter, and prefix-cached input may still consume plan allocation. Do not
  assume capacity based on the price or treat every provider rejection as a transient error. The
  account keeps its grandfathered unlimited-limits Token Plan benefit; migrating to the new M Plan
  (Go/Explore/Build) would forfeit it, so the legacy plan is retained. Upstream doubles M3 list
  pricing past 512k input tokens — input, output, and cache read all double.
- **ChatGPT** was direct-through-Codex until recently; LiteLLM token history is light, but the
  weekly Codex cap is hit every week. OpenAI does not publish the exact weekly number. In the GPT-5.6
  generation (retired 2026-09-23) Luna consumed 80% fewer subscription credits and Terra 20% fewer;
  whether GPT-6 tiers carry the same weighting is not recorded here.
- **GLM Lite's** annual USD price is promotional and not cleanly published.
- Charm Hyper is recorded at $20 USD/month with $12.50 of usage per 24 hours. Current account terms remain authoritative.
- All 5h caps are **rolling windows** (oldest usage falls off continuously), not calendar resets.
- Kimi subscription traffic uses equivalent Moonshot list prices for cost comparison: K2.7 Code is
  $0.19 cached input / $0.95 cache miss / $4 output per MTok; K3 is $0.30 / $3 / $15.
- Historical (`dsv4f` retired 2026-09-26): the upstream DSV4F repricing reported in August 2026 changed
  the economics materially: roughly 8x higher uncached input and 40x higher cache-read pricing than the
  former baseline. Treat the provider account and current invoice as authoritative; LiteLLM model
  metadata can lag provider pricing.
- Cached input is cheaper billing-wise but still consumes upstream subscription/token allocation. A
  high K3 cache-hit ratio does not make a context-heavy diagnostic session quota-free.
- Opencode is LilDrunkenSmurf's ad-hoc interactive coding workload, so its pool usage is intentional
  rather than unattended fleet waste. Neuralwatt is an intentional PAYG fallback, not an accidental leak.

## Model inventory

Aliases are defined by `LiteLLMModel` CRs in `kubernetes/apps/base/llm/litellm/models/`, grouped here by
where they run. The bare `qwen3.8-flash-next` alias has no CR; it is auto-projected from its
InferenceService.

Each local generative model exposes two aliases against **one** server: the bare name runs the
vendor's thinking recipe, and the `-chat` suffix runs the non-thinking (instruct) one. They share
weights, KV cache and slots, so the second door costs no memory. Flash-Next is now the only local
model family: one alias group spreads across two machines (skirk and the 3090).

### Local (self-hosted)

Local inference has no per-token provider charge, but consumes electricity and shared hardware capacity.
A KV cache stores attention keys and values. A context limit covers input and generated output together.
MTP proposes several tokens before the main model verifies them.

| Alias | Backend | Model | Context | Role |
| --- | --- | --- | --- | --- |
| `qwen3.8-flash-next` | Strix Halo (Gufo, two sessions) + 3090 (Strata, three slots) | Qwen3.8-Flash-Next UD-Q4_K_XL (Strix) and GSQ-RCO IQ3_S (3090), shared Q8_0 MTP head, BF16 vision projector | 262144 engine context; LiteLLM group input 245760 | Local reasoning, coding, vision, tools, Courier coordinator |
| `qwen3.8-flash-next-chat` | Same deployments | Same weights, thinking disabled | Same | Non-thinking vision, heartbeat requests, `auto` classifier |
| `qwen3.8-flash-next-iq3_s` | 3090, Strata engine 0.1.52 | Same weights, GSQ-RCO IQ3_S, MTP | 245760 LiteLLM input; 256K engine context | Internal rung inside the `qwen3.8-flash-next` group; three slots, capped `max_parallel_requests: 3` |
| `embed` | CPU, three replicas | Qwen3-Embedding-0.6B Q8_0 | 32768 | 1024-dimension embeddings for memini and toolhive |
| `rerank` | CPU, three replicas | bge-reranker-v2-m3 Q8_0 | Not declared | memini reranking |

The 3090 hosts one always-resident service, `strata-fn` (Strata engine, IQ3_S at 256K context).
The former `nvidia` ModelPool and ModelRouter — 27B/muse swapping through `nvidia-router-proxy` —
were retired when Flash-Next took over all local traffic on 2026-11-08; no swapping happens any more.
See [Shared local inference](coding-loop.md#shared-local-inference) for operations.

The retired 27B server ran MTP, eight active sequences, prefix caching, and `GPU_UTIL=0.985`; the manifest lives in git history for rollback.
Startup logs read on 2026-11-03 confirm `int8_per_token_head` KV and three speculative tokens.
On 2026-10-31, the measured shared cache pool held 208,216 tokens in 7.6 GiB, up from 172,649.
The pool is not the per-request limit or eight separate context allocations. Fixed per-sequence state also consumes cache capacity.
The 0.99 trial failed its startup free-memory requirement. The 0.985 deployment started, but sustained load stability remains a separate observation.
Keep the request cap at 147456. If memory failures appear under load, the agreed fallback is 0.98.
The TurboQuant trial remains closed because MTP produced repetition loops. Do not retry without evidence that upstream fixes the quality failure.

Flash-Next uses two Gufo sessions and a 64 GiB disk continuation cache.
Gufo 0.28.1 fixes prefill differences across pass sizes, including short tails after cache restores.
Its published MTP gains use greedy decoding, not our sampled temperature 1.0 configuration. Upstream also measured slower short replies in some cases.
No matched local sampled before/after result is recorded here.
Both local services use idle-aware rollouts (`waitForIdle: true`, `idleTimeoutSeconds: 86400`). Do not restart or wake models to inspect capacity.

Vision requests use Flash-Next. The proxy fallback for `qwen3.8-flash-next-chat` tries MiniMax-M3.1-Flash. Strata's vision path is served but not yet exercised; that rung keeps `supportsVision: false` until one real image request passes.
The gaming PC with a 9070 XT is not configured inference capacity. Radiance and a dual-boot Talos worker remain experiments.
The `dsv4f-local` alias remains registered, but has no configured InferenceService and cannot serve through that missing backend.
Commented manifests in `litellm/kustomization.yaml` are references, not active capacity.

### Cloud (flat-rate subscriptions)

MiniMax pricing source (checked 2026-10-19):
[official pricing](https://platform.minimax.io/docs/pricing/overview).
M3.1 Flash is $0.15/$0.60/$0.015 per million input/output/cache-read tokens,
flat across the listed context range. New tokens use the standard input rate;
there is no separate Flash cache-write surcharge listed. M3 Standard remains
$0.30/$1.20/$0.06 at <=512k input, and $0.60/$2.40/$0.12 above 512k.
M3 Priority is 1.5x Standard; no priority tier is configured here.
These are recorded list-price accounting values, not a promise of subscription quota equivalence. Current provider terms were not rechecked in this pass.
The repository Actions variable `FALLBACK_MODEL` is `MiniMax-M3.1-Flash` (read 2026-11-03).



| Alias                 | Subscription                      | Upstream model                              | Ctx (in) | Role                                                                                          |
| --------------------- | --------------------------------- | ------------------------------------------- | -------- | --------------------------------------------------------------------------------------------- |
| `MiniMax-M3.1-Flash` | MiniMax Plus               | MiniMax-M3.1-Flash (Anthropic endpoint) | 1M   | OpenClaw default + Matcha primary; `auto` MEDIUM and miss default; Hermes/opencode `reviewer` + `explorer`. Thinking always on; `reasoning_effort` low/medium/high/xhigh/max (default max). Published list pricing: $0.15/M input, $0.60/M output, $0.015/M cache reads; no long-context tier listed |
| `MiniMax-M3`          | MiniMax Plus                      | MiniMax-M3 (Anthropic endpoint)             | 1M       | Retained standalone for rollback and manual use; no pool rungs                                 |
| `MiniMax-M2.7` | Legacy client entry | No active LiteLLMModel CR | 204800 declared by client | Not a configured proxy backend. Old cron entries require separate verification |
| `glm-5.3`             | GLM Coding Lite                   | glm-5.3 (Z.AI)                              | 1M       | Hermes fallback; manual. `frontier-pool` rung 3 is a separate deployment of the same model    |
| `glm-5.3-flash`       | Charm Hyper, then GLM Coding Lite | glm-5.3-flash (order 1 Hyper, order 2 Z.AI) | 1M       | OpenClaw Miso/main primary; `oracle` role; Courier `frontier` coordinator                                                     |
| `chatgpt/gpt-6-astra` | ChatGPT Plus                      | gpt-6-astra (Codex/OAuth)                   | 272k*    | Direct alias; `frontier-pool` rung 2                                                          |
| `chatgpt/gpt-6.1-sol` | ChatGPT Plus                      | gpt-6.1-sol (Codex/OAuth)                   | 272k     | Direct alias; `reasoning-pool` rung 2                                                         |
| `chatgpt/gpt-6-luna`  | ChatGPT Plus                      | gpt-6-luna (Codex/OAuth)                    | 272k     | Direct alias defaults to `max`; implementation lead defaults to `high`                                |
| `kimi-k2.7`           | Kimi Coding                       | kimi-for-coding                             | 262k     | Coding subscription; `reasoning-pool` rung 1 is a separate deployment                         |
| `kimi-k3`             | Kimi Coding                       | k3                                          | 1M       | Frontier Kimi lane; `frontier-pool` rung 1 is a separate deployment                           |

\* `gpt-6-astra`'s real window is 1.05M, but a prompt past 272k reprices the *entire* request at
2x input/cache and 1.5x output, so it is declared at the cheap ceiling. Raise it deliberately if a
long-context call is ever worth the multiplier.

**Moonshot is gone** (2026-08-25). Its credits were deliberately drained rather than topped up, so
`kimi-k2.7` and `kimi-k3` are single-rung on the Kimi Coding subscription with no PAYG rung beneath and
no router fallback in `litellmproxy.yaml`. Kimi Coding signals cap-out with a 403, which LiteLLM retries
but never cools down. Inside `frontier-pool` and `reasoning-pool` the order-based fallback moves past
it (see **Frontier pool**); a direct `kimi-*` call fails.

### DeepSeek V4.1 Flash (Charm Hyper, Neuralwatt PAYG)

| Alias     | Order | Provider    | Ctx | Budget                                   |
| --------- | ----- | ----------- | --- | ---------------------------------------- |
| `dsv4.1f` | 1     | Charm Hyper | 1M  | —                                        |
| `dsv4.1f` | 2     | Neuralwatt  | 1M  | `max_budget: 1.0`, `budget_duration: 1d` |

`dsv4.1f` replaced `dsv4f` on 2026-09-26 (#10533); the Neuralwatt rung was capped at $1/day on
2026-09-27 (#10557). Consumers: OpenClaw and Hermes fallback chains, and the `auto` router fallback.
Neither DeepSeek provider is in `reasoning-pool`. Neuralwatt is not in an ordered pool.

Neuralwatt charges for measured GPU energy rather than tokens. PAYG is $5/kWh; prefix-cache hits
avoid prefill work and therefore reduce the charged energy. Use Neuralwatt's usage API/dashboard for
authoritative cost; LiteLLM and Prometheus are routing/volume telemetry, not the billing authority.

Historical (2026-08-25): the Neuralwatt balance was ~$9.52 against a trailing burn of ~$3.17/day, which
is why it was demoted behind Hyper and capped. `glm-5.2` and `neuralwatt/glm-5.2` were removed on
2026-08-25 — neither had a single consumer.

### Cloud (Opencode Go gateway) — retired

Retired 2026-08-25 when the plan capped out, ahead of its 08-28 lapse. It had supplied `dsv4f`
(Go rung), `dsv4p`, `mimo-v2.5`, `mimo-v2.5-pro`, `qwen3.8-max`, `go-gpt-5.6-luna` and a
`reasoning-pool` rung. `dsv4f` survived on Neuralwatt until 2026-09-26, when `dsv4.1f` replaced it; the
rest were deleted along with the `OPENCODE_API_KEY` wiring.

### Ordered pools

Pool definitions live in `models/`. Each rung declares its own context and output metadata.
Clients also declare limits, so a standalone model window does not establish a pool-wide window.
Leave output room inside the backend total context, even when metadata lists separate input and output maxima.

| Pool | Ordered members | Effort defaults | Policy |
| --- | --- | --- | --- |
| `frontier-pool` | Kimi K3 -> GPT-6 Astra -> GLM-5.3 (Z.AI) | No effort pin | Frontier escalation; three rungs, no DeepSeek floor |
| `reasoning-pool` | Kimi K2.7 -> GPT-6.1 Sol -> GLM Flash (Hyper) -> GLM Flash (Z.AI) -> Flash-Next | K2.7 drops `reasoning_effort` | Planning and hard debugging, then local fallback |
| `implementation-pool` | GPT-6 Luna -> GLM Flash (Hyper) -> Strata (Flash-Next IQ3_S) | Luna `high`; Strata `xhigh` | Implementation after the approach is settled |
| `local-pool` | Flash-Next (skirk) | Thinking recipe | Local-only provider selection, shared hardware |
| `local-pool-chat` | Flash-Next (skirk) | Flash-Next `reasoning_effort: none` | Non-thinking local requests and AI PR review |
| `grooming-pool` | Flash-Next -> GLM Flash (Hyper) -> GPT-6 Luna -> GLM Flash (Z.AI) | No effort pin | Dispatch issue grooming |
| `free-pool` | Eight OpenRouter deployments, listed below | No effort pin | Optional work on public material only |

Opencode declares `implementation-pool` at 147456 tokens, `frontier-pool` at 272000, and `reasoning-pool` at 262144.
Reasoning rungs declare input limits of 262144 (K2.7), 272000 (Sol), 262144 (both GLM Flash deployments), and 245760 (Flash-Next).
The 1M standalone GLM alias does not give the reasoning pool a 1M window.
Implementation's Strata rung declares 245760 input and 40960 output, which exceed the engine's 262144 total when combined. This remains a configuration discrepancy.

The direct `glm-5.3-flash` alias tries Hyper before Z.AI. The implementation pool has a Hyper-only GLM rung.
The reasoning pool has separate Hyper and Z.AI rungs. Neither pool includes MiniMax or DeepSeek.
The direct Luna alias defaults to `max`, while its implementation rung defaults to `high`.
Both use nested `extra_body.reasoning.effort`. These are defaults, not enforced overrides of client requests.

Kimi leads frontier and reasoning. ChatGPT is rung 2 in those pools and rung 1 in implementation.
These shared subscriptions do not create independent quota for each pool. Provider failover responds to request failures, not an unpublished allowance almost exhausted.
Direct Kimi aliases have no PAYG fallback. The ordered pools provide alternatives when a Kimi request fails.

`free-pool` tries Nemotron 3.5 Super VL, Nemotron 3.5 Lightning, Nemotron 3 Ultra, Gemma 4 31B,
Nemotron 3 Super, Cohere North Mini Code, Dots 3 Note Preview, then `openrouter/free`.
Opencode declares a 200000-token context. Availability is not reserved capacity, and providers can log prompts.
Use only public-repository material. Never send private code, credentials, or secrets.
Courier exposes this as an optional `free` role, not a replacement for final verification.

## Model capability ranking

> Historical benchmark snapshot, primarily 2026-08-23. Alias names changed afterward. Scores do not describe the current local engines or cloud pool selection. No benchmarks were rerun for this pass.

Benchmark snapshot as of **2026-08-23** — perishable. Numbers remain largely **vendor
self-reported on non-overlapping harnesses** (SWE-bench Pro ≠ Verified; Terminal-Bench
2.0 ≠ 2.1 ≠ 3.0; vendor SWE-Pro runs 15–30pts above standardized scaffolding), so treat deltas as
**directional**, not precise, and re-pull when models bump. `n/p` = not published. Do not read this
table as a statement about pricing, cache behaviour, or quota consumption.

Rows for `dsv4p`, `glm-5.2`, `mimo-v2.5` and `mimo-v2.5-pro` are kept for reference only — those
aliases were retired on 2026-08-25 and are no longer served. The Mellum2 row is likewise
historical: in that snapshot the then-reviewer alias served Nemotron 3.5 Lightning
30B-A3B. The later 9070XT reviewer and its wake endpoint are now permanently retired.

Rows are ordered by **AA-II**, the [Artificial Analysis Intelligence Index](https://artificialanalysis.ai/leaderboards/models)
(v4.1.1) — the only axis in this table measured on one harness across every model here, and therefore
the only column where a cross-row comparison is defensible on its own. Every other column mixes
harnesses. Cells marked ⁱ are **independently run**; everything else is vendor-reported.

| Model             | Alias                   | Arch (total/active) | Ctx   | AA-II | SWE-V | SWE-Pro | LiveCodeB | Term-B 2.1 | GPQA  | AIME  |
| ----------------- | ----------------------- | ------------------- | ----- | ----- | ----- | ------- | --------- | ---------- | ----- | ----- |
| GPT-5.6 Sol       | `chatgpt/gpt-5.6-sol`   | proprietary         | 1.05M | 61ⁱ   | 96.2ⁱ | 64.6    | n/p       | 89.5ⁱ ²    | 94.1ⁱ | n/p   |
| GLM-5.3           | `glm-5.3`               | MoE ~753B/40A ³     | 1M    | 60ⁱ   | n/p   | n/p ³   | n/p       | 88.2 ⁴     | n/p   | n/p   |
| Qwen3.8-Max       | `qwen3.8-max`           | MoE 2.4T/95A        | 1M    | 58ⁱ   | n/p   | 67.7    | n/p       | 86.6 ⁵     | 92.6  | n/p   |
| Kimi K3           | `kimi-k3`               | MoE 2.8T/104A ⁶     | 1M    | 57ⁱ   | 93.4ⁱ | n/p     | 87.2ⁱ     | 80.9ⁱ ⁶    | 93.5  | n/p   |
| GPT-5.6 Terra     | `chatgpt/gpt-5.6-terra` | proprietary         | 1.05M | 55ⁱ   | n/p   | 63.4    | n/p       | 73.4ⁱ ²    | n/p ² | n/p   |
| DeepSeek-V4-Pro   | `dsv4p`                 | MoE 1.6T/49A        | 1M    | 53ⁱ   | 96.4ⁱ | n/p ⁷   | n/p ⁷     | 87.9       | n/p ⁷ | n/p   |
| GLM-5.2           | `glm-5.2`               | MoE ~753B/40A       | 1M    | 53ⁱ   | n/p   | 62.1    | n/p       | 78ⁱ ⁴      | 89ⁱ   | 99.2  |
| DeepSeek-V4-Flash | `dsv4f`                 | MoE 284B/13A        | 1M    | 52ⁱ   | n/p ⁷ | n/p ⁷   | n/p ⁷     | 79ⁱ ⁷      | 91ⁱ   | n/p   |
| Qwen3.8-27B dense | `qwen3.8-27b`           | dense 27.8B         | 145k⁸ | 52ⁱ   | n/p ⁸ | 61.7    | 90.3      | 73.0       | 89.2  | n/p   |
| GPT-5.6 Luna      | `chatgpt/gpt-5.6-luna`  | proprietary         | 1.05M | 51ⁱ   | n/p   | 62.7    | n/p       | 84.7       | n/p ² | n/p   |
| MiniMax-M3        | `MiniMax-M3`            | MoE ~428B/23A ¹     | 1M    | 45ⁱ   | 80.5  | 59.0    | n/p       | 66.0       | 93ⁱ   | n/p   |
| MiMo-V2.5-Pro     | `mimo-v2.5-pro`         | MoE 1.02T/42A       | 1M    | 43ⁱ   | 78.9  | 57.2    | n/p ⁹     | n/p ⁹      | n/p ⁹ | n/p ⁹ |
| MiniMax-M2.7      | `MiniMax-M2.7`          | MoE ~230B/10A       | 205k  | 39ⁱ   | n/p   | 56.2    | n/p       | n/p ⁹      | 89.8  | 94.2  |
| MiMo-V2.5         | `mimo-v2.5`             | MoE 310B/15A        | 1M    | 38ⁱ   | n/p   | 56.1    | n/p       | n/p ⁹      | n/p   | n/p   |
| Qwen3.6-35B-A3B   | `qwen3.8-flash-next`    | MoE 35B/3A          | 262k  | 32ⁱ   | 73.4  | 49.5    | 80.4      | n/p ⁹      | 86.0  | 92.7  |
| Mellum2-12B-A2.5B | — (retired)             | MoE 12B/2.5A        | 131k  | n/p   | n/p   | n/p     | 37.2      | n/p        | 40.9  | 41.7  |

¹ MiniMax-M3 is **~428B total / ~23B active** — the ~229B/9.8B figure the previous snapshot carried is
M2.7's spec, misattributed. The [official config](https://huggingface.co/MiniMaxAI/MiniMax-M3/raw/main/config.json)
gives 60 layers, 128 experts (4 routed + 1 shared per token), which arithmetically yields ~428B/~23B;
every source citing "229.9B across 256 experts" is reciting M2.7. GPQA is
[Artificial Analysis](https://artificialanalysis.ai/models/minimax-m3)-run; the coding rows remain
vendor-run on MiniMax's own sandbox against leaderboard-sourced competitor numbers — a mixed-harness
comparison. [Vals AI](https://www.vals.ai/models/minimax_MiniMax-M3) has M3 ranked on SWE-bench,
LiveCodeBench and Terminal-Bench 2.1 but does not expose the values. The HF card's
"Long-Horizon Terminal Bench 38.5" is **not** Terminal-Bench 2.x and must not be compared to the 66.0.

² OpenAI published **no** SWE-bench Verified, GPQA, AIME, or LiveCodeBench for any 5.6 tier — it led
with agentic evals. Sol's SWE-V 96.2 and Terra's Term-B 73.4 are
[Vals AI](https://www.vals.ai/models/openai_gpt-5.6-sol) runs, not OpenAI's. Terminal-Bench 2.1 for Sol
has three values on the same benchmark version — vendor 88.8,
[AA](https://artificialanalysis.ai/evaluations/terminalbench-v2-1) 89.5, Vals 85.8 — so the harness,
not the model, moves it several points. The GPQA triple 94.6/92.9/92.3 the previous snapshot carried
appears only in aggregator blogs with no primary source; AA independently measures Sol at 94.1, and
Terra/Luna are unmeasured. The ~15pt SWE-Pro scaffolding penalty is confirmed and
[wider than thought](https://www.morphllm.com/swe-bench-pro) — 15 to 30pts — and no 5.6 tier has ever
been run on standardized SWE-Pro scaffolding at all.

³ [GLM-5.3](https://z.ai/blog/glm-5.3) (2026-08-14) is a **post-training-only** refresh of GLM-5.2 —
same base model, same 753B/40A architecture, no retrain. Weights are still not public as of this
snapshot (the blog promised them "in two weeks"), so there is no HuggingFace card and every GLM-5.3
number is vendor-sourced from that blog. Z.ai has **never** published SWE-bench Verified for any GLM,
and dropped SWE-bench Pro from the 5.3 table after reporting 62.1 for 5.2 — so a "SWE-bench 62.1"
citation is Pro, not Verified. The headline "+50% coding" rests entirely on **Z.ai Code Bench, a private
in-house benchmark**, unreproducible by anyone.

⁴ Discount GLM's Terminal-Bench claims. The [official tbench.ai board](https://www.tbench.ai/leaderboard/terminal-bench/2.1)
has no GLM-5.2 or 5.3 submission at all; the one GLM datapoint it does hold, GLM-5.1, scores **58.7
against Z.ai's self-reported 69.0 on the same bench and harness** — a ~10pt vendor gap. AA
independently puts GLM-5.2 at 78 (vendor 81.0). GLM-5.3's 88.2 has no independent run. Separately,
the widely-quoted "4.6 → 28.3" jump is **Terminal-Bench 3.0**, a different benchmark; never line it up
against 2.0 or 2.1. Z.ai also silently re-ran several GLM-5.2 baselines between the two blogs
(SWE-Marathon 13.0 → 19.4, FrontierSWE 74.4 → 67.5).

⁵ Qwen3.8-Max's agentic claim is the weakest in the table.
[Vals AI measures Terminal-Bench at 67.4 against the vendor's 86.6](https://www.yottalabs.ai/post/qwen-3-8-benchmarks-what-is-verified-2026) —
a 19pt collapse, versus roughly 3pts for GPT. Most of its vendor coding rows were run under
*Anthropic's* Claude Code harness rather than a neutral one, and its FrontierSWE / DeepSWE 1.1 figures
are non-standard names with no public leaderboard. Architecture is disclosed, not undisclosed:
2.4T/95A MoE. Note the row it replaces: `qwen3.7-plus` still exists as a separate, cheaper tier and was
not superseded — swapping the gateway alias to `qwen3.8-max` was a tier jump at 5× the input price,
not a like-for-like upgrade.

⁶ K3 corrections. Active params are **104B**, not the ~50B previously recorded (896 experts, 16 routed
+ 2 shared, 93 layers) per the [HF card](https://huggingface.co/moonshotai/Kimi-K3). More importantly,
**the previous footnote's claim that these were renamed benches was wrong**:
[ProgramBench](https://www.vals.ai/benchmarks/programbench) is a genuine third-party benchmark
(arXiv 2605.03546, program reconstruction — not issue resolution), so it was never a SWE-bench rename
and the old table's "SWE-V ≈ ProgramBench 77.8" mapping was invalid. Independent runs now exist and
they cut both ways: Vals gives K3 **SWE-bench Verified 93.4** (rank #3, a number Moonshot never
published) but scores ProgramBench at **62.8 against the vendor's 77.8** and Terminal-Bench 2.1 at
**80.9 against the vendor's 88.3**. Vals notes K3 "forfeits 22 tasks to zero, mostly submissions that
fail to build" — harness sensitivity, not noise. The genuinely self-named bench to distrust is **Kimi
Code Bench 2.0 (72.9)**. AA corroborates rank ~#3 at index 57 but flags hallucination **51%**, up from
39%. Still absent from the official swebench.com and Scale SEAL boards.

⁷ DeepSeek shipped **V4-Flash-0731** (2026-07-31) and **V4-Pro-0813** (2026-08-13); there is no "0713".
Both GA cards **replaced the benchmark suite wholesale**, dropping SWE-bench Verified, SWE-bench Pro,
LiveCodeBench, GPQA and MMLU-Pro entirely — so the familiar Flash figures (SWE-V 79.0, SWE-Pro 52.6,
LiveCodeBench 91.6, GPQA 88.1) and Pro figures (80.6 / 55.4 / 93.5 / 90.1) are **preview-build numbers
that no longer describe the deployed model**, and are marked `n/p` here rather than carried forward.
Architecture is unchanged across the refresh; the 304B/1.7T figures on the GA HF repos include an
attached speculative-decoding draft module and are not model size. The refresh was large where it is
measured — Flash Terminal-Bench 2.1 61.8 → 82.7, DeepSWE 7.3 → 54.4 — and AA independently confirms
the direction, lifting Flash from index 40 to 52. Note also that Flash's old 56.9 was Terminal-Bench
**2.0**; the 2.1 retro-score for the same build is 61.8.

⁸ `qwen3.8-27b` has run **Qwen3.8-27B** since 2026-08-14, not the Qwen3.6-27B the previous snapshot listed —
that row was wrong on the model name irrespective of benchmarks. Qwen publishes no SWE-bench Verified
for it (the nearest vendor substitute, QwenSWEBench 79.0, is Qwen's own harness) and no AIME, so the
generational SWE-V and AIME comparisons against Qwen3.6-27B cannot be made. Terminal-Bench also
switched versions between generations: 3.6-27B's 59.3 was 2.0, 3.8-27B's 73.0 is 2.1, so the +13.7
arithmetic is cross-version and wrong — the vendor states the real delta as **+9.6 on 2.1**. Native
context is 262k. The 24 GB 3090 limits requests to 147456 tokens.
The alias previously served Swift 1.5 and now serves base Qwen AutoRound. Vendor scores do not measure this quantized serving configuration.

⁸a **KV-history correction (2026-10-20).** From 2026-09-15 (`505ac596b`) to 2026-10-18 (`eedbe8a96`) the
27B ran `CTX=huge` (KVarN k4v2, 4.9 GiB GPU pool ≈ 314k tokens) **plus a 16 GiB host CPU KV offload tier**
(`--kv-offloading-size 16`). The large room figures quoted from that era were therefore not fully on-card,
and its ~32 tok/s decode was suppressed by offload I/O over the Oculink x4 link — KVarN-native decode was
never measured clean. Treat every cross-era room/speed comparison that touches those dates as confounded.
Historical baseline (2026-10-20, `31b5d20f0`): fp8 KV + MTP, ~174k pool (~1.18 full-depth 147k slots), ~64 tok/s
request-derived p50. The 2026-10-20 TurboQuant trial (`turboquant_4bit_nc`, 253k pool) is **closed**: TQ+MTP
corrupts output (repetition loops; matches syv-ai/HyperQwen#323, GSM8K 191→0) and TQ without MTP decodes at
~21.5 tok/s solo — 3× down on fp8+MTP. Revisit only if upstream fixes the TQ×MTP interaction.

⁹ Terminal-Bench 2.0-only rows, shown as `n/p` in the 2.1 column to keep it comparable: MiniMax-M2.7
**57.0**, MiMo-V2.5 **65.8**, MiMo-V2.5-Pro **68.4**, Qwen3.6-35B-A3B **51.5**. Separately, the
MiMo-Pro LiveCodeBench 39.6 / GPQA 66.7 / AIME 37.3 the previous snapshot carried are
**base-model few-shot pretraining evals** (1-shot LCB v6, 5-shot GPQA, 2-shot AIME 24&25) that an
automated HF metadata PR flattened into the card alongside post-trained numbers. They are not
comparable to any other row here and have been removed rather than corrected — Xiaomi publishes no
post-trained equivalents.

`qwen3.8-flash-next` now runs Qwen3.8-Flash-Next (180B-e51B-A6B) with its mmproj loaded — swapped in
on 2026-09-08 (then UD-IQ4_XS on Vulkan llama.cpp), replacing the Qwen3.6-35B-A3B this section's scores
were measured against (which had itself replaced the HauhauCS and Ornith-1.0-35B post-tunes of the same
Qwen3.6 in the 2026-08-25 unsloth move). Since 2026-09-24 (#10479) the skirk deployment runs on gufo (ROCm) at
UD-Q4_K_XL with the MTP head; since 2026-11-08 a second deployment (Strata engine,
IQ3_S) serves the same group from the 3090. Image analysis goes through `qwen3.8-flash-next-chat` (skirk), with MiniMax-M3.1-Flash
as proxy fallback, rather than a dedicated `llama-vision`, which was removed.

Mellum2 (historical reviewer lane, now retired) publishes more than the previous snapshot credited it with — the
[Mellum2 Instruct card](https://huggingface.co/JetBrains/Mellum2-12B-A2.5B-Instruct) carries
LiveCodeBench v6 37.2, EvalPlus 78.4, MultiPL-E 67.1, GPQA 40.9 and AIME 41.7, all self-reported. What
it genuinely does not publish is any *agentic* coding bench: no SWE-bench of any slice, no
Terminal-Bench. Its headline remains **BFCL v3 66.3** (tool use), which is the axis that actually
matters for a reviewer: the verdict is a structured `submit_result` call whose `issueAsk` must be a
verbatim substring of the issue body, and a malformed payload is rejected by the harness regardless of
how good the judgement was. Newer numbers exist that the row does not use — BFCL v4 44.2, and a
**Thinking** variant at BFCL v3 69.4 / LiveCodeBench v6 69.9, nearly double the Instruct build. Rank it
on independence and format reliability, not on a coding leaderboard.

Current interpretation:

The historical Qwen3.6-35B-A3B scores do not describe the current Flash-Next model.
Do not use the 52-versus-32 AA-II comparison to rank 27B against Flash-Next.
The current division of work follows hardware, context requirements, vision support, and operational experience, not that obsolete comparison.
27B provides local coding. Flash-Next provides the larger-context and vision lane.
No current fleet-wide ranking is established by this documentation pass.

The former 9070 XT reviewer and its wake endpoint remain retired.
Current review roles use MiniMax-M3.1-Flash or the local Flash-Next lane as configured by the consumer.
The benchmark tables retain their dates and model identities.

Sources: [Artificial Analysis](https://artificialanalysis.ai/leaderboards/models) ·
[AA Terminal-Bench v2.1](https://artificialanalysis.ai/evaluations/terminalbench-v2-1) ·
[Vals AI SWE-bench Verified](https://www.vals.ai/benchmarks/swebench) ·
[Vals ProgramBench](https://www.vals.ai/benchmarks/programbench) ·
[tbench.ai Terminal-Bench 2.1](https://www.tbench.ai/leaderboard/terminal-bench/2.1) ·
[GLM-5.3](https://z.ai/blog/glm-5.3) · [GLM-5.2](https://huggingface.co/zai-org/GLM-5.2) ·
[Kimi K3](https://huggingface.co/moonshotai/Kimi-K3) ·
[MiniMax-M3](https://huggingface.co/MiniMaxAI/MiniMax-M3) ·
[DeepSeek-V4-Flash-0731](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731) ·
[DeepSeek-V4-Pro-0813](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro-0813) ·
[Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B) ·
[Qwen3.6-35B-A3B](https://huggingface.co/Qwen/Qwen3.6-35B-A3B) ·
[MiMo-V2.5-Pro](https://huggingface.co/XiaomiMiMo/MiMo-V2.5-Pro) ·
[Mellum2-12B-A2.5B](https://huggingface.co/JetBrains/Mellum2-12B-A2.5B-Instruct) ·
[GPT-5.6 models](https://developers.openai.com/api/docs/models/gpt-5.6-sol).

## Historical repo-bench results

These results describe the listed checkpoints and test configurations, not current aliases.
The old blanket pre-September date conflicts with rows naming Flash-Next. Exact run dates need the original receipts.
Do not use this table to rank the currently deployed Gufo and HyperQwen configurations.

Four suites from `repo-bench` v2, scored on this repo's own material. Error rows (transport
failures) are dropped rather than counted as zeros — the `tally` subcommand does this.

| Candidate                                             | Troubleshooting | Reviewing | Agentic | Coding | Mean  |
| ----------------------------------------------------- | --------------- | --------- | ------- | ------ | ----- |
| `qwen3.8-27b` 27B Q4 (3090)                           | 0.981           | 0.923     | 0.718   | 0.710  | 0.833 |
| Qwen3.8-27B FP8 (Strix)                               | 0.938           | 0.920     | 0.782   | 0.760  | 0.850 |
| Flash-Next UD-Q3_K_XL (Strix)                         | 0.978*          | 0.792     | 0.833   | 0.760  | 0.841 |
| Flash-Next NVFP4 + FP8 engram (borrowed RTX 6000 Pro) | 0.991           | 0.838     | 0.788   | 0.620  | 0.809 |
| Nemotron 3.5 30B-A3B (Strix)                          | 0.910           | 0.817     | 0.756   | 0.080  | 0.641 |
| `MiniMax-M3`                                          | 0.956           | 0.759     | 0.558   | 0.590  | 0.716 |
| `MiniMax-M2.7`                                        | 0.956           | 0.842     | 0.481   | 0.500  | 0.695 |
| `chatgpt/gpt-5.6-luna` (effort=medium)                | 0.926           | 0.758     | 0.744   | 0.620  | 0.762 |

\* n=15; three tasks died on the qwen4exp indexer assert and were dropped.

**Run-to-run noise is ±0.02**, measured from the duplicate `nvidia`/`qwen3.8-27b` pair (same model,
different dates: deltas 0.016 / 0.003 / 0.019 / 0.020). So the top three rows are a tie, and a 180B
at Q3 does not beat a 27B on this bench.

Reviewing is Flash-Next's worst suite and both 27Bs' best; agentic is the reverse. Nemotron's coding
score is broken, which is fine for a review-only lane and disqualifying for a coder.

Caveat on luna: it ran GPT-5.6 Luna at `effort=medium`. The deployed path is now GPT-6 Luna through
`implementation-pool` (and the direct alias), with `high` on the pool and `max` on the direct alias. That row is not evidence
about the deployed path.

Methodology trap: candidate names are not stable across time. `qwen3.8-flash-next` meant Ornith in August
and Flash-Next later, and `tally` merges by candidate name — check what the alias pointed at before
comparing rows.

## Hardware placement and historical measurements

Strix Halo has ~256 GB/s theoretical and ~200-220 GB/s real. Decode is bandwidth-bound, so what
matters is **active** parameters per token, not total parameters:

| Model                         | Arch           | Weights   | Read/token      | Measured TG |
| ----------------------------- | -------------- | --------- | --------------- | ----------- |
| Qwen3.6-35B-A3B Q4            | MoE, 3B active | 21.3 GiB  | ~1.7 GiB        | 34-42 t/s   |
| Nemotron 3.5 30B-A3B Q4       | MoE, 3B active | 23.8 GiB  | ~1.7 GiB        | ~35 t/s     |
| Qwen3.8-27B ROCmFP8           | dense 27B      | 26.3 GiB  | 26.3 GiB        | ~8-10 t/s   |
| Qwen3.8-Flash-Next UD-Q3_K_XL | MoE 180B-A6B   | 101.3 GiB | ~4 GiB + engram | 11 t/s      |

The table records older engine and quantization configurations. Its 11 tok/s Flash-Next row is not a current Gufo measurement.
Strix now serves Flash-Next alone. The 3090 defaults to dense 27B and can swap to Muse.
Do not compare the historical 44 tok/s 3090 result with current HyperQwen throughput without matched requests.
A later
gufo streaming change removed the 4 GiB staging allocation in favor of a 1 MiB default; that setting
is a streaming buffer, not a model checkpoint-size limit. In a reported synthetic 4,171-token probe,
TTFT moved from 5.80s to 74ms, then 107ms; an observational sample of 98 requests reported 96.9%
prefix reuse and 1.18s TTFT versus a different earlier sample's 95.3% and 1.95s. These measurements
are encouraging but not controlled comparisons and do not establish a single root cause or faster
model inference.

Historical (2026-08-27; ComfyUI is now disabled in `kubernetes/apps/main/llm/kustomization.yaml`):
measured footprint of the resident set, mid-generate: GTT **76.8 GiB of 124**, ~47 GiB free, with
ComfyUI actually taking **6.8 GiB** rather than the 14 GiB its `--reserve-vram 110` permits. Wall
power: skirk **48.7 W** serving three models plus an image generation; the 3090 **142 W idle**,
~299 W under load.

## Consumers

| Consumer               | In repo?                                                                           | Points at                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OpenClaw**           | yes (`.../llm/openclaw/configmap.yaml`)                                            | defaults `minimax/MiniMax-M3.1-Flash` (fallbacks `qwen3.8-flash-next`, `qwen3.8-27b`, `dsv4.1f`); Miso/main `glm-5.3-flash`; Matcha `MiniMax-M3.1-Flash`; Saffron `reasoning-pool`; Sage `muse-glimmer`; subagents `muse-glimmer`; heartbeat `qwen3.8-flash-next-chat`; image `qwen3.8-flash-next-chat`; lossless-claw summary/expansion `local-pool-chat`                                                                                                                                              |
| **Hermes**             | yes (`.../llm/hermes/configmap.yaml`)                                              | default `reasoning-pool` (fallbacks `kimi-k3` -> `muse-glimmer` -> `qwen3.8-flash-next` -> `glm-5.3` -> `dsv4.1f`); compression/web-extract/approval/session-search `qwen3.8-flash-next`; vision `qwen3.8-flash-next-chat`; roles explorer `MiniMax-M3.1-Flash`, coder-local `qwen3.8-27b`, agentic-local `qwen3.8-flash-next`, implementer `implementation-pool`, reviewer `MiniMax-M3.1-Flash`, oracle `glm-5.3-flash`, vision-local `qwen3.8-flash-next-chat` |
| **Courier**            | yes (`.../llm/courier/config/laneprofile.yaml`)                                    | Configured consumers: `courier-local` -> `local`, `courier-cloud` -> `local` with the MiniMax-M3.1-Flash solo profile, `courier-hyper` -> `local` with the Hyper-only `glm-5.3-flash-hyper` hyper profile, `courier-frontier` -> `escalated` with the frontier profile (`glm-5.3-flash` coordinator). Queue is shared, not partitioned; models are in the LaneProfiles. |
| **Dispatch**           | yes (`.../llm/dispatch/helmrelease.yaml`)                                          | groomer -> `grooming-pool` (`qwen3.8-flash-next` primary; rungs Muse, GLM Flash on Hyper, GPT-6 Luna, then GLM Flash on Z.AI; 245760); lanes `local`, `frontier`, and `backlog`; aliases `normal` -> `local`, `escalated` -> `frontier`, `cloud` -> `local`. Manifest/configuration does not establish runtime claim or completion state.                                                                                                                                                                                                                                                                     |
| **Opencode** (CLI/Zen) | yes (`.../llm/opencode/configmap.yaml`)                                            | default `auto`; coordinator `reasoning-pool`; coordinator-local `qwen3.8-flash-next`; role subagents `MiniMax-M3.1-Flash`/`implementation-pool`/`qwen3.8-27b`/`qwen3.8-flash-next`/`glm-5.3-flash`, plus the workstation CLI on LiteLLM aliases directly                                                                                                                                                                                                                         |
| **memini**             | yes (`.../llm/memini/helmrelease.yaml`)                                            | LLM `muse-glimmer`; `embed`; `rerank`                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| **toolhive vMCP**      | yes (`.../llm/toolhive/config/virtualmcpserver.yaml`)                              | `embed` (optimizer)                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **alert-triage**       | yes (`.../observability/alert-triage/helmrelease.yaml`)                            | `qwen3.8-flash-next`                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **repo-wiki**          | yes (`.../llm/repo-wiki/helmrelease.yaml`)                                         | `WIKI_MODEL: local-strix`, which is not a LiteLLM alias; its key allows `local-pool-chat`, `qwen3.8-flash-next-chat`, `qwen3.8-27b-chat`                                                                                                                                                                                                                                                                                                                                                |
| **AI PR review**       | workflow yes (`.github/workflows/ai-pr-review.yaml`); models are repo Actions vars | primary `local-pool-chat`; fallback `MiniMax-M3.1-Flash`; smart `glm-5.3-flash` (vars read 2026-11-03)                                                                                                                                                                                                                                                                                                                                                              |
| **Zed**                | key only (`.../litellm/virtualkeys/zed.yaml`)                                      | LiteLLM aliases directly                                                                                                                                                                                                                                                                                                                                                                                                                                                                |

### OpenClaw cron fleet (unverified historical snapshot)

The repository configures four OpenClaw agents (Miso, Matcha, Saffron, Sage). The cron jobs are not in git; the table below
is a snapshot of Miso's and Saffron's 16 jobs and has not been re-verified. The model choice per job
already encodes an intent-lane pattern by hand.

| Job                             | Agent   | Model              | Schedule        | Purpose                                        |
| ------------------------------- | ------- | ------------------ | --------------- | ---------------------------------------------- |
| Afternoon Email/Finance Check   | Miso    | MiniMax-M2.7       | 4pm daily       | Email + financial anomaly scan                 |
| Instagram Hourly Image Dispatch | Miso    | qwen3.8-flash-next | 9am–8pm Mon–Thu | Publish one approved staged IG post per window |
| Image Category Creation         | Miso    | MiniMax-M3         | every 6h        | Generate new image category + gallery          |
| Evening Email/Finance Check     | Miso    | MiniMax-M2.7       | 9pm daily       | End-of-day email + finance summary             |
| Nightly Audit Decomposer        | Saffron | qwen3.8-flash-next | 2am daily       | Decompose audit umbrellas into child issues    |
| Nightly Tech Sweep              | Saffron | MiniMax-M3-chat    | 6:20am daily    | Overnight health check + low-risk fixes        |
| Morning Brief                   | Miso    | qwen3.8-flash-next | 8:00am daily    | Weather, calendar, inbox, IG pool, news, radon |
| Daily LLM + HN Digest           | Miso    | qwen3.8-flash-next | 8:30am daily    | r/LocalLLaMA etc. + HN top stories             |
| Daily Home-Ops Updates          | Saffron | MiniMax-M2.7       | 9am daily       | Commit watch on homelab k8s repos              |
| Daily Image (Miso)              | Miso    | qwen3.8-flash-next | 9:15am daily    | Character image generation                     |
| Alertmanager Health Digest      | Saffron | MiniMax-M3-chat    | 9:30am daily    | Firing Prometheus alerts + investigation       |
| Solar Daily Check               | Miso    | MiniMax-M2.7       | 9:35am daily    | Solar generation + weather + guess tracking    |
| Daily Image (Saffron)           | Saffron | qwen3.8-flash-next | 10:15am daily   | Character image generation                     |
| Weekly IG Posting Times         | Miso    | MiniMax-M3-chat    | 11am Fri        | Research optimal IG posting times              |
| Weekly Audit                    | Saffron | MiniMax-M2.7       | 1am Wed         | Spawn per-repo audit sub-agents                |
| Weekly Prompt Hygiene           | Saffron | MiniMax-M3-chat    | 10:45am Wed     | Audit prompt files for bloat/contradictions    |

Issue work (picking up issues and opening PRs) runs through Dispatch lanes rather than OpenClaw:
`local` is worked by Courier on local models, the MiniMax-M3.1-Flash profile and the Hyper-only `glm-5.3-flash-hyper` hyper profile; `frontier` is worked by `courier-frontier`. See [The coding loop](coding-loop.md).

## Current routing + observed usage

Routing today is `simple-shuffle` with hand-written availability fallbacks
(`kubernetes/apps/base/llm/litellm/litellmproxy.yaml`). `simple-shuffle` spreads a synchronized fan-out
evenly across a group's deployments; `least-busy` increments its in-flight
counter _after_ the routing decision, so a burst reads equal counts and piles
onto the first deployment — wrong for the 3-replica `embed` and `rerank` groups. `qwen3.8-flash-next`
is a single gufo server with 2 sessions, not a multi-instance group.

```yaml
routing_strategy: simple-shuffle
cooldown_time: 30
enable_pre_call_checks: true
fallbacks:
    - qwen3.8-flash-next: [qwen3.8-27b]
    - qwen3.8-flash-next-chat: [muse-glimmer, MiniMax-M3.1-Flash]
    - qwen3.8-27b: [qwen3.8-flash-next]
    - auto: [dsv4.1f, MiniMax-M3.1-Flash]
context_window_fallbacks:
    - qwen3.8-27b: [qwen3.8-flash-next]
```

Observed 7-day traffic (Prometheus, 2026-08-23; `litellm_total_tokens_metric_total`, cached input
included; all consumers combined). Alias names were retro-renamed; rows reflect the models of that date.

| Model                       | Reported tokens (7d) |
| --------------------------- | -------------------: |
| gpt-5.6-luna                |               329.0M |
| MiniMax-M3                  |               313.6M |
| qwen3.8-27b                 |               219.8M |
| deepseek-v4-flash (`dsv4f`) |               203.7M |
| glm-5.3                     |                74.5M |
| MiniMax-M3-chat             |                22.8M |
| MiniMax-M2.7                |                13.7M |
| k3                          |                 7.4M |

These are volume counters, not provider invoices. Kimi subscription traffic is valued at equivalent
Moonshot API rates in LiteLLM even though the plan itself is flat-rate. Cached input still counts against
upstream allocations.

### Cache accounting

There are two different caches in this stack:

- LiteLLM's Redis response cache (300-second TTL) covers only the `embedding`/`aembedding` call types
  (`supported_call_types`, #10517); chat completions are not response-cached. It is separate from
  provider prefix caching.
- OpenClaw model entries set `cache_prompt: true` for `kimi-k2.7`, `kimi-k3`, `glm-5.3`,
  `glm-5.3-flash`, `dsv4.1f` and the local aliases (`qwen3.8-flash-next`, `qwen3.8-27b`,
  `muse-glimmer`, `local-pool`, plus their `-chat` twins); the native MiniMax
  entries set `cacheRetention: "short"` instead. Providers may report prefix-cache reads in response
  usage, but they do not all expose that usage consistently.

GLM-5.3 on Z.AI is the important example. Prometheus showed zero `litellm_input_cached_tokens_metric_total`
for GLM, but a direct probe through LiteLLM on 2026-08-23 returned approximately 60k-145k cached
prefix tokens on repeated direct requests. Streaming usage chunks omitted or under-reported
`cached_tokens`. The zero Prometheus value is therefore not proof that Z.AI caching is disabled. Use
Z.AI's billing/usage dashboard to verify discounted billing for streamed requests; do not route main
away from GLM based on that counter alone.

### Context economics and guardrails

OpenClaw main (Miso) intentionally stays on GLM, now `glm-5.3-flash` (Hyper first, Z.AI second).
Saffron uses `reasoning-pool`; subagents use `muse-glimmer` and heartbeats use
`qwen3.8-flash-next-chat`. This preserves the quality lanes instead of routing main away from GLM
merely because one provider's streaming usage telemetry is incomplete.

The OpenClaw ConfigMap's lossless-claw settings are now tuned for the actual failure mode:

- `proactiveThresholdCompactionMode: inline`, `contextThreshold: 0.75`, `freshTailCount: 64`, and
  `freshTailMaxTokens: 24000` keep compaction work on the active turn and retain a bounded tail.
  Local Qwen aliases and both local pools override `contextThreshold` to 0.50.
- `leafChunkTokens: 20000`, `sweepDeadlineMs: 300000`, and `compactUntilUnderDeadlineMs: 600000` give
  leaf summarization enough time without allowing an unbounded sweep.
- `largeFileThresholdTokens: 6000` externalizes oversized tool results at ingest, before a diagnostic
  turn can accumulate dozens of large `exec` results. `stubLargeToolPayloads` remains false because
  there was no historical sidecar corpus to restub; old bloated sessions are not retroactively fixed.
- Model entries set `cache_prompt: true`, but cache savings do not reduce the upstream allocation consumed
  by a large prompt. Input-size discipline is still required even when the prefix cache is healthy.

The operational rule is simple: cap log/tool output, avoid replaying giant diagnostic dumps into a single
turn, and start a fresh session after a context incident. A single turn can exceed a model window before
`afterTurn()` compaction gets a chance to run.

### Slot accounting on local pools

Alias limits do not reserve hardware. Requests through different aliases and pools share the same backend sessions and cache.
The 3090 also serves automated work, so interactive requests compete with that workload.

Current declared limits:

- The direct 27B alias permits ten parallel requests against eight vLLM sequences. Its chat alias declares no parallel cap.
- The implementation pool caps its 27B rung at two requests. Its input/output metadata exceeds the backend total context when combined.
- Muse and both local-pool Muse rungs permit two requests, matching two llama.cpp slots.
- Flash-Next permits two sessions. Reasoning and both local pools cap their Flash-Next rungs at two, while grooming caps its rung at one.
- The bare Flash-Next alias is projected from the InferenceService. Its chat CR declares no parallel cap.
- The implementation pool marks its 27B rung vision-capable, but the direct alias and running text-only launcher do not support images.

These discrepancies are documented, not repaired by this pass. Do not infer ten simultaneous long-context requests from the direct alias cap.
The shared KV pool and fixed sequence state constrain actual concurrency.
Prefer targeted reads and direct changes for understood work. Delegate only when independent work justifies context, scheduling, and verification costs.
Agent names are not extra capacity. Flash-Next coordinator, agentic, and vision work share one engine.

## Smart-routing: the `auto` alias

An opt-in `auto` alias routes for **opencode, Zed and pi only**; every other consumer (crons,
Courier/Dispatch, Hermes roles, the native MiniMax aliases) stays pinned. It uses LiteLLM's **LLM
classifier** (`classifier_type: llm`), not the rule-based complexity scorer — see the measurements below.

Tiers (three effective tiers; REASONING is folded into COMPLEX):

| Tier           | Target                         | Why                                                      |
| -------------- | ------------------------------ | -------------------------------------------------------- |
| SIMPLE         | `qwen3.8-27b` (3090 AutoRound) | Small requests; local, shared capacity                                     |
| MEDIUM         | `MiniMax-M3.1-Flash`                   | Subscription capacity; still quota-limited                        |
| COMPLEX        | `reasoning-pool`               | K2.7 -> Sol -> GLM Flash (Hyper) -> GLM Flash (Z.AI) -> Flash-Next |
| REASONING      | `reasoning-pool`               | Folded — no classifier could separate it                 |
| default (miss) | `MiniMax-M3.1-Flash`                   | `classifier_fallback: default_model`                     |

Classifier is `qwen3.8-27b-chat` (`classifier_llm_config`, 20s timeout) — local but contended, and sits in
every request's path. Session affinity is on (`session_affinity: true`, 3600s TTL). The reviewer
alias classified until 2026-08-22, then `qwen3.8-flash-next`.

`frontier-pool` is deliberately **not** a tier target, but `auto` is not insulated from the weekly
caps: COMPLEX reaches Kimi K2.7 and GPT-6.1 Sol as `reasoning-pool` rungs 1 and 2, ahead of
GLM Flash on Hyper, GLM Flash on Z.AI, and Flash-Next. Kimi K3 stays in `frontier-pool` or explicit selection.

### Measured (2026-08-07, LiteLLM 1.95.0)

Two 20-prompt corpora, one held out. Scored against a throwaway proxy running the real router
against real backends.

| Config                                         | Tier accuracy      |
| ---------------------------------------------- | ------------------ |
| Rule-based scorer, boundaries `.45/.65/.85`    | **5/20 (25%)**     |
| Rule-based scorer, boundaries `.15/.35/.60`    | 7/20 (35%)         |
| LLM classifier (then-reviewer alias), held out | 17/20 (85%) 3-tier |
| LLM classifier, end-to-end on real pools       | **16/20 (80%)**    |

The scorer cannot be fixed by tuning. Observed score means: SIMPLE −0.120, MEDIUM +0.115,
**COMPLEX +0.085**, REASONING +0.205 — COMPLEX scores *below* MEDIUM, and the ceiling is 0.325.
It keys on code presence and keyword density, not reasoning depth, so a prose-heavy proof scores
under a request to rename a variable. No boundary choice recovers an ordering that isn't there.

This corrects a prior claim in this document that complexity "skews high" under code-dense system
prompts. It skews **low**; the raised boundaries were the direct cause of ~90% of traffic pinning
to SIMPLE. `tier_boundaries` is now removed (inert once `classifier_type: llm` is set).

`classifier_fallback` is `default_model`, **not** `heuristic` — a heuristic fallback silently
reverts to the 25% scorer on any classifier timeout, which is invisible in production.

Every remaining error is a conservative over-route (nothing hard lands somewhere weak); all 10
genuinely-hard prompts routed correctly in the end-to-end run.

**Known gap:** the corpora are bare user prompts. Real opencode traffic carries a large code-dense
system prompt that was never tested — the exact variable the old rationale was about. Treat 80% as
measured-on-bare-prompts. Audit with the `cause=` decision log
(`cause=llm_classifier | complexity_scorer | literal_keyword_match | session_affinity_pin`).
The classifier is also non-deterministic: identical inputs scored 15/20 and 17/20, so ±2.

Mechanics (verified against LiteLLM source):

- Both routers are pre-routing hooks returning a model _name_, resolved once — **no chaining**,
  so semantic can't sit "in front of" complexity. A model _group_ as a tier target works.
- Local context is guarded by `context_window_fallbacks` (only `qwen3.8-27b` -> `qwen3.8-flash-next`)
  plus `enable_pre_call_checks`, not by any router setting; nothing routes past flash-next's 262k.
The reasoning pool has no MiniMax rung. The direct MiniMax aliases use the Anthropic Messages endpoint.
The `auto` MEDIUM tier and classifier-miss default use `MiniMax-M3.1-Flash`.
Direct ChatGPT aliases are not tier targets, but Sol is reachable through reasoning.

**semantic router** (`auto-semantic` + `router.json`) was once scaffolded but is no longer in the
repo: `from_json` builds an encoder at startup (crashloop risk on the live gateway), so it would need
verify-then-enable if revived.

Still ahead:

- Evaluate a local MEDIUM tier only after measuring quality and latency under current contention. Historical 37–90s observations do not establish current latency.
- Re-measure against real opencode system prompts rather than bare user messages.
- Auto Router v2 offers `keyword_tier_rules` (deterministic tier overrides, `cause=literal_keyword_match`)
  if specific terms should force a tier regardless of classification.
- Harness-level quality escalation in OpenClaw/Hermes — escalate on tool failure, uncertainty markers,
  failed tests/lint, or explicit "are you sure". Supervision, not routing.

Reproduce: harness at `~/.cache/autorouter-probe` (configs, both corpora, probe scripts).

References: LiteLLM [Auto Routing](https://docs.litellm.ai/docs/proxy/auto_routing) ·
[Auto Router v2](https://docs.litellm.ai/blog/autorouter-v2) ·
[Fallbacks](https://docs.litellm.ai/docs/proxy/reliability).

## Frontier pool

`frontier-pool` is the explicit frontier escalation alias. Its strict order is Kimi K3, GPT-6 Astra, then GLM-5.3 on Z.AI.
It has no MiniMax, DeepSeek, or local floor. If all three rungs fail, the request fails instead of degrading to the reasoning lane.
Sol is in the reasoning pool and a direct alias, not another independent ChatGPT allowance.
Opencode declares a 272000-token ceiling for frontier, matching Astra's declared input ceiling.

Failover can change which model answers. Inspect LiteLLM deployment logs or response model identifiers rather than assume the first rung served the request.
Kimi historically signals exhaustion with HTTP 403, not only 429. The historical source investigation found ordered fallback after retries, without cooldown for 403.
That observation is not a fresh failure-injection test of the current LiteLLM version.
Use `litellm_deployment_failure_responses_total` and deployment fallback counters to diagnose actual failures.
Configuration establishes order and intent, not evidence that every upstream error path works.

## Reasoning-effort and thinking-mode pinning

Luna defaults to `high` on implementation and `max` on its direct alias.
Both use nested `extra_body: {reasoning: {effort: ...}}`, rather than a bare `reasoning_effort` default.
A historical LiteLLM investigation found that the provider transform dropped the bare form. Reinspect the outgoing request after relevant provider changes.
Client arguments can override these defaults. An enforced override requires separate proxy behavior, not documentation.
Effort consumes subscription allowance, so defaults are a quota/quality decision.

The remaining DeepSeek notes are historical. They describe retired `dsv4f` routes, not current fallback instructions.
The active `dsv4.1f` alias has Hyper and Neuralwatt deployments, with no thinking override or alias-level router fallback.

**DeepSeek V4 Flash runs with thinking default-on.** Historical (`dsv4f` retired 2026-09-26;
`dsv4.1f` sets no thinking override and has no router fallback of its own). The
`thinking: {type: disabled}` workaround for the upstream LiteLLM DeepSeek `reasoning_content`
multi-turn bug was removed after retesting the live OpenCode Go endpoint (2026-08-04):

- Multi-turn and full agentic tool round-trips now succeed with `reasoning_content` stripped — the
  failure the workaround existed for is fixed server-side. LiteLLM's own
  `DeepSeekChatConfig._fill_reasoning_content()` fix is irrelevant here either way: it is bound to
  `custom_llm_provider="deepseek"` and never runs on an `openai/`-via-OpenCode rung.
- The one surviving constraint is **forced** tool choice: `tool_choice: "required"` or a named
  function returns `400 "Thinking mode does not support this tool_choice"`. `tool_choice: "auto"` is
  fine, and forced calls fall through to the `dsv4f` → `qwen3.8-27b` router fallback rather than failing.
- Watch `litellm_deployment_successful_fallbacks_total{requested_model="dsv4f",fallback_model="qwen3.8-27b"}`.
  If it climbs, a consumer is forcing a tool and `extra_body: {thinking: {type: disabled}}` should be
  restored on that deployment. The likeliest source is the `qwen3.8-flash-next` → `dsv4f` context-window
  fallback, which arrives carrying whatever `tool_choice` the original caller set.
- `dsv4p` was retired with the Opencode Go plan on 2026-08-25; the note is kept for history.
