# LLM wake proxy

A single doormouse reverse proxy wakes `smurf-pc` with Wake-on-LAN and
forwards ComfyUI requests through `http://comfy-fast-wake.llm:8080` to
`smurf-pc.internal:8188`. The machine and host-routed endpoint are configured
in `config.toml`; the Service provides the hostname used for routing.

The WoL address is `10.69.1.255`, using the dedicated WoL NIC's MAC rather
than the NIC serving `smurf-pc.internal`. Keep the host-network and DNS
settings required for the wake packet and internal hostname resolution.

The proxy waits for the backend before forwarding the first request.
`timeout = "10m"` and `response_header_timeout = "20m"` bound that wait.

The 2Gi memory limit is a stopgap for an upstream doormouse per-request
transport leak that OOMKilled the pod at 512Mi during render-pipeline
`/history` polling.
