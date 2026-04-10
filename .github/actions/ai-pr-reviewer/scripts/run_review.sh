#!/usr/bin/env bash
set -euo pipefail

# This script is a port of the logic from .github/workflows/ai-review.yaml
# It has been modularized to be used within a GitHub Action.

# --- Helper Functions ---

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] $1"
}

error() {
  log "ERROR: $1" >&2
}

# --- Environment & Inputs ---
# These will be passed as environment variables by the action runner or defined in the script.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
PR_NUMBER="${PR_NUMBER:-}"
AI_BASE_URL="${AI_BASE_URL:-}"
AI_MODEL="${AI_MODEL:-}"
AI_API_KEY="${AI_API_KEY:-}"
AI_FALLBACK_BASE_URL="${AI_FALLBACK_BASE_URL:-}"
AI_FALLBACK_MODEL="${AI_FALLBACK_MODEL:-}"
AI_FALLBACK_API_KEY="${AI_FALLBACK_API_KEY:-}"
AI_PRIMARY_RETRIES="${AI_PRIMARY_RETRIES:-8}"
AI_PRIMARY_RETRY_DELAY_SEC="${AI_PRIMARY_RETRY_DELAY_SEC:-15}"
ALLOWED_SOURCE_HOSTS="${ALLOWED_SOURCE_HOSTS:-github.com,api.github.com,gitlab.com,registry.terraform.io,artifacthub.io,minecraft.net,www.minecraft.net}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
SYSTEM_PROMPT="${SYSTEM_PROMPT:-}"
STANDARDS_FILE="${STANDARDS_FILE:-CLAUDE.md}"
OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/null}"

if [[ -z "$REPO" || -z "$PR_NUMBER" || -z "$AI_BASE_URL" || -z "$AI_MODEL" ]]; then
  error "Missing required environment variables: REPO, PR_NUMBER, AI_BASE_URL, or AI_MODEL"
  exit 1
fi

if [[ -z "$GH_TOKEN" ]]; then
  error "Missing GitHub token in GH_TOKEN or GITHUB_TOKEN"
  exit 1
fi

if [[ -n "$AI_FALLBACK_BASE_URL" && -z "$AI_FALLBACK_MODEL" ]]; then
  error "AI_FALLBACK_MODEL is required when AI_FALLBACK_BASE_URL is set"
  exit 1
fi

if [[ -z "$AI_FALLBACK_BASE_URL" && -n "$AI_FALLBACK_MODEL" ]]; then
  error "AI_FALLBACK_BASE_URL is required when AI_FALLBACK_MODEL is set"
  exit 1
fi

if [[ -z "$SYSTEM_PROMPT" ]]; then
  SYSTEM_PROMPT="$(<"$SCRIPT_DIR/default_system_prompt.txt")"
fi

curl_model() {
  local base_url="$1"
  local api_key="$2"
  local payload_file="$3"
  local output_file="$4"

  local args=(
    -fsSL
    "$base_url/chat/completions"
    -H "Content-Type: application/json"
    --data "@$payload_file"
  )

  if [[ -n "$api_key" ]]; then
    args+=( -H "Authorization: Bearer $api_key" )
  fi

  curl "${args[@]}" > "$output_file"
}

parse_and_validate() {
  local response_file="$1"
  jq -r '.choices[0].message.content // empty' "$response_file" > ai-output.raw
  sed -e 's/^```json$//' -e 's/^```$//' ai-output.raw | sed '/^$/d' > ai-output.json
  jq . ai-output.json > /dev/null
  jq -e '.verdict == "approve" or .verdict == "request_changes"' ai-output.json > /dev/null
  jq -e '.review_markdown and (.review_markdown | length > 0)' ai-output.json > /dev/null
}

# --- Step 1: Collect PR Context ---

log "Collecting PR context for #$PR_NUMBER in $REPO..."

gh pr view "$PR_NUMBER" --repo "$REPO" \
  --json number,title,body,headRefOid,baseRefName,headRefName,author,changedFiles,additions,deletions,files,url > pr.json

gh pr diff "$PR_NUMBER" --repo "$REPO" > pr.diff
head -c 140000 pr.diff > pr.diff.truncated

gh api "repos/$REPO/pulls/$PR_NUMBER/files" --paginate > pr-files.raw.json
jq '[.[] | {filename,status,additions,deletions,changes,previous_filename,patch}]' pr-files.raw.json > pr-files.json
head -c 70000 pr-files.json > pr-files.truncated.json

