#!/usr/bin/env bash
# Postinstall: just show next step message

set -euo pipefail

# Skip in CI environments
if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  exit 0
fi

# Get the package directory (where thrivekit is installed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get the project root (go up from node_modules/thrivekit)
PROJECT_ROOT="$(cd "$PKG_ROOT/../.." && pwd)"

# Don't run in the thrivekit package itself
if [[ -f "$PROJECT_ROOT/package.json" ]] && grep -q '"name": "thrivekit"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  exit 0
fi

# Just show the next step
echo "" >&2
echo "  ✨ thrivekit installed!" >&2
echo "" >&2
echo "  Run setup:" >&2
echo "    npx thrivekit setup" >&2
echo "" >&2
