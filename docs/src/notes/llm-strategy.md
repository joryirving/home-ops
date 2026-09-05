# LLM Strategy

How the LLM fleet is subscribed, wired, and used — and where smart-routing is headed.

Everything funnels through **LiteLLM** (`kubernetes/apps/base/llm/litellm/litellmproxy.yaml` and
`kubernetes/apps/base/llm/litellm/models/*.yaml`) at `http://litellm.llm:4000`. Clients address stable
aliases; LiteLLM forwards to the upstream a given subscription or local server expects. This doc is the
reference for keeping those aliases meaningful and for designing intent-based routing on top of them.

**Last reconciled against the cluster: 2026-08-25.** That pass retired Opencode Go and Moonshot,
removed `glm-5.2`, renamed `llama-strix-nemotron` to `llama-reviewer`, moved the local models to
unsloth builds, and added a non-thinking `-chat` door beside each one.

This is a strategy snapshot, not a live quota ledger. Provider pricing, rolling allowances, and
Prometheus counters are perishable; dated observations below are labeled as such.

## Subscriptions

Subscriptions remain the primary capacity. Neuralwatt supplies a dwindling energy-metered PAYG
balance behind `dsv4f`. Moonshot and Opencode Go were both retired on 2026-08-25.

| Plan                | Price                                        | Cap                                                                          | Reset                              | Models                                                                       | Primary use                                                                   |
| ------------------- | -------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **ChatGPT Plus**    | ~$25 CAD/mo                                  | unpublished rolling + weekly quota, with tier-weighted usage                  | rolling (3h chat) + weekly (Codex) | GPT-5.6 Sol, Terra, Luna                                                      | Sol frontier; Luna is the reasoning-pool lead                                 |
| **MiniMax Plus**    | ~$200 USD/yr ($20/mo, annual = 2mo free)     | 300 prompts / 5h                                                             | rolling 5h                         | M3 and M2.7, via the Anthropic endpoint                                      | Agentic reasoning workhorse                                                   |
| **Opencode Go**     | $10 USD/mo                                   | $12 / 5h, $30 / wk, $60 / mo (dollar-denominated)                            | rolling 5h / wk / mo               | DeepSeek V4 Flash/Pro, MiMo v2.5/Pro, Qwen3.8-Max                              | High-volume coding/reasoning lane; current pricing is no longer assumed cheap |
| **GLM Coding Lite** | ~$151 USD/yr (promotional, region-dependent) | ~80 prompts / 5h                                                             | rolling 5h                         | GLM-5.3 on the Z.AI coding endpoint; GLM-5.2 remains a Neuralwatt fallback       | OpenClaw main primary; cache-sensitive long-context lane                       |
| **Kimi Coding**     | ~$180 USD/yr ($15/mo; ~$261 CAD/12mo)        | plan allowance                                                               | plan-defined                       | Kimi K2.7 Code, Kimi K3                                                         | Primary Kimi coding and frontier lanes                                          |
| **Moonshot (Kimi)** | pay-per-use                                  | none (per-key RPM/TPM only)                                                  | n/a                                | kimi-k2.7-code, kimi-k3                                                         | Token-metered fallback behind Kimi Coding                                       |
| **Neuralwatt**      | pay-per-use ($5/kWh energy billing)          | account credit; API-key allowances available                                | n/a                                | GLM-5.2, DeepSeek V4 Flash                                                     | Intentional PAYG fallback and capacity insurance                               |

Caveats worth remembering:

- **MiniMax M3 is covered by the flat plan** (both M3 and M2.7), reached via the direct Anthropic
  endpoint. LiteLLM still logs ~$239/30d "phantom" spend against it — the plan is flat, the metric is
  not, so don't chase that number.
- **ChatGPT** was direct-through-Codex until recently; LiteLLM token history is light, but the
  weekly Codex cap is hit every week. OpenAI does not publish the exact weekly number. Luna now
  consumes 80% fewer subscription credits and Terra 20% fewer; subscription price and quota budget
  are unchanged.
- **GLM Lite's** annual USD price is promotional and not cleanly published.
- All 5h caps are **rolling windows** (oldest usage falls off continuously), not calendar resets.
- Kimi subscription traffic uses equivalent Moonshot list prices for cost comparison: K2.7 Code is
  $0.19 cached input / $0.95 cache miss / $4 output per MTok; K3 is $0.30 / $3 / $15.
- The upstream DSV4F repricing reported in August 2026 changed the economics materially: roughly 8x
  higher uncached input and 40x higher cache-read pricing than the former baseline. Treat the provider
  account and current invoice as authoritative; LiteLLM model metadata can lag provider pricing.
- Cached input is cheaper billing-wise but still consumes upstream subscription/token allocation. A
  high K3 cache-hit ratio does not make a context-heavy diagnostic session quota-free.
- Opencode is LilDrunkenSmurf's ad-hoc interactive coding workload, so its Luna/K3 usage is intentional
  rather than unattended fleet waste. Neuralwatt is an intentional PAYG fallback, not an accidental leak.

## Model inventory

Aliases as defined in the LiteLLM configmap, grouped by where they run.

