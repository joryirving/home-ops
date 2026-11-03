# Native Courier canary

Deploys a separate 0.1.12 native controller and one MiniMax lane (concurrency 1)
in the restricted `courier-native` namespace. Existing v1 lanes remain unchanged.
Dispatch, label and cron intake are disabled; merging does not launch model work.
The prepared Dispatch identity is `courier-native-minimax` but no Dispatch token
is provisioned until intake is deliberately enabled.

Before admitting a manually selected real task:

- Verify v1 actually runs 0.1.12 with `--owned-namespace=llm`; dependency readiness
  alone is not a version/argument assertion.
- Confirm both controllers ignore foreign runs, native topology preflight passes,
  and external secrets are ready. Do not inspect or print secret values.
- This canary permits forge operations only for `misospace/courier`. Forge and
  model secrets are separate from the v1 executor secret, but reuse the existing
  operator-managed upstream credentials; they are not newly issued credentials.
  Courier v0.1.12 temporarily needs `courier-native-observer` as a second
  Kubernetes Secret object containing the same GitHub token as
  `courier-native-github`; remove that alias when Courier #638 lands.
- Control egress to LiteLLM uses namespace/pod selectors rather than a transient
  Service IP pin. Workers have no outbound network access; dependency downloads
  require a separately approved read-only cache before tasks that need them.
- 2026-11-02 night ran `glm-5.3-flash` while the MiniMax upstream was
  rate-limited (api.minimax.io 429s), blocking the courier#102 acceptance
  exercise on an upstream-quota condition; restored to `MiniMax-M3.1-Flash`
  on 2026-11-03 with the refreshed quota.
- The lane declares `transport: anthropic` (courier 0.1.18, #716): the
  harness speaks LiteLLM's Anthropic Messages surface natively, because
  MiniMax reasoning blocks only survive their own protocol. The lane's
  `runtimeImage` and `harnessImage.tag` pins are gone — both images track
  the chart version (#717).
- Broker egress to the kube-apiserver is granted by `ciliumnetworkpolicy.yaml`
  (`courier-broker-apiserver`): under Cilium the API server carries a reserved
  identity that the per-run ipBlock rules cannot match, so every secure run
  would die on the broker's `read own pod` without it (misospace/courier#680;
  #685 adds the preflight proof).
- Stop/finish v1 MiniMax work before admitting native MiniMax work if total
  MiniMax concurrency must remain one. This PR does not change v1 intake.

Record actual authenticated heartbeat/checkpoint, remote-confirmed commit/PR
publication, long-tool behavior, control restart/resume and operator recovery
before declaring migration readiness (Courier #102). No live acceptance evidence
is provided by this scaffold. Native context budgets remain unwired (#636).

Enabling normal Dispatch intake and retiring v1 are separate reviewed changes.
Do not reset claims, delete retained runs or reclaim active work as part of setup.
