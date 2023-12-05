# Label control planes

## NoSchedule
kubectl taint nodes raiden nahida furina node-role.kubernetes.io/control-plane=true:NoSchedule --context main

# Label workers
kubectl label nodes eula ayaka hutao ganyu node-role.kubernetes.io/worker=true --context main

# Label Longhorn nodes
kubectl label nodes eula ayaka hutao ganyu node.longhorn.io/create-default-disk=true --context main
