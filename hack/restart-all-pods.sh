### WARNING ###
## This will restart all pods in all namespaces! ##
## Use this carefully ##
CLUSTER=${1:-teyvat}
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}' --context $CLUSTER); do
  for kind in deploy daemonset statefulset; do
    kubectl get "${kind}" -n "${ns}" -o name  --context $CLUSTER | xargs -I {} kubectl rollout restart {} -n "${ns}" --context $CLUSTER
  done
done
