# pr-reviewer Helm chart

Self-hosted deployment of the pr-reviewer controller daemon (#1348) and
its Kubernetes worker-executor provisioning (#734/#738), built on the
bjw-s `common` library chart (pinned to `5.3.0` in `Chart.yaml`).

Scope and posture:

- **The chart never deploys PostgreSQL.** `controller.controlPlaneUrl`
  (or `controller.controlPlaneUrlExistingSecret`) points at an
  operator-provided database.
- **One forge platform per controller instance** (GitHub App or Forgejo
  token — see `examples/README.md` for the Secret manifests).
- **Fail-closed wiring.** Every env var the chart sets maps onto the
  controller's environment contract in `src/controller/main.ts`; a
  drift test (`tests-v3/deploy-packaging.test.ts`) keeps the chart from
  naming variables the entrypoint does not read. Incomplete wiring fails
  at `helm template` time, not at pod CrashLoop time.
- **`dist/` is not committed** (repo rule): images are built by CI /
  `deploy/images/Dockerfile`; the controller and worker images are
  self-contained bundles (no `node_modules`).

## Dependency management

`Chart.lock` and vendored `charts/` are intentionally not committed —
the repository `.gitignore` excludes them and CI runs
`helm dependency build` (see `.github/workflows/charts.yaml`). They must
NOT be listed in `.helmignore`: Helm 4 applies that file when *reading*
the chart directory, so ignoring the built dependency hides the bjw-s
common library templates at render time. Run
`helm dependency build deploy/charts/pr-reviewer` locally before
`helm template`/`install`.

## Release version synchronization

The chart's `appVersion` and the controller/worker image tags in
`examples/*.yaml` track the application release in
`.release-please-manifest.json`. Each version field carries an
`x-release-please-version` annotation and its file is listed under
`packages["."].extra-files` in `release-please-config.json`, so the standing
release PR bumps all of them together. `tests-v3/deploy-packaging.test.ts`
fails when a bound field and the manifest disagree, so a release PR cannot
land with stale deployment artifacts. The chart's own `version` (`0.1.0`)
is the independent Helm chart version and is never annotated.

## Values structure

- `controller` — the daemon: chart-owned wiring keys
  (`instanceConfig`, `controlPlaneUrl`, `webhook`, `admin`,
  `reconcile`, `forgeAuth`, `credentials`, `followUp`, `paths`, `env`)
  PLUS the bjw-s common passthrough sections (`controllers`, `service`,
  `persistence`, `secrets`, `serviceAccount`, `defaultPodOptions`, …)
  rendered for the controller component. The common library reads its
  API keys from the component's section (the chart re-roots the render
  values), so operator-side overrides work exactly like app-template.
- `workerExecutor` — provisions the objects AROUND the worker Jobs
  (`mode: kubernetes`): dedicated worker ServiceAccount
  (token never mounted), namespace-scoped Role/RoleBinding granting the
  CONTROLLER's service account `create/get/list/delete` on `batch/jobs`
  plus `create/get/list/update/patch/delete` on core `secrets` in the
  worker namespace (pods are never touched directly — the Job
  controller's background propagation removes them), and shared PVCs
  mounted at identical absolute paths in controller and workers. The
  secrets verbs exist for the per-run credential Secrets the executor
  projects: it creates/replaces them, rebinds each to the owning Job,
  label-lists its own material, and deletes them at settle; they are
  per-run and ephemeral, and `deploy/admission/worker-secret-policy.yaml`
  is the cluster-side guardrail on their shape.
  The Job manifests themselves are built by the executor from the
  instance config's `kubernetes` profile.
- `networkPolicy` (default ON) — default-deny policies for controller
  and worker pods; the worker selector matches the executor's
  `app.kubernetes.io/managed-by: pr-reviewer-action` pod label
  (WORKER_NETWORK_POSTURE in `src/executor/kubernetes.ts`).
- `serviceMonitor` (default OFF) — the admin listener serves `/metrics`;
  the chart binds it to the pod-wide wildcard when the admin surface is
  enabled, so a Prometheus scrape works out of the box (still guarded by
  the admin bearer token and the NetworkPolicy). Requires
  `controller.admin.enabled`.

## Security defaults

- `runAsNonRoot`, uid/gid 1000, `fsGroup` 65532, seccomp
  `RuntimeDefault`, all capabilities dropped, no privilege escalation,
  read-only root filesystem (writable roots are PVCs; `/tmp` is an
  emptyDir). `fsGroup` is the worker executor's pinned group
  (`WORKER_RUN_AS_ID`, uid/gid 65532): setgid propagation on the shared
  claims is what lets the controller read the worker's result file and
  the worker read the controller's envelope across the uid boundary
  (#1631).
- The controller's service-account token is mounted ONLY when
  `workerExecutor.mode: kubernetes` (the executor talks to the cluster
  API); otherwise `automountServiceAccountToken: false`.
- Worker pods never mount any token, and the worker NetworkPolicy
  denies all ingress and limits egress to DNS + TLS (the worker's
  request/result travel over shared volumes, not the network).
- Secret material always travels through `secretKeyRef` or secret
  mounts; inline values (`webhook.secret`, `admin.token`,
  `credentials.<ref>.value`) exist only for throwaway environments and
  are rendered into chart-managed Secrets.
- Model credentials are read from their Secret-backed environment variables
  at controller startup. Rotating a backing Secret therefore requires a
  controller rollout/restart; the chart does not claim live Secret watching.

## Admin/metrics reachability

The controller's admin listener defaults to loopback
(`PR_REVIEWER_ADMIN_BIND`, a closed literal-address allowlist in
`src/controller/main.ts`). Whenever `controller.admin.enabled` is set,
this chart binds it to the pod-wide wildcard (`0.0.0.0`) so kubelet HTTP
probes (`/healthz`, `/readyz`) and Prometheus scrapes (`/metrics`) work.
The surface stays guarded: health and metrics are content-free, the
`/admin/*` API requires the bearer token (refused at startup without
one), and the NetworkPolicy bounds which sources may reach the port.

The #742 operations dashboard (`GET /dashboard` on the admin listener)
stays off by default: `controller.admin.dashboard: false` leaves
`PR_REVIEWER_ADMIN_DASHBOARD` unset, and `true` renders
`PR_REVIEWER_ADMIN_DASHBOARD=true`. The knob requires
`controller.admin.enabled` (the render fails otherwise, because the flag
means nothing without the listener). The shell holds no data and needs
no token; every value it shows comes from the bearer-protected
`/admin/*` API. See `docs/architecture/operations-dashboard.md`.
