#!/usr/bin/env bash
# ralph-setup.sh - Set up ralph in a project
#
# Detects project type and adds convenience commands to Makefile or package.json

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}Error: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# Get script directory
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
RALPH_TEMPLATES="$SCRIPT_DIR/../templates"

cwd=$(pwd)

echo ""
print_info "ralph-setup: Setting up ralph in your project"
echo ""

# Check what kind of project this is
has_makefile=false
has_package_json=false
has_ralph=false

[[ -f "$cwd/Makefile" ]] && has_makefile=true
[[ -f "$cwd/package.json" ]] && has_package_json=true
[[ -d "$cwd/.ralph" ]] && has_ralph=true

# Detect project type
detect_project_type() {
  local project_type="minimal"

  if [[ -d "frontend" && -d "core" ]]; then
    project_type="django-react"
  elif [[ -d "frontend" && -d "backend" ]]; then
    project_type="monorepo"
  elif [[ -f "Cargo.toml" ]]; then
    project_type="rust"
  elif [[ -f "go.mod" ]]; then
    project_type="go"
  elif [[ -f "pyproject.toml" || -f "requirements.txt" ]]; then
    project_type="python"
  elif [[ -f "package.json" ]]; then
    project_type="node"
  fi

  echo "$project_type"
}

project_type=$(detect_project_type)

echo "Project type: $project_type"
echo "Makefile:     $has_makefile"
echo "package.json: $has_package_json"
echo "Ralph init:   $has_ralph"
echo ""

# Find ralph binary path
ralph_bin="npx ralph"
possible_paths=(
  "node_modules/.bin/ralph"
  "frontend/node_modules/.bin/ralph"
  "client/node_modules/.bin/ralph"
)

for p in "${possible_paths[@]}"; do
  if [[ -f "$cwd/$p" ]]; then
    ralph_bin="./$p"
    break
  fi
done

echo "Ralph binary: $ralph_bin"
echo ""

# Add to Makefile if present
if $has_makefile; then
  makefile_path="$cwd/Makefile"
  if grep -q 'ralph:' "$makefile_path" 2>/dev/null || grep -q 'ralph-' "$makefile_path" 2>/dev/null; then
    print_warning "Makefile already has ralph commands, skipping."
  else
    cat >> "$makefile_path" <<EOF

# =============================================================================
# Ralph - Autonomous AI Development Loop
# =============================================================================

RALPH := $ralph_bin

.PHONY: ralph ralph-init ralph-status ralph-run ralph-check ralph-prd

ralph: ralph-status ## Show ralph status

ralph-init: ## Initialize ralph in this project
	\$(RALPH) init

ralph-status: ## Show current feature, stories, progress
	\$(RALPH) status

ralph-prd: ## Generate PRD interactively: make ralph-prd NOTES="your feature"
	\$(RALPH) prd "\$(NOTES)"

ralph-run: ## Run autonomous loop until all stories pass
	\$(RALPH) run

ralph-check: ## Run verification checks only
	\$(RALPH) check

ralph-signs: ## Show all learned patterns
	\$(RALPH) signs
EOF
    print_success "Added ralph commands to Makefile"
  fi
fi

# Add npm scripts if package.json is at root (and no Makefile)
if $has_package_json && ! $has_makefile; then
  pkg_path="$cwd/package.json"

  if grep -q '"ralph"' "$pkg_path" 2>/dev/null; then
    print_warning "package.json already has ralph scripts, skipping."
  else
    # Use a temp file for safe JSON manipulation
    if command -v jq &>/dev/null; then
      tmpfile=$(mktemp)
      jq '.scripts += {
        "ralph": "ralph status",
        "ralph:init": "ralph init",
        "ralph:prd": "ralph prd",
        "ralph:run": "ralph run",
        "ralph:check": "ralph check",
        "ralph:signs": "ralph signs"
      }' "$pkg_path" > "$tmpfile" && mv "$tmpfile" "$pkg_path"
      print_success "Added ralph scripts to package.json"
    else
      print_warning "jq not found, skipping package.json update"
      echo "Install jq to enable: brew install jq"
    fi
  fi
fi

# Initialize ralph if not already done
if ! $has_ralph; then
  echo ""
  print_info "Initializing ralph..."

  # Create .ralph directory
  mkdir -p "$cwd/.ralph/archive" "$cwd/.ralph/screenshots"

  # Copy appropriate config template
  config_template="$RALPH_TEMPLATES/config/${project_type}.json"
  if [[ -f "$config_template" ]]; then
    cp "$config_template" "$cwd/.ralph/config.json"
  else
    cp "$RALPH_TEMPLATES/config/minimal.json" "$cwd/.ralph/config.json"
  fi

  # Create empty signs
  echo '{"signs": []}' > "$cwd/.ralph/signs.json"

  # Create progress log
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  echo "[$timestamp] INIT Ralph initialized via ralph-setup" > "$cwd/.ralph/progress.txt"

  # Copy PROMPT.md if it doesn't exist
  if [[ ! -f "$cwd/PROMPT.md" ]]; then
    cp "$RALPH_TEMPLATES/PROMPT.md" "$cwd/PROMPT.md"
    echo "Created PROMPT.md"
  fi

  print_success "Ralph initialized!"
fi

echo ""
print_success "Setup complete!"
echo ""
echo "Next steps:"
if $has_makefile; then
  echo "  1. Generate PRD: make ralph-prd NOTES='your feature description'"
  echo "  2. Start loop:   make ralph-run"
  echo "  3. Check status: make ralph-status"
else
  echo "  1. Generate PRD: npx ralph prd 'your feature description'"
  echo "  2. Start loop:   npx ralph run"
  echo "  3. Check status: npx ralph status"
fi
echo ""
echo "Documentation: https://github.com/allthriveai/vibe-and-thrive#ralph"
