# Label control planes
## PreferNoSchedule
kubectl taint nodes venti node-role.kubernetes.io/control-plane=true:PreferNoSchedule --context test

# Label workers
kubectl label nodes kazuha node-role.kubernetes.io/worker=true --context test
