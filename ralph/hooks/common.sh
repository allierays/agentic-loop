#!/usr/bin/env bash
# shellcheck shell=bash
# common.sh - Shared utilities for Claude Code hooks
#
# Source this file at the start of PostToolUse hooks:
#   source "$(dirname "$0")/common.sh"
#
# Provides:
#   - parse_hook_input: Sets HOOK_INPUT, TOOL_NAME, FILE_PATH, NEW_CONTENT
#   - is_code_file: Check if FILE_PATH matches code extensions
#   - is_test_file: Check if FILE_PATH is a test file
#   - hook_allow: Output JSON to allow the operation
#   - hook_warn: Output JSON warning (non-blocking)
#   - hook_block: Output JSON to block the operation

set -euo pipefail

# Global variables set by parse_hook_input
HOOK_INPUT=""
TOOL_NAME=""
FILE_PATH=""
NEW_CONTENT=""

# Parse hook input from stdin and extract common fields
# Sets: HOOK_INPUT, TOOL_NAME, FILE_PATH, NEW_CONTENT
parse_hook_input() {
  HOOK_INPUT=$(cat)
  TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // ""')
  FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

  # Extract content based on tool type
  NEW_CONTENT=""
  if [[ "$TOOL_NAME" == "Write" ]]; then
    NEW_CONTENT=$(echo "$HOOK_INPUT" | jq -r '.tool_input.content // ""')
  elif [[ "$TOOL_NAME" == "Edit" ]]; then
    NEW_CONTENT=$(echo "$HOOK_INPUT" | jq -r '.tool_input.new_string // ""')
  fi
}

# Check if FILE_PATH matches given extensions
# Usage: is_code_file "ts,tsx,js,jsx,py" && echo "yes"
is_code_file() {
  local extensions="$1"

  # Files without extension don't match
  [[ "$FILE_PATH" != *"."* ]] && return 1

  local file_ext="${FILE_PATH##*.}"

  # Check if file extension is in the comma-separated list
  [[ ",$extensions," == *",$file_ext,"* ]]
}

# Check if FILE_PATH is a test file
is_test_file() {
  case "$FILE_PATH" in
    *.test.*|*.spec.*|*/__tests__/*|*/test/*|*/tests/*|*/fixtures/*)
      return 0
      ;;
  esac
  return 1
}

# Output JSON to allow the operation (continue: true)
hook_allow() {
  echo '{"continue": true}'
}

# Output warning JSON (non-blocking, adds context)
# Usage: hook_warn "Warning message"
hook_warn() {
  local message="$1"
  jq -n --arg warn "$message" '{
    "continue": true,
    "hookSpecificOutput": {
      "additionalContext": $warn
    }
  }'
}

# Output blocking JSON (continue: false)
# Usage: hook_block "Error message"
hook_block() {
  local message="$1"
  jq -n --arg msg "$message" '{
    "continue": false,
    "message": $msg
  }'
}

# Run a warn-* hook with shared boilerplate
# Usage: run_warn_hook <extensions> <check_fn> [--skip-tests] [--block]
#   extensions: comma-separated file extensions to match (e.g., "ts,tsx,js,jsx,py")
#   check_fn:   function name that sets WARNINGS variable
#   --skip-tests: skip test files
#   --block:      use hook_block instead of hook_warn on warning
run_warn_hook() {
  local extensions="$1"
  local check_fn="$2"
  shift 2

  local skip_tests=false
  local block=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-tests) skip_tests=true ;;
      --block) block=true ;;
    esac
    shift
  done

  parse_hook_input

  if [[ "$skip_tests" == "true" ]] && is_test_file; then
    hook_allow
    exit 0
  fi

  if ! is_code_file "$extensions"; then
    hook_allow
    exit 0
  fi

  WARNINGS=""
  "$check_fn"

  if [[ -n "$WARNINGS" ]]; then
    if [[ "$block" == "true" ]]; then
      hook_block "$WARNINGS"
    else
      hook_warn "$WARNINGS"
    fi
  else
    hook_allow
  fi
}
