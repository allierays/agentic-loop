#!/usr/bin/env bash
# protect-prd.sh - Protect prd.json from accidental edits
# Hook: PreToolUse matcher: "Edit|Write"
#
# Allows: /prd, /idea commands (they create .prd-edit-allowed marker)
# Blocks: Accidental edits during normal coding

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Check if editing prd.json
if [[ "$FILE_PATH" == *"prd.json"* ]]; then
  # Allow if /prd or /idea set the bypass marker
  if [[ -f ".ralph/.prd-edit-allowed" ]]; then
    rm -f ".ralph/.prd-edit-allowed"  # One-time use
    echo '{"continue": true}'
    exit 0
  fi

  echo "BLOCKED: prd.json is managed by Ralph. Use /prd or /idea to add stories." >&2
  exit 2  # Exit code 2 = blocking error
fi

# Allow all other edits
echo '{"continue": true}'
