# Maya benchmarks on ganyu

These tests use GLM-5.3-Flash Maya-S24 on one RTX 3090 with 24 GiB of VRAM.
The tests call Maya directly, so they do not measure LiteLLM overhead or route limits.
Prefill means processing the input. Decode means generating output tokens.
Time to first token (TTFT) includes prefill, request overhead, and any wait.

## Findings

- The larger RAM tier raised decode speed in all four matched runs. The range went from 10.7–15.3 to 16.2–18.5 tok/s.
- Two slots improved the second caller's time to first token for short prompts. Together the two streams still produced 18.9 tok/s, the same as one stream.
- At 262,144 context, two uncached 31K prompts reached 1,174 input tok/s combined. That equals one stream's solo rate, so two slots add no prefill throughput: prefills run one at a time.
- The 1M configuration started with two slots and peaked at 90.73 GiB in the early snapshot. No 1M prompt completed as part of this benchmark.
- The sampled prefills logged no expert reads from disk. Copy-stream counters did not show how long GPU compute waited for weights.
- Strata's QFN IQ3_S and Maya's GLM prefill at the same rate, 1,020 to 1,170 tok/s above 14K input tokens. QFN decodes far faster, but that gap mixes two effects: QFN drafts with DFlash2 and GLM does not, and Maya's 64-token runs understate its steady state.
- Maya 1.1.67 supports DFlash2 for GLM-5.3-Flash at any quant, including this IQ2_XXS_S build, but the engine refuses it with `--parallel` above 1. See "DFlash2 for GLM on Maya".
- No exposed PCIe stall was measured. Staged copy work accounts for at most 6.6% to 22.5% of a chunk's wall time, `ring wait` measures the copy stream waiting on compute, and the `/stats` ring fields give contradictory per-batch rates. The remaining question needs a GPU trace, and no tracer is installed.

Interleaving remained off. The tests do not establish whether a wider PCIe link would materially improve prefill.

## RAM tier comparison at 131,072 context and one slot

Commit `ece9fb5330` raised the pod memory limit from 80 to 96 GiB and `MAYA_EXPERT_RAM_GB` from 64 to 88.
Both runs used the same prompts. Each request generated 64 tokens and reused zero input tokens from the prefix cache.
The input rates in this table divide input tokens by TTFT. They are not engine timings.

| Input tokens | TTFT, 64 / 88 (s) | Input rate, 64 / 88 (tok/s) | Decode, 64 / 88 (tok/s) | Total, 64 / 88 (s) |
| ---: | ---: | ---: | ---: | ---: |
| 6,986 | 10.71 / 11.14 | 652 / 627 | 14.1 / 16.2 | 15.3 / 15.1 |
| 14,124 | 17.78 / 13.85 | 795 / 1,020 | 15.3 / 17.8 | 22.0 / 17.4 |
| 28,330 | 31.79 / 27.15 | 891 / 1,044 | 10.7 / 18.5 | 37.7 / 30.6 |
| 114,150 | 103.96 / 101.90 | 1,098 / 1,120 | 13.2 / 17.7 | 108.8 / 105.5 |

The earlier pod reached its 80 GiB limit. The 96 GiB pod reached 83.3 GiB in this sweep, with zero restarts and 23,730 MiB of device VRAM in use.
The 96 GiB configuration brought node memory requests to 95% at the time of the test.

## Two slots at 131,072 context

Commit `81e2add6d9` added the second slot. `/props` reported two slots.
The first test used 2,814 input tokens and 64 output tokens per request.

| Requests submitted together | TTFT by arrival of first token (s) | Group wall time (s) | Output tokens per wall second | Pod memory before / after (GiB) |
| ---: | --- | ---: | ---: | ---: |
| 1 | 10.95 | 15.2 | 4.2 | 77.9 / 78.1 |
| 2 | 9.44, 18.72 | 25.7 | 5.0 | 78.1 / 78.2 |
| 4 | 9.38, 18.16, 35.43, 44.57 | 52.7 | 4.9 | 78.2 / 78.7 |

