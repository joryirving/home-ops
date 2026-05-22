---
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets
---
apiVersion: v1
kind: Namespace
metadata:
  name: flux-system
---
apiVersion: v1
kind: Namespace
metadata:
  name: network
---
apiVersion: v1
kind: Namespace
metadata:
  name: observability
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-credentials-secret
  namespace: external-secrets
data:
  1password-credentials.json: op://kubernetes/1password-{{ ENV.CLUSTER }}/OP_SESSION_JSON
---
apiVersion: v1
kind: Secret
metadata:
  name: onepassword-connect-vault-secret
  namespace: external-secrets
stringData:
  OP_CONNECT_TOKEN: op://kubernetes/1password-{{ ENV.CLUSTER }}/OP_CONNECT_TOKEN
---
apiVersion: v1
kind: Secret
metadata:
  name: jory-dev-tls
  namespace: kube-system
  annotations:
    cert-manager.io/alt-names: '*.jory.dev,jory.dev'
    cert-manager.io/certificate-name: jory-dev
    cert-manager.io/common-name: jory.dev
    cert-manager.io/ip-sans: ""
    cert-manager.io/issuer-group: ""
    cert-manager.io/issuer-kind: ClusterIssuer
    cert-manager.io/issuer-name: letsencrypt-production
    cert-manager.io/uri-sans: ""
  labels:
    controller.cert-manager.io/fao: "true"
type: kubernetes.io/tls
data:
  tls.crt: op://kubernetes/jory-dev-tls/tls.crt
  tls.key: op://kubernetes/jory-dev-tls/tls.key