Each local generative model exposes two aliases against **one** server: the bare name runs the
vendor's thinking recipe, and the `-chat` suffix runs the non-thinking (instruct) one. They share
weights, KV cache and slots, so the second door costs no memory.

### Local (self-hosted, $0 marginal)

| Alias                   | Backend              | Model                                          | Ctx (in) | Role                                  |
| ----------------------- | -------------------- | ---------------------------------------------- | -------- | ------------------------------------- |
| `llama-strix`           | Strix ROCm (2 slots) | Qwen3.6-35B-A3B unsloth UD-Q4_K_XL, native MTP | 262k     | General local brain; vision + tools   |
| `llama-strix-chat`      | same server          | —                                              | 262k     | Non-thinking door; memini scoring     |
| `llama-nvidia`          | 3090 (2 slots)       | Qwen3.8-27B unsloth UD-Q4_K_XL                 | 131k     | Coding lane; vision                   |
| `llama-nvidia-chat`     | same server          | —                                              | 131k     | Non-thinking door                     |
| `llama-reviewer`        | Strix ROCm (2 slots) | Nemotron 3.5 Lightning 30B-A3B UD-Q4_K_XL, MTP | 200k     | Foreman code review                   |
| `llama-reviewer-chat`   | same server          | —                                              | 200k     | Non-thinking door                     |
| `llama-vision`          | Strix ROCm (2 slots) | MiniCPM-V 4.5 abliterated Q4_K_M               | 16k      | Image analysis; will not refuse       |
| `memini-embed`          | Intel iGPU           | Qwen3-Embedding-0.6B                           | —        | Embeddings (1024-dim)                 |
| `memini-rerank`         | Strix ROCm           | Qwen3-Reranker-0.6B                            | —        | Reranking                             |
| `toolhive-embed`        | Intel iGPU           | Qwen3-Embedding-0.6B                           | —        | Embeddings for toolhive vMCP          |

`llama-strix-dsv4f` (DeepSeek-V4-Flash UD-IQ2_M) and `llama-strix-fp8` exist in git but are commented
out of the kustomization — they need most of the box to themselves.

### Cloud (flat-rate subscriptions)

| Alias                   | Subscription    | Upstream model                  | Ctx (in) | Role                                          |
| ----------------------- | --------------- | ------------------------------- | -------- | --------------------------------------------- |
| `MiniMax-M3`            | MiniMax Plus    | MiniMax-M3 (Anthropic endpoint) | 1M       | Big-context generation                        |
| `MiniMax-M3-chat`       | MiniMax Plus    | MiniMax-M3 (OpenAI endpoint)    | 1M       | Terminal fallback sink for the local models    |
| `MiniMax-M2.7`          | MiniMax Plus    | MiniMax-M2.7                    | 204.8k   | Agentic reasoning workhorse                   |
| `glm-5.3`               | GLM Coding Lite | glm-5.3 (Z.AI)                  | 1M       | OpenClaw main primary                         |
| `chatgpt/gpt-6-astra`   | ChatGPT Plus    | gpt-6-astra (Codex/OAuth)       | 272k*    | Frontier-pool lead                            |
| `chatgpt/gpt-5.6-sol`   | ChatGPT Plus    | gpt-5.6-sol (Codex/OAuth)       | 1.1M     | Previous flagship, direct-call only           |
| `chatgpt/gpt-5.6-terra` | ChatGPT Plus    | gpt-5.6-terra (Codex/OAuth)     | 1.05M    | Balanced, explicit-only OpenAI tier           |
| `chatgpt/gpt-5.6-luna`  | ChatGPT Plus    | gpt-5.6-luna (Codex/OAuth)      | 1.05M    | Reasoning-pool lead                           |
| `kimi-k2.7`             | Kimi Coding     | kimi-for-coding                 | 262k     | Coding subscription                           |
| `kimi-k3`               | Kimi Coding     | k3                              | 1M       | Frontier Kimi lane                            |

\* `gpt-6-astra`'s real window is 1.05M, but a prompt past 272k reprices the *entire* request at
2x input/cache and 1.5x output, so it is declared at the cheap ceiling. Raise it deliberately if a
long-context call is ever worth the multiplier.

**Moonshot is gone** (2026-08-25). Its credits were deliberately drained rather than topped up, so
`kimi-k2.7` and `kimi-k3` are now single-rung on the Kimi Coding subscription with no PAYG rung
beneath. Kimi Coding signals cap-out with a 403, which LiteLLM retries but never cools down, so both
groups have an explicit router fallback to `MiniMax-M3-chat`.

### Neuralwatt (energy-metered PAYG)

| Alias   | Upstream model    | Ctx | Role                                              |
| ------- | ----------------- | --- | ------------------------------------------------- |
| `dsv4f` | deepseek-v4-flash | 1M  | Sole surviving DeepSeek lane; frontier-pool floor |

Neuralwatt charges for measured GPU energy rather than tokens. PAYG is $5/kWh; prefix-cache hits
avoid prefill work and therefore reduce the charged energy. Use Neuralwatt's usage API/dashboard for
authoritative cost; LiteLLM and Prometheus are routing/volume telemetry, not the billing authority.

