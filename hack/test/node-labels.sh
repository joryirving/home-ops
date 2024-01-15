# Label control planes
## PreferNoSchedule
kubectl taint nodes venti node-role.kubernetes.io/control-plane=true:NoSchedule --context pi

# Label workers
kubectl label nodes kazuha node-role.kubernetes.io/worker=true --context pi
