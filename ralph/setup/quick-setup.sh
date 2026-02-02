#!/usr/bin/env bash
# Path 1: Quick Setup for experienced users

# Get script directory
WIZARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIBE_ROOT="$(cd "$WIZARD_DIR/../.." && pwd)"

quick_setup() {
  clear
  source "$WIZARD_DIR/ui.sh"
  show_logo

  # Detect project
  local project_type
  project_type=$(detect_project_type)
  echo -e "  Detected: ${GREEN}$project_type${NC} project\n"

  # Show what will be installed
  echo -e "  ${BOLD}This will set up:${NC}"
  echo -e "    ${CYAN}•${NC} Claude Code skills (11 slash commands)"
  echo -e "    ${CYAN}•${NC} Pre-commit hooks (security + quality)"
  echo -e "    ${CYAN}•${NC} Ralph autonomous loop"
  echo -e "    ${CYAN}•${NC} vibe-check CLI"
  echo ""

  # Non-interactive mode: skip prompts (CI, Claude Code, piped input)
  if [[ ! -t 0 ]] || [[ -n "${CI:-}" ]] || [[ -n "${CLAUDE_CODE:-}" ]]; then
    echo -e "  ${DIM}(Non-interactive mode detected, auto-installing...)${NC}"
    echo ""
    do_install
    show_completion
    return
  fi

  # Ask how they want to proceed
  echo -e "  ${BOLD}How would you like to proceed?${NC}"
  echo ""
  echo -e "  ${GREEN}[1]${NC} ${EMOJI_ROCKET} ${BOLD}Quick install${NC}"
  echo -e "      ${DIM}Install everything now, explore later${NC}"
  echo ""
  echo -e "  ${GREEN}[2]${NC} ${EMOJI_MOVIE} ${BOLD}Take a tour${NC}"
  echo -e "      ${DIM}Walk through each feature with Claude${NC}"
  echo ""

  local choice
  while true; do
    echo -ne "  Press ${GREEN}1${NC} or ${GREEN}2${NC} (or ${DIM}q${NC} to quit): "
    read -r -n 1 choice
    echo ""
    case "$choice" in
      1)
        echo ""
        do_install
        show_completion
        return
        ;;
      2)
        echo ""
        echo -e "  ${CYAN}Great!${NC} After setup, run ${BOLD}/tour${NC} in Claude Code"
        echo -e "  ${DIM}for an interactive walkthrough of all features.${NC}"
        echo ""
        sleep 2
        do_install
        show_completion_with_tour
        return
        ;;
      q|Q)
        echo -e "\n  ${DIM}Setup cancelled. Run 'npx agentic-loop' anytime.${NC}"
        return 1
        ;;
      *)
        echo -e "  ${RED}Invalid choice${NC}"
        ;;
    esac
  done
}

do_install() {
  install_claude_skills
  install_precommit_hooks
  install_ralph
  configure_mcp
}

show_completion_with_tour() {
  echo ""
  echo -e "  ${GREEN}┌─────────────────────────────────┐${NC}"
  echo -e "  ${GREEN}│       Setup complete! ${EMOJI_PARTY}        │${NC}"
  echo -e "  ${GREEN}└─────────────────────────────────┘${NC}"
  echo ""
  echo -e "  ${BOLD}Next step:${NC} Open Claude Code and run:"
  echo ""
  echo -e "    ${CYAN}/tour${NC}"
  echo ""
  echo -e "  ${DIM}This will walk you through all the features.${NC}"
  echo ""
}

detect_project_type() {
  # Django + React (AllThrive pattern)
  [[ -d "frontend" && -d "core" ]] && echo "django-react" && return
  # Django alone
  [[ -f "manage.py" ]] && echo "django" && return
  # Rust
  [[ -f "Cargo.toml" ]] && echo "rust" && return
  # Go
  [[ -f "go.mod" ]] && echo "go" && return
  # Python
  [[ -f "pyproject.toml" || -f "requirements.txt" ]] && echo "python" && return
  # Node/TypeScript
  [[ -f "package.json" ]] && echo "node" && return
  # Minimal/unknown
  echo "minimal"
}

