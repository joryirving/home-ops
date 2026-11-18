# Chart examples

Each example is a complete (or layerable) values file. Secrets are NEVER
put in values — the placeholder manifests below create the prerequisite
Secrets in the release namespace first.

## Install

```sh
# 1. Prerequisite Secrets (edit the placeholder data).
kubectl apply -f secrets.yaml

# 2. The chart (controller-only example).
helm dependency build deploy/charts/pr-reviewer
helm install pr-reviewer deploy/charts/pr-reviewer \
  -f deploy/charts/pr-reviewer/examples/values-controller-only.yaml
```

For the Kubernetes worker executor, layer the executor example (it
provisions the worker namespace's service account, the namespace-scoped
Role/RoleBinding, and the shared PVCs; the worker Jobs themselves are
created by the controller's executor from the instance config):

```sh
helm install pr-reviewer deploy/charts/pr-reviewer \
  -f deploy/charts/pr-reviewer/examples/values-kubernetes-executor.yaml
```

Point at external PostgreSQL (never deployed by this chart):

```sh
helm install pr-reviewer deploy/charts/pr-reviewer \
  -f deploy/charts/pr-reviewer/examples/values-controller-only.yaml \
  -f deploy/charts/pr-reviewer/examples/values-external-postgres.yaml
```

## Prerequisite Secrets

### Forgejo instance (`values-controller-only.yaml`)

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: pr-reviewer-instance-config
  namespace: pr-reviewer
stringData:
  # Full schema: docs/operator-config-and-adoption.md
  instance-config.yaml: |
    version: 1
    forges:
      - name: forge
        kind: forgejo
        endpoint: https://git.example.com
        credential: forge-token
    model-profiles:
      - name: local-fast
        endpoint: https://model-endpoint.example.com/v1
        api-format: openai
        credential: model-key
        model: <model-id>
    default-model-profile: local-fast
    executor-profiles:
      - name: in-process
        kind: local
        local:
          command: node
          args: ["/app/dist/index.js", "worker"]
    default-executor-profile: in-process
    evidence-profiles:
      - name: default
        providers-file: /config/evidence-providers.json
    default-evidence-profile: default
---
apiVersion: v1
kind: Secret
metadata:
  name: pr-reviewer-control-plane
  namespace: pr-reviewer
stringData:
  dsn: postgresql://pr_reviewer:REPLACE_ME@postgres.example.com:5432/pr_reviewer
---
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-webhook-secret
  namespace: pr-reviewer
stringData:
  webhook-secret: REPLACE_ME
---
apiVersion: v1
kind: Secret
metadata:
  name: forgejo-token
  namespace: pr-reviewer
stringData:
  token: REPLACE_ME
---
apiVersion: v1
kind: Secret
metadata:
  name: pr-reviewer-admin
  namespace: pr-reviewer
stringData:
  token: REPLACE_ME
---
apiVersion: v1
kind: Secret
metadata:
  name: model-credentials
  namespace: pr-reviewer
stringData:
  model-key: REPLACE_ME
```

### GitHub App instance (`values-kubernetes-executor.yaml`)

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: pr-reviewer-control-plane
  namespace: pr-reviewer
stringData:
  dsn: postgresql://pr_reviewer:REPLACE_ME@postgres.example.com:5432/pr_reviewer
---
apiVersion: v1
kind: Secret
metadata:
  name: github-webhook-secret
  namespace: pr-reviewer
stringData:
  webhook-secret: REPLACE_ME
---
# The GitHub App's PEM private key. The key NAME in the Secret becomes
# the mounted file name; the chart points
# PR_REVIEWER_GITHUB_APP_PRIVATE_KEY_FILE at it.
apiVersion: v1
kind: Secret
metadata:
  name: github-app-private-key
  namespace: pr-reviewer
stringData:
  private-key.pem: |
    -----BEGIN PRIVATE KEY-----
    REPLACE_ME
    -----END PRIVATE KEY-----
---
apiVersion: v1
kind: Secret
metadata:
  name: model-credentials
  namespace: pr-reviewer
stringData:
  model-key: REPLACE_ME
```

## Notes

- The instance config must declare forges for exactly ONE platform per
  instance; run one controller instance per forge platform.
- `PR_REVIEWER_CREDENTIAL_<REF>` material is provided through
  `controller.credentials` (each reference the model profiles name).
- The admin listener is served on `controller.admin.port`, guarded by the
  admin bearer token and bound pod-wide (`PR_REVIEWER_ADMIN_BIND=0.0.0.0`)
  when enabled; `kubectl exec` + loopback also works for local debugging.
- The chart's `networkPolicy` is default-deny; the webhook port accepts
  ingress from any source by default (the forge delivery path) — narrow
  it with `networkPolicy.additionalIngress`.
