#!/usr/bin/env bash
# install.sh - Install Ralph hooks into Claude Code settings
#
# Usage: ./install.sh [--global] [--force]
#   --global: Install to ~/.claude/settings.json (applies to all projects)
#   --force:  Reinstall even if hooks already configured
#   Default: Install to .claude/settings.json (project-level)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse args
SETTINGS_FILE=".claude/settings.json"
FORCE=false

for arg in "$@"; do
  case $arg in
    --global)
      SETTINGS_FILE="$HOME/.claude/settings.json"
      ;;
    --force)
      FORCE=true
      ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Auto-install jq if missing
install_jq() {
  echo -e "${YELLOW}jq not found, installing...${NC}"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if command -v brew &>/dev/null; then
      brew install jq
    else
      echo -e "${RED}Error: Homebrew not found. Install jq manually:${NC}"
      echo "  brew install jq"
      echo "  Or: https://jqlang.github.io/jq/download/"
      exit 1
    fi
  elif command -v apt-get &>/dev/null; then
    # Debian/Ubuntu
    sudo apt-get update -qq && sudo apt-get install -y jq
  elif command -v dnf &>/dev/null; then
    # Fedora/RHEL 8+
    sudo dnf install -y jq
  elif command -v yum &>/dev/null; then
    # CentOS/RHEL 7
    sudo yum install -y jq
  elif command -v pacman &>/dev/null; then
    # Arch
    sudo pacman -S --noconfirm jq
  elif command -v apk &>/dev/null; then
    # Alpine
    sudo apk add jq
  else
    echo -e "${RED}Error: Could not detect package manager.${NC}"
    echo "Install jq manually: https://jqlang.github.io/jq/download/"
    exit 1
  fi

  echo -e "${GREEN}✓ jq installed${NC}"
}

# Check for jq, install if missing
if ! command -v jq &>/dev/null; then
  install_jq
fi

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

# Check if hooks already configured and valid
if [[ "$FORCE" != "true" ]] && jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
  session_hook=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$SETTINGS_FILE" 2>/dev/null)
  stop_hook=$(jq -r '.hooks.Stop[0].hooks[0].command // empty' "$SETTINGS_FILE" 2>/dev/null)

  # All hooks must exist AND point to current script directory
  if [[ -n "$session_hook" && -x "$session_hook" && -n "$stop_hook" && -x "$stop_hook" ]]; then
    if [[ "$session_hook" == "$SCRIPT_DIR/"* && "$stop_hook" == "$SCRIPT_DIR/"* ]]; then
      echo -e "${YELLOW}Hooks already configured and valid.${NC}"
      echo "Use --force to reinstall."
      exit 0
    else
      echo -e "${YELLOW}Hooks point to different location, updating...${NC}"
      echo ""
    fi
  else
    echo -e "${YELLOW}Existing hooks are invalid, reinstalling...${NC}"
    echo ""
  fi
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
        },
        {
          "type": "command",
          "command": "$SCRIPT_DIR/warn-empty-catch.sh",
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
echo "  • protect-prd.sh      - Blocks edits to prd.json"
echo "  • warn-debug.sh       - Warns about console.log/debugger"
echo "  • warn-secrets.sh     - Warns about hardcoded secrets/API keys"
echo "  • warn-urls.sh        - Warns about hardcoded localhost URLs"
echo "  • warn-empty-catch.sh - Warns about empty catch blocks"
echo "  • inject-context.sh   - Loads signs & progress at session start"
echo "  • save-learnings.sh   - Extracts learnings at session end"
echo "  • log-tools.sh        - Logs tool usage to .ralph/tool-log.txt"
echo ""
echo -e "${YELLOW}Note:${NC} Restart Claude Code for hooks to take effect."
