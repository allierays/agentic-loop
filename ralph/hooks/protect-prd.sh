#!/usr/bin/env bash
# protect-prd.sh - Protect prd.json from accidental edits
# Hook: PreToolUse matcher: "Edit|Write"
#
# Allows: /prd, /idea commands (they create .prd-edit-allowed marker)
# Allows: Ralph loop fixing test steps (detected by last_failure.txt)
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

  # Allow if Ralph is in a retry loop with a RECENT failure (within 10 min)
  # This lets Ralph fix broken test steps, but not stale failures from old sessions
  if [[ -f ".ralph/last_failure.txt" ]]; then
    file_age=$(( $(date +%s) - $(stat -f %m ".ralph/last_failure.txt" 2>/dev/null || echo 0) ))
    if [[ $file_age -lt 600 ]]; then  # 10 minutes
      echo '{"continue": true}'
      exit 0
    fi
  fi

  echo "BLOCKED: prd.json is managed by Ralph. Use /prd or /idea to add stories." >&2
  exit 2  # Exit code 2 = blocking error
fi

# Allow all other edits
echo '{"continue": true}'
