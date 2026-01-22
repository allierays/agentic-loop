#!/usr/bin/env bash
# log-tools.sh - Log tool usage for debugging and analysis
# Hook: PostToolUse matcher: "*"

set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // "."')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
RALPH_DIR="$CWD/.ralph"

# Only log if .ralph exists (we're in a Ralph session)
if [[ -d "$RALPH_DIR" ]]; then
  TIMESTAMP=$(date '+%H:%M:%S')

  # Extract relevant info based on tool
  case "$TOOL_NAME" in
    Read)
      FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' | sed "s|$CWD/||")
      echo "[$TIMESTAMP] READ: $FILE" >> "$RALPH_DIR/tool-log.txt"
      ;;
    Write)
      FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' | sed "s|$CWD/||")
      echo "[$TIMESTAMP] WRITE: $FILE" >> "$RALPH_DIR/tool-log.txt"
      ;;
    Edit)
      FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' | sed "s|$CWD/||")
      echo "[$TIMESTAMP] EDIT: $FILE" >> "$RALPH_DIR/tool-log.txt"
      ;;
    Bash)
      CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' | head -c 80)
      echo "[$TIMESTAMP] BASH: $CMD" >> "$RALPH_DIR/tool-log.txt"
      ;;
    Grep|Glob)
      PATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // ""')
      echo "[$TIMESTAMP] $TOOL_NAME: $PATTERN" >> "$RALPH_DIR/tool-log.txt"
      ;;
    Task)
      DESC=$(echo "$INPUT" | jq -r '.tool_input.description // ""')
      echo "[$TIMESTAMP] TASK: $DESC" >> "$RALPH_DIR/tool-log.txt"
      ;;
  esac
fi

echo '{"continue": true}'
