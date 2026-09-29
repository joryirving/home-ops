# Games-on-Whales (Wolf + Fenrir)

GPU game streaming on skirk's Strix Halo iGPU, via the direwolf operator.

**Not deployed.** `./games-on-whales.yaml` is commented out in
`kubernetes/apps/main/games/kustomization.yaml`. Skirk runs GoW or flash-next,
not both: #10278 (2026-09-17) suspended flash-next to bring GoW up on skirk,
and 8afc51df1 the same day turned GoW off and brought flash-next back. It never
streamed video on skirk.

## Shape

- **Operator**: `direwolf-operator` chart (pinned OCI tag + digest) with the
  `shrinedogg` operator, wolf, wolf-agent and moonlight-proxy images.
- **CRDs**: the `fenrir-crds` Flux Kustomization applies `./crds` from the
  `fenrir` `GitRepository`, pinned to a commit
  (`kubernetes/apps/main/games/games-on-whales.yaml`); `games-on-whales`
  depends on it.
- **GPU**: every `App` (`apps.yaml`) claims the `gow-amd-gpu`
  ResourceClaimTemplate (`resourceclaim.yaml`: `gpu.amd.com`, `adminAccess`,
  `allocationMode: All`) and tolerates the `llm-workload` taint.
- **Wolf sidecar** (`user.yaml`): `hostPath` mounts of `/dev/dri` and
  `/dev/kfd`, `privileged`. The entrypoint is shadowed by
  `wolf-entrypoint.yaml` so wolf starts as root (see the comment in
  `user.yaml`).
- **Render node**: `renderD128` in `apps.yaml` is correct for skirk; the
  `gpu.amd.com` driver injects `card1` + `renderD128` (per the comment there).
- **Moonlight**: the chart's `app` Service on Cilium LB IP `10.69.10.43`,
  sharing key `direwolf`, matching the operator's `--lb-sharing-key=direwolf`.
- **User**: `alex` (upstream hardcodes the name; do not rename).

## History

GoW first ran on ganyu's RTX 3090, sharing it with the LLM. It stopped
deploying on 2026-09-10 (19a4d9fa5) when the device plugin stopped
time-slicing the card for the `nvidia` `ModelPool`: a Wolf session needs two
GPU grants (the `wolf` pod plus the app pod), and the card now advertises one.
Video streaming on the 3090 had also never worked under the NVIDIA DRA driver,
whose CDI spec injects the compute userspace but not the graphics/EGL stack
Wolf's compositor needs. It moved to skirk's AMD iGPU on 2026-09-17 (#10278,
#10280, #10281). Git history has the NVIDIA-era version of this page.
