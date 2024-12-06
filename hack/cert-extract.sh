#!/bin/zsh
export TLS_CERT="jory.dev-tls"
export TLS_NAMESPACE="network"
CERT_DIR=/tmp/cert
CERT_TMP=$CERT_DIR/tmp
CERT_JSON=$CERT_DIR/certificate/certificate-tls.json
CLUSTER=${1:-utility}
DESTINATION=${2:-caddy}

# Set default values based on DESTINATION
if [[ "$DESTINATION" == "caddy" ]]; then
  SERVER="root@voyager"
  PATH="/mnt/cache/docker/CaddyV2/data"
elif [[ "$DESTINATION" == "unifi" ]]; then
  SERVER="root@192.168.1.1"
  PATH="/data/unifi-core/config"
else
  echo "Unknown DESTINATION: $DESTINATION"
  exit 1
fi

mkdir -p $CERT_DIR/certificate/

if [[ -f "$CERT_JSON" ]]; then
    echo "certificate-tls.json exists"
else
    echo "Creating file"
    touch $CERT_JSON
fi

kubectl get secret $TLS_CERT -n $TLS_NAMESPACE -ojson > $CERT_TMP

DIFF="$(diff $CERT_TMP $CERT_JSON)"
if [[ "$DIFF" != "" ]]; then
  echo "New certificates extracted"
  kubectl --context $CLUSTER get secret $TLS_CERT -n $TLS_NAMESPACE -ojsonpath="{.data}" | jq '.["tls.crt"]' | sed -e s/\"//g | base64 -d > $CERT_DIR/certificate.crt
  kubectl --context $CLUSTER get secret $TLS_CERT -n $TLS_NAMESPACE -ojsonpath="{.data}" | jq '.["tls.key"]' | sed -e s/\"//g | base64 -d > $CERT_DIR/certificate.key
  cp $CERT_TMP $CERT_JSON
  cat $CERT_DIR/certificate.crt $CERT_DIR/certificate.key > $CERT_DIR/certificate.pem
  scp $CERT_DIR/certificate.crt $SERVER:$PATH
  scp $CERT_DIR/certificate.key $SERVER:$PATH
  echo "Certificate copied to $DESTINATION"
else
  echo "No change in certificates"
fi

rm $CERT_TMP
