# LLM Strategy

How the LLM fleet is subscribed, wired, and used — and where smart-routing is headed.

Everything funnels through **LiteLLM** (`kubernetes/apps/base/llm/litellm/litellmproxy.yaml` and
`kubernetes/apps/base/llm/litellm/models/*.yaml`) at `http://litellm.llm:4000`. Clients address stable
aliases; LiteLLM forwards to the upstream a given subscription or local server expects. This doc is the
reference for keeping those aliases meaningful and for designing intent-based routing on top of them.

This is a strategy snapshot, not a live quota ledger. Provider pricing, rolling allowances, and
Prometheus counters are perishable; dated observations below are labeled as such.

## Subscriptions

Subscriptions remain the primary capacity. Neuralwatt supplies energy-metered GLM capacity, while
Moonshot is the token-metered failover behind the Kimi Coding subscription.

| Plan                | Price                                        | Cap                                                                          | Reset                              | Models                                                                       | Primary use                                                                   |
| ------------------- | -------------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **ChatGPT Plus**    | ~$25 CAD/mo                                  | unpublished rolling + weekly quota, with tier-weighted usage                  | rolling (3h chat) + weekly (Codex) | GPT-5.6 Sol, Terra, Luna                                                      | Sol frontier; Luna is the reasoning-pool lead                                 |
| **MiniMax Plus**    | ~$200 USD/yr ($20/mo, annual = 2mo free)     | 300 prompts / 5h                                                             | rolling 5h                         | M3 and M2.7, via the Anthropic endpoint                                      | Agentic reasoning workhorse                                                   |
| **Opencode Go**     | $10 USD/mo                                   | $12 / 5h, $30 / wk, $60 / mo (dollar-denominated)                            | rolling 5h / wk / mo               | DeepSeek V4 Flash/Pro, MiMo v2.5/Pro, Qwen3.7-plus                              | High-volume coding/reasoning lane; current pricing is no longer assumed cheap |
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

### Local (self-hosted, $0 marginal)

| Alias                  | Backend                                  | Model                | Ctx (in) | Role                                |
| ---------------------- | ---------------------------------------- | -------------------- | -------- | ----------------------------------- |
| `self-hosted`          | Strix ROCm (2 slots) + Mac LM Studio (2 slots) | Qwen3.6-35B-A3B ⁶    | 262k     | Default local brain; vision + tools |
| `reviewer`             | Strix ROCm (3 slots)                     | Mellum2-12B-A2.5B    | 131k     | Foreman code review only            |
| `nvidia`               | 3090 (1 slot)                            | Qwen (CUDA)          | 145k     | General local, no vision            |
| `memini-embed`         | llama.cpp                                | Qwen3-Embedding-0.6B | —        | Embeddings (1024-dim); iGPU tenant  |
| `memini-rerank`        | llama.cpp                                | Qwen3-Reranker-0.6B  | —        | Reranking (infinity); iGPU tenant   |
| `toolhive-embed`       | llama.cpp                                | Qwen3-Embedding-0.6B | —        | Embeddings for toolhive vMCP; iGPU  |

### Cloud (flat-rate subscriptions)

| Alias                  | Subscription                  | Upstream model                  | Ctx (in) | Role                                               |
| ---------------------- | ----------------------------- | ------------------------------- | -------- | -------------------------------------------------- |
| `MiniMax`              | MiniMax Plus                  | MiniMax-M3 (Anthropic endpoint) | 1M       | Big-context generation                             |
| `MiniMax-M2.7`         | MiniMax Plus                  | MiniMax-M2.7                    | 204.8k   | Agentic reasoning workhorse                        |
| `glm-5.3`              | GLM Coding Lite              | glm-5.3 (Z.AI)                  | 1M       | OpenClaw main primary; upstream prompt-cache lane |
| `chatgpt/gpt-5.6-sol`   | ChatGPT Plus                  | gpt-5.6-sol (Codex/OAuth)       | 1.1M     | Flagship frontier                                  |
| `chatgpt/gpt-5.6-terra` | ChatGPT Plus                  | gpt-5.6-terra (Codex/OAuth)     | 1.05M    | Balanced, explicit-only OpenAI tier                |
| `chatgpt/gpt-5.6-luna`  | ChatGPT Plus                  | gpt-5.6-luna (Codex/OAuth)      | 1.05M    | Reasoning-pool lead; high-volume OpenAI tier       |
| `kimi-k2.7`            | Kimi Coding → Moonshot        | kimi-for-coding / kimi-k2.7-code | 262k    | Coding subscription first, token PAYG fallback     |
| `kimi-k3`              | Kimi Coding → Moonshot        | k3 / kimi-k3                    | 1M      | Frontier Kimi lane; subscription first             |

