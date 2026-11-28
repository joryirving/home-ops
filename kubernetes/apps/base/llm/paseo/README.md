# Paseo

Paseo runs coding agents in this cluster. A client sends a task to the daemon, the daemon starts an agent in a workspace, and the client reads the result back.

The daemon speaks MCP (Model Context Protocol, a JSON-RPC protocol for tool calls) on one HTTP endpoint. This page documents that endpoint, the credential it needs, the tools it exposes, and the checks to run after each change.

## Endpoint

- URL: `https://paseo.jory.dev/mcp/agents`
- Transport: Streamable HTTP, stateless. The daemon builds a new MCP server for each request, so there is no session id to keep.
- Method: `POST` only.
- Required request header: `Accept: application/json, text/event-stream`

Use the path `/mcp/agents`. The path `/mcp` is not an endpoint, and nothing handles it. A request without a credential gets `401` from the daemon password middleware. A request with a valid credential gets an Express `404`.

The daemon checks the `Host` header against `PASEO_HOSTNAMES`, which holds only `paseo.jory.dev`. A client that calls the Service DNS name `paseo.llm.svc.cluster.local:6767` gets `403 {"error":"Invalid Host header"}`. Every client must therefore use the route hostname, and must resolve it to the internal gateway.

The route `route.app` in `helmrelease.yaml` attaches to `envoy-internal` in the `network` namespace, so the endpoint is reachable inside the network only. No public route, gateway, or OIDC application fronts it. The certificate is `*.jory.dev` from the `letsencrypt-production` `ClusterIssuer`, so a stock trust store verifies it and no `caBundle` is needed.

A disabled endpoint answers before authentication. While `daemon.mcp.enabled` is `false`, a request to `/mcp/agents` returns `404 {"error":"Agent MCP endpoint disabled"}` even with a correct credential.

## Configuration

`config/paseo.json` becomes the `paseo-config` ConfigMap through the `configMapGenerator` in `kustomization.yaml`. The image entrypoint copies that file to `~/.paseo/config.json` on every container start, and the daemon reads only the copy in the home directory. A change therefore takes effect on the next start.

```json
"daemon": {
  "relay": { "enabled": false },
  "mcp": { "enabled": true, "injectIntoAgents": false }
}
```

`daemon.mcp.enabled` turns the endpoint on. `daemon.mcp.injectIntoAgents` controls whether agents that the daemon runs also receive the Paseo tool catalog. Keep it `false`. When it is `false`, enabling the endpoint does not let a worker spawn more workers. Set it to `true` only for a provider profile that needs delegation. Restrict such a profile with `agents.providers.<id>.paseoTools.disabledTools`, for example `["create_agent", "send_agent_prompt", "kill_agent"]`. The upstream project states that this provider setting is not a security boundary for an agent that can reach a shell.

Reloader watches the ConfigMap. The pod template holds the annotation `reloader.stakater.com/auto: "true"` and Reloader already injects the checksum env `STAKATER_PASEO_CONFIG_CONFIGMAP`, so a content change rolls the Deployment.

Do not merge this file while a session is live. The merge restarts the Paseo pod, and the restart ends every active session. Get an explicit go-ahead first.

## Authentication

The endpoint uses the existing daemon password. Nothing new is involved.

The `paseo` `ExternalSecret` maps the `password` field of the 1Password item `paseo` to the `PASEO_PASSWORD` env var. The daemon hashes that value with bcrypt at process start. A client sends the plaintext password:

```
Authorization: Bearer <daemon password>
```

The scheme is case-sensitive and must read exactly `Bearer`. A lowercase `bearer` fails with `401`. The daemon logs a rejection as `Rejected HTTP request with invalid daemon password`.

`/mcp/agents` is exempt from the global password middleware and authenticates inside the route. It accepts a per-run capability token or a valid daemon password bearer. The password path is the one a long-lived client uses.

If no daemon password is configured, the endpoint is open. `PASEO_PASSWORD` is present in the pod, so the endpoint is protected today. The `ExternalSecret` declares no `refreshInterval`, and the hash happens at process start, so a rotated password needs a pod restart to take effect.

## Client setup

Use an environment variable for the credential. Do not commit the password and do not paste it into a client file.

### OpenClaw

OpenClaw reads MCP servers from `mcp.servers` in `kubernetes/apps/base/llm/openclaw/configmap.yaml`. Add an entry beside the existing ones, then add `PASEO_PASSWORD` to the `externalsecret.yaml` of that app:

