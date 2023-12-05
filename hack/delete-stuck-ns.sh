#!/usr/bin/env bash

ns=$1
cluster=${1:-default}

function delete_namespace () {
    echo "Deleting namespace $ns"
    kubectl get namespace $ns -o json > tmp.json --context $cluster
    sed -i 's/"kubernetes"//g' tmp.json
    kubectl replace --raw "/api/v1/namespaces/$1/finalize" -f ./tmp.json --context $cluster
    rm ./tmp.json
}

TERMINATING_NS=$(kubectl get ns | awk '$2=="Terminating" {print $1}' --context $cluster)

for ns in $TERMINATING_NS
do
    delete_namespace $ns
done
