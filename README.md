# OpenClaw Chat

<p align="center">
  <img src="https://img.shields.io/badge/docker-hub-blue?style=flat-square&logo=docker" alt="Docker">
  <img src="https://img.shields.io/github/actions/workflow/status/joryirving/openclaw-chat/ci.yml?style=flat-square" alt="CI">
  <img src="https://img.shields.io/github/v/release/joryirving/openclaw-chat?style=flat-square" alt="Release">
  <img src="https://img.shields.io/github/license/joryirving/openclaw-chat?style=flat-square" alt="License">
</p>

> Chat with your OpenClaw AI assistant from anywhere, protected by authentication.

## Features

- 🔐 **Authentication**: OIDC (Authentik, Okta, Google) + local username/password fallback
- 💬 **Real-time chat**: WebSocket connection to OpenClaw gateway
- 📱 **Mobile-friendly**: PWA-style responsive UI with native app feel
- 🐳 **Containerized**: Docker + Kubernetes deployment ready
- 🔒 **Security hardened**: Non-root user, read-only filesystem, capability dropping
- 🤖 **Automated**: CI/CD with security scanning

## Quick Start

### Docker Compose (Local)

```bash
# Clone and run
git clone https://github.com/joryirving/openclaw-chat.git
cd openclaw-chat

# Configure environment
cp .env.example .env
nano .env

# Start services
docker-compose up -d
```

### Docker (Standalone)

```bash
# Pull from GHCR
docker pull ghcr.io/joryirving/openclaw-chat:latest

# Run container
docker run -d \
  --name openclaw-chat \
  -p 3000:3000 \
  -e GATEWAY_URL=ws://your-gateway:18789 \
  -e SESSION_SECRET=your-secret \
  ghcr.io/joryirving/openclaw-chat:latest
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GATEWAY_URL` | Yes | - | WebSocket URL to OpenClaw gateway |
| `PORT` | No | `3000` | Server port |
| `SESSION_SECRET` | Yes | - | Secret for session encryption (min 32 chars) |
| `OIDC_ENABLED` | No | `false` | Enable OIDC authentication |
| `OIDC_ISSUER` | If OIDC | - | OIDC provider URL (e.g., https://authentik.example.com) |
| `OIDC_CLIENT_ID` | If OIDC | - | OIDC client ID |
| `OIDC_CLIENT_SECRET` | If OIDC | - | OIDC client secret |
| `OIDC_CALLBACK_URL` | If OIDC | - | OIDC callback URL |
| `LOCAL_USERS` | If local auth | `admin:password123` | Username:password pairs (comma separated) |

### Local Authentication

For testing or development without OIDC:

```env
OIDC_ENABLED=false
LOCAL_USERS=admin:password123,user2:secret456
```

### OIDC Configuration

Example for Authentik:

```env
OIDC_ENABLED=true
OIDC_ISSUER=https://authentik.yourdomain.com
OIDC_CLIENT_ID=openclaw-chat
OIDC_CLIENT_SECRET=your-client-secret
OIDC_CALLBACK_URL=https://chat.yourdomain.com/auth/oidc/callback
```

## Kubernetes Deployment

### Basic Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openclaw-chat
spec:
  replicas: 1
  selector:
    matchLabels:
      app: openclaw-chat
  template:
    metadata:
      labels:
        app: openclaw-chat
    spec:
      containers:
      - name: chat
        image: ghcr.io/joryirving/openclaw-chat:latest
        ports:
        - containerPort: 3000
        env:
        - name: GATEWAY_URL
          value: ws://openclaw-gateway:18789
        - name: SESSION_SECRET
          valueFrom:
            secretKeyRef:
              name: openclaw-chat-secrets
              key: session-secret
        - name: OIDC_ENABLED
          value: "true"
        - name: OIDC_ISSUER
          value: https://authentik.yourdomain.com
        - name: OIDC_CLIENT_ID
          value: openclaw-chat
        - name: OIDC_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: openclaw-chat-secrets
              key: oidc-client-secret
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /api/auth
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /api/auth
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
```

### NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: openclaw-chat
spec:
  podSelector:
    matchLabels:
      app: openclaw-chat
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: production
      ports:
      - protocol: TCP
        port: 3000
  egress:
    - to:
      - podSelector:
          matchLabels:
            app: openclaw-gateway
      ports:
      - protocol: TCP
        port: 18789
    - to:
      - namespaceSelector: {}
      ports:
      - protocol: TCP
        port: 443
      - protocol: TCP
        port: 53
```

## Security

### Container Security

The container runs as a non-root user (UID 1000). For production:

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

### Recommended Practices

1. **Always use TLS** in production
2. **Rotate secrets** regularly
3. **Enable OIDC** for production deployments
4. **Use network policies** to restrict access
5. **Monitor logs** for suspicious activity
6. **Keep updated** with Dependabot PRs

See [SECURITY.md](SECURITY.md) for full security guidelines.

## Development

### Local Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run dev

# Run tests
npm test
```

### Building

```bash
# Build Docker image
docker build -t openclaw-chat .

# Build for multiple platforms
docker buildx build --platform linux/amd64,linux/arm64 -t openclaw-chat .
```

## API

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Chat UI (protected) |
| GET | `/login` | Login page |
| POST | `/login` | Authenticate user |
| POST | `/logout` | End session |
| GET | `/api/auth` | Check auth status |
| WS | `/ws` | WebSocket to gateway |

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [OpenClaw](https://github.com/openclaw/openclaw) - AI assistant framework
- [Express.js](https://expressjs.com/) - Web framework
- [ws](https://github.com/websockets/ws) - WebSocket library
