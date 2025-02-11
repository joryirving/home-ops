#!/usr/bin/env bash

set -euo pipefail

function log() {
    echo -e "\033[0;32m[$(date --iso-8601=seconds)] (${FUNCNAME[1]}) $*\033[0m"
}

function wait_for_crds() {
    local -r crds=(
        "ciliuml2announcementpolicies.cilium.io"
        "ciliumbgppeeringpolicies.cilium.io"
        "ciliumloadbalancerippools.cilium.io"
    )

    for crd in "${crds[@]}"; do
        until kubectl --context ${CLUSTER} get crd "$crd" &>/dev/null; do
            log "Waiting for Cilium CRD '${crd}'..."
            sleep 5
        done
    done
}

function apply_config() {
    if kubectl --context ${CLUSTER} --namespace kube-system diff --kustomize \
        "${CLUSTER_DIR}/apps/kube-system/cilium/config" &>/dev/null;
    then
        log "Cilium config is up-to-date. Skipping..."
    else
        log "Applying Cilium config..."
        kubectl --context ${CLUSTER} apply --namespace kube-system --server-side \
            --field-manager kustomize-controller \
            --kustomize "${CLUSTER_DIR}/apps/kube-system/cilium/config"
    fi
}

function main() {
    wait_for_crds
    apply_config
}

main "$@"
