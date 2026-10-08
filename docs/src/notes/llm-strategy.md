# LLM Strategy

How the LLM fleet is subscribed, wired, and used — and where smart-routing is headed.

Everything funnels through **LiteLLM** (`kubernetes/apps/base/llm/litellm/litellmproxy.yaml` and
`kubernetes/apps/base/llm/litellm/models/*.yaml`) at `http://litellm.llm:4000`. Clients address stable
aliases; LiteLLM forwards to the upstream a given subscription or local server expects. This doc is the
reference for keeping those aliases meaningful and for designing intent-based routing on top of them.

**Reconciled again 2026-09-28.** GPT-5.6 aliases were replaced by GPT-6 Astra/Sol/Luna (2026-09-23),
`dsv4f` by `dsv4.1f` on Charm Hyper with a capped Neuralwatt rung (2026-09-26), Flash-Next moved to gufo
on ROCm (2026-09-24), `qwen3.8-27b` became Swift 1.5 on vLLM (2026-09-25), `muse-glimmer` is the default
resident of the 3090 pool, Kimi leads `frontier-pool` and `reasoning-pool` (2026-09-27), and
`gemma-4-12b-it-qat` is out of the coding roles. The **Model inventory**, pool, consumer and routing
sections below reflect this; the **capability ranking** and **v2 bench** sections still measure older
models (see the notes there).

The 2026-09-08 pass renamed the local aliases to model-specific names (`llama-nvidia`→`qwen3.8-27b`,
`llama-strix`→`qwen3.8-flash-next`, `llama-reviewer`→`gemma-4-12b-it-qat`, plus `-chat` twins), swapped
the Strix box from Qwen3.6-35B-A3B to Qwen3.8-Flash-Next, moved the reviewer lane to Gemma 4 12B-it QAT
on the 9070XT (LM Studio `gemma-wake`), removed the short-lived `llama-vision`, and swapped the reranker
to jina on CPU (since replaced by bge-reranker-v2-m3).

The prior pass (2026-08-25) retired Opencode Go and Moonshot, removed `glm-5.2`, renamed
`llama-strix-nemotron` to `llama-reviewer` (now `gemma-4-12b-it-qat`), moved the local models to
unsloth builds, and added a non-thinking `-chat` door beside each one.

This is a strategy snapshot, not a live quota ledger. Provider pricing, rolling allowances, and
Prometheus counters are perishable; dated observations below are labeled as such.

## Subscriptions

Subscriptions remain the primary capacity. Neuralwatt supplies energy-metered PAYG as `dsv4.1f` rung 2
behind Charm Hyper, capped at $1/day.

| Plan                | Price                                        | Cap                                                          | Reset                              | Models                                                | Primary use                                                                                               |
| ------------------- | -------------------------------------------- | ------------------------------------------------------------ | ---------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| **ChatGPT Plus**    | ~$25 CAD/mo                                  | unpublished rolling + weekly quota, with tier-weighted usage | rolling (3h chat) + weekly (Codex) | GPT-6 Astra, Sol, Luna                                | Astra `frontier-pool` rung 2; Sol `reasoning-pool` rung 2; Luna `implementation-pool` lead                |
| **MiniMax Plus**    | ~$200 USD/yr ($20/mo, annual = 2mo free)     | 300 prompts / 5h                                             | rolling 5h                         | M3 and M2.7, via the Anthropic endpoint               | Agentic reasoning workhorse                                                                               |
| **GLM Coding Lite** | ~$151 USD/yr (promotional, region-dependent) | ~80 prompts / 5h                                             | rolling 5h                         | GLM-5.3 and GLM-5.3-Flash on the Z.AI coding endpoint | `frontier-pool` rung 3 (GLM-5.3); `reasoning-pool` rung 3 and `glm-5.3-flash` rung 2 behind Hyper (Flash) |
| **Kimi Coding**     | ~$180 USD/yr ($15/mo; ~$261 CAD/12mo)        | plan allowance                                               | plan-defined                       | Kimi K2.7 Code, Kimi K3                               | `frontier-pool` lead (K3); `reasoning-pool` lead (K2.7)                                                   |
| **Charm Hyper**     | $20 USD/mo                                   | $12.50 of usage per 24h                                      | every 24h                          | GLM-5.3-Flash, DeepSeek V4.1 Flash (`HYPER_API_KEY`)  | `glm-5.3-flash` order 1; `dsv4.1f` order 1; `frontier-pool` rung 4                                        |
| **Neuralwatt**      | pay-per-use ($5/kWh energy billing)          | account credit; LiteLLM `max_budget` $1/day on its rung      | n/a                                | DeepSeek V4.1 Flash                                   | `dsv4.1f` rung 2, behind Hyper                                                                            |

Retired 2026-08-25: **Opencode Go** ($10 USD/mo gateway; DeepSeek V4 Flash/Pro, MiMo v2.5/Pro,
Qwen3.8-Max) and **Moonshot** (pay-per-use Kimi fallback behind Kimi Coding).

Caveats worth remembering:

- **MiniMax M3 is covered by the flat plan** (both M3 and M2.7), reached via the direct Anthropic
  endpoint. LiteLLM still logs ~$239/30d "phantom" spend against it — the plan is flat, the metric is
  not, so don't chase that number.
