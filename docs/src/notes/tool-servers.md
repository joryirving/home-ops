# Tool servers

MCP is served by the LiteLLM operator in the `llm` namespace. The proxy exposes one endpoint,
`http://litellm.llm:4000/mcp`; `https://mcp.jory.dev/mcp` routes to the same endpoint. Each client
has its own `LiteLLMTeam` and bearer key, scoped to MCP servers and not model access. Manifests live
under `kubernetes/apps/base/llm/litellm/mcp/` and `mcp-access/`; the `litellm` Flux Kustomization
owns them.

## Runtime layout

| Server aliases | Runtime | Notes |
|---|---|---|
| `flux`, `ha`, `kubectl`, `marketplace`, `talos`, `unifi_network` | Operator-managed HTTP workloads | Their images, service accounts, and workload settings are declared in `mcp/`. |
| `arr`, `dispatch`, `github`, `seerr` | `stdio` subprocesses in the LiteLLM proxy image | Fixed launch entries in `docker/litellm-mcp/launch.py`; credentials are mounted from ExternalSecrets. |
| `grafana`, `plan_shop_eat` | Existing remote HTTP/SSE endpoints | LiteLLM registers the endpoints; it does not run their servers. |

The custom proxy image bundles the four stdio servers and is built by
`.github/workflows/litellm-mcp-image.yaml`. The stdio processes share the LiteLLM proxy pod's
filesystem, resource budget, and failure domain; they do not get ToolHive-style per-server pod
isolation. Keep their launch commands and environment allowlisted, secrets file-mounted, and
read-only unless a tool requires writes. Verify keyword/tool-search behavior against the deployed
LiteLLM version during migration; do not assume it behaves exactly like the retired vMCP gateway.

`marketplace` uses the existing `marketplace-browser-profile` RWO PVC. The manifest deliberately
sets `kustomize.toolkit.fluxcd.io/prune: disabled` so removing the old owner cannot delete the profile.
Do not run the old and new marketplace workloads against that claim at the same time.

## Adding a server

1. Add a `LiteLLMMCPServer` to `kubernetes/apps/base/llm/litellm/mcp/` and list it in that
   directory's `kustomization.yaml`. Use a fixed, digest-pinned image for an operator-managed
   workload; use an explicit endpoint for a remote server. For stdio, add a fixed launcher entry
   and tests to `docker/litellm-mcp/` rather than accepting caller-provided commands.
2. Add credentials through an `ExternalSecret` backed by 1Password. Add the alias to each intended
   `LiteLLMTeam` in `mcp-access/`; keep model access disabled for MCP-only keys.
3. Check the exact upstream tools, auth scope, write behavior, resource limits, probes, and network
   reachability. Exercise tool discovery and invocation through `/mcp` before enabling it for users.

## Mandatory ToolHive-to-LiteLLM cutover runbook

This is an operator-run migration, not an automatic PR action. The current draft is **blocked**:
do not merge or deploy until the custom image is published, its immutable digest is recorded below,
public image pulls succeed, and the live checks in this runbook pass. No live cluster changes have
been made as part of preparing this runbook.

### 1. Clear pre-deployment gates

- Run `.github/workflows/litellm-mcp-image.yaml` against the reviewed commit. Publish the tested
  image to GHCR, confirm it is publicly pullable without credentials, then replace the draft image
  in `kubernetes/apps/base/llm/litellm/litellmproxy.yaml` with the published `@sha256:` digest. A
  tag alone is not sufficient.
- Verify the published image digest matches the tested artifact; run the image's LiteLLM startup
  and stdio smoke checks, then validate the manifests and migration contract tests.
- Before the maintenance window, verify all 12 aliases and each consumer's separate bearer key are
  present in the rendered manifests. Agree on a rollback point and stop write-capable MCP activity
  during the cutover. Do not test mutating tools through both gateways.

### 2. Inventory and freeze reconciliation

Use the `main` context and save the output with the change record. Stop if the cluster, resources,
Flux inventory, or PVC identity differ from expectations; do not substitute a broad `delete all`.

