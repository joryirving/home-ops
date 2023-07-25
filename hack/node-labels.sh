# Label control planes

## NoSchedule
kubectl taint nodes raiden nahida node-role.kubernetes.io/control-plane=true:NoSchedule

# Label workers
kubectl label nodes eula ayaka node-role.kubernetes.io/worker=true

# Label Longhorn nodes
kubectl label nodes eula ayaka yelan node.longhorn.io/create-default-disk=true
