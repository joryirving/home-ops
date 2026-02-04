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

# The original GitHub payload is available as an environment variable from webhook
ORIGINAL_HOOK_PAYLOAD=$(cat)

# Forward the ORIGINAL GitHub payload directly to OpenClaw instead of creating a simplified version
# This preserves the full GitHub webhook structure that the transform function expects
PAYLOAD_JSON="$ORIGINAL_HOOK_PAYLOAD"

# Send notification to OpenClaw with authentication
# Using the webhook secret as the authentication token for OpenClaw
response=$(curl -s -w "\n%{http_code}" -X POST http://openclaw.llm:18789/webhooks/github \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: $EVENT_TYPE" \
  -H "X-GitHub-Delivery: $(date +%s)" \
  -H "Authorization: Bearer $GITHUB_WEBHOOK_SECRET" \
  -d "$PAYLOAD_JSON")

http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | head -n-1)

if [ "$http_code" -eq 200 ]; then
  echo "Successfully sent original GitHub payload to OpenClaw" >&2
  echo "$response_body"
else
  echo "Failed to send notification to OpenClaw, HTTP Code: $http_code" >&2
  echo "Response: $response_body" >&2
  exit 1
fi