```sh
kubectl config current-context
flux get kustomizations -n flux-system
flux get kustomizations -n llm
kubectl -n llm get pvc marketplace-browser-profile -o wide
kubectl -n llm get pvc marketplace-browser-profile -o jsonpath='{.metadata.uid}{"\\n"}'
kubectl api-resources --api-group=toolhive.stacklok.dev -o wide
```

List every namespaced ToolHive custom resource using the API resource names returned by the previous
command, and save the full Flux inventories for the old Kustomizations before changing anything.
Check the old Kustomization inventory for all cross-cutting resources, including Dragonfly, its
ExternalSecrets, and gateway route/policy/monitoring objects; do not assume the resource categories
below are exhaustive. Then suspend the root and each old child, plus `litellm` and the three consumer
Kustomizations, so neither side can race staging. These are the expected names; confirm them against
the inventory first.

```sh
flux suspend kustomization cluster-apps -n flux-system
flux suspend kustomization litellm -n llm
flux suspend kustomization hermes -n llm
flux suspend kustomization openclaw -n llm
flux suspend kustomization opencode -n llm
flux suspend kustomization toolhive-crds -n llm
flux suspend kustomization toolhive -n llm
flux suspend kustomization toolhive-config -n llm
flux suspend kustomization arr-mcp -n llm
flux suspend kustomization dispatch-mcp -n llm
flux suspend kustomization flux-mcp -n llm
flux suspend kustomization github-mcp -n llm
flux suspend kustomization grafana-mcp -n llm
flux suspend kustomization ha-mcp -n llm
flux suspend kustomization kubectl-mcp -n llm
flux suspend kustomization marketplace-mcp -n llm
flux suspend kustomization plan-shop-eat-mcp -n llm
flux suspend kustomization seerr-mcp -n llm
flux suspend kustomization talos-mcp -n llm
flux suspend kustomization unifi-network-mcp -n llm
```

Verify every listed Kustomization is suspended and the old operator is still healthy. Do not remove
the ToolHive operator or its CRDs yet.

### 3. Protect shared state and identities

Before old owners are removed, confirm each shared object exists in the saved inventories and its
replacement is present in the reviewed source. The new `mcp/flux-rbac.yaml` is the tracked owner for
the exact baseline `flux-mcp` ServiceAccount, Flux read/write roles, and bindings; it marks them
`prune: disabled` to protect identity during the handoff. The new `mcp/rbac.yaml` reuses the existing
kubectl roles, and `mcp/talosserviceaccount.yaml` reuses the Talos account. Do not rename or recreate
these identities.

The Marketplace PVC is also shared: confirm its original UID and `Bound` state, and verify the new
manifest describes the same claim before transfer. The new Marketplace ExternalSecrets reuse the old
targets and Facebook 1Password fields; verify both are Ready before deleting old copies. Keep all
1Password source items intact, including the legacy ToolHive API key and Redis password, for rollback.

```sh
kubectl -n llm annotate pvc marketplace-browser-profile \
  kustomize.toolkit.fluxcd.io/prune=disabled --overwrite
kubectl -n llm annotate serviceaccount kubectl-mcp-readonly flux-mcp \
  kustomize.toolkit.fluxcd.io/prune=disabled --overwrite
kubectl annotate clusterrole kubectl-mcp-readonly kubectl-mcp-readonly-explicit flux-mcp-write \
  kustomize.toolkit.fluxcd.io/prune=disabled --overwrite
kubectl annotate clusterrolebinding kubectl-mcp-readonly kubectl-mcp-readonly-explicit \
  flux-mcp-readonly flux-mcp-readonly-explicit flux-mcp-write \
  kustomize.toolkit.fluxcd.io/prune=disabled --overwrite
kubectl -n llm annotate serviceaccounts.talos.dev talos-mcp-talosconfig \
  kustomize.toolkit.fluxcd.io/prune=disabled --overwrite
kubectl -n llm get pvc marketplace-browser-profile -o wide
kubectl -n llm get pvc marketplace-browser-profile -o jsonpath='{.metadata.uid}{"\\n"}'
```

The Talos account is the namespaced `ServiceAccount` resource `talos.dev`, not a cluster-scoped
Kubernetes ServiceAccount. Confirm the API resource name via discovery before annotating. Retain
prune protection through the handoff; remove it only after the new tracked owner and its inventory
are confirmed.

