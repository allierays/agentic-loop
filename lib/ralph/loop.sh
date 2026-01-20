#!/usr/bin/env bash
# loop.sh - The autonomous development loop

run_loop() {
  local max_iterations="$DEFAULT_MAX_ITERATIONS"
  local specific_story=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max)
        max_iterations="$2"
        shift 2
        ;;
      --story)
        specific_story="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  # Validate prerequisites
  check_dependencies
  require_file "$RALPH_DIR/prd.json" "No PRD found. Run 'ralph prd' first."
  require_file "$PROMPT_FILE" "PROMPT.md not found. Run 'ralph init' first."

  local iteration=0

  while [[ $iteration -lt $max_iterations ]]; do
    # Check for stop signal
    if [[ -f "$RALPH_DIR/.stop" ]]; then
      rm -f "$RALPH_DIR/.stop"
      print_warning "Stop signal received. Exiting gracefully."
      return 0
    fi

    ((iteration++))
    echo ""
    print_info "=== Iteration $iteration/$max_iterations ==="
    echo ""

    # 1. Get next incomplete story
    local story
    if [[ -n "$specific_story" ]]; then
      story="$specific_story"
      # Verify it exists
      local exists
      exists=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .id' "$RALPH_DIR/prd.json" 2>/dev/null)
      if [[ -z "$exists" ]]; then
        print_error "Story $story not found in PRD"
        return 1
      fi
    else
      story=$(jq -r '.stories[] | select(.passes==false) | .id' "$RALPH_DIR/prd.json" 2>/dev/null | head -1)
    fi

    if [[ -z "$story" ]]; then
      print_success "All stories complete!"
      archive_feature
      return 0
    fi

    # 2. Session startup checklist (Anthropic best practice)
    startup_checklist

    # 3. Build prompt with current story context (including failure context if any)
    print_info "Preparing prompt for $story..."
    local prompt_file
    prompt_file=$(create_temp_file ".md") || {
      print_error "Failed to create temp file for prompt"
      return 1
    }

    local failure_context=""
    if [[ -f "$RALPH_DIR/last_failure.txt" ]]; then
      failure_context=$(cat "$RALPH_DIR/last_failure.txt")
    fi

    # Temporarily disable errexit to capture build_prompt errors
    set +e
    build_prompt "$story" "$failure_context" > "$prompt_file" 2>&1
    local build_status=$?
    set -e

    if [[ $build_status -ne 0 ]]; then
      print_error "Failed to build prompt (see $prompt_file for errors)"
      cat "$prompt_file" | head -20
      return 1
    fi

    # Save git state before Claude runs (for migration detection)
    local pre_story_sha=""
    if command -v git &>/dev/null && [[ -d ".git" ]]; then
      pre_story_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
    fi

    # 4. Spawn Claude (fresh context, with timeout)
    echo ""
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║                                                   ║"
    echo "  ║   ██████   █████  ██      ██████  ██   ██         ║"
    echo "  ║   ██   ██ ██   ██ ██      ██   ██ ██   ██         ║"
    echo "  ║   ██████  ███████ ██      ██████  ███████         ║"
    echo "  ║   ██   ██ ██   ██ ██      ██      ██   ██         ║"
    echo "  ║   ██   ██ ██   ██ ███████ ██      ██   ██         ║"
    echo "  ║                                                   ║"
    printf "  ║   Story: %-40s  ║\n" "$story"
    echo "  ║   Starting Claude... (may take a minute)          ║"
    echo "  ║                                                   ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo ""

    local timeout_seconds
    timeout_seconds=$(get_config '.maxSessionSeconds' "$DEFAULT_TIMEOUT_SECONDS")

    # Run Claude with output visible on terminal
    if ! cat "$prompt_file" | run_with_timeout "$timeout_seconds" claude -p --dangerously-skip-permissions --verbose; then
      print_warning "Claude session ended (timeout or error)"
      log_progress "$story" "TIMEOUT" "Claude session ended after ${timeout_seconds}s"
      rm -f "$prompt_file"

      # If running specific story, exit on failure
      [[ -n "$specific_story" ]] && return 1
      continue
    fi

    rm -f "$prompt_file"

    # 5. Run verification pipeline
    echo ""
    if run_verification "$story"; then
      # Mark story as complete
      update_json "$RALPH_DIR/prd.json" \
        --arg id "$story" '(.stories[] | select(.id==$id) | .passes) = true'

      # Clear failure context on success
      rm -f "$RALPH_DIR/last_failure.txt"
      rm -f "$RALPH_DIR/last_review_failure.json"
      rm -f "$RALPH_DIR/last_test_failure.log"
      rm -f "$RALPH_DIR/last_playwright_failure.log"
      rm -f "$RALPH_DIR/last_browser_failure.json"

      # Run migrations if new migration files were created
      if ! run_migrations_if_needed "$pre_story_sha"; then
        log_progress "$story" "FAILED" "Migration failed"
        print_error "Migration failed for $story, will retry..."
        continue
      fi

      # Auto-commit if git is available
      if command -v git &>/dev/null && [[ -d ".git" ]]; then
        local title
        title=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .title' "$RALPH_DIR/prd.json")
        git add -A
        git commit -m "feat($story): $title" || true
      fi

      log_progress "$story" "COMPLETED"
      print_success "Story $story completed!"

      # If running specific story, we're done
      [[ -n "$specific_story" ]] && return 0
    else
      log_progress "$story" "FAILED" "Verification failed, will retry"
      print_warning "Verification failed for $story, iterating..."

      # If running specific story, exit on failure
      [[ -n "$specific_story" ]] && return 1
    fi

    sleep "$ITERATION_DELAY_SECONDS"  # Brief pause between iterations
  done

  print_warning "Max iterations ($max_iterations) reached"
  return 1
}

