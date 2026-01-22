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
  if [[ ! -d ".ralph" ]] && [[ -f "$PKG_ROOT/bin/ralph.sh" ]]; then
    "$PKG_ROOT/bin/ralph.sh" init > /dev/null 2>&1 || true
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

install_claude_hooks() {
  # Skip if jq not available
  command -v jq &>/dev/null || return 0

  local settings_file=".claude/settings.json"
  local hooks_dir="$PKG_ROOT/lib/ralph/hooks"

  # Skip if hooks directory doesn't exist
  [[ ! -d "$hooks_dir" ]] && return 0

  # Ensure .claude directory exists
  mkdir -p ".claude"

  # Create settings file if it doesn't exist
  [[ ! -f "$settings_file" ]] && echo '{}' > "$settings_file"

  # Skip if hooks already configured
  jq -e '.hooks' "$settings_file" > /dev/null 2>&1 && return 0

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
  echo "  Start Claude Code and type /tour:"
  echo ""
  echo "    claude"
  echo "    /tour"
fi

echo ""