**This is a runway, not a subscription.** As of 2026-08-25 the balance is ~$9.52 against a trailing
burn of ~$3.17/day, so `dsv4f` has days rather than months. When it zeroes, `dsv4f` and
`frontier-pool` rung 4 both go with it. `glm-5.2` and `neuralwatt/glm-5.2` were removed on 2026-08-25
— neither had a single consumer.

### Cloud (Opencode Go gateway) — retired

Retired 2026-08-25 when the plan capped out, ahead of its 08-28 lapse. It had supplied `dsv4f`
(Go rung), `dsv4p`, `mimo-v2.5`, `mimo-v2.5-pro`, `qwen3.8-max`, `go-gpt-5.6-luna` and a
`reasoning-pool` rung. `dsv4f` survives on Neuralwatt; the rest were deleted along with the
`OPENCODE_API_KEY` wiring.

### Ordered pools

| Pool | Order | Members | Policy |
| ---- | ----- | ------- | ------ |
| `reasoning-pool` | 1 -> 3 | GPT-5.6 Luna -> GLM-5.3-Flash (Z.AI) -> MiniMax-M3 | Strong reasoning lane; M3 is the flat-plan floor |
| `frontier-pool` | 1 -> 4 | GPT-6 Astra -> Kimi K3 (Kimi Coding) -> GLM-5.3 (Z.AI) -> DSV4F (Neuralwatt) | Frontier escalation, subscriptions before PAYG |

**Provider failover** (LiteLLM `order:`, transparent to callers) reacts when an upstream rejects a
request; it cannot detect that an unpublished rolling allowance is merely _close_ to exhausted.

`glm-5.3-flash` sits between Luna and the M3 floor. It is a reasoning model in its own right
(it takes `reasoning_effort`, pinned to `high` on this rung to match Luna) and a stronger rung than
dropping straight to M3, but it spends GLM Coding Lite quota — the same subscription behind
`frontier-pool` rung 3 — so sustained reasoning overflow can leave frontier escalation a rung
shorter. M3 remains the floor precisely because the flat plan cannot be exhausted this way.

Kimi-for-Coding was removed from `reasoning-pool`: its 262k context made it the pool's conservative
ceiling even though Kimi K3 is a 1M model standalone. It remains available via the Kimi aliases and
`frontier-pool`.

## Model capability ranking

Benchmark snapshot as of **2026-08-23** — perishable. Numbers remain largely **vendor
self-reported on non-overlapping harnesses** (SWE-bench Pro ≠ Verified; Terminal-Bench
2.0 ≠ 2.1 ≠ 3.0; vendor SWE-Pro runs 15–30pts above standardized scaffolding), so treat deltas as
**directional**, not precise, and re-pull when models bump. `n/p` = not published. Do not read this
table as a statement about pricing, cache behaviour, or quota consumption.

Rows for `dsv4p`, `glm-5.2`, `mimo-v2.5` and `mimo-v2.5-pro` are kept for reference only — those
aliases were retired on 2026-08-25 and are no longer served. The Mellum2 row is likewise
historical: `llama-reviewer` now serves Nemotron 3.5 Lightning 30B-A3B.

