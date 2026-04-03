# Open WebUI Tool Servers (Kubernetes plan)

## Goal

Add a small set of **self-hosted, Open WebUI-compatible tool servers** that fit the current GitOps layout and are safe to run inside the cluster.

This cluster-hosted Open WebUI deployment should prefer **global/shared tool servers** that are reachable from the backend over workstation-local tools.

## Current topology decision

For Home Assistant specifically, the cleanest split is:

- **Home Assistant stays in `utility`** where it already lives
- the **Open WebUI-facing tool server lives in `main`** next to the LLM apps that consume it

That keeps the tool server private to the LLM cluster while still allowing it to talk upstream to Home Assistant.

## First implementation included in this PR

This PR adds a deployable **Home Assistant tool server** in `main` using [`mcpo`](https://github.com/open-webui/mcpo) to expose the existing Home Assistant MCP endpoint as an OpenAPI-compatible HTTP service for Open WebUI.

### Shape
- namespace: `llm`
- cluster: `main`
- exposure: `ClusterIP` only
- upstream: `https://hass.jory.dev/api/mcp`
- auth to upstream: Home Assistant token from the existing `openclaw` 1Password item

### Intended Open WebUI registration

After deployment, register it in Open WebUI as a **global tool server** using:

```text
http://home-assistant-tool-server.llm.svc.cluster.local:8000/homeassistant
```

No public route is created in this first pass.

## Recommended next wave

### 1. Ops / status server
**Value:** Highest

Expose read-only endpoints for:
- pod / deployment status
- recent failing workloads
- storage pressure summaries
- backup health
- app health rollups

**Why first:** Highest practical value with the lowest blast radius. It answers "what is broken?" without handing raw shell access to the model.

**Deployment shape:**
- namespace: `llm`
- exposure: `ClusterIP` only
- auth: API key or forward-auth if a route is later added

---

### 2. Home Assistant wrapper
**Value:** High

Expose safe endpoints for:
- entity state lookup
- sensors
- scenes
- light/climate control

**Why:** Real daily utility, but still constrain writes to a small allowlist.

**Deployment shape:**
- namespace: `llm`
- exposure: `ClusterIP` only at first
- secrets: Home Assistant token via `ExternalSecret`

---

### 3. Read-only Postgres/query server
**Value:** High

Expose:
- approved read-only queries
- job / queue inspection
- migration state
- app diagnostics

**Why:** Great debugging leverage, but should stay read-only and schema-scoped.

**Deployment shape:**
- namespace: `llm`
- exposure: `ClusterIP` only
- auth: API key
- connectivity: dedicated read-only database user

---

### 4. GitHub helper server
**Value:** Medium-high

Expose:
- PR / issue status
- CI run status
- labels / reviewers / mergeability

**Why:** Useful for workflow-heavy chat sessions, but lower priority than internal ops visibility.

**Deployment shape:**
- namespace: `llm`
- exposure: `ClusterIP` only
- secrets: GitHub token or GitHub App credentials via `ExternalSecret`

## What not to start with

- workstation-local filesystem tools
- broad shell wrappers
- arbitrary SQL execution
- unauthenticated public tool routes

Those are great ways to turn "helpful assistant" into "incident retrospective material."

## Repo structure to follow

For each tool server, follow the existing app pattern:

```text
kubernetes/apps/base/llm/<tool-server>/
├── kustomization.yaml
├── helmrelease.yaml
└── externalsecret.yaml   # only when credentials are needed

kubernetes/apps/main/llm/<tool-server>.yaml
```

And wire the app into:

- `kubernetes/apps/main/llm/kustomization.yaml`
- optionally later into `utility` / `test` if it makes sense there

Use:
- `HelmRelease` with `app-template`
- `ExternalSecret` for credentials
- `ClusterIP` service by default
- no public route unless there is a clear backend/browser requirement

## Suggested rollout order

### Phase 1
1. ops-status server
2. Home Assistant wrapper

### Phase 2
3. read-only Postgres/query server
4. GitHub helper server

## Deployment guardrails

Before merging a real tool server manifest, require:
- internal-only reachability unless sharing is intentional
- auth on every non-public endpoint when practical
- explicit read-only mode where possible
- bounded actions instead of arbitrary command/query execution
- resource requests/limits
- health probes
- no host mounts unless explicitly justified

## Proposed next implementation

The next actual deployment after Home Assistant should be an **ops-status server** because it is:
- the most broadly useful to Open WebUI
- safer than shell access
- easy to keep read-only
- easy to expose over a narrow OpenAPI surface

A minimal first API should answer:
- `GET /healthz`
- `GET /services`
- `GET /services/{name}`
- `GET /alerts`
- `GET /backups`
