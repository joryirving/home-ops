# Security Review - OpenClaw Chat

## Findings

### Critical
- [ ] XSS in user messages (unescaped HTML)
- [ ] No CSRF protection on POST forms

### High
- [ ] Session fixation (should regenerate after login)
- [ ] WebSocket message size limits
- [ ] OIDC callback URL validation missing

### Medium
- [ ] Missing security headers (Permissions-Policy, Referrer-Policy)
- [ ] No input length validation on messages

### Low
- [ ] Error messages leak server info

## Recommendations
1. Add HTML escaping for user messages
2. Add CSRF protection (csurf or similar)
3. Regenerate session after successful login
4. Validate OIDC callback URL against allowed origins
5. Add input length limits

