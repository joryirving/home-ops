NAMESPACE=${1:-default}
cluster=${1:-default}

kubectl get deployments -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $cluster|grep -iv NAME|while read LINE; do kubectl rollout restart deployment $LINE -n $NAMESPACE --context $cluster; done;
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $cluster|grep -iv NAME|while read LINE; do kubectl rollout restart statefulset $LINE -n $NAMESPACE --context $cluster; done;
kubectl get daemonset -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $cluster|grep -iv NAME|while read LINE; do kubectl rollout restart daemonset $LINE -n $NAMESPACE --context $cluster; done;
