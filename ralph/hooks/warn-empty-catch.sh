#!/usr/bin/env bash
# warn-empty-catch.sh - Warn about empty catch blocks that silently swallow errors
# Hook: PostToolUse matcher: "Edit|Write"

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Only check code files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.py)
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

WARNINGS=""

# JavaScript/TypeScript: catch (e) { } or catch { }
if echo "$NEW_CONTENT" | grep -qE 'catch\s*\([^)]*\)\s*\{\s*\}'; then
  WARNINGS="⚠️  Empty catch block detected. Handle the error or add a comment explaining why it's ignored."
fi

# Also check for catch with only a comment (no actual handling)
if echo "$NEW_CONTENT" | grep -qE 'catch\s*\([^)]*\)\s*\{\s*(//[^\n]*)?\s*\}'; then
  if [[ -z "$WARNINGS" ]]; then
    WARNINGS="⚠️  Catch block with no error handling. Consider logging or rethrowing the error."
  fi
fi

# Python: except: pass or except Exception: pass
if echo "$NEW_CONTENT" | grep -qE 'except.*:\s*pass\s*$'; then
  WARNINGS="⚠️  Empty except block (pass). Handle the exception or add logging."
fi

# Python: bare except with just pass on next line
if echo "$NEW_CONTENT" | grep -qE 'except.*:\s*$' && echo "$NEW_CONTENT" | grep -qE '^\s*pass\s*$'; then
  if [[ -z "$WARNINGS" ]]; then
    WARNINGS="⚠️  Except block with only 'pass'. Consider logging or reraising the exception."
  fi
fi

# Block if empty catch detected
if [[ -n "$WARNINGS" ]]; then
  jq -n --arg warn "$WARNINGS" '{
    "continue": false,
    "message": $warn
  }'
else
  echo '{"continue": true}'
fi
