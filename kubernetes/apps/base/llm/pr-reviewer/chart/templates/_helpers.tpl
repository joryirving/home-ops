{{/*
Chart helpers for the #738 self-hosted chart.

The controller component is rendered through the bjw-s `common` library
(dependency `common`, pinned in Chart.yaml). Because the library reads
its API keys (`controllers`, `service`, `persistence`, `secrets`,
`serviceAccount`, `defaultPodOptions`, …) from top-level values, this
chart re-roots the render values on the `controller` section
(`pr-reviewer.component-values`) so operators use the familiar
app-template shapes nested under `controller`.

What the common library cannot express — the conditional env wiring that
maps values onto the controller's fail-closed environment contract
(src/controller/main.ts), conditional probes, and conditional rendered
Secrets/persistence — is injected in template land
(`pr-reviewer.controller.configure`) BEFORE the library renders.
*/}}

{{/*
The chart's resource name (mirrors the common library's name logic so
chart-injected objects and library-rendered objects never diverge).
*/}}
{{- define "pr-reviewer.name" -}}
{{- $name := .Values.nameOverride | default .Chart.Name -}}
{{- $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The chart's fully-qualified resource name (mirrors the common library's
fullname logic: overrides win, then release-name containment, then
release-chart).
*/}}
{{- define "pr-reviewer.fullname" -}}
{{- $name := include "pr-reviewer.name" . -}}
{{- $fullname := .Values.fullnameOverride -}}
{{- if empty $fullname -}}
{{- if contains $name .Release.Name -}}
{{- $fullname = .Release.Name -}}
{{- else -}}
{{- $fullname = printf "%s-%s" .Release.Name $name -}}
{{- end -}}
{{- end -}}
{{- $fullname | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully-qualified resource name computed from explicit parts (for custom
templates that render outside the component-scoped context).
*/}}
{{- define "pr-reviewer.resource-fullname" -}}
{{- $name := index . "nameOverride" | default (index . "chartName") -}}
{{- $name = $name | trunc 63 | trimSuffix "-" -}}
{{- $releaseName := index . "releaseName" -}}
{{- $fullname := index . "fullnameOverride" -}}
{{- if empty $fullname -}}
{{- if contains $name $releaseName -}}
{{- $fullname = $releaseName -}}
{{- else -}}
{{- $fullname = printf "%s-%s" $releaseName $name -}}
{{- end -}}
{{- end -}}
{{- $fullname | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
#735 credential env name: exactly `credentialEnvName` in
src/controller/main.ts — the reference uppercased with every
non-alphanumeric character mapped to `_`.
*/}}
{{- define "pr-reviewer.credential-env-name" -}}
{{- printf "PR_REVIEWER_CREDENTIAL_%s" (upper . | regexReplaceAll "[^A-Z0-9]" "_") -}}
{{- end -}}

{{/*
The component-scoped Values map: the component's section plus `global`,
ready to become a render context's `.Values` for the common library.
*/}}
{{- define "pr-reviewer.component-values" -}}
{{- $component := index . "component" -}}
{{- $root := index . "root" -}}
{{- $values := dict -}}
{{- /* the common library's own default values, which Helm merges in under
       the dependency key: bjw-s.common.values.init treats them as the base
       the component section is merged over */ -}}
{{- if hasKey $root.Values "common" -}}
{{- $_ := set $values "common" $root.Values.common -}}
{{- end -}}
{{- if hasKey $root.Values "global" -}}
{{- $_ := set $values "global" $root.Values.global -}}
{{- end -}}
{{- range $key, $value := (index $root.Values $component | default dict) -}}
{{- $_ := set $values $key $value -}}
{{- end -}}
{{- $values | toYaml -}}
{{- end -}}

{{/*
The controller container's environment: the complete mapping of chart
values onto the fail-closed env contract in src/controller/main.ts.
Conditional variables are genuinely ABSENT when their feature is off —
an empty `PR_REVIEWER_ADMIN_PORT` would be a startup refusal, not a
skip. Secret material always travels through secretKeyRef, never inline.
*/}}
{{- define "pr-reviewer.controller.env" -}}
{{- $v := .Values -}}
{{- $fullname := include "pr-reviewer.fullname" . -}}
- name: PR_REVIEWER_INSTANCE_CONFIG
  value: /config/instance-config.yaml
- name: PR_REVIEWER_CONTROL_PLANE_URL
  valueFrom:
    secretKeyRef:
      name: {{ ternary (printf "%s-control-plane" $fullname) $v.controlPlaneUrlExistingSecret.name (empty $v.controlPlaneUrlExistingSecret.name) }}
      key: {{ default "dsn" $v.controlPlaneUrlExistingSecret.key }}
