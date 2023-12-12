#!/usr/bin/env bash
cluster=${1:-default}
kubectl get job -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --context $cluster | awk '/src/ {print $1, $2}' | while read -r job namespace; do kubectl delete job "$job" -n "$namespace" --context $cluster; done
kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --context $cluster | awk '/src/ {print $1, $2}' | while read -r pvc namespace; do kubectl patch pvc "$pvc" -n "$namespace" -p '{"metadata":{"finalizers":null}}' --type=merge --context $cluster; done
kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace --context $cluster | awk '/src/ {print $1, $2}' | while read -r pvc namespace; do kubectl delete pvc "$pvc" -n "$namespace" --context $cluster; done