### Neuralwatt (energy-metered PAYG)

| Alias                    | Upstream model     | Ctx | Role                                          |
| ------------------------ | ------------------ | --- | --------------------------------------------- |
| `neuralwatt/glm-5.2`     | glm-5.2            | 1M  | Direct long-context reasoning fallback        |
| `dsv4f` (Neuralwatt rung) | deepseek-v4-flash | 1M  | PAYG fallback when OpenCode Go is unavailable |

Neuralwatt charges this account for measured GPU energy rather than tokens. PAYG is $5/kWh;
prefix-cache hits avoid prefill work and therefore reduce the charged energy. Neuralwatt also publishes
token prices for compatibility, but those are not the billing basis here. Use Neuralwatt's usage
API/dashboard for authoritative cost and energy; LiteLLM and Prometheus are routing/volume telemetry,
not the billing authority.

### Cloud (Opencode Go gateway, `opencode.ai/zen/go/v1`)

| Alias                               | Upstream model    | Ctx (in)    | Role                                                |
| ----------------------------------- | ----------------- | ----------- | --------------------------------------------------- |
| `dsv4f`                             | deepseek-v4-flash | 1M          | OpenClaw subagent/heartbeat and reasoning-pool rung; cache-sensitive after repricing |
| `dsv4p`                             | deepseek-v4-pro   | 1M          | Heavier DeepSeek                                    |
| `mimo-v2.5` / `mimo-v2.5-pro`       | mimo-v2.5(-pro)   | 262k        | Lighter analysis lane                               |
| `qwen3.7-plus`                      | qwen3.7-plus      | 1M          | Big-context Qwen via gateway                        |

**Provider failover** (LiteLLM `order:`, transparent to callers): `kimi-k2.7` and `kimi-k3` use their
Kimi Coding deployments before Moonshot; `frontier-pool` and `dsv4f` have explicit ordered PAYG rungs;
`glm-5.3` is the OpenClaw main primary and `glm-5.2` remains a Neuralwatt fallback lane. This reacts
when an upstream rejects requests; it cannot detect that an unpublished rolling allowance is merely
_close_ to exhausted. `go-minimax-m3` / `go-minimax-m2.7` were removed entirely (redundant with the
flat MiniMax plan + the native `MiniMax-M3-chat` endpoint).

The current ordered pools are deliberately separate:

| Pool | Order | Members | Effective input context | Policy |
| ---- | ----- | ------- | ----------------------- | ------ |
| `reasoning-pool` | 1 -> 2 -> 3 | GPT-5.6 Luna -> DSV4F (OpenCode Go) -> MiniMax-M3 | 1M | Strong reasoning lane; M3 is the flat-plan floor |
| `frontier-pool` | 1 -> 6 | GPT-5.6 Sol -> Kimi K3 sub -> Kimi K3 Moonshot -> GLM-5.3 -> DSV4F Neuralwatt -> GLM-5.2 Neuralwatt | 1M | Frontier escalation for Opencode/Zed; no MiniMax downgrade |

Kimi-for-Coding was removed from `reasoning-pool`: its 262k context limit made it the pool's
conservative ceiling even though Kimi K3 itself is a 1M standalone/frontier model. The Kimi Coding
subscription remains available through the Kimi aliases and `frontier-pool`.

## Model capability ranking

Benchmark snapshot as of **2026-07-30** — perishable. The table retains the comparable GLM-5.2
benchmark row, while the production OpenClaw main route is GLM-5.3. Do not use the benchmark row as a
proxy for current provider pricing, cache behavior, or quota consumption. Numbers are mostly **vendor
self-reported on non-overlapping harnesses** (SWE-bench Pro ≠ Verified; Terminal-Bench
2.0 ≠ 2.1; GPT SWE-Pro drops ~15pts under standardized scaffolding), so treat deltas as
**directional**, not precise, and re-pull when models bump. `n/p` = not published.

