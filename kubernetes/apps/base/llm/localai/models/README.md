# LocalAI Model Catalog

This directory manages LocalAI model definitions and artifact sync jobs with Flux.

## Structure

- `<model>.yaml`: one file per model containing both the model ConfigMap and sync Job.
- `externalsecret.yaml`: creates `localai-secret` with `HF_TOKEN` from the existing `openclaw` 1Password item and `OPENAI_API_KEY` from the `localai` item.

## Managed Models

- `qwen3_5_9b`: downloads `Qwen3.5-9B-heretic.Q4_K_M.gguf` and `mmproj-F16.gguf` into `/models/qwen-vision`.
- `gemma4_e4b`: downloads `gemma-4-E4B-it-UD-Q4_K_XL.gguf` into `/models/memory`.

## How To Add A Model

1. Add a new `<model>.yaml` file containing a model ConfigMap and sync Job.
2. Configure the sync Job to download artifacts into `/models` on the `localai` PVC.
3. Copy the model config file from `/config` to `/models` after download.
4. Add the new file to `kustomization.yaml`.

## Notes For Intel iGPU

- Keep `mmap: false` in model configs for stability.
- Tune `gpu_layers`, `threads`, and `context_size` per model after testing.
- LocalAI supports GPT Vision with llama.cpp/LLaVA-style configs. Multimodal models need a compatible projection file configured with top-level `mmproj`.
