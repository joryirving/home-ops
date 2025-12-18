#!/bin/bash

EVENT="$1"
RAW_PAYLOAD=$(cat)   # Read the full webhook body from stdin

echo "Event: $EVENT"
echo "Payload size: $(echo "$RAW_PAYLOAD" | wc -c) bytes"
echo "$RAW_PAYLOAD" > /tmp/latest-payload.json
