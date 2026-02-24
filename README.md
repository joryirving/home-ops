# OpenClaw Chat

<p align="center">
  <img src="https://img.shields.io/docker/vize/joryirving/openclaw-chat?sort=semver&label=docker" alt="Docker">
  <img src="https://github.com/joryirving/openclaw-chat/actions/workflows/ci.yml/badge.svg" alt="CI">
  <img src="https://img.shields.io/github/v/release/joryirving/openclaw-chat?sort=semver" alt="Release">
  <img src="https://img.shields.io/github/license/joryirving/openclaw-chat" alt="License">
</p>

> Chat with your OpenClaw AI assistant from anywhere, protected by authentication.

## Features

- 🔐 **Authentication**: OIDC (Authentik, Okta, Google) + local username/password fallback
- 💬 **Real-time chat**: WebSocket connection to OpenClaw gateway
- 📱 **Mobile-friendly**: PWA-style responsive UI with native app feel
- 🐳 **Containerized**: Docker + Kubernetes deployment ready
- 🔒 **Security hardened**: Non-root user, read-only filesystem, rate limiting
- 🤖 **Automated**: CI/CD with security scanning + container testing
- 📦 **Renovate**: Automated dependency updates

## Quick Start

### Docker Compose

```bash
git clone https://github.com/joryirving/openclaw-chat.git
cd openclaw-chat
cp .env.example .env
docker-compose up -d
```

### Docker

```bash
docker run -d --name openclaw-chat \
  -p 3000:3000 \
  -e GATEWAY_URL=ws://your-gateway:18789 \
  -e SESSION_SECRET=your-secret \
  ghcr.io/joryirving/openclaw-chat:latest
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GATEWAY_URL` | Yes | - | WebSocket URL to OpenClaw gateway |
| `PORT` | No | `3000` | Server port |
| `SESSION_SECRET` | Yes | - | Secret for sessions (min 32 chars) |
| `OIDC_ENABLED` | No | `false` | Enable OIDC auth |
| `OIDC_ISSUER` | If OIDC | - | OIDC provider URL |
| `OIDC_CLIENT_ID` | If OIDC | - | OIDC client ID |
| `OIDC_CLIENT_SECRET` | If OIDC | - | OIDC client secret |
| `LOCAL_USERS` | If local | `admin:password123` | Users (user:pass, comma sep) |

## Security

The container runs as non-root (UID 1000). Production deployment should include:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
```

## Development

```bash
npm install
npm run dev    # Development
npm run test   # Run tests
npm run lint   # Lint
```

## License

MIT License - see [LICENSE](LICENSE).
