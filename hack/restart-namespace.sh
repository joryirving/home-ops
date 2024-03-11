NAMESPACE=${1:-default}
CLUSTER=${1:-main}

kubectl get deployments -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $CLUSTER|grep -iv NAME|while read LINE; do kubectl rollout restart deployment $LINE -n $NAMESPACE --context $CLUSTER; done;
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $CLUSTER|grep -iv NAME|while read LINE; do kubectl rollout restart statefulset $LINE -n $NAMESPACE --context $CLUSTER; done;
kubectl get daemonset -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $CLUSTER|grep -iv NAME|while read LINE; do kubectl rollout restart daemonset $LINE -n $NAMESPACE --context $CLUSTER; done;