- name: PR_REVIEWER_DURABLE_STATE_DIR
  value: {{ $v.paths.durableStateDir | quote }}
- name: PR_REVIEWER_RUNS_ROOT
  value: {{ $v.paths.runsRoot | quote }}
- name: PR_REVIEWER_WORKSPACE_CACHE_ROOT
  value: {{ $v.paths.workspaceCacheRoot | quote }}
{{- if $v.webhook.enabled }}
- name: PR_REVIEWER_WEBHOOK_PORT
  value: {{ $v.webhook.port | quote }}
- name: PR_REVIEWER_WEBHOOK_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ ternary (printf "%s-webhook" $fullname) $v.webhook.existingSecret.name (empty $v.webhook.existingSecret.name) }}
      key: {{ default "webhook-secret" $v.webhook.existingSecret.key }}
{{- end }}
{{- if $v.admin.enabled }}
- name: PR_REVIEWER_ADMIN_PORT
  value: {{ $v.admin.port | quote }}
- name: PR_REVIEWER_ADMIN_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ ternary (printf "%s-admin" $fullname) $v.admin.existingSecret.name (empty $v.admin.existingSecret.name) }}
      key: {{ default "token" $v.admin.existingSecret.key }}
{{/* the admin surface is bearer-token guarded (fail-closed) and the
NetworkPolicy bounds ingress, so the pod-wide wildcard is what makes
/healthz, /readyz and /metrics reachable by kubelet and Prometheus */}}
- name: PR_REVIEWER_ADMIN_BIND
  value: "0.0.0.0"
{{- if $v.admin.dashboard }}
{{/* #742 dashboard: rendered only when the knob is on, with the exact ON
spelling the lexical check in src/controller/main.ts accepts; OFF stays
genuinely absent — an empty value is never emitted (unset is OFF) */}}
- name: PR_REVIEWER_ADMIN_DASHBOARD
  value: "true"
{{- end }}
{{- end }}
{{- if $v.reconcile.enabled }}
- name: PR_REVIEWER_RECONCILE_INTERVAL_MS
  value: {{ $v.reconcile.intervalMs | quote }}
- name: PR_REVIEWER_RECONCILE_REPOS
  value: {{ join "," $v.reconcile.repos | quote }}
{{- if and (eq $v.forgeAuth.platform "github") (not (empty $v.reconcile.githubInstallationId)) }}
- name: PR_REVIEWER_GITHUB_APP_INSTALLATION_ID
  value: {{ $v.reconcile.githubInstallationId | quote }}
{{- end }}
{{- end }}
{{- if eq $v.forgeAuth.platform "github" }}
- name: PR_REVIEWER_GITHUB_APP_ID
  value: {{ $v.forgeAuth.github.appId | quote }}
- name: PR_REVIEWER_GITHUB_APP_PRIVATE_KEY_FILE
  value: {{ printf "/secrets/github-app/%s" (default "private-key.pem" $v.forgeAuth.github.appPrivateKeyExistingSecret.key) | quote }}
{{- else }}
- name: FORGEJO_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ $v.forgeAuth.forgejo.existingSecret.name }}
      key: {{ default "token" $v.forgeAuth.forgejo.existingSecret.key }}
{{- end }}
{{- range $ref, $cred := $v.credentials }}
{{- $secretRef := get $cred "existingSecret" | default dict }}
{{- $inlineKey := include "pr-reviewer.credential-env-name" $ref | trimPrefix "PR_REVIEWER_CREDENTIAL_" }}
- name: {{ include "pr-reviewer.credential-env-name" $ref }}
  valueFrom:
    secretKeyRef:
      name: {{ ternary (printf "%s-credentials" $fullname) $secretRef.name (empty $secretRef.name) }}
      key: {{ default $inlineKey $secretRef.key }}
{{- end }}
{{- with $v.followUp.model }}
- name: PR_REVIEWER_FOLLOWUP_MODEL
  value: {{ . | quote }}
{{- end }}
{{- with $v.followUp.mentions }}
- name: PR_REVIEWER_FOLLOWUP_MENTIONS
  value: {{ join "," . | quote }}
{{- end }}
{{- range $entry := $v.env }}
{{ toYaml (list $entry) }}
{{- end }}
{{- end -}}

