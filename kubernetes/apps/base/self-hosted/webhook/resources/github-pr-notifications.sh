#!/bin/bash

# Script to handle GitHub notifications and forward to OpenClaw
# Parameters:
# $1 - Repository name
# $2 - Event type
# $3 - Action type
# $4 - Issue/PR number

REPOSITORY_NAME="$1"
EVENT_TYPE="$2"
ACTION_TYPE="$3"
ISSUE_NUMBER="$4"

echo "$(date): Received GitHub event: $EVENT_TYPE action: $ACTION_TYPE for $REPOSITORY_NAME issue/PR: $ISSUE_NUMBER" >&2

# The payload is available as an environment variable from webhook
HOOK_PAYLOAD=$(cat)

# Process the payload and extract relevant information
if command -v jq >/dev/null 2>&1; then
  # Use jq if available
  SENDER=$(echo "$HOOK_PAYLOAD" | jq -r '.sender.login // "unknown"')
  COMMENT_BODY=$(echo "$HOOK_PAYLOAD" | jq -r '.comment.body // empty')
else
  # Fallback parsing without jq (basic extraction)
  SENDER=$(echo "$HOOK_PAYLOAD" | sed -n 's/.*"login"[[:space:]*]:*[[:space:]*]"*\([^",}]*\)"*.*/\1/p' | head -1)
  if [ -z "$SENDER" ]; then
    SENDER="unknown"
  fi
  COMMENT_BODY=$(echo "$HOOK_PAYLOAD" | sed -n 's/.*"body"[[:space:]*]:*[[:space:]*]"*\([^"]*\)"*.*/\1/p' | head -1)
fi

# Prepare JSON payload for OpenClaw
PAYLOAD_JSON="{\"event\": \"$EVENT_TYPE\", \"action\": \"$ACTION_TYPE\", \"repository\": \"$REPOSITORY_NAME\", \"issue_number\": \"$ISSUE_NUMBER\", \"sender\": \"$SENDER\", \"comment_body\": \"$COMMENT_BODY\", \"timestamp\": \"$(date -Iseconds)\"}"

# Send notification to OpenClaw with authentication
# Using the webhook secret as the authentication token for OpenClaw
response=$(curl -s -w "\n%{http_code}" -X POST http://openclaw.llm.svc.cluster.local:18789/webhook/github \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: $EVENT_TYPE" \
  -H "X-GitHub-Delivery: $(date +%s)" \
  -H "Authorization: Bearer $OPENCLAW_WEBHOOK_TOKEN" \
  -d "$PAYLOAD_JSON")

http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | head -n-1)

if [ "$http_code" -eq 200 ]; then
  echo "Successfully sent notification to OpenClaw" >&2
  echo "$response_body"
else
  echo "Failed to send notification to OpenClaw, HTTP Code: $http_code" >&2
  echo "Response: $response_body" >&2
  exit 1
fi