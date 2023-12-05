kubectl get daemonset -n storage -o custom-columns=NAME:.metadata.name --context main|grep -iv NAME|while read LINE; do kubectl rollout restart daemonset $LINE -n storage --context main; done;
kubectl get deployments -n storage -o custom-columns=NAME:.metadata.name --context main|grep -iv NAME|while read LINE; do kubectl rollout restart deployment $LINE -n storage --context main; done;
