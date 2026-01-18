#!/usr/bin/env bash
# ralph.sh - Autonomous AI Development Loop
#
# A CLI tool that orchestrates Claude CLI for autonomous development loops.
# Part of vibe-and-thrive: https://github.com/allthriveai/vibe-and-thrive

set -euo pipefail

# Get the directory where ralph.sh is installed (works even via symlink)
get_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "$source" ]]; do
    local dir
    dir=$(cd -P "$(dirname "$source")" && pwd)
    source=$(readlink "$source")
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

SCRIPT_DIR="$(get_script_dir)"
RALPH_LIB="$SCRIPT_DIR/../lib/ralph"
RALPH_TEMPLATES="$SCRIPT_DIR/../templates"

# Project-local directories (can be overridden by environment)
RALPH_DIR="${RALPH_DIR:-.ralph}"
PROMPT_FILE="${PROMPT_FILE:-PROMPT.md}"

# Export for use in sourced files
export RALPH_DIR PROMPT_FILE RALPH_LIB RALPH_TEMPLATES

# Source function libraries
source "$RALPH_LIB/utils.sh"
source "$RALPH_LIB/init.sh"
source "$RALPH_LIB/loop.sh"
source "$RALPH_LIB/verify.sh"
source "$RALPH_LIB/prd.sh"
source "$RALPH_LIB/signs.sh"

# Main entry point
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    init)
      ralph_init "$@"
      ;;
    prd)
      ralph_prd "$@"
      ;;
    run)
      run_loop "$@"
      ;;
    status)
      ralph_status "$@"
      ;;
    check)
      ralph_check "$@"
      ;;
    verify)
      if [[ $# -lt 1 ]]; then
        print_error "Usage: ralph verify <story-id>"
        exit 1
      fi
      run_verification "$1"
      ;;
    sign)
      ralph_sign "$@"
      ;;
    signs)
      ralph_signs "$@"
      ;;
    unsign)
      ralph_unsign "$@"
      ;;
    progress)
      if [[ -f "$RALPH_DIR/progress.txt" ]]; then
        tail -50 "$RALPH_DIR/progress.txt"
      else
        echo "No progress log found. Run 'ralph init' first."
      fi
      ;;
    help|-h|--help)
      ralph_help
      ;;
    version|-v|--version)
      echo "ralph 2.0.0 (bash)"
      echo "Part of vibe-and-thrive"
      ;;
    *)
      print_error "Unknown command: $cmd"
      echo ""
      ralph_help
      exit 1
      ;;
  esac
}

# Run main
main "$@"