{{/*
Controller container's probes. With the admin listener enabled it binds
the pod-wide wildcard (PR_REVIEWER_ADMIN_BIND=0.0.0.0), so kubelet HTTP
probes reach /healthz and /readyz on the admin port. Without it the
listener is loopback-only: readiness proves the webhook intake is bound
(TCP), and the exec fallback proves the node runtime is alive.
*/}}
{{- define "pr-reviewer.controller.probes" -}}
{{- $v := .Values -}}
liveness:
  enabled: true
{{- if $v.admin.enabled }}
  type: HTTP
  path: /healthz
  port: {{ $v.admin.port }}
{{- else }}
  type: COMMAND
  command: ["node", "-e", "process.exit(0)"]
{{- end }}
  spec:
    periodSeconds: 20
    failureThreshold: 6
readiness:
  enabled: true
{{- if $v.admin.enabled }}
  type: HTTP
  path: /readyz
  port: {{ $v.admin.port }}
{{- else if $v.webhook.enabled }}
  type: TCP
  port: {{ $v.webhook.port }}
{{- else }}
  type: COMMAND
  command: ["node", "-e", "process.exit(0)"]
{{- end }}
  spec:
    periodSeconds: 10
    failureThreshold: 6
{{- end -}}

{{/*
Validate the controller wiring fail-closed at render time and inject the
template-conditional pieces (env, probes, rendered Secrets, persistence)
into the component values before the common library renders. Signature:
dict "ctx" <component context> "workerExecutorKubernetes" <bool>.
*/}}
{{- define "pr-reviewer.controller.configure" -}}
{{- $ctx := index . "ctx" -}}
{{- $kubeExecutor := index . "workerExecutorKubernetes" -}}
{{- $v := $ctx.Values -}}
{{- $fullname := include "pr-reviewer.fullname" $ctx -}}

{{- /* fail closed on incomplete wiring — the daemon would refuse anyway */ -}}
{{- if empty (dig "controllers" "main" "containers" "main" "image" "repository" "" $v) -}}
{{- fail "controller.controllers.main.containers.main.image.repository is required" -}}
{{- end -}}
{{- if and (empty $v.controlPlaneUrl) (empty $v.controlPlaneUrlExistingSecret.name) -}}
{{- fail "controller.controlPlaneUrl or controller.controlPlaneUrlExistingSecret.name is required" -}}
{{- end -}}
{{- if and (empty $v.instanceConfig) (empty $v.instanceConfigExistingSecret.name) -}}
{{- fail "controller.instanceConfig or controller.instanceConfigExistingSecret.name is required" -}}
{{- end -}}
{{- if $v.webhook.enabled -}}
{{- if and (empty $v.webhook.secret) (empty $v.webhook.existingSecret.name) -}}
{{- fail "controller.webhook.secret or controller.webhook.existingSecret.name is required when the webhook intake is enabled" -}}
{{- end -}}
{{- end -}}
{{- if $v.admin.enabled -}}
{{- if and (empty $v.admin.token) (empty $v.admin.existingSecret.name) -}}
{{- fail "controller.admin.token or controller.admin.existingSecret.name is required when the admin listener is enabled" -}}
{{- end -}}
{{- end -}}
{{- if and $v.admin.dashboard (not $v.admin.enabled) -}}
{{- fail "controller.admin.dashboard requires controller.admin.enabled (the dashboard is served on the admin listener)" -}}
{{- end -}}
{{- if $v.reconcile.enabled -}}
{{- if and (eq $v.forgeAuth.platform "github") (empty $v.reconcile.githubInstallationId) -}}
{{- fail "controller.reconcile.githubInstallationId is required when reconciliation is enabled and forgeAuth.platform is github" -}}
{{- end -}}
{{- if empty $v.reconcile.repos -}}
{{- fail "controller.reconcile.repos must be a non-empty list when reconciliation is enabled" -}}
{{- end -}}
{{- end -}}
{{- if eq $v.forgeAuth.platform "github" -}}
{{- if empty $v.forgeAuth.github.appId -}}
{{- fail "controller.forgeAuth.github.appId is required when forgeAuth.platform is github" -}}
{{- end -}}
{{- if and (empty $v.forgeAuth.github.appPrivateKey) (empty $v.forgeAuth.github.appPrivateKeyExistingSecret.name) -}}
{{- fail "controller.forgeAuth.github private key material (appPrivateKey or appPrivateKeyExistingSecret.name) is required" -}}
{{- end -}}
{{- else -}}
{{- if and (empty $v.forgeAuth.forgejo.token) (empty $v.forgeAuth.forgejo.existingSecret.name) -}}
{{- fail "controller.forgeAuth.forgejo token material (token or existingSecret.name) is required" -}}
{{- end -}}
{{- end -}}

