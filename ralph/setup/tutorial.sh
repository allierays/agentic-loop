#!/usr/bin/env bash
# Path 3: New to Claude Code tutorial

# Get script directory
WIZARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tutorial() {
  source "$WIZARD_DIR/ui.sh"
  source "$WIZARD_DIR/quick-setup.sh"

  clear
  show_logo
  echo -e "  ${BOLD}${EMOJI_BOOK} Welcome to Claude Code!${NC}\n"
  echo -e "  ${DIM}This tutorial will teach you the basics.${NC}"
  echo -e "  ${DIM}Press 's' at any time to skip to setup.${NC}\n"

  press_enter || { quick_setup; return; }

  # Lesson 1: What is Claude Code
  lesson_what_is_claude
  press_enter || { quick_setup; return; }

  # Lesson 2: Slash commands
  lesson_slash_commands
  press_enter || { quick_setup; return; }

  # Lesson 3: MCP servers
  lesson_mcp
  press_enter || { quick_setup; return; }

  # Lesson 4: agentic-loop integration
  lesson_integration
  press_enter || { quick_setup; return; }

  # Complete - offer setup
  echo ""
  echo -e "  ${GREEN}${EMOJI_PARTY} Tutorial complete!${NC}\n"
  echo -e "  You now know the basics of Claude Code."
  echo -e "  Let's set up agentic-loop for your project.\n"

  quick_setup
}

lesson_what_is_claude() {
  clear
  show_logo
  show_step 1 4 "What is Claude Code?"

  echo -e "  Claude Code is ${BOLD}Anthropic's official CLI${NC} for Claude AI."
  echo ""
  echo -e "  It's an AI coding assistant that can:"
  echo ""
  echo -e "    ${CYAN}•${NC} Read and understand your entire codebase"
  echo -e "    ${CYAN}•${NC} Write and edit code across multiple files"
  echo -e "    ${CYAN}•${NC} Run terminal commands (with your permission)"
  echo -e "    ${CYAN}•${NC} Browse the web for documentation"
  echo -e "    ${CYAN}•${NC} Use tools via MCP (Model Context Protocol)"
  echo ""
  echo -e "  ${BOLD}How to use it:${NC}"
  echo ""
  echo -e "    ${DIM}\$ claude${NC}"
  echo -e "    ${CYAN}Claude:${NC} How can I help you today?"
  echo ""
  echo -e "    ${DIM}\$ claude \"explain this function\"${NC}"
  echo -e "    ${CYAN}Claude:${NC} This function does..."
  echo ""
  echo -e "  ${DIM}Try it: Open a new terminal and type 'claude'${NC}"
}

lesson_slash_commands() {
  clear
  show_logo
  show_step 2 4 "Slash Commands"

  echo -e "  Slash commands are ${BOLD}shortcuts for common tasks${NC}."
  echo ""
  echo -e "  ${BOLD}Built-in commands:${NC}"
  echo ""
  echo -e "    ${CYAN}/help${NC}      Show all available commands"
  echo -e "    ${CYAN}/clear${NC}     Clear conversation history"
  echo -e "    ${CYAN}/compact${NC}   Summarize context to save tokens"
  echo -e "    ${CYAN}/cost${NC}      Show token usage and cost"
  echo ""
  echo -e "  ${BOLD}Custom commands${NC} (from ${DIM}.claude/commands/${NC}):"
  echo ""
  echo -e "    ${CYAN}/idea${NC}      Brainstorm → PRD → Ready for Ralph"
  echo -e "    ${CYAN}/vibe-check${NC} Code quality audit"
  echo -e "    ${CYAN}/review${NC}    Code review with security checks"
  echo ""
  echo -e "  Custom commands are markdown files with prompts."
  echo -e "  agentic-loop installs 7 pre-built commands."
  echo ""
  echo -e "  ${DIM}Try it: In Claude Code, type '/vibe-help' for the cheatsheet${NC}"
}

lesson_mcp() {
  clear
  show_logo
  show_step 3 4 "MCP Servers (Tools)"

  echo -e "  ${BOLD}MCP${NC} = Model Context Protocol"
  echo ""
  echo -e "  MCP lets Claude use ${BOLD}external tools${NC}."
  echo ""
  echo -e "  ${BOLD}Example: Chrome DevTools MCP${NC}"
  echo ""
  echo -e "    ${CYAN}•${NC} Navigate to URLs in a browser"
  echo -e "    ${CYAN}•${NC} Take screenshots of pages"
  echo -e "    ${CYAN}•${NC} Inspect page elements"
  echo -e "    ${CYAN}•${NC} Check console for errors"
  echo ""
  echo -e "  This means Claude can ${BOLD}verify your UI changes${NC}"
  echo -e "  actually work in a real browser."
  echo ""
  echo -e "  ${BOLD}Config location:${NC} ${DIM}~/.claude.json${NC}"
  echo ""
  cat << 'EOF'
  {
    "mcpServers": {
      "chrome-devtools": {
        "command": "npx",
        "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools"]
      }
    }
  }
EOF
  echo ""
  echo -e "  ${DIM}agentic-loop configures this automatically.${NC}"
}

lesson_integration() {
  clear
  show_logo
  show_step 4 4 "agentic-loop Integration"

  echo -e "  ${BOLD}agentic-loop${NC} adds superpowers to Claude Code:"
  echo ""
  echo -e "  ${BOLD}1. The Workflow (/idea → Ralph → Ship)${NC}"
  echo -e "     ${DIM}Brainstorm ideas, generate PRDs, execute autonomously${NC}"
  echo ""
  echo -e "  ${BOLD}2. Code Quality (/vibe-check)${NC}"
  echo -e "     ${DIM}Catches AI-generated code issues before commit${NC}"
  echo ""
  echo -e "  ${BOLD}3. Pre-commit Hooks${NC}"
  echo -e "     ${DIM}Automatically blocks problematic commits${NC}"
  echo ""
  echo -e "  ${BOLD}4. Slash Commands (7 included)${NC}"
  echo -e "     ${DIM}/idea, /vibe-help, /tour, /vibe-check, /review, /explain, /styleguide${NC}"
  echo ""
  echo -e "  ${BOLD}5. MCP Configuration${NC}"
  echo -e "     ${DIM}Chrome DevTools for visual verification${NC}"
  echo ""
  echo -e "  ${DIM}All of this installs with: npm install agentic-loop${NC}"
}

# If run directly, execute tutorial
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  tutorial
fi
