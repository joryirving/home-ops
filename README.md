# OpenClaw Chat

Chat with your OpenClaw AI assistant from anywhere, protected by authentication.

## Features

- 🔐 **Authentication**: OIDC (Authentik) + local username/password fallback
- 💬 **Real-time chat**: WebSocket connection to OpenClaw gateway
- 📱 **Mobile-friendly**: PWA-style responsive UI
- 🐳 **Containerized**: Easy deployment anywhere

## Quick Start

### Local Development

```bash
# Install dependencies
npm install

# Copy env template
cp .env.example .env

# Edit .env with your settings
nano .env

# Run
npm start
```

### Docker

```bash
# Build and run
docker-compose up -d

# Or build manually
docker build -t openclaw-chat .
docker run -p 3000:3000 \
  -e GATEWAY_URL=ws://your-gateway:18789 \
  -e SESSION_SECRET=your-secret \
  openclaw-chat
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GATEWAY_URL` | Yes | WebSocket URL to OpenClaw gateway |
| `PORT` | No | Server port (default: 3000) |
| `SESSION_SECRET` | Yes | Secret for session cookies |
| `OIDC_ENABLED` | No | Enable OIDC auth (default: false) |
| `OIDC_ISSUER` | If OIDC | OIDC provider URL |
| `OIDC_CLIENT_ID` | If OIDC | OIDC client ID |
| `OIDC_CLIENT_SECRET` | If OIDC | OIDC client secret |
| `LOCAL_USERS` | If local auth | Username:password pairs (comma separated) |

## Auth Configuration

### Local Auth Only (Default)

Set `OIDC_ENABLED=false` and configure `LOCAL_USERS`:

```
LOCAL_USERS=admin:password123,john:secret456
```

### OIDC (Authentik)

Set environment:

```
OIDC_ENABLED=true
OIDC_ISSUER=https://authentik.yourdomain.com
OIDC_CLIENT_ID=openclaw-chat
OIDC_CLIENT_SECRET=your-secret
```

## Kubernetes Deployment

Example deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openclaw-chat
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: chat
        image: ghcr.io/joryirving/openclaw-chat:latest
        env:
        - name: GATEWAY_URL
          value: ws://openclaw-gateway:18789
        - name: SESSION_SECRET
          valueFrom:
            secretKeyRef:
              name: openclaw-chat-secrets
              key: session-secret
```

## License

MIT
