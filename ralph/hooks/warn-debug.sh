#!/usr/bin/env bash
# shellcheck shell=bash
# warn-debug.sh - Warn about debug statements in written code
# Hook: PostToolUse matcher: "Edit|Write"

source "$(dirname "$0")/common.sh"

parse_hook_input

# Only check code files
if ! is_code_file "ts,tsx,js,jsx,py,go,rs"; then
  hook_allow
  exit 0
fi

# Check for debug patterns
WARNINGS=""

if echo "$NEW_CONTENT" | grep -qE 'console\.(log|debug|info|warn|error)[[:space:]]*\('; then
  WARNINGS="⚠️  Debug statement detected: console.log/debug. Remove before commit."
fi

if echo "$NEW_CONTENT" | grep -qE '^[[:space:]]*debugger[[:space:]]*;?[[:space:]]*$'; then
  WARNINGS="${WARNINGS}${WARNINGS:+\\n}⚠️  Debugger statement detected. Remove before commit."
fi

if echo "$NEW_CONTENT" | grep -qE '^[[:space:]]*print[[:space:]]*\('; then
  WARNINGS="${WARNINGS}${WARNINGS:+\\n}⚠️  Print statement detected. Remove before commit."
fi

# Output warning or allow
if [[ -n "$WARNINGS" ]]; then
  hook_warn "$WARNINGS"
else
  hook_allow
fi
