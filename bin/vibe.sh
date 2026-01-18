#!/usr/bin/env bash
# vibe - Quick reference for vibe-and-thrive

set -euo pipefail

# Colors
BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

show_help() {
  cat <<EOF

${BOLD}vibe-and-thrive${NC} ${DIM}— Quick Reference${NC}

${CYAN}The Loop${NC}
  /idea "feature"          Brainstorm → PRD
  ralph run                Autonomous coding, commits when done
  ralph status             Check progress
  /vibe-check              Audit before shipping

${CYAN}Other Commands${NC} ${DIM}(in Claude Code)${NC}
  /vibe-help               This cheatsheet (more detail)
  /tour                    Interactive walkthrough
  /review                  Code review with security checks
  /explain                 Explain code line by line
  /styleguide              Generate design system reference

${CYAN}Ralph${NC} ${DIM}(in terminal)${NC}
  ralph run                Execute stories autonomously
  ralph run --max 10       Limit iterations
  ralph status             Show progress
  ralph check              Run verification only
  ralph signs              List learned patterns
  ralph sign "pattern"     Teach Ralph a pattern

${CYAN}Setup${NC}
  npm install vibe-and-thrive

${DIM}https://github.com/allthriveai/vibe-and-thrive${NC}

EOF
}

case "${1:-help}" in
  help|-h|--help|"")
    show_help
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run 'vibe help' for usage"
    exit 1
    ;;
esac
