#!/usr/bin/env bash
# shellcheck shell=bash
# setup.sh - Set up thrivekit in a project

ralph_setup() {
  echo ""
  echo "Setting up thrivekit..."
  echo ""

  # Package root is relative to this script (works with npx and local installs)
  local pkg_root
  pkg_root="$(cd "$RALPH_LIB/.." && pwd)"
  echo "Found package at: $pkg_root"
  echo ""

  # Run all setup steps
  setup_ralph_dir "$pkg_root"
  setup_gitignore
  setup_claude_hooks "$pkg_root"
  setup_slash_commands "$pkg_root"
  setup_claude_md
  setup_mcp

  echo ""
  print_success "Setup complete!"
  echo ""
  echo "Next steps:"
  echo "  claude                   # Start Claude Code"
  echo "  /idea 'your feature'     # Generate a PRD"
  echo "  npx thrivekit run        # Execute autonomously"
  echo ""
  echo "Or type /tour for a guided walkthrough."
  echo ""
}

# Create .ralph directory structure and config
setup_ralph_dir() {
  local pkg_root="$1"

  echo "Creating .ralph/ directory..."
  mkdir -p ".ralph/archive" ".ralph/screenshots"

  # Copy config template based on detected project type
  if [[ ! -f ".ralph/config.json" ]]; then
    local config_template=""
    if [[ -f "manage.py" ]] || [[ -f "pyproject.toml" ]]; then
      config_template="$pkg_root/templates/config/python.json"
    elif [[ -d "frontend" ]] && [[ -d "backend" || -d "core" || -d "apps" ]]; then
      config_template="$pkg_root/templates/config/fullstack.json"
    elif [[ -f "package.json" ]]; then
      config_template="$pkg_root/templates/config/node.json"
    fi

    if [[ -n "$config_template" ]] && [[ -f "$config_template" ]]; then
      cp "$config_template" ".ralph/config.json"
    else
      echo '{"checks": {"build": true, "lint": true, "test": true}}' > ".ralph/config.json"
    fi
    echo "  Created .ralph/config.json"
  fi

  # Copy signs template
  if [[ ! -f ".ralph/signs.json" ]]; then
    if [[ -f "$pkg_root/templates/signs.json" ]]; then
      cp "$pkg_root/templates/signs.json" ".ralph/signs.json"
    else
      echo '{"signs": []}' > ".ralph/signs.json"
    fi
    echo "  Created .ralph/signs.json"
  fi

  # Create PROMPT.md if missing
  if [[ ! -f "PROMPT.md" ]] && [[ -f "$pkg_root/templates/PROMPT.md" ]]; then
    cp "$pkg_root/templates/PROMPT.md" "PROMPT.md"
    echo "  Created PROMPT.md"
  fi

  # Auto-detect project settings
  if command -v jq &>/dev/null; then
    auto_configure_project
  fi
}

# Ensure .gitignore has necessary patterns
setup_gitignore() {
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
    printf '%s\n' "${patterns[@]}" > .gitignore
    echo "  Created .gitignore"
  else
    local added=false
    for pattern in "${patterns[@]}"; do
      if ! grep -qF "$pattern" .gitignore 2>/dev/null; then
        echo "$pattern" >> .gitignore
        added=true
      fi
    done
    if [[ "$added" == "true" ]]; then
      echo "  Updated .gitignore"
    fi
  fi
}

