#!/bin/bash

export TLS_CERT="jory-dev-tls"
export TLS_NAMESPACE="kube-system"
CERT_DIR="/tmp/cert"
CERT_TMP="$CERT_DIR/tmp"
CERT_JSON="$CERT_DIR/certificate/certificate-tls.json"
CLUSTER="${1:-utility}"
DESTINATION="${2:-caddy}"

# Set default values based on DESTINATION
if [[ "$DESTINATION" == "caddy" ]]; then
  SERVER="root@voyager"
  DIR="/mnt/user/docker/CaddyV2/data/certificates"
elif [[ "$DESTINATION" == "unifi" ]]; then
  SERVER="root@192.168.1.1"
  DIR="/data/unifi-core/config"
elif [[ "$DESTINATION" == "pikvm" ]]; then
  SERVER="root@192.168.1.11"
  DIR="/etc/kvmd/nginx/ssl"
else
  echo "Unknown DESTINATION: $DESTINATION"
  exit 1
fi

mkdir -p "$CERT_DIR/certificate/"

# Ensure certificate JSON exists
if [[ ! -f "$CERT_JSON" ]]; then
    echo "{}" > "$CERT_JSON"
fi

kubectl --context "$CLUSTER" get secret "$TLS_CERT" -n "$TLS_NAMESPACE" -ojson > "$CERT_TMP"

if ! diff "$CERT_TMP" "$CERT_JSON" >/dev/null; then
  echo "New certificates extracted"
else
  echo "No change in certificates"
fi

kubectl --context "$CLUSTER" get secret "$TLS_CERT" -n "$TLS_NAMESPACE" -ojsonpath="{.data.tls\.crt}" | base64 -d > "$CERT_DIR/certificate.crt"
kubectl --context "$CLUSTER" get secret "$TLS_CERT" -n "$TLS_NAMESPACE" -ojsonpath="{.data.tls\.key}" | base64 -d > "$CERT_DIR/certificate.key"

cp "$CERT_TMP" "$CERT_JSON"
cat "$CERT_DIR/certificate.crt" "$CERT_DIR/certificate.key" > "$CERT_DIR/certificate.pem"

# Transfer certificate and key atomically
if [[ "$DESTINATION" == "caddy" ]]; then
scp "$CERT_DIR/certificate.crt" "$SERVER:$DIR/wildcard.crt"
scp "$CERT_DIR/certificate.key" "$SERVER:$DIR/wildcard.key"
elif [[ "$DESTINATION" == "pikvm" ]]; then
scp "$CERT_DIR/certificate.crt" "$SERVER:$DIR/server.crt"
scp "$CERT_DIR/certificate.key" "$SERVER:$DIR/server.key"
else
scp "$CERT_DIR/certificate.pem" "$SERVER:$DIR"
fi

echo "Certificate copied to $DESTINATION"

rm -f "$CERT_TMP"