| Model             | Alias                  | Arch (total/active) | Ctx   | SWE-V | SWE-Pro | LiveCodeB | Term-B | GPQA  | AIME  |
| ----------------- | ---------------------- | ------------------- | ----- | ----- | ------- | --------- | ------ | ----- | ----- |
| GPT-5.6 Sol       | `chatgpt/gpt-5.6-sol`  | proprietary         | 1.1M  | n/p   | 64.6    | n/p       | 88.8   | 94.6  | n/p   |
| GPT-5.6 Terra     | `chatgpt/gpt-5.6-terra`| proprietary         | 1.05M | n/p   | 63.4    | n/p       | 87.4   | 92.9  | n/p   |
| GPT-5.6 Luna      | `chatgpt/gpt-5.6-luna` | proprietary         | 1.05M | n/p   | 62.7    | n/p       | 84.7   | 92.3  | n/p   |
| DeepSeek-V4-Pro   | `dsv4p`                | MoE 1.6T/49A        | 1M    | 80.6  | 55.4    | 93.5      | 67.9   | 90.1  | n/p   |
| GLM-5.2           | `glm-5.2`              | MoE ~753B/40A       | 1M    | n/p   | 62.1    | n/p       | 81.0   | 91.2  | 99.2  |
| Kimi K3           | `kimi-k3`              | MoE 2.8T/50A        | 1M    | 77.8⁵ | n/p     | n/p       | 88.3⁵  | 93.5⁵ | n/p   |
| MiniMax-M3        | `MiniMax`              | MoE ~229B/9.8A²     | 1M    | 80.5¹ | 59.0    | n/p       | 66.0   | 92.9  | n/p   |
| DeepSeek-V4-Flash | `dsv4f`                | MoE 284B/13A        | 1M    | 79.0  | n/p     | 91.6      | 56.9   | 88.1  | n/p   |
| Qwen3.6-27B dense | `nvidia`               | dense 27B           | 145k³ | 77.2  | 53.5    | 83.9      | 59.3   | 87.8  | 94.1  |
| MiMo-V2.5-Pro     | `mimo-v2.5-pro`        | MoE 1.02T/42A       | 1M    | 78.9⁴ | 57.2    | 39.6⁴     | n/p    | 66.7⁴ | 37.3⁴ |
| MiniMax-M2.7      | `MiniMax-M2.7`         | ~229B/n_p           | n/p   | n/p   | 56.2    | n/p       | 57.0   | n/p   | n/p   |
| MiMo-V2.5         | `mimo-v2.5`            | MoE 310B/15A        | 1M    | n/p   | 56.1    | n/p       | 65.8   | n/p   | n/p   |
| Qwen3.6-35B-A3B   | `self-hosted`          | MoE 35B/3A          | 262k  | 73.4  | 49.5    | n/p       | 51.5   | 86.0  | 92.7  |
| Mellum2-12B-A2.5B | `reviewer`             | MoE 12B/2.5A        | 131k  | n/p⁷  | n/p     | n/p       | n/p    | n/p   | n/p   |
| Qwen3.7-Plus      | `qwen3.7-plus`         | MoE undisclosed     | 1M    | n/p   | ~60     | n/p       | n/p    | n/p   | n/p   |

¹ GPT/MiniMax SWE-Pro are vendor-reported; cross-provider agent scaffolding can materially shift
reported results. ² MiniMax-M3 param count is contested across sources (also
cited ~428B/23B); most non-coding numbers are vendor-run, independent verification pending.
³ Qwen3.6-27B is 262k native but pinned to 145k on the 24GB 3090. ⁴ MiMo-Pro reasoning /
LiveCodeBench from HF-card scrape only — low confidence; LiveCodeBench slice not comparable
to others. ⁵ Kimi K3 (Moonshot; API launch 2026-07-16, open weights ~07-27): MoE 2.8T total /
~50B active (16 of 896 experts), Kimi Delta Attention, 1M ctx / 131k default output, MXFP4,
native vision. All numbers self-reported on renamed benches (SWE-V ≈ ProgramBench 77.8; Term-B
is 2.1 = 88.3; GPQA-Diamond 93.5) — no weights, report, or third-party SWE run yet. Self-positions
**#3 overall, behind BOTH Claude Fable 5 AND GPT-5.6 Sol** (not "beats all but Fable"), ahead of
Opus 4.8 / GLM-5.2; #1 on the Frontend Code Arena past Fable 5 (1679 Elo). Artificial Analysis
Intelligence Index 57 (Fable 60 / Sol 59) corroborates the ~#3 rank but flags hallucination ~51%
(up from 39%). Pricing $0.30 cached / $3 miss / $15 output per MTok. Treat as marketing until repo-bench.

