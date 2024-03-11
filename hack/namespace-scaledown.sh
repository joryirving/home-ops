#!/usr/bin/env bash
NAMESPACE=${1:-default}
CLUSTER=${1:-main}
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $CLUSTER|grep -iv NAME|while read LINE; do kubectl scale --replicas=0 sts/$LINE -n $NAMESPACE --context $CLUSTER; done;
kubectl get deployment -n $NAMESPACE -o custom-columns=NAME:.metadata.name --context $CLUSTER|grep -iv NAME|while read LINE; do kubectl scale --replicas=0 deployment/$LINE -n $NAMESPACE --context $CLUSTER; done;
