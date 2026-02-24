# Miso Chat

<p align="center">
  <img src="https://img.shields.io/docker/vize/joryirving/miso-chat?sort=semver&label=docker" alt="Docker">
  <img src="https://github.com/joryirving/miso-chat/actions/workflows/build.yaml/badge.svg" alt="Build">
  <img src="https://img.shields.io/github/v/release/joryirving/miso-chat?sort=semver" alt="Release">
  <img src="https://img.shields.io/github/license/joryirving/miso-chat" alt="License">
</p>

> Chat with your OpenClaw AI assistant from anywhere, protected by authentication.

## Features

- 🔐 **Authentication**: OIDC (Authentik, Okta, Google) + local username/password fallback
- 💬 **Real-time chat**: WebSocket connection to OpenClaw gateway
- 📱 **Mobile-friendly**: PWA-style responsive UI with native app feel
- 🐳 **Containerized**: Docker + Kubernetes deployment ready
- 🔒 **Security hardened**: Non-root user, rate limiting, XSS protection
- 🤖 **Automated**: CI/CD with linting, testing, and multi-platform builds

## Quick Start

### Docker Compose

```bash
git clone https://github.com/joryirving/miso-chat.git
cd miso-chat
cp .env.example .env
docker-compose up -d
```

### Docker

```bash
docker run -d --name miso-chat \
  -p 3000:3000 \
  -e GATEWAY_URL=ws://your-gateway:18789 \
  -e SESSION_SECRET=your-secret \
  ghcr.io/joryirving/miso-chat:latest
```

## Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GATEWAY_URL` | Yes | - | WebSocket URL to OpenClaw gateway |
| `PORT` | No | `3000` | Server port |
| `SESSION_SECRET` | Yes | - | Secret for sessions |
| `OIDC_ENABLED` | No | `false` | Enable OIDC auth |
| `LOCAL_USERS` | If local | `admin:password123` | Users (user:pass) |

## Security

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
