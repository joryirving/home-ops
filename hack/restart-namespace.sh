NAMESPACE=${1:-default}

kubectl get deployments -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl rollout restart deployment $LINE -n $NAMESPACE; done;
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl rollout restart statefulset $LINE -n $NAMESPACE; done;
kubectl get daemonset -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl rollout restart daemonset $LINE -n $NAMESPACE; done;
