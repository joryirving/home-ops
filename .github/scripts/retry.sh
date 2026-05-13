#!/usr/bin/env bash
set -euo pipefail

attempts="${RETRY_ATTEMPTS:-3}"
delay="${RETRY_DELAY_SECONDS:-20}"

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 2
fi

for attempt in $(seq 1 "$attempts"); do
  status=0
  "$@" || status="$?"

  if [[ "$status" -eq 0 ]]; then
    exit 0
  fi

  if [[ "$attempt" -eq "$attempts" ]]; then
    exit "$status"
  fi

  echo "Command failed with exit code $status; retrying in ${delay}s (${attempt}/${attempts})..." >&2
  sleep "$delay"
done
