# free-pool

`free-pool` (in `free-pool.yaml`) is a LiteLLM model group made of free models from OpenCode Zen and OpenRouter. It is the "throw cheap work at it" lane.

## Rules

- **Public material only.** Free tiers log prompts and may train on them. Send only public repos and public data: no secrets, no tokens, no personal data.
- **Never a fallback.** No other pool, fallback chain or default model points at `free-pool`, so private traffic can't reach it by accident. Keep it that way.
- **Who uses it:**
  - Courier's `free` role in the `local` LaneProfile.
  - The opencode, pi and zed catalogs, picked by hand only.
  - Virtual keys: the Courier key allows it. Keys without a `models:` list (opencode, pi, zed) can reach every model, so these can too.

## How it routes

Rungs are tried in `order:`, strongest and most reliable first. `openrouter/free`, a random free model, is always last.

Free tiers answer `429` when quota runs out. LiteLLM cools a deployment down on `429`, but **not** on `402` or `403`, so a rung that returns `403` is retried on every request. Only list models that answer `200` from LiteLLM.

Limits:
- **OpenRouter:** 20 requests a minute and 1,000 a day across all free models, once $10 of credits has been bought. Some models have their own cap; Space Bunny allows 200 a day.
- **Zen:** the free limits aren't published.

## Keys

In the `litellm` ExternalSecret:
- **`OPENCODE_API_KEY`:** from the 1Password `opencode` item.
- **`OPENROUTER_API_KEY`:** from the 1Password `openrouter` item.

## Updating the list

Free models rotate often. To refresh:

1. **List candidates.**
   - OpenRouter: `curl -s https://openrouter.ai/api/v1/models`, then keep entries where `pricing.prompt` and `pricing.completion` are both `"0"` and `supported_parameters` includes `tools`.
   - Zen: `curl -s https://opencode.ai/zen/v1/models`, then keep ids ending in `-free`.
2. **Probe each one** with a one-word request, using the same keys LiteLLM uses:

   ```sh
   OR=$(op read op://kubernetes/openrouter/OPENROUTER_API_KEY)
   OC=$(op read op://kubernetes/opencode/OPENCODE_API_KEY)
   B='{"model":"%s","messages":[{"role":"user","content":"Reply with the single word: ok"}],"max_tokens":16}'
   curl -s https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $OR" -H 'content-type: application/json' -d "$(printf "$B" <model>)"
   curl -s https://opencode.ai/zen/v1/chat/completions   -H "Authorization: Bearer $OC" -H 'content-type: application/json' -d "$(printf "$B" <model>)"
   ```

   Keep only models that answer `200`. As of 2026-09-29, these fail and must stay out:
   - **Most Zen `-free` models:** "OpenCode's free tier can only be used from within OpenCode".
   - **OpenRouter `inkling:free`:** gated to "agentic harnesses" (`403`).
   - **Zen `deepseek-v4-flash-free`:** reported as unavailable.
3. **Edit `free-pool.yaml`.**
   - One document per rung, named `free-pool-<provider>-<model>`.
   - Set `maxInputTokens` to the model's context length.
   - Set `supportsVision` only if the model takes image input.
   - Renumber `order:` so the strongest model comes first and `openrouter/free` comes last.
4. **Update the declared context** wherever it appears, to the smallest `maxInputTokens` in the pool:
   - `kubernetes/apps/base/llm/opencode/configmap.yaml`
   - Courier's catalog in `kubernetes/apps/base/llm/courier/externalsecret.yaml`
   - In dotfiles: `home/.chezmoitemplates/shared/litellm-opencode-models`, `litellm-zed-models` and `home/dot_pi/agent/models.json.tmpl`.
5. **Don't add `free-pool`** to any other pool, fallback or default.
