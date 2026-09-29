# Planned cluster shutdown

Use this runbook for planned power work, including a UPS replacement. It
hibernates CloudNativePG (CNPG) before the Talos nodes are shut down, preserving
database volumes while avoiding an unplanned PostgreSQL failover during the
power event.

Do not use this for an active outage. In that case, restore stable power first
and assess Ceph before changing workloads.

All commands target the `main` cluster (`--context main`). `kubectl cnpg`
needs the krew plugin (`task workstation:krew`).

The cluster depends on voyager (the NAS) for the kopiur NFS repository, app NFS
mounts, and CNPG backups to Garage (`https://s3.jory.dev`). Shut voyager down
after the last Talos node, and bring it up first.

## Before starting

- Make sure the new UPS is ready and that someone has physical access to every
  node.
- Announce the outage and stop any maintenance, restore, or upgrade in
  progress. Avoid the full Kopia maintenance window (03:00 America/Edmonton, up
  to 1h jitter) and the daily CNPG `ScheduledBackup` (cron `0 40 4 * * *`).
- Confirm every node is Ready, Ceph is healthy, and there are no failing or
  pending pods:

  ```sh
  kubectl --context main get nodes -o wide
  kubectl --context main -n rook-ceph get cephcluster -o wide
  kubectl --context main get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
  ```

- Confirm that each CNPG cluster is healthy and has a recent successful backup,
  and that kopiur has no failed snapshots. Resolve any failure before
  continuing.

  ```sh
  kubectl --context main get clusters.postgresql.cnpg.io -A -o wide
  kubectl --context main get backups.postgresql.cnpg.io -A --sort-by=.metadata.creationTimestamp | tail
  task kopiur:status CLUSTER=main
  ```

- Expect the Columbina Gatus heartbeat alert for `main` once Alertmanager stops
  (`ansible/columbina/templates/gatus-secrets.yaml.j2`).

## Hibernate CloudNativePG

CNPG hibernation performs a controlled PostgreSQL shutdown and leaves the
cluster data untouched. It is preferable to letting the nodes lose power with
database instances still running.

Suspend every Flux Kustomization first. The hibernation annotation is a live
maintenance action, not a committed manifest setting; without this, Flux can
remove the annotation and restart a database while the shutdown is in
progress. Suspending only `flux-system` and `cluster-apps` is not enough: the
application Kustomizations live in their app namespaces and keep reconciling on
their own.

First record the target set, and note any Kustomization that is already
suspended so it stays suspended on resume:

```sh
kubectl --context main get clusters.postgresql.cnpg.io -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,PRIMARY:.status.currentPrimary,READY:.status.readyInstances,STATUS:.status.phase'

flux get ks -A --context main
```

Suspend the parents, then every other Kustomization:

```sh
kubectl --context main -n flux-system patch kustomization flux-system --type=merge \
  -p '{"spec":{"suspend":true}}'
kubectl --context main -n flux-system patch kustomization cluster-apps --type=merge \
  -p '{"spec":{"suspend":true}}'

kubectl --context main get kustomizations.kustomize.toolkit.fluxcd.io -A --no-headers \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name' |
while read -r namespace name; do
  kubectl --context main -n "$namespace" patch kustomization "$name" --type=merge \
    -p '{"spec":{"suspend":true}}'
done

flux get ks -A --context main
```

Then hibernate every CNPG cluster:

```sh
while IFS=/ read -r namespace name; do
  kubectl --context main annotate clusters.postgresql.cnpg.io -n "$namespace" "$name" \
    cnpg.io/hibernation=on --overwrite
done < <(
  kubectl --context main get clusters.postgresql.cnpg.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'
)
```

Wait for every cluster to report `Hibernated` with zero ready instances. Do
not proceed while any database pod remains. Hibernation respects each
cluster's `stopDelay` (CNPG default 1800s; not overridden in
`kubernetes/components/postgres/cluster.yaml`), so do not force-delete a
primary just to make the shutdown faster.

