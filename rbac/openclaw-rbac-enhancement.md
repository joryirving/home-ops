# OpenClaw RBAC Enhancement

## Current Limitations

OpenClaw currently lacks permissions to read:
- HelmReleases (`helm.toolkit.fluxcd.io/v1beta2`)
- Kustomizations (`kustomize.toolkit.fluxcd.io/v1beta2`)
- ExternalSecrets (`external-secrets.io/v1beta1`)
- Events in namespaces

This prevents effective troubleshooting of deployments like the recent ComfyUI issue.

## Required Changes

The `openclaw-openclaw-read-all` ClusterRole needs to be updated to include:

```yaml
rules:
# Add to existing core API rules
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# Add new rules for Flux CRDs
- apiGroups: ["helm.toolkit.fluxcd.io"]
  resources: ["helmreleases"]
  verbs: ["get", "list", "watch"]

- apiGroups: ["kustomize.toolkit.fluxcd.io"]
  resources: ["kustomizations"]
  verbs: ["get", "list", "watch"]

# Add new rules for External Secrets
- apiGroups: ["external-secrets.io"]
  resources: ["externalsecrets", "secretstores", "clustersecretstores"]
  verbs: ["get", "list", "watch"]
```

## Location

The ClusterRole `openclaw-openclaw-read-all` appears to be managed by a HelmRelease with the following metadata:
- Annotation: `meta.helm.sh/release-name: openclaw`
- Labels: `app.kubernetes.io/instance: openclaw`, `helm.toolkit.fluxcd.io/name: openclaw`

This configuration needs to be updated in the appropriate HelmRelease values file.
