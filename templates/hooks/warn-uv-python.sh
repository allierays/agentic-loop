#!/usr/bin/env bash
# warn-uv-python.sh - Warn about bare pytest/python instead of uv run
# Hook: PostToolUse matcher: "Bash"
#
# Copy to .ralph/hooks/ and Claude Code will warn when bare pytest/python
# commands are used in projects that should use 'uv run'.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Skip if empty
[[ -z "$COMMAND" ]] && { echo '{"continue": true}'; exit 0; }

WARNINGS=""

# Check for bare pytest (not preceded by "uv run")
if echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|)pytest\s' && ! echo "$COMMAND" | grep -qE 'uv run pytest'; then
  WARNINGS="Use 'uv run pytest' instead of bare 'pytest' to ensure correct environment."
fi

# Check for bare python (not preceded by "uv run")
if echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|)python\s' && ! echo "$COMMAND" | grep -qE 'uv run python'; then
  WARNINGS="${WARNINGS:+$WARNINGS\n}Use 'uv run python' instead of bare 'python' to ensure correct environment."
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
