#!/usr/bin/env bash
NAMESPACE=$1
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=0 sts/$LINE -n $NAMESPACE; done;
kubectl get statefulset -n $NAMESPACE -o custom-columns=NAME:.metadata.name|grep -iv NAME|while read LINE; do kubectl scale --replicas=0 sts/$LINE -n $NAMESPACE; done;
