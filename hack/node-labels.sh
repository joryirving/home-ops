# Label control planes
## PreferNoSchedule
kubectl taint nodes raiden node-role.kubernetes.io/master=true:PreferNoSchedule

## NoSchedule
kubectl taint nodes zhongli nahida node-role.kubernetes.io/control-plane=true:NoSchedule

# Label workers
kubectl label nodes eula ayaka node-role.kubernetes.io/worker=true
kubectl label nodes yelan node-role.kubernetes.io/light-worker=true

# Label Longhorn nodes
kubectl label nodes eula ayaka yelan node.longhorn.io/create-default-disk=true
