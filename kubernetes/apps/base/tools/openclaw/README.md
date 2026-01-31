# OpenClaw

OpenClaw is an AI assistant platform that provides access to various LLMs and integrates with multiple communication channels.

## Configuration

This configuration sets up OpenClaw with:

- Gateway service on port 18789
- Integration with multiple LLM providers (Qwen, OpenAI, Google Gemini)
- Discord plugin enabled
- Proper secret management via ExternalSecrets

## Secrets Required

The following secrets need to be stored in 1Password under the item named `openclaw-config`:

- `gateway_token`: The authentication token for the OpenClaw gateway
- `qwen_api_key`: API key for Qwen portal access
- `openai_api_key`: API key for OpenAI services
- `google_api_key`: API key for Google Gemini services
- `github_token`: GitHub token for repository access (optional)

## Deployment

This configuration follows GitOps principles using Flux. After adding the secrets to 1Password and ensuring ExternalSecrets is configured, apply this configuration to deploy OpenClaw.