#!/bin/bash

# Extract essential fields
EVENT_TYPE=${1:-}
ACTION_TYPE=${2:-}
REPOSITORY_NAME=${3:-}
REPOSITORY_OWNER=${4:-}
PR_NUMBER=${5:-}
PR_TITLE=${6:-}
PR_USER=${7:-}
PR_URL=${8:-}
PR_BODY=${9:-}

echo "$(date): Received GitHub event: $EVENT_TYPE action: $ACTION_TYPE for $REPOSITORY_NAME issue/PR: $PR_NUMBER" >&2

# Build the payload to send to OpenClaw
PAYLOAD_JSON=$(jq -n \
  --arg action "$ACTION_TYPE" \
  --arg repo "$REPOSITORY_NAME" \
  --arg repo_owner "$REPOSITORY_OWNER" \
  --arg pr_number "$PR_NUMBER" \
  --arg pr_title "$PR_TITLE" \
  --arg pr_user "$PR_USER" \
  --arg pr_url "$PR_URL" \
  --arg pr_body "$PR_BODY" \
  '{
    action: $action,
    repository: {
      full_name: $repo,
      owner: { login: $repo_owner }
    },
    pull_request: {
      number: ($pr_number | tonumber),
      title: $pr_title,
      user: { login: $pr_user },
      html_url: $pr_url,
      body: $pr_body
    }
  }')

# Send to OpenClaw
response=$(curl -s -w "\n%{http_code}" -X POST http://openclaw.llm:18789/webhooks/github \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GITHUB_WEBHOOK_SECRET" \
  -H "User-Agent: GitHub-Hookshot/test" \
  -H "X-GitHub-Event: $EVENT_TYPE" \
  -H "X-GitHub-Delivery: test-delivery-$(date +%s)" \
  -d "$PAYLOAD_JSON")

http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | head -n-1)

if [ "$http_code" -eq 200 ]; then
  echo "✅ Successfully sent GitHub payload to OpenClaw" >&2
  echo "$response_body"
else
  echo "❌ Failed to send notification to OpenClaw, HTTP Code: $http_code" >&2
  echo "$response_body" >&2
  exit 1
fi
