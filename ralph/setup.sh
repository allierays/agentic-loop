#!/usr/bin/env bash
# shellcheck shell=bash
# setup.sh - Set up agentic-loop in a project

# Append missing sections from template to existing PROMPT.md
# Usage: append_prompt_sections <template_file> <target_file>
append_prompt_sections() {
  local template="$1"
  local target="$2"
  local added=false

  # Key sections to check and append if missing
  local sections=(
    "### 3. Verify It Actually Works"
    "**Playwright MCP**"
    "**Chrome DevTools MCP**"
    "## Verification Checklist"
    "## Code Quality Standards"
    "## Architecture Rules"
    "## Scalability Rules"
  )

  for section in "${sections[@]}"; do
    if ! grep -qF "$section" "$target" 2>/dev/null; then
      # Section missing - extract and append it
      case "$section" in
        "### 3. Verify It Actually Works"|"**Playwright MCP**"|"**Chrome DevTools MCP**")
          # Extract the browser verification block
          if ! grep -qF "Playwright MCP" "$target" 2>/dev/null; then
            echo "" >> "$target"
            echo "### 3. Verify It Actually Works" >> "$target"
            echo "" >> "$target"
            echo "**You have browser tools - USE THEM to verify your work:**" >> "$target"
            echo "" >> "$target"
            echo "**Playwright MCP** (testing & automation):" >> "$target"
            echo "- Navigate to URLs and verify page content" >> "$target"
            echo "- Take screenshots to verify UI renders correctly" >> "$target"
            echo "- Click elements and fill forms to test interactions" >> "$target"
            echo "- Get accessibility snapshots for a11y testing" >> "$target"
            echo "" >> "$target"
            echo "**Chrome DevTools MCP** (debugging & inspection):" >> "$target"
            echo "- Inspect DOM elements and check console for errors" >> "$target"
            echo "- Debug network requests and responses" >> "$target"
            echo "- Check element styles and computed properties" >> "$target"
            echo "" >> "$target"
            echo "**Do NOT say you're done until:**" >> "$target"
            echo "- All unit tests pass" >> "$target"
            echo "- You've opened the browser and visually verified the feature works" >> "$target"
            echo "- Console has no errors" >> "$target"
            echo "- Error states are handled gracefully" >> "$target"
            added=true
            break  # Don't re-add for the other MCP checks
          fi
          ;;
        "## Verification Checklist")
          echo "" >> "$target"
          echo "## Verification Checklist" >> "$target"
          echo "" >> "$target"
          echo "Before considering any story complete:" >> "$target"
          echo "" >> "$target"
          echo "- [ ] All acceptance criteria are met" >> "$target"
          echo "- [ ] All error handling from story is implemented" >> "$target"
          echo "- [ ] TypeScript/code compiles without errors" >> "$target"
          echo "- [ ] Unit tests written and passing" >> "$target"
          echo "- [ ] **Browser verified** - used MCP tools to visually confirm it works" >> "$target"
          echo "- [ ] No console errors" >> "$target"
          echo "- [ ] Linting passes" >> "$target"
          added=true
          ;;
      esac
    fi
  done

  if [[ "$added" == "true" ]]; then
    echo "  Updated PROMPT.md with new sections"
  fi
}

