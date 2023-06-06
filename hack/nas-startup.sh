## Scale up NFS namespaces
kubectl get statefulset -n downloads -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=1 sts/$LINE -n downloads; done;
kubectl get statefulset -n downloads -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=1 sts/$LINE -n downloads; done;

kubectl get statefulset -n media -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=1 sts/$LINE -n media; done;
kubectl get statefulset -n media -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=1 sts/$LINE -n media; done;

#Restart Daemonset
kubectl get daemonset -n downloads -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl rollout restart daemonset $LINE -n downloads; done;
