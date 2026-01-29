#!/usr/bin/env bash
set -euo pipefail

# Incoming arguments
EVENT_TYPE=${1:-}
REPOSITORY=${2:-}
AUTHOR=${3:-}
ISSUE_NUMBER=${4:-}
BODY=${5:-}
URL=${6:-}

echo "$(date): Processing GitHub event - ${EVENT_TYPE} from ${AUTHOR} on ${REPOSITORY}#${ISSUE_NUMBER}"

# Check if the comment mentions the bot
if [[ "$BODY" =~ @(smurf-bot|moltbot|Miso) ]]; then
    echo "Event mentions bot, preparing notification..."

    # Prepare notification payload
    PAYLOAD=$(cat << EOF
{
  "event_type": "${EVENT_TYPE}",
  "repository": "${REPOSITORY}",
  "issue_number": "${ISSUE_NUMBER}",
  "author": "${AUTHOR}",
  "body": $(printf '%s' "$BODY" | jq -Rs '.' | sed 's/\\n/\\n/g'),
  "url": "${URL}",
  "timestamp": "$(date -Iseconds)"
}
EOF
)

    # Send to Moltbot webhook (configuration would depend on your setup)
    # This assumes you have a Moltbot webhook endpoint configured
    if [[ -n "${MOLTBOT_WEBHOOK_URL:-}" ]]; then
        curl -X POST \
             -H "Content-Type: application/json" \
             -H "User-Agent: GitHub-Webhook/1.0" \
             -d "${PAYLOAD}" \
             "${MOLTBOT_WEBHOOK_URL}"
        echo "Notification sent to Moltbot"
    else
        echo "MOLTBOT_WEBHOOK_URL not configured, saving payload to log:"
        echo "${PAYLOAD}"
    fi
else
    echo "Event does not mention bot, ignoring."
fi