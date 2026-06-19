# LLMKube

Kubernetes operator ([defilantech/LLMKube](https://github.com/defilantech/LLMKube)) for
self-hosted llama.cpp inference, running in the `llm` namespace. Replaces the
hand-rolled app-template HelmReleases for GPU model serving.

A model is two CRs — a **`Model`** (where the weights come from + hardware
target) and an **`InferenceService`** (the serving pod: llama.cpp args, GPU,
probes, endpoint) — one file per model under `models/`:

```
llmkube/
  helmrepository.yaml   helmrelease.yaml   kustomization.yaml   # the operator
  models/
    kustomization.yaml        # lists the active model files + the shared ServiceMonitor
    servicemonitor.yaml       # one SM scrapes every InferenceService (job = service name)
    qwen3.6-27b.yaml          # Model + InferenceService (RTX 3090)
```

All models reconcile under a single `llmkube-models` Flux Kustomization
(`apps/main/llm/llmkube.yaml`, `dependsOn: llmkube`).

## How weights are sourced

The `Model.spec.source` scheme decides what the operator does. Three modes:

| `source` | What happens | Persistence |
| --- | --- | --- |
| `pvc://<claim>/<path>.gguf` | Mounts the claim **read-only**. No download. | You staged it |
| `https://…/<file>.gguf` | Init container `curl`s it into the **shared cache PVC** (`llmkube-model-cache`, CephFS RWX) on first start; skipped thereafter | Persistent, survives restarts |
| `<org>/<repo>` (bare HF id) | **vLLM runtime only** — not used by the llama.cpp runtime | — |

> ⚠️ The cache (`modelCache` in `helmrelease.yaml`) **must stay enabled** for
> `https://` sources. With it disabled, downloads fall back to an ephemeral
> `emptyDir` and re-pull the full model on every pod restart.

## Adding a new model

Drop one file in `models/` (a `Model` + `InferenceService`, mirror
`models/qwen3.6-27b.yaml`) and add it to `models/kustomization.yaml`. No new
folder, no Flux Kustomization — the operator and the existing `llmkube-models`
Kustomization pick it up.

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
          envFrom: [{ secretRef: { name: huggingface } }]  # for gated repos
          volumeMounts: [{ name: models, mountPath: /models }]
      volumes:
        - name: models
          persistentVolumeClaim: { claimName: llmkube-models }
```

For Ceph PVC sources, remember `--no-mmap` (cold-fault rule) in the
`InferenceService.spec.extraArgs`.

## Continuity notes

- Keep each model's `InferenceService.metadata.name` == the old Service name so
  LiteLLM routing and the prometheus `job` label stay stable.
- Carry our own `ServiceMonitor` (selector `inference.llmkube.dev/service`); the
  operator's PodMonitor is disabled so the `job` label keeps matching the
  openclaw idle-watcher.
