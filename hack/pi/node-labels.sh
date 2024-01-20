# Label control planes
## PreferNoSchedule
# kubectl taint nodes FuXuan node-role.kubernetes.io/control-plane=true:PreferNoSchedule --context pi

# Label workers
kubectl label nodes seele node-role.kubernetes.io/worker=true --context pi
kubectl label nodes fuxuan jingliu kafka seele node.longhorn.io/create-default-disk=true --context pi
