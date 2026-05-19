# postgres

CloudNativePG-backed Postgres component. Default Postgres for all apps in this repo (replaces the previous CrunchyData PGO setup that was retired due to the Snowflake acquisition).

## Substitution variables

| Variable            | Default        | Notes                                                                |
|---------------------|----------------|----------------------------------------------------------------------|
| `APP`               | _(required)_   | Name of the consuming app — used for cluster, secret, backup paths.  |
| `POSTGRES_USERNAME` | `${APP}`       | App-level role / database name created on initial bootstrap.         |

## Bootstrap behavior

**Default: `bootstrap.recovery` from Barman** at `s3://postgresql/${APP}/${APP}/`. A torn-down cluster (delete the `Cluster` CR + PVCs) rebuilds itself from the latest base backup + replays WAL. Same-path same-`serverName` rebuilds work because of the `cnpg.io/skipEmptyWalArchiveCheck: enabled` annotation — the recovered cluster inherits the source's `system_identifier` and writes new WAL on a new timeline (no name collisions).

**Net-new clusters (no backup yet exists):** add the `components.postgres/cnpg: init` label to the consuming Flux Kustomization. A patch in `clusters/main/apps.yaml` strips the `.recovery` block and the `externalClusters` list, leaving a plain `bootstrap.initdb` that brings the cluster up empty with `${POSTGRES_USERNAME:=${APP}}` as both the database name and the owner role. Remove the label once the cluster is live and the first scheduled backup has completed.

## Backups

Weekly full backups via the `ScheduledBackup` resource (Sunday 01:30, see `scheduledbackup.yaml`). Continuous WAL archiving to the same `s3://postgresql/${APP}/${APP}/` prefix. `retentionPolicy: 7d`.

## Connecting from an app

CNPG generates a `${APP}-app` Secret with these keys: `uri`, `jdbc-uri`, `username`, `password`, `host`, `port`, `dbname`, `pgpass`.

Standard app-template pattern:

```yaml
DATABASE_URL:
  valueFrom:
    secretKeyRef:
      name: "{{ .Release.Name }}-app"
      key: uri
```

The `uri` points at the cluster's read-write primary service `${APP}-rw`. There is no `Pooler` / PgBouncer in this component — apps connect directly. If transaction-mode pooling is ever needed (e.g. authentik at scale), add a `Pooler` CRD per cluster as a follow-up.

## Health check expression

```yaml
healthCheckExprs:
  - apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
    current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
```
