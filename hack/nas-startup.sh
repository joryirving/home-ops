#!/usr/bin/env bash
NAMESPACE=$1
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=1 sts/$LINE -n $NAMESPACE; done;
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=1 sts/$LINE -n $NAMESPACE; done;

#Restart Daemonset
kubectl get daemonset -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl rollout restart daemonset $LINE -n $NAMESPACE; done;
