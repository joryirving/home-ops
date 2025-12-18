#!/bin/bash

RAW_PAYLOAD="$1"

echo "Received payload:"
echo "$RAW_PAYLOAD" > /tmp/latest-payload.json