- **ChatGPT** was direct-through-Codex until recently; LiteLLM token history is light, but the
  weekly Codex cap is hit every week. OpenAI does not publish the exact weekly number. In the GPT-5.6
  generation (retired 2026-09-23) Luna consumed 80% fewer subscription credits and Terra 20% fewer;
  whether GPT-6 tiers carry the same weighting is not recorded here.
- **GLM Lite's** annual USD price is promotional and not cleanly published.
- **Charm Hyper's** price and cap are not recorded here.
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
weights, KV cache and slots, so the second door costs no memory. `muse-glimmer` is the exception: it
has no `-chat` twin.

### Local (self-hosted, $0 marginal)

| Alias                     | Backend                                            | Model                                                                     | Ctx (in)                                    | Role                                                                                    |
| ------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------- | ------------------------------------------- | --------------------------------------------------------------------------------------- |
| `qwen3.8-flash-next`      | skirk (Strix Halo), gufo ROCm (2 sessions)         | Qwen3.8-Flash-Next 180B-e51B-A6B UD-Q4_K_XL, MTP (Q8_0 head), mmproj BF16 | 262k (LiteLLM 245760)                       | General local brain; vision + tools; Courier coordinator                                |
| `qwen3.8-flash-next-chat` | same server                                        | —                                                                         | 262k (LiteLLM 245760)                       | Non-thinking door (`enable_thinking: false`); OpenClaw image + heartbeat, Hermes vision |
| `muse-glimmer`            | 3090, ModelPool `nvidia` default resident          | Muse-Glimmer-30B UD-Q5_K_M, llama.cpp CUDA, DFlash draft, mmproj, 2 slots | 131k                                        | OpenClaw subagents + Sage, memini LLM, `local-pool` rung 1, vision fallback             |
| `qwen3.8-27b`             | 3090, ModelPool `nvidia` via `nvidia-router-proxy` | Swift 1.5 (`ukisai/Swift-1.5-Qwen3.8-27b-W4A16-AWQ`), vLLM, MTP           | 144k total (MAX_LEN 147456; LiteLLM 122880) | Coding lane (Courier `coder-local`, `implementation-pool` rung 2); text-only            |
| `qwen3.8-27b-chat`        | same server                                        | —                                                                         | same                                        | Non-thinking door; `auto` classifier                                                    |
| `gemma-4-12b-it-qat`      | 9070XT (Windows, LM Studio)                        | Gemma 4 12B-it QAT                                                        | 262144                                      | Manual use (`gemma-wake`); `local-pool` rung 3; Hermes `local-reviewer`                 |
| `gemma-4-12b-it-qat-chat` | same server                                        | —                                                                         | 262144                                      | Non-thinking door; `local-pool-chat` rung 3                                             |
| `embed`                   | CPU (3 replicas)                                   | Qwen3-Embedding-0.6B Q8_0                                                 | 32k                                         | Embeddings (1024-dim) for memini                                                        |
| `rerank`                  | CPU (3 replicas)                                   | bge-reranker-v2-m3 Q8_0                                                   | —                                           | memini reranking                                                                        |

