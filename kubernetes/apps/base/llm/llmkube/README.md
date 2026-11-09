# LLMKube

Kubernetes operator ([defilantech/LLMKube](https://github.com/defilantech/LLMKube)) for
self-hosted inference (llama.cpp, vLLM, and generic custom runtimes such as
gufo), running in the `llm` namespace. Replaces the hand-rolled app-template
HelmReleases for model serving.

A model is two CRs — a **`Model`** (where the weights come from + hardware
target) and an **`InferenceService`** (the serving pod: runtime args, GPU,
probes, endpoint). The CRDs are cluster-wide, so each model's two CRs live **in
the folder of the app that consumes it**, not under `llmkube/`:

```
llmkube/                    # the operator + shared cluster infra only
  ocirepository.yaml  helmrelease.yaml  kustomization.yaml   # the operator
  priorityclass.yaml        # gpu-preemptible (value -100), used by GPU inference pods
  resourceclaim.yaml        # llama-strix-gpu RCT (Strix models); llama-intel-gpu RCT (unused)

embed/                      # Qwen3-Embedding-0.6B on CPU, served to LiteLLM as `embed`
  model.yaml                # the Model
  embed-{1,2,3}.yaml        # three single-replica InferenceServices

memini/                     # bge-reranker-v2-m3 on CPU, served to LiteLLM as `rerank`
  memini-rerank.yaml        # the Model
  memini-rerank-{1,2,3}.yaml  # three single-replica InferenceServices

litellm/                    # chat/vision models, reconciled by the `litellm` KS
  strata-fn.yaml                  # Qwen3.8-Flash-Next IQ3_S (Strata engine) on the RTX 3090
  qwen3.8-flash-next.yaml         # Qwen3.8-Flash-Next UD-Q4_K_XL on Strix Halo (gufo, multimodal)
  llmkube-skirk-cache.yaml        # local-hostpath model cache PVC on skirk
  models/                         # LiteLLMModel CRs, grouped by model name
  # plus commented-out variants in kustomization.yaml (Strix swap-backs, gemma-4-e4b, ...)
```

Each consuming app's own Flux Kustomization reconciles its models (`embed`,
`memini`, `litellm` in `apps/main/llm/`); there is no dedicated
`llmkube-models` Kustomization. Each of those KSs has `dependsOn: llmkube`, so
the CRDs exist before the models apply.

## How weights are sourced

The `Model.spec.source` scheme decides what the operator does:

| `source`                            | What happens                                                                                                                              | Persistence                   |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| `hf://<org>/<repo>` + `spec.files`  | Downloads each listed file from the repo into the model cache; `spec.mmproj` names the projector among them (`strata-fn`, flash-next) | Persistent, survives restarts |
| `https://…/<file>.gguf`             | Init container `curl`s one file into the **shared cache PVC** (`llmkube-model-cache`, CephFS RWX) on first start; skipped thereafter     | Persistent, survives restarts |
| `pvc://<claim>/<path>.gguf`         | Mounts the claim **read-only**. No download. Not used today; the claim must exist first                                                   | You staged it                 |
| `<org>/<repo>` (bare HF id)         | **vLLM runtime only.** the image entrypoint pulls `HF_REPO` into the shared cache (subPath per model). No vLLM model remains in the repo today; historical | Persistent, survives restarts |

Single-file `https://` sources are still used by the CPU models
(`embed/model.yaml`, `memini/memini-rerank.yaml`). The gufo flash-next
InferenceService sets `skipModelInit: true` and reads its Model's files from
the skirk cache by path, so it relies on them already being there.

> The cache (`modelCache` in `helmrelease.yaml`) **must stay enabled** for
> downloaded sources. With it disabled, downloads fall back to an ephemeral
> `emptyDir` and re-pull the full model on every pod restart.

## Adding a new model

Drop the `Model` + `InferenceService` file into the **consuming app's** folder
and add it to that app's `kustomization.yaml` — `litellm/` for chat/vision
models, `embed/` or `memini/` for the CPU embedding/rerank pools. No new
folder, no Flux Kustomization — the operator and the app's existing
Kustomization pick it up.

Hardware access depends on the target:

- **CPU** — `accelerator: cpu`, no claim. Pass `--flash-attn "on"` and
  `--load-mode mmap` in `extraArgs`, and spread replicas with a
  `podAntiAffinity` on a pool label (see `embed/`, `memini/`).
- **Intel iGPU** — the consuming KS must pull in `components/gpu`, which
  generates a `${APP}-gpu` ResourceClaimTemplate to reference as the model's
  `resourceClaimTemplateName`. The `memini` and `toolhive-config` KSs still
  include the component, but no model uses it today.
- **AMD Strix** — reference the shared `llama-strix-gpu` template
  (`llmkube/resourceclaim.yaml`). Skirk models set
  `spec.modelCache.claimName: llmkube-skirk-cache` on the InferenceService to
  use the node-local cache instead of CephFS; gufo (`runtime: generic`,
  `skipModelInit: true`) mounts that PVC directly.
- **NVIDIA** — no claim; request `gpu: { count: 1 }` on the hardware block.

Runtime notes (LLMKube 0.9.30):

- `spec.flashAttention` is only rendered when the model has a GPU. CPU pods
  need `--flash-attn "on"` in `extraArgs` instead.
- The operator adds `--alias <modelRef>` to llama.cpp automatically, so the
  served name is the `modelRef`. Don't add `--alias` to `extraArgs`.
  Non-llama.cpp runtimes set it themselves (e.g. gufo `--served-model-name`).
- GPU llama.cpp models use `--load-mode none`; CPU models use
  `--load-mode mmap`. (No GPU llama.cpp model remains resident today.).

### Option A — let the operator download it (preferred)

Point `source` at the HF repo and list the files to fetch:

```yaml
apiVersion: inference.llmkube.dev/v1alpha1
kind: Model
metadata:
    name: my-model
spec:
    source: hf://unsloth/<Repo>-GGUF
    sourceSecretRef:
        name: huggingface
    files:
        - <File>.gguf
        - mmproj-<...>.gguf
    mmproj: mmproj-<...>.gguf
    format: gguf
    quantization: Q4_K_XL
    hardware:
        accelerator: cuda
        gpu: { enabled: true, vendor: nvidia, count: 1, layers: 99 }
```

On first reconcile the files download into the model cache; later restarts
reuse them. To re-pull after an upstream change, set
`spec.refreshPolicy: OnChange` (ETag revalidation each reconcile) — otherwise a
cached file is kept forever. Changing the `source` forces a fresh download
(the cache key is derived from it).

`spec.sourceSecretRef: {name: huggingface}` makes the downloader send the
`HF_TOKEN` from the `huggingface` Secret (litellm ExternalSecret) as a bearer
on huggingface.co requests: gated repos work and authenticated pulls skip the
anonymous rate limits. The token is never forwarded off huggingface.co.
Together with `files:`, that covers gated and multi-file/vision models, so
there is no pre-staging path.

## The 3090: Strata (Flash-Next IQ3_S)

The egpu / RTX 3090 (ganyu) hosts a single resident service, `strata-fn`
(`litellm/strata-fn.yaml`): the Strata engine (`ghcr.io/niko1221/strata`)
running Qwen3.8-Flash-Next IQ3_S at 256K context with MTP and GPU vision. The
former `nvidia` `ModelPool` + `ModelRouter` (muse-glimmer / qwen3.8-27b
swapping) was retired when Flash-Next took over all 3090 traffic — no swapping
happens any more; the card has one always-resident workload.

Key properties:

- `runtime: generic` + `skipModelInit: true`: the packs are pre-staged on the
  `llmkube-ganyu-cache` PVC (`/data/Strata-data`, ~84 GB IQ3_S + ~5 GB MTP
  draft) and the pod command is a `strata launch` wrapper that supervises the
  engine and exits (pod restart) if it dies. Do not set `FAMILY`/`MODEL` env
  vars on this pod — Strata lets env override CLI flags and silently reverts
  to the wrong pack.
- Cold start is 4-8 minutes (hashing + load); the startup probe budget reflects
  that. The prefix cache is RAM-only: after any restart or redeploy, early
  requests pay full prefill until it warms. Schedule redeploys off-peak.
- The engine serves the model under the name `qwen3.8-flash-next-iq3_s`
  (not CLI-renamable), so it cannot join the `qwen3.8-flash-next` group via
  litellm-operator auto-registration; it has an explicit `LiteLLMModel` CR in
  `litellm/models/` instead (same pattern as the old muse CRs), pointing at
  `strata-fn.llm.svc.cluster.local` directly.
- LiteLLM caps it at `max_parallel_requests: 3` (three concurrent sessions,
  measured ~80 tok/s aggregate at saturation; ~1040 tok/s fresh prefill flat to
  232K, cached-prefix TTFT 0.32-0.6 s at 16K).
- The engine warned about low free VRAM (<512 MiB) and suggested
  `--vram-reserve-mib 768`; `strata launch` does not expose that flag. If
  decode throughput degrades, patch the generated run config in the wrapper
  command before the engine starts.

Rollback: the muse-glimmer and qwen3.8-27b packs and manifests live in git
history; re-apply the manifests, set `strata-fn` `replicas: 0`, and the 24 GiB
card frees up. The Strata packs stay on the PVC either way (~219 GB total).

## Continuity notes

- Name each `InferenceService` after its **consumer** where it is single-tenant;
  a model shared across consumers gets a neutral app instead: `embed`
  (`apps/base/llm/embed`, three single-replica InferenceServices `embed-1/2/3`
  pooled in LiteLLM as `embed`) that both memini and toolhive-config depend
  on. `memini-rerank-1/2/3` has the same shape, pooled as `rerank`. HAZARD:
  memini gates embedding compatibility on the `MEMINI_EMBED_MODEL`
  name and FATALS at startup if it differs from the name the store was created
  under — even when the model and dims are identical (it does not compare vectors).
  So ANY change to that value (a rename, or a real model/dim swap) requires
  `MEMINI_REEMBED_ON_MODEL_CHANGE: true`, which re-embeds the store at startup;
  it is set true. An upstream fix has been requested in memini. The `service`
  label on `llamacpp:*` metrics is the pod's `inference.llmkube.dev/service`,
  relabeled on by the PodMonitor, so renaming a service means updating any
  `service=~`/`service!~` filters in the dashboards. LiteLLM routes follow
  `params.apiBase` in the `LiteLLMModel` CRs in `litellm/models/` (or the
  operator's auto-projection), not the InferenceService name.
- Metrics come from the operator's PodMonitor
  (`prometheus.inferencePodMonitor.enabled: true`), which relabels
  `inference.llmkube.dev/{service,model,runtime}` onto every series. There's no
  hand-rolled ServiceMonitor anymore (retired with the idle-watcher). Pod and
  Service monitors both attach per-pod `pod`/`instance` labels, so the dashboards
  aggregate `by (service)` to keep a pod restart from fanning out into a new line
  per pod.
