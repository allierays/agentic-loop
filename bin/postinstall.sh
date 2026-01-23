#!/usr/bin/env bash
# Postinstall: silent setup + contextual message

set -euo pipefail

# Skip in CI environments
if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  exit 0
fi

# Get the package directory (where vibe-and-thrive is installed)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get the project root (go up from node_modules/vibe-and-thrive)
# npm runs postinstall from package dir, we need project root
PROJECT_ROOT="$(cd "$PKG_ROOT/../.." && pwd)"

# Verify we're in a valid project (has package.json), not a global install
if [[ ! -f "$PROJECT_ROOT/package.json" ]]; then
  # Might be global install or npm link - skip silently
  exit 0
fi

# Don't run in the vibe-and-thrive package itself
if [[ -f "$PROJECT_ROOT/package.json" ]] && grep -q '"name": "vibe-and-thrive"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
  exit 0
fi

# Change to project root for setup
cd "$PROJECT_ROOT" || exit 0

# Silent setup functions (no output unless error)

install_claude_skills() {
  mkdir -p .claude/commands
  if [[ -d "$PKG_ROOT/.claude/commands" ]]; then
    cp -r "$PKG_ROOT/.claude/commands/"* .claude/commands/ 2>/dev/null || true
  fi
}

install_precommit_hooks() {
  if [[ ! -f .pre-commit-config.yaml ]]; then
    cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: https://github.com/allthriveai/vibe-and-thrive
    rev: v1.0.0
    hooks:
      - id: build
        name: Build check
      - id: check-env-files
        name: Block .env files
      - id: check-secrets
        name: Check for hardcoded secrets
      - id: check-hardcoded-urls
        name: Check for hardcoded URLs
      - id: vibe-check-quality
        name: AI code quality check
EOF
  fi

  # Install hooks if pre-commit is available and we're in a git repo
  if command -v pre-commit &>/dev/null && [[ -d ".git" ]]; then
    pre-commit install > /dev/null 2>&1 || true
  fi
}

install_ralph() {
  # Just create the directory structure - don't run full init
  # Users will run /idea or ralph prd to generate a PRD
  mkdir -p ".ralph/archive" ".ralph/screenshots"

  # Copy config template based on detected project type
  if [[ ! -f ".ralph/config.json" ]]; then
    local config_template=""
    if [[ -f "manage.py" ]] || [[ -f "pyproject.toml" ]]; then
      config_template="$PKG_ROOT/templates/config/python.json"
    elif [[ -d "frontend" ]] && [[ -d "backend" || -d "core" ]]; then
      config_template="$PKG_ROOT/templates/config/fullstack.json"
    elif [[ -f "package.json" ]]; then
      config_template="$PKG_ROOT/templates/config/node.json"
    fi

    if [[ -n "$config_template" ]] && [[ -f "$config_template" ]]; then
      cp "$config_template" ".ralph/config.json"
    else
      # Fall back to minimal config
      echo '{"checks": {"build": true, "lint": true, "test": true}}' > ".ralph/config.json"
    fi
  fi

  # Copy signs template if available, otherwise create empty
  if [[ ! -f ".ralph/signs.json" ]]; then
    if [[ -f "$PKG_ROOT/templates/signs.json" ]]; then
      cp "$PKG_ROOT/templates/signs.json" ".ralph/signs.json"
    else
      echo '{"signs": []}' > ".ralph/signs.json"
    fi
  fi

  # Create PROMPT.md if missing
  if [[ ! -f "PROMPT.md" ]] && [[ -f "$PKG_ROOT/templates/PROMPT.md" ]]; then
    cp "$PKG_ROOT/templates/PROMPT.md" "PROMPT.md"
  fi
}

configure_mcp() {
  local claude_json="$HOME/.claude.json"

  # Skip if jq not available
  command -v jq &>/dev/null || return 0

  # Create claude.json if it doesn't exist
  [[ ! -f "$claude_json" ]] && echo '{}' > "$claude_json"

  # Skip if already configured
  jq -e '.mcpServers["chrome-devtools"]' "$claude_json" > /dev/null 2>&1 && return 0

  # Add Chrome DevTools MCP
  local tmp=$(mktemp)
  jq '.mcpServers["chrome-devtools"] = {
    "command": "npx",
    "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools@0.0.5"]
  }' "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
}

install_jq_if_missing() {
  # Try to install jq automatically
  if [[ "$OSTYPE" == "darwin"* ]] && command -v brew &>/dev/null; then
    # macOS with Homebrew - doesn't need sudo
    echo "  Installing jq via Homebrew..."
    brew install jq >/dev/null 2>&1 && return 0
  fi

  # For other systems, warn instead of using sudo during npm install
  echo "  ⚠️  jq not installed - Claude Code hooks not configured"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "     Run: brew install jq && npx ralph hooks"
  elif command -v apt-get &>/dev/null; then
    echo "     Run: sudo apt install jq && npx ralph hooks"
  else
    echo "     Install jq and run: npx ralph hooks"
  fi
  return 1
}

