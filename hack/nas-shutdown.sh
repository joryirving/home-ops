#!/usr/bin/env bash
NAMESPACE=${1:-default}
cluster=${1:-default}
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $cluster|grep -iv NAME|while read LINE; do kubectl scale --replicas=0 sts/$LINE -n $NAMESPACE --context $cluster; done;
kubectl get deployment -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $cluster|grep -iv NAME|while read LINE; do kubectl scale --replicas=0 deployment/$LINE -n $NAMESPACE --context $cluster; done;
