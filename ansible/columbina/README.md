# Columbina

Bootstrap the OVH VPS that hosts the towonel hub for the clusters' `TowonelTunnel`s.
Ansible prepares the host and starts `doco-cd`; `doco-cd` reconciles the
Compose apps under `docker/columbina`.

```bash
ansible-galaxy collection install -r ansible/columbina/requirements.yaml
ansible-playbook -i ansible/columbina/inventory.yaml ansible/columbina/playbook.yaml
```

After `towonel.jory.dev` resolves to the VPS and the hub is healthy, create a
hub API key for the towonel operator and store it in 1Password:

- item: `towonel-tunnel`
- property: `api_key`

Each cluster's `towonel-operator` ExternalSecret reads it as `TOWONEL_API_KEY`
for the `TowonelTunnel` CR (`kubernetes/apps/base/network/towonel-operator`).

Also keep the VPS addresses in the same item:

- `TOWONEL_VPS_IP`: `148.113.195.107`
- `TOWONEL_VPS_IPV6`: `2607:5300:229:c9c::1`

The playbook templates `/opt/coturn/turnserver.conf` for
`docker/columbina/04-coturn` from item `workadventure`, field
`WORKADVENTURE_TURN_AUTH_SECRET` in the `kubernetes` vault.

It also templates `/opt/gatus/secrets.yaml` (Discord alerting and
Alertmanager heartbeat tokens for the buddy Gatus) from 1Password. It expects
these fields in the `kubernetes` vault:

- item `discord`, field `DISCORD_WEBHOOK_URL`
- item `alertmanager`, field `GATUS_HEARTBEAT_TOKEN` (shared with both
  clusters' Alertmanager, which pushes Watchdog heartbeats to
  `https://columbina-gatus.jory.dev/api/v1/endpoints/heartbeat_<cluster>/external?success=true`)

Important state lives in `/opt/towonel/data`. Back up at least:

- `operator.key`
- `invite_hash.key`
- `hub.db`

`doco-cd` keeps its generated API and webhook secrets in `/opt/doco-cd`.