install_claude_hooks() {
  local settings_file=".claude/settings.json"
  local hooks_dir="$PKG_ROOT/ralph/hooks"

  # Skip if hooks directory doesn't exist
  [[ ! -d "$hooks_dir" ]] && return 0

  # Auto-install jq if missing (or warn if can't auto-install)
  if ! command -v jq &>/dev/null; then
    install_jq_if_missing || return 0
  fi

  # Ensure .claude directory exists
  mkdir -p ".claude"

  # Create settings file if it doesn't exist
  [[ ! -f "$settings_file" ]] && echo '{}' > "$settings_file"

  # Check if hooks are already configured AND valid
  if jq -e '.hooks' "$settings_file" > /dev/null 2>&1; then
    # Get the first hook command path to check if it's valid
    local existing_hook
    existing_hook=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$settings_file" 2>/dev/null)

    if [[ -n "$existing_hook" ]]; then
      if [[ -x "$existing_hook" ]]; then
        # Hooks exist and are valid, skip
        return 0
      else
        # Hooks configured but invalid - reinstall
        echo "  ⚠️  Existing Claude Code hooks are invalid, reinstalling..."
      fi
    fi
  fi

  # Build hooks config
  local hooks_config
  hooks_config=$(cat <<EOF
{
  "PreToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {"type": "command", "command": "$hooks_dir/protect-prd.sh", "timeout": 5}
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {"type": "command", "command": "$hooks_dir/warn-debug.sh", "timeout": 5},
        {"type": "command", "command": "$hooks_dir/warn-secrets.sh", "timeout": 5},
        {"type": "command", "command": "$hooks_dir/warn-urls.sh", "timeout": 5},
        {"type": "command", "command": "$hooks_dir/warn-empty-catch.sh", "timeout": 5}
      ]
    },
    {
      "matcher": "*",
      "hooks": [
        {"type": "command", "command": "$hooks_dir/log-tools.sh", "timeout": 3}
      ]
    }
  ],
  "SessionStart": [
    {
      "hooks": [
        {"type": "command", "command": "$hooks_dir/inject-context.sh", "timeout": 5}
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {"type": "command", "command": "$hooks_dir/save-learnings.sh", "timeout": 10}
      ]
    }
  ]
}
EOF
)

  # Merge hooks into settings
  local tmp=$(mktemp)
  jq --argjson hooks "$hooks_config" '.hooks = $hooks' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
}

