# Git-managed plugins

The stock OpenClaw image is shared by the plugin init container and Gateway.
`inventory.json` declares external packages. Official packages follow the image's
reported release through `{hostVersion}`; third-party packages have explicit pins.

The init container runs OpenClaw's supported installer using an isolated writable
config and isolated SQLite state beneath `~/.openclaw/plugin-stage`. It never opens
the live Gateway database or changes the Git-managed Gateway config. Each source
and host release gets a separate generation. A successful receipt skips package
installation on subsequent starts, but the installer still verifies that the
plugin loads. Failures prevent Gateway startup rather than using a stale package.

To add a plugin:

1. Add its ID and pinned `npm:` or `clawhub:` source to `inventory.json`.
2. Add `/home/node/.openclaw/plugin-stage/active/<id>` to `plugins.load.paths` in
   `configmap.yaml`, preserving existing paths.
3. Add the ID to `plugins.allow` and configure `plugins.entries.<id>` in Git.
4. Review the package capabilities and install-policy warnings before merging.
   The init command explicitly accepts capabilities and acknowledges warnings;
   policy blocks still fail the installation.
5. Review rendered manifests and check plugin status after deployment.

Old generations and existing plugins are retained for rollback. No automated
cleanup deletes existing extension or npm directories. Inventory removal alone
does not uninstall packages: remove the associated load path and enablement too.
No decision model is selected merely by installing TypeSafe.

## Provenance limitation

The Gateway loads these packages as explicit local paths. Although staging uses
the official installer, its install ledger belongs to isolated state. The Gateway
therefore reports `record-missing`, not `trusted-official`, for these copies.
Plugin-local storage and ordinary tools/providers remain supported, but features
requiring trusted provenance (such as dispatching hook agent turns or Gateway
scope elevation) must not be assumed to work. Do not copy SQLite trust records or
relax Gateway security to hide the warning. Existing plugins outside this inventory
and their live installation records are left untouched.

This is deliberately a draft rollout until the staged Discord, Comfy, SearXNG,
and Memini packages are checked for trust-gated behavior. TypeSafe was exercised
with OpenClaw 2026.11.5: real install, repeated cached run, and a separate consumer
with read-only config. This is not a production rollout verification.
