#!/usr/bin/env bash
# shellcheck shell=bash
# ralph.sh - Autonomous AI Development Loop
#
# A CLI tool that orchestrates Claude CLI for autonomous development loops.
# Part of agentic-loop: https://github.com/allthriveai/agentic-loop

set -euo pipefail

# Handle Ctrl+C - kill all child processes
trap 'echo ""; echo "Interrupted. Stopping..."; kill 0 2>/dev/null; exit 130' INT TERM

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
RALPH_LIB="$SCRIPT_DIR/../ralph"
RALPH_TEMPLATES="$SCRIPT_DIR/../templates"

# Project-local directories (can be overridden by environment)
RALPH_DIR="${RALPH_DIR:-.ralph}"
PROMPT_FILE="${PROMPT_FILE:-PROMPT.md}"

# Export for use in sourced files
export RALPH_DIR PROMPT_FILE RALPH_LIB RALPH_TEMPLATES

# Ensure minimal setup exists (in case postinstall was skipped or global install)
if [[ ! -d ".ralph" ]]; then
  mkdir -p ".ralph/archive" ".ralph/screenshots"
fi
# Always ensure config.json exists and run auto-detection if newly created
if [[ ! -f ".ralph/config.json" ]]; then
  echo '{}' > ".ralph/config.json"
  # Run auto-detection (function is in init.sh, sourced below)
  _ralph_needs_autoconfig=true
fi
[[ ! -f ".ralph/signs.json" ]] && echo '{"signs": []}' > ".ralph/signs.json"
if [[ ! -f "PROMPT.md" ]] && [[ -f "$RALPH_TEMPLATES/PROMPT.md" ]]; then
  cp "$RALPH_TEMPLATES/PROMPT.md" "PROMPT.md"
fi

# Source function libraries
source "$RALPH_LIB/utils.sh"
source "$RALPH_LIB/init.sh"
source "$RALPH_LIB/setup.sh"
source "$RALPH_LIB/loop.sh"
source "$RALPH_LIB/verify.sh"
source "$RALPH_LIB/prd.sh"
source "$RALPH_LIB/signs.sh"
source "$RALPH_LIB/test.sh"

# Run auto-config if config.json was just created
if [[ "${_ralph_needs_autoconfig:-}" == "true" ]]; then
  echo "Auto-detecting project configuration..." >&2
  auto_configure_project
  unset _ralph_needs_autoconfig
fi

# Main entry point
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    setup)
      ralph_setup "$@"
      ;;
    init)
      ralph_init "$@"
      ;;
    prd)
      ralph_prd "$@"
      ;;
    run)
      # Clear any previous stop signal
      rm -f "$RALPH_DIR/.stop"
      run_loop "$@"
      ;;
    stop)
      # Signal the loop to stop after current story
      mkdir -p "$RALPH_DIR"
      touch "$RALPH_DIR/.stop"
      echo "Stop signal sent. Ralph will stop after current story completes."
      echo "(Use Ctrl+C to force stop immediately)"
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
    test)
      ralph_test "$@"
      ;;
    coverage)
      ralph_test_coverage "$@"
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
    notify)
      ralph_notify "$@"
      ;;
    backup)
      source "$RALPH_LIB/backup.sh"
      ralph_backup "$@"
      ;;
    restore)
      source "$RALPH_LIB/backup.sh"
      ralph_restore "$@"
      ;;
    backups)
      source "$RALPH_LIB/backup.sh"
      ralph_list_backups
      ;;
    hooks)
      bash "$RALPH_LIB/hooks/install.sh" "$@"
      ;;
    progress)
      if [[ -f "$RALPH_DIR/progress.txt" ]]; then
        tail -50 "$RALPH_DIR/progress.txt"
      else
        echo "No progress log found. Run 'ralph init' first."
      fi
      ;;
    config)
      if [[ ! -f "$RALPH_DIR/config.json" ]]; then
        print_error "Ralph not initialized. Run 'ralph init' first."
        exit 1
      fi
      echo "Auto-detecting project configuration..."
      auto_configure_project
      echo ""
      echo "Current config:"
      jq '.' "$RALPH_DIR/config.json"
      ;;
    help|-h|--help)
      ralph_help
      ;;
    version|-v|--version)
      # Read version from package.json
      local version
      version=$(jq -r '.version // "unknown"' "$SCRIPT_DIR/../package.json" 2>/dev/null || echo "unknown")
      echo "ralph $version (agentic-loop)"
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