⁶ `self-hosted` runs the abliterated Qwen3.6-35B-A3B (HauhauCS "Aggressive", Q5_K_P) with its
mmproj loaded, which is what makes this box the image backend. It replaced Ornith-1.0-35B — a
post-tune of the *same* Qwen3.6-35B-A3B — so the swap kept the architecture and dropped the
post-tune. The Mac LM Studio upstream is multimodal too but NOT abliterated: it will refuse
content the Strix answers, and it is flagged `supports_vision` anyway so `enable_pre_call_checks`
keeps it eligible for image failover rather than leaving images with no fallback.

⁷ Mellum2 publishes none of these benches. The number it does publish is BFCL v3 **66.3**
(tool use), which is the axis that actually matters for a reviewer: the verdict is a structured
`submit_result` call whose `issueAsk` must be a verbatim substring of the issue body, and a
malformed payload is rejected by the harness regardless of how good the judgement was. Rank it on
independence and format reliability, not on a coding leaderboard.

Reading it for routing:

- **Frontier tier** (`gpt-5.6-sol`, `kimi-k3`, `glm-5.3`) — strict subscription/PAYG escalation;
  Sol is the ceiling, K3 is the independent coding/frontier lane, and GLM is the long-horizon fallback.
  Neuralwatt supplies the PAYG safety rungs. MiniMax intentionally does not appear here.
- **Reasoning tier** (`gpt-5.6-luna`, `dsv4f`, `MiniMax-M3`) — a separate ordered lane for strong
  reasoning work. Luna leads, DSV4F is the OpenCode Go rung, and MiniMax is the flat-plan floor. The
  pool now has a 1M effective context because the 262k Kimi-for-Coding member was removed.
- **Cheap/fast** (`dsv4f`, `mimo-v2.5`) — near-frontier coding at low cost; `dsv4f` remains a strong
  workhorse, but the August 2026 provider repricing means it is no longer safe to call it cheapest
  without accounting for cache hits and prompt size. Since V4 Flash went GA it no longer belongs only
  in this tier: repo-bench re-scored it 0.895 -> 0.957, at or above the previous top cluster, while V4
  Pro stayed at 0.864. That inversion is why the reasoning tier and Hermes' fallback chain reach for
  Flash, not Pro.
- **Local** — `nvidia` (Qwen3.6-27B dense) is the local quality + speed pick; `self-hosted`
  (35B-A3B) trails it everywhere and earns its place only on the 262k context window.
- **`reviewer` is a deliberate family split, not a quality pick.** Foreman's coder runs
  Qwen (`nvidia`), so a Qwen reviewer inherits the coder's blind spots — it was Qwen
  reviewing Qwen while `self-hosted` served review, since Ornith was itself a
  Qwen3.6-35B-A3B post-tune. Mellum2 is JetBrains' software-engineering MoE, trained from
  scratch on 10.6T tokens, and at 2.5B active it reviews faster than the 35B it replaced
  while costing nothing. It exists to disagree with the coder, so published coding scores
  matter less here than independence and structured-output reliability.
- **MiniMax-M2.7 / MiMo / Qwen3.7-Plus** — agentic workhorses with thin published reasoning
  numbers; rank on coding/agentic axes, not GPQA/AIME.

## Consumers

| Consumer               | In repo?                                    | Points at                                                                                    |
| ---------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **OpenClaw**           | yes (`.../llm/openclaw/app/configmap.yaml`) | Miso/main `glm-5.3`; Saffron `reasoning-pool`; subagents `dsv4f`; heartbeat `llama-nvidia`; image `self-hosted` |
| **Hermes**             | yes (`.../llm/hermes/configmap.yaml`)       | default `kimi-k3`; compression/extract/approval/session-search `self-hosted`                 |
| **Foreman**            | yes (`.../llm/foreman/agents/*.yaml`)       | `coder` → `nvidia`; `coder-strix` + `coder-revision` → `self-hosted`; `coder-frontier` → `MiniMax-M3-chat`; reviewers → `reviewer` |
| **Opencode** (CLI/Zen) | no (workstation)                            | LiteLLM aliases directly; ad-hoc interactive coding, not unattended fleet traffic             |
| **Zed**                | no (workstation)                            | LiteLLM aliases directly                                                                     |

### OpenClaw cron fleet

Two agents (Miso, Saffron) run 16 scheduled jobs, plus two issue-worker pipelines. The model choice
per job already encodes an intent-lane pattern by hand.

