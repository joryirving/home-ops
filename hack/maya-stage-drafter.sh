#!/usr/bin/env bash
# Put the pinned DFlash2 drafter on Maya's data claim, so enabling drafting
# later needs no download in front of the GPU. `[cluster]` defaults to `main`.
#
# The pod asks for no GPU and starts no engine: it only mounts the claim next to
# Strata's own work on ganyu. It refuses to run while a Maya pod exists, because
# the claim is ReadWriteOnce. Nothing here changes a manifest or a route.
set -euo pipefail

CTX="${1:-main}"
NS=llm
POD=maya-stage-drafter
CLAIM=project-maya-ganyu-data
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE=$(awk '/image: ghcr.io\/joryirving\/maya:/ {print $2; exit}' \
  "$HERE/../kubernetes/apps/base/llm/litellm/project-maya.yaml")

# The pins upstream 1.1.67 holds for the drafter (maya.py's DFLASH dict). The
# drafter is licensed CC BY-NC-ND 4.0: non-commercial use only.
REPO=Anbeeld/GLM-5.3-Flash-DFlash2-GGUF
REVISION=f3569acb7f9cee95e66d24442d75536eb00ab842
FILE=GLM-5.3-Flash-DFlash2-Q4_K_M.gguf
BYTES=697017248
SHA256=f4158ffb805b26c4fe439669c2009908a80ea89e1576ecea4d03eaded18f017c
FOLDER=/data/GLM-5.3-Flash-DFlash2

K="kubectl --context $CTX -n $NS"

if [ -z "$IMAGE" ]; then
  echo "could not read the Maya image from project-maya.yaml" >&2
  exit 1
fi
if [ -n "$($K get pods -l app=project-maya-glm-5-3-flash-s24 -o name 2>/dev/null || true)" ]; then
  echo "a Maya pod is running: $CLAIM is in use. Stop Maya first, or stage by hand." >&2
  exit 1
fi

cleanup() { $K delete pod "$POD" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT
$K delete pod "$POD" --ignore-not-found --wait=true >/dev/null 2>&1 || true

# No priorityClassName: priority 0 cannot preempt anything, and preempts last.
# The claim is bound to ganyu, so the selector only says so out loud.
$K apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  labels:
    krr/ignore: "true"
spec:
  restartPolicy: Never
  nodeSelector:
    topology.kubernetes.io: egpu
  tolerations:
    - key: llm-workload
      operator: Exists
      effect: NoSchedule
  containers:
    - name: stage
      image: $IMAGE
      imagePullPolicy: IfNotPresent
      command: ["/bin/sh", "-c", "sleep 3600"]
      securityContext:
        runAsUser: 0
        runAsGroup: 0
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
          # Only so the check below can read the file as Maya's user. The pod
          # still runs as root and asks for no GPU.
          add: ["SETUID", "SETGID"]
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
        limits:
          memory: 1Gi
      volumeMounts:
        - name: maya-data
          mountPath: /data
  volumes:
    - name: maya-data
      persistentVolumeClaim:
        claimName: $CLAIM
EOF

echo "waiting for $POD ..."
if ! $K wait --for=condition=Ready "pod/$POD" --timeout=5m; then
  echo "the pod did not start; node ganyu may be out of room:" >&2
  $K describe pod "$POD" | sed -n '/Events:/,$p' >&2
  exit 1
fi

# Piped on stdin: the image has no tar, so kubectl cp would fail.
OUT=$($K exec -i "$POD" -- /opt/maya/.venv/bin/python - "$FOLDER" "$REPO" "$REVISION" "$FILE" \
  "$BYTES" "$SHA256" < "$HERE/maya-stage-drafter.py")
echo "$OUT"
case "$OUT" in
  *"sha256=$SHA256"*) echo "matches the pinned sha256 and size" ;;
  *) echo "the helper did not report the pinned file" >&2; exit 1 ;;
esac

# A second read of the claim, for the record: the helper above is the one that
# checked, so list the folder as it stands before the pod goes away. Maya reads
# the claim as UID 65534 after setpriv, so read it that way too: the folder's
# mode and the file's mode both have to allow it.
echo
$K exec "$POD" -- /bin/sh -c "ls -ld $FOLDER && ls -l $FOLDER && wc -c < $FOLDER/$FILE && setpriv --reuid 65534 --regid 65534 --clear-groups /opt/maya/.venv/bin/python -c 'import sys; print(\"readable as 65534:\", len(open(sys.argv[1], \"rb\").read(4096)), \"bytes\")' $FOLDER/$FILE"

cat <<'NOTE'

Staged. This does not enable drafting: set DRAFT=on in
kubernetes/apps/base/llm/litellm/project-maya.yaml (with PARALLEL=1) when you want it.
NOTE
