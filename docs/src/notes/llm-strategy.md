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

## Target: intent-lane routing

The goal is to stop addressing provider/model names from tools and instead address **intent lanes**,
then let LiteLLM route. The cron fleet already proves the lanes exist — formalize them:

| Lane | Model | Maps to today |
|---|---|---|
| `local-fast` | `nvidia` (3090 Qwen) | Short edits, YAML, shell, quick transforms |
| `local-general` | `self-hosted` (Strix Qwen3.6-35B) | Default local brain; digests, decomposition, image dispatch |
| `local-reviewer` | `review` (GLM-4.7-Flash / Gemma) | Second opinion, PR review (MC Normal) |
| `cloud-coder` | `MiniMax-M2.7` / `dsv4f` | Agentic reasoning + high-volume coding (most crons) |
| `frontier` | `chatgpt/gpt-5.5` | High-stakes, hard debugging (MC Escalated) |

Plan, in layers (LiteLLM-native first, no new infra):

1. **Define the lane aliases** above as model groups.
2. **Expose one default alias** (e.g. `auto`) for tools to point at.
3. **Complexity Router** as first pass — token count, code presence, reasoning markers, etc. →
   simple/medium/complex/reasoning tiers.
4. **Auto Routing (semantic)** for intent the complexity score can't infer — e.g. "review this PR"
   must land on `local-reviewer`, not `local-general`.
5. **Fallbacks** stay for *availability* (3090 down → spill to gateway), not quality.
6. **Harness-level quality escalation** in OpenClaw/Hermes — escalate to `cloud-coder`/`frontier` on
   tool failure, uncertainty markers, failed tests/lint, or explicit "are you sure" — re-running
   `original_prompt + local_answer + failure_signal`. This is supervision, not routing.

References: LiteLLM [Auto Routing](https://docs.litellm.ai/docs/proxy/auto_routing) ·
[Fallbacks](https://docs.litellm.ai/docs/proxy/reliability).
