# LLMKube

Kubernetes operator ([defilantech/LLMKube](https://github.com/defilantech/LLMKube)) for
self-hosted llama.cpp inference, running in the `llm` namespace. Replaces the
hand-rolled app-template HelmReleases for GPU model serving.

A model is two CRs — a **`Model`** (where the weights come from + hardware
target) and an **`InferenceService`** (the serving pod: llama.cpp args, GPU,
probes, endpoint). The CRDs are cluster-wide, so each model's two CRs live **in
the folder of the app that consumes it**, not under `llmkube/`:

```
llmkube/                    # the operator + shared cluster infra only
  ocirepository.yaml  helmrelease.yaml  kustomization.yaml   # the operator
  priorityclass.yaml        # gpu-preemptible (3090 yields to game sessions)
  resourceclaim.yaml        # llama-strix-gpu RCT, shared by the Strix models
  servicemonitor.yaml       # one SM scrapes every InferenceService (job = service name)

memini/                     # Intel iGPU helpers, reconciled by the `memini` KS
  memini-embed.yaml  memini-rerank.yaml  memini-summary.yaml

litellm/app/                # chat/vision models, reconciled by the `litellm` KS
  llama-nvidia.yaml         # Qwen3.6-27B on RTX 3090
  llama-strix.yaml          # Ornith-1.0-35B on Strix Halo
  llama-vision.yaml         # Qwen3.5-4B on Strix Halo (multimodal)

toolhive/config/            # per-app tenant model, reconciled by `toolhive-config`
  toolhive-embed.yaml       # Qwen3-Embedding-0.6B on Intel iGPU (was a TEI EmbeddingServer CRD)
```

Each consuming app's own Flux Kustomization reconciles its models (`memini`,
`litellm` in `apps/main/llm/`); there is no dedicated `llmkube-models`
Kustomization. The CRDs come from the `llmkube` operator, so those apps assume
it's already reconciled (no explicit `dependsOn`).

## How weights are sourced

The `Model.spec.source` scheme decides what the operator does. Three modes:

| `source`                    | What happens                                                                                                                   | Persistence                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------- |
| `pvc://<claim>/<path>.gguf` | Mounts the claim **read-only**. No download.                                                                                   | You staged it                 |
| `https://…/<file>.gguf`     | Init container `curl`s it into the **shared cache PVC** (`llmkube-model-cache`, CephFS RWX) on first start; skipped thereafter | Persistent, survives restarts |
| `<org>/<repo>` (bare HF id) | **vLLM runtime only** — not used by the llama.cpp runtime                                                                      | —                             |

> ⚠️ The cache (`modelCache` in `helmrelease.yaml`) **must stay enabled** for
> `https://` sources. With it disabled, downloads fall back to an ephemeral
> `emptyDir` and re-pull the full model on every pod restart.

## Adding a new model

Drop the `Model` + `InferenceService` file into the **consuming app's** folder
and add it to that app's `kustomization.yaml` — `memini/` for the Intel iGPU
helpers, `litellm/app/` for the chat/vision models, `toolhive/config/` for
per-app embedding tenants. No new folder, no Flux Kustomization — the operator
and the app's existing Kustomization pick it up.

GPU access depends on the target:

- **Intel iGPU** — the consuming KS must pull in `components/gpu`, which
  generates a `${APP}-gpu` ResourceClaimTemplate. Reference it as the model's
  `resourceClaimTemplateName` (e.g. `memini-gpu`, `toolhive-config-gpu`).
- **AMD Strix** — reference the shared `llama-strix-gpu` template
  (`llmkube/resourceclaim.yaml`).
- **NVIDIA** — no claim; request `gpu: { count: 1 }` on the hardware block.

## The 3090: single always-on tenant

The egpu / RTX 3090 runs one `InferenceService` permanently — `llama-nvidia`
(Qwen3.6-27B, `replicas: 1`). It serves the `nvidia` coding model and acts as a
LiteLLM fallback for `self-hosted`.

There's no burst-swap (the old `burst-watcher` + `llama-nvidia-gemma` were
retired): the card holds one model, so spinning a second up meant tearing Qwen
down — too slow, and it took `nvidia` offline for too long. The card stays warm
for `nvidia` traffic throughout.

### Option A — let the operator download it (preferred for new models)

Point `source` at the **direct GGUF resolve URL** (not the repo id — the
llama.cpp init container `curl`s a single file):

```yaml
apiVersion: inference.llmkube.dev/v1alpha1
kind: Model
metadata:
    name: my-model
spec:
    source: https://huggingface.co/unsloth/<Repo>-GGUF/resolve/main/<File>.gguf
    format: gguf
    quantization: Q4_K_XL
    hardware:
        accelerator: gpu
        gpu: { enabled: true, vendor: nvidia, count: 1, layers: 99 }
```

On first reconcile the init container downloads into the shared CephFS cache;
later restarts reuse it. To re-pull after an upstream change, set
`spec.refreshPolicy: OnChange` (ETag revalidation each reconcile) — otherwise a
cached file is kept forever. Changing the `source` URL forces a fresh download
(the cache key is derived from the URL).

**Caveats**

- **No HF token** in this path — works for public GGUFs (unsloth, mradermacher).
  Gated/private repos must be pre-staged (Option B).
- **Single file only.** Multimodal models needing a separate `mmproj-*.gguf`
  can't be expressed as one `source` — pre-stage them (Option B).

### Option B — pre-stage on Ceph, then reference it

Use this for gated models, multi-file/vision models, or weights you already
have on `llmkube-models`. Download out of band, then:

```yaml
spec:
    source: pvc://llmkube-models/<dir>/<File>.gguf
```

A one-off download Job (same pattern as the old `model-download` initContainer):

```yaml
apiVersion: batch/v1
kind: Job
metadata:
    name: stage-my-model
spec:
    template:
        spec:
            restartPolicy: OnFailure
            containers:
                - name: hf
                  image: python:3.14-slim
                  command: ["/bin/sh", "-ec"]
                  args:
                      - |
                          pip install --no-cache-dir "huggingface_hub[hf_xet]"
                          hf download <org>/<repo> <File>.gguf --local-dir /models/<dir>
                  envFrom: [{ secretRef: { name: huggingface } }] # for gated repos
                  volumeMounts: [{ name: models, mountPath: /models }]
            volumes:
                - name: models
                  persistentVolumeClaim: { claimName: llmkube-models }
```

For Ceph PVC sources, remember `--no-mmap` (cold-fault rule) in the
`InferenceService.spec.extraArgs`.

## Continuity notes

- Name each `InferenceService` after its **consumer** (e.g. `memini-embed` for
  memini, `toolhive-embed` for toolhive-config). The prometheus `service` label
  on `llamacpp:*` metrics comes from the generated `Service`, so updating it
  also means updating any `service!="…"` filters in dashboards. Litellm routes
  follow `api_base` in the configmap, not the InferenceService name.
- Carry our own `ServiceMonitor` (selector `inference.llmkube.dev/service`); the
  operator's PodMonitor is disabled so the `job` label keeps matching the
  openclaw idle-watcher.
