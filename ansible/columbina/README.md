# Columbina

Bootstrap the OVH VPS that fronts the Kubernetes `towonel-agent` workloads.
Ansible prepares the host and starts `doco-cd`; `doco-cd` reconciles the
Compose apps under `docker/columbina`.

```bash
ansible-galaxy collection install -r ansible/columbina/requirements.yaml
ansible-playbook -i ansible/columbina/inventory.yaml ansible/columbina/playbook.yaml
```

After `towonel.jory.dev` resolves to the VPS and the hub is healthy, create the
agent invite on the VPS:

```bash
ssh ubuntu@148.113.195.107
sudo docker exec towonel-hub towonel invite create --name home-ops --hostnames '*.jory.dev'
```

Store the resulting token in 1Password:

- item: `towonel-tunnel`
- property: `invite_token`

Also keep the VPS addresses in the same item:

- `TOWONEL_VPS_IP`: `148.113.195.107`
- `TOWONEL_VPS_IPV6`: `2607:5300:229:c9c::1`

Important state lives in `/opt/towonel/data`. Back up at least:

- `operator.key`
- `invite_hash.key`
- `hub.db`

`doco-cd` keeps its generated API and webhook secrets in `/opt/doco-cd`.
