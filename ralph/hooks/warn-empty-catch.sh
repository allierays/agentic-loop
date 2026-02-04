#!/usr/bin/env bash
# shellcheck shell=bash
# warn-empty-catch.sh - Warn about empty catch blocks that silently swallow errors
# Hook: PostToolUse matcher: "Edit|Write"

source "$(dirname "$0")/common.sh"

_check_empty_catch() {
  # JavaScript/TypeScript: catch (e) { } or catch { }
  if echo "$NEW_CONTENT" | grep -qE 'catch[[:space:]]*\([^)]*\)[[:space:]]*\{[[:space:]]*\}'; then
    WARNINGS="⚠️  Empty catch block detected. Handle the error or add a comment explaining why it's ignored."
  fi

  # Also check for catch with only a comment (no actual handling)
  if echo "$NEW_CONTENT" | grep -qE 'catch[[:space:]]*\([^)]*\)[[:space:]]*\{[[:space:]]*(//[^}]*)?\}'; then
    if [[ -z "$WARNINGS" ]]; then
      WARNINGS="⚠️  Catch block with no error handling. Consider logging or rethrowing the error."
    fi
  fi

  # Python: except: pass or except Exception: pass
  if echo "$NEW_CONTENT" | grep -qE 'except.*:[[:space:]]*pass[[:space:]]*$'; then
    WARNINGS="⚠️  Empty except block (pass). Handle the exception or add logging."
  fi

  # Python: bare except with just pass on next line
  if echo "$NEW_CONTENT" | grep -qE 'except.*:[[:space:]]*$' && echo "$NEW_CONTENT" | grep -qE '^[[:space:]]*pass[[:space:]]*$'; then
    if [[ -z "$WARNINGS" ]]; then
      WARNINGS="⚠️  Except block with only 'pass'. Consider logging or reraising the exception."
    fi
  fi
}

run_warn_hook "ts,tsx,js,jsx,py" _check_empty_catch --block
