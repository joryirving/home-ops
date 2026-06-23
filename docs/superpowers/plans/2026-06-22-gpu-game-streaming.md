# GPU Game Streaming Implementation Plan
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
**Goal:** Deploy Games-on-Whales (Wolf + Fenrir) with Test Ball app and a GPU handoff watcher in the main cluster, enabling game streaming that yields the NVIDIA GPU to Direwolf sessions and restores LLM inference after idle timeout.
**Architecture:** Wolf/Fenrir in base/games, Flux Kustomization overlays in main/games. gpu-handoff-watcher watches Direwolf CRDs, scales llama-nvidia InferenceService to 0 during active sessions, restores after idle timeout.
**Tech Stack:** Games-on-Whales (shrinedogg/dsluo), Flux HelmRelease + OCIRepository, app-template for watcher, llmkube InferenceService API, Kubernetes RBAC.
---

## Prerequisites

- [ ] Verify Games-on-Whales chart version and CRDs against upstream (shrinedogg/dsluo pattern). Pull Fenrir CRDs to `fenrir-crds.yaml` before Wolf deploys.
- [ ] Confirm `llama-nvidia` InferenceService current replica count is 1 and `priority` field supports scaling to 0 without data loss.

## Base: Games-on-Whales

- [ ] Create `kubernetes/apps/base/games/games-on-whales/` directory
- [ ] Create `kustomization.yaml` — list all resources, no inline namespace
- [ ] Create `ocirepository.yaml` — pin Wolf chart by tag via OCIRepository named `games-on-whales`
- [ ] Create `fenrir-source.yaml` — separate OCI source for Fenrir chart (if not bundled with Wolf)
- [ ] Create `fenrir-crds.yaml` — static CRD manifests pulled from chart, applied before HelmRelease
- [ ] Create `helmrelease.yaml` — Wolf deployment via app-template or native GoW chart. Include Test Ball in `apps.yaml` or inline values. Follow repo sorting rules.
- [ ] Create `user.yaml` — default user config ConfigMap/Secret (use external-secrets for credentials)
- [ ] Create `apps.yaml` — App definitions including Test Ball
- [ ] Create `wolf-entrypoint.yaml` — any custom entrypoint or env overrides needed

## Base: GPU Handoff Watcher

- [ ] Create `kubernetes/apps/base/games/gpu-handoff-watcher/` directory
- [ ] Create `kustomization.yaml`
- [ ] Create `ocirepository.yaml` — app-template OCIRepository named `gpu-handoff-watcher`
- [ ] Create `configmap.yaml` — `INFERENCESERVICE_NAME=llama-nvidia`, `INFERENCESERVICE_NAMESPACE=llm`, `IDLE_TIMEOUT=900`, `WATCHER_NAMESPACE=games`
- [ ] Create `rbac.yaml` — Role + RoleBinding to watch `direwolf` CRDs in games ns, patch `inferenceservice` in llm ns (ClusterRole if cross-ns)
- [ ] Create `helmrelease.yaml` — app-template Deployment running the watcher script. Resource limits: 64Mi memory, 50m CPU.

## Main Cluster Overlay

- [ ] Create `kubernetes/apps/main/games/games-on-whales.yaml` — Flux Kustomization pointing to `./kubernetes/apps/base/games/games-on-whales`, with `postBuild.substitute.APP=games-on-whales`
- [ ] Create `kubernetes/apps/main/games/gpu-handoff-watcher.yaml` — Flux Kustomization pointing to `./kubernetes/apps/base/games/gpu-handoff-watcher`, with `postBuild.substitute.APP=gpu-handoff-watcher`
- [ ] Update `kubernetes/apps/main/games/kustomization.yaml` — add both resources to the list

## Optional: Priority Adjustment

- [ ] If needed, add `priority` field to `qwen3.6-27b.yaml` InferenceService spec to allow the watcher to scale replicas safely. Verify with llmkube docs.

## Validation

- [ ] Run `flate test all --path ./kubernetes/clusters/main` — must pass with no render errors
- [ ] Run `git diff` review — verify namespace injection via kustomization, no plain-text secrets, YAML sorting rules followed, OCIRepository per-app pattern correct
- [ ] Verify Fenrir CRDs are applied before Wolf HelmRelease (check kustomization resource order or HelmRelease dependsOn)

## Notes

- Follow shrinedogg/dsluo patterns for GoW config. Their docs and examples are the source of truth for Wolf/Fenrir interaction.
- Pull and verify chart CRDs before commit — don't rely on runtime CRD installation for Fenrir.
- The watcher must handle the case where llama-nvidia doesn't exist yet (cluster bootstrap race). Use a startup probe or init container that waits for the InferenceService CRD.
- First PR excludes Steam/NonSteamLaunchers/Genshin/Honkai. Add an `apps.yaml` comment noting these are future scope.