| Job                             | Agent   | Model        | Schedule        | Purpose                                        |
| ------------------------------- | ------- | ------------ | --------------- | ---------------------------------------------- |
| Afternoon Email/Finance Check   | Miso    | MiniMax-M2.7 | 4pm daily       | Email + financial anomaly scan                 |
| Instagram Hourly Image Dispatch | Miso    | self-hosted  | 9am–8pm Mon–Thu | Publish one approved staged IG post per window |
| Image Category Creation         | Miso    | MiniMax      | every 6h        | Generate new image category + gallery          |
| Evening Email/Finance Check     | Miso    | MiniMax-M2.7 | 9pm daily       | End-of-day email + finance summary             |
| Nightly Audit Decomposer        | Saffron | self-hosted  | 2am daily       | Decompose audit umbrellas into child issues    |
| Nightly Tech Sweep              | Saffron | mimo-v2.5    | 6:20am daily    | Overnight health check + low-risk fixes        |
| Unified Morning Brief           | Miso    | MiniMax-M2.7 | 7:30am daily    | Weather, calendar, inbox, IG pool, news, radon |
| Daily LLM + HN Digest           | Miso    | self-hosted  | 8:30am daily    | r/LocalLLaMA etc. + HN top stories             |
| Daily Home-Ops Updates          | Saffron | MiniMax-M2.7 | 9am daily       | Commit watch on homelab k8s repos              |
| Daily Image (Miso)              | Miso    | self-hosted  | 9:15am daily    | Character image generation                     |
| Alertmanager Health Digest      | Saffron | mimo-v2.5    | 9:30am daily    | Firing Prometheus alerts + investigation       |
| Solar Daily Check               | Miso    | MiniMax-M2.7 | 9:35am daily    | Solar generation + weather + guess tracking    |
| Daily Image (Saffron)           | Saffron | self-hosted  | 10:15am daily   | Character image generation                     |
| Weekly IG Posting Times         | Miso    | mimo-v2.5    | 11am Fri        | Research optimal IG posting times              |
| Weekly Audit                    | Saffron | MiniMax-M2.7 | 1am Wed         | Spawn per-repo audit sub-agents                |
| Weekly Prompt Hygiene           | Saffron | mimo-v2.5    | 10:45am Wed     | Audit prompt files for bloat/contradictions    |

Issue-worker pipelines (pick up issues and open PRs):

- **MC Normal** → `self-hosted`
- **MC Escalated** → `gpt-5.6-sol`

## Current routing + observed usage

Routing today is `simple-shuffle` with hand-written availability fallbacks
(`kubernetes/apps/base/llm/litellm/litellmproxy.yaml`). `simple-shuffle` spreads a synchronized fan-out
evenly across a group's deployments; `least-busy` increments its in-flight
counter _after_ the routing decision, so a burst reads equal counts and piles
onto the first deployment — wrong for the 2-instance `self-hosted` group.

