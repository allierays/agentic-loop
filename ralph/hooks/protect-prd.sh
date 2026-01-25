#!/usr/bin/env bash
# protect-prd.sh - Protect prd.json from marking stories as passed
# Hook: PreToolUse matcher: "Edit|Write"
#
# Allows: Most edits to prd.json (adding fields, fixing test steps, etc.)
# Blocks: Edits that mark stories as "passes": true (Ralph handles this)

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Check if editing prd.json
if [[ "$FILE_PATH" == *"prd.json"* ]]; then
  # Get the new content being written
  NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // .tool_input.content // ""')

  # Block if trying to set passes to true (Ralph handles story completion)
  if echo "$NEW_STRING" | grep -qE '"passes"\s*:\s*true'; then
    echo "BLOCKED: Cannot mark stories as passed. Ralph handles this after verification." >&2
    exit 2  # Exit code 2 = blocking error
  fi

  # Allow all other prd.json edits (adding mcp, originalContext, fixing testSteps, etc.)
  echo '{"continue": true}'
  exit 0
fi

# Allow all other edits
echo '{"continue": true}'
