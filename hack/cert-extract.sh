#!/bin/zsh
export TLS_CERT="jory.dev-tls"
export TLS_NAMESPACE="cert-manager"
CERT_DIR=/tmp/cert
CERT_TMP=$CERT_DIR/tmp
CERT_JSON=$CERT_DIR/certificate/certificate-tls.json
CLUSTER=${1:-main}

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
  scp $CERT_DIR/certificate.crt root@192.168.1.1:/data/unifi-core/config/unifi-core.crt
  scp $CERT_DIR/certificate.key root@192.168.1.1:/data/unifi-core/config/unifi-core.key
else
  echo "No change in certificates"
fi
rm $CERT_TMP
