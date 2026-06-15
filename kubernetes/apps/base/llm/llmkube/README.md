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
    qwen3.6-27b.yaml          # Model + InferenceService
    gemma-4-26b-a4b.yaml
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

## The 3090: default tenant + pressure burst

The single egpu / RTX 3090 has two `InferenceService`s, distinguished by
`priority` so the scheduler arbitrates the one card:

- `llama-nvidia` (Qwen3.6-27B) — `replicas: 1`, priority `normal`. Default
  tenant: the `nvidia` coding model, also a LiteLLM backfill for `self-hosted`.
- `gemma-review` (Gemma-4-26B-A4B) — `replicas: 0`, priority `high`. The review
  burst capacity, downloaded on demand (`refreshPolicy: OnChange`).

`burst-watcher/` polls `llamacpp:requests_deferred{job="llama-review"}`. When the
ROCm review model stays backed up, it scales `gemma-review` `0→1` only after
`llama-nvidia` is idle, avoiding interruption of in-flight Qwen work. When the
queue drains (after `MIN_UP_SECONDS`), it scales back to `0` only after
`gemma-review` is idle, then Qwen can continue as the default 3090 tenant.
LiteLLM has `gemma-review` as an `order: 3` backfill in the `review` group, so
traffic spreads to it once it's up.

While a review burst is active the 3090's coding (`nvidia`) and the `self-hosted`
backfill are unavailable — that's the cost of one card serving review instead.

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
              pip install --no-cache-dir "huggingface_hub[hf_transfer]"
              hf download <org>/<repo> <File>.gguf --local-dir /models/<dir>
          env: { HF_HUB_ENABLE_HF_TRANSFER: "1" }
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