ralph_setup() {
  echo ""
  echo "    _                    _   _        _                       "
  echo "   / \   __ _  ___ _ __ | |_(_) ___  | |    ___   ___  _ __   "
  echo "  / _ \ / _\` |/ _ \ '_ \| __| |/ __| | |   / _ \ / _ \| '_ \  "
  echo " / ___ \ (_| |  __/ | | | |_| | (__  | |__| (_) | (_) | |_) | "
  echo "/_/   \_\__, |\___|_| |_|\__|_|\___| |_____\___/ \___/| .__/  "
  echo "        |___/                                         |_|     "
  echo ""
  echo "   Autonomous AI coding loop"
  echo ""

  # Package root is relative to this script (works with npx and local installs)
  local pkg_root
  pkg_root="$(cd "$RALPH_LIB/.." && pwd)"

  # Run all setup steps
  setup_ralph_dir "$pkg_root"
  setup_custom_checks
  setup_gitignore
  setup_claude_hooks "$pkg_root"
  setup_slash_commands "$pkg_root"
  setup_claude_md
  setup_mcp
  setup_precommit_hooks
  setup_github_ci "$pkg_root"

  echo ""
  echo "  ========================================"
  echo "  Setup complete!"
  echo "  ========================================"
  echo ""
  echo "  Next steps (two terminals):"
  echo ""
  echo "  --- Terminal 1: Claude Code ---"
  echo "  claude --dangerously-skip-permissions"
  echo "  /tour                   # Guided walkthrough"
  echo "  /idea 'your feature'    # Generate a PRD"
  echo ""
  echo "  --- Terminal 2: Ralph Loop ---"
  echo "  npx agentic-loop run         # Execute PRDs autonomously"
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
    local detected_type=""
    # Check for Go projects
    if [[ -f "go.mod" ]]; then
      config_template="$pkg_root/templates/config/go.json"
      detected_type="go"
    # Check for Rust projects
    elif [[ -f "Cargo.toml" ]]; then
      config_template="$pkg_root/templates/config/rust.json"
      detected_type="rust"
    # Check for Hugo projects
    elif [[ -f "hugo.toml" || -f "hugo.yaml" || -f "config.toml" ]] && [[ -d "content" || -d "layouts" || -d "themes" ]]; then
      config_template="$pkg_root/templates/config/go.json"
      detected_type="hugo"
    # Check for Python framework variants (more specific first)
    elif [[ -f "pyproject.toml" ]]; then
      if grep -qiE "(fastmcp|\"fastmcp\"|'fastmcp')" pyproject.toml 2>/dev/null; then
        config_template="$pkg_root/templates/config/fastmcp.json"
        detected_type="fastmcp"
      elif grep -qiE "(fastapi|\"fastapi\"|'fastapi')" pyproject.toml 2>/dev/null; then
        config_template="$pkg_root/templates/config/python.json"
        detected_type="fastapi"
      elif grep -qiE "(django|\"django\"|'django')" pyproject.toml 2>/dev/null || [[ -f "manage.py" ]]; then
        config_template="$pkg_root/templates/config/python.json"
        detected_type="django"
      else
        config_template="$pkg_root/templates/config/python.json"
        detected_type="python"
      fi
    elif [[ -f "requirements.txt" ]]; then
      if grep -qi 'fastmcp' requirements.txt 2>/dev/null; then
        config_template="$pkg_root/templates/config/fastmcp.json"
        detected_type="fastmcp"
      elif grep -qi 'fastapi' requirements.txt 2>/dev/null; then
        config_template="$pkg_root/templates/config/python.json"
        detected_type="fastapi"
      elif grep -qi 'django' requirements.txt 2>/dev/null || [[ -f "manage.py" ]]; then
        config_template="$pkg_root/templates/config/python.json"
        detected_type="django"
      else
        config_template="$pkg_root/templates/config/python.json"
        detected_type="python"
      fi
    elif [[ -f "manage.py" ]]; then
      config_template="$pkg_root/templates/config/python.json"
      detected_type="django"
    # Check for fullstack projects
    elif [[ -d "frontend" ]] && [[ -d "backend" || -d "core" || -d "apps" ]]; then
      config_template="$pkg_root/templates/config/fullstack.json"
      detected_type="fullstack"
    # Check for Node projects
    elif [[ -f "package.json" ]]; then
      config_template="$pkg_root/templates/config/node.json"
      detected_type="node"
    fi

    if [[ -n "$config_template" ]] && [[ -f "$config_template" ]]; then
      cp "$config_template" ".ralph/config.json"
      echo "  Created .ralph/config.json (detected: $detected_type)"
    else
      echo '{"checks": {"build": true, "lint": true, "test": true}}' > ".ralph/config.json"
      echo "  Created .ralph/config.json"
    fi

    # Store detected type for CLAUDE.md generation
    export RALPH_DETECTED_TYPE="$detected_type"
  fi

  # Copy or merge signs template
  if [[ ! -f ".ralph/signs.json" ]]; then
    if [[ -f "$pkg_root/templates/signs.json" ]]; then
      cp "$pkg_root/templates/signs.json" ".ralph/signs.json"
    else
      echo '{"signs": []}' > ".ralph/signs.json"
    fi
    echo "  Created .ralph/signs.json"
  else
    # Merge new default signs into existing file
    if [[ -f "$pkg_root/templates/signs.json" ]] && command -v jq &>/dev/null; then
      local existing_ids new_signs_added=0
      existing_ids=$(jq -r '.signs[].id // empty' ".ralph/signs.json" 2>/dev/null | tr '\n' '|')

      # Add signs from template that don't exist locally
      while IFS= read -r sign; do
        local sign_id
        sign_id=$(echo "$sign" | jq -r '.id // empty')
        if [[ -n "$sign_id" && ! "$existing_ids" =~ "$sign_id" ]]; then
          # Add this sign to local file
          local tmp_file
          tmp_file=$(mktemp)
          jq --argjson new_sign "$sign" '.signs += [$new_sign]' ".ralph/signs.json" > "$tmp_file"
          mv "$tmp_file" ".ralph/signs.json"
          ((new_signs_added++))
        fi
      done < <(jq -c '.signs[]' "$pkg_root/templates/signs.json" 2>/dev/null)

      if [[ $new_signs_added -gt 0 ]]; then
        echo "  Merged $new_signs_added new sign(s) into .ralph/signs.json"
      fi
    fi
  fi

  # Create or update PROMPT.md
  if [[ -f "$pkg_root/templates/PROMPT.md" ]]; then
    if [[ ! -f "PROMPT.md" ]]; then
      cp "$pkg_root/templates/PROMPT.md" "PROMPT.md"
      echo "  Created PROMPT.md"
    else
      # Append missing sections to existing PROMPT.md
      append_prompt_sections "$pkg_root/templates/PROMPT.md" "PROMPT.md"
    fi
  fi

  # Auto-detect project settings
  if command -v jq &>/dev/null; then
    auto_configure_project
  fi
}

