# free-pool

`free-pool` (in `free-pool.yaml`) is a LiteLLM model group of free models from OpenRouter. It is the "throw cheap work at it" lane.

It used to also draw from OpenCode Zen, but **Zen closed outside API access on ~2026-10-10**: every model — `-free` or paid, keyed or keyless — returns `403 FreeTierError` ("OpenCode's free tier can only be used from within OpenCode") to any caller that isn't the OpenCode client itself. LiteLLM can never satisfy that gate, so there are no Zen rungs. Check the Zen console before assuming this is still true.

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
- **OpenRouter:** 20 requests a minute and 1,000 a day across all free models, once $10 of credits has been bought (without credits the daily allowance is much smaller). Some models have their own cap. A key is required even for `:free` models — keyless calls answer `401`.
- The pool is now OpenRouter-only, so all free traffic shares that one ceiling. There is no second provider to spill onto.

## Keys

In the `litellm` ExternalSecret:
- **`OPENROUTER_API_KEY`:** from the 1Password `openrouter` item.
- ~~**`OPENCODE_API_KEY`:**~~ no longer used by the pool since Zen left. The secret stays — the same 1Password field feeds `memini` and the opencode virtual key.

## Updating the list

Free models rotate often. To refresh:

1. **List candidates.**
   - OpenRouter: `curl -s https://openrouter.ai/api/v1/models`, then keep entries where `pricing.prompt` and `pricing.completion` are both `"0"` and `supported_parameters` includes `tools`. **Do not filter by the `-free` suffix** — some free models don't carry it. The pricing fields are the source of truth.
   - Zen: closed to outside callers; skip unless the gate above has lifted. The Zen console lists models the public `/v1/models` does not (e.g. `nemotron-3-ultra-free`), so the console is worth a look if Zen reopens.
2. **Probe each one** with a one-word request, using the same keys LiteLLM uses:

   ```sh
   OR=$(op read op://kubernetes/openrouter/OPENROUTER_API_KEY)
   B='{"model":"%s","messages":[{"role":"user","content":"Reply with the single word: ok"}],"max_tokens":16}'
   curl -s https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $OR" -H 'content-type: application/json' -d "$(printf "$B" <model>)"
   ```

   Keep only models that answer `200`. As of **2026-10-15**, these fail and must stay out:
   - **All Zen models:** `403 FreeTierError` from any non-OpenCode-client caller, keyed or keyless, free or paid. Whole provider out.
   - **OpenRouter `inkling:free` / `inkling-small:free`:** gated to "agentic harnesses" (`403`) as of 2026-09-29 — never list an unverified rung, a 403 rung is retried on every request.
   - **OpenRouter `stealth/space-bunny-alpha`:** removed from OpenRouter entirely (`404` "No endpoints found"), 2026-10-15.
   - **Zen `deepseek-v4-flash-free`:** reported as unavailable (2026-09-29); untested since, moot while Zen is closed.
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
