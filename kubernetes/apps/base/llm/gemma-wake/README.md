# Gemma wake proxy

This app fronts the Windows `smurf-pc` LM Studio server with a Wake-on-LAN
reverse proxy. It is intentionally limited to the Gemma LiteLLM routes; the
ComfyUI `:8188` endpoints remain direct.

The proxy runs with host networking because Wake-on-LAN packets must leave on
the cluster node's LAN interface. Keep the service internal and do not add an
external route.

The target values below were observed on 2026-09-01 and must remain aligned
with the Windows PC's DHCP reservation:

- 10G SFP traffic address: `192.168.30.14`
- built-in 1G WoL MAC: `b4:2e:99:3e:2c:f3`
- 1G WoL broadcast: `192.168.30.255`

The MAC and address intentionally belong to different NICs: WoL targets the
built-in 1G adapter, while liveness checks and LM Studio requests use the 10G
SFP adapter.

The proxy only wakes the PC. Windows power management remains responsible for
putting it to sleep; no shutdown command is configured.