jq -r '.body // ""' pr.json > pr-body.txt

cat pr-body.txt pr.diff.truncated \
  | grep -Eo 'https?://[^ )]+' \
  | sed 's/[",.;]$//' \
  | sort -u \
  | head -n 25 > urls.txt || true

grep -E '^[+-].*(image:|tag:|version:|chart:|appVersion:|digest:)' pr.diff.truncated > version-hints.txt || true
head -n 180 version-hints.txt > version-hints.truncated.txt || true

# --- Step 2: Gather HelmValues context ---

log "Gathering HelmRelease context..."
CHANGED_HELMRELEASES=$(gh api "repos/$REPO/pulls/$PR_NUMBER/files" --paginate --jq '.[] | select(.filename | endswith("helmrelease.yaml")) | .filename' 2>/dev/null || true)

: > helmvalues-context.md
if [ -n "$CHANGED_HELMRELEASES" ]; then
  echo "# HelmRelease Values Context (modified files only)" >> helmvalues-context.md
  echo >> helmvalues-context.md

  TOTAL=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ ! -f "$f" ]; then
      echo "## File: $f" >> helmvalues-context.md
      echo "(file not present in checked-out tree at this ref)" >> helmvalues-context.md
      echo >> helmvalues-context.md
      continue
    fi

    LINES=$(wc -l < "$f")
    if [ $((TOTAL + LINES)) -gt 1200 ]; then
      echo "(helmrelease content truncated — too many total lines)" >> helmvalues-context.md
      break
    fi

    TOTAL=$((TOTAL + LINES))
    echo "## File: $f (${LINES} lines)" >> helmvalues-context.md
    echo '```yaml' >> helmvalues-context.md
    cat "$f" >> helmvalues-context.md
    echo '```' >> helmvalues-context.md
    echo >> helmvalues-context.md
  done <<< "$CHANGED_HELMRELEASES"
else
  echo "No helmrelease.yaml files changed in this PR." >> helmvalues-context.md
fi

# --- Step 3: Gather linked sources ---

