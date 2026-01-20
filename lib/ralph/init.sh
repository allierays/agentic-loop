#!/usr/bin/env bash
# init.sh - Initialize ralph in a project

ralph_init() {
  if [[ -d "$RALPH_DIR" ]]; then
    print_info "Ralph already initialized in this directory."
    print_info "Run 'ralph status' to see current state."
    return 0
  fi

  echo "Initializing ralph..."

  # Create directory structure
  mkdir -p "$RALPH_DIR/archive" "$RALPH_DIR/screenshots"

  # Detect project type and generate appropriate config
  local project_type
  project_type=$(detect_project_type)
  echo "Detected project type: $project_type"

  # Copy config template based on project type
  local config_template="$RALPH_TEMPLATES/config/${project_type}.json"
  if [[ -f "$config_template" ]]; then
    cp "$config_template" "$RALPH_DIR/config.json"
  else
    # Fall back to minimal config
    cp "$RALPH_TEMPLATES/config/minimal.json" "$RALPH_DIR/config.json"
  fi

  # Create signs with defaults
  if [[ -f "$RALPH_TEMPLATES/signs.json" ]]; then
    cp "$RALPH_TEMPLATES/signs.json" "$RALPH_DIR/signs.json"
  else
    echo '{"signs": []}' > "$RALPH_DIR/signs.json"
  fi

  # Create empty progress log
  local timestamp
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  echo "[$timestamp] INIT Ralph initialized" > "$RALPH_DIR/progress.txt"

  # Copy PROMPT.md template if it doesn't exist in project
  if [[ ! -f "PROMPT.md" ]]; then
    cp "$RALPH_TEMPLATES/PROMPT.md" "PROMPT.md"
    echo "Created PROMPT.md template"
  fi

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
    print_warning "Credentials not provided. Edit .ralph/config.json to add them later."
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
    echo "No active PRD. Generate one with: ralph prd 'your feature notes...'"
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
ralph - Autonomous AI Development Loop

Usage:
  ralph <command> [options] [arguments]

Commands:
  init                    Initialize ralph in current directory
  prd <notes>             Generate PRD interactively (quick mode)
  prd --file <file>       Generate PRD from file
  run                     Run autonomous loop until all stories pass
  run --max <n>           Run with max iterations (default: 20)
  status                  Show current feature and story status
  check                   Run verification checks only
  verify <story-id>       Verify a specific story
  sign <pattern> [cat]    Add a learned pattern (sign)
  signs                   List all learned patterns
  help                    Show this help message

PRD Generation:
  /idea <description>     Thorough brainstorm with architecture & scalability
  ralph prd <description> Quick PRD with basic structure

Examples:
  ralph init
  /idea "Add user authentication with OAuth"   # thorough
  ralph prd "Add a contact form"               # quick
  ralph run
  ralph run --max 10
  ralph status
  ralph sign "Always use camelCase in WebSocket responses" frontend

Environment:
  RALPH_DIR       Override .ralph directory location (default: .ralph)
  PROMPT_FILE     Override PROMPT.md location (default: PROMPT.md)

For more information, see: https://github.com/allthriveai/vibe-and-thrive
EOF
}
