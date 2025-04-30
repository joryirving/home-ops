#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="debug"
export ROOT_DIR="$(git rev-parse --show-toplevel)"

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
    log debug "Waiting for nodes to be available"

    # Skip waiting if all nodes are 'Ready=True'
    if kubectl --context ${CLUSTER}  wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        log info "Nodes are available and ready, skipping wait for nodes"
        return
    fi

    # Wait for all nodes to be 'Ready=False'
    until kubectl --context ${CLUSTER} wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        log info "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
        sleep 10
    done
}

# CRDs to be applied before the helmfile charts are installed
function apply_crds() {
    log debug "Applying CRDs"

    local -r crds=(
        # renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
        https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
        # renovate: datasource=github-releases depName=prometheus-operator/prometheus-operator
        https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.82.0/stripped-down-crds.yaml
        # renovate: datasource=github-releases depName=kubernetes-sigs/external-dns
        https://raw.githubusercontent.com/kubernetes-sigs/external-dns/refs/tags/v0.16.1/docs/sources/crd/crd-manifest.yaml
    )

    for crd in "${crds[@]}"; do
        if kubectl --context ${CLUSTER} diff --filename "${crd}" &>/dev/null; then
            log info "CRDs are up-to-date" "crd=${crd}"
            continue
        fi
        if kubectl --context ${CLUSTER} apply --server-side --filename "${crd}" &>/dev/null; then
            log info "CRDs applied" "crd=${crd}"
        else
            log error "Failed to apply CRDs" "crd=${crd}"
        fi
    done
}

# Resources to be applied before the helmfile charts are installed
function apply_resources() {
    log debug "Applying resources"

    local -r resources_file="${ROOT_DIR}/bootstrap/resources.yaml.j2"

    if ! output=$(render_template "${resources_file}") || [[ -z "${output}" ]]; then
        exit 1
    fi

    if echo "${output}" | kubectl --context ${CLUSTER} diff --filename - &>/dev/null; then
        log info "Resources are up-to-date"
        return
    fi

    if echo "${output}" | kubectl --context ${CLUSTER} apply --server-side --filename - &>/dev/null; then
        log info "Resources applied"
    else
        log error "Failed to apply resources"
    fi
}

# Disks in use by rook-ceph must be wiped before Rook is installed
function wipe_rook_disks() {
    log debug "Wiping Rook disks"

    # Skip disk wipe if Rook is detected running in the cluster
    # NOTE: Is there a better way to detect Rook / OSDs?
    if kubectl --context ${CLUSTER} --namespace rook-ceph get kustomization rook-ceph &>/dev/null; then
        log warn "Rook is detected running in the cluster, skipping disk wipe"
        return
    fi

    if [ "$CSI_DISK" = "null" ]; then
        log warn "No disks to wipe"
        return
    fi

    if ! nodes=$(talosctl --talosconfig ${TALOS_DIR}/${CLUSTER}/clusterconfig/talosconfig config info --output json 2>/dev/null | jq --exit-status --raw-output '.nodes | join(" ")') || [[ -z "${nodes}" ]]; then
        log error "No Talos nodes found"
    fi

    log debug "Talos nodes discovered" "nodes=${nodes}"

    bus_path="/pci0000:00/0000:00:1c.4/0000:58:00.0/nvme"

    ## TODO: Uncomment this when I have different kinds of disks
    # # Wipe disks on each node that match the CSI_DISK environment variable
    for node in ${nodes}; do
        if ! disks=$(talosctl --talosconfig ${TALOS_DIR}/${CLUSTER}/clusterconfig/talosconfig --nodes "${node}" get disk --output json 2>/dev/null |
            jq --exit-status --raw-output --slurp '. | map(select(.spec.bus_path == ${bus_path}) | .metadata.id) | join(" ")') || [[ -z "${nodes}" ]]; then
            log error "No disks found" "node=${node}" "model=${bus_path}"
        fi

        log debug "Talos node and disk discovered" "node=${node}" "disks=${bus_path}"

        # Wipe each disk on the node
        for disk in ${disks}; do
            if talosctl --talosconfig ${TALOS_DIR}/${CLUSTER}/clusterconfig/talosconfig --nodes "${node}" wipe disk "${disk}" &>/dev/null; then
                log info "Disk wiped" "node=${node}" "disk=${disk}"
            else
                log error "Failed to wipe disk" "node=${node}" "disk=${target_disk}"
            fi
        done
    done
}

# Apply Helm releases using helmfile
function apply_helm_releases() {
    log debug "Applying Helm releases with helmfile"

    local -r helmfile_file="${ROOT_DIR}/bootstrap/helmfile.yaml"

    if [[ ! -f "${helmfile_file}" ]]; then
        log error "File does not exist" "file=${helmfile_file}"
    fi

    if ! helmfile --kube-context ${CLUSTER} --file "${helmfile_file}" apply --hide-notes --skip-diff-on-install --suppress-diff --suppress-secrets; then
        log error "Failed to apply Helm releases"
    fi

    log info "Helm releases applied successfully"
}

function main() {
    check_env KUBECONFIG KUBERNETES_VERSION CSI_DISK TALOS_VERSION CLUSTER
    check_cli helmfile jq kubectl kustomize minijinja-cli op talosctl yq

    if ! op whoami --format=json &>/dev/null; then
        log error "Failed to authenticate with 1Password CLI"
    fi

    # Apply resources and Helm releases
    wait_for_nodes
    wipe_rook_disks
    apply_crds
    apply_resources
    apply_helm_releases

    log info "Congrats! The cluster is bootstrapped and Flux is syncing the Git repository"
}

main "$@"
