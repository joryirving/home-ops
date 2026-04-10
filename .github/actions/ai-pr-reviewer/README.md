# AI PR Reviewer Action

This action analyzes a pull request with an OpenAI-compatible model and returns a review verdict plus markdown review text.

It is set up to work with:

- local models in this repo
- bearer-auth cloud models in other repos

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github_token` | GitHub token for PR and API access | Yes | - |
| `ai_base_url` | Base URL of the primary OpenAI-compatible API | Yes | - |
| `ai_model` | Model name for the primary analysis pass | Yes | - |
| `ai_api_key` | Optional bearer token for the primary AI endpoint | No | `""` |
| `ai_fallback_base_url` | Optional fallback OpenAI-compatible API base URL | No | `""` |
| `ai_fallback_model` | Optional fallback model name | No | `""` |
| `ai_fallback_api_key` | Optional bearer token for the fallback AI endpoint | No | `""` |
| `ai_primary_retries` | Number of retries for the primary model | No | `8` |
| `ai_primary_retry_delay_sec` | Delay between primary retries in seconds | No | `15` |
| `allowed_source_hosts` | Comma-separated list of hosts allowed for linked source fetching | No | `github.com,api.github.com,gitlab.com,registry.terraform.io,artifacthub.io,minecraft.net,www.minecraft.net` |
| `system_prompt` | Optional system prompt override | No | bundled prompt |
| `standards_file` | Repository standards file path | No | `CLAUDE.md` |

## Outputs

| Output | Description |
|--------|-------------|
| `verdict` | `approve` or `request_changes` |
| `review_markdown` | Full markdown review body |
| `analysis_engine` | Model and endpoint that produced the final result |

## Requirements

- The repository must already be checked out.
- `gh`
- `jq`
- `curl`
- `git`
- `python3`

## Usage

Local model in this repo:

```yaml
- uses: ./.github/actions/ai-pr-reviewer
  id: review
  with:
    github_token: ${{ steps.app-token.outputs.token }}
    ai_base_url: ${{ vars.AI_BASE_URL || 'http://llama-server.llm:8080/v1' }}
    ai_model: ${{ vars.AI_MODEL || 'self-hosted' }}
```

Cloud model in another repo:

```yaml
- uses: your-org/your-repo/.github/actions/ai-pr-reviewer@main
  id: review
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    ai_base_url: https://api.minimax.io/v1
    ai_model: MiniMax-M1
    ai_api_key: ${{ secrets.MINIMAX_API_KEY }}
```