The next test used short essay prompts and 256 output tokens per request.
The group decode rate divides total output tokens by the time from the earliest first token to the last completion.
It includes any waits inside that window. With three callers, the third caller waited for a slot.

| Requests submitted together | TTFT by arrival of first token (s) | Group wall time (s) | Group decode rate (tok/s) | Pod memory before / after (GiB) |
| ---: | --- | ---: | ---: | ---: |
| 1 | 0.91 | 14.5 | 18.9 | 78.7 / 78.7 |
| 2 | 0.91, 1.68 | 27.9 | 18.9 | 78.7 / 78.7 |
| 3 | 1.05, 2.02, 31.40 | 49.0 | 16.0 | 78.7 / 78.8 |

## Long prompts at 262,144 context and two slots

Commits `be031ae90e` and `c001e89420` raised and kept the context at 262,144.
The engine kept a window of 32,768 positions in VRAM. It reported a 1.57 GB pinned attention cache for each slot.
The tests used one request at a time and allowed 64 output tokens. The input rate uses TTFT rather than the engine clock.

| Input tokens | TTFT (s) | Input rate (tok/s) | Decode (tok/s) | Total (s) | Pod memory before / after (GiB) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 29,350 | 25.2 | 1,164 | 15.1 | 29.5 | 79.8 / 80.3 |
| 118,062 | 104.2 | 1,133 | 16.7 | 108.0 | 80.3 / 80.4 |
| 180,742 | 165.4 | 1,093 | 16.5 | 169.3 | 80.4 / 80.7 |
| 226,272 | 213.0 | 1,062 | 15.8 | 217.1 | 80.7 / 81.7 |

A separate concurrency run used different prompts from the 131,072 short-prompt test. It also generated different output lengths.
Its group decode rates were 8.9, 11.6, and 9.8 tok/s for one, two, and three callers. Do not use those rates to compare context sizes.

The follow-up used the same prompts at each context size. The repeated 1,054-token prompt reused the prefix cache.
Each cell shows TTFT in seconds and decode rate in tok/s. This was one pass per context, not a test of run-to-run variation.

| Prompt | 131,072 context | 262,144 context |
| --- | ---: | ---: |
| 21 tokens | 0.80 / 17.5 | 1.17 / 16.5 |
| 20 tokens | 0.64 / 19.0 | 0.77 / 20.0 |
| 1,054 tokens, first request | 8.53 / 15.7 | 9.36 / 16.2 |
| 1,054 tokens, repeat | 0.05 / 19.1 | 0.05 / 18.4 |
| 36,852 tokens | 35.74 / 15.0 | 36.93 / 15.7 |

## Two long prompts at 262,144 context

An earlier mixed prefill and decode test ended with a connection reset. It produced no usable comparison.
The next test submitted both long prompts together, with interleaving off. Both prompts reused zero input tokens and generated eight output tokens.

