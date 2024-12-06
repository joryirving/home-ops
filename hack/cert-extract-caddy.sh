#!/bin/bash

# Define the namespace and secret name of your cert-manager wildcard cert
NAMESPACE="network"
SECRET_NAME="domain.tld-tls"
CLUSTER="utility"

# Define the destination Caddy server info
CADDY_SERVER="user@host"
CADDY_PATH="/path/to/data"

# Define the temporary files
CERT_FILE="/tmp/cert.crt"
KEY_FILE="/tmp/cert.key"

# Use kubectl to fetch the certificate and private key
kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' --context $CLUSTER | base64 -d > $CERT_FILE
kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.tls\.key}' --context $CLUSTER | base64 -d > $KEY_FILE

# SCP the certificate and key to the Caddy container's directory
scp $CERT_FILE $CADDY_SERVER:$CADDY_PATH/certificates/wildcard.crt
scp $KEY_FILE $CADDY_SERVER:$CADDY_PATH/certificates/wildcard.key

# Clean up temporary files
rm -f $CERT_FILE $KEY_FILE

echo "Certificate copied to Caddy"
