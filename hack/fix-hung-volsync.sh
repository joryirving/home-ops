#!/usr/bin/env bash
kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace | awk '/src/ {print $1, $2}' | while read -r pvc namespace; do kubectl patch pvc "$pvc" -n "$namespace" -p '{"metadata":{"finalizers":null}}' --type=merge; done
kubectl get pvc -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace | awk '/src/ {print $1, $2}' | while read -r pvc namespace; do kubectl delete pvc "$pvc" -n "$namespace"; done
kubectl get job -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace | awk '/src/ {print $1, $2}' | while read -r job namespace; do kubectl delete job "$job" -n "$namespace"; done