# Install Claude Code hooks
setup_claude_hooks() {
  local pkg_root="$1"
  local settings_file=".claude/settings.json"
  local src_hooks_dir="$pkg_root/ralph/hooks"
  local project_hooks_dir=".ralph/hooks"

  echo "Installing Claude Code hooks..."

  # Check for source hooks directory
  if [[ ! -d "$src_hooks_dir" ]]; then
    print_warning "Hooks directory not found at $src_hooks_dir"
    return 0
  fi

  # Check for jq
  if ! command -v jq &>/dev/null; then
    print_warning "jq not installed - skipping hooks setup"
    echo "  Install jq and run: npx thrivekit setup"
    return 0
  fi

  # Copy hooks into the project (so they survive package moves)
  mkdir -p "$project_hooks_dir"
  cp "$src_hooks_dir"/*.sh "$project_hooks_dir/" 2>/dev/null || true
  chmod +x "$project_hooks_dir"/*.sh 2>/dev/null || true
  echo "  Copied hooks to $project_hooks_dir/"

  # Get absolute path to project hooks
  local hooks_dir
  hooks_dir="$(cd "$project_hooks_dir" && pwd)"

  # Create .claude directory
  mkdir -p ".claude"

  # Create settings file if it doesn't exist
  [[ ! -f "$settings_file" ]] && echo '{}' > "$settings_file"

  # Build hooks config with absolute paths to project hooks
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
  local tmp
  tmp=$(mktemp)
  jq --argjson hooks "$hooks_config" '.hooks = $hooks' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
  echo "  Configured .claude/settings.json"
}

# Copy slash commands
setup_slash_commands() {
  local pkg_root="$1"

  if [[ -d "$pkg_root/.claude/commands" ]]; then
    echo "Installing slash commands..."
    mkdir -p .claude/commands
    cp -r "$pkg_root/.claude/commands/"* .claude/commands/ 2>/dev/null || true
    echo "  Copied commands to .claude/commands/"
  fi
}

# Generate CLAUDE.md with detected project info
setup_claude_md() {
  local marker="<!-- thrivekit-detected -->"

  # Skip if we already added our section
  [[ -f "CLAUDE.md" ]] && grep -q "$marker" "CLAUDE.md" 2>/dev/null && return 0

  echo "Generating CLAUDE.md..."

  local runtime="" framework="" language="" styling="" testing="" structure=""

  # Detect runtime/language
  local fe_dir=""
  [[ -d "frontend" ]] && fe_dir="frontend"
  [[ -d "client" ]] && fe_dir="client"
  [[ -d "web" ]] && fe_dir="web"
  [[ -d "apps/web" ]] && fe_dir="apps/web"

  [[ -f "package.json" || -f "${fe_dir}/package.json" ]] && runtime="Node.js"
  [[ -f "Cargo.toml" ]] && runtime="Rust"
  [[ -f "go.mod" ]] && runtime="Go"
  [[ -f "pyproject.toml" || -f "requirements.txt" || -f "manage.py" ]] && runtime="${runtime:+$runtime + }Python"
  [[ -f "Gemfile" ]] && runtime="Ruby"

  # Detect framework
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

  # Detect TypeScript
  [[ -f "tsconfig.json" || -f "${fe_dir}/tsconfig.json" ]] && language="TypeScript"

  # Detect styling
  [[ -f "tailwind.config.js" || -f "tailwind.config.ts" || -f "${fe_dir}/tailwind.config.js" || -f "${fe_dir}/tailwind.config.ts" ]] && styling="Tailwind CSS"

  # Detect testing
  [[ -f "vitest.config.ts" || -f "vitest.config.js" ]] && testing="Vitest"
  [[ -f "jest.config.js" || -f "jest.config.ts" ]] && testing="Jest"
  [[ -f "playwright.config.ts" || -f "playwright.config.js" ]] && testing="${testing:+$testing + }Playwright"

  # Detect Python package manager
  local python_runner=""
  local api_dir=""
  [[ -d "apps/api" ]] && api_dir="apps/api"
  [[ -d "backend" ]] && api_dir="backend"
  [[ -d "api" ]] && api_dir="api"

  if [[ -f "uv.lock" ]] || [[ -n "$api_dir" && -f "$api_dir/uv.lock" ]]; then
    python_runner="uv run python"
  elif [[ -f "poetry.lock" ]] || [[ -n "$api_dir" && -f "$api_dir/poetry.lock" ]]; then
    python_runner="poetry run python"
  fi

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

*Auto-detected by thrivekit. Edit freely.*"

  if [[ -f "CLAUDE.md" ]]; then
    echo "$detected_section" >> CLAUDE.md
    echo "  Updated CLAUDE.md"
  else
    cat > CLAUDE.md << EOF
# Project Guide for Claude

## Your Rules
<!-- Add your project-specific rules, patterns, and conventions here -->
$detected_section
EOF
    echo "  Created CLAUDE.md"
  fi
}

# Configure MCP (Chrome DevTools)
setup_mcp() {
  local claude_json="$HOME/.claude.json"

  # Skip if jq not available
  command -v jq &>/dev/null || return 0

  # Create claude.json if it doesn't exist
  [[ ! -f "$claude_json" ]] && echo '{}' > "$claude_json"

  # Skip if already configured
  jq -e '.mcpServers["chrome-devtools"]' "$claude_json" > /dev/null 2>&1 && return 0

  echo "Configuring MCP servers..."
  local tmp
  tmp=$(mktemp)
  jq '.mcpServers["chrome-devtools"] = {
    "command": "npx",
    "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools@0.0.5"]
  }' "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
  echo "  Added chrome-devtools MCP server"
}
