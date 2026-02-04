#!/bin/bash

# Read full payload from stdin
WEBHOOK_BODY=$(cat)

# Extract essential fields
REPOSITORY_NAME=$(echo "$WEBHOOK_BODY" | jq -r '.repository.full_name')
EVENT_TYPE=$(echo "$WEBHOOK_BODY" | jq -r '.pull_request ? .pull_request : .action')
ACTION_TYPE=$(echo "$WEBHOOK_BODY" | jq -r '.action')
PR_NUMBER=$(echo "$WEBHOOK_BODY" | jq -r '.pull_request.number // .issue.number // empty')
PR_TITLE=$(echo "$WEBHOOK_BODY" | jq -r '.pull_request.title // empty')
PR_USER=$(echo "$WEBHOOK_BODY" | jq -r '.pull_request.user.login // empty')
PR_URL=$(echo "$WEBHOOK_BODY" | jq -r '.pull_request.html_url // empty')
PR_BODY=$(echo "$WEBHOOK_BODY" | jq -r '.pull_request.body // empty')


echo "$(date): Received GitHub event: $EVENT_TYPE action: $ACTION_TYPE for $REPOSITORY_NAME issue/PR: $ISSUE_NUMBER" >&2

# Build the payload to send to OpenClaw
PAYLOAD_JSON=$(jq -n \
  --arg action "$ACTION_TYPE" \
  --arg repo "$REPOSITORY_NAME" \
  --arg pr_number "$PR_NUMBER" \
  --arg pr_title "$PR_TITLE" \
  --arg pr_user "$PR_USER" \
  --arg pr_url "$PR_URL" \
  --arg pr_body "$PR_BODY" \
  '{
    action: $action,
    repository: {
      full_name: $repo,
      owner: { login: $pr_user }
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
  -H "X-GitHub-Event: $EVENT_TYPE" \
  -H "X-GitHub-Delivery: test-delivery-$(date +%s)" \
  -H "Authorization: Bearer $GITHUB_WEBHOOK_SECRET" \
  -d "$PAYLOAD_JSON")

http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | head -n-1)

if [ "$http_code" -eq 200 ]; then
  echo "✅ Successfully sent GitHub payload to OpenClaw" >&2
  echo "$response_body"
else
  echo "❌ Failed to send notification to OpenClaw, HTTP Code: $http_code" >&2
  echo "Response: $response_body" >&2
  exit 1
fi
