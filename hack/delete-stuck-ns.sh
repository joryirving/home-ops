#!/usr/bin/env bash

ns=$1
cluster=${2:-default}

function delete_namespace () {
    echo "Deleting namespace $ns"
    kubectl --context $cluster get namespace $ns -o json > tmp.json
    sed -i 's/"kubernetes"//g' tmp.json
    kubectl --context $cluster replace --raw "/api/v1/namespaces/$1/finalize" -f ./tmp.json
    rm ./tmp.json
}

TERMINATING_NS=$(kubectl --context $cluster get ns | awk '$2=="Terminating" {print $1}')

for ns in $TERMINATING_NS
do
    delete_namespace $ns
done
