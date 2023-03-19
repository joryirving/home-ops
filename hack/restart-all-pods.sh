### WARNING ###
## This will restart all pods in all namespaces! ##
## Use this carefully ##
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  for kind in deploy daemonset statefulset; do
    kubectl get "${kind}" -n "${ns}" -o name | xargs -I {} kubectl rollout restart {} -n "${ns}"
  done
done