#!/usr/bin/env bash
kubectl --context teyvat get deployments --all-namespaces -l nfsMount=true -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name" --no-headers | awk '{print "kubectl --context teyvat rollout restart deployment/"$2" -n "$1}' | sh