generate_claude_md() {
  local runtime="" framework="" language="" styling="" testing="" structure=""
  local marker="<!-- vibe-and-thrive-detected -->"

  # Skip if we already added our section
  [[ -f "CLAUDE.md" ]] && grep -q "$marker" "CLAUDE.md" 2>/dev/null && return 0

  # Detect runtime/language (check root and common monorepo paths)
  local fe_dir=""
  [[ -d "frontend" ]] && fe_dir="frontend"
  [[ -d "client" ]] && fe_dir="client"
  [[ -d "web" ]] && fe_dir="web"

  [[ -f "package.json" || -f "${fe_dir}/package.json" ]] && runtime="Node.js"
  [[ -f "Cargo.toml" ]] && runtime="Rust"
  [[ -f "go.mod" ]] && runtime="Go"
  [[ -f "pyproject.toml" || -f "requirements.txt" || -f "manage.py" ]] && runtime="${runtime:+$runtime + }Python"
  [[ -f "Gemfile" ]] && runtime="Ruby"

  # Detect framework (check root and frontend dir)
  local pkg="package.json"
  [[ -n "$fe_dir" && -f "${fe_dir}/package.json" ]] && pkg="${fe_dir}/package.json"

  if [[ -f "$pkg" ]]; then
    grep -q '"next"' "$pkg" 2>/dev/null && framework="Next.js"
    grep -q '"react"' "$pkg" 2>/dev/null && [[ -z "$framework" ]] && framework="React"
    grep -q '"vue"' "$pkg" 2>/dev/null && framework="Vue"
    grep -q '"svelte"' "$pkg" 2>/dev/null && framework="Svelte"
    grep -q '"express"' "$pkg" 2>/dev/null && framework="${framework:+$framework + }Express"
  fi
  [[ -f "manage.py" ]] && framework="${framework:+$framework + }Django"
  [[ -f "Cargo.toml" ]] && grep -q "actix" Cargo.toml 2>/dev/null && framework="Actix"
  [[ -f "Cargo.toml" ]] && grep -q "axum" Cargo.toml 2>/dev/null && framework="Axum"

  # Detect TypeScript
  [[ -f "tsconfig.json" || -f "${fe_dir}/tsconfig.json" ]] && language="TypeScript"

  # Detect styling
  [[ -f "tailwind.config.js" || -f "tailwind.config.ts" || -f "${fe_dir}/tailwind.config.js" || -f "${fe_dir}/tailwind.config.ts" ]] && styling="Tailwind CSS"

  # Detect testing
  [[ -f "vitest.config.ts" || -f "vitest.config.js" ]] && testing="Vitest"
  [[ -f "jest.config.js" || -f "jest.config.ts" ]] && testing="Jest"
  [[ -f "playwright.config.ts" || -f "playwright.config.js" ]] && testing="${testing:+$testing + }Playwright"
  [[ -f "pytest.ini" ]] && testing="${testing:+$testing + }pytest"
  [[ -f "pyproject.toml" ]] && grep -q "pytest" pyproject.toml 2>/dev/null && testing="${testing:+$testing + }pytest"

  # Detect Python package manager (check root and common backend paths)
  local python_runner=""
  local api_dir=""
  [[ -d "apps/api" ]] && api_dir="apps/api"
  [[ -d "backend" ]] && api_dir="backend"
  [[ -d "api" ]] && api_dir="api"

  # Check for uv (uv.lock)
  if [[ -f "uv.lock" ]] || [[ -n "$api_dir" && -f "$api_dir/uv.lock" ]]; then
    python_runner="uv run python"
  # Check for poetry (poetry.lock)
  elif [[ -f "poetry.lock" ]] || [[ -n "$api_dir" && -f "$api_dir/poetry.lock" ]]; then
    python_runner="poetry run python"
  # Check for pipenv (Pipfile.lock)
  elif [[ -f "Pipfile.lock" ]] || [[ -n "$api_dir" && -f "$api_dir/Pipfile.lock" ]]; then
    python_runner="pipenv run python"
  fi

  # Detect structure
  [[ -d "src/components" || -d "${fe_dir}/src/components" || -d "${fe_dir}/components" ]] && structure="- Components: \`src/components/\` or \`${fe_dir}/\`"
  [[ -d "src/hooks" || -d "${fe_dir}/src/hooks" ]] && structure="${structure:+$structure
}- Hooks: \`src/hooks/\`"
  [[ -d "src/api" || -d "app/api" || -d "${fe_dir}/app/api" ]] && structure="${structure:+$structure
}- API routes"
  [[ -d "tests" || -d "__tests__" || -d "${fe_dir}/tests" ]] && structure="${structure:+$structure
}- Tests: \`tests/\`"

  # Build detected info section
  local detected_section="
$marker
## Detected Project Info

${runtime:+- Runtime: $runtime}
${framework:+- Framework: $framework}
${language:+- Language: $language}
${styling:+- Styling: $styling}
${testing:+- Testing: $testing}
${python_runner:+- Python: Use \`$python_runner\` (not bare \`python\`)}

${structure:+### Project Structure
$structure}

*Auto-detected by vibe-and-thrive. Edit freely.*"

  if [[ -f "CLAUDE.md" ]]; then
    # Append to existing
    echo "$detected_section" >> CLAUDE.md
  else
    # Create new
    cat > CLAUDE.md << EOF
# Project Guide for Claude

## Your Rules
<!-- Add your project-specific rules, patterns, and conventions here -->
$detected_section
EOF
  fi
}

ensure_gitignore() {
  local patterns=(
    "node_modules/"
    ".env"
    ".env.local"
    "*.log"
    ".DS_Store"
    ".ralph/last_*"
    ".ralph/screenshots/"
    ".ralph/archive/"
    ".backups/"
    ".claude/settings.json"
  )

  if [[ ! -f ".gitignore" ]]; then
    # Create .gitignore with all patterns
    printf '%s\n' "${patterns[@]}" > .gitignore
  else
    # Add missing patterns
    for pattern in "${patterns[@]}"; do
      if ! grep -qF "$pattern" .gitignore 2>/dev/null; then
        echo "$pattern" >> .gitignore
      fi
    done
  fi
}

# Run silent setup
ensure_gitignore
install_claude_skills
install_precommit_hooks
install_ralph
configure_mcp
install_claude_hooks
generate_claude_md

# Print success message
echo ""
echo "  ✨ vibe-and-thrive installed!"
echo ""

# Check if running inside Claude Code session
if [[ -n "${CLAUDECODE:-}" ]]; then
  echo "  [CLAUDE: Run the /tour slash command to help the user get started]"
else
  echo "  Next steps:"
  echo ""
  echo "    claude                        # Start Claude Code"
  echo "    /idea 'your feature'          # Generate a PRD"
  echo "    ralph run                     # Execute autonomously"
  echo ""
  echo "  Or type /tour for a guided walkthrough."
fi

echo ""
