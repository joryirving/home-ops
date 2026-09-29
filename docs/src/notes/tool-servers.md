# Tool servers (ToolHive)

MCP tool servers run under the ToolHive operator in the `llm` namespace on `main`, behind one
aggregating gateway. The earlier `mcpo` tool-server bundle this page used to describe (added
in #6609) was removed on 2026-04-13; git history has that version.

## Layout

```text
kubernetes/apps/base/llm/toolhive/
├── crds/          # toolhive-crds KS
├── app/           # the operator (toolhive KS)
├── config/        # the gateway (toolhive-config KS)
└── mcp-servers/   # one folder per server, one KS each

kubernetes/apps/main/llm/toolhive.yaml   # every Flux Kustomization above
```

## The gateway

- **`VirtualMCPServer` `mcp-gateway-internal`** aggregates every server in the `MCPGroup`
  `mcp-tools`. Tool name conflicts are resolved by a `{workload}_` prefix. Sessions are kept
  in the `toolhive-config` Dragonfly.
- **In-cluster**: `vmcp-mcp-gateway-internal.llm:4483`, anonymous (no key).
- **Public**: `mcp.jory.dev` through `envoy-external`. An Envoy `SecurityPolicy` enforces
  `apiKeyAuth` on the `x-api-key` header, with keys from the `mcp-gateway-api-keys` Secret
  (1Password `toolhive` item). Gatus expects a 401 without a key.
- **Optimizer**: tool embeddings come from the LiteLLM `embed` model
  (`http://litellm.llm:4000/v1`, 180s timeout).

## Servers

| Folder | Resource | Kind | Upstream |
|---|---|---|---|
| `arr-mcp` | `arr` | `MCPServer` (stdio) | Sonarr, Radarr, Prowlarr |
| `dispatch-mcp` | `dispatch-mcp` | `MCPServer` (stdio) | Dispatch |
| `flux-mcp` | `flux` | `MCPServer` (streamable-http) | flux-operator MCP, read-only RBAC |
| `github-mcp` | `github` | `MCPServer` (stdio) | GitHub |
| `grafana-mcp` | `grafana` | `MCPServerEntry` (sse) | `mcp-grafana.observability:8000` |
| `ha-mcp` | `ha-mcp` | `MCPServer` (streamable-http) | Home Assistant |
| `kubectl-mcp` | `kubectl` | `MCPServer` (streamable-http) | Kubernetes API, read-only RBAC |
| `plan-shop-eat-mcp` | `plan-shop-eat` | `MCPServerEntry` (streamable-http) | hosted remote |
| `seerr-mcp` | `seerr-mcp` | `MCPServer` (stdio) | Seerr |
| `talos-mcp` | `talos-mcp` | `MCPServer` (streamable-http) | Talos API |
| `unifi-network-mcp` | `unifi-network-mcp` | `MCPServer` (streamable-http) | UniFi Network |

`MCPServer` runs the server in-cluster; `MCPServerEntry` registers a remote endpoint.

## Adding a server

1. Create `kubernetes/apps/base/llm/toolhive/mcp-servers/<name>-mcp/` with a
   `kustomization.yaml`, the `MCPServer` (or `MCPServerEntry`) with
   `groupRef: {name: mcp-tools}`, and an `ExternalSecret` when it needs credentials.
2. Add a Flux `Kustomization` block for it to `kubernetes/apps/main/llm/toolhive.yaml`, with
   `dependsOn: toolhive` plus the app it wraps (e.g. `grafana` in `observability`).

The gateway picks the new server up through the group; nothing else changes.

## Deployment guardrails

Before merging a real tool server manifest, require:

- internal-only reachability unless sharing is intentional
- auth on every non-public endpoint when practical
- explicit read-only mode where possible
- bounded actions instead of arbitrary command/query execution
- resource requests/limits
- health probes
- no host mounts unless explicitly justified
