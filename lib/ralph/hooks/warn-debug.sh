#!/usr/bin/env bash
# warn-debug.sh - Warn about debug statements in written code
# Hook: PostToolUse matcher: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Only check code files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs)
    ;;
  *)
    echo '{"continue": true}'
    exit 0
    ;;
esac

# Get the content that was written
NEW_CONTENT=""
if [[ "$TOOL_NAME" == "Write" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')
fi

# Check for debug patterns
WARNINGS=""

if echo "$NEW_CONTENT" | grep -qE 'console\.(log|debug|info|warn|error)\s*\('; then
  WARNINGS="⚠️  Debug statement detected: console.log/debug. Remove before commit."
fi

if echo "$NEW_CONTENT" | grep -qE '^\s*debugger\s*;?\s*$'; then
  WARNINGS="${WARNINGS}\n⚠️  Debugger statement detected. Remove before commit."
fi

if echo "$NEW_CONTENT" | grep -qE '^\s*print\s*\('; then
  WARNINGS="${WARNINGS}\n⚠️  Print statement detected. Remove before commit."
fi

# Output warning as additional context (non-blocking)
if [[ -n "$WARNINGS" ]]; then
  jq -n --arg warn "$WARNINGS" '{
    "continue": true,
    "hookSpecificOutput": {
      "additionalContext": $warn
    }
  }'
else
  echo '{"continue": true}'
fi
