#!/usr/bin/env bash
# protect-prd.sh - Block edits to prd.json (Ralph manages this file)
# Hook: PreToolUse matcher: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Block any attempt to edit prd.json
if [[ "$FILE_PATH" == *"prd.json"* ]]; then
  echo "BLOCKED: prd.json is managed by Ralph. Do not edit it directly." >&2
  exit 2  # Exit code 2 = blocking error
fi

# Allow all other edits
echo '{"continue": true}'