```yaml
routing_strategy: simple-shuffle
fallbacks:
    - llama-strix: [llama-nvidia]
    - llama-nvidia: [llama-strix]
    - dsv4f: [llama-nvidia]
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
| llama-strix-nemotron        |                45.0M |
| mimo-v2.5                   |                22.8M |
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
DSV4F and heartbeats use the local NVIDIA model. This preserves the quality lanes instead of routing
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
  time-to-first-token on the `nvidia` alias while the model itself was fine (fixed 2026-08).
- **Cap below the backend** and provisioned VRAM goes unused. `llama-reviewer` served 3
  slots while LiteLLM dispatched into 2 — a third of the model unreachable (fixed 2026-08).

Current: Strix 2, Mac 2, reviewer 3, nvidia 1. The Strix box is memory-bandwidth bound, so
aggregate tok/s improves with concurrent streams spread **across** resident models rather
than piled onto one — the useful range is roughly 6-8 streams for the whole box, not per
model. Both `self-hosted` members stay `order: 1` deliberately: the Mac is used whenever it
is awake, and a failed call when it sleeps is the accepted cost of not idling it.

Foreman's demand cannot currently be bounded per-Agent
([LLMKube#1497](https://github.com/defilantech/LLMKube/issues/1497)), so the only levers on
its share of `self-hosted` are the bridge's `MAX_IN_PROGRESS` and the `LANE_CODER_AGENTS`
split ratio — both blunt. Measured `self-hosted` utilisation across *all* consumers
(Foreman, home-ops PR reviews, groomer, repo-wiki) is ~15 busy-hours/day against 96
slot-hours, so headroom is real and the risk is bursts, not steady state.

## Smart-routing: the `auto` alias

An opt-in `auto` alias routes for **opencode + Zed only**; every other consumer (crons, MC
workers, Hermes roles, MiniMax) stays pinned. It uses LiteLLM's **LLM classifier**
(`classifier_type: llm`), not the rule-based complexity scorer — see the measurements below.

Tiers (three effective tiers; REASONING is folded into COMPLEX):

| Tier               | Target                              | Why                                          |
| ------------------ | ----------------------------------- | -------------------------------------------- |
| SIMPLE             | `self-hosted` (Strix 35B-A3B)       | Trivia — 0.4s, local, free                   |
| MEDIUM             | `MiniMax-M3-chat`                   | Flat sub, ~1.1s, no weekly quota to burn     |
| COMPLEX            | `reasoning-pool`                    | Luna -> DSV4F -> MiniMax-M3                  |
| REASONING          | `reasoning-pool`                    | Folded — no classifier could separate it     |
| default (miss)     | `MiniMax-M3-chat`                   | `classifier_fallback: default_model`         |

Classifier is `reviewer` (Mellum2-12B, ~0.5s) — a software-engineering model classifying a
software-engineering axis, and the cheapest thing in the fleet to put in every request's path.

`frontier-pool` is deliberately **not** a tier target: `auto` must not compete with interactive
sessions for the weekly ChatGPT/Kimi caps. COMPLEX reaches Luna and DSV4F through `reasoning-pool`;
Kimi K3 remains in `frontier-pool` or explicit selection rather than being a reasoning-pool rung.

### Measured (2026-08-07, LiteLLM 1.95.0)

Two 20-prompt corpora, one held out. Scored against a throwaway proxy running the real router
against real backends.

| Config                                     | Tier accuracy      |
| ------------------------------------------ | ------------------ |
| Rule-based scorer, boundaries `.45/.65/.85` | **5/20 (25%)**     |
| Rule-based scorer, boundaries `.15/.35/.60` | 7/20 (35%)         |
| LLM classifier (`reviewer`), held out       | 17/20 (85%) 3-tier |
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
- Local context ceilings (145k/262k) are guarded by `context_window_fallbacks` +
  `enable_pre_call_checks`, not by any router setting.
- `reasoning-pool`'s M3 rung uses MiniMax's OpenAI-compatible `/v1` endpoint, so it may expose
  thinking in content; acceptable for this lane. OpenClaw's native `MiniMax-M3` alias uses the
  Anthropic `/messages` endpoint and its think-tag stripping shim.

Excluded from `auto` by design: the native `MiniMax` messages alias and the manual Sol/Terra aliases.
A **semantic router** (`auto-semantic` + `router.json`) is scaffolded but commented out: `from_json`
builds an encoder at startup (crashloop risk on the live gateway), so it's verify-then-enable later.

Still ahead:

- Swap MEDIUM to `nvidia` once Foreman's backlog drains — it's the better model and free, but was
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

1. `gpt-5.6-sol` — flagship frontier (ChatGPT Plus sub)
2. `kimi-k3` @ Kimi Coding — dedicated Kimi sub (flat)
3. `kimi-k3` @ Moonshot — PAYG backup
4. `glm-5.3` @ Z.AI — GLM Coding Lite sub
5. `dsv4f` @ Neuralwatt — PAYG DeepSeek fallback
6. `glm-5.2` @ Neuralwatt — PAYG GLM fallback

Implemented as one **self-contained `order:` group**, not router fallbacks referencing the shared
groups. It intentionally has no MiniMax floor: a frontier request fails rather than silently degrading
to the reasoning lane.

Caveats:

- **Know which model answered.** Failover is silent — read the `x-litellm-model-id` response header (or
  the LiteLLM logs) to see whether you're on Sol, K3, or GLM.
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
  fine, and forced calls fall through to the `dsv4f` → `nvidia` router fallback rather than failing.
- Watch `litellm_deployment_successful_fallbacks_total{requested_model="dsv4f",fallback_model="nvidia"}`.
  If it climbs, a consumer is forcing a tool and `extra_body: {thinking: {type: disabled}}` should be
  restored on that deployment. The likeliest source is the `self-hosted` → `dsv4f` context-window
  fallback, which arrives carrying whatever `tool_choice` the original caller set.
- `dsv4p` keeps the disable; it is only reachable by explicit selection now.
