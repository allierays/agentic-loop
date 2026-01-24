#!/usr/bin/env bash
# shellcheck shell=bash
# init.sh - Initialize ralph in a project

ralph_init() {
  # Check if already initialized (progress.txt is created by full init)
  if [[ -f "$RALPH_DIR/progress.txt" ]]; then
    echo "Ralph already initialized in this directory."
    echo "Use 'ralph run' to start the loop or 'ralph status' to check status."
    return 0
  fi

  echo "Initializing ralph..."

  # Create directory structure
  mkdir -p "$RALPH_DIR/archive" "$RALPH_DIR/screenshots"

  # Detect project type and generate appropriate config
  local project_type
  project_type=$(detect_project_type)
  echo "Detected project type: $project_type"

  # Copy config template based on project type (only if missing)
  if [[ ! -f "$RALPH_DIR/config.json" ]]; then
    local config_template="$RALPH_TEMPLATES/config/${project_type}.json"
    if [[ -f "$config_template" ]]; then
      cp "$config_template" "$RALPH_DIR/config.json"
    else
      # Fall back to minimal config
      cp "$RALPH_TEMPLATES/config/minimal.json" "$RALPH_DIR/config.json"
    fi
  fi

  # Create signs with defaults (only if missing)
  if [[ ! -f "$RALPH_DIR/signs.json" ]]; then
    if [[ -f "$RALPH_TEMPLATES/signs.json" ]]; then
      cp "$RALPH_TEMPLATES/signs.json" "$RALPH_DIR/signs.json"
    else
      echo '{"signs": []}' > "$RALPH_DIR/signs.json"
    fi
  fi

  # Create progress log (only if missing)
  if [[ ! -f "$RALPH_DIR/progress.txt" ]]; then
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    echo "[$timestamp] INIT Ralph initialized" > "$RALPH_DIR/progress.txt"
  fi

  # Copy PROMPT.md template if it doesn't exist in project
  if [[ ! -f "PROMPT.md" ]]; then
    cp "$RALPH_TEMPLATES/PROMPT.md" "PROMPT.md"
    echo "Created PROMPT.md template"
  fi

  # Auto-detect and configure project-specific settings
  echo ""
  echo "Auto-configuring project settings..."
  auto_configure_project

  print_success "Ralph initialized!"
  echo ""

  # Prompt for test credentials
  configure_test_auth

  echo ""
  echo "Next steps:"
  echo "  1. Review .ralph/config.json (test credentials, checks, etc.)"
  echo "  2. Generate PRD:"
  echo "     - Thorough: /idea 'feature description' (brainstorm + architecture + scalability)"
  echo "     - Quick:    ralph prd 'feature description' (basic PRD)"
  echo "  3. Start loop: ralph run"
}

# Configure test authentication credentials
configure_test_auth() {
  # Skip if not running in an interactive terminal
  if [[ ! -t 0 ]]; then
    return 0
  fi

  echo ""
  print_info "=== Test Authentication Setup ==="
  echo ""
  echo "Ralph needs test credentials to verify authenticated endpoints."
  echo "(You can skip this and edit .ralph/config.json later)"
  echo ""

  # Ask if they want to configure auth
  read -p "Configure test credentials now? [y/N] " -n 1 -r
  echo ""

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Skipped. Edit .ralph/config.json to add credentials later."
    return 0
  fi

  echo ""
  read -p "Test user email/username: " test_user
  read -s -p "Test user password: " test_password
  echo ""

  if [[ -z "$test_user" || -z "$test_password" ]]; then
    print_warning "Credentials not provided."
    echo "  Options to add them later:"
    echo "    1. Edit .ralph/config.json (stored in plain text)"
    echo "    2. Set RALPH_TEST_USER and RALPH_TEST_PASSWORD env vars (recommended)"
    return 0
  fi

  # Update config.json with credentials
  local config="$RALPH_DIR/config.json"
  if [[ -f "$config" ]]; then
    local tmpfile
    tmpfile=$(mktemp)
    if jq --arg user "$test_user" --arg pass "$test_password" \
       '.auth.testUser = $user | .auth.testPassword = $pass' \
       "$config" > "$tmpfile" 2>/dev/null; then
      mv "$tmpfile" "$config"
      print_success "Test credentials saved to .ralph/config.json"
      print_warning "Note: Credentials stored in plain text. Consider using env vars instead:"
      echo "    export RALPH_TEST_USER='$test_user'"
      echo "    export RALPH_TEST_PASSWORD='****'"
    else
      rm -f "$tmpfile"
      print_warning "Failed to update config. Edit .ralph/config.json manually."
    fi
  fi
}

