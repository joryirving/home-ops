# 🧩 GitHub App Git Workflow (Reference)

## ✅ Correct Flow
1. **Generate JWT** from `GITHUB_APP_ID` + `GITHUB_PRIVATE_KEY` (PEM)
2. **Exchange JWT** for installation access token via:
   ```bash
   curl -X POST \
     -H "Authorization: Bearer $JWT" \
     -H "Accept: application/vnd.github+json" \
     "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens"
   ```
3. Use **HTTPS URLs only** (`https://github.com/owner/repo.git`)
4. Authenticate git with:
   - `username = x-access-token`
   - `password = <installation_token>`
5. Push only to branches the App has write access to (e.g., `feat/*`, not `main` unless explicitly granted)

## ❌ Why SSH Doesn’t Work
- GitHub Apps have **no SSH identity**
- App private key is **not an SSH key** (it’s for JWT signing)
- GitHub will **always reject** SSH auth using it
- ✅ Renovate uses HTTPS + token — proven pattern

> 💡 Tip: Refresh token before each push if >1h old (tokens expire after 1h).