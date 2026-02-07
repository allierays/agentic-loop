#!/usr/bin/env bash
# shellcheck shell=bash
# agentic-loop - Tools to thrive with agentic coding
#
# Main CLI - wraps ralph.sh for the autonomous dev loop.
#
# Run options:
#   run                     Run autonomous loop until all stories pass
#   run --max <n>           Run with max iterations (default: 20)
#   run --fast              Skip code review for faster iterations
#   run --quiet             Suppress the live activity feed
#   run --story <id>        Run a specific story only

set -euo pipefail

# Get the directory where this script is installed (handles symlinks)
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

# Pass through to ralph.sh
exec "$SCRIPT_DIR/ralph.sh" "$@"
