#!/usr/bin/env bash
# shellcheck shell=bash
# thrivekit - Tools to thrive with agentic coding
#
# Main CLI - wraps ralph.sh for the autonomous dev loop.

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
