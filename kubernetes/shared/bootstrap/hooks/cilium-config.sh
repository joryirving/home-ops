#!/usr/bin/env bash
set -euo pipefail
function wait_for_crds() {
    local -r crds=(
        "ciliuml2announcementpolicies.cilium.io"
        "ciliumbgppeeringpolicies.cilium.io"
        "ciliumloadbalancerippools.cilium.io"
    )
    for crd in "${crds[@]}"; do
        until kubectl --context ${CLUSTER} get crd "$crd" &>/dev/null; do
            echo "Waiting for CRD '${crd}'..."
            sleep 5
        done
    done
}
function apply_config() {
    echo "Checking if Cilium config needs to be applied..."
    if kubectl --context ${CLUSTER} diff \
        --namespace=kube-system \
        --kustomize \
        "${CLUSTER_DIR}/apps/kube-system/cilium/config" &>/dev/null;
    then
        echo "Cilium config is up to date. Skipping..."
    else
        echo "Applying Cilium config..."
        kubectl --context ${CLUSTER} apply \
            --namespace=kube-system \
            --server-side \
            --field-manager=kustomize-controller \
            --kustomize \
            "${CLUSTER_DIR}/apps/kube-system/cilium/config"
    fi
}
function main() {
    wait_for_crds
    apply_config
}
main "$@"
