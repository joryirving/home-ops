#!/usr/bin/env bash
set -euo pipefail

file="${1:?Usage: validate-images.sh <file>}"

ALLOWED_REGISTRIES="docker.io ghcr.io nvcr.io public.ecr.aws registry.erwanleboucher.dev registry.k8s.io quay.io mirror.gcr.io atdr.meo.ws"
MAX_IMAGES=500
MAX_FILE_BYTES=65536

if [ ! -f "$file" ]; then
  echo "::error::File not found: $file" >&2
  exit 1
fi

file_bytes=$(wc -c < "$file" | tr -d ' ')
if [ "$file_bytes" -gt "$MAX_FILE_BYTES" ]; then
  echo "::error::Image list exceeds ${MAX_FILE_BYTES} bytes (${file_bytes})" >&2
  exit 1
fi

if ! jq empty "$file" 2>/dev/null; then
  echo "::error::Invalid JSON in $file" >&2
  exit 1
fi

if [ "$(jq 'type' "$file")" != '"array"' ]; then
  echo "::error::Image list is not a JSON array" >&2
  exit 1
fi

non_string=$(jq '[.[] | select(type != "string")] | length' "$file")
if [ "$non_string" -ne 0 ]; then
  echo "::error::Image list contains non-string entries" >&2
  exit 1
fi

count=$(jq 'length' "$file")
if [ "$count" -gt "$MAX_IMAGES" ]; then
  echo "::error::Image count ${count} exceeds maximum ${MAX_IMAGES}" >&2
  exit 1
fi

jq -r '.[]' "$file" | while IFS= read -r image; do
  if [ -z "$image" ]; then
    echo "::error::Empty image reference" >&2
    exit 1
  fi

  case "$image" in
    *"://"*)
      echo "::error::Image contains URL scheme: $image" >&2
      exit 1
      ;;
  esac

  if printf '%s' "$image" | grep -qE '[[:cntrl:][:space:]]'; then
    echo "::error::Image contains whitespace or control characters: $image" >&2
    exit 1
  fi

  case "$image" in
    [-]*)
      echo "::error::Image starts with dash (option injection): $image" >&2
      exit 1
      ;;
  esac

  if printf '%s' "$image" | grep -qE "[;|&\`\$(){}<>!\\\\#*~^?\"']"; then
    echo "::error::Image contains shell metacharacters: $image" >&2
    exit 1
  fi

  case "$image" in
    */*)
      first="${image%%/*}"
      case "$first" in
        *.*|*:*) host="$first" ;;
        *) host="docker.io" ;;
      esac
      ;;
    *)
      host="docker.io"
      ;;
  esac

  allowed=false
  for reg in $ALLOWED_REGISTRIES; do
    if [ "$host" = "$reg" ]; then
      allowed=true
      break
    fi
  done

  if [ "$allowed" = false ]; then
    echo "::error::Disallowed registry: $host (image: $image)" >&2
    exit 1
  fi
done

jq -c '.' "$file" > "${file}.compact"
mv "${file}.compact" "$file"

echo "Validated ${count} images (${file_bytes} bytes)"