# Set up custom PRD checks directory
setup_custom_checks() {
  local checks_dir=".ralph/checks/prd"

  # Skip if directory already exists
  if [[ -d "$checks_dir" ]]; then
    local count
    count=$(ls -1 "$checks_dir"/check-* 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" -gt 0 ]]; then
      echo "  Custom PRD checks: $count script(s) in $checks_dir/"
    fi
    return 0
  fi

  mkdir -p "$checks_dir"
  echo "  Created $checks_dir/ (add custom check scripts here)"
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
  local global_hooks_dir="$HOME/.config/ralph/hooks"

  echo "Installing Claude Code hooks..."

  # Check for source hooks directory
  if [[ ! -d "$src_hooks_dir" ]]; then
    print_warning "Hooks directory not found at $src_hooks_dir"
    return 0
  fi

  # Check for jq
  if ! command -v jq &>/dev/null; then
    print_warning "jq not installed - skipping hooks setup"
    echo "  Install jq and run: npx agentic-loop setup"
    return 0
  fi

  # Copy hooks into the project (so they survive package moves)
  mkdir -p "$project_hooks_dir"
  cp "$src_hooks_dir"/*.sh "$project_hooks_dir/" 2>/dev/null || true
  chmod +x "$project_hooks_dir"/*.sh 2>/dev/null || true
  echo "  Copied hooks to $project_hooks_dir/"

  # Note if global hooks exist
  if [[ -d "$global_hooks_dir" ]] && ls -1 "$global_hooks_dir"/*.sh &>/dev/null; then
    echo "  Found global hooks in $global_hooks_dir/"
  fi

  # Get absolute path to project hooks
  local hooks_dir
  hooks_dir="$(cd "$project_hooks_dir" && pwd)"

  # Create .claude directory
  mkdir -p ".claude"

  # Create settings file if it doesn't exist
  [[ ! -f "$settings_file" ]] && echo '{}' > "$settings_file"

  # Helper to resolve hook path (project takes priority over global)
  _resolve_hook() {
    local hook_name="$1"
    if [[ -f "$project_hooks_dir/$hook_name" ]]; then
      echo "$hooks_dir/$hook_name"
    elif [[ -f "$global_hooks_dir/$hook_name" ]]; then
      echo "$global_hooks_dir/$hook_name"
    fi
  }

  # Resolve each hook path (project hooks take priority over global)
  local protect_prd warn_debug warn_secrets warn_urls warn_empty_catch log_tools inject_context save_learnings
  protect_prd=$(_resolve_hook "protect-prd.sh")
  warn_debug=$(_resolve_hook "warn-debug.sh")
  warn_secrets=$(_resolve_hook "warn-secrets.sh")
  warn_urls=$(_resolve_hook "warn-urls.sh")
  warn_empty_catch=$(_resolve_hook "warn-empty-catch.sh")
  log_tools=$(_resolve_hook "log-tools.sh")
  inject_context=$(_resolve_hook "inject-context.sh")
  save_learnings=$(_resolve_hook "save-learnings.sh")

  # Build hooks arrays using jq for proper JSON
  local pre_tool_hooks post_edit_hooks post_all_hooks session_start_hooks stop_hooks

  # PreToolUse: protect-prd on Edit|Write
  pre_tool_hooks="[]"
  [[ -n "$protect_prd" ]] && pre_tool_hooks=$(jq -n --arg cmd "$protect_prd" '[{"type": "command", "command": $cmd, "timeout": 5}]')

  # PostToolUse: warn-* hooks on Edit|Write
  post_edit_hooks="[]"
  for hook_path in "$warn_debug" "$warn_secrets" "$warn_urls" "$warn_empty_catch"; do
    [[ -n "$hook_path" ]] && post_edit_hooks=$(echo "$post_edit_hooks" | jq --arg cmd "$hook_path" '. + [{"type": "command", "command": $cmd, "timeout": 5}]')
  done

  # PostToolUse: log-tools on all
  post_all_hooks="[]"
  [[ -n "$log_tools" ]] && post_all_hooks=$(jq -n --arg cmd "$log_tools" '[{"type": "command", "command": $cmd, "timeout": 3}]')

  # SessionStart: inject-context
  session_start_hooks="[]"
  [[ -n "$inject_context" ]] && session_start_hooks=$(jq -n --arg cmd "$inject_context" '[{"type": "command", "command": $cmd, "timeout": 5}]')

  # Stop: save-learnings
  stop_hooks="[]"
  [[ -n "$save_learnings" ]] && stop_hooks=$(jq -n --arg cmd "$save_learnings" '[{"type": "command", "command": $cmd, "timeout": 10}]')

  # Build the complete hooks config
  local hooks_config
  hooks_config=$(jq -n \
    --argjson pre_tool "$pre_tool_hooks" \
    --argjson post_edit "$post_edit_hooks" \
    --argjson post_all "$post_all_hooks" \
    --argjson session_start "$session_start_hooks" \
    --argjson stop "$stop_hooks" \
    '{
      "PreToolUse": [{"matcher": "Edit|Write", "hooks": $pre_tool}],
      "PostToolUse": [
        {"matcher": "Edit|Write", "hooks": $post_edit},
        {"matcher": "*", "hooks": $post_all}
      ],
      "SessionStart": [{"hooks": $session_start}],
      "Stop": [{"hooks": $stop}]
    }'
  )

  # Merge hooks into settings
  local tmp
  tmp=$(mktemp)
  jq --argjson hooks "$hooks_config" '.hooks = $hooks' "$settings_file" > "$tmp" && mv "$tmp" "$settings_file"
  echo "  Configured .claude/settings.json"
}

# Copy slash commands (skills format for Claude Code)
setup_slash_commands() {
  local pkg_root="$1"

  # New skills format (.claude/skills/<name>/SKILL.md)
  if [[ -d "$pkg_root/.claude/skills" ]]; then
    echo "Installing slash commands..."
    mkdir -p .claude/skills
    cp -r "$pkg_root/.claude/skills/"* .claude/skills/ 2>/dev/null || true
    echo "  Copied skills to .claude/skills/"
  fi

  # Legacy commands format (for backward compatibility)
  if [[ -d "$pkg_root/.claude/commands" ]]; then
    mkdir -p .claude/commands
    cp -r "$pkg_root/.claude/commands/"* .claude/commands/ 2>/dev/null || true
  fi
}

# Generate CLAUDE.md with detected project info
setup_claude_md() {
  local marker="<!-- agentic-loop-detected -->"
  local pkg_root
  pkg_root="$(cd "$RALPH_LIB/.." && pwd)"

  # Skip if we already added our section
  [[ -f "CLAUDE.md" ]] && grep -q "$marker" "CLAUDE.md" 2>/dev/null && return 0

  echo "Generating CLAUDE.md..."

  local runtime="" framework="" language="" styling="" testing="" structure=""
  local framework_type=""  # For template selection

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

  # Detect framework (with template type detection)
  local pkg="package.json"
  [[ -n "$fe_dir" && -f "${fe_dir}/package.json" ]] && pkg="${fe_dir}/package.json"

  if [[ -f "$pkg" ]]; then
    grep -q '"next"' "$pkg" 2>/dev/null && framework="Next.js"
    grep -q '"react"' "$pkg" 2>/dev/null && [[ -z "$framework" ]] && framework="React" && framework_type="react"
    grep -q '"vue"' "$pkg" 2>/dev/null && framework="Vue"
    grep -q '"svelte"' "$pkg" 2>/dev/null && framework="Svelte"
    grep -q '"express"' "$pkg" 2>/dev/null && framework="${framework:+$framework + }Express"
  fi

  # Detect Python frameworks (more specific detection)
  if [[ -f "pyproject.toml" ]]; then
    if grep -qiE "(fastmcp|\"fastmcp\"|'fastmcp')" pyproject.toml 2>/dev/null; then
      framework="${framework:+$framework + }FastMCP"
      framework_type="fastmcp"
    elif grep -qiE "(fastapi|\"fastapi\"|'fastapi')" pyproject.toml 2>/dev/null; then
      framework="${framework:+$framework + }FastAPI"
      framework_type="fastapi"
    elif grep -qiE "(django|\"django\"|'django')" pyproject.toml 2>/dev/null || [[ -f "manage.py" ]]; then
      framework="${framework:+$framework + }Django"
      framework_type="django"
    fi
  elif [[ -f "requirements.txt" ]]; then
    if grep -qi 'fastmcp' requirements.txt 2>/dev/null; then
      framework="${framework:+$framework + }FastMCP"
      framework_type="fastmcp"
    elif grep -qi 'fastapi' requirements.txt 2>/dev/null; then
      framework="${framework:+$framework + }FastAPI"
      framework_type="fastapi"
    elif grep -qi 'django' requirements.txt 2>/dev/null || [[ -f "manage.py" ]]; then
      framework="${framework:+$framework + }Django"
      framework_type="django"
    fi
  elif [[ -f "manage.py" ]]; then
    framework="${framework:+$framework + }Django"
    framework_type="django"
  fi

  # Detect Hugo (Go static site generator)
  for hugo_config in "hugo.toml" "hugo.yaml" "hugo.json" "config.toml"; do
    if [[ -f "$hugo_config" ]] && [[ -d "content" || -d "layouts" || -d "themes" ]]; then
      framework="${framework:+$framework + }Hugo"
      [[ -z "$runtime" ]] && runtime="Go"
      break
    fi
  done

  # Detect TypeScript
  [[ -f "tsconfig.json" || -f "${fe_dir}/tsconfig.json" ]] && language="TypeScript"

  # Detect styling
  [[ -f "tailwind.config.js" || -f "tailwind.config.ts" || -f "${fe_dir}/tailwind.config.js" || -f "${fe_dir}/tailwind.config.ts" ]] && styling="Tailwind CSS"

  # Detect testing
  [[ -f "vitest.config.ts" || -f "vitest.config.js" ]] && testing="Vitest"
  [[ -f "jest.config.js" || -f "jest.config.ts" ]] && testing="Jest"
  [[ -f "playwright.config.ts" || -f "playwright.config.js" ]] && testing="${testing:+$testing + }Playwright"
  [[ -f "pytest.ini" || -f "pyproject.toml" ]] && grep -q 'pytest' pyproject.toml 2>/dev/null && testing="${testing:+$testing + }pytest"

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

*Auto-detected by agentic-loop. Edit freely.*"

  # Check for framework-specific template
  local framework_template=""
  if [[ -n "$framework_type" ]]; then
    framework_template="$pkg_root/templates/examples/CLAUDE-${framework_type}.md"
  fi

  if [[ -f "CLAUDE.md" ]]; then
    # Append framework template if it exists and not already included
    if [[ -n "$framework_template" && -f "$framework_template" ]]; then
      local template_marker="<!-- CLAUDE-${framework_type} -->"
      if ! grep -q "$template_marker" "CLAUDE.md" 2>/dev/null; then
        echo "" >> CLAUDE.md
        echo "$template_marker" >> CLAUDE.md
        # Skip the first line (# CLAUDE.md - ...) of the template
        tail -n +2 "$framework_template" >> CLAUDE.md
        echo "  Appended ${framework_type} conventions to CLAUDE.md"
      fi
    fi
    echo "$detected_section" >> CLAUDE.md
    echo "  Updated CLAUDE.md"
  else
    # Create new CLAUDE.md
    cat > CLAUDE.md << EOF
# Project Guide for Claude

## Your Rules
<!-- Add your project-specific rules, patterns, and conventions here -->
EOF

    # Include framework template if available
    if [[ -n "$framework_template" && -f "$framework_template" ]]; then
      local template_marker="<!-- CLAUDE-${framework_type} -->"
      echo "" >> CLAUDE.md
      echo "$template_marker" >> CLAUDE.md
      # Skip the first line (# CLAUDE.md - ...) of the template
      tail -n +2 "$framework_template" >> CLAUDE.md
      echo "  Included ${framework_type} conventions"
    fi

    echo "$detected_section" >> CLAUDE.md
    echo "  Created CLAUDE.md"
  fi
}

# Configure MCP (Browser tools for verification)
setup_mcp() {
  local claude_json="$HOME/.claude.json"

  # Skip if jq not available
  command -v jq &>/dev/null || return 0

  # Create claude.json if it doesn't exist
  [[ ! -f "$claude_json" ]] && echo '{}' > "$claude_json"

  local added_any=false

  # Add Playwright MCP if not configured
  # Uses chromium + headless to avoid conflicts with user's Chrome session
  if ! jq -e '.mcpServers["playwright"]' "$claude_json" > /dev/null 2>&1; then
    echo "Configuring MCP servers..."
    local tmp
    tmp=$(mktemp)
    jq '.mcpServers["playwright"] = {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--browser", "chromium", "--headless"]
    }' "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
    echo "  Added playwright MCP server (browser automation & testing)"
    added_any=true
  fi

  # Add Chrome DevTools MCP if not configured
  if ! jq -e '.mcpServers["chrome-devtools"]' "$claude_json" > /dev/null 2>&1; then
    [[ "$added_any" == "false" ]] && echo "Configuring MCP servers..."
    local tmp
    tmp=$(mktemp)
    jq '.mcpServers["chrome-devtools"] = {
      "command": "npx",
      "args": ["chrome-devtools-mcp@latest"]
    }' "$claude_json" > "$tmp" && mv "$tmp" "$claude_json"
    echo "  Added chrome-devtools MCP server (debugging & inspection)"
    added_any=true
  fi

  # Ask about test credentials
  if [[ "$added_any" == "true" ]]; then
    setup_test_credentials
  fi
}

# Set up test credentials for browser automation
setup_test_credentials() {
  echo ""
  echo "  Browser automation often needs login credentials for testing."
  echo ""
  read -r -p "  Do you have test user credentials to configure? [y/N] " response

  if [[ "$response" =~ ^[Yy]$ ]]; then
    echo ""
    echo "  These will be stored in .env (already in .gitignore - never committed)"
    echo ""

    # Create .env if it doesn't exist
    if [[ ! -f ".env" ]]; then
      touch ".env"
      echo "  Created .env file"
    fi

    # Get credentials
    read -r -p "  Test user email: " test_email
    read -r -s -p "  Test user password: " test_password
    echo ""

    # Add to .env (remove old entries first, then append)
    if grep -q "^RALPH_TEST_USER=" .env 2>/dev/null; then
      # Remove old entries
      local tmp
      tmp=$(mktemp)
      grep -v "^RALPH_TEST_USER=\|^RALPH_TEST_PASSWORD=" .env > "$tmp" && mv "$tmp" .env
    fi
    # Append new (using printf to handle special characters safely)
    echo "" >> .env
    echo "# Test credentials for browser automation (auto-added by agentic-loop)" >> .env
    printf 'RALPH_TEST_USER=%s\n' "$test_email" >> .env
    printf 'RALPH_TEST_PASSWORD=%s\n' "$test_password" >> .env

    echo "  Saved credentials to .env"
    echo ""
    echo "  Note: .env is gitignored - your password will never be committed to git."
  fi
}

# Set up pre-commit hooks
setup_precommit_hooks() {
  echo "Setting up pre-commit hooks..."

  # Create .pre-commit-config.yaml if it doesn't exist
  if [[ ! -f ".pre-commit-config.yaml" ]]; then
    cat > .pre-commit-config.yaml << 'EOF'
repos:
  - repo: https://github.com/allierays/agentic-loop
    rev: v1.0.0
    hooks:
      - id: backup-db
        name: Backup database before commit
      - id: check-secrets
        name: Check for hardcoded secrets
      - id: check-hardcoded-urls
        name: Check for hardcoded URLs
      - id: check-debug
        name: Check for debug statements
EOF
    echo "  Created .pre-commit-config.yaml"
  else
    echo "  Skipped: .pre-commit-config.yaml already exists"
  fi

  # Install hooks if pre-commit is available
  if command -v pre-commit &>/dev/null; then
    if [[ -d ".git" ]]; then
      pre-commit install > /dev/null 2>&1
      echo "  Hooks installed"
    else
      echo "  Not a git repo - run 'pre-commit install' after git init"
    fi
  else
    echo "  pre-commit not found - install with: pip install pre-commit"
    echo "  Then run: pre-commit install"
  fi
}

# Set up GitHub Actions CI/CD
setup_github_ci() {
  local pkg_root="$1"

  # Skip if not a git repo
  if [[ ! -d ".git" ]]; then
    return 0
  fi

  # Skip if already set up
  if [[ -f ".github/workflows/pr.yml" ]] && [[ -f ".github/workflows/nightly.yml" ]]; then
    return 0
  fi

  echo ""
  echo "  GitHub Actions CI/CD can be configured:"
  echo "    - PR checks: Fast lint/typecheck on pull requests"
  echo "    - Nightly: Full test suite + PRD tests at 3am UTC"
  echo ""
  read -r -p "  Set up GitHub Actions? [Y/n] " response

  if [[ "$response" =~ ^[Nn]$ ]]; then
    echo "  Skipped GitHub Actions (run 'npx agentic-loop ci install' later)"
    return 0
  fi

  echo "Setting up GitHub Actions CI/CD..."

  # Create workflows directory
  mkdir -p .github/workflows

  # Read config values for dynamic generation
  local backend_dir frontend_dir test_cmd
  backend_dir=$(get_config '.directories.backend' "")
  frontend_dir=$(get_config '.directories.frontend' "")
  test_cmd=$(get_config '.checks.testCommand' "")

  # Generate PR workflow
  if [[ ! -f ".github/workflows/pr.yml" ]]; then
    _generate_pr_workflow "$backend_dir" "$frontend_dir"
    echo "  Created .github/workflows/pr.yml (fast PR checks)"
  fi

  # Generate nightly workflow
  if [[ ! -f ".github/workflows/nightly.yml" ]]; then
    _generate_nightly_workflow "$backend_dir" "$frontend_dir" "$test_cmd"
    echo "  Created .github/workflows/nightly.yml (nightly full tests)"
  fi
}

# Generate PR workflow based on project structure
_generate_pr_workflow() {
  local backend_dir="$1"
  local frontend_dir="$2"

  cat > .github/workflows/pr.yml << 'HEADER'
# Fast PR checks - lint only, no tests
name: PR Check

on:
  pull_request:
    branches: [main, master]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
HEADER

  # Detect and add Python steps
  if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]] || [[ -n "$backend_dir" && -f "$backend_dir/pyproject.toml" ]]; then
    local py_dir="${backend_dir:-.}"
    cat >> .github/workflows/pr.yml << EOF

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install Python dependencies
        run: |
          pip install ruff uv
          cd $py_dir && uv pip install -e . --system 2>/dev/null || pip install -e . 2>/dev/null || true

      - name: Ruff lint
        run: cd $py_dir && ruff check .
EOF
  fi

  # Detect and add Node.js steps
  if [[ -f "package.json" ]] || [[ -n "$frontend_dir" && -f "$frontend_dir/package.json" ]]; then
    local node_dir="${frontend_dir:-.}"
    cat >> .github/workflows/pr.yml << EOF

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Node dependencies
        run: cd $node_dir && npm ci

      - name: Lint
        run: cd $node_dir && npm run lint 2>/dev/null || true

      - name: TypeScript check
        run: cd $node_dir && npx tsc --noEmit 2>/dev/null || true

      - name: Build
        run: cd $node_dir && npm run build 2>/dev/null || true
EOF
  fi
}

# Generate nightly workflow based on project structure
_generate_nightly_workflow() {
  local backend_dir="$1"
  local frontend_dir="$2"
  local test_cmd="$3"

  cat > .github/workflows/nightly.yml << 'HEADER'
# Nightly comprehensive test suite
name: Nightly Tests

on:
  schedule:
    - cron: '0 3 * * *'  # 3am UTC daily
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
HEADER

  # Add services if backend exists (likely needs DB)
  if [[ -n "$backend_dir" ]] || [[ -f "pyproject.toml" ]]; then
    cat >> .github/workflows/nightly.yml << 'EOF'

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      DATABASE_URL: postgresql://test:test@localhost:5432/test
EOF
  fi

  cat >> .github/workflows/nightly.yml << 'EOF'

    steps:
      - uses: actions/checkout@v4
EOF

  # Add Python setup and tests
  if [[ -f "pyproject.toml" ]] || [[ -n "$backend_dir" && -f "$backend_dir/pyproject.toml" ]]; then
    local py_dir="${backend_dir:-.}"
    local py_test_cmd="${test_cmd:-pytest -v --tb=short}"

    cat >> .github/workflows/nightly.yml << EOF

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install Python dependencies
        run: |
          pip install uv
          cd $py_dir && uv pip install -e ".[dev]" --system 2>/dev/null || pip install -e . 2>/dev/null || true

      - name: Run migrations
        run: cd $py_dir && alembic upgrade head 2>/dev/null || true
        continue-on-error: true

      - name: Python tests
        run: cd $py_dir && $py_test_cmd
        continue-on-error: true
EOF
  fi

  # Add Node.js setup and tests
  if [[ -f "package.json" ]] || [[ -n "$frontend_dir" && -f "$frontend_dir/package.json" ]]; then
    local node_dir="${frontend_dir:-.}"
    cat >> .github/workflows/nightly.yml << EOF

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Node dependencies
        run: cd $node_dir && npm ci

      - name: Node tests
        run: cd $node_dir && npm test 2>/dev/null || true
        continue-on-error: true
EOF
  fi

  # Add PRD tests
  cat >> .github/workflows/nightly.yml << 'EOF'

      - name: Run PRD tests
        if: hashFiles('.ralph/prd.json') != ''
        run: npx agentic-loop test prd 2>/dev/null || true
        continue-on-error: true

  notify:
    needs: test
    runs-on: ubuntu-latest
    if: failure()
    steps:
      - name: Notify on failure
        run: echo "Nightly tests failed!"
EOF
}
