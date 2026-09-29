# Operational Scripts

Miscellaneous scripts for cluster operations. `[cluster]` is a kube context name and defaults to `main`.

## Scripts

| Script                                     | Purpose                                                                                                            | Warning                                                                                                                       |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `cert-extract.sh`                          | Extract TLS cert from cluster and deploy to Caddy/Unifi/PiKVM                                                      | -                                                                                                                             |
| `delete-stuck-ns.sh <namespace> [cluster]` | Finalizes every `Terminating` namespace in the cluster                                                             | The namespace argument is currently ignored; uses GNU `sed -i` syntax                                                         |
| `nas-restart.sh [cluster]`                 | Restart deployments labelled `nfsMount=true`                                                                       | Broken: `$CLUSTER` isn't exported to the generated commands, so they fail unless `CLUSTER` is already set in your environment |
| `restart-all-pods.sh [cluster]`            | Restart all deployments, daemonsets and statefulsets in all namespaces                                             | **Destructive**; no shebang, run with `bash`                                                                                  |
| `llm-benchmark.py`                         | Measure per-request and aggregate decode tok/s and TTFT across concurrency levels on an OpenAI-compatible endpoint | Needs `httpx`; not executable, run with `python3`                                                                             |

## Usage

```bash
# Extract cert to Caddy (default)
./cert-extract.sh [cluster] caddy

# Extract cert to UniFi
./cert-extract.sh [cluster] unifi

# Extract cert to PiKVM
./cert-extract.sh [cluster] pikvm

# Finalize all Terminating namespaces (first argument is ignored)
./delete-stuck-ns.sh my-namespace [cluster]

# Restart NAS-mounted deployments (currently needs CLUSTER exported, see above)
./nas-restart.sh [cluster]

# Restart all pods (dangerous!)
bash ./restart-all-pods.sh [cluster]

# Benchmark an endpoint (defaults shown)
python3 ./llm-benchmark.py --base-url http://localhost:8088/v1 --model self-hosted --api-key none \
    --max-tokens 256 --iterations 2 --concurrency 1 2
```
