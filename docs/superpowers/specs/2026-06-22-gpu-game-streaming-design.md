# GPU Game Streaming Design

## Scope

Deploy Games-on-Whales (Wolf + Fenrir) in `main/games` namespace with a Test Ball app, plus a hybrid GPU handoff watcher that manages GPU contention between game streaming and LLM inference. Steam launchers, Genshin Impact, and Honkai are explicitly out of scope; a future note may reference them.

## Architecture

### Games-on-Whales

- **Wolf** — The main container runtime. Handles session management, VR streaming, and app orchestration. Deployed via HelmRelease using the official GoW chart.
- **Fenrir** — Wolf's companion CRD controller. Manages custom resources (`Direwolf` sessions, `App` definitions). Requires CRDs applied before Wolf starts.
- **Test Ball** — Minimal first-party app included for smoke-testing the streaming pipeline end-to-end without requiring a full game asset.

### GPU Handoff Watcher

A lightweight watcher that monitors `Direwolf` session state and adjusts the `llama-nvidia` InferenceService replica count:

1. Detects active Direwolf sessions via the Kubernetes API.
2. Scales `llama-nvidia` replicas from 1 → 0 when sessions exist.
3. Waits for all sessions to go idle up to a configurable timeout (default 15 min).
4. Restores `llama-nvidia` replicas to 1 after sessions end and idle timeout elapses.

The watcher runs as a standard Deployment in the `games` namespace with RBAC to watch `Direwolf` CRDs and patch the `InferenceService`.

### File Layout

```
kubernetes/apps/base/games/
├── games-on-whales/
│   ├── kustomization.yaml
│   ├── ocirepository.yaml
│   ├── helmrelease.yaml
│   ├── fenrir-source.yaml        # Fenrir Helm chart OCI source
│   ├── fenrir-crds.yaml          # Pre-pulled CRD manifests
│   ├── user.yaml                 # Default user config
│   ├── apps.yaml                 # App definitions (Test Ball)
│   └── wolf-entrypoint.yaml      # Custom entrypoint overrides
├── gpu-handoff-watcher/
│   ├── kustomization.yaml
│   ├── ocirepository.yaml
│   ├── helmrelease.yaml
│   ├── configmap.yaml            # Timeout, InferenceService ref
│   └── rbac.yaml                 # Watch Direwolf, patch InferenceService

kubernetes/apps/main/games/
├── kustomization.yaml            # Add games-on-whales.yaml, gpu-handoff-watcher.yaml
├── games-on-whales.yaml          # Flux Kustomization overlay
└── gpu-handoff-watcher.yaml      # Flux Kustomization overlay
```

Optionally: `kubernetes/apps/base/llm/llmkube/models/qwen3.6-27b.yaml` may need a `priority` field adjustment to allow preemption during handoff.

## Handoff Behavior

| Condition | llama-nvidia replicas | Action |
|---|---|---|
| No active Direwolf sessions | 1 | Normal operation |
| New Direwolf session created | 0 → scale down | Immediate |
| Sessions exist, idle < timeout | 0 | Hold |
| All sessions ended, idle > timeout | 0 → 1 | Restore |

The watcher never scales llama-nvidia above its original replica count. It only scales to zero and back.

## Validation

- `flate test all --path ./kubernetes/clusters/main` — renders all Kustomizations + HelmReleases
- `git diff` review before push — verify no secrets, correct namespace injection, sorting rules followed
- Smoke-test: deploy Test Ball, verify streaming session, confirm llama-nvidia scales to 0, end session, wait for timeout, confirm restore

## Non-Goals

- Steam launcher support
- NonSteamLauncher integration
- Genshin Impact
- Honkai series games
- Multi-GPU handoff (single GPU assumption)
- Persistent volume provisioning for game assets (out of scope for initial PR)
