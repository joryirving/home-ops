# Miso-Chat Wishlist

## In Progress

## Todo

### Bugs (Priority)

- [ ] **#119: Fix GATEWAY_WS_URL undefined** - PR #118 uses undefined `GATEWAY_WS_URL` variable. Use `GATEWAY_WS_WS` instead.
  - Location: `server.js:244`
  - Blocked by: PR #118

- [ ] **#120: Fix ws.send() bypasses request tracking** - PR #118 directly calls `gatewayWsManager.ws.send()` instead of `gatewayWsManager.send()`, bypassing timeout logic.
  - Location: `server.js:613`
  - Blocked by: PR #118

### Features

- [ ] Wire chat.send to use GatewayWsManager instead of per-request WS (after #119, #120)

- [ ] Add JSDoc to GatewayWsManager public API

- [ ] Clear pendingRequests on disconnect to prevent orphaned requests (#118)
