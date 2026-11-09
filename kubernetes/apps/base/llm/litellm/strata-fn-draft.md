# Strata Flash-Next as the 3090 worker (muse + 27B deprecation)

Status: **ready for review** — this PR is the full cutover, not an inert
draft. Merging it retires `qwen3.8-27b` and `muse-glimmer` (cluster lanes and
Mac endpoint) and brings up `strata-fn` at `replicas: 1`. Nothing is committed
to `main` yet.

## Why

Strata Flash-Next IQ3_S on the RTX 3090 replaces both 3090 workloads:

| | qwen3.8-27B (vLLM W4A16) | muse-glimmer (llama.cpp) | Strata FN IQ3_S |
| --- | --- | --- | --- |
| Decode (per stream) | ~34 tok/s (vLLM p50) | ~30 tok/s class | 75–100 tok/s |
| Aggregate at saturation | — | — | ~80 tok/s (3 slots) |
| Fresh prefill | — | — | ~1040 tok/s flat to 232K |
| Cached 16K TTFT | litellm p50 3.8 s | p50 15.2 s (3090 era) | 0.32–0.6 s |
| Max context | 147456 | 131072 | 256K (232K prompt verified) |
| Quality vs Q8_0 reference | ≈ BF16 (W4A16) | — | 87.7% top-1, PPL 4.097 vs 4.052 |
| Host RAM while resident | ~10.8 GB free | — | ~35 GB free |

Benchmarked 2026-11-08 on ganyu (engine 0.1.52, image 0.2.7-cuda13, driver
595.91.07): PCIe Gen4 x4 saturated at 6.5–7 GB/s during load, sanity suite
12/12, 262K-preset admission verified at 232K prompt tokens.

## What this PR changes

**New**

- `litellm/strata-fn.yaml` — llmkube `Model` stub + `InferenceService`
  (`runtime: generic`, launch + supervise command, `skipModelInit`, IQ3_S @
  256K, vision on, `replicas: 1`, auth-header probes, no memory limit — Strata
  plans KV from host RAM).
- `litellm/models/strata-fn.yaml` — explicit `LiteLLMModel` joining the
  `qwen3.8-flash-next` group as `order: 2`, `max_parallel_requests: 3`,
  `maxInputTokens: 245760`, vision **false** until one real image request
  passes.

**Deleted**

- `litellm/qwen3.8-27b.yaml` (Model + IS), `litellm/muse-glimmer.yaml`
  (Model + IS), `litellm/nvidia-pool.yaml` (ModelPool + ModelRouter — the
  `nvidia-router-proxy` service disappears with it).
- `models/qwen3.8-27b.yaml`, `models/muse-glimmer.yaml` (all muse/27B
  LiteLLMModel rungs, including the Mac LM Studio muse deployment — **confirm
  the Mac endpoint should go too**).

**Rewired consumers** (every reference to the deleted models/groups):

- `litellmproxy.yaml` fallbacks: `qwen3.8-flash-next → 27B` and the reverse
  mapping die; `flash-next-chat` falls back to MiniMax only;
  `context_window_fallbacks` (27B→FN) dropped.
- Pools: `implementation-pool`'s 27B rung becomes the Strata rung (order 3);
  `grooming-pool` and `local-pool` muse rungs dropped (FN rungs remain).
- Virtual keys: `pr-review`, `pr-review-fork`, courier, dispatch, memini,
  alert-triage, repo-wiki allowlists repointed.
- App configs: opencode (`coder-local` → flash-next, model table), openclaw
  (fallback chains, aliases, catalog, family-safe rules, Sage/subagent
  primaries), hermes (fallback providers, `coder-local`), courier (rebase
  coordinator, lane profiles), courier-native (coordinator/reviewer roles),
  memini (`MEMINI_LLM_MODEL` → `qwen3.8-flash-next-chat`), dispatch (groomer
  context tokens → 245760).
