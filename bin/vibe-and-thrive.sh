#!/usr/bin/env bash
# Main entry point - runs when user types: npx vibe-and-thrive

set -euo pipefail

# Get script directory (handles symlinks from npm)
get_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [ -L "$source" ]; do
    local dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

SCRIPT_DIR="$(get_script_dir)"
LIB_DIR="$SCRIPT_DIR/../ralph/setup"

# Source UI utilities
source "$LIB_DIR/ui.sh"

# Parse arguments
show_help() {
  echo "vibe-and-thrive - Tools to help you thrive with agentic coding"
  echo ""
  echo "Usage: vibe-and-thrive [command]"
  echo ""
  echo "Commands:"
  echo "  (no args)    Interactive setup wizard"
  echo "  --quick      Quick setup (skip intro)"
  echo "  --tour       Feature tour"
  echo "  --tutorial   Claude Code tutorial"
  echo "  --help       Show this help"
  echo ""
  echo "Examples:"
  echo "  npx vibe-and-thrive           # Interactive wizard"
  echo "  npx vibe-and-thrive --quick   # Fast setup"
}

main() {
  # Handle arguments
  case "${1:-}" in
    --help|-h)
      show_help
      exit 0
      ;;
    --quick|-q)
      source "$LIB_DIR/quick-setup.sh"
      quick_setup
      exit 0
      ;;
    --tour|-t)
      source "$LIB_DIR/feature-tour.sh"
      feature_tour
      exit 0
      ;;
    --tutorial|-T)
      source "$LIB_DIR/tutorial.sh"
      tutorial
      exit 0
      ;;
    "")
      # Interactive mode - show menu
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac

  # Interactive wizard
  clear
  show_logo
  show_welcome

  local choice
  choice=$(prompt_menu)

  case "$choice" in
    1)
      source "$LIB_DIR/quick-setup.sh"
      quick_setup
      ;;
    2)
      source "$LIB_DIR/feature-tour.sh"
      feature_tour
      ;;
    3)
      source "$LIB_DIR/tutorial.sh"
      tutorial
      ;;
    q|Q)
      echo ""
      echo -e "  ${DIM}Goodbye! Run 'npx vibe-and-thrive' anytime.${NC}"
      echo ""
      exit 0
      ;;
  esac
}

main "$@"
