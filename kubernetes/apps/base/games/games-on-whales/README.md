# Games-on-Whales (Wolf + Fenrir)

GPU game streaming on ganyu's RTX 3090, sharing the GPU with `llama-nvidia`.

## What works

- **GPU time-slicing** — the 3090 advertises `nvidia.com/gpu: 2`
  (`kube-system/nvidia-device-plugin`).
- **PriorityClass preemption** — `llama-nvidia` runs at `gpu-preemptible`
  (-100); launching a session preempts it to free the GPU, and it reloads when
  the session ends. Validated live: a Steam session evicted `llama-nvidia`.
- Wolf starts, pairs over Moonlight, negotiates HEVC, and (once it has a render
  node) detects the NVIDIA GPU for its zero-copy pipeline.

## What does NOT work yet: video streaming (blocked on the NVIDIA DRA driver)

Sessions start and preempt the LLM, but **no video is produced**. The root
cause is upstream, not in this repo.

This cluster accesses the NVIDIA GPU via the **DRA driver**
(`kubernetes-sigs/dra-driver-nvidia-gpu`). Its generated CDI spec injects the
GPU *compute* userspace (CUDA etc.) but **not the graphics/display userspace
stack** — `libEGL_nvidia`, `libGLX_nvidia`, the nvidia GBM backend, and the
EGL/Vulkan ICDs. Wolf's wayland compositor (smithay) therefore falls back to
Mesa, which cannot initialize EGL on the proprietary NVIDIA render node:

```
libEGL warning: egl: failed to create dri2 screen
MESA: error: ZINK: failed to choose pdev
panicked: Failed to create EGLDisplay: InitFailed(NotInitialized)
```

### Why it's a DRA-driver gap, specifically

- The nvidia-container-toolkit *can* inject those graphics libraries as of
  v1.18.0 (https://github.com/NVIDIA/nvidia-container-toolkit/pull/1354,
  closing dra-driver issue #446), but #1354 made it **opt-in**: the consumer
  must set the feature flag when instantiating `nvcdi`.
- The DRA driver does **not** opt in. In `cmd/gpu-kubelet-plugin/cdi.go`,
  `NewCDIHandler` calls `nvcdi.New(...)` with only
  `nvcdi.WithFeatureFlags(nvcdi.FeatureDisableNvsandboxUtils)` — no
  graphics/explicit-libraries flag.
- It is a compile-time decision in the driver. There is **no** Helm value, env
  var, kubelet-plugin arg, or claim/device-config field to flip — so it cannot
  be enabled from this repo.

## Findings for whoever revisits this

Confirmed by inspecting a live `wolf` container (with a temporary
`hostPath: /dev/dri` + `privileged` workaround that is intentionally NOT in
these manifests):

1. **Two GPUs on ganyu.** `/dev/dri/renderD128` is the **Intel iGPU** (`xe`
   driver); `/dev/dri/renderD129` is the **NVIDIA 3090**. The `renderNode`
   values in `apps.yaml` are inherited from an upstream example (`renderD128`)
   and are wrong for this node — but wolf auto-detected the NVIDIA node
   (`renderD129`) anyway, so `renderNode` may be better removed than hardcoded
   (the Intel/NVIDIA node numbering can swap across reboots).
2. **`/dev/dri` is not injected under DRA**; a `hostPath` mount + `privileged`
   on the `wolf` sidecar makes the device nodes appear and clears the first
   panic — but the graphics-libs gap above is the real wall, so that workaround
   alone still produces no video.

## To unblock (future), in order of preference

1. **Wait for / file an upstream change** so the DRA driver opts into graphics
   library injection (add the flag to the `nvcdi.New(...)` call in `cdi.go`, or
   make it configurable) — `kubernetes-sigs/dra-driver-nvidia-gpu`. Then verify
   `renderNode` / device injection on ganyu and retest. (This is the chosen
   path: prep and wait.)
2. Run a patched DRA-driver image that sets the flag (maintains a fork).
3. `hostPath`-mount the host's nvidia GL/EGL/GBM libs + ICD JSONs into `wolf`
   alongside `/dev/dri` (brittle, version-coupled to the host driver).
4. Take the `wolf` pods off DRA and onto the GPU Operator / device-plugin
   graphics path (injects the full driver userspace; cuts against running
   everything on DRA).

The HelmRelease, User, and App manifests are otherwise complete and ready.