**The 3090 is a ModelPool.** `nvidia` (`kubernetes/apps/base/llm/litellm/nvidia-pool.yaml`) swaps the
card between `muse-glimmer` (the default) and `qwen3.8-27b` (`swapPolicy: reclaim`, `reclaimAfter: 5m`,
`swapBudget: 900s`). The one-way `muse-fallthrough` rule (`poolActivation: IfIdle`) lets muse requests
be served by the 27B; 27B requests never fall through to muse. Rationale is in
[The shared 3090](coding-loop.md#the-shared-3090).

Vision no longer has a dedicated model — the old `llama-vision` (CPU Gemma 4 E4B, briefly) was removed;
image analysis goes through `qwen3.8-flash-next-chat`, whose router fallback is `muse-glimmer` then
`MiniMax-M2.7`. `qwen3.8-27b` is text-only. Commented-out manifests kept as named fallback references
in `kubernetes/apps/base/llm/litellm/kustomization.yaml`: `qwen3.6-35b-a3b`,
`nemotron-3.5-lightning-30b-a3b`, `glm-5.3-flash-local`, the llama.cpp ROCm and Vulkan Flash-Next
variants, and the `gemma-4-e4b` vision sidecar.

`dsv4f-local` (DeepSeek-V4-Flash UD-IQ2_M) is still registered as a LiteLLM alias
(`models/dsv4f-local.yaml`), but no backend InferenceService exists for it, so it cannot serve. The FP8
variant was deleted (FP8 doesn't work on gfx1151).

### Cloud (flat-rate subscriptions)

| Alias                 | Subscription                      | Upstream model                              | Ctx (in) | Role                                                                                          |
| --------------------- | --------------------------------- | ------------------------------------------- | -------- | --------------------------------------------------------------------------------------------- |
| `MiniMax-M3`          | MiniMax Plus                      | MiniMax-M3 (Anthropic endpoint)             | 1M       | OpenClaw default + Matcha primary; `auto` MEDIUM and miss default; Hermes/opencode `reviewer` |
| `MiniMax-M3-chat`     | MiniMax Plus                      | MiniMax-M3 (OpenAI endpoint)                | 1M       | Router fallback for `gemma-4-12b-it-qat` and `auto`                                           |
| `MiniMax-M2.7`        | MiniMax Plus                      | MiniMax-M2.7                                | 204.8k   | Agentic workhorse; `explorer` role; `implementation-pool` rung 3                              |
| `glm-5.3`             | GLM Coding Lite                   | glm-5.3 (Z.AI)                              | 1M       | Hermes fallback; manual. `frontier-pool` rung 3 is a separate deployment of the same model    |
| `glm-5.3-flash`       | Charm Hyper, then GLM Coding Lite | glm-5.3-flash (order 1 Hyper, order 2 Z.AI) | 1M       | OpenClaw Miso/main primary; `oracle` role                                                     |
| `chatgpt/gpt-6-astra` | ChatGPT Plus                      | gpt-6-astra (Codex/OAuth)                   | 272k*    | Direct alias; `frontier-pool` rung 2                                                          |
| `chatgpt/gpt-6.1-sol` | ChatGPT Plus                      | gpt-6.1-sol (Codex/OAuth)                   | 272k     | Direct alias; `reasoning-pool` rung 2                                                         |
| `chatgpt/gpt-6-luna`  | ChatGPT Plus                      | gpt-6-luna (Codex/OAuth)                    | 272k     | Direct alias (effort pinned `max`); `implementation-pool` lead                                |
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
`frontier-pool` rung 4 is its own Hyper deployment; Neuralwatt is not in any pool.

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

One file per pool in `models/` (`frontier-pool.yaml`, `reasoning-pool.yaml`, `implementation-pool.yaml`,
`local-pool.yaml`).

| Pool                  | Order  | Members                                                                                                            | Effort pins                                   | Policy                                                             |
| --------------------- | ------ | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- | ------------------------------------------------------------------ |
| `frontier-pool`       | 1 -> 4 | Kimi K3 (Kimi Coding) -> GPT-6 Astra (ChatGPT) -> GLM-5.3 (Z.AI) -> DSV4.1F (Hyper)                                | none                                          | Frontier escalation; no MiniMax floor                              |
| `reasoning-pool`      | 1 -> 5 | Kimi K2.7 (Kimi Coding) -> GPT-6.1 Sol (ChatGPT) -> GLM-5.3-Flash (Z.AI) -> MiniMax-M3 (`/v1`) -> qwen3.8-flash-next | none; K2.7 drops `reasoning_effort`         | Planning lane; M3 is the flat-plan floor, flash-next the local one |
| `implementation-pool` | 1 -> 3 | GPT-6 Luna (ChatGPT) -> qwen3.8-27b (3090) -> MiniMax-M2.7                                                         | Luna `max` (`extra_body`); 27b `xhigh`        | Implementation lane, deliberately below the planning lane          |
| `local-pool`          | 1 -> 3 | muse-glimmer (3090) -> qwen3.8-flash-next (skirk) -> gemma-4-12b-it-qat (9070XT)                                   | none                                          | Local-only, $0 marginal                                            |
| `local-pool-chat`     | 1 -> 3 | same members, non-thinking samplers                                                                                | flash-next and gemma `reasoning_effort: none` | OpenClaw lossless-claw; AI PR review primary                       |

The three cloud-led pools are a capability ladder, not three copies of the same idea: `frontier-pool` for
actual problems, `reasoning-pool` for planning, `implementation-pool` for carrying out a plan already
made. Kimi leads `frontier-pool` (K3) and `reasoning-pool` (K2.7); ChatGPT is rung 2 in both and rung 1
in `implementation-pool` (Luna). A Kimi cap-out drops frontier and reasoning to their ChatGPT rungs; a
ChatGPT cap-out touches all three pools at once, so ChatGPT is still the most widely shared dependency.

`local-pool` and `local-pool-chat` are the local-only ladder. The Courier, Dispatch and PR-review keys
are allowed `local-pool`; OpenClaw's lossless-claw summary/expansion and the AI PR review workflow's
primary model use `local-pool-chat`. Rung 3 is gemma, so those consumers still land on it when rungs 1
and 2 fail, even though gemma is out of the coding roles.

Reasoning effort is **passed through**, not pinned, on every ChatGPT rung except Luna, which is pinned
to `max` via `extra_body: {reasoning: {effort: max}}` both in `implementation-pool` and in
`chatgpt-gpt-6-luna.yaml` (2026-09-28). The pin is a default rather than a hard override (see
**Reasoning-effort and thinking-mode pinning**). The earlier `high` pin was chosen because GPT-5.6 Luna's
TTFT measured ~60s at `xhigh` against ~10s at `high`; the move to `max` reverses that trade and has
not been re-measured on GPT-6.

LiteLLM has no group-level window: each rung declares its own `maxInputTokens`, and with
`enable_pre_call_checks` a request too large for a rung is filtered off it. Clients declare their own
ceiling per group; opencode declares `implementation-pool` 147456 (the 27B's MAX_LEN, rung 2),
`frontier-pool` 272000 (Astra, rung 2) and `reasoning-pool` 1000000. In `reasoning-pool`, rung 1 (K2.7)
takes 262144 and rung 5 (flash-next) 245760, so a request past those only lands on Sol (272k),
GLM-5.3-Flash (1M) or M3 (1M).

**Provider failover** (LiteLLM `order:`, transparent to callers) reacts when an upstream rejects a
request; it cannot detect that an unpublished rolling allowance is merely _close_ to exhausted.

`glm-5.3-flash` (rung 3, Z.AI) sits between Sol and the M3 floor. It accepts `reasoning_effort`
(`allowed_openai_params`) but the rung pins none, so it takes the caller's. It is a stronger rung than
dropping straight to M3, but it spends GLM Coding Lite quota — the same subscription behind
`frontier-pool` rung 3 — so sustained reasoning overflow can leave frontier escalation a rung
shorter. M3 remains the floor precisely because the flat plan cannot be exhausted this way.

Kimi-for-Coding was once removed from `reasoning-pool` because its 262k context capped the pool's
declared window. It returned as rung 1 on 2026-09-27 (#10571); requests past 262k skip it.

## Model capability ranking

> **Stale as of the 2026-09-08 rename.** The scores and analysis below were measured against the previous local models — Qwen3.6-35B-A3B on the Strix box (now Qwen3.8-Flash-Next) and Nemotron 3.5 Lightning as the reviewer (now Gemma 4 12B-it QAT). The aliases have been renamed to match the current names, but the numbers have **not** been re-run; treat them as historical until re-benchmarked. Since then: the GPT-5.6 aliases were retired 2026-09-23 (GPT-6 Astra/Sol/Luna replaced them), `dsv4f` was retired 2026-09-26 (`dsv4.1f` replaced it), and `qwen3.8-27b` has served Swift 1.5 since 2026-09-25. Rows naming those aliases describe the models of the snapshot date.

Benchmark snapshot as of **2026-08-23** — perishable. Numbers remain largely **vendor
self-reported on non-overlapping harnesses** (SWE-bench Pro ≠ Verified; Terminal-Bench
2.0 ≠ 2.1 ≠ 3.0; vendor SWE-Pro runs 15–30pts above standardized scaffolding), so treat deltas as
**directional**, not precise, and re-pull when models bump. `n/p` = not published. Do not read this
table as a statement about pricing, cache behaviour, or quota consumption.

Rows for `dsv4p`, `glm-5.2`, `mimo-v2.5` and `mimo-v2.5-pro` are kept for reference only — those
aliases were retired on 2026-08-25 and are no longer served. The Mellum2 row is likewise
historical: in that snapshot the then-reviewer alias (later renamed `gemma-4-12b-it-qat`) served
Nemotron 3.5 Lightning 30B-A3B; it now runs Gemma 4 12B-it QAT on the 9070XT (LM Studio `gemma-wake`)
and is out of the coding process.

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
context is 262k; the 24GB 3090 runs `MAX_LEN` 147456 (~144k). There is no Qwen3.8-35B-A3B. Since
2026-09-25 the alias serves Swift 1.5 (`ukisai/Swift-1.5-Qwen3.8-27b-W4A16-AWQ`, #10496), so the vendor
numbers in this row describe the base model, not the deployed one.

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
Qwen3.6 in the 2026-08-25 unsloth move). Since 2026-09-24 (#10479) it runs on gufo (ROCm) at
UD-Q4_K_XL with the MTP head. Image analysis goes through `qwen3.8-flash-next-chat`, with `muse-glimmer`
as router fallback, rather than a dedicated `llama-vision`, which was removed.

Mellum2 (historical reviewer lane; this paragraph previously carried the retro-renamed alias
`gemma-4-12b-it-qat`) publishes more than the previous snapshot credited it with — the
[Mellum2 Instruct card](https://huggingface.co/JetBrains/Mellum2-12B-A2.5B-Instruct) carries
LiveCodeBench v6 37.2, EvalPlus 78.4, MultiPL-E 67.1, GPQA 40.9 and AIME 41.7, all self-reported. What
it genuinely does not publish is any *agentic* coding bench: no SWE-bench of any slice, no
Terminal-Bench. Its headline remains **BFCL v3 66.3** (tool use), which is the axis that actually
matters for a reviewer: the verdict is a structured `submit_result` call whose `issueAsk` must be a
verbatim substring of the issue body, and a malformed payload is rejected by the harness regardless of
how good the judgement was. Newer numbers exist that the row does not use — BFCL v4 44.2, and a
**Thinking** variant at BFCL v3 69.4 / LiveCodeBench v6 69.9, nearly double the Instruct build. Rank it
on independence and format reliability, not on a coding leaderboard.

Reading it for routing:

- **The independent numbers narrowed the frontier, they did not reorder it.** On AA's single harness
  the top of this table is Sol 61, GLM-5.3 60, Qwen3.8-Max 58, K3 57 — a four-point spread across four
  different subscriptions. Treating any of them as decisively better than the others is not supported.
- **Frontier tier** (`gpt-5.6-sol`, `kimi-k3`, `glm-5.3`; 2026-08-23 analysis, current `frontier-pool`
  is K3 -> `gpt-6-astra` -> GLM-5.3 -> `dsv4.1f`) — unchanged, and now better evidenced. Sol
  is the ceiling on the strength of an independent SWE-V 96.2 that OpenAI never claimed itself; K3 is
  the independent coding lane at SWE-V 93.4; GLM-5.3 is the long-horizon fallback but is the *least*
  independently verified model in the tier — its entire benchmark table is one vendor blog, its weights
  are unreleased, and the only official-board GLM datapoint runs 10pts under the vendor's own claim.
- **What dropping Opencode Go cost.** *(Executed 2026-08-25.)* Go supplied `dsv4p`, `dsv4f`,
  `mimo-v2.5(-pro)` and `qwen3.8-max`. The reasoning at the time, which held:
  - `dsv4p` is the real loss and it is narrow: **SWE-bench Verified 96.4, the second-best score on
    Vals' board**. But Sol sits at 96.2 on that *same* harness. The capability is duplicated by a
    subscription that is staying, at a 0.2pt difference — inside anyone's error bar.
  - `dsv4f` is the volume workhorse, and its replacement is already racked. Flash and the local
    Qwen3.8-27B on the 3090 **both score AA-II 52**. For OpenClaw subagent and heartbeat traffic,
    which is what Flash actually serves, the local box is a like-for-like substitute at zero marginal
    cost. Flash's genuine edge over local is the 1M context and the throughput, not the intelligence.
  - `qwen3.8-max` posts the highest AA-II of the Go set at 58, but it is also the row whose vendor
    claims collapse hardest under independent testing (Term-B 86.6 → 67.4). GLM-5.3 at 60 and K3 at 57
    bracket it on a harness that measured all three the same way.
  - `mimo-v2.5` (38) and `mimo-v2.5-pro` (43) are beaten by MiniMax-M3 (45) on the flat plan, and by
    the local Qwen3.8-27B (52). Nothing is lost.
  - **Net: the frontier ceiling is unaffected and the cheap lane moves to hardware already owned.** The
    exposure is operational rather than qualitative — losing 1M-context cheap throughput, and losing
    `dsv4f` as the third reasoning-pool rung, which would need repointing at local or MiniMax
    (historical, `dsv4f` retired 2026-09-26).
- **DeepSeek V4 Flash is still genuinely strong and the refresh made it stronger** — AA lifted it 40 →
  52 on the 0731 build, its independently-measured GPQA is 91, and repo-bench previously re-scored it
  0.895 → 0.957 while V4 Pro stayed at 0.864. The argument for dropping it is that the capability is
  now duplicated locally and by flat-rate plans, not that the model is weak.
- **Reasoning tier** (`gpt-5.6-luna`, `MiniMax-M3`; historical, GPT-5.6 retired 2026-09-23) — Luna
  was the weakest GPT tier here at AA-II 51 and its long-context recall collapsed (vendor MRCR 41.3
  against Sol's 91.5), so the pool's nominal 1M context was not usable depth on that rung. Current
  `reasoning-pool` is K2.7 -> `gpt-6.1-sol` -> GLM-5.3-Flash -> MiniMax-M3 -> `qwen3.8-flash-next`; Luna
  now leads `implementation-pool`.
- **Local** — `qwen3.8-27b` is now Qwen3.8-27B and the gap to `qwen3.8-flash-next` widened from "trails it
  everywhere" to a 20-point AA-II spread (52 vs 32). `qwen3.8-flash-next` earns its place on the 262k window
  and vision, nothing else. The local box is now competitive with paid cheap-tier cloud, which is the
  single most decision-relevant change in this refresh.
- **`gemma-4-12b-it-qat` is out of the coding process** (2026-09-27). It was kept as a non-Qwen
  family split to review Qwen-authored code, but it missed the known defect in the 2026-09-22
  adversarial review benchmark, and it depends on waking the gaming PC. It stays served (LiteLLM +
  `gemma-wake`) for manual use; review now goes to MiniMax-M3 and `qwen3.8-flash-next`. It still
  backs Hermes `local-reviewer` and is rung 3 of `local-pool`/`local-pool-chat`, so the AI PR review
  workflow (primary `local-pool-chat`) can still land on it.
- **MiniMax-M2.7 / MiMo** — agentic workhorses with thin published reasoning numbers; rank on
  coding/agentic axes, not GPQA/AIME.

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

## v2 bench: the local models are within noise of each other

> **Same caveat as the capability ranking:** measured against the pre-2026-09-08 local models, aliases renamed but scores not re-run.

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
`implementation-pool` (and the direct alias), both pinned to `effort: max`. That row is not evidence
about the deployed path.

Methodology trap: candidate names are not stable across time. `qwen3.8-flash-next` meant Ornith in August
and Flash-Next later, and `tally` merges by candidate name — check what the alias pointed at before
comparing rows.

## Where a model runs is decided by memory bandwidth

Strix Halo has ~256 GB/s theoretical and ~200-220 GB/s real. Decode is bandwidth-bound, so what
matters is **active** parameters per token, not total parameters:

| Model                         | Arch           | Weights   | Read/token      | Measured TG |
| ----------------------------- | -------------- | --------- | --------------- | ----------- |
| Qwen3.6-35B-A3B Q4            | MoE, 3B active | 21.3 GiB  | ~1.7 GiB        | 34-42 t/s   |
| Nemotron 3.5 30B-A3B Q4       | MoE, 3B active | 23.8 GiB  | ~1.7 GiB        | ~35 t/s     |
| Qwen3.8-27B ROCmFP8           | dense 27B      | 26.3 GiB  | 26.3 GiB        | ~8-10 t/s   |
| Qwen3.8-Flash-Next UD-Q3_K_XL | MoE 180B-A6B   | 101.3 GiB | ~4 GiB + engram | 11 t/s      |

As of 2026-08: **Strix runs A3B-class MoE and small dense vision models; the 3090 runs the dense 27B**,
where 900+ GB/s of VRAM gives it 44 t/s on weights that would crawl on the APU. A dense model on Strix
is slow no matter how good it scores, and Flash-Next is slow *and* needs 101 GiB — it evicts the whole
rest of the resident set to hold a tie on quality (see the v2 bench section). Since 2026-09-24 skirk
runs Flash-Next alone (gufo); the 3090 pool holds `muse-glimmer` (default) or the 27B.

Historical (2026-08-27; ComfyUI is now disabled in `kubernetes/apps/main/llm/kustomization.yaml`):
measured footprint of the resident set, mid-generate: GTT **76.8 GiB of 124**, ~47 GiB free, with
ComfyUI actually taking **6.8 GiB** rather than the 14 GiB its `--reserve-vram 110` permits. Wall
power: skirk **48.7 W** serving three models plus an image generation; the 3090 **142 W idle**,
~299 W under load.

## Consumers

| Consumer               | In repo?                                                                           | Points at                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ---------------------- | ---------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OpenClaw**           | yes (`.../llm/openclaw/configmap.yaml`)                                            | defaults `minimax/MiniMax-M3` (fallbacks `qwen3.8-flash-next`, `qwen3.8-27b`, `dsv4.1f`); Miso/main `glm-5.3-flash`; Matcha `MiniMax-M3`; Saffron `reasoning-pool`; Sage `muse-glimmer`; subagents `muse-glimmer`; heartbeat `qwen3.8-flash-next-chat`; image `qwen3.8-flash-next-chat`; lossless-claw summary/expansion `local-pool-chat`                                                                                                                                              |
| **Hermes**             | yes (`.../llm/hermes/configmap.yaml`)                                              | default `reasoning-pool` (fallbacks `kimi-k3` -> `muse-glimmer` -> `qwen3.8-flash-next` -> `glm-5.3` -> `dsv4.1f`); compression/web-extract/approval/session-search `qwen3.8-flash-next`; vision `qwen3.8-flash-next-chat`; roles explorer `MiniMax-M2.7`, coder-local `qwen3.8-27b`, agentic-local `qwen3.8-flash-next`, implementer `implementation-pool`, reviewer `MiniMax-M3`, local-reviewer `gemma-4-12b-it-qat`, oracle `glm-5.3-flash`, vision-local `qwen3.8-flash-next-chat` |
| **Courier**            | yes (`.../llm/courier/config/laneprofile.yaml`)                                    | LaneProfile `local`, concurrency 1: coordinator + `agentic-local` (large recon, adversarial review) -> `qwen3.8-flash-next`; `coder-local` (narrow file-scoped work, at most two in flight) -> `qwen3.8-27b`                                                                                                                                                                                                                                                                            |
| **Dispatch**           | yes (`.../llm/dispatch/helmrelease.yaml`)                                          | groomer -> `qwen3.8-flash-next` (262144); lanes `local` (default, worked by Courier) and `frontier` (escalation, MiniMax-M3, no worker); aliases `normal` -> `local`, `escalated` -> `frontier`, `cloud` -> `local`                                                                                                                                                                                                                                                                     |
| **Opencode** (CLI/Zen) | yes (`.../llm/opencode/configmap.yaml`)                                            | default `auto`; coordinator `reasoning-pool`; coordinator-local `qwen3.8-flash-next`; role subagents `MiniMax-M2.7`/`MiniMax-M3`/`implementation-pool`/`qwen3.8-27b`/`qwen3.8-flash-next`/`glm-5.3-flash`, plus the workstation CLI on LiteLLM aliases directly                                                                                                                                                                                                                         |
| **memini**             | yes (`.../llm/memini/helmrelease.yaml`)                                            | LLM `muse-glimmer`; `embed`; `rerank`                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| **alert-triage**       | yes (`.../observability/alert-triage/helmrelease.yaml`)                            | `qwen3.8-flash-next`                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| **repo-wiki**          | yes (`.../llm/repo-wiki/helmrelease.yaml`)                                         | `WIKI_MODEL: local-strix`, which is not a LiteLLM alias; its key allows `local-pool-chat`, `qwen3.8-flash-next-chat`, `qwen3.8-27b-chat`                                                                                                                                                                                                                                                                                                                                                |
| **AI PR review**       | workflow yes (`.github/workflows/ai-pr-review.yaml`); models are repo Actions vars | primary `local-pool-chat`; fallback `GLM-5.3-flash-local` (not a LiteLLM alias); smart `MiniMax-M3` (vars read 2026-09-28)                                                                                                                                                                                                                                                                                                                                                              |
| **Zed**                | key only (`.../litellm/virtualkeys/zed.yaml`)                                      | LiteLLM aliases directly                                                                                                                                                                                                                                                                                                                                                                                                                                                                |

### OpenClaw cron fleet

OpenClaw has four agents (Miso, Matcha, Saffron, Sage). The cron jobs are not in git; the table below
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
`local` is worked by Courier on local models; `frontier` (MiniMax-M3 escalation) currently has no
worker. See [The coding loop](coding-loop.md).

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
    - qwen3.8-flash-next-chat: [muse-glimmer, MiniMax-M2.7]
    - qwen3.8-27b: [qwen3.8-flash-next]
    - gemma-4-12b-it-qat: [MiniMax-M3-chat]
    - auto: [dsv4.1f, MiniMax-M3-chat]
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
| gemma-4-12b-it-qat          |                45.0M |
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
  `gemma-4-12b-it-qat`, `muse-glimmer`, `local-pool`, plus their `-chat` twins); the native MiniMax
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

### Slot accounting on the local pools

`max_parallel_requests` per LiteLLM member should match the backend's real concurrency,
because the two failure modes are asymmetric:

- **Cap above the backend** and requests queue *inside* the server, invisible to the router.
  In 2026-08 `qwen3.8-27b` (then llama.cpp) sat at 2 against a single slot; the queueing surfaced as
  a 53 s average time-to-first-token on the alias while the model itself was fine (fixed 2026-08).
- **Cap below the backend** and provisioned VRAM goes unused. The reviewer alias (now
  `gemma-4-12b-it-qat`) served 3 slots while LiteLLM dispatched into 2 — a third of the model
  unreachable (fixed 2026-08).

Current caps (`models/*.yaml`):

- `qwen3.8-27b` 10 against vLLM `MAX_SEQS` 8 (`litellm/qwen3.8-27b.yaml`) — a known discrepancy. The
  `implementation-pool` 27b rung caps at 2, and Courier's LaneProfile keeps `coder-local` to two in
  flight. That rung also declares 131072 in + 40960 out, more than the 147456 `MAX_LEN`.
- `muse-glimmer` 2, matching its 2 llama.cpp slots; its `local-pool`/`local-pool-chat` rungs are 2.
- `qwen3.8-flash-next` rungs: `reasoning-pool` 2, `local-pool` 1, `local-pool-chat` 1, against gufo
  `--sessions 2`. The bare alias is auto-projected, so its cap is not in `models/`.
- gemma `local-pool`/`local-pool-chat` rungs 4. `qwen3.8-27b-chat`, `qwen3.8-flash-next-chat` and the
  bare gemma aliases set no cap.

As of 2026-08, with several models resident on skirk, aggregate tok/s improved with concurrent streams
spread **across** resident models rather than piled onto one (roughly 6-8 streams for the whole box).
Skirk now serves Flash-Next alone. The Mac LM Studio member was removed; `qwen3.8-flash-next` is the
single cluster server (one gufo process, 2 sessions).

Courier is the main automated consumer. It runs at concurrency 1; the coordinator holds one of the
two `qwen3.8-flash-next` sessions and `agentic-local` uses the other. Since 2026-09-27 its key is ~54%
`qwen3.8-flash-next` prompt tokens (coordinator ~42%, reviewer ~12%) and ~39% `qwen3.8-27b`. The
lever on its share is the LaneProfile concurrency. The last whole-box utilisation figure (~15 busy-hours/day against 96 slot-hours)
predates Courier and has not been re-measured.

## Smart-routing: the `auto` alias

An opt-in `auto` alias routes for **opencode, Zed and pi only**; every other consumer (crons,
Courier/Dispatch, Hermes roles, the native MiniMax aliases) stays pinned. It uses LiteLLM's **LLM
classifier** (`classifier_type: llm`), not the rule-based complexity scorer — see the measurements below.

Tiers (three effective tiers; REASONING is folded into COMPLEX):

| Tier           | Target                         | Why                                                      |
| -------------- | ------------------------------ | -------------------------------------------------------- |
| SIMPLE         | `qwen3.8-27b` (3090 Swift 1.5) | Trivia — local, free                                     |
| MEDIUM         | `MiniMax-M3`                   | Flat sub, no weekly quota to burn                        |
| COMPLEX        | `reasoning-pool`               | K2.7 -> Sol -> GLM-5.3-Flash -> MiniMax-M3 -> flash-next |
| REASONING      | `reasoning-pool`               | Folded — no classifier could separate it                 |
| default (miss) | `MiniMax-M3`                   | `classifier_fallback: default_model`                     |

Classifier is `qwen3.8-27b-chat` (`classifier_llm_config`, 20s timeout) — local and free to sit in
every request's path. Session affinity is on (`session_affinity: true`, 3600s TTL). The reviewer
alias classified until 2026-08-22, then `qwen3.8-flash-next`.

`frontier-pool` is deliberately **not** a tier target, but `auto` is not insulated from the weekly
caps: COMPLEX reaches Kimi K2.7 and GPT-6.1 Sol as `reasoning-pool` rungs 1 and 2, ahead of
GLM-5.3-Flash, MiniMax-M3 and flash-next. Kimi K3 stays in `frontier-pool` or explicit selection.

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
- `reasoning-pool`'s M3 rung uses MiniMax's OpenAI-compatible `/v1` endpoint, so it may expose
  thinking in content; acceptable for this lane. OpenClaw's native `MiniMax-M3` alias uses the
  Anthropic `/messages` endpoint and its think-tag stripping shim.

Excluded from `auto` by design: the direct `chatgpt/*` aliases are not tier targets (Sol is reachable
only as `reasoning-pool` rung 2). The native `MiniMax-M3` messages alias is the MEDIUM tier and the
classifier-miss default.
A **semantic router** (`auto-semantic` + `router.json`) was once scaffolded but is no longer in the
repo: `from_json` builds an encoder at startup (crashloop risk on the live gateway), so it would need
verify-then-enable if revived.

Still ahead:

- Swap MEDIUM to `qwen3.8-27b` once the 3090 has headroom beyond Courier's `coder-local` — it's the better model and free, but was
  measured at 37–90s under contention, unusable for a tier that receives over-routed volume.
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

The `frontier-pool` alias is the "grab the smartest model with room left" lane for opencode/Zed — pick
it and ask it to do things; LiteLLM routes to the best-available frontier model and falls down the chain
a strict `order:` chain (429/403 -> cooldown -> next). Subscriptions first, DeepSeek last:

1. `kimi-k3` @ Kimi Coding — dedicated Kimi sub (flat), 1M
2. `gpt-6-astra` @ ChatGPT Plus — flagship frontier, capped at 272k (see the Astra footnote)
3. `glm-5.3` @ Z.AI — GLM Coding Lite sub
4. `dsv4.1f` @ Charm Hyper — DeepSeek V4.1 Flash

`gpt-6.1-sol` is not a rung. It draws the same ChatGPT rolling window as Astra, so pairing the two would
give a second rung with no headroom of its own; it is `reasoning-pool` rung 2 and a direct alias.
Rung 1 (K3) is 1M; opencode declares the pool at 272k, the smallest rung (Astra, rung 2).

Implemented as one **self-contained `order:` group**, not router fallbacks referencing the shared
groups. It intentionally has no MiniMax floor: a frontier request fails rather than silently degrading
to the reasoning lane.

Caveats:

- **Know which model answered.** Failover is silent — read the `x-litellm-model-id` response header (or
  the LiteLLM logs) to see whether you're on K3, Astra, GLM or Hyper DSV4.1F.
- **No silent quality downgrade.** Once all four rungs reject a request, the request fails. Use
  `reasoning-pool` when MiniMax M3 is an acceptable final fallback.
- **Cap signals are not all 429s.** Kimi Coding announces exhaustion with a **403**, not a 429. A 403
  is retried but never cools the deployment down, so retries re-hit the capped rung; what actually
  advances the chain is LiteLLM's automatic **order-based fallback**, which synthesises fallback
  entries for the higher `order:` rungs of the same group once retries are exhausted. No separate
  model_name or `fallbacks:` entry is needed for that, and none should be added.
- **Fallbacks fire on any exception, including 400s.** `run_async_fallback` filters nothing by type or
  status, so a hard `BadRequestError` walks the chain rather than failing the caller. That is what
  makes thinking-mode-vs-forced-tool-choice (below) a graceful degradation instead of an outage.
- **Diagnose rungs from metrics, not guesses.** `litellm_deployment_failure_responses_total`
  (labelled by `exception_status` / `api_base`) plus
  `litellm_deployment_{successful,failed}_fallbacks_total` show exactly which rung answered and why
  the previous one didn't.

## Reasoning-effort and thinking-mode pinning

Per-deployment behaviours are pinned in the model CRs without inline comment; the reasoning lives
here.

**Luna is configured with `max` reasoning effort** via `extra_body: {reasoning: {effort: max}}` on the
`implementation-pool` rung (order 1) and on the direct `chatgpt/gpt-6-luna` alias (2026-09-28). The
nested `extra_body` form is deliberate:

- `extra_body` is merged onto the wire *after* the provider transform, so it survives the `chatgpt/`
  provider's strict allow-list (which permits nested `reasoning` but strips `reasoning_effort`).
- A prior LiteLLM 1.94 test found that a bare `reasoning_effort: "max"` could be dropped by the
  provider mapper. Keep the nested `extra_body` form and re-check the wire request after provider or
  LiteLLM upgrades rather than assuming the requested effort was applied.
- This is a default, not an override: client kwargs are merged last and win. A true hard override
  would need a proxy `async_pre_call_hook`.
- Effort costs subscription quota. The ChatGPT plan meters reasoning work, and Luna leads
  `implementation-pool` at `order: 1`, so it fronts every implementation-pool request (opencode and
  Hermes `implementer`). COMPLEX-classified `auto` traffic is fronted by K2.7, not Luna. Lower it from
  `max` only as an explicit quota/quality tradeoff.

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
