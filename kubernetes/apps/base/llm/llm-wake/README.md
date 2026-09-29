# LLM wake proxy

A single doormouse reverse proxy that fronts the on-demand inference boxes with
Wake-on-LAN, so agents hit a stable in-cluster endpoint and the machines only
draw power while working. Replaces the separate `comfy-wake` / `gemma-wake` apps.

Machines and their `comfy-wake.llm` / `gemma-wake.llm` routes live in one
`config.toml`; add a `[[machines]]` + `[[routes]]` pair to onboard another box.

The two boxes are woken differently (`broadcast_ip` in `config.toml`):

- **shenhe: unicast** to its host IP. The `10.69.1.x` Servers VLAN drops inbound
  cross-VLAN broadcast, but a unicast routes normally and still wakes the
  powered-off NIC because the DHCP reservation keeps the gateway's IP->MAC
  binding.
- **smurf-pc: subnet broadcast** to `10.69.1.255`, which the network relays
  cross-VLAN to its WoL NIC. That NIC has no IP by design, so the gateway holds
  no IP->MAC binding and a unicast can't reach it. The broadcast needs the pod
  on `hostNetwork` (with `dnsPolicy: ClusterFirstWithHostNet`); restored in
  #10177 after the unicast-only collapse in #10123 broke it.

Targets:

- shenhe (ComfyUI): MAC `d8:9d:67:f4:2b:03`, wake unicast `10.69.1.25`, proxy
  `shenhe.internal:8188`
- smurf-pc (Gemma/LM Studio): WoL MAC `b4:2e:99:3e:2c:f3` (the 1G WoL NIC — not
  `smurf-pc.internal`/the 10G data NIC, which is down while asleep), wake
  broadcast `10.69.1.255`, proxy `smurf-pc.internal:8889`

Consumed at `http://comfy-wake.llm:8080` (openclaw) and `http://gemma-wake.llm:8080`
(litellm `gemma-4-12b-it-qat` / `-chat`, and the gemma rung of `local-pool` /
`local-pool-chat`). Sleeping is handled on each box; the first request after an
idle power-off blocks while the box POSTs. That hold is bounded by `timeout =
"10m"` and `response_header_timeout = "20m"` (shenhe cold-boots in ~70s).

The 2Gi memory limit is a stopgap for a per-request transport leak in upstream
doormouse, which OOMKilled the pod at 512Mi under the render pipeline's
`/history` poll flood.
