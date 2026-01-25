#!/usr/bin/env bash
# Postinstall: just show next step message

set -euo pipefail

# Skip in CI environments
if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  exit 0
fi

# Get the package directory (where agentic-loop is installed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get the project root (go up from node_modules/agentic-loop)
PROJECT_ROOT="$(cd "$PKG_ROOT/../.." && pwd)"

# Don't run in the agentic-loop package itself
if [[ -f "$PROJECT_ROOT/package.json" ]] && grep -q '"name": "agentic-loop"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  exit 0
fi

# Just show the next step
echo "" >&2
echo "  ✨ agentic-loop installed!" >&2
echo "" >&2
echo "  Run setup:" >&2
echo "    npx agentic-loop setup" >&2
echo "" >&2
