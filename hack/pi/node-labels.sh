# Label control planes
## PreferNoSchedule
# kubectl taint nodes FuXuan node-role.kubernetes.io/control-plane=true:PreferNoSchedule --context pi

# Label workers
kubectl label nodes Jingliu Kafka Seele node-role.kubernetes.io/worker=true --context pi
kubectl label nodes FuXuan Jingliu Kafka Seele node.longhorn.io/create-default-disk=true --context pi
