# LLM wake proxy

A single doormouse reverse proxy that fronts the on-demand inference boxes with
Wake-on-LAN, so agents hit a stable in-cluster endpoint and the machines only
draw power while working. Replaces the separate `comfy-wake` / `gemma-wake` apps.

Machines and their `comfy-wake.llm` / `gemma-wake.llm` routes live in one
`config.toml`; add a `[[machines]]` + `[[routes]]` pair to onboard another box.

The magic packet is sent **unicast to the target's host IP**, not a subnet
broadcast. UniFi drops inbound cross-VLAN broadcast on the `10.69.1.x` Servers
VLAN, so a broadcast from anywhere else never reaches those NICs; a unicast
routes normally and still wakes a powered-off NIC because the DHCP reservation
keeps the gateway's IP->MAC binding. That's why this needs no hostNetwork and no
Multus — a plain pod's routed egress is enough, and the kubelet probes work.

Targets:

- shenhe (ComfyUI): MAC `d8:9d:67:f4:2b:03`, wake `10.69.1.25`, proxy `shenhe.internal:8188`
- smurf-pc (Gemma/LM Studio): WoL MAC `b4:2e:99:3e:2c:f3`, wake `192.168.30.114`
  (the 1G WoL NIC — not `smurf-pc.internal`/the 10G data NIC, which is down while
  asleep), proxy `smurf-pc.internal:8889`

Consumed at `http://comfy-wake.llm:8080` (openclaw) and `http://gemma-wake.llm:8080`
(litellm gemma models). Sleeping is handled on each box; the first request after an
idle power-off blocks while the box POSTs.