log "Gathering linked sources..."
: > linked-sources.md
if [ -s urls.txt ]; then
  TARGET_VERSION="$(jq -r '.title' pr.json | sed -n 's/.*→ *v\?\([0-9][0-9.]*\).*/\1/p' | head -n1)"
  if [ -z "$TARGET_VERSION" ]; then
    TARGET_VERSION="$(grep -Eo 'v?[0-9]+\.[0-9]+\.[0-9]+' version-hints.truncated.txt 2>/dev/null | sed 's/^v//' | tail -n1 || true)"
  fi

  : > seen-repos.txt
  : > repo-candidates.txt
  i=0
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    i=$((i+1))
    [ "$i" -gt 25 ] && break

    normalized_url="$(printf '%s' "$url" | sed -E 's#^https?://redirect.github.com/#https://github.com/#')"

    {
      echo "## Source $i"
      echo "URL: $url"
      if [ "$normalized_url" != "$url" ]; then
        echo "Normalized URL: $normalized_url"
      fi
      echo
      echo "### Fetched Content (truncated)"
    } >> linked-sources.md

    host=$(printf '%s' "$normalized_url" | sed -E 's#^https?://([^/]+).*#\1#' | tr '[:upper:]' '[:lower:]')
    allowed=0
    IFS=',' read -ra allowed_hosts <<< "$ALLOWED_SOURCE_HOSTS"
    for raw_host in "${allowed_hosts[@]}"; do
      candidate=$(printf '%s' "$raw_host" | xargs | tr '[:upper:]' '[:lower:]')
      [ -n "$candidate" ] || continue
      if [ "$host" = "$candidate" ]; then
        allowed=1
        break
      fi
    done

    if [ "$allowed" -eq 1 ]; then
      if curl -fsSL -L --max-time 25 "$normalized_url" -o source.raw 2>/dev/null; then
        head -c 5000 source.raw | tr $'\0' ' ' > source.tmp
        if [ -s source.tmp ]; then
          echo '```text' >> linked-sources.md
          cat source.tmp >> linked-sources.md
          echo >> linked-sources.md
          echo '```' >> linked-sources.md
        else
          echo "(No content captured from URL)" >> linked-sources.md
        fi
      else
        echo "(Failed to fetch allowlisted URL content from $host)" >> linked-sources.md
      fi
    else
      echo "(Skipped non-allowlisted URL on self-hosted runner: $host)" >> linked-sources.md
    fi

    if [[ "$normalized_url" =~ ^https?://github\.com/([^/]+)/([^/]+)/releases/tag/([^/?#]+) ]]; then
      owner="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]}"
      tag="${BASH_REMATCH[3]}"

      echo >> linked-sources.md
      echo "### GitHub Release Metadata: $owner/$repo@$tag" >> linked-sources.md

      if gh api "repos/$owner/$repo/releases/tags/$tag" > gh-release.json 2>/dev/null; then
        jq '{tag_name,name,published_at,html_url,body}' gh-release.json > gh-release.filtered.json
        echo '```json' >> linked-sources.md
        head -c 5000 gh-release.filtered.json >> linked-sources.md
        echo >> linked-sources.md
        echo '```' >> linked-sources.md
      else
        echo "(Could not fetch release metadata for tag $tag)" >> linked-sources.md
      fi

      if gh api "repos/$owner/$repo/releases?per_page=8" > gh-releases.json 2>/dev/null; then
        jq '[.[] | {tag_name,name,published_at,html_url}]' gh-releases.json > gh-releases.filtered.json
        echo "### Recent Releases" >> linked-sources.md
        echo '```json' >> linked-sources.md
        head -c 3000 gh-releases.filtered.json >> linked-sources.md
        echo >> linked-sources.md
        echo '```' >> linked-sources.md
      fi
    fi

    if [[ "$normalized_url" =~ ^https?://github\.com/([^/]+)/([^/]+)/compare/([^?#]+)$ ]]; then
      owner="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]}"
      compare_spec="${BASH_REMATCH[3]}"

      echo >> linked-sources.md
      echo "### GitHub Compare Metadata: $owner/$repo@$compare_spec" >> linked-sources.md

      if gh api "repos/$owner/$repo/compare/$compare_spec" > gh-compare.json 2>/dev/null; then
        jq '{html_url,status,ahead_by,behind_by,total_commits,commits:[.commits[]? | {sha,commit:{message,author,date}}]}' gh-compare.json > gh-compare.filtered.json
        echo '```json' >> linked-sources.md
        head -c 7000 gh-compare.filtered.json >> linked-sources.md
        echo >> linked-sources.md
        echo '```' >> linked-sources.md

        jq '[.files[]? | {filename,status,additions,deletions,changes,patch}]' gh-compare.json > gh-compare.files.json
        echo "### GitHub Compare Files" >> linked-sources.md
        echo '```json' >> linked-sources.md
        head -c 7000 gh-compare.files.json >> linked-sources.md
        echo >> linked-sources.md
        echo '```' >> linked-sources.md
      else
        echo "(Could not fetch compare metadata for $owner/$repo@$compare_spec)" >> linked-sources.md
      fi
    fi

    if [[ "$normalized_url" =~ ^https?://github\.com/([^/]+)/([^/?#]+) ]]; then
      owner="${BASH_REMATCH[1]}"
      repo="${BASH_REMATCH[2]}"
      repo_key="$owner/$repo"
      grep -qx "$repo_key" repo-candidates.txt 2>/dev/null || echo "$repo_key" >> repo-candidates.txt
    fi

    echo >> linked-sources.md
  done < urls.txt

  while IFS= read -r repo_key; do
    [ -z "$repo_key" ] && continue
    if ! grep -qx "$repo_key" seen-repos.txt 2>/dev/null; then
      echo "$repo_key" >> seen-repos.txt
      owner="${repo_key%/*}"
      repo="${repo_key#*/}"

      echo >> linked-sources.md
      echo "### GitHub Releases Enrichment: $repo_key" >> linked-sources.md

      if gh api "repos/$owner/$repo/releases?per_page=30" > gh-releases.repo.json 2>/dev/null; then
        jq '[.[] | {tag_name,name,published_at,html_url}]' gh-releases.repo.json > gh-releases.repo.filtered.json
        echo "#### Recent Releases (tags)" >> linked-sources.md
        echo '```json' >> linked-sources.md
        head -c 5000 gh-releases.repo.filtered.json >> linked-sources.md
        echo >> linked-sources.md
        echo '```' >> linked-sources.md

        if [ -n "$TARGET_VERSION" ]; then
          jq --arg v "$TARGET_VERSION" '
            [ .[]
              | select(
                  ((.tag_name // "" | ascii_downcase) == ($v | ascii_downcase))
                  or ((.tag_name // "" | ascii_downcase) == ("v" + ($v | ascii_downcase)))
                  or ((.tag_name // "" | ascii_downcase) | contains(($v | ascii_downcase)))
                  or ((.name // "" | ascii_downcase) | contains(($v | ascii_downcase)))
                )
              | {tag_name,name,published_at,html_url,body}
            ][:5]
          ' gh-releases.repo.json > gh-releases.target.filtered.json
          if [ "$(jq 'length' gh-releases.target.filtered.json)" -gt 0 ]; then
            echo "#### Releases matching target version $TARGET_VERSION" >> linked-sources.md
            echo '```json' >> linked-sources.md
            head -c 8000 gh-releases.target.filtered.json >> linked-sources.md
            echo >> linked-sources.md
            echo '```' >> linked-sources.md
          else
            echo "(No release tags matched target version $TARGET_VERSION in $repo_key)" >> linked-sources.md
            if gh api "repos/$owner/$repo/tags?per_page=50" > gh-tags.repo.json 2>/dev/null; then
              jq '[.[] | {name,commit:.commit.sha}]' gh-tags.repo.json > gh-tags.repo.filtered.json
              echo "#### Recent Tags" >> linked-sources.md
              echo '```json' >> linked-sources.md
              head -c 4000 gh-tags.repo.filtered.json >> linked-sources.md
              echo >> linked-sources.md
              echo '```' >> linked-sources.md
            else
              echo "(Could not fetch tags list for $repo_key)" >> linked-sources.md
            fi
          fi
        fi
      else
        echo "(Could not fetch releases list for $repo_key)" >> linked-sources.md
      fi
    fi
  done < repo-candidates.txt
fi

# --- Step 4: Gather image digest provenance context ---

log "Gathering image digest provenance..."
python3 "$SCRIPT_DIR/image_digest_analysis.py" || error "Image digest analysis failed"

# --- Step 5: Gather repo impact + history context ---

log "Gathering repository impact and history..."
{
  jq -r '.title, (.body // "")' pr.json
  cat version-hints.truncated.txt 2>/dev/null || true
} \
  | tr '[:upper:]' '[:lower:]' \
  | grep -Eo '[a-z0-9][a-z0-9._/-]{2,}' \
  | grep -Ev '^(https?|from|into|that|this|with|without|renovate|pull|request|release|notes|digest|sha|main|chart|image|version|kubernetes|github|com|www|docker|ghcr|io)$' \
  | sort -u \
  | head -n 14 > terms.txt || true

: > repo-impact.md
: > repo-history.md

if [ -s terms.txt ]; then
  while IFS= read -r term; do
    [ -z "$term" ] && continue

    {
      echo "## Term: $term"
      echo
      echo "### git grep hits"
      echo '```text'
      git grep -n -- "$term" -- \
        kubernetes \
        .github \
        docs \
        2>/dev/null | head -n 60 || true
      echo '```'
      echo
    } >> repo-impact.md

    {
      echo "## Term: $term"
      echo
      echo "### git log context"
      echo '```text'
      git log --oneline --decorate --grep="$term" -n 10 || true
      echo '```'
      echo
    } >> repo-history.md
  done < terms.txt

  head -c 45000 repo-impact.md > repo-impact.truncated.md
  head -c 20000 repo-history.md > repo-history.truncated.md
else
  echo "No candidate dependency terms extracted." > repo-impact.md
  echo "No candidate dependency terms extracted." > repo-history.md
fi

# --- Step 6: Build review corpus ---

log "Building review corpus..."
: > standards-context.md
if [ -f "$STANDARDS_FILE" ]; then
  echo "# Repository Standards and Conventions" >> standards-context.md
  echo "Derived from $STANDARDS_FILE for this repository." >> standards-context.md
  echo >> standards-context.md
  cat "$STANDARDS_FILE" >> standards-context.md
else
  echo "($STANDARDS_FILE not found; standards context unavailable.)" >> standards-context.md
fi

{
  echo "# HelmRelease Values Context"
  cat helmvalues-context.md
  echo
  echo "# PR Metadata"
  echo '```json'
  jq . pr.json
  echo '```'
  echo
  echo "# PR Files (truncated)"
  echo '```json'
  cat pr-files.truncated.json
  echo '```'
  echo
  echo "# Version Hints from Diff"
  echo '```text'
  cat version-hints.truncated.txt 2>/dev/null || echo "(none)"
  echo '```'
  echo
  echo "# PR Diff (truncated)"
  echo '```diff'
  cat pr.diff.truncated
  echo '```'
  echo
  echo "# Linked Sources"
  cat linked-sources.md
  echo
  echo "# Image Digest Provenance"
  cat image-digest-context.md
  echo
  echo "# Repository Impact Scan"
  cat repo-impact.truncated.md
  echo
  echo "# Repository History"
  cat repo-history.truncated.md
  echo
  echo "# Repository Standards and Conventions ($STANDARDS_FILE)"
  cat standards-context.md
} > review-corpus.md

head -c 220000 review-corpus.md > review-corpus.truncated.md

# --- Step 7: Analyze with AI ---

log "Analyzing with $AI_MODEL..."

jq -n \
  --arg model "$AI_MODEL" \
  --arg system "$SYSTEM_PROMPT" \
  --arg user "Analyze this Renovate PR corpus and return STRICT JSON." \
  --rawfile corpus review-corpus.truncated.md \
  '{model:$model,messages:[{role:"system",content:$system},{role:"user",content:($user + "\n\n" + $corpus)}],temperature:0.1}' > ai-request.primary.json

# Retry logic and fallback logic
PRIMARY_OK=0
ATTEMPT=1
while [ "$ATTEMPT" -le "$AI_PRIMARY_RETRIES" ]; do
  echo "Primary model attempt ${ATTEMPT}/${AI_PRIMARY_RETRIES}: $AI_MODEL @ $AI_BASE_URL"
  if curl_model "$AI_BASE_URL" "$AI_API_KEY" ai-request.primary.json ai-response.primary.json && \
    parse_and_validate ai-response.primary.json; then
    PRIMARY_OK=1
    break
  fi

  echo "Primary model attempt $ATTEMPT failed; waiting ${AI_PRIMARY_RETRY_DELAY_SEC}s" >&2
  ATTEMPT=$((ATTEMPT + 1))
  sleep "$AI_PRIMARY_RETRY_DELAY_SEC"
done

if [ "$PRIMARY_OK" -eq 1 ]; then
  ANALYSIS_ENGINE="$AI_MODEL@$AI_BASE_URL"
  echo "Primary model succeeded"
else
  if [[ -z "$AI_FALLBACK_BASE_URL" || -z "$AI_FALLBACK_MODEL" ]]; then
    error "Primary model unavailable and no fallback model configured"
    exit 1
  fi

  echo "Primary model unavailable after retries; trying fallback: $AI_FALLBACK_MODEL @ $AI_FALLBACK_BASE_URL" >&2
  head -c 120000 review-corpus.md > review-corpus.fallback.truncated.md
  jq -n \
    --arg model "$AI_FALLBACK_MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "Analyze this Renovate PR corpus and return STRICT JSON." \
    --rawfile corpus review-corpus.fallback.truncated.md \
    '{model:$model,messages:[{role:"system",content:$system},{role:"user",content:($user + "\n\n" + $corpus)}],temperature:0.1}' > ai-request.fallback.json

  if curl_model "$AI_FALLBACK_BASE_URL" "$AI_FALLBACK_API_KEY" ai-request.fallback.json ai-response.fallback.json && \
    parse_and_validate ai-response.fallback.json; then
    ANALYSIS_ENGINE="$AI_FALLBACK_MODEL@$AI_FALLBACK_BASE_URL"
    echo "Fallback model succeeded" >&2
  else
    error "Fallback model failed"
    exit 1
  fi
fi

echo "analysis_engine=$ANALYSIS_ENGINE" >> "$OUTPUT_FILE"
echo "verdict=$(jq -r '.verdict' ai-output.json)" >> "$OUTPUT_FILE"

{
  echo 'review_markdown<<EOF'
  jq -r '.review_markdown' ai-output.json
  echo 'EOF'
} >> "$OUTPUT_FILE"

# --- Step 8: Output Results ---

log "Analysis complete. Writing outputs..."
jq -r '.review_markdown' ai-output.json > review-body.md
echo "$(jq -r '.verdict' ai-output.json)" > verdict.txt
echo "$ANALYSIS_ENGINE" > analysis_engine.txt

log "Done."