install_claude_skills() {
  echo -e "  ${CYAN}Installing Claude skills...${NC}"

  # New skills format (.claude/skills/<name>/SKILL.md)
  if [[ -d "$VIBE_ROOT/.claude/skills" ]]; then
    mkdir -p .claude/skills
    cp -r "$VIBE_ROOT/.claude/skills/"* .claude/skills/ 2>/dev/null || true
    local count=$(ls -d .claude/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    ${GREEN}${EMOJI_CHECK}${NC} $count slash commands installed"
  # Fallback to legacy commands format
  elif [[ -d "$VIBE_ROOT/.claude/commands" ]]; then
    mkdir -p .claude/commands
    cp -r "$VIBE_ROOT/.claude/commands/"* .claude/commands/ 2>/dev/null || true
    local count=$(ls -1 .claude/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    ${GREEN}${EMOJI_CHECK}${NC} $count slash commands installed"
  else
    echo -e "    ${YELLOW}${EMOJI_WARN}${NC} No skill templates found"
  fi
}

install_precommit_hooks() {
  echo -e "  ${CYAN}Setting up pre-commit hooks...${NC}"

  if [[ ! -f .pre-commit-config.yaml ]]; then
    cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: https://github.com/allierays/agentic-loop
    rev: v1.0.0
    hooks:
      - id: check-secrets
        name: Check for hardcoded secrets
      - id: check-hardcoded-urls
        name: Check for hardcoded URLs
      - id: vibe-check-quality
        name: AI code quality check
EOF
    echo -e "    ${GREEN}${EMOJI_CHECK}${NC} Created .pre-commit-config.yaml"
  else
    echo -e "    ${DIM}Skipped: .pre-commit-config.yaml already exists${NC}"
  fi

  if command -v pre-commit &>/dev/null; then
    if [[ -d ".git" ]]; then
      pre-commit install > /dev/null 2>&1
      echo -e "    ${GREEN}${EMOJI_CHECK}${NC} Hooks installed"
    else
      echo -e "    ${YELLOW}${EMOJI_WARN}${NC} Not a git repo, run 'pre-commit install' after git init"
    fi
  else
    echo -e "    ${YELLOW}${EMOJI_WARN}${NC} pre-commit not found"
    echo -e "        Run: ${CYAN}pip install pre-commit && pre-commit install${NC}"
  fi
}

install_ralph() {
  echo -e "  ${CYAN}Initializing Ralph...${NC}"

  # Delegate to ralph init via the CLI
  if [[ -f "$VIBE_ROOT/bin/ralph.sh" ]]; then
    # Only init if not already initialized
    if [[ ! -d ".ralph" ]]; then
      if "$VIBE_ROOT/bin/ralph.sh" init > /dev/null 2>&1; then
        echo -e "    ${GREEN}${EMOJI_CHECK}${NC} Ralph initialized"
      else
        echo -e "    ${YELLOW}${EMOJI_WARN}${NC} Ralph init failed (you can run 'ralph init' later)"
      fi
    else
      echo -e "    ${DIM}Skipped: Ralph already initialized${NC}"
    fi
  else
    echo -e "    ${YELLOW}${EMOJI_WARN}${NC} Ralph not available in this installation"
  fi
}

configure_mcp() {
  echo -e "  ${CYAN}Configuring MCP servers...${NC}"

  local claude_json="$HOME/.claude.json"

  # Check for jq
  if ! command -v jq &>/dev/null; then
    echo -e "    ${YELLOW}${EMOJI_WARN}${NC} jq not found, skipping MCP config"
    echo -e "        Install: ${CYAN}brew install jq${NC} or ${CYAN}apt install jq${NC}"
    return
  fi

  # Create claude.json if it doesn't exist
  [[ ! -f "$claude_json" ]] && echo '{}' > "$claude_json"

  local added_any=false

  # Add Playwright MCP if not configured (uses chromium + headless to avoid Chrome conflicts)
  if ! jq -e '.mcpServers["playwright"]' "$claude_json" > /dev/null 2>&1; then
    local tmp=$(mktemp)
    jq '.mcpServers["playwright"] = {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--browser", "chromium", "--headless"]
    }' "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
    echo -e "    ${GREEN}${EMOJI_CHECK}${NC} Playwright MCP configured"
    added_any=true
  else
    echo -e "    ${DIM}Skipped: Playwright MCP already configured${NC}"
  fi

  # Add Chrome DevTools MCP if not configured
  if ! jq -e '.mcpServers["chrome-devtools"]' "$claude_json" > /dev/null 2>&1; then
    local tmp=$(mktemp)
    jq '.mcpServers["chrome-devtools"] = {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools@0.0.5"]
    }' "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
    echo -e "    ${GREEN}${EMOJI_CHECK}${NC} Chrome DevTools MCP configured"
    added_any=true
  else
    echo -e "    ${DIM}Skipped: Chrome DevTools MCP already configured${NC}"
  fi
}

show_completion() {
  echo ""
  echo -e "  ${GREEN}┌─────────────────────────────────┐${NC}"
  echo -e "  ${GREEN}│       Setup complete! ${EMOJI_PARTY}        │${NC}"
  echo -e "  ${GREEN}└─────────────────────────────────┘${NC}"
  echo ""
  echo -e "  ${BOLD}Try these commands:${NC}"
  echo ""
  echo -e "    ${CYAN}vibe-check .${NC}          Scan your code for issues"
  echo -e "    ${CYAN}ralph prd \"idea\"${NC}     Start autonomous development"
  echo -e "    ${CYAN}ralph check${NC}           Run all quality checks"
  echo ""
  echo -e "  ${BOLD}In Claude Code:${NC}"
  echo ""
  echo -e "    ${CYAN}/help${NC}                 See available commands"
  echo -e "    ${CYAN}/prd${NC}                  Generate requirements"
  echo -e "    ${CYAN}/review${NC}               Code review changes"
  echo ""
}

# If sourced, export functions; if run directly, execute quick_setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  quick_setup
fi
