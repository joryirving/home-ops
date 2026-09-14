# Gemma wake proxy

Fronts the Windows `smurf-pc` LM Studio server with a Wake-on-LAN reverse proxy,
limited to the Gemma LiteLLM routes. Runs in the utility cluster's `network`
namespace alongside `comfy-wake`, attached to `multus-iot` (VLAN 10) so it has an
L2 presence off host networking.

The magic packet is broadcast on the IoT segment (`192.168.10.255`) and the
network relays it cross-VLAN to the target, the same way Home Assistant wakes
hosts. Liveness/readiness work because the macvlan subnet differs from the
utility nodes' primary subnet.

Target values (must stay aligned with the Windows PC's DHCP reservation):

- WoL MAC (built-in 1G NIC): `b4:2e:99:3e:2c:f3`
- WoL broadcast: `192.168.10.255`
- health + proxy target (10G SFP NIC): `smurf-pc.internal:8889`

Exposed to the main-cluster consumers over internal DNS via a LoadBalancer:
`http://gemma-wake.jory.dev:8080` (litellm's gemma models point here). The proxy
only wakes the PC; Windows power management handles sleep.
