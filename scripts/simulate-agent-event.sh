#!/bin/sh
# Drives the Knurl bridge without a real agent. Usage:
#   scripts/simulate-agent-event.sh <kind> [session-id] [tool-or-path]
set -eu
PORT="${KNURL_BRIDGE_PORT:-51741}"
KIND="${1:?usage: simulate-agent-event.sh <kind> [session] [tool|path]}"
SESSION="${2:-sim-1}"
EXTRA="${3:-}"

body="{\"provider\":\"cursor\",\"session_id\":\"$SESSION\",\"kind\":\"$KIND\""
if [ -n "$EXTRA" ]; then
  case "$EXTRA" in
    */*) body="$body,\"path\":\"$EXTRA\"" ;;
    *)   body="$body,\"tool\":\"$EXTRA\"" ;;
  esac
fi
body="$body,\"working_directory\":\"$(pwd)\"}"

printf '%s' "$body" | curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "http://127.0.0.1:$PORT/event" \
  -H 'Content-Type: application/json' \
  --data-binary @-