# Display startup checklist (Anthropic best practice)
startup_checklist() {
  echo "--- Startup Checklist ---"
  echo "Working directory: $(pwd)"
  echo ""

  echo "Recent progress:"
  if [[ -f "$RALPH_DIR/progress.txt" ]]; then
    tail -"$MAX_PROGRESS_LINES" "$RALPH_DIR/progress.txt" | sed 's/^/  /'
  else
    echo "  (no progress yet)"
  fi
  echo ""

  echo "Stories:"
  jq -r '.stories[] | "  \(.id): \(.title) [\(if .passes then "DONE" else "TODO" end)]"' "$RALPH_DIR/prd.json" 2>/dev/null || echo "  (none)"
  echo ""

  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    echo "Git status:"
    git status --short | head -"$MAX_GIT_STATUS_LINES" | sed 's/^/  /'
    echo ""
  fi
}

# Build the prompt with story context injected
build_prompt() {
  local story="$1"
  local failure_context="${2:-}"

  # Read base PROMPT.md
  cat "$PROMPT_FILE"

  echo ""
  echo "---"
  echo ""
  echo "## Current Story"
  echo ""

  # Inject story details
  local story_json
  story_json=$(jq --arg id "$story" '.stories[] | select(.id==$id)' "$RALPH_DIR/prd.json")
  echo '```json'
  echo "$story_json"
  echo '```'

  # Extract file guidance if present
  local has_files
  has_files=$(echo "$story_json" | jq -r '.files // empty' 2>/dev/null)
  if [[ -n "$has_files" ]]; then
    echo ""
    echo "### File Guidance for This Story"
    echo ""
    echo "**Create these files:**"
    echo "$story_json" | jq -r '.files.create[]? // empty' | sed 's/^/- /'
    echo ""
    echo "**Modify these files:**"
    echo "$story_json" | jq -r '.files.modify[]? // empty' | sed 's/^/- /'
    echo ""
    echo "**Reuse/import from:**"
    echo "$story_json" | jq -r '.files.reuse[]? // empty' | sed 's/^/- /'
  fi

  # Extract scalability guidance if present (for backend stories)
  local has_scale
  has_scale=$(echo "$story_json" | jq -r '.scale // empty' 2>/dev/null)
  if [[ -n "$has_scale" ]]; then
    echo ""
    echo "### Scalability Requirements for This Story"
    echo ""
    echo "$story_json" | jq -r '.scale | to_entries[] | "- **\(.key):** \(.value)"' 2>/dev/null
  fi

  echo ""
  echo "## Feature Context"
  echo ""
  echo '```json'
  jq '{feature: .feature, metadata: .metadata}' "$RALPH_DIR/prd.json"
  echo '```'

  # Include scalability if defined
  local has_scalability
  has_scalability=$(jq -r '.scalability // empty' "$RALPH_DIR/prd.json" 2>/dev/null)
  if [[ -n "$has_scalability" ]]; then
    echo ""
    echo "## Scalability Requirements"
    echo ""
    echo "**IMPORTANT:** Follow these scalability rules."
    echo ""
    echo '```json'
    jq '.scalability' "$RALPH_DIR/prd.json"
    echo '```'
    echo ""
    echo "### Key Rules:"
    echo "- Always paginate list endpoints (never return unbounded arrays)"
    echo "- Avoid N+1 queries - eager load relationships"
    echo "- Add database indexes for frequently queried fields"
    echo "- Implement caching strategy as specified"
    echo "- Add rate limiting to public endpoints"
  fi

  # Include architecture if defined
  local has_architecture
  has_architecture=$(jq -r '.architecture // empty' "$RALPH_DIR/prd.json" 2>/dev/null)
  if [[ -n "$has_architecture" ]]; then
    echo ""
    echo "## Architecture Guidelines"
    echo ""
    echo "**IMPORTANT:** Follow these architecture rules strictly."
    echo ""
    echo '```json'
    jq '.architecture' "$RALPH_DIR/prd.json"
    echo '```'
    echo ""
    echo "### Key Rules:"
    echo "- Put files in the specified directories"
    echo "- Reuse existing components listed in 'patterns.reuse'"
    echo "- Do NOT create anything in 'doNotCreate'"
    echo "- Keep files under $(jq -r '.architecture.principles.maxFileLines // 300' "$RALPH_DIR/prd.json") lines"
    echo "- Scripts go in scripts/, docs go in docs/"
  fi

  # Include failure context from previous iteration if available
  if [[ -n "$failure_context" ]]; then
    echo ""
    echo "## Previous Iteration Failed"
    echo ""
    echo "**IMPORTANT:** The previous attempt at this story failed verification. Review the errors below and fix them."
    echo ""
    echo '```'
    echo "$failure_context"
    echo '```'
    echo ""
    echo "### What to do:"
    echo "1. Read the error messages carefully"
    echo "2. Identify the root cause"
    echo "3. Fix the issue (do not just retry the same approach)"
    echo "4. Run verification again"
  fi

  echo ""
  echo "## Signs (Learned Patterns)"
  echo ""
  echo "Apply these lessons from previous sessions:"
  echo ""
  if [[ -f "$RALPH_DIR/signs.json" ]]; then
    jq -r '.signs[] | "- [\(.category)] \(.pattern)"' "$RALPH_DIR/signs.json" 2>/dev/null || echo "(none yet)"
  else
    echo "(none yet)"
  fi

  # Include user's DNA (personal preferences) if it exists
  if [[ -f "$HOME/.claude/DNA.md" ]]; then
    echo ""
    echo "## Developer DNA"
    echo ""
    echo "The developer has these working preferences:"
    echo ""
    cat "$HOME/.claude/DNA.md"
  fi
}

# Archive completed feature
archive_feature() {
  local feature_name
  feature_name=$(jq -r '.feature.name' "$RALPH_DIR/prd.json")

  print_success "Feature '$feature_name' complete!"

  # Archive the PRD
  local archive_dir="$RALPH_DIR/archive"
  mkdir -p "$archive_dir"

  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  mv "$RALPH_DIR/prd.json" "$archive_dir/prd-${timestamp}.json"

  # Final commit if git available
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    git add -A
    git commit -m "feat: complete $feature_name" || true
  fi

  log_progress "FEATURE" "ARCHIVED" "$feature_name"

  echo ""
  echo "PRD archived to: $archive_dir/prd-${timestamp}.json"
  echo "Run 'ralph prd' to start a new feature."
}
