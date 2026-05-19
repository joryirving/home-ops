# postgres-cnpg

CloudNativePG-backed Postgres component. Migration target for the existing `components/postgres` (CrunchyData PGO), which is being phased out due to the Snowflake acquisition.

## Substitution variables

| Variable    | Default                  | Notes                                                                 |
|-------------|--------------------------|-----------------------------------------------------------------------|
| `APP`       | _(required)_             | Name of the consuming app — used for cluster, secret, backup paths.   |
| `USERNAME`  | `${APP}`                 | App-level role (only honored on initial `initdb` bootstrap).          |
| `DATABASES` | `["${APP}"]`             | Reserved for future use (single-DB initdb today).                     |

## Bootstrap behavior

Default: the cluster bootstraps via `recovery` from the Barman archive at `s3://postgresql/${APP}` (Garage). This means a torn-down cluster will rebuild itself from the last backup.

For a brand-new app (no backup yet exists), add the `components.postgres/cnpg: init` label to the consuming Flux Kustomization. A patch in `clusters/main/apps.yaml` swaps `bootstrap.recovery` for `bootstrap.initdb` so the cluster comes up empty. Remove the label once the app is live and the first backup has completed.

## Connecting from an app

CNPG generates a `${APP}-app` Secret with these keys: `uri`, `jdbc-uri`, `username`, `password`, `host`, `port`, `dbname`, `pgpass`.

The standard pattern in an app-template HelmRelease:

```yaml
DATABASE_URL:
  valueFrom:
    secretKeyRef:
      name: "{{ .Release.Name }}-app"
      key: uri
```

This points directly at the cluster's read-write primary service `${APP}-rw`. There is no PgBouncer/Pooler in this first cut — see _Future work_.

## Health check expression

```yaml
healthCheckExprs:
  - apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
    current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
```

## Future work

- **PgBouncer/Pooler** — CNPG's `Pooler` CRD exists but doesn't generate its own connection secret, so adoption needs a wrapper to template `<cluster>-app` creds into a pooler-targeted URI. Re-add once that pattern is settled. Apps that rely on `transaction` pool mode (authentik) will need this before migrating.
- **Encryption at rest** — Barman supports server-side encryption (`wal.encryption: AES256`); enable once we've verified Garage's SSE behavior.
- **Promote back to `components/postgres/`** — once every app is migrated and CPGO is decommissioned, rename this folder to `components/postgres/` and update import paths.
