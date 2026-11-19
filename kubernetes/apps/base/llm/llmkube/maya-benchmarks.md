# Maya benchmarks on ganyu

These tests use GLM-5.3-Flash Maya-S24 on one RTX 3090 with 24 GiB of VRAM.
The tests call Maya directly, so they do not measure LiteLLM overhead or route limits.
Prefill means processing the input. Decode means generating output tokens.
Time to first token (TTFT) includes prefill, request overhead, and any wait.

## Findings

- The larger RAM tier raised decode speed in all four matched runs. The range went from 10.7–15.3 to 16.2–18.5 tok/s.
- Two slots improved the second caller's time to first token for short prompts. Together the two streams still produced 18.9 tok/s, the same as one stream.
- At 262,144 context, two uncached 31K prompts reached 1,174 input tok/s combined. Prefill ran one prompt at a time and paused output on the first stream.
- The 1M configuration started with two slots and peaked at 90.73 GiB in the early snapshot. No 1M prompt completed as part of this benchmark.
- The sampled prefills logged no expert reads from disk. Copy-stream counters did not show how long GPU compute waited for weights.

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

The source divides bytes by 2^30, although the log labels the volumes `GB`. The three rows report `disk 0.00` for staged expert reads.
The 1M row is not a matched solo result. Live traffic kept a slot busy during both attempts to start a controlled comparison.
These percentages show staged copy activity as a share of chunk time, not the share of prefill time lost to PCIe.

To measure the missing times, capture a GPU timeline for matched uncached prompts in solo and paired runs.
Include staged and early expert copies, GPU kernels, and the compute stream's waits for weights.
Time when no kernel runs is not all transfer wait. Host planning, CPU expert work, or other dependencies can also leave the GPU idle.

## Next comparison

Interleaving lets a request generate output between pieces of another request's prefill.
At the same context size, compare the longest gap between output tokens with interleaving off and on.
Also record the long prompt's prefill rate and TTFT, both streams' decode rates, peak memory, and expert disk counters.
