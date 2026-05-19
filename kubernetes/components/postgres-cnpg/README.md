# postgres-cnpg

CloudNativePG-backed Postgres component. Migration target for the existing `components/postgres` (CrunchyData PGO), which is being phased out due to the Snowflake acquisition.

## Substitution variables

| Variable            | Default                | Notes                                                              |
|---------------------|------------------------|--------------------------------------------------------------------|
| `APP`               | _(required)_           | Name of the consuming app — used for cluster, secret, backup paths.|
| `POSTGRES_USERNAME` | `${APP}`               | App-level role / database name created on initial bootstrap.       |
| `CNPG_IMPORT_TYPE`  | `microservice`         | `microservice` (single DB) or `monolith` (full pg_dump).           |

## Bootstrap behavior

**Default (CPGO → CNPG migration window):** `bootstrap.initdb.import` from the live CPGO source.

The component declares a `${APP}-cpgo` `externalCluster` pointing at the in-cluster CPGO primary service (`${APP}-primary`) using the CPGO-generated `${APP}-pguser-postgres` secret. CNPG runs `pg_dump | pg_restore` natively as part of the new cluster's `initdb` phase. CPGO stays serving the app the whole time; cutover happens later when the app's `DATABASE_URL` is flipped.

`pgDumpExtraOptions` skip the `pg_stat_statements` and `pgaudit` extensions and the `pgbouncer` schema, which the dump role can't recreate on the CNPG side.

**Net-new clusters (no CPGO source):** add the `components.postgres/cnpg: init` label to the consuming Flux Kustomization. A patch in `clusters/main/apps.yaml` strips the `.import` block and the `externalClusters` list, leaving a plain `bootstrap.initdb` that brings the cluster up empty.

**Backups** flow to Barman at `s3://postgresql/${APP}/${APP}/` (serverName pinned to `${APP}` so write and read sides agree on the same prefix) with `retentionPolicy: 7d`.

**Future rebuilds:** once all apps are migrated off CPGO, a follow-up PR swaps the default from `bootstrap.initdb.import` to `bootstrap.recovery` from Barman. The `cnpg.io/skipEmptyWalArchiveCheck: enabled` annotation is set so same-path same-serverName rebuilds work.

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
