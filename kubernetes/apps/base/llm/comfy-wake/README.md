# ComfyUI wake proxy

Fronts the on-demand `shenhe` (Z820 + RTX 2070 Super) ComfyUI server with a
Wake-on-LAN reverse proxy, so agents hit a stable endpoint and the box only
draws power while rendering. Runs in the utility cluster's `network` namespace
(the main cluster has no non-VPN VLAN free of the node subnet, and a macvlan on
the node subnet breaks kubelet probes).

Attached to `multus-iot` (VLAN 10) so the pod has its own L2 presence off host
networking. The magic packet is broadcast on that segment (`192.168.10.255`) and
the network relays it cross-VLAN to `shenhe`'s NIC, the same way Home Assistant
wakes hosts. Liveness/readiness work because the macvlan subnet differs from the
utility nodes' primary subnet.

Target values:

- WoL MAC (`eno1`): `d8:9d:67:f4:2b:03`
- WoL broadcast: `192.168.10.255`
- health + proxy target: `shenhe.internal:8188`

Exposed to the main-cluster consumers over internal DNS via a LoadBalancer:
`http://comfy-wake.jory.dev:8090` (openclaw's comfy tool points here). Sleeping is
handled on the box by its own `comfy-idle-shutdown` service. The first request
after an idle power-off blocks while the Z820 POSTs and ComfyUI starts (~2 min).