| Request | Input tokens | Engine prefill (s) | Engine prefill (tok/s) | TTFT (s) | Total (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| First to emit | 31,335 | 26.91 | 1,164.3 | 26.94 | 54.40 |
| Second to emit | 31,336 | 26.44 | 1,185.2 | 53.39 | 54.40 |

The two requests processed 1,173.8 input tok/s combined, measured from submission to the last first token.
The prefills ran back-to-back. The first stream took another 27.45 seconds to finish after its first token.
The pod peaked at 81.11 GiB. Live traffic prevented a new solo control.
Maya logged `disk 0.00` for both prefills. The 3090 used PCIe 4.0 x4 and Maya logged about 5.9 GB/s during expert copies.

## 1,000,000 context memory snapshot

Commit `200bdda082` raised the engine context to 1,000,000 tokens. The pod reported that limit for both slots.
The LiteLLM input and output limits did not change in that commit. This snapshot does not test a million-token prompt or two long prompts.

| Measurement | Value |
| --- | ---: |
| Pod memory, current / peak / limit | 90.67 / 90.73 / 96.00 GiB |
| File-backed / anonymous memory | 88.22 / 2.05 GiB |
| Swap / pod restarts / cgroup OOM kills | 0 GiB / 0 / 0 |
| GPU device memory used / total | 23,594 / 24,576 MiB |
| Attention cache in pinned RAM, per slot | 5.98 GB |
| Expert RAM tier, pinned | 75.50 GB |
| Experts warm across RAM and VRAM | 12,096 |

One slot was active at the time of the snapshot. Two prefill chunks had expert disk counters and both reported `disk 0.00`.
These counters measure expert reads. They do not measure all storage activity or rule out expert reads below the log's display precision.
Startup reads the model from disk. The goal is no expert reads from disk during inference after warmup.

## Expert transfers and the prefill critical path

Maya reports the time spent on staged expert copies. It does not report how much of that time blocks GPU computation.
The `ring wait` counter measures the copy stream waiting for GPU computation to release a staging buffer. It does not measure the GPU waiting for a copy.
The `copies` counter covers the staged copy groups. The PCIe volume in this line excludes the separate expert copies that Maya starts early.

| Context and workload | Chunk tokens | Chunk wall (s) | Staged PCIe (GiB) | Staged within VRAM (GiB) | Staged copy span (s) | Copy span / chunk wall | Copy stream ring wait (s) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 262,144, paired benchmark, first prefill | 31,334 | 25.651 | 15.21 | 0.28 | 2.581 | 10.1% | 4.838 |
| 262,144, paired benchmark, second prefill | 31,335 | 26.113 | 10.24 | 0.27 | 1.731 | 6.6% | 6.529 |
| 1,000,000, live traffic sample | 15,124 | 15.539 | 20.12 | 2.67 | 3.489 | 22.5% | 2.133 |

The source divides bytes by 2^30, although the log labels the volumes `GB`. All three rows report `disk 0.00`, in solo and paired runs alike.
The 1M row is not a matched solo result. Live traffic kept a slot busy during both attempts to start a controlled comparison.
These percentages show staged copy activity as a share of chunk time, not the share of prefill time lost to PCIe.

### What the copy counters can and cannot support

The 2.581 s and 1.731 s spans are copy-stream time, not stall time. The engine's own log rate is about 5.9 GiB/s, and 15.21 GiB and 10.24 GiB divided by that rate give those two spans.
`ring wait` (4.838 s and 6.529 s) counts the copy stream waiting for a staging buffer to free, which means copying ran ahead of compute. It is not compute waiting for a copy.

`/stats` adds four ring fields. Two readings of them disagree, so their units cannot be pinned down:

| Reading | Ring batches | Cumulative MiB | Cumulative ms | Implied per batch |
| --- | ---: | ---: | ---: | ---: |
| Two readings 12 minutes apart, live traffic | 750 to 774 | 218,742 to 242,371 | 218,742 to 225,858 | 313 MiB, 292 ms, 1.07 GiB/s |
| One 31K prefill, 30 second window | 107 | 6,218 | 417 | 58 MiB, 3.9 ms, 14.9 GiB/s |

PCIe 4.0 x4 moves about 5.9 GiB/s, so the second row's rate is impossible for PCIe traffic, and the first row's 292 ms per batch is longer than a whole prefill. Either `ram_batch_mib` is not bytes moved, or `ram_batch_ms` is not batch duration. Do not size the copy path from these fields.
The per-request log line stays the only usable copy figure, and only as an upper bound: at most 2.581 s of a 25.651 s chunk, about 10%, is copy work of any kind.

### Reaching the exposed stall time

The gap is still open, and the tooling is not on hand:

- `nsys` and `nsys-ui` are not installed on this workstation, and upstream 1.1.67 ships no `--trace` switch. A capture needs a new image with Nsight Systems, plus `--trace-fork-before-exec` because the engine starts through a shell and `setpriv`.
- The GLM engine has no CUDA graph path, so CUDA graph tracing would add nothing.
- `nvidia-smi -d COLUMN` samples activity, not API calls.
- GPU state sampled through a Strata prefill (190 one-second samples): mean `utilization.gpu` 79.9%, with 79% of samples at 95% or higher; SM clock 1,659 MHz mean and 210 MHz idle; 214 W mean and 300 W peak; 22,248 MiB used, unchanged through the run.
- `utilization.gpu` counts any sampled second in which at least one kernel ran. A card at 100% can still be stalling between short kernels, so this says nothing about whether compute waited on weights.

Time when no kernel runs is not all transfer wait either. Host planning, CPU expert work, or other dependencies can leave the GPU idle. A trace separates them; the counters do not.

## QFN on Strata against GLM on Maya

Strata serves Qwen3.8-Flash-Next IQ3_S (78 GB of shards) on the same card, engine `0.1.59`, 268,288 context, three slots, dflash2 drafting at `--spec 6`.
The live engine holds 79.4 GiB resident. Maya keeps 90.7 GiB. Both hold about 23.6 GiB of the card's 24 GiB.
These requests used a unique marker at the start of each prompt, so the prefix cache reused nothing, and thinking was off.
Prefill and decode use the engine's own `timings`, so queue time behind other traffic does not enter them. Time to first token does include queueing.

| Prompt tokens | QFN IQ3_S prefill (tok/s) | GLM Maya prefill (tok/s) | QFN IQ3_S decode (tok/s) | GLM Maya decode (tok/s) |
| ---: | ---: | ---: | ---: | ---: |
| 130 / 21 | 121 (1.07 s to read) | not measured (0.77 s to first token) | 63 | 19.0 |
| 8,341 / 6,986 | 1,034 | 627 | 75 | 16.2 |
| 16,736 / 14,124 | 1,088 | 1,020 | 98 | 17.8 |
| 33,536 / 29,350 | 1,124 | 1,164 | 113 | 15.1 |
| 139,189 / 118,062 | 1,166 | 1,133 | 95 | 16.7 |
| not measured / 180,742 | - | 1,093 | - | 16.5 |
| not measured / 226,272 | - | 1,062 | - | 15.8 |

The two engines are not configured alike, and two differences dominate the decode columns.

Speculation: Strata drafts with dflash2 and reports accepted drafts; Maya reported `draft_n 0` and `draft_n_accepted 0`, so its GLM decoded one token per step.

Output length also moves the measured rate. Two matched Strata runs with 1,024 output tokens, same base text, cold prefix cache, thinking off:

| Engine and run | Prompt tokens | Output tokens | Prefill (tok/s, engine) | Prefill wall (s) | Decode wall (s) | Decode (tok/s, client) | Decode (tok/s, engine) | Drafts made / accepted |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Strata, 64 output tokens | 33,536 | 64 | 1,124 | 29.8 | 0.6 | 113 | 113 | not recorded |
| Strata, 1,024 output tokens | 29,176 | 1,024 | 1,086 | 26.9 | 10.4 | 98.1 | 97.9 | 672 / 501 (0.746) |
| Strata, 1,024 output tokens | 126,146 | 1,024 | 1,134 | 111.2 | 10.3 | 99.8 | 99.6 | 636 / 466 (0.733) |

Strata's rate barely moves with output length, and its client and engine figures agree within 0.3%, so the table's Strata column is sound at 64 tokens.
Maya's 15.1 to 19.4 tok/s all come from 64-token runs. One attempt at 1,024 output tokens on the 1M pod is **void and excluded**: that pod was being deleted during the run as the card moved back to Strata, so it shared the GPU with Strata's cold start. A matched Maya run at 1,024 tokens still needs a window when the card is Maya's.

Strata's queue was busy during two of these requests. The short prompt read its 130 tokens in 1.07 s but waited 28.8 s for a slot.
Maya was not run at 8K, and Strata was not run past 126,146 tokens. A matched sweep at 180K and 226K on Strata would need about four minutes of the card and would block the local lane meanwhile.

Strata IQ3_S against Unsloth UD-Q4_K_XL was already measured on this machine on 2026-11-08, in `/data/bench-standard` and `/data/bench-q4` on the cache PVC. Same protocol, same engine options, 131,072 context.
IQ3_S was faster in every column: prefill 595 and 1,138 against 362 and 706 at 4K and 16K, decode 75 against 46, time to first token 2.05 s against 3.56 s and 14.43 s against 23.25 s, and 57 tok/s against 36 tok/s with four requests at once. Both passed 12 of 12 sanity checks.
The Unsloth shards total 104 GB and IQ3_S totals 78 GB, so the larger quant cannot stay resident in an 80 GiB pod on a 125.6 GiB node. That explains the gap.

## DFlash2 for GLM on Maya: supported upstream, blocked by configuration

Maya 1.1.67 (upstream tag `56b5216`) ships a DFlash2 drafter for GLM-5.3-Flash. `maya.py` pins it at line 597: `Anbeeld/GLM-5.3-Flash-DFlash2-GGUF`, revision `f3569acb7f9cee95e66d24442d75536eb00ab842`, file `GLM-5.3-Flash-DFlash2-Q4_K_M.gguf`, 697,017,248 bytes, sha256 starting `f4158ffb`, licence CC BY-NC-ND 4.0.
The comment says the drafter is made for the model in any of its listed quants, which covers the Maya-S24 `IQ2_XXS_S` shards this deployment runs. It is separate from the model's own MTP block, and the setup offers `mtp` or `dflash2` (`DRAFTS` at line 601). This pod has neither: the manifest sets no `--dflash` path and `MAYA_GLM_NO_MTP` is unset but unused.

Three things block it here, and none is a missing asset:

1. `--dflash` is refused with more than one slot. `src/program/generate.cpp` line 2598 states the condition: one GPU, the NextN block loaded (`MAYA_GLM_NO_MTP` unset), and no `--dflash`. The same file describes `--parallel N` at line 405 as "up to N requests decode at once (1-8, default 1)". Maya runs `--parallel 2`.
2. The other drafting path, MTP, is off. `src/core/glm_mtp.cu` lines 24 to 26 limit it by default to `gfx115x` APUs and need `MAYA_GLM_MTP_DECODE=1` for a glm-dsa model, and `multi_mtp_setting` at line 123 returns 0 when more than one conversation is active. The startup line's `mtp=0` and every request's `draft_n 0` agree with this.
3. VRAM headroom. The drafter loads next to the expert arena, and on this pod the arena covers the whole card.

Headroom read on the running 1M pod before the card moved back to Strata:

| Source | Card (MiB) | Reported free (MiB) |
| --- | ---: | ---: |
| engine `/props` | 24,470 | 586 |
| `nvidia-smi` | 24,576 | 652 |
| Maya's log, after `maya-vision` lends its pool | 24,470 | 2,980 |

The drafter needs 665 MiB. It does not fit in 586 MiB and it fits in 2,980 MiB. The larger figure follows the on-demand encoder path: `serve --vision` measures what the encoder needs and exports `MAYA_GLM_VISION_LEND_MB`, which makes the expert cache lendable so its tail returns to the engine while a picture is read (`generate.cpp` 6108 to 6110, `serve/server.py` 7397). `maya-vision` 1.1.1 is in the image, so the larger figure is the intended state.
What is not settled: `MAYA_GLM_VISION_LEND_MB` is a measurement the server passes in, not a guarantee the arena shrank by that amount, and upstream marks a case where `GlmVlm::init` returns success without reserving the full pool. A test should confirm the free figure after the lend rather than trusting it, and lower the RAM tier first.

Smallest reversible test, once the card is Maya's again:

- Change `--parallel 2` to `--parallel 1` and add `--draft dflash2` to the `maya.py --setup` line. Setup then downloads the pinned drafter and writes the engine's own `--dflash <path>` into the config (`maya.py` 4190); passing `--dflash` to setup is not the switch. The 3090 is sm_86, so it is not in the pre-sm_80 branch that keeps MTP instead (`choose_draft`).
- Set `MAYA_EXPERT_RAM_GB` a few GB below 88, and confirm the card's free VRAM after the vision lend before believing any headroom figure.
- Pass condition: the request's `timings` report `draft_n` above 0 and `draft_n_accepted` above 0. A faster stream without nonzero drafts is not a pass.
- Rollback: `--dflash off` with `MAYA_GLM_NO_MTP=1` returns to today's one-token-per-step decode.
- Costs to watch: one slot makes a second caller wait, and a lower RAM tier gives back part of the 31% decode gain in the RAM tier table.

## Queueing behind a long first request

Run on the 1M pod during the handoff to Strata, so treat the absolute values as indicative and re-run them in a clean window. A solo short prompt reached its first token in 3.44 s. With an ~31K prompt already in flight, a short second request waited 64.28 s at `max_tokens 1` and 25.77 s at `max_tokens 4096`.
That matches the slot rule: with two slots, a long prefill holds one slot and the second request starts only when a slot frees, so the second caller's wait tracks the first caller's whole request rather than its prefill.
Both requests did get GPU work in overlapping windows, and the pair's combined output stayed close to twice a single stream. The prefills still ran one after the other, which is what the clean 262,144 paired run above already showed.

### Why prefills take turns, and what would change it

In 1.1.67 the engine reads one prompt at a time on a single GPU, and there is no config switch for reading two prompts together. `generate.cpp` line 1252 offers `MAYA_GLM_PREFILL_INTERLEAVE=tokens,rounds,mode`, which cuts one prompt into pieces of at least 256 tokens (rounded to whole chunks) and lets other slots decode between the pieces. That narrows a decoder's gap; it does not add prefill throughput, because the pieces are still read in sequence.
`MAYA_GLM_PREFILL_GAPS` does run the split's batched rows, and line 3202 refuses it here: it "needs a split with MAYA_GLM_SPLIT_ROWS", so it is off on one card. In short, batched prefill on one GPU is an upstream design limit, not a setting this deployment left off.

## How these were measured

- Neither engine pod has `curl` or `wget`. Read `127.0.0.1:8080` with Python: Strata has `/opt/strata/terminal/python/bin/python3`; for Maya use a helper pod. `kubectl cp` into the Strata pod fails with a `chown` error, so pipe the script: `kubectl -n llm exec -i POD -- python3 -u - < script.py`.
- Request keys that matter: `stream_options: {"include_usage": true}` for token counts, `temperature: 0`, `ignore_eos: true` on Maya to fill the output budget, and `chat_template_kwargs: {"enable_thinking": false}` on Strata. `timings` arrives on the final streaming event.
- A unique hex marker starts every prompt, so the prefix cache reuses nothing; `usage.prompt_tokens_details.cached_tokens` confirms it.
- GPU sampling works from the device plugin container, which is the only workload on ganyu with `nvidia-smi`:
  `kubectl -n kube-system exec nvidia-device-plugin-<id> -c nvidia-device-plugin-ctr -- nvidia-smi --query-gpu=utilization.gpu,memory.used,clocks.sm,power.draw --format=csv,noheader`
- Maya's useful counters: `/props` for slots, context, VRAM and pinned MiB; `/stats` for `ring_batch_*`, `ram_inflight_mb`, `ram_pending_mb`, and expert seconds. Strata's: `/metrics` and its own `timings`.
- The sweep scripts live in the session scratch directory and do not survive it. Their request bodies and the sampler above are the parts worth keeping.

## Next comparison

1. Matched Maya decode. Needs a window where the 3090 is Maya's: one 31K prompt and one 126K prompt, 1,024 output tokens each, so the decode columns in the comparison table rest on equal output lengths.
2. The DFlash2 test above, at `--parallel 1`, checked by `draft_n` and `draft_n_accepted` rather than by speed alone.
3. A GPU trace with Nsight Systems in a test image, to separate exposed PCIe stall from CPU expert work and host planning.

Interleaving lets a request generate output between pieces of another request's prefill.
At the same context size, compare the longest gap between output tokens with interleaving off and on.
Also record the long prompt's prefill rate and TTFT, both streams' decode rates, peak memory, and expert disk counters.
