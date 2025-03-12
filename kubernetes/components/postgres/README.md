# crunchy-postgres

## Postgres Clusters

```sh
kubectl get cronjob --all-namespaces -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers | \
grep -E 'repo[0-9]+-(diff|full|incr)$' | \
xargs -n2 sh -c 'kubectl patch cronjob $1 -n $0 --type=merge -p "{\"spec\": {\"successfulJobsHistoryLimit\": 0}}"' 
```