```javascript
paseo: {
  url: "https://paseo.jory.dev/mcp/agents",
  transport: "streamable-http",
  headers: {
    Accept: "application/json, text/event-stream",
    Authorization: "$${PASEO_PASSWORD}",
  },
},
```

`$${PASEO_PASSWORD}` is the escaped form of `${PASEO_PASSWORD}`. Helm consumes one `$`, and OpenClaw expands the value at runtime.

### OpenCode and a local Paseo session

OpenCode reads `mcp` in `opencode.json`. Paseo mounts its own copy from the `opencode-config` ConfigMap at `/etc/paseo/opencode.json`:

```json
"mcp": {
  "paseo": {
    "type": "remote",
    "url": "https://paseo.jory.dev/mcp/agents",
    "enabled": true,
    "headers": {
      "Authorization": "{env:PASEO_PASSWORD}"
    }
  }
}
```

`{env:PASEO_PASSWORD}` is the OpenCode expansion syntax. Export the variable in the environment that runs the client before you start it.

A generic MCP client needs the same three pieces: the URL, the two headers, and `POST`. Prefer a real MCP client over hand-written HTTP, because the handshake and the streaming response carry protocol detail.

### Relationship to ToolHive

The daemon is not registered with the ToolHive MCP gateway, and no `MCPServer` object points at it. Clients connect to the daemon directly. In-cluster consumers that point at `http://vmcp-mcp-gateway-internal.llm:4483/mcp` reach other servers, not Paseo. The direct path keeps the credential boundary in one place: one daemon password and one internal route.

## Tool catalog

Paseo 0.18.0 registers 43 tools. The list below comes from the tool registration sites in that release, so run `tools/list` after a restart to confirm the live set. Browser tools are opt-in and `speak` needs a voice session.

Create work:

- `create_agent` starts an agent. Pass `workspaceId` to place it, and `initialPrompt` to give it the task. With `background: true` the agent stays out of default lists.
- `create_workspace` makes an isolated workspace, with a branch or a pull-request checkout.
- `create_schedule` and `create_heartbeat` keep running work on a timer after the call ends.
- `list_profiles`, `list_providers`, `list_models`, `inspect_provider`, and `list_hosts` supply the arguments the create tools need.

Send instructions:

- `send_agent_prompt` delivers a follow-up prompt. `activeTurnBehavior` picks `steer` to join the running turn or `interrupt` to replace it.
- `run_schedule_once` triggers a schedule now.
- `send_terminal_keys` writes keystrokes to a terminal.

Watch progress:

- `get_agent_status` reports state, and `get_agent_activity` reports what the agent did.
- `list_agents` covers current agents, and `includeBackground` adds hidden ones.
- `list_workspaces`, `list_terminals`, `list_schedules`, `inspect_schedule`, and `schedule_logs` cover the surrounding machinery.
- `list_pending_permissions` shows permission requests waiting on a human answer.

Read results:

- `get_agent_status` and `get_agent_activity` are the intended result path for an external MCP client.
- `capture_terminal` returns the visible terminal buffer.
- `schedule_logs` returns run history for a schedule.

Stop work:

- `cancel_agent` aborts the current run and keeps the agent alive.
- `kill_agent` terminates the agent for good.
- `archive_agent` and `archive_workspace` retire an agent or a workspace.
- `kill_terminal`, `stop_workspace_script`, `pause_schedule`, `delete_schedule`, and `delete_heartbeat` stop the other long-lived units.

There is no tool that detaches an agent from the daemon. `update_agent`, `rename_workspace`, `set_agent_mode`, `list_workspace_scripts`, `start_workspace_script`, `resume_schedule`, `subscribe_change_request`, and `unsubscribe_change_request` cover the rest.

## Checks after the restart

Run these in order. Each one prints a status, and no command prints the password.

1. Confirm the pod is new and healthy:

   ```bash
   kubectl -n llm rollout status deploy/paseo
   ```

2. Confirm the enabled config reached the daemon home directory:

   ```bash
   kubectl -n llm exec deploy/paseo -c app -- grep -o '"mcp":[^}]*}' /home/paseo/.paseo/config.json
   ```

3. Complete the MCP handshake through the route, from inside the pod. Expect `200` and a server-info body. Do not expect a `Mcp-Session-Id` to persist, because the transport is stateless:

   ```bash
   kubectl -n llm exec -i deploy/paseo -c app -- sh -lc 'cat > /tmp/mcp.mjs && node /tmp/mcp.mjs' <<'EOF'
   const body = { jsonrpc: "2.0", id: 1, method: "initialize", params: {
     protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "probe", version: "0" } } };
   const r = await fetch("https://paseo.jory.dev/mcp/agents", { method: "POST",
     headers: { Accept: "application/json, text/event-stream", "Content-Type": "application/json",
       Authorization: `Bearer ${process.env.PASEO_PASSWORD}` },
     body: JSON.stringify(body) });
   console.log("authorized initialize:", r.status);
   console.log((await r.text()).slice(0, 400));
   EOF
   ```

