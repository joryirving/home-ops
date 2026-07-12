# Kopiur test canary

This is an isolated Kopiur canary for the `test` cluster. It uses two local
hostpath PVCs: one source claim and one Kopia repository claim. It has no
schedule, maintenance, or dependency on VolSync or production backup storage.

## Prerequisite

The `kopiur-test` item in the Kubernetes 1Password vault contains a dedicated
random `KOPIA_PASSWORD`. It does not reuse the production VolSync password.
External Secrets creates the `kopiur-canary-repository` Secret from that item.

## Validation

After Flux reconciles, wait for the seed job and repository:

```bash
kubectl --context test -n storage wait --for=condition=complete job/kopiur-canary-seed --timeout=5m
kubectl --context test -n storage wait --for=condition=Ready repository/kopiur-canary --timeout=5m
```

Create a one-shot backup. It is deliberately outside the reconciled manifests
so each run creates a new Snapshot:

```bash
kubectl --context test -n storage create -f - <<'EOF'
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Snapshot
metadata:
  generateName: kopiur-canary-
spec:
  policyRef:
    name: kopiur-canary
  deletionPolicy: Retain
EOF
kubectl --context test -n storage get snapshots
```

Wait for the generated Snapshot to reach `Succeeded`, then restore it to a new
PVC (replace `SNAPSHOT_NAME`):

```bash
kubectl --context test -n storage apply -f - <<'EOF'
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: kopiur-canary-restore
spec:
  source:
    snapshotRef:
      name: SNAPSHOT_NAME
  target:
    pvc:
      name: kopiur-canary-restored
      storageClassName: local-hostpath
      capacity: 1Gi
      accessModes: [ReadWriteOnce]
EOF
kubectl --context test -n storage wait --for=jsonpath='{.status.phase}'=Succeeded restore/kopiur-canary-restore --timeout=5m
kubectl --context test -n storage run kopiur-canary-verify --rm -i --restart=Never --image=ghcr.io/joryirving/busybox:1.38.0@sha256:4134704517da2f7d8392082461df5e065bf50da4d3b496376b9e5f033f31cb33 --overrides='{"spec":{"containers":[{"name":"verify","image":"ghcr.io/joryirving/busybox:1.38.0@sha256:4134704517da2f7d8392082461df5e065bf50da4d3b496376b9e5f033f31cb33","command":["/bin/sh","-ec","cd /data && sha256sum -c payload.sha256 && test \"$(cat payload)\" = \"kopiur test canary payload v1\""],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"kopiur-canary-restored"}}]}}'
```

Remove the `Restore` and restored PVC before repeating the restore with a new
Snapshot. Keep the repository PVC until you intentionally retire the canary.
