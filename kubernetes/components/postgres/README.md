# crunchy-postgres

## Postgres Clusters

### Disabling successfulJobsHistoryLimit

```sh
kubectl get cronjob --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers | \
grep -E 'repo[0-9]+-(diff|full|incr)$' | \
xargs -n2 sh -c 'kubectl patch cronjob $1 -n $0 --type=merge -p "{\"spec\": {\"successfulJobsHistoryLimit\": 0}}"' 
```

### Boostraping new cluster

```yaml
patches:
- patch: |-
    - op: remove
    path: /spec/dataSource
target:
    kind: PostgresCluster
```
