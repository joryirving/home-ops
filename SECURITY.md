# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please send an email to the repository owner. All security vulnerabilities will be promptly addressed.

Please include the following:
- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Any suggested fixes (optional)

## Security Best Practices

### Container Security

This container runs as a non-root user by default.

Recommended deployment configuration:

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

### Environment Variables

Never commit secrets to version control. Use:

- Kubernetes Secrets
- HashiCorp Vault
- AWS Secrets Manager
- GitHub Secrets

Required environment variables:
- `GATEWAY_URL` - OpenClaw WebSocket gateway
- `SESSION_SECRET` - Random string for session encryption

### Network

- Always run behind a reverse proxy with TLS
- Configure firewall rules to restrict access
- Use network policies in Kubernetes

### Authentication

- Change default passwords immediately
- Use strong, unique passwords
- Enable OIDC for production deployments
- Rotate secrets regularly