{{- /* secrets the chart renders itself (forceRenamed so the env wiring
       and the rendered objects can never drift apart) */ -}}
{{- $rendered := dict -}}
{{- if not (empty $v.controlPlaneUrl) -}}
{{- $_ := set $rendered "control-plane" (dict "forceRename" (printf "%s-control-plane" $fullname) "stringData" (dict "dsn" $v.controlPlaneUrl)) -}}
{{- end -}}
{{- if and $v.webhook.enabled (empty $v.webhook.existingSecret.name) -}}
{{- $_ := set $rendered "webhook" (dict "forceRename" (printf "%s-webhook" $fullname) "stringData" (dict "webhook-secret" $v.webhook.secret)) -}}
{{- end -}}
{{- if and $v.admin.enabled (empty $v.admin.existingSecret.name) -}}
{{- $_ := set $rendered "admin" (dict "forceRename" (printf "%s-admin" $fullname) "stringData" (dict "token" $v.admin.token)) -}}
{{- end -}}
{{- $inlineCredentials := dict -}}
{{- range $ref, $cred := $v.credentials -}}
{{- if not (empty (get $cred "value")) -}}
{{- $_ := set $inlineCredentials (include "pr-reviewer.credential-env-name" $ref | trimPrefix "PR_REVIEWER_CREDENTIAL_") (get $cred "value") -}}
{{- end -}}
{{- end -}}
{{- if not (empty $inlineCredentials) -}}
{{- $_ := set $rendered "credentials" (dict "forceRename" (printf "%s-credentials" $fullname) "stringData" $inlineCredentials) -}}
{{- end -}}
{{- if not (empty $v.instanceConfig) -}}
{{- $_ := set $rendered "instance-config" (dict "forceRename" (printf "%s-instance-config" $fullname) "stringData" (dict "instance-config.yaml" $v.instanceConfig)) -}}
{{- end -}}
{{- if and (eq $v.forgeAuth.platform "github") (not (empty $v.forgeAuth.github.appPrivateKey)) -}}
{{- $_ := set $rendered "github-app" (dict "forceRename" (printf "%s-github-app" $fullname) "stringData" (dict "private-key.pem" $v.forgeAuth.github.appPrivateKey)) -}}
{{- end -}}
{{- $_ := set $v "secrets" (mustMergeOverwrite ($v.secrets | default dict) $rendered) -}}

{{- /* persistence: the instance-config mount (chart-rendered secret or
       operator-provided existing secret), read-only */ -}}
{{- $instanceSecretName := "" -}}
{{- if not (empty $v.instanceConfig) -}}
{{- $instanceSecretName = printf "%s-instance-config" $fullname -}}
{{- else -}}
{{- $instanceSecretName = $v.instanceConfigExistingSecret.name -}}
{{- end -}}
{{- $_ := set $v "persistence" (mustMergeOverwrite ($v.persistence | default dict) (dict "instance-config" (dict "type" "secret" "name" $instanceSecretName "globalMounts" (list (dict "path" "/config" "readOnly" true))))) -}}

{{- /* GitHub App private key: mounted read-only — from the operator's
       existing secret, or from the chart-rendered one above; the env var
       names the file the mount produces */ -}}
{{- if eq $v.forgeAuth.platform "github" -}}
{{- $githubKeySecret := $v.forgeAuth.github.appPrivateKeyExistingSecret.name -}}
{{- if empty $githubKeySecret -}}
{{- $githubKeySecret = printf "%s-github-app" $fullname -}}
{{- end -}}
{{- $_ := set $v "persistence" (mustMergeOverwrite $v.persistence (dict "github-app" (dict "type" "secret" "name" $githubKeySecret "globalMounts" (list (dict "path" "/secrets/github-app" "readOnly" true))))) -}}
{{- end -}}

{{- /* env + probes: template-conditional, injected into the container */ -}}
{{- $controllers := deepCopy ($v.controllers | default dict) -}}
{{- $main := index $controllers "main" -}}
{{- $container := index (index $main "containers") "main" -}}
{{- $_ := set $container "env" (include "pr-reviewer.controller.env" $ctx | fromYamlArray) -}}
{{- $_ := set $container "probes" (include "pr-reviewer.controller.probes" $ctx | fromYaml) -}}
{{- if $kubeExecutor -}}
{{- /* the Kubernetes executor needs the controller's in-cluster identity
       to create/delete worker Jobs; otherwise no token is mounted */ -}}
{{- $_ := set $main "podOptions" (mustMergeOverwrite ($main.podOptions | default dict) (dict "automountServiceAccountToken" true)) -}}
{{- $sa := index ($v.serviceAccount | default dict) "main" -}}
{{- if not (empty $sa) -}}
{{- $_ := set $sa "automountServiceAccountToken" true -}}
{{- end -}}
{{- end -}}
{{- $_ := set $v "controllers" $controllers -}}
{{- end -}}
