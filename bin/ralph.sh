#!/usr/bin/env bash
# shellcheck shell=bash
# ralph.sh - Autonomous AI Development Loop
#
# A CLI tool that orchestrates Claude CLI for autonomous development loops.
# Part of agentic-loop: https://github.com/allierays/agentic-loop

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
# Check if config.json needs to be created (but don't create it yet - let init copy the template)
if [[ ! -f ".ralph/config.json" ]]; then
  # Copy config template based on detected project type
  _project_type="minimal"
  if [[ -f "pyproject.toml" ]]; then
    if grep -qE "(fastmcp|\"fastmcp\"|'fastmcp')" pyproject.toml 2>/dev/null; then
      _project_type="fastmcp"
    elif grep -qE "(fastapi|\"fastapi\"|'fastapi')" pyproject.toml 2>/dev/null; then
      _project_type="fastapi"
    elif grep -qE "(django|\"django\"|'django')" pyproject.toml 2>/dev/null || [[ -f "manage.py" ]]; then
      _project_type="django"
    else
      _project_type="python"
    fi
  elif [[ -f "go.mod" ]]; then
    _project_type="go"
  elif [[ -f "Cargo.toml" ]]; then
    _project_type="rust"
  elif [[ -d "frontend" ]] && [[ -d "backend" || -d "core" || -d "apps" ]]; then
    _project_type="fullstack"
  elif [[ -f "package.json" ]]; then
    _project_type="node"
  fi

  # Check user template override first
  _user_template="$HOME/.config/ralph/templates/config/${_project_type}.json"
  _config_template="$RALPH_TEMPLATES/config/${_project_type}.json"

  if [[ -f "$_user_template" ]]; then
    cp "$_user_template" ".ralph/config.json"
    echo "Using user template: $_user_template" >&2
  elif [[ -f "$_config_template" ]]; then
    cp "$_config_template" ".ralph/config.json"
  else
    # Fall back to minimal config if template doesn't exist
    _user_minimal="$HOME/.config/ralph/templates/config/minimal.json"
    _config_template="$RALPH_TEMPLATES/config/minimal.json"
    if [[ -f "$_user_minimal" ]]; then
      cp "$_user_minimal" ".ralph/config.json"
    elif [[ -f "$_config_template" ]]; then
      cp "$_config_template" ".ralph/config.json"
    else
      echo '{"projectType": "unknown"}' > ".ralph/config.json"
    fi
  fi
  unset _project_type _config_template
  # Run auto-detection to fill in project-specific values
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
source "$RALPH_LIB/prd-check.sh"   # PRD validation before loop
source "$RALPH_LIB/code-check.sh"  # Code verification after Claude writes
source "$RALPH_LIB/prd.sh"
source "$RALPH_LIB/signs.sh"
source "$RALPH_LIB/test.sh"
source "$RALPH_LIB/ci.sh"

# Run auto-config if config.json was just created
if [[ "${_ralph_needs_autoconfig:-}" == "true" ]]; then
  echo "Auto-detecting project configuration..." >&2
  auto_configure_project
  unset _ralph_needs_autoconfig
fi

# Merge user config defaults into project config
if [[ -f "$RALPH_DIR/config.json" && -f "$HOME/.config/ralph/config.json" ]]; then
  _merge_user_config
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
    skip)
      # Signal the loop to skip the current story and move to the next one
      mkdir -p "$RALPH_DIR"
      touch "$RALPH_DIR/.skip"
      echo "Skip signal sent. Ralph will skip the current story when Claude finishes."
      ;;
    status)
      ralph_status "$@"
      ;;
    check)
      ralph_check "$@"
      ;;
    prd-check|prdcheck)
      ralph_prd_check "$@"
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
    ci)
      ralph_ci "$@"
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
      ralph_config "$@"
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
