#!/usr/bin/env bash
# Path 2: Feature Tour (auto-demo) with skip options

# Get script directory
WIZARD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

feature_tour() {
  source "$WIZARD_DIR/ui.sh"
  source "$WIZARD_DIR/quick-setup.sh"

  clear
  show_logo
  echo -e "  ${BOLD}${EMOJI_MOVIE} Feature Tour${NC}\n"
  echo -e "  ${DIM}Watch what thrivekit can do for your codebase.${NC}"
  echo -e "  ${DIM}Press 's' anytime to skip to setup.${NC}\n"
  sleep 1

  # Demo 1: vibe-check
  demo_vibe_check
  press_enter || { quick_setup; return; }

  # Demo 2: Pre-commit hooks
  demo_precommit
  press_enter || { quick_setup; return; }

  # Demo 3: Ralph autonomous loop
  demo_ralph
  press_enter || { quick_setup; return; }

  # Demo 4: Claude Code skills
  demo_skills
  press_enter || { quick_setup; return; }

  # Offer to install
  echo ""
  echo -e "  ${BOLD}That's the tour! Ready to set up your project?${NC}\n"

  if confirm "Install thrivekit?"; then
    quick_setup
  else
    echo -e "\n  ${DIM}No problem! Run 'npx thrivekit' anytime to set up.${NC}"
  fi
}

demo_vibe_check() {
  show_step 1 4 "vibe-check: Catch AI code issues"

  echo -e "  ${DIM}$ vibe-check src/example.ts${NC}\n"
  sleep 0.5

  # Simulated output with typewriter effect
  typewrite "  Scanning 1 file..." 0.03
  sleep 0.3
  echo ""

  # Error
  echo -e "  ${RED}${EMOJI_CROSS}${NC} ${BOLD}src/example.ts:15${NC}"
  echo -e "    ${RED}[error]${NC} Hardcoded API URL detected"
  echo -e "    ${DIM}const url = \"https://api.example.com/users\"${NC}"
  sleep 0.2
  echo ""

  # Warnings
  echo -e "  ${YELLOW}${EMOJI_WARN}${NC} ${BOLD}src/example.ts:23${NC}"
  echo -e "    ${YELLOW}[warn]${NC} Function too long (85 lines, max 50)"
  sleep 0.2
  echo ""

  echo -e "  ${YELLOW}${EMOJI_WARN}${NC} ${BOLD}src/example.ts:42${NC}"
  echo -e "    ${YELLOW}[warn]${NC} Using 'any' type"
  sleep 0.2
  echo ""

  echo -e "  Found ${RED}1 error${NC}, ${YELLOW}2 warnings${NC}"
  echo ""
  echo -e "  ${DIM}vibe-check catches common AI-generated code issues:${NC}"
  echo -e "  ${DIM}- Hardcoded secrets and URLs${NC}"
  echo -e "  ${DIM}- Overly complex functions${NC}"
  echo -e "  ${DIM}- Missing error handling${NC}"
  echo -e "  ${DIM}- TypeScript type issues${NC}"
}

demo_precommit() {
  show_step 2 4 "Pre-commit hooks: Block bad commits"

  echo -e "  ${DIM}$ git commit -m \"add feature\"${NC}\n"
  sleep 0.5

  echo -e "  ${GREEN}${EMOJI_CHECK}${NC} check-secrets............${GREEN}passed${NC}"
  sleep 0.2
  echo -e "  ${RED}${EMOJI_CROSS}${NC} check-hardcoded-urls.....${RED}FAILED${NC}"
  sleep 0.3
  echo ""
  echo -e "  ${RED}Commit blocked!${NC} Fix the issue first."
  echo ""
  echo -e "  ${DIM}Pre-commit hooks automatically run before each commit:${NC}"
  echo -e "  ${DIM}- Scans for hardcoded secrets (API keys, passwords)${NC}"
  echo -e "  ${DIM}- Detects hardcoded URLs that should be config${NC}"
  echo -e "  ${DIM}- Runs vibe-check quality scan${NC}"
  echo ""
  echo -e "  ${DIM}Bad code never makes it into your repo.${NC}"
}

demo_ralph() {
  show_step 3 4 "Ralph: Autonomous development loop"

  echo -e "  ${DIM}$ ralph prd \"Add user authentication\"${NC}\n"
  sleep 0.5

  echo -e "  ${CYAN}Claude:${NC} I have a few questions about this feature:"
  sleep 0.2
  echo -e "    1. What auth method? (OAuth, JWT, session-based)"
  echo -e "    2. Need password reset flow?"
  echo -e "    3. Any rate limiting requirements?"
  echo -e "    4. Should failed logins be logged?"
  echo ""
  sleep 0.3

  echo -e "  ${DIM}After you answer, Ralph:${NC}"
  echo -e "    1. Generates detailed user stories"
  echo -e "    2. Creates testable acceptance criteria"
  echo -e "    3. Runs in a loop until ALL tests pass"
  echo -e "    4. Commits working code automatically"
  echo ""
  echo -e "  ${DIM}You describe what you want. Ralph builds it.${NC}"
}

demo_skills() {
  show_step 4 4 "Claude Code commands"

  echo -e "  ${BOLD}In Claude Code, type these commands:${NC}\n"

  echo -e "  ${CYAN}/idea${NC}            Brainstorm → PRD → Ready for Ralph"
  sleep 0.1
  echo -e "  ${CYAN}/vibe-help${NC}       Quick reference cheatsheet"
  sleep 0.1
  echo -e "  ${CYAN}/tour${NC}            Interactive walkthrough"
  sleep 0.1
  echo -e "  ${CYAN}/vibe-check${NC}      Full code quality audit"
  sleep 0.1
  echo -e "  ${CYAN}/review${NC}          Code review with security checks"
  sleep 0.1
  echo -e "  ${CYAN}/explain${NC}         Explain code line by line"
  sleep 0.1
  echo -e "  ${CYAN}/styleguide${NC}      Generate design system reference"
  echo ""

  echo -e "  ${DIM}These commands guide Claude through${NC}"
  echo -e "  ${DIM}the thrivekit workflow.${NC}"
}

# If run directly, execute feature_tour
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  feature_tour
fi
