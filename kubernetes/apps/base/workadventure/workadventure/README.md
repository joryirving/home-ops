# WorkAdventure

## Media architecture

Bubbles of up to `MAX_USERS_FOR_WEBRTC` (default 4) users are mesh P2P between
browsers, relayed by coturn only when NATs block a direct path. Larger bubbles
switch to the in-cluster LiveKit SFU (`../livekit`), which replaced the
`meet.jit.si` dependency. LiveKit works behind towonel where coturn couldn't:
its media terminates at the SFU pod itself, which just replies to whatever
source it sees — the tunnel's SNAT is symmetric and harmless there, unlike
TURN's source-IP-authenticated peer leg. LiveKit advertises the VPS IP
(`rtc.node_ip`) and needs exactly two forwarded ports: 7881/tcp (ICE-TCP
fallback) and 7882/udp (UDP mux).

## Where is coturn?

coturn runs on the columbina VPS (`docker/columbina/04-coturn`), not in the
cluster.

TURN cannot sit behind towonel: the tunnel source-NATs all forwarded UDP to
the in-cluster agent pod IP, while TURN validates relayed traffic against
per-peer-IP permissions that clients install for their peers' *public*
addresses. Every relayed packet arrives from the agent pod IP instead, fails
the permission check, and is silently dropped — allocations succeed, media
never flows. Game servers tolerate the SNAT (they just reply to whatever
source they see); TURN is the one protocol that authenticates source IPs.

Running coturn on the VPS puts it directly on the public IP (`turn.jory.dev`,
3478/tcp+udp, relay range 49160-49179/udp — already open in ufw) and keeps
WebRTC relay traffic off the tunnel entirely. It needs no cluster access: the
only shared piece is the TURN auth secret (1Password `workadventure` item,
`WORKADVENTURE_TURN_AUTH_SECRET`), templated onto the host by
`ansible/columbina` and consumed here as `TURN_STATIC_AUTH_SECRET` via the
`workadventure` ExternalSecret. The `turn.jory.dev` DNSEndpoint lives in this
app because WorkAdventure is its only consumer.