```sh
while IFS=/ read -r namespace name; do
  kubectl --context main cnpg status -n "$namespace" "$name"
done < <(
  kubectl --context main get clusters.postgresql.cnpg.io -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'
)

kubectl --context main get pods -A -l cnpg.io/cluster
```

## Set Ceph noout

Stop Ceph from marking OSDs out and rebalancing while nodes are down:

```sh
kubectl --context main -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
```

## Shut down Talos

Use Talos's normal shutdown path for the first nodes. It cordons and drains the
node; wait for each command to finish before moving to the next.

```sh
talosctl --context main shutdown --nodes 10.69.1.24 # skirk: worker
talosctl --context main shutdown --nodes 10.69.1.21 # ayaka: control plane + Ceph
```

Once a Ceph node is down, Rook's OSD PodDisruptionBudgets block further drains,
and after two control-plane nodes are down etcd and the Ceph mons lose quorum,
so draining the last nodes stalls. With CNPG hibernated and `noout` set, shut
the remaining two down back-to-back without draining:

```sh
talosctl --context main shutdown --force --nodes 10.69.1.22 # eula: control plane + Ceph
talosctl --context main shutdown --force --nodes 10.69.1.23 # ganyu: control plane + Ceph
```

Confirm the nodes are powered off, then shut down voyager. Before unplugging or
moving any power equipment, stop `nut-monitor` on venti so it does not act on
the UPS disconnect (see [rpi-nut](./rpi-nut.md)).

## Bring the cluster back

1. Complete the UPS replacement and restore power. If the UPS model changed,
   update `ups.conf` and the `MONITOR` line on the Pi and the `server`/`ups`
   params in
   `kubernetes/apps/base/observability/exporters/nut-exporter/servicemonitor.yaml`,
   then start `nut-monitor` again.
2. Power on voyager first. Wait for its NFS exports and `https://s3.jory.dev` to
   respond before starting any Talos node.
3. Start the three control-plane nodes, then the worker.
4. Wait for the API and storage to recover:

   ```sh
   kubectl --context main get nodes -o wide
   kubectl --context main -n rook-ceph get cephcluster -o wide
   ```

   Ceph reports `HEALTH_WARN` while `noout` is set. Once all nodes are Ready,
   all OSDs are up, and `noout` is the only warning, unset it and wait for
   `HEALTH_OK`:

   ```sh
   kubectl --context main -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
   ```

5. Resume every CNPG cluster:

   ```sh
   while IFS=/ read -r namespace name; do
     kubectl --context main annotate clusters.postgresql.cnpg.io -n "$namespace" "$name" \
       cnpg.io/hibernation=off --overwrite
   done < <(
     kubectl --context main get clusters.postgresql.cnpg.io -A \
       -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}'
   )
   ```

6. Wait for each database to have its expected primary and ready instances:

   ```sh
   kubectl --context main get clusters.postgresql.cnpg.io -A -o wide
   ```

7. Resume Flux from the application layer upward, then re-suspend any
   Kustomization that was suspended before the maintenance:

   ```sh
   kubectl --context main get kustomizations.kustomize.toolkit.fluxcd.io -A --no-headers \
     -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name' |
   while read -r namespace name; do
     case "$namespace/$name" in
       flux-system/flux-system | flux-system/cluster-apps) continue ;;
     esac
     kubectl --context main -n "$namespace" patch kustomization "$name" --type=merge \
       -p '{"spec":{"suspend":false}}'
   done

   kubectl --context main -n flux-system patch kustomization cluster-apps --type=merge \
     -p '{"spec":{"suspend":false}}'
   kubectl --context main -n flux-system patch kustomization flux-system --type=merge \
     -p '{"spec":{"suspend":false}}'

   flux get ks -A --context main
   ```

8. Check for workloads that did not recover normally:

   ```sh
   kubectl --context main get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
   ```

9. Check backups before declaring the maintenance complete:

   ```sh
   task kopiur:status CLUSTER=main
   kubectl --context main get backups.postgresql.cnpg.io -A --sort-by=.metadata.creationTimestamp | tail
   ```
