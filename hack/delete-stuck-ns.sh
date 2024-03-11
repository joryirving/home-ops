#!/usr/bin/env bash

NAMESPACE=$1
CLUSTER=${2:-main}

function delete_namespace () {
    echo "Deleting namespace $NAMESPACE"
    kubectl --context $CLUSTER get namespace $NAMESPACE -o json > tmp.json
    sed -i 's/"kubernetes"//g' tmp.json
    kubectl --context $CLUSTER replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f ./tmp.json
    rm ./tmp.json
}

TERMINATING_NS=$(kubectl --context $CLUSTER get ns | awk '$2=="Terminating" {print $1}')

for NAMESPACE in $TERMINATING_NS
do
    delete_namespace $NAMESPACE
done