4. List the tools with the same request shape and `"method": "tools/list"`. Compare the names against the catalog above.

5. Confirm the endpoint rejects bad credentials. Expect `401` for each row, and expect a different body from the disabled-state `404`:

   ```bash
   kubectl -n llm exec -i deploy/paseo -c app -- sh -lc 'cat > /tmp/auth.mjs && node /tmp/auth.mjs' <<'EOF'
   const body = { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} };
   const pw = process.env.PASEO_PASSWORD;
   const cases = [["no token", null], ["wrong password", "Bearer definitely-not-it"],
     ["lowercase scheme", `bearer ${pw}`], ["correct", `Bearer ${pw}`]];
   for (const [label, value] of cases) {
     const headers = { Accept: "application/json, text/event-stream", "Content-Type": "application/json" };
     if (value) headers.Authorization = value;
     const r = await fetch("http://127.0.0.1:6767/mcp/agents", { method: "POST", headers, body: JSON.stringify(body) });
     console.log(label, "=>", r.status);
   }
   EOF
   ```

6. Confirm an agent can reach the endpoint from inside a Paseo session only if you enabled injection. With `injectIntoAgents: false` the Paseo catalog is absent, which is the expected result.

7. Read the daemon log for unexpected rejections. Filter the runtime metrics lines first, because they are large:

   ```bash
   kubectl -n llm logs deploy/paseo -c app --tail 400 | grep -v ws_runtime_metrics | grep -iE 'mcp|invalid daemon password'
   ```

## Risks

One credential, one identity:

- The daemon password is shared. There is no per-client credential, no read-only role, and no attribution of who called what. A leaked password cannot be rotated for one client only.
- The same bearer authenticates the whole `/api/*` surface, not only the MCP endpoint. An MCP client that keeps the token can use non-MCP daemon routes too.

Delegation reach:

- `respond_to_permission` and `list_pending_permissions` let a caller answer permission prompts that belong to another agent. That replaces the human approval gate. Treat these two tools as the sharpest ones in the catalog.
- `create_terminal`, `send_terminal_keys`, and `capture_terminal` give a shell inside the daemon pod.
- The agents inherit broad credentials. The entrypoint writes `~/.git-credentials` from `GITHUB_TOKEN` in the `paseo` Secret. It also sets the git identity to the bot account. An agent therefore holds GitHub write access, plus the LiteLLM, Memini, and Context7 keys that sit in the environment.

Uncontrolled growth:

- No per-caller quota limits `create_agent`.
- `create_schedule` and `create_heartbeat` outlive the request and keep starting agents on a timer.
- An agent started with `background: true` stays out of the default `list_agents` output, so a caller can hide work.
- Recursion is off today, because `injectIntoAgents` is `false` and the injection path is gated on it. Turning it on makes every worker a potential spawner.

Shared state:

- `/workspace` and `worktrees.root` (`/workspace/worktrees`) live on one PVC. A caller that passes an existing `workspaceId` can enter the tree of a live interactive session. Require callers to create a worktree with `create_workspace` instead.
- Agents from different callers share the pod, its files, and its credentials.

Rate and behavior details:

- Each password check costs bcrypt work at cost 12. A flood of wrong passwords is CPU work, and nothing rate-limits it. This change adds no Envoy policy, by design.
- While the endpoint is disabled, callers see `404` before any `401`. Do not read that `404` as proof that a credential failed.

Separate, pre-existing disagreement:

- `helmrelease.yaml` sets `PASEO_RELAY_ENABLED: "true"`, while `config/paseo.json` sets `daemon.relay.enabled` to `false`. At 0.18.0 the env var wins, and the default relay endpoint is `relay.paseo.sh:443`. I saw no established `:443` peer and the `relayExternalSocketAttached` counters stayed at `0`, so an active relay path is unconfirmed. Reconcile the two values in a separate change.

## Version note

These statements describe Paseo 0.18.0, the pinned image `ghcr.io/joryirving/paseo:0.18.0@sha256:5d0a5b3a...`, built from `getpaseo/paseo` at `v0.18.0`. The endpoint path, the disabled-before-auth order, the `Bearer` casing rule, and the tool count all come from that revision. Re-run the checks above after any Paseo version bump.
