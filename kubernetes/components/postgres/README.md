# crunchy-postgres

## Postgres Clusters

### Disabling successfulJobsHistoryLimit

```sh
kubectl get cronjob --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers | \
grep -E 'repo[0-9]+-(diff|full|incr)$' | \
xargs -n2 sh -c 'kubectl patch cronjob $1 -n $0 --type=merge -p "{\"spec\": {\"successfulJobsHistoryLimit\": 0}}"' 
```

### Boostraping new cluster

Add this to the `kustomization.yaml` to boostrap a new Postgres cluster that has no existing backups:

```yaml
  labels:
    components.postgres/cpgo: init
```

Set account to owner
Exec into the master pod for the postgres cluster:
```
psql
ALTER DATABASE <app> OWNER TO <app>;
```

Based on this [patch](https://github.com/joryirving/home-ops/blob/2f86fd78a27e4ece10b75dcf40d5d7215b8beb2b/kubernetes/clusters/main/apps.yaml#L158-L178), it will remove the datasource and start a blank cluster. You can remove this and it'll "restore" from the backup.
