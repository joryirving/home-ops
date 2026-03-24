# Operational Scripts

Miscellaneous scripts for cluster operations.

## Scripts

| Script | Purpose | Warning |
|--------|---------|---------|
| `cert-extract.sh` | Extract TLS cert from cluster and deploy to Caddy/Unifi/PiKVM | - |
| `delete-stuck-ns.sh <namespace> [cluster]` | Force delete stuck terminating namespaces | - |
| `nas-restart.sh [cluster]` | Restart deployments with NFS mounts | - |
| `node-labels.sh` | Apply worker labels to nodes | Outdated - review before use |
| `restart-all-pods.sh [cluster]` | Restart all pods in all namespaces | **Destructive** |

## Usage

```bash
# Extract cert to Caddy (default)
./cert-extract.sh [cluster] caddy

# Extract cert to UniFi
./cert-extract.sh [cluster] unifi

# Extract cert to PiKVM
./cert-extract.sh [cluster] pikvm

# Delete stuck namespace
./delete-stuck-ns.sh my-namespace [cluster]

# Restart NAS-mounted deployments
./nas-restart.sh [cluster]

# Restart all pods (dangerous!)
./restart-all-pods.sh [cluster]
```