Rows are ordered by **AA-II**, the [Artificial Analysis Intelligence Index](https://artificialanalysis.ai/leaderboards/models)
(v4.1.1) — the only axis in this table measured on one harness across every model here, and therefore
the only column where a cross-row comparison is defensible on its own. Every other column mixes
harnesses. Cells marked ⁱ are **independently run**; everything else is vendor-reported.

| Model               | Alias                   | Arch (total/active) | Ctx   | AA-II | SWE-V | SWE-Pro | LiveCodeB | Term-B 2.1 | GPQA  | AIME  |
| ------------------- | ----------------------- | ------------------- | ----- | ----- | ----- | ------- | --------- | ---------- | ----- | ----- |
| GPT-5.6 Sol         | `chatgpt/gpt-5.6-sol`   | proprietary         | 1.05M | 61ⁱ   | 96.2ⁱ | 64.6    | n/p       | 89.5ⁱ ²    | 94.1ⁱ | n/p   |
| GLM-5.3             | `glm-5.3`               | MoE ~753B/40A ³     | 1M    | 60ⁱ   | n/p   | n/p ³   | n/p       | 88.2 ⁴     | n/p   | n/p   |
| Qwen3.8-Max         | `qwen3.8-max`           | MoE 2.4T/95A        | 1M    | 58ⁱ   | n/p   | 67.7    | n/p       | 86.6 ⁵     | 92.6  | n/p   |
| Kimi K3             | `kimi-k3`               | MoE 2.8T/104A ⁶     | 1M    | 57ⁱ   | 93.4ⁱ | n/p     | 87.2ⁱ     | 80.9ⁱ ⁶    | 93.5  | n/p   |
| GPT-5.6 Terra       | `chatgpt/gpt-5.6-terra` | proprietary         | 1.05M | 55ⁱ   | n/p   | 63.4    | n/p       | 73.4ⁱ ²    | n/p ² | n/p   |
| DeepSeek-V4-Pro     | `dsv4p`                 | MoE 1.6T/49A        | 1M    | 53ⁱ   | 96.4ⁱ | n/p ⁷   | n/p ⁷     | 87.9       | n/p ⁷ | n/p   |
| GLM-5.2             | `glm-5.2`               | MoE ~753B/40A       | 1M    | 53ⁱ   | n/p   | 62.1    | n/p       | 78ⁱ ⁴      | 89ⁱ   | 99.2  |
| DeepSeek-V4-Flash   | `dsv4f`                 | MoE 284B/13A        | 1M    | 52ⁱ   | n/p ⁷ | n/p ⁷   | n/p ⁷     | 79ⁱ ⁷      | 91ⁱ   | n/p   |
| Qwen3.8-27B dense   | `llama-nvidia`                | dense 27.8B         | 145k⁸ | 52ⁱ   | n/p ⁸ | 61.7    | 90.3      | 73.0       | 89.2  | n/p   |
| GPT-5.6 Luna        | `chatgpt/gpt-5.6-luna`  | proprietary         | 1.05M | 51ⁱ   | n/p   | 62.7    | n/p       | 84.7       | n/p ² | n/p   |
| MiniMax-M3          | `MiniMax`               | MoE ~428B/23A ¹     | 1M    | 45ⁱ   | 80.5  | 59.0    | n/p       | 66.0       | 93ⁱ   | n/p   |
| MiMo-V2.5-Pro       | `mimo-v2.5-pro`         | MoE 1.02T/42A       | 1M    | 43ⁱ   | 78.9  | 57.2    | n/p ⁹     | n/p ⁹      | n/p ⁹ | n/p ⁹ |
| MiniMax-M2.7        | `MiniMax-M2.7`          | MoE ~230B/10A       | 205k  | 39ⁱ   | n/p   | 56.2    | n/p       | n/p ⁹      | 89.8  | 94.2  |
| MiMo-V2.5           | `mimo-v2.5`             | MoE 310B/15A        | 1M    | 38ⁱ   | n/p   | 56.1    | n/p       | n/p ⁹      | n/p   | n/p   |
| Qwen3.6-35B-A3B     | `llama-strix`           | MoE 35B/3A          | 262k  | 32ⁱ   | 73.4  | 49.5    | 80.4      | n/p ⁹      | 86.0  | 92.7  |
| Mellum2-12B-A2.5B   | — (retired)                   | MoE 12B/2.5A        | 131k  | n/p   | n/p   | n/p     | 37.2      | n/p        | 40.9  | 41.7  |

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

⁸ `llama-nvidia` has run **Qwen3.8-27B** since 2026-08-14, not the Qwen3.6-27B the previous snapshot listed —
that row was wrong on the model name irrespective of benchmarks. Qwen publishes no SWE-bench Verified
for it (the nearest vendor substitute, QwenSWEBench 79.0, is Qwen's own harness) and no AIME, so the
generational SWE-V and AIME comparisons against Qwen3.6-27B cannot be made. Terminal-Bench also
switched versions between generations: 3.6-27B's 59.3 was 2.0, 3.8-27B's 73.0 is 2.1, so the +13.7
arithmetic is cross-version and wrong — the vendor states the real delta as **+9.6 on 2.1**. Native
context is 262k, pinned to 140k on the 24GB 3090. There is no Qwen3.8-35B-A3B.

⁹ Terminal-Bench 2.0-only rows, shown as `n/p` in the 2.1 column to keep it comparable: MiniMax-M2.7
**57.0**, MiMo-V2.5 **65.8**, MiMo-V2.5-Pro **68.4**, Qwen3.6-35B-A3B **51.5**. Separately, the
MiMo-Pro LiveCodeBench 39.6 / GPQA 66.7 / AIME 37.3 the previous snapshot carried are
**base-model few-shot pretraining evals** (1-shot LCB v6, 5-shot GPQA, 2-shot AIME 24&25) that an
automated HF metadata PR flattened into the card alongside post-trained numbers. They are not
comparable to any other row here and have been removed rather than corrected — Xiaomi publishes no
post-trained equivalents.

`llama-strix` runs the stock unsloth Qwen3.6-35B-A3B (UD-Q4_K_XL, native MTP) with its
mmproj loaded. The abliterated HauhauCS build it previously ran — and Ornith-1.0-35B before
that, a post-tune of the *same* Qwen3.6-35B-A3B — were dropped in the 2026-08-25 move to
unsloth builds, so the box keeps the architecture without a post-tune. Uncensored image
analysis now lives on `llama-vision` (abliterated MiniCPM-V 4.5); the Mac LM Studio member
is gone, so there is no second `llama-strix` upstream to reason about.

`llama-reviewer` publishes more than the previous snapshot credited it with — the
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
- **Frontier tier** (`gpt-5.6-sol`, `kimi-k3`, `glm-5.3`) — unchanged, and now better evidenced. Sol
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
    `dsv4f` as the third reasoning-pool rung, which would need repointing at local or MiniMax.
- **DeepSeek V4 Flash is still genuinely strong and the refresh made it stronger** — AA lifted it 40 →
  52 on the 0731 build, its independently-measured GPQA is 91, and repo-bench previously re-scored it
  0.895 → 0.957 while V4 Pro stayed at 0.864. The argument for dropping it is that the capability is
  now duplicated locally and by flat-rate plans, not that the model is weak.
- **Reasoning tier** (`gpt-5.6-luna`, `MiniMax-M3`) — note Luna is the weakest GPT tier here
  at AA-II 51 and its long-context recall collapses (vendor MRCR 41.3 against Sol's 91.5), so the pool's
  nominal 1M context is not usable depth on that rung. Luna is pinned to `xhigh` reasoning effort.
- **Local** — `llama-nvidia` is now Qwen3.8-27B and the gap to `llama-strix` widened from "trails it
  everywhere" to a 20-point AA-II spread (52 vs 32). `llama-strix` earns its place on the 262k window
  and vision, nothing else. The local box is now competitive with paid cheap-tier cloud, which is the
  single most decision-relevant change in this refresh.
- **`llama-reviewer` is a deliberate family split, not a quality pick.** Foreman's coder runs
  Qwen (`llama-nvidia`), so a Qwen reviewer inherits the coder's blind spots — it was Qwen
  reviewing Qwen while `llama-strix` served review, since Ornith was itself a
  Qwen3.6-35B-A3B post-tune. The lane went to JetBrains' Mellum2 first and now runs
  NVIDIA's Nemotron 3.5 Lightning 30B-A3B — still a non-Qwen family, ~3B active, free.
  It exists to disagree with the coder, so published coding scores
  matter less here than independence and structured-output reliability.
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

Four suites from `repo-bench` v2, scored on this repo's own material. Error rows (transport
failures) are dropped rather than counted as zeros — the `tally` subcommand does this.

| Candidate | Troubleshooting | Reviewing | Agentic | Coding | Mean |
| --------- | --------------- | --------- | ------- | ------ | ---- |
| `llama-nvidia` 27B Q4 (3090) | 0.981 | 0.923 | 0.718 | 0.710 | 0.833 |
| Qwen3.8-27B FP8 (Strix) | 0.938 | 0.920 | 0.782 | 0.760 | 0.850 |
| Flash-Next UD-Q3_K_XL (Strix) | 0.978* | 0.792 | 0.833 | 0.760 | 0.841 |
| Flash-Next NVFP4 + FP8 engram (borrowed RTX 6000 Pro) | 0.991 | 0.838 | 0.788 | 0.620 | 0.809 |
| Nemotron 3.5 30B-A3B (Strix) | 0.910 | 0.817 | 0.756 | 0.080 | 0.641 |
| `MiniMax-M3` | 0.956 | 0.759 | 0.558 | 0.590 | 0.716 |
| `MiniMax-M2.7` | 0.956 | 0.842 | 0.481 | 0.500 | 0.695 |
| `chatgpt/gpt-5.6-luna` (effort=medium) | 0.926 | 0.758 | 0.744 | 0.620 | 0.762 |

\* n=15; three tasks died on the qwen4exp indexer assert and were dropped.

**Run-to-run noise is ±0.02**, measured from the duplicate `nvidia`/`llama-nvidia` pair (same model,
different dates: deltas 0.016 / 0.003 / 0.019 / 0.020). So the top three rows are a tie, and a 180B
at Q3 does not beat a 27B on this bench.

Reviewing is Flash-Next's worst suite and both 27Bs' best; agentic is the reverse. Nemotron's coding
score is broken, which is fine for a review-only lane and disqualifying for a coder.

Caveat on luna: it ran at `effort=medium`, and every real consumer reaches it through
`reasoning-pool` which pins `effort: max`. That row is not evidence about the deployed path.

Methodology trap: candidate names are not stable across time. `llama-strix` meant Ornith in August
and Flash-Next later, and `tally` merges by candidate name — check what the alias pointed at before
comparing rows.

## Where a model runs is decided by memory bandwidth

Strix Halo has ~256 GB/s theoretical and ~200-220 GB/s real. Decode is bandwidth-bound, so what
matters is **active** parameters per token, not total parameters:

| Model | Arch | Weights | Read/token | Measured TG |
| ----- | ---- | ------- | ---------- | ----------- |
| Qwen3.6-35B-A3B Q4 | MoE, 3B active | 21.3 GiB | ~1.7 GiB | 34-42 t/s |
| Nemotron 3.5 30B-A3B Q4 | MoE, 3B active | 23.8 GiB | ~1.7 GiB | ~35 t/s |
| Qwen3.8-27B ROCmFP8 | dense 27B | 26.3 GiB | 26.3 GiB | ~8-10 t/s |
| Qwen3.8-Flash-Next UD-Q3_K_XL | MoE 180B-A6B | 101.3 GiB | ~4 GiB + engram | 11 t/s |

So **Strix runs A3B-class MoE and small dense vision models; the 3090 runs the dense 27B**, where
900+ GB/s of VRAM gives it 44 t/s on weights that would crawl on the APU. A dense model on Strix is
slow no matter how good it scores, and Flash-Next is slow *and* needs 101 GiB — it evicts the whole
rest of the resident set to hold a tie on quality (see the v2 bench section).

Measured footprint of the resident set, mid-generate, 2026-08-27: GTT **76.8 GiB of 124**, ~47 GiB
free, with ComfyUI actually taking **6.8 GiB** rather than the 14 GiB its `--reserve-vram 110`
permits. Wall power: skirk **48.7 W** serving three models plus an image generation; the 3090
**142 W idle**, ~299 W under load.

## Consumers

| Consumer               | In repo?                                    | Points at                                                                                    |
| ---------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **OpenClaw**           | yes (`.../llm/openclaw/app/configmap.yaml`) | Miso/main `glm-5.3-flash`; Matcha `dsv4f`; Saffron `reasoning-pool`; subagents `MiniMax-M3`; heartbeat `llama-nvidia`; image `llama-vision`; lossless-claw expansion/summary `llama-strix-chat` |
| **Hermes**             | yes (`.../llm/hermes/configmap.yaml`)       | default `MiniMax-M3`; compression/extract/approval/session-search `llama-strix`; vision `llama-vision` |
| **Foreman**            | yes (`.../llm/foreman/agents/*.yaml`)       | `coder` → `llama-nvidia`; `coder-revision` + `coder-frontier` → `MiniMax-M3-chat`; `reviewer` + `reviewer-fork` → `llama-reviewer` |
| **Opencode** (CLI/Zen) | yes (`.../llm/opencode/configmap.yaml`)     | default `auto`; coordinator `reasoning-pool`; role subagents `MiniMax-M3`/`llama-nvidia`/`llama-strix`/`glm-5.3`/`llama-reviewer`, plus the workstation CLI on LiteLLM aliases directly |
| **Zed**                | no (workstation)                            | LiteLLM aliases directly                                                                     |

### OpenClaw cron fleet

Two agents (Miso, Saffron) run 16 scheduled jobs, plus two issue-worker pipelines. The model choice
per job already encodes an intent-lane pattern by hand.

| Job                             | Agent   | Model        | Schedule        | Purpose                                        |
| ------------------------------- | ------- | ------------ | --------------- | ---------------------------------------------- |
| Afternoon Email/Finance Check   | Miso    | MiniMax-M2.7 | 4pm daily       | Email + financial anomaly scan                 |
| Instagram Hourly Image Dispatch | Miso    | llama-strix  | 9am–8pm Mon–Thu | Publish one approved staged IG post per window |
| Image Category Creation         | Miso    | MiniMax      | every 6h        | Generate new image category + gallery          |
| Evening Email/Finance Check     | Miso    | MiniMax-M2.7 | 9pm daily       | End-of-day email + finance summary             |
| Nightly Audit Decomposer        | Saffron | llama-strix  | 2am daily       | Decompose audit umbrellas into child issues    |
| Nightly Tech Sweep              | Saffron | MiniMax-M3-chat    | 6:20am daily    | Overnight health check + low-risk fixes        |
| Unified Morning Brief           | Miso    | MiniMax-M2.7 | 7:30am daily    | Weather, calendar, inbox, IG pool, news, radon |
| Daily LLM + HN Digest           | Miso    | llama-strix  | 8:30am daily    | r/LocalLLaMA etc. + HN top stories             |
| Daily Home-Ops Updates          | Saffron | MiniMax-M2.7 | 9am daily       | Commit watch on homelab k8s repos              |
| Daily Image (Miso)              | Miso    | llama-strix  | 9:15am daily    | Character image generation                     |
| Alertmanager Health Digest      | Saffron | MiniMax-M3-chat    | 9:30am daily    | Firing Prometheus alerts + investigation       |
| Solar Daily Check               | Miso    | MiniMax-M2.7 | 9:35am daily    | Solar generation + weather + guess tracking    |
| Daily Image (Saffron)           | Saffron | llama-strix  | 10:15am daily   | Character image generation                     |
| Weekly IG Posting Times         | Miso    | MiniMax-M3-chat    | 11am Fri        | Research optimal IG posting times              |
| Weekly Audit                    | Saffron | MiniMax-M2.7 | 1am Wed         | Spawn per-repo audit sub-agents                |
| Weekly Prompt Hygiene           | Saffron | MiniMax-M3-chat    | 10:45am Wed     | Audit prompt files for bloat/contradictions    |

Issue-worker pipelines (pick up issues and open PRs):

- **MC Normal** → `llama-strix`
- **MC Escalated** → `gpt-5.6-sol`

## Current routing + observed usage

Routing today is `simple-shuffle` with hand-written availability fallbacks
(`kubernetes/apps/base/llm/litellm/litellmproxy.yaml`). `simple-shuffle` spreads a synchronized fan-out
evenly across a group's deployments; `least-busy` increments its in-flight
counter _after_ the routing decision, so a burst reads equal counts and piles
onto the first deployment — wrong for the 2-instance `llama-strix` group.

```yaml
routing_strategy: simple-shuffle
fallbacks:
    - llama-strix: [llama-nvidia, MiniMax-M3-chat]
    - llama-nvidia: [llama-strix, MiniMax-M3-chat]
    - dsv4f: [llama-nvidia]
    - kimi-k2.7: [MiniMax-M3-chat]
    - kimi-k3: [MiniMax-M3-chat]
    - auto: [dsv4f, MiniMax-M3-chat]
context_window_fallbacks:
    - llama-nvidia: [llama-strix]
    - llama-strix: [dsv4f]
```

Observed 7-day traffic (Prometheus, 2026-08-23; `litellm_total_tokens_metric_total`, cached input
included; all consumers combined):

| Model                       | Reported tokens (7d) |
| --------------------------- | -------------------: |
| gpt-5.6-luna                |               329.0M |
| MiniMax-M3                  |               313.6M |
| llama-nvidia                |               219.8M |
| deepseek-v4-flash (`dsv4f`) |               203.7M |
| glm-5.3                     |                74.5M |
| llama-reviewer              |                45.0M |
| MiniMax-M3-chat                   |                22.8M |
| MiniMax-M2.7                |                13.7M |
| k3                          |                 7.4M |

These are volume counters, not provider invoices. Kimi subscription traffic is valued at equivalent
Moonshot API rates in LiteLLM even though the plan itself is flat-rate. Cached input still counts against
upstream allocations.

### Cache accounting

There are two different caches in this stack:

- LiteLLM's Redis response cache is enabled with a 300-second TTL. This is exact-request reuse at the
  proxy layer and is separate from provider prefix caching.
- OpenClaw requests set `cache_prompt: true` for GLM, K3, DSV4F, and the local model aliases. Providers
  may report prefix-cache reads in response usage, but they do not all expose that usage consistently.

GLM-5.3 is the important example. Prometheus showed zero `litellm_input_cached_tokens_metric_total`
for GLM, but a direct probe through LiteLLM on 2026-08-23 returned approximately 60k-145k cached
prefix tokens on repeated direct requests. Streaming usage chunks omitted or under-reported
`cached_tokens`. The zero Prometheus value is therefore not proof that Z.AI caching is disabled. Use
Z.AI's billing/usage dashboard to verify discounted billing for streamed requests; do not route main
away from GLM based on that counter alone.

### Context economics and guardrails

OpenClaw main intentionally stays on GLM-5.3. Saffron uses the 1M `reasoning-pool`; subagents use
MiniMax-M3 and heartbeats use the local NVIDIA model. This preserves the quality lanes instead of routing
main away from GLM merely because one provider's streaming usage telemetry is incomplete.

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

`max_parallel_requests` per LiteLLM member must match the backend's real `parallelSlots`,
because the two failure modes are asymmetric:

- **Cap above the backend** and requests queue *inside* llama.cpp, invisible to the router.
  `llama-nvidia` sat at 2 against a single slot; the queueing surfaced as a 53 s average
  time-to-first-token on the `llama-nvidia` alias while the model itself was fine (fixed 2026-08).
- **Cap below the backend** and provisioned VRAM goes unused. `llama-reviewer` served 3
  slots while LiteLLM dispatched into 2 — a third of the model unreachable (fixed 2026-08).

Current: Strix 2, reviewer 2, nvidia 1. The Strix box is memory-bandwidth bound, so
aggregate tok/s improves with concurrent streams spread **across** resident models rather
than piled onto one — the useful range is roughly 6-8 streams for the whole box, not per
model. The Mac LM Studio member was removed; `llama-strix` is now the single cluster server.

Foreman's demand cannot currently be bounded per-Agent
([LLMKube#1497](https://github.com/defilantech/LLMKube/issues/1497)), so the only levers on
its share of `llama-strix` are the bridge's `MAX_IN_PROGRESS` and the `LANE_CODER_AGENTS`
split ratio — both blunt. Measured `llama-strix` utilisation across *all* consumers
(Foreman, home-ops PR reviews, groomer, repo-wiki) is ~15 busy-hours/day against 96
slot-hours, so headroom is real and the risk is bursts, not steady state.

## Smart-routing: the `auto` alias

An opt-in `auto` alias routes for **opencode, Zed and pi only**; every other consumer (crons, MC
workers, Hermes roles, MiniMax) stays pinned. It uses LiteLLM's **LLM classifier**
(`classifier_type: llm`), not the rule-based complexity scorer — see the measurements below.

Tiers (three effective tiers; REASONING is folded into COMPLEX):

| Tier               | Target                              | Why                                          |
| ------------------ | ----------------------------------- | -------------------------------------------- |
| SIMPLE             | `llama-nvidia` (3090 Qwen3.8-27B)   | Trivia — local, free                         |
| MEDIUM             | `MiniMax-M3`                        | Flat sub, no weekly quota to burn            |
| COMPLEX            | `reasoning-pool`                    | Luna -> GLM-5.3-Flash -> MiniMax-M3          |
| REASONING          | `reasoning-pool`                    | Folded — no classifier could separate it     |
| default (miss)     | `MiniMax-M3`                        | `classifier_fallback: default_model`         |

Classifier is `llama-strix` (`classifier_llm_config`, 20s timeout) — local and free to sit in
every request's path. It replaced the reviewer-alias classifier on 2026-08-22.

`frontier-pool` is deliberately **not** a tier target: `auto` must not compete with interactive
sessions for the weekly ChatGPT/Kimi caps. COMPLEX reaches Luna, GLM-5.3-Flash and MiniMax-M3 through
`reasoning-pool`;
Kimi K3 remains in `frontier-pool` or explicit selection rather than being a reasoning-pool rung.

### Measured (2026-08-07, LiteLLM 1.95.0)

Two 20-prompt corpora, one held out. Scored against a throwaway proxy running the real router
against real backends.

| Config                                     | Tier accuracy      |
| ------------------------------------------ | ------------------ |
| Rule-based scorer, boundaries `.45/.65/.85` | **5/20 (25%)**     |
| Rule-based scorer, boundaries `.15/.35/.60` | 7/20 (35%)         |
| LLM classifier (`llama-reviewer`), held out       | 17/20 (85%) 3-tier |
| LLM classifier, end-to-end on real pools    | **16/20 (80%)**    |

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
- Local context ceilings (140k/262k) are guarded by `context_window_fallbacks` +
  `enable_pre_call_checks`, not by any router setting.
- `reasoning-pool`'s M3 rung uses MiniMax's OpenAI-compatible `/v1` endpoint, so it may expose
  thinking in content; acceptable for this lane. OpenClaw's native `MiniMax-M3` alias uses the
  Anthropic `/messages` endpoint and its think-tag stripping shim.

Excluded from `auto` by design: the manual Sol/Terra aliases. The native `MiniMax-M3` messages
alias is now the MEDIUM tier and the classifier-miss default.
A **semantic router** (`auto-semantic` + `router.json`) is scaffolded but commented out: `from_json`
builds an encoder at startup (crashloop risk on the live gateway), so it's verify-then-enable later.

Still ahead:

- Swap MEDIUM to `llama-nvidia` once Foreman's backlog drains — it's the better model and free, but was
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
a strict `order:` chain (429/403 -> cooldown -> next). Subscriptions first, then their PAYG counterparts:

1. `gpt-6-astra` — flagship frontier (ChatGPT Plus sub), capped at 272k (see below)
2. `kimi-k3` @ Kimi Coding — dedicated Kimi sub (flat)
4. `glm-5.3` @ Z.AI — GLM Coding Lite sub
5. `dsv4f` @ Neuralwatt — PAYG DeepSeek fallback

`gpt-5.6-sol` is no longer a rung. It draws the same ChatGPT rolling window as Astra, so pairing the
two would have given a second rung with no headroom of its own; it stays reachable as a direct model.
The pool's declared window follows rung 1 at 272k rather than the 1M of the rungs below it.

Implemented as one **self-contained `order:` group**, not router fallbacks referencing the shared
groups. It intentionally has no MiniMax floor: a frontier request fails rather than silently degrading
to the reasoning lane.

Caveats:

- **Know which model answered.** Failover is silent — read the `x-litellm-model-id` response header (or
  the LiteLLM logs) to see whether you're on Astra, K3, or GLM.
- **No silent quality downgrade.** Once both K3 and GLM capacity paths reject a request, the frontier
  request fails. Use `reasoning-pool` when MiniMax M3 is an acceptable final fallback.
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

Two per-deployment behaviours are pinned in the configmap without inline comment; the reasoning lives
here.

**Luna is configured with `max` reasoning effort** via `extra_body: {reasoning: {effort: max}}` on the
`reasoning-pool` rung. The nested `extra_body` form is deliberate:

- `extra_body` is merged onto the wire *after* the provider transform, so it survives the `chatgpt/`
  provider's strict allow-list (which permits nested `reasoning` but strips `reasoning_effort`).
- A prior LiteLLM 1.94 test found that a bare `reasoning_effort: "max"` could be dropped by the
  provider mapper. Keep the nested `extra_body` form and re-check the wire request after provider or
  LiteLLM upgrades rather than assuming the requested effort was applied.
- This is a default, not an override: client kwargs are merged last and win. A true hard override
  would need a proxy `async_pre_call_hook`.
- Effort costs subscription quota. The ChatGPT plan meters reasoning work, and Luna leads the tier at
  `order: 1`, so it fronts every COMPLEX-classified request. Lower it from `max` only as an explicit
  quota/quality tradeoff.

**DeepSeek V4 Flash runs with thinking default-on.** The `thinking: {type: disabled}` workaround for
[litellm#26395](https://github.com/BerriAI/litellm/issues/26395) was removed after retesting the live
OpenCode Go endpoint (2026-08-04):

- Multi-turn and full agentic tool round-trips now succeed with `reasoning_content` stripped — the
  failure the workaround existed for is fixed server-side. LiteLLM's own
  `DeepSeekChatConfig._fill_reasoning_content()` fix is irrelevant here either way: it is bound to
  `custom_llm_provider="deepseek"` and never runs on an `openai/`-via-OpenCode rung.
- The one surviving constraint is **forced** tool choice: `tool_choice: "required"` or a named
  function returns `400 "Thinking mode does not support this tool_choice"`. `tool_choice: "auto"` is
  fine, and forced calls fall through to the `dsv4f` → `llama-nvidia` router fallback rather than failing.
- Watch `litellm_deployment_successful_fallbacks_total{requested_model="dsv4f",fallback_model="llama-nvidia"}`.
  If it climbs, a consumer is forcing a tool and `extra_body: {thinking: {type: disabled}}` should be
  restored on that deployment. The likeliest source is the `llama-strix` → `dsv4f` context-window
  fallback, which arrives carrying whatever `tool_choice` the original caller set.
- `dsv4p` was retired with the Opencode Go plan on 2026-08-25; the note is kept for history.
