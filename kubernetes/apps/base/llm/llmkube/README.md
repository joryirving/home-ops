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
  project-maya.yaml              # GLM-5.3-Flash S24 (Maya engine) on the RTX 3090
  qwen3-8-flash-next-strata.yaml  # Qwen3.8-Flash-Next IQ3_S (Strata engine), stopped
  qwen3-8-flash-next-gufo.yaml    # Qwen3.8-Flash-Next UD-Q4_K_XL on Strix Halo (gufo, multimodal)
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
| `hf://<org>/<repo>` + `spec.files`  | Downloads each listed file from the repo into the model cache; `spec.mmproj` names the projector among them (`qwen3-8-flash-next-strata`, `qwen3-8-flash-next-gufo`) | Persistent, survives restarts |
| `https://…/<file>.gguf`             | Init container `curl`s one file into the **shared cache PVC** (`llmkube-model-cache`, CephFS RWX) on first start; skipped thereafter     | Persistent, survives restarts |
| `pvc://<claim>/<path>.gguf`         | Mounts the claim **read-only**. No download. The claim must exist first. `project-maya-glm-5-3-flash-s24` uses it: Maya downloads its own weights, so the operator only needs a `Model` to hang the service on | You staged it                 |
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

## The 3090: Maya (GLM-5.3-Flash S24)

The egpu / RTX 3090 (ganyu) hosts a single resident service,
`project-maya-glm-5-3-flash-s24` (`litellm/project-maya.yaml`): Project Maya's
own `maya` engine (`ghcr.io/joryirving/maya`) running GLM-5.3-Flash S24 at 131K
context with GPU vision. It took the card over from Strata (Qwen3.8-Flash-Next
IQ3_S), which is stopped but still in git.

Key properties:

- `runtime: generic` + `skipModelInit: true`: the pod runs upstream's own
  `maya.py --setup`. It downloads the model shards and the vision encoder's
  mmproj/vocab from HuggingFace into the `project-maya-ganyu-data` PVC
  (`/data`: ~95 GB shards, ~1 GB pack, ~1 GB vision files), builds the pack,
  writes the config in `/opt/maya` and starts the server. Nothing is compiled
  in the pod: the image carries the engine and the encoder with upstream's
  stamps, so setup's build steps skip.
- The setup is idempotent: a pod that finds the config and the pack starts the
  server and downloads nothing. The first start needs hours (download, pack,
  load), so the startup probe budget is hours, not minutes.
- Images: GLM-5.3-Flash's vision tower reads pictures through the `maya-vision`
  encoder (server-side, on demand; the engine lends it VRAM). The engine takes
  the image embeddings, so it needs no `--vision` flag — that spelling belongs
  to the Qwen/DeepSeek/MiniMax engines and it would kill the GLM engine.
- `ulimit -l unlimited` + `CAP_SYS_RESOURCE`: the engine pins the model's RAM
  tier with mlock.
- `MAYA_EXPERT_RAM_GB=64`: the RAM tier's cap (upstream's recommendation for
  this quant on a 24 GB card), so the pinned arena stays inside the pod's
  80Gi limit.
- LiteLLM route `glm-5.3-flash-local` (`litellm/models/project-maya.yaml`),
  kept apart from the cloud GLM route. The engine's 131072 context is split
  into 122880 input and 8192 output tokens.

Rollback: Strata's manifests stay in git with `replicas: 0` and its packs stay
on the `llmkube-ganyu-cache` PVC (~219 GB); set `qwen3-8-flash-next-strata`
`replicas: 1` and stop Maya to put Qwen3.8-Flash-Next IQ3_S back on the card.

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
