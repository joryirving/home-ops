# Label control planes

## NoSchedule
#kubectl taint nodes navia node-role.kubernetes.io/control-plane=true:PreferNoSchedule- --context teyvat

# Label workers
kubectl label nodes ayaka eula ganyu hutao node-role.kubernetes.io/worker=true --context teyvat
