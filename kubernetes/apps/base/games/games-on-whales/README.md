# Games-on-Whales DRA trial

A single-node Firefox streaming trial on Skirk's Strix Halo GPU, using
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

The Wolf agent, Wolf, and Firefox all reference one `gow-amd-gpu` ResourceClaim
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

Wolf runs privileged with `/dev/uinput` and `/dev/input` mounted for virtual
gamepads and fallback input emulation. In the pinned Wolf build, lobby keyboard
and mouse input go directly through `WaylandKeyboard` and `WaylandMouse`; they
do not require uinput. The current manifest still requires the extension because
its `/dev/uinput` hostPath mount is mandatory. A keyboard/mouse-only trial can
omit that mount and the extension/module configuration. Firefox has an ephemeral home directory; this trial creates no
application PVCs and includes no Steam installation. The old `User`, sidecar
policies, and root-entrypoint workaround are removed. The selected Wolf image
already starts as root.

cert-manager generates the RSA serving key into `games-on-whales-tls`; no key
is committed. An init container copies the upstream streaming configuration
and certificate into writable Wolf state, using `cert.pem` and `key.pem` as
required by Wolf's startup script. The proxy and agent use the same certificate.
Wolf state is ephemeral. Certificate renewal requires restarting the Wolf pod
so its copied certificate matches the proxy; Moonlight may require re-pairing.

## Before enabling

1. For the manifests as written, install Sidero's official `uinput` extension on Skirk. Its current image has
   neither the module nor `/dev/uinput`. This change adds `siderolabs/uinput` to
   `talos/main/worker/schematic.yaml` and a `KernelModuleConfig` to `skirk.yaml`.
   The extension contains the matching kernel module; its build copies it and
   runs `depmod`, with no runtime install script. Factory lists it for Talos
   `v1.14.2`. See the [extension instructions](https://github.com/siderolabs/extensions/tree/main/drivers/uinput).
   Applying configuration alone cannot install an extension: regenerate/apply
   Skirk's installer schematic, then perform a controlled Talos upgrade at the
   existing version. The repository's `talos:upgrade-node` task uses the
   installer image from the live node configuration. This drains/reboots Skirk
   and interrupts its workloads; schedule it separately from enabling GoW.
2. Verify `uinput` appears in `/proc/modules` and `/dev/uinput` exists. Confirm
   the AMD DRA driver still publishes Skirk's `gpu-1-128` device. Kubernetes is
   currently `1.37.0`; the fork uses consumable lobby capacity. No API-server or
   kubelet feature-gate change is proposed.
3. Review Skirk's current memory/load before the trial. Earlier GoW attempts
   never streamed successfully on this GPU. Leave the trial disabled until the
   extension and capacity checks pass; decide separately whether to stop an LLM
   workload for an uncontended test.
4. Enable `./games-on-whales.yaml` in the main games overlay. Check the CRD and
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
The default profile starts with no devices authorized and exposes only Firefox.
The former hardcoded `alex` User is no longer used.

Launch Firefox and verify all of the following:

- A lobby ResourceClaim allocates on Skirk and an application StatefulSet is
  created there with both GPU and lobby claims.
- Wolf's Wayland and PulseAudio sockets arrive in Firefox through CDI, and the
  Session acquires a stream URL.
- Moonlight receives video and audio; keyboard/mouse input works. Test H.264
  first, then AV1. Actual encoder availability on this image/GPU remains unverified.
- Cancel/resume works, a second session can start, and lobby capacity/sockets
  clean up when their claims are released.

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
  resources whose APIs are installed. A simulated operator-generated Firefox
  StatefulSet also passed.
- App and Profile validated against the pinned fork's CRD schemas offline;
  live custom-resource admission awaits CRD installation.
- The Skirk patch validated with a synthetic Talos worker configuration. The
  synthetic generator's automatic hostname was removed to match the node's
  explicitly configured hostname. No live machine configuration was applied.

Useful upstream install feedback: the chart is stale, the example assumes a
`devic.es/uinput` device plugin, Talos needs the uinput extension, the agent
setting is `MAX_LOBBIES` (the example says `MAX_WAYLAND_SOCKETS`), and example
certificates should be replaced with generated credentials. No message has been
sent upstream.

To stop a later trial, first cancel sessions and inspect remaining Lobbies,
ResourceClaims and StatefulSets. Disabling the overlay prunes the app resources,
but deliberately retains CRDs and their objects; inspect owner references before
removing anything. Do not delete existing pairing/session state blindly.
