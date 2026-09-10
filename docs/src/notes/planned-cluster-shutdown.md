# Planned cluster shutdown

Use this runbook for planned power work, including a UPS replacement. It
hibernates CloudNativePG (CNPG) before the Talos nodes are shut down, preserving
database volumes while avoiding an unplanned PostgreSQL failover during the
power event.

Do not use this for an active outage. In that case, restore stable power first
and assess Ceph before changing workloads.

## Before starting

- Make sure the new UPS is ready and that someone has physical access to every
  node.
- Announce the outage and stop any maintenance, restore, or upgrade in
  progress.
- Confirm every node is Ready, Ceph is healthy, and there are no failing or
  pending pods:

  ```sh
  kubectl get nodes -o wide
  kubectl -n rook-ceph get cephcluster -o wide
  kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
  ```

- Confirm that each CNPG cluster is healthy and has a recent successful backup.
  Resolve any failed backup before continuing.

  ```sh
  kubectl get clusters.postgresql.cnpg.io -A -o wide
  kubectl get backups.postgresql.cnpg.io -A --sort-by=.metadata.creationTimestamp
  ```

## Hibernate CloudNativePG

CNPG hibernation performs a controlled PostgreSQL shutdown and leaves the
cluster data untouched. It is preferable to letting the nodes lose power with
database instances still running.

Pause the Flux reconciliation hierarchy first. The hibernation annotation is a
live maintenance action, not a committed manifest setting; without this pause,
Flux can remove the annotation and restart a database while the shutdown is in
progress. On `main`, `flux-system` owns `cluster-apps`, which owns the
application Kustomizations, so both must be paused in that order.

First record the target set:

```sh
kubectl get clusters.postgresql.cnpg.io -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIMARY:.status.currentPrimary,READY:.status.readyInstances,STATUS:.status.phase'
```

```sh
kubectl -n flux-system patch kustomization flux-system --type=merge \
  -p '{"spec":{"suspend":true}}'
kubectl -n flux-system patch kustomization cluster-apps --type=merge \
  -p '{"spec":{"suspend":true}}'

kubectl -n flux-system get kustomization flux-system cluster-apps \
  -o custom-columns='NAME:.metadata.name,SUSPENDED:.spec.suspend'
```

Then hibernate every CNPG cluster:

```sh
while IFS=/ read -r namespace name; do
  kubectl annotate cluster -n "$namespace" "$name" \
    cnpg.io/hibernation=on --overwrite
done < <(
  kubectl get clusters.postgresql.cnpg.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'
)
```

Wait for every cluster to report `Hibernated` with zero ready instances. Do
not proceed while any database pod remains. Hibernation respects each
cluster's `stopDelay`; on this cluster it is 30 minutes, so do not force-delete
a primary just to make the shutdown faster.

```sh
while IFS=/ read -r namespace name; do
  kubectl cnpg status -n "$namespace" "$name"
done < <(
  kubectl get clusters.postgresql.cnpg.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'
)

kubectl get pods -A -l cnpg.io/cluster
```

## Shut down Talos

Use Talos's normal shutdown path. It cordons and drains the node; do **not**
add `--force`, which skips that protection. Wait for each command to finish
before moving to the next node.

```sh
talosctl shutdown --nodes 10.69.1.24 # skirk: worker
talosctl shutdown --nodes 10.69.1.21 # ayaka: control plane + Ceph
talosctl shutdown --nodes 10.69.1.22 # eula: control plane + Ceph
talosctl shutdown --nodes 10.69.1.23 # ganyu: control plane + Ceph
```

After the last command completes, confirm the nodes are powered off before
unplugging or moving any power equipment.

## Bring the cluster back

1. Complete the UPS replacement, restore power, and start the three
   control-plane nodes before the worker.
2. Wait for the API and storage to recover:

   ```sh
   kubectl get nodes -o wide
   kubectl -n rook-ceph get cephcluster -o wide
   ```

   Continue only when all nodes are Ready and Ceph is `HEALTH_OK`.

3. Resume every CNPG cluster:

   ```sh
   while IFS=/ read -r namespace name; do
     kubectl annotate cluster -n "$namespace" "$name" \
       cnpg.io/hibernation=off --overwrite
   done < <(
     kubectl get clusters.postgresql.cnpg.io -A \
       -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'
   )
   ```

4. Wait for each database to have its expected primary and ready instances,
   then resume Flux reconciliation from the child application layer upward:

   ```sh
   kubectl -n flux-system patch kustomization cluster-apps --type=merge \
     -p '{"spec":{"suspend":false}}'
   kubectl -n flux-system patch kustomization flux-system --type=merge \
     -p '{"spec":{"suspend":false}}'
   ```

5. Confirm each database has its expected primary and ready instances, then
   check for workloads that did not recover normally:

   ```sh
   kubectl get clusters.postgresql.cnpg.io -A -o wide
   kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
   ```

6. Check the backup controller and the most recent backup result before
   declaring the maintenance complete.