# Detect the type of project based on files present
detect_project_type() {
  local project_type="minimal"

  # Check for fullstack patterns first (more specific)
  if [[ -d "frontend" && -d "core" ]]; then
    project_type="fullstack"
  elif [[ -d "frontend" && -d "backend" ]]; then
    project_type="fullstack"
  elif [[ -d "apps" ]]; then
    project_type="fullstack"  # Monorepo
  # Then check for single-language projects
  elif [[ -f "Cargo.toml" ]]; then
    project_type="rust"
  elif [[ -f "go.mod" ]]; then
    project_type="go"
  elif [[ -f "pyproject.toml" || -f "requirements.txt" || -f "setup.py" ]]; then
    project_type="python"
  elif [[ -f "package.json" ]]; then
    project_type="node"
  fi

  echo "$project_type"
}

# Auto-detect and configure project-specific settings
auto_configure_project() {
  local config="$RALPH_DIR/config.json"
  [[ ! -f "$config" ]] && return 0

  local updated=false
  local tmpfile
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

  if [[ -n "$playwright_dir" ]]; then
    if jq -e '.playwright.testDir' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg dir "$playwright_dir" '.playwright.testDir = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected playwright.testDir: $playwright_dir"
      updated=true
    fi
  fi

  # 2. Detect testUrlBase from common patterns
  local base_url=""
  # Check package.json scripts for dev server port
  if [[ -f "package.json" ]]; then
    if grep -q '"dev".*:3000' package.json 2>/dev/null; then
      base_url="http://localhost:3000"
    elif grep -q '"dev".*:5173' package.json 2>/dev/null; then
      base_url="http://localhost:5173"  # Vite default
    elif grep -q '"dev".*:8080' package.json 2>/dev/null; then
      base_url="http://localhost:8080"
    fi
  fi
  # Check for monorepo frontend
  for fe_pkg in "apps/web/package.json" "apps/frontend/package.json" "frontend/package.json"; do
    if [[ -f "$fe_pkg" && -z "$base_url" ]]; then
      if grep -q ':3000' "$fe_pkg" 2>/dev/null; then
        base_url="http://localhost:3000"
      elif grep -q ':5173' "$fe_pkg" 2>/dev/null; then
        base_url="http://localhost:5173"
      fi
    fi
  done

  if [[ -n "$base_url" ]]; then
    if jq -e '.testUrlBase' "$tmpfile" >/dev/null 2>&1 && [[ "$(jq -r '.testUrlBase' "$tmpfile")" != "" ]]; then
      : # Already set
    else
      jq --arg url "$base_url" '.testUrlBase = $url' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected testUrlBase: $base_url"
      updated=true
    fi
  fi

  # 3. Detect frontend/backend directories for monorepos
  local frontend_dir="" backend_dir=""
  for dir in "apps/web" "apps/frontend" "frontend" "packages/web" "web"; do
    if [[ -d "$dir" && -f "$dir/package.json" ]]; then
      frontend_dir="$dir"
      break
    fi
  done
  for dir in "apps/api" "apps/backend" "backend" "api" "server"; do
    if [[ -d "$dir" ]] && ([[ -f "$dir/package.json" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/requirements.txt" ]]); then
      backend_dir="$dir"
      break
    fi
  done

  if [[ -n "$frontend_dir" ]]; then
    if jq -e '.directories.frontend' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg dir "$frontend_dir" '.directories.frontend = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected directories.frontend: $frontend_dir"
      updated=true
    fi
  fi

  if [[ -n "$backend_dir" ]]; then
    if jq -e '.directories.backend' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg dir "$backend_dir" '.directories.backend = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected directories.backend: $backend_dir"
      updated=true
    fi
  fi

  # 4. Detect package manager
  local pkg_manager="npm"
  if [[ -f "pnpm-lock.yaml" ]]; then
    pkg_manager="pnpm"
  elif [[ -f "yarn.lock" ]]; then
    pkg_manager="yarn"
  elif [[ -f "bun.lockb" ]]; then
    pkg_manager="bun"
  fi

  if [[ "$pkg_manager" != "npm" ]]; then
    if jq -e '.packageManager' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg pm "$pkg_manager" '.packageManager = $pm' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected packageManager: $pkg_manager"
      updated=true
    fi
  fi

  # Save if updated
  if [[ "$updated" == "true" ]]; then
    mv "$tmpfile" "$config"
  else
    rm -f "$tmpfile"
  fi
}

# Show current ralph status
ralph_status() {
  if [[ ! -d "$RALPH_DIR" ]]; then
    print_error "Ralph not initialized. Run 'ralph init' first."
    return 1
  fi

  echo ""
  print_info "=== Ralph Status ==="
  echo ""

  # Check if PRD exists
  if [[ -f "$RALPH_DIR/prd.json" ]]; then
    local feature_name status
    feature_name=$(jq -r '.feature.name // "Unknown"' "$RALPH_DIR/prd.json")
    status=$(jq -r '.feature.status // "unknown"' "$RALPH_DIR/prd.json")

    echo "Feature: $feature_name"
    echo "Status:  $status"
    echo ""

    # Show stories
    echo "Stories:"
    jq -r '.stories[] | "  \(.id): \(.title) [\(if .passes then "DONE" else "TODO" end)]"' "$RALPH_DIR/prd.json" 2>/dev/null || echo "  (none)"

    # Count pass/fail
    local total passed failed
    total=$(jq '.stories | length' "$RALPH_DIR/prd.json")
    passed=$(jq '[.stories[] | select(.passes == true)] | length' "$RALPH_DIR/prd.json")
    failed=$((total - passed))
    echo ""
    echo "Progress: $passed/$total passed ($failed remaining)"
  else
    # Check for misplaced PRD in subdirectories
    local found_prd
    found_prd=$(find . -path "./.ralph" -prune -o -name "prd.json" -path "*/.ralph/prd.json" -print 2>/dev/null | head -1)

    if [[ -n "$found_prd" ]]; then
      print_warning "PRD found in wrong location: $found_prd"
      echo ""
      echo "Move it to root with:"
      echo "  mv $found_prd .ralph/prd.json"
    else
      echo "No active PRD. Generate one with: ralph prd 'your feature notes...'"
    fi
  fi

  echo ""

  # Show recent progress
  if [[ -f "$RALPH_DIR/progress.txt" ]]; then
    echo "Recent activity:"
    tail -5 "$RALPH_DIR/progress.txt" | sed 's/^/  /'
  fi

  echo ""
}

# Show help
ralph_help() {
  cat <<'EOF'
thrivekit - Tools to thrive with agentic coding

What is this?
  Ralph is an autonomous development loop that builds features for you.
  You describe what you want, Ralph writes the code, tests it, and iterates
  until it works.

  PRD (Product Requirements Document) is how you tell Ralph what to build.
  Use /idea in Claude Code to brainstorm and generate PRDs interactively.

Quick Start:
  1. npx thrivekit setup              # Set up your project
  2. claude --dangerously-skip-permissions
  3. /idea "your feature description" # Generate a PRD (in Claude)
  4. npx thrivekit run                # Ralph builds it autonomously

Usage:
  npx thrivekit <command> [options]

Commands:
  setup                   Set up project (hooks, config, CLAUDE.md)
  init                    Initialize Ralph in current directory
  config                  Re-detect and update project config
  prd <notes>             Generate PRD interactively (quick mode)
  prd --file <file>       Generate PRD from file
  run                     Run autonomous loop until all stories pass
  run --max <n>           Run with max iterations (default: 20)
  status                  Show current feature and story status
  check                   Run verification checks only
  verify <story-id>       Verify a specific story
  sign <pattern> [cat]    Add a learned pattern (sign)
  signs                   List all learned patterns
  backup                  Backup detected databases to .backups/
  backups                 List available database backups
  restore <path>          Restore database from backup
  help                    Show this help message

PRD Generation:
  /idea <description>           Thorough brainstorm (in Claude Code)
  npx thrivekit prd <notes>     Quick PRD generation

Examples:
  npm install thrivekit && npx thrivekit setup
  /idea "Add user authentication with OAuth"
  npx thrivekit prd "Add a contact form"
  npx thrivekit run
  npx thrivekit run --max 10
  npx thrivekit status
  npx thrivekit sign "Always use camelCase" frontend

Environment:
  RALPH_DIR       Override .ralph directory location (default: .ralph)
  PROMPT_FILE     Override PROMPT.md location (default: PROMPT.md)

For more information, see: https://github.com/allthriveai/thrivekit
EOF
}
