# Label control planes
## PreferNoSchedule
# kubectl taint nodes FuXuan node-role.kubernetes.io/control-plane=true:PreferNoSchedule --context pi

# Label workers
kubectl label nodes bronya node-role.kubernetes.io/worker=true --context pi
kubectl label nodes bronya himeko jingliu kafka node.longhorn.io/create-default-disk=true --context pi
