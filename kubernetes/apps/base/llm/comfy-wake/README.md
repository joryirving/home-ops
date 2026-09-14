# ComfyUI wake proxy

Fronts the on-demand `shenhe` (Z820 + RTX 2070 Super) ComfyUI server with a
Wake-on-LAN reverse proxy, so agents can hit a stable in-cluster endpoint and the
box only draws power while rendering. Modelled on `gemma-wake`.

The proxy runs with host networking because Wake-on-LAN packets must leave on the
cluster node's LAN interface, and it broadcasts on the same segment the target's
WoL NIC lives on.

Target values:

- WoL MAC (`eno1`): `d8:9d:67:f4:2b:03`
- WoL broadcast: `10.69.1.255`
- health + proxy target: `shenhe.internal:8188`

Prerequisite: `shenhe` must sit on the `10.69.1.x` VLAN so a cluster node shares
its segment (a cross-subnet directed broadcast will not wake it). Give the WoL MAC
a DHCP reservation there and point `shenhe.internal` at that address.

The proxy only wakes the box. Sleeping is handled on `shenhe` itself by the
`comfy-idle-shutdown` service (powers off after ComfyUI has been idle), mirroring
how `gemma-wake` leaves sleep to the target.

Consume it at `http://comfy-wake.llm:8080`. The first request after an idle
power-off blocks ~4 minutes while the Z820 POSTs and ComfyUI starts.
