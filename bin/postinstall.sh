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

# Auto-detect and configure project-specific settings in .ralph/config.json
auto_configure_ralph() {
  local config=".ralph/config.json"
  [[ ! -f "$config" ]] && return 0
  command -v jq &>/dev/null || return 0  # Need jq

  local tmpfile detected_items=""
  tmpfile=$(mktemp)
  cp "$config" "$tmpfile"

  # 1. Detect Playwright test directory
  local playwright_dir=""
  for dir in "tests/e2e" "e2e" "test/e2e" \
             "apps/web/tests/e2e" "apps/frontend/tests/e2e" \
             "frontend/tests/e2e" "frontend/e2e" \
             "packages/web/tests/e2e"; do
    if [[ -d "$dir" ]]; then
      playwright_dir="$dir"
      break
    fi
  done
  if [[ -n "$playwright_dir" ]] && ! jq -e '.playwright.testDir' "$tmpfile" >/dev/null 2>&1; then
    jq --arg dir "$playwright_dir" '.playwright.testDir = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
    detected_items="${detected_items}    e2e tests: $playwright_dir\n"
  fi

  # 2. Detect testUrlBase from package.json scripts
  local base_url=""
  if [[ -f "package.json" ]]; then
    grep -q '"dev".*:3000' package.json 2>/dev/null && base_url="http://localhost:3000"
    grep -q '"dev".*:5173' package.json 2>/dev/null && base_url="http://localhost:5173"
    grep -q '"dev".*:8080' package.json 2>/dev/null && base_url="http://localhost:8080"
  fi
  for fe_pkg in "apps/web/package.json" "apps/frontend/package.json" "frontend/package.json"; do
    if [[ -f "$fe_pkg" && -z "$base_url" ]]; then
      grep -q ':3000' "$fe_pkg" 2>/dev/null && base_url="http://localhost:3000"
      grep -q ':5173' "$fe_pkg" 2>/dev/null && base_url="http://localhost:5173"
    fi
  done
  if [[ -n "$base_url" ]] && ! jq -e '.testUrlBase // empty | select(. != "")' "$tmpfile" >/dev/null 2>&1; then
    jq --arg url "$base_url" '.testUrlBase = $url' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
    detected_items="${detected_items}    dev server: $base_url\n"
  fi

  # 3. Detect frontend/backend directories for monorepos
  local frontend_dir="" backend_dir=""
  for dir in "apps/web" "apps/frontend" "frontend" "packages/web" "web"; do
    [[ -d "$dir" && -f "$dir/package.json" ]] && frontend_dir="$dir" && break
  done
  for dir in "apps/api" "apps/backend" "backend" "api" "server"; do
    if [[ -d "$dir" ]] && ([[ -f "$dir/package.json" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/requirements.txt" ]]); then
      backend_dir="$dir"
      break
    fi
  done
  if [[ -n "$frontend_dir" ]] && ! jq -e '.directories.frontend' "$tmpfile" >/dev/null 2>&1; then
    jq --arg dir "$frontend_dir" '.directories.frontend = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
    detected_items="${detected_items}    frontend: $frontend_dir\n"
  fi
  if [[ -n "$backend_dir" ]] && ! jq -e '.directories.backend' "$tmpfile" >/dev/null 2>&1; then
    jq --arg dir "$backend_dir" '.directories.backend = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
    detected_items="${detected_items}    backend: $backend_dir\n"
  fi

  # 4. Detect package manager
  local pkg_manager=""
  [[ -f "pnpm-lock.yaml" ]] && pkg_manager="pnpm"
  [[ -f "yarn.lock" ]] && pkg_manager="yarn"
  [[ -f "bun.lockb" ]] && pkg_manager="bun"
  if [[ -n "$pkg_manager" ]] && ! jq -e '.packageManager' "$tmpfile" >/dev/null 2>&1; then
    jq --arg pm "$pkg_manager" '.packageManager = $pm' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
    detected_items="${detected_items}    package manager: $pkg_manager\n"
  fi

  # Save config
  mv "$tmpfile" "$config"

  # Output what was detected (use stderr so npm shows it)
  if [[ -n "$detected_items" ]]; then
    echo "  Auto-configured .ralph/config.json:" >&2
    echo -e "$detected_items" >&2
  fi
}

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
    elif [[ -d "frontend" ]] && [[ -d "backend" || -d "core" || -d "apps" ]]; then
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

  # Install CLAUDE.md if missing (project-specific AI instructions)
  if [[ ! -f "CLAUDE.md" ]]; then
    local claude_template=""
    # Select template based on project type
    if [[ -f "manage.py" ]]; then
      claude_template="$PKG_ROOT/templates/examples/CLAUDE-django.md"
    elif [[ -f "pyproject.toml" ]] && grep -q "fastapi" pyproject.toml 2>/dev/null; then
      claude_template="$PKG_ROOT/templates/examples/CLAUDE-fastapi.md"
    elif [[ -d "frontend" ]] && [[ -d "backend" || -d "api" ]]; then
      claude_template="$PKG_ROOT/templates/examples/CLAUDE-fullstack.md"
    elif [[ -f "package.json" ]] && grep -q '"react"' package.json 2>/dev/null; then
      claude_template="$PKG_ROOT/templates/examples/CLAUDE-react.md"
    elif [[ -f "package.json" ]]; then
      claude_template="$PKG_ROOT/templates/examples/CLAUDE-node.md"
    fi

    if [[ -n "$claude_template" ]] && [[ -f "$claude_template" ]]; then
      cp "$claude_template" "CLAUDE.md"
    fi
  fi

  # Auto-detect and configure project-specific settings
  auto_configure_ralph
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
    # Get hook paths to validate - check multiple hooks since one might be stale
    local session_hook stop_hook
    session_hook=$(jq -r '.hooks.SessionStart[0].hooks[0].command // empty' "$settings_file" 2>/dev/null)
    stop_hook=$(jq -r '.hooks.Stop[0].hooks[0].command // empty' "$settings_file" 2>/dev/null)

    # All hooks must exist AND point to current package location
    if [[ -n "$session_hook" && -x "$session_hook" && -n "$stop_hook" && -x "$stop_hook" ]]; then
      # Also verify hooks point to this package (not stale path from dev install)
      if [[ "$session_hook" == "$hooks_dir/"* && "$stop_hook" == "$hooks_dir/"* ]]; then
        # Hooks exist, valid, and point to current package - skip
        return 0
      else
        echo "  ⚠️  Hooks point to different location, updating..."
      fi
    else
      # Hooks configured but some are invalid - reinstall
      echo "  ⚠️  Existing Claude Code hooks are invalid, reinstalling..."
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

# Print success message (use stderr so npm shows it)
echo "" >&2
echo "  ✨ vibe-and-thrive installed!" >&2
echo "" >&2

# Check if running inside Claude Code session
if [[ -n "${CLAUDECODE:-}" ]]; then
  echo "  [CLAUDE: Run the /tour slash command to help the user get started]" >&2
else
  echo "  Next steps:" >&2
  echo "" >&2
  echo "    claude                        # Start Claude Code" >&2
  echo "    /idea 'your feature'          # Generate a PRD" >&2
  echo "    ralph run                     # Execute autonomously" >&2
  echo "" >&2
  echo "  Or type /tour for a guided walkthrough." >&2
fi

echo "" >&2