- Docs: `docs/src/notes/coding-loop.md` and the llmkube README rewritten for
  the resident-Strata topology.

**Merge-time behavior (expected, not a failure):** Flux applies the deletions
and the new IS together. The strata-fn pod requests `gpu: 1` while the 27B pod
may still be terminating, so strata stays Pending until the 27B pod is gone
(`nvidia.com/gpu: 1` is exclusive — no time slicing). Strata then needs 4–8
minutes cold (hashing + load). Total cutover window ~10 minutes with the
litellm `qwen3.8-flash-next` group served by skirk throughout.

## Open questions for reviewers

1. **autoRegister interplay.** `litellm-operator` has
   `llmkube.autoRegister: true`, so the skirk IS auto-registers (no explicit
   CR, presumably no `order`). An explicit `order: 2` CR for Strata may or may
   not share load with an un-ordered auto deployment. Options: (a) verify
   litellm behavior empirically after merge; (b) add an explicit skirk CR at
   `order: 1`; (c) find an annotation to skip auto-registration.
2. **`modelRef` + `skipModelInit` with no downloader.** `modelRef` is required
   by the IS schema, so the manifest carries a `Model` stub. Confirm the Model
   controller stays quiet when `skipModelInit` is set and the named files are
   absent from its own cache layout (on skirk it logged "Runtime-resolved ...
   already Ready" and skipped — expect the same, but verify).
3. **Probe headers.** `probeOverrides.httpGet.httpHeaders` assumes the CRD
   passes headers through to the k8s Probe. If not, check whether Strata
   exposes an unauthenticated `/health` and switch the probes to it.
4. **`--vram-reserve-mib 768`.** The engine warned (<512 MiB free VRAM →
   possible driver paging, decode collapse) and suggested this flag, but
   `strata launch` does not expose it on the CLI. If needed, patch the
   generated run config in the wrapper command before the engine starts.
5. **Vision.** `--vision gpu` + BF16 mmproj are served (`input_modalities:
   ["text","image"]`) but no image was sent during the benchmark. Run one real
   image request through Strata before flipping `supportsVision: true` on the
   Strata CR (skirk's flash-next lane keeps vision in the group meanwhile).
6. **Mac muse endpoint.** This PR drops the muse group entirely, including the
   Mac LM Studio deployment in `models/muse-glimmer.yaml`. Confirm.
7. **Engine log volume.** Strata writes its engine log to
   `/data/state/strata/launch/*.engine.log` on the cache PVC; confirm rotation
   or log-noise growth over weeks.

Resolved during review: the ISTA-DASLab slug was verified against HF (public,
ungated, both shard paths present) and the image is now digest-pinned
(`sha256:db96cd9b…`, the amd64 manifest the benchmark ran).

## Post-merge watch items (first week)

- Saturation queueing: total FN concurrency is now 5 (2 skirk + 3 strata) vs
  the old 2 + 8 + muse mix. Bursts of 8+ parallel short tasks queue instead of
  spreading.
- Prefix-cache warm-up after any Strata redeploy (RAM-only cache).
- MTP acceptance rate and litellm cooldown/fallback counters.
- 27B model files on the cache PVC (`subPath vllm-27…`, ~28 GB) are reclaimable
  once the lane has a clean week.

## Rollback

Revert this PR. On re-apply, set `strata-fn` `replicas: 0` first (or let the
delete of the IS free the GPU), then the 27B/muse manifests come back from git
and Flux rebuilds them. The Strata packs stay on the PVC either way (~219 GB).

## Accepted trade-offs

- No Prometheus metrics from Strata itself; litellm per-deployment metrics and
  probes are the only telemetry.
- 5 concurrent FN sessions max (was 2 skirk + 8 vLLM 27B + muse).
- Single model family locally: a bad FN weights/engine update takes out all
  local capacity at once; cloud fallbacks (Z.AI / dsv4.1f groups) are the
  hedge. Pin the pack revision and keep the previous pack on disk for one
  clean week.
