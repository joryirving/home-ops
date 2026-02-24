# Miso-Chat Summary

## Current State
- **Location**: `/home/node/.openclaw/workspace/miso-chat/`
- **Main file**: `server.js` (247 lines)
- **Container**: `ghcr.io/joryirving/miso-chat`
- **Latest version**: 0.1.7

## What Works
- Express server with WebSocket
- Local auth (username/password)
- OIDC auth (fixed in 0.1.3 - `issuer` not `issuerURL`)
- Basic chat UI at `/public/index.html`

## What's Broken / Missing

### 1. Sessions Not Working (MAIN ISSUE)
The app shows ALL sessions but can't SEND replies. The server.js doesn't have:
- `sessions_list` integration
- `sessions_send` integration
- No way to pick a session and reply to it

### 2. WebSocket via Envoy
- Frontend connects to `window.location.host`
- Envoy needs WebSocket upgrade support to proxy to backend

### 3. Gateway DNS
- Pod can't resolve `openclaw.llm`
- Needs full FQDN: `openclaw.llm.svc.cluster.local`

## Required API Calls (for reply functionality)
```javascript
// List sessions
GET /api/sessions

// Get history for a session  
GET /api/sessions/:sessionKey/history

// Send message to a session
POST /api/sessions/:sessionKey/send
{ "message": "hello" }
```

## Key Env Vars
```
OIDC_ENABLED=true/false
OIDC_ISSUER=https://sso.jory.dev
OIDC_CLIENT_ID=
OIDC_CLIENT_SECRET=
OIDC_CALLBACK_URL=
SESSION_SECRET=
LOCAL_USERS=admin:password123
OPENCLAW_URL=http://openclaw.llm.svc.cluster.local:8080
```

## Next Steps (Backlog)
1. Add session picker UI dropdown
2. Call sessions_list on page load
3. Persist selected sessionKey
4. Add "send reply" functionality using sessions_send
5. Fix WebSocket routing through Envoy

## Debug
```bash
kubectl logs -n llm -l app.kubernetes.io/name=miso-chat
```
