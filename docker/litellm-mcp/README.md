# LiteLLM MCP runtime image

`ghcr.io/joryirving/litellm-mcp:1.104.0-mcp1` extends the pinned LiteLLM database image with the four existing stdio servers. It preserves the base image's LiteLLM entrypoint and command for the operator proxy. Configure an MCP server with command `python3` and args `["/opt/mcp/launch.py", "<server>"]`, where `<server>` is `arr`, `seerr`, `github`, or `dispatch`.

The launcher starts one child with a fixed executable, fixed arguments, and an explicit allowlist environment. It does not forward the parent environment, read LiteLLM provider/admin keys, invoke a shell, or perform package installation at launch. LiteLLM v1.104.0's MCP stdio client (`mcp/client/stdio.py`) passes safe defaults plus `server.env`, not the complete proxy environment; credentials are therefore read from files, not inherited from the proxy.

## Secret mount contract

Mount each Kubernetes Secret read-only into its matching directory under `/var/run/litellm-mcp`. Secret data key names remain exactly as shown:

| Server | Secret name | Key and file path | Child environment name |
| --- | --- | --- | --- |
| `arr` | `litellm-mcp-sonarr` | `/var/run/litellm-mcp/arr/SONARR_API_KEY` | `SONARR_API_KEY` |
| `arr` | `litellm-mcp-radarr` | `/var/run/litellm-mcp/arr/RADARR_API_KEY` | `RADARR_API_KEY` |
| `arr` | `litellm-mcp-prowlarr` | `/var/run/litellm-mcp/arr/PROWLARR_API_KEY` | `PROWLARR_API_KEY` |
| `seerr` | `litellm-mcp-seerr` | `/var/run/litellm-mcp/seerr/SEERR_API_KEY` | `SEERR_API_KEY` |
| `github` | `litellm-mcp-github` | `/var/run/litellm-mcp/github/token` | `GITHUB_PERSONAL_ACCESS_TOKEN` |
| `dispatch` | `litellm-mcp-dispatch` | `/var/run/litellm-mcp/dispatch/token` | `DISPATCH_AGENT_TOKEN` |

All six credential files will be readable in the shared LiteLLM pod filesystem by design. The launcher only loads the selected server's allowlisted files into its child's environment; this is not a per-server filesystem sandbox. The proxy/stdio processes run as UID/GID 1000; the coordinator's pod security context uses UID/GID 1000 and `fsGroup: 1000`, with all stdio Secret volumes mode `0440`. Kubernetes service-account credentials should remain disabled for the LiteLLM pod. Docker smoke tests model the nonroot process, dropped capabilities, no-new-privileges, read-only root filesystem, tmpfs, and writable UI/cache paths with supplemental GID 1000. Real PVC ownership and kubelet `fsGroupChangePolicy: OnRootMismatch` behavior still need a live-cluster acceptance check; Docker directory ownership is not proof of NFS/Ceph volume semantics.

## Runtime dependencies and source evidence

- `ghcr.io/berriai/litellm-database:v1.104.0@sha256:fbe28229d2d02181c0a7d9df9599de614b491f3d897d2d7da18404f088310218` is the requested base. The amd64 image contains Python 3.13, `/usr/bin/node` v26.10.0, and `/bin/sh`; the requested exact digest was verified by pulling it.
- The original `arr-mcp` manifest invoked `npx -y mcp-arr-server@1.5.4`. That npm version is pinned. Its tarball declares only `@modelcontextprotocol/sdk` as a runtime dependency, ships `dist/index.js`, and has `build` / `prepublishOnly` scripts only; `prepublishOnly` builds TypeScript and is not run during npm install. The registry tarball integrity is recorded in `package-lock.json`.
- The original Seerr manifest ran `npx -y @jhomen368/overseerr-mcp` without a version. Registry metadata and upstream `main` both resolve to maintained release `2.3.1` from `https://github.com/jhomen368/overseerr-mcp`. Its published package ships prebuilt `build/index.js`; its install lifecycle has no scripts. `build`, `test`, and `prepublishOnly` scripts exist, but are not install hooks. Upstream `Dockerfile` installs `dumb-init` and upgrades Alpine packages; this runtime does not execute that Dockerfile or its apk upgrade/install steps. The exact npm tarball integrity is recorded in `package-lock.json`.
- The Seerr and Arr packages are the only npm direct dependencies added by this image; their declared transitive dependencies supply their MCP SDK and Zod (`npm ls` verifies one shared resolved SDK and Zod tree). The dispatch server is copied, with dependencies, from the existing pinned image `ghcr.io/misospace/dispatch-mcp:sha-e4eaba8@sha256:11fee95712142758e1ff4c608ff0c7104ab391926fec5f96e8ea6ec63a8b1bed`; inspection confirmed it ships `node_modules`, `tsx` 4.23.12, and `src/mcp/server.ts` but not npm. Its stdio entry point is TypeScript, so its already-installed `tsx` executable is required. Its `@modelcontextprotocol/sdk` and Zod are used only from this copied dependency tree. It reads `DISPATCH_URL` and `DISPATCH_AGENT_TOKEN`; URL is fixed in the launcher and only the token comes from its secret file.
- The original GitHub manifest did not pin an image. Registry tag `2.0.1` resolves to upstream commit `55edd58d5e1127fe7ea3c036bc14dca66f7e41c4`, amd64 image digest `sha256:5fe6af7e4085ba332aeeede31a1d4f294755be16d9500fd8a02644100d9fa618` (multi-platform index `sha256:03f565ea952662cd14a8a0373d910aeced3aff7197ab6afef786755db8d25994`). The executable and exact release are copied from this source image. The original uses `stdio`; the launcher does the same.
- npm dependencies install with `npm ci --omit=dev --ignore-scripts`. This skips package lifecycle scripts. A direct review of both selected packages' metadata found no install hooks; dispatch is copied as-is and no npm install runs for it. No runtime `npx` network install occurs.
- The runtime Node binary is copied from the amd64 digest-pinned `node:24.21.0-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20`. Debian glibc Node was selected instead of Alpine Node after inspecting the Wolfi/glibc LiteLLM base; verify runtime `node --version` after build.

## Build and test

```sh
cd docker/litellm-mcp
npm ci --ignore-scripts --no-audit --no-fund
python3 -m unittest -v

docker build --platform linux/amd64 -t ghcr.io/joryirving/litellm-mcp:1.104.0-mcp1 .
python3 build_image.py --image ghcr.io/joryirving/litellm-mcp:1.104.0-mcp1 --skip-build
```

The Python tests exercise environment allowlisting, secret-file mapping and failures, process replacement/arguments, and safe exec errors. The image test starts the LiteLLM proxy using the base image's original entrypoint/CMD and `--port 4000`, then smoke-initializes all four stdio servers via the pinned image's actual `mcp.client.stdio` and requests `tools/list`. It does not call any upstream service or tool; reported timings are measured for this local smoke test only.

The workflow builds on pull requests without publishing. Only `workflow_dispatch` publishes `1.104.0-mcp1` and the source commit SHA tags to GHCR. Do not pin a digest in cluster config until a publish has actually completed; the draft tag is not yet present in GHCR and has no digest.