### 4. Stage and verify the replacement

Stop the old `marketplace-mcp` first and wait for its ToolHive-managed pod to terminate and release
the RWO claim before creating the LiteLLM `marketplace` workload. Never let both pods mount the
profile concurrently.

Keep `cluster-apps` suspended and do not resume `litellm` or any consumer Flux Kustomization while
staging against the old source artifact: the old source could restore ToolHive resources or revert
consumer configuration. Build each exact path with its Flux Kustomization file, components, and
substitutions from the reviewed commit. For example:

```sh
flux build kustomization litellm \
  --path ./kubernetes/apps/base/llm/litellm \
  --kustomization-file ./kubernetes/apps/main/llm/litellm.yaml
flux build kustomization hermes \
  --path ./kubernetes/apps/base/llm/hermes \
  --kustomization-file ./kubernetes/apps/main/llm/hermes.yaml
flux build kustomization openclaw \
  --path ./kubernetes/apps/base/llm/openclaw \
  --kustomization-file ./kubernetes/apps/main/llm/openclaw.yaml
flux build kustomization opencode \
  --path ./kubernetes/apps/base/llm/opencode \
  --kustomization-file ./kubernetes/apps/main/llm/opencode.yaml
```

These commands read the local working tree; ensure it is exactly the reviewed commit. Apply only the
reviewed rendered output while the Kustomizations and root remain suspended. Inspect each diff and
stop if substitutions are unresolved, unrelated resources would be deleted, or output differs from
the reviewed render. Do not use `kubectl apply -k` on raw app directories: Flux components and
`postBuild` substitutions are part of the desired state. Verify new MCP resources and ExternalSecrets
are Ready, the proxy runs the published digest, and all four stdio servers start on every proxy
replica. Check discovery/search, the exact alias set, and each of Hermes, OpenClaw, and OpenCode using
only its own MCP bearer key with no model grants. Start with read-only/list operations.

Do not resume any Flux Kustomization until the reviewed commit is merged, the source artifact is
confirmed to contain that exact commit, and the root remains suspended. Then resume `litellm` and the
three consumer Kustomizations and confirm each is Ready; only after their source reconciliations
succeed, verify the in-cluster `/mcp` endpoint, the public `mcp.jory.dev/mcp` route, unauthenticated
rejection, and authenticated calls with each existing Secret (never print key values). Do not invoke
mutating tools through both gateways or allow two Marketplace instances to write profile state. If
safe invocation cannot be assured, stop at read-only checks and retain the old gateway for rollback.
Confirm the Marketplace PVC retains its original UID and data.

### 5. Drain ToolHive before removing its operator

After the reviewed commit is merged and its source artifact is verified, keep `cluster-apps` and all
old ToolHive children suspended. The PR removes the old source tree, so do not depend on editing and
reconciling intermediate child manifests or making a second source commit. With the old operator
still running, delete only the exact ToolHive custom resources recorded in the live inventory, using
the discovered resource plurals and names; wait for every deletion and finalizer. Never delete a CRD
while any instance remains. The expected objects are ten `MCPServer`s (`arr`, `dispatch`, `flux`,
`github`, `ha-mcp`, `kubectl`, `marketplace-mcp`, `seerr-mcp`, `talos-mcp`, `unifi-network-mcp`),
two `MCPServerEntry`s (`grafana`, `plan-shop-eat`), `VirtualMCPServer/mcp-gateway-internal`,
`MCPGroup/mcp-tools`, and `MCPTelemetryConfig/prometheus`. Verify the old Marketplace pod is gone
and the RWO volume detached.

Only after every ToolHive custom resource and finalizer is gone, resume `cluster-apps`. Flux does not
guarantee `dependsOn` is applied in reverse during deletion; verify the old child Kustomizations,
operator, and CRDs disappear without removing the PVC or the shared RBAC/Talos identities. Confirm
LiteLLM and all consumer Kustomizations remain Ready and public/in-cluster MCP checks still pass.
Save the inventories and check results with the change record. Leave 1Password source items intact.
