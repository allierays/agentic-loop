#!/usr/bin/env bash
# inject-context.sh - Inject signs and recent progress at session start
# Hook: SessionStart

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
RALPH_DIR="$CWD/.ralph"

CONTEXT=""

# Inject signs (learned patterns)
if [[ -f "$RALPH_DIR/signs.json" ]]; then
  SIGNS=$(jq -r '.signs[]? | "- [\(.category)] \(.pattern)"' "$RALPH_DIR/signs.json" 2>/dev/null | head -20)
  if [[ -n "$SIGNS" ]]; then
    CONTEXT="## Learned Patterns (Signs)\nApply these lessons:\n$SIGNS\n\n"
  fi
fi

# Inject recent progress
if [[ -f "$RALPH_DIR/progress.txt" ]]; then
  PROGRESS=$(tail -10 "$RALPH_DIR/progress.txt" 2>/dev/null)
  if [[ -n "$PROGRESS" ]]; then
    CONTEXT="${CONTEXT}## Recent Progress\n$PROGRESS\n\n"
  fi
fi

# Inject last failure context if exists
if [[ -f "$RALPH_DIR/last_failure.txt" ]]; then
  FAILURE=$(cat "$RALPH_DIR/last_failure.txt" | head -50)
  CONTEXT="${CONTEXT}## Previous Failure (FIX THIS)\n$FAILURE\n"
fi

if [[ -n "$CONTEXT" ]]; then
  jq -n --arg ctx "$CONTEXT" '{
    "continue": true,
    "hookSpecificOutput": {
      "additionalContext": $ctx
    }
  }'
else
  echo '{"continue": true}'
fi
