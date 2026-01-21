#!/usr/bin/env bash
# install.sh - Install Ralph hooks into Claude Code settings
#
# Usage: ./install.sh [--global]
#   --global: Install to ~/.claude/settings.json (applies to all projects)
#   Default: Install to .claude/settings.json (project-level)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIBE_PATH="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Parse args
SETTINGS_FILE=".claude/settings.json"
if [[ "${1:-}" == "--global" ]]; then
  SETTINGS_FILE="$HOME/.claude/settings.json"
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Installing Ralph hooks..."
echo "  Hooks path: $SCRIPT_DIR"
echo "  Settings: $SETTINGS_FILE"
echo ""

# Ensure settings directory exists
mkdir -p "$(dirname "$SETTINGS_FILE")"

# Create settings file if it doesn't exist
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
fi

# Build hooks config with actual path
HOOKS_CONFIG=$(cat <<EOF
{
  "PreToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {
          "type": "command",
          "command": "$SCRIPT_DIR/protect-prd.sh",
          "timeout": 5
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {
          "type": "command",
          "command": "$SCRIPT_DIR/warn-debug.sh",
          "timeout": 5
        },
        {
          "type": "command",
          "command": "$SCRIPT_DIR/warn-secrets.sh",
          "timeout": 5
        },
        {
          "type": "command",
          "command": "$SCRIPT_DIR/warn-urls.sh",
          "timeout": 5
        }
      ]
    },
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "$SCRIPT_DIR/log-tools.sh",
          "timeout": 3
        }
      ]
    }
  ],
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$SCRIPT_DIR/inject-context.sh",
          "timeout": 5
        }
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "$SCRIPT_DIR/save-learnings.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
EOF
)

# Merge hooks into settings
CURRENT_SETTINGS=$(cat "$SETTINGS_FILE")
MERGED=$(echo "$CURRENT_SETTINGS" | jq --argjson hooks "$HOOKS_CONFIG" '.hooks = $hooks')

echo "$MERGED" > "$SETTINGS_FILE"

echo -e "${GREEN}✓ Hooks installed successfully!${NC}"
echo ""
echo "Hooks enabled:"
echo "  • protect-prd.sh    - Blocks edits to prd.json"
echo "  • warn-debug.sh     - Warns about console.log/debugger"
echo "  • warn-secrets.sh   - Warns about hardcoded secrets/API keys"
echo "  • warn-urls.sh      - Warns about hardcoded localhost URLs"
echo "  • inject-context.sh - Loads signs & progress at session start"
echo "  • save-learnings.sh - Extracts learnings at session end"
echo "  • log-tools.sh      - Logs tool usage to .ralph/tool-log.txt"
echo ""
echo -e "${YELLOW}Note:${NC} Restart Claude Code for hooks to take effect."
