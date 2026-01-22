#!/usr/bin/env bash
# save-learnings.sh - Extract potential learnings from session transcript
# Hook: Stop
#
# This hook analyzes the transcript for patterns that might be worth saving as signs.
# It logs suggestions to .ralph/suggested-signs.txt for human review.

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
RALPH_DIR="$CWD/.ralph"

# Ensure .ralph directory exists
mkdir -p "$RALPH_DIR"

# Log session end
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session ended" >> "$RALPH_DIR/progress.txt"

# If transcript exists, analyze for patterns
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  # Look for retry patterns (same error appearing multiple times)
  # Look for "I learned" or "the issue was" phrases
  # This is a simple heuristic - can be enhanced

  PATTERNS=$(grep -E "(the issue was|I learned|the problem was|fixed by|solution was)" "$TRANSCRIPT_PATH" 2>/dev/null | tail -5 || true)

  if [[ -n "$PATTERNS" ]]; then
    echo "" >> "$RALPH_DIR/suggested-signs.txt"
    echo "=== Session $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$RALPH_DIR/suggested-signs.txt"
    echo "$PATTERNS" >> "$RALPH_DIR/suggested-signs.txt"
  fi
fi

echo '{"continue": true}'
