#!/usr/bin/env bash
# shellcheck shell=bash
# warn-debug.sh - Warn about debug statements in written code
# Hook: PostToolUse matcher: "Edit|Write"

source "$(dirname "$0")/common.sh"

_check_debug() {
  if echo "$NEW_CONTENT" | grep -qE 'console\.(log|debug|info|warn|error)[[:space:]]*\('; then
    WARNINGS="⚠️  Debug statement detected: console.log/debug. Remove before commit."
  fi

  if echo "$NEW_CONTENT" | grep -qE '^[[:space:]]*debugger[[:space:]]*;?[[:space:]]*$'; then
    WARNINGS="${WARNINGS}${WARNINGS:+\\n}⚠️  Debugger statement detected. Remove before commit."
  fi

  if echo "$NEW_CONTENT" | grep -qE '^[[:space:]]*print[[:space:]]*\('; then
    WARNINGS="${WARNINGS}${WARNINGS:+\\n}⚠️  Print statement detected. Remove before commit."
  fi
}

run_warn_hook "ts,tsx,js,jsx,py,go,rs" _check_debug
