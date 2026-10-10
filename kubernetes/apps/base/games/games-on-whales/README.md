# Games-on-Whales DRA trial

A single-node streaming trial for Firefox, Steam, and Test Ball on Skirk's
Strix Halo GPU, using
[axolotlite's installation examples](https://github.com/axolotlite/fenrir/tree/3f75c1aa5e69f2370ea31b6e2cf10c406ad97abb/examples).
[Upstream PR #49](https://github.com/games-on-whales/fenrir/pull/49) is still a draft.

**Disabled for review:** `./games-on-whales.yaml` remains commented out in
`kubernetes/apps/main/games/kustomization.yaml`. These are explicitly selected
unreleased test artifacts, not a production version upgrade. No live deployment
or successful stream has been verified.

## Deployment

The existing app-template chart manages three Deployments: operator,
Moonlight proxy, and Wolf with its DRA agent. The fork's own chart still uses the
older deployment model. CRDs come from the fork at commit
`3f75c1aa5e69f2370ea31b6e2cf10c406ad97abb`; `fenrir-crds` does not prune CRDs,
so disabling this trial cannot delete their stored objects through Flux.

Published example artifacts were checked for anonymous pull access and amd64:

| Component | Source revision | Image digest |
| --- | --- | --- |
| Wolf DRA agent | `d9d7fd62c71b152b622920b6685d93e75f24cd06` | `a4f3056abea36c185ec6a5320ce880e6dc4a57a6dd1b64181008bb5048154553` |
| Operator | `df237935ff52b77d3ffeb984d488e67fd41d194d` | `c7adba8ba7d8143221b7f57fcd8bedb77d74ee592f17a007a7a30273dfc540a6` |
| Moonlight proxy | `ec705eade00c898f53aef9394a621715d6a3eea8` | `d749125271e5a6fb69cb39e23c39e5367c31f5e46dea397e64a1fe103341ad73` |
| Wolf | `d6d41dec9cf758b086768e19a7dc02c20ffce22c` | `ff82c125c9b79b2e9443de2b0eaec40c904edb03291680d408cccd57c1d59c76` |

The Wolf agent, Wolf, and all three apps reference one `gow-amd-gpu` ResourceClaim
with administrative access. This avoids competing exclusive allocations with
existing GPU consumers. The `games` namespace already permits administrative
DRA claims. This provides shared device access, **not** memory or compute
isolation; Skirk's LLM workloads can still contend with video encoding.

`gow-wolf` selects the new `wolf.dra.io` driver and configures `renderD128`.
The operator adds a separate lobby claim to each application container; CDI
injects the Wayland and PulseAudio sockets. The driver writes CDI files to
Talos's `/run/cdi` and mounts kubelet plugin/registration directories.
Both agent containers claim the GPU because the agent also checks render-node
paths when processing lobby configuration.

Wolf runs privileged for this trial, but mounts neither `/dev/uinput` nor
`/dev/input`. In the pinned Wolf build, lobby keyboard and mouse input go
through `WaylandKeyboard` and `WaylandMouse`, so this keyboard/mouse-only trial
needs no uinput extension or Talos configuration change. Virtual gamepads and
fallback input emulation are outside the trial's scope.

The original three apps retain their names and IDs:

| App | ID | State |
| --- | --- | --- |
| Firefox | 1 | Ephemeral home directory, as before |
| Steam | 2 | `steam-data` StatefulSet claim template: 300 GiB, `ceph-block`, RWO; mounted at `/home/retro` |
| Test Ball | 3 | Ephemeral bouncing-ball video and ticking audio |

Steam keeps its existing digest-pinned image and adds the upstream example's
memory-backed `/dev/shm` mount. The new `volumeClaimTemplates` API replaces the
old singular `volumeClaimTemplate`; the operator creates Steam's PVC when its
lobby launches. No existing Steam PVC was found in the live games namespace on
2026-10-09. The default Profile has Flux pruning disabled because the fork gives
application PVCs a Profile owner reference: deleting that Profile could cause
Kubernetes to garbage-collect Steam data. Retain it when disabling the trial.

The fork removed per-app `wolfConfig` pipeline settings. Test Ball now runs
GStreamer's bouncing-ball video into `waylandsink` and ticking audio into the
lobby's `pulsesink`, using the same pinned Wolf image for its installed tools.
Resolution, refresh rate, and audio sink come from CDI. Its shell variables are
excluded from Flux substitution. This tests the compositor/socket path as well
as encoding; it is no longer a compositor-free pipeline inside Wolf.

The old `User`, sidecar policies, and root-entrypoint workaround are removed.
The selected Wolf image already starts as root.

cert-manager generates the RSA serving key into `games-on-whales-tls`; no key
is committed. An init container copies the upstream streaming configuration
and certificate into writable Wolf state, using `cert.pem` and `key.pem` as
required by Wolf's startup script. The proxy and agent use the same certificate.
Wolf state is ephemeral. Certificate renewal requires restarting the Wolf pod
so its copied certificate matches the proxy; Moonlight may require re-pairing.

## Before enabling

1. Confirm the AMD DRA driver still publishes Skirk's `gpu-1-128` device.
   Kubernetes is currently `1.37.0`; the fork uses consumable lobby capacity.
   No API-server, kubelet feature-gate, or Talos image/configuration change is
   proposed for this keyboard/mouse-only trial.
2. Review Skirk's current memory/load before the trial. Earlier GoW attempts
   never streamed successfully on this GPU. Leave the trial disabled until the
   capacity checks pass. For an uncontended test, pause the `litellm` Flux
   Kustomization and suspend the `qwen3.8-flash-next` InferenceService, then
   verify its pod has stopped. Unsuspend it and resume Flux after testing.
   These are temporary live operations; this change does not stop flash-next.
3. Enable `./games-on-whales.yaml` in the main games overlay. Check the CRD and
   app Kustomizations, HelmRelease, and all three Deployments. Verify the two
   Services receive the same address, `10.69.10.43`, and the Wolf driver publishes
   a ResourceSlice for Skirk with two lobby slots. Readiness probes check socket
   presence; they do not prove encoding or a working stream.

## Pairing and streaming

Add `10.69.10.43` in Moonlight, then follow the pairing URL in the
`games-on-whales-moonlight-proxy` logs. Treat pairing URLs/codes as credentials;
do not paste them into public test reports. Get the resulting Pairing name:

```sh
kubectl --context main -n games get pairings
```

Add that name under `spec.pairings` in `profile.yaml` and let Flux reconcile.
The default profile starts with no devices authorized and lists Firefox, Steam,
and Test Ball. Once a Pairing is added, that client can select all three apps.
The driver currently allows two active lobbies at a time.
The former hardcoded `alex` User is no longer used.

Launch each app in turn and verify all of the following:

- A lobby ResourceClaim allocates on Skirk and an application StatefulSet is
  created there with both GPU and lobby claims.
- Wolf's Wayland and PulseAudio sockets arrive in the app through CDI, and the
  Session acquires a stream URL.
- Moonlight receives video and audio; keyboard/mouse input works. Test H.264
  first, then AV1. Actual encoder availability on this image/GPU remains unverified.
- Test Ball displays a moving ball and ticking audio; Steam opens its client
  and retains its home/library across lobby restarts.
- Cancel/resume works, a second session can start, and lobby capacity/sockets
  clean up when their claims are released. Virtual gamepad testing is excluded.

The two Services share a Cilium IP: proxy TCP 47984/47989, Wolf TCP/UDP 48010
and UDP 48000/47999/48100/48200. Main uses BGP, so the upstream L2 lease advice
does not apply. No public ingress is configured.

## Validation and upstream feedback

Prepared on 2026-10-09:

- Helm rendering with app-template `5.2.1` and Kubernetes `1.37.0` passed.
- A temporary repository copy with the GoW overlay **enabled** passed all 17
  `flate test all` checks in the games namespace, including the fork source,
  CRDs, app Kustomization, HelmRelease, and OCIRepository.
- Server-side dry runs passed for the rendered Deployments/Services and base
  resources whose APIs are installed. Simulated operator-generated StatefulSets
  for Firefox, Steam (including its 300 GiB PVC template), and Test Ball passed.
- All three Apps and the Profile validated against the pinned fork's CRD schemas offline;
  live custom-resource admission awaits CRD installation.
- The pinned Wolf image contains `gst-launch-1.0`, `videotestsrc`, `waylandsink`,
  `audiotestsrc`, and `pulsesink`. A local container smoke test of Test Ball's
  combined video/audio pipeline passed with finite sources and fake sinks;
  actual Wayland/PulseAudio connection and streamed output remain unverified.

Useful upstream install feedback: the chart is stale, the example assumes a
`devic.es/uinput` device plugin even though Wayland keyboard/mouse input does
not need it, the agent setting is `MAX_LOBBIES` (the example says `MAX_WAYLAND_SOCKETS`), and example
certificates should be replaced with generated credentials. No message has been
sent upstream.

To stop a later trial, first cancel sessions and inspect remaining Lobbies,
ResourceClaims and StatefulSets. Disabling the overlay prunes the app resources,
but deliberately retains CRDs and the default Profile. Steam's PVC is retained
through that Profile ownership and the StatefulSet's default retention policy.
Inspect owner references before removing anything; do not delete the Profile or
existing pairing/session state blindly.
