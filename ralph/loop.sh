#!/usr/bin/env bash
# shellcheck shell=bash
# loop.sh - The autonomous development loop

# Pre-flight checks to catch common issues before wasting iterations
preflight_checks() {
  echo "--- Pre-flight Checks ---"
  local warnings=0

  # Check API connectivity if configured
  local api_url
  api_url=$(get_config '.api.baseUrl' "")
  if [[ -n "$api_url" ]]; then
    printf "  API connectivity ($api_url)... "
    if curl -sf --connect-timeout 5 "$api_url" >/dev/null 2>&1 || \
       curl -sf --connect-timeout 5 "${api_url}/health" >/dev/null 2>&1 || \
       curl -sf --connect-timeout 5 "${api_url}/api/health" >/dev/null 2>&1; then
      print_success "ok"
    else
      print_warning "unreachable"
      echo "    Is your API server running?"
      ((warnings++))
    fi
  fi

  # Check frontend connectivity if configured
  local test_url
  test_url=$(get_config '.testUrlBase' "")
  if [[ -n "$test_url" ]]; then
    printf "  Frontend connectivity ($test_url)... "
    if curl -sf --connect-timeout 5 "$test_url" >/dev/null 2>&1; then
      print_success "ok"
    else
      print_warning "unreachable"
      echo "    Is your frontend dev server running?"
      ((warnings++))
    fi
  fi

  # Check for common migration issues in Python projects
  local backend_dir
  backend_dir=$(get_config '.directories.backend' "")
  if [[ -n "$backend_dir" && -d "$backend_dir" ]]; then
    # Check for alembic migrations
    if [[ -d "$backend_dir/alembic" ]] || [[ -d "$backend_dir/migrations" ]]; then
      printf "  Database migrations... "
      # Detect Python runner
      local py_runner="python"
      if [[ -f "$backend_dir/uv.lock" ]]; then
        py_runner="uv run"
      elif [[ -f "$backend_dir/poetry.lock" ]]; then
        py_runner="poetry run"
      fi
      # Try to verify DB connection via alembic
      if [[ -f "$backend_dir/alembic.ini" ]]; then
        if (cd "$backend_dir" && $py_runner alembic current >/dev/null 2>&1); then
          print_success "ok"
        elif docker compose exec -T api alembic current >/dev/null 2>&1; then
          # Try via Docker if local fails
          print_success "ok (via docker)"
        else
          print_warning "check DB connection"
          echo "    Run: cd $backend_dir && $py_runner alembic current"
          ((warnings++))
        fi
      fi
    fi
  fi

  # Check Docker if docker-compose exists
  for compose_file in "docker-compose.yml" "docker-compose.yaml" "compose.yml"; do
    if [[ -f "$compose_file" ]]; then
      printf "  Docker services... "
      if docker compose ps --quiet 2>/dev/null | grep -q .; then
        print_success "running"
      elif docker-compose ps --quiet 2>/dev/null | grep -q .; then
        print_success "running"
      else
        print_warning "not running"
        echo "    Run: docker compose up -d"
        ((warnings++))
      fi
      break
    fi
  done

  echo ""
  if [[ $warnings -gt 0 ]]; then
    print_warning "$warnings pre-flight warning(s) - loop may fail on connectivity issues"
    echo ""
    read -r -p "Continue anyway? [Y/n] " response
    if [[ "$response" =~ ^[Nn] ]]; then
      echo "Aborted. Fix the issues and try again."
      exit 1
    fi
  fi
}

run_loop() {
  local max_iterations="$DEFAULT_MAX_ITERATIONS"
  local specific_story=""
  local fast_mode=false

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
      --fast)
        fast_mode=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # Export for use in verification
  export RALPH_FAST_MODE="$fast_mode"

  # Validate prerequisites
  check_dependencies

  # Pre-flight checks to catch issues before wasting iterations
  preflight_checks

  if [[ ! -f "$RALPH_DIR/prd.json" ]]; then
    # Check for misplaced PRD in subdirectories
    local found_prd
    found_prd=$(find . -path "./.ralph" -prune -o -name "prd.json" -path "*/.ralph/prd.json" -print 2>/dev/null | head -1)

    if [[ -n "$found_prd" ]]; then
      print_warning "PRD found in wrong location: $found_prd"
      echo ""
      echo "PRD should be at root: .ralph/prd.json"
      echo ""
      read -r -p "Move it to root? [Y/n] " response
      if [[ "$response" =~ ^[Nn] ]]; then
        echo "Aborted. Move it manually:"
        echo "  mv $found_prd .ralph/prd.json"
        exit 1
      fi
      mkdir -p "$RALPH_DIR"
      mv "$found_prd" "$RALPH_DIR/prd.json"
      print_success "Moved PRD to .ralph/prd.json"
      echo ""
    else
      print_error "No PRD found."
      echo ""
      echo "Create one with:"
      echo "  /idea 'your feature description'   # thorough (recommended)"
      echo "  ralph prd 'your feature'           # quick"
      echo ""
      exit 1
    fi
  fi

  if [[ ! -f "$PROMPT_FILE" ]]; then
    print_error "PROMPT.md not found."
    echo ""
    echo "Create it with: ralph init"
    echo ""
    exit 1
  fi

  # Validate PRD structure
  if ! validate_prd "$RALPH_DIR/prd.json"; then
    return 1
  fi

  local iteration=0
  local last_story=""
  local consecutive_failures=0
  local max_story_retries=5
  local total_attempts=0
  local skipped_stories=()
  local start_time
  local session_started=false  # Track if we've started a Claude session
  start_time=$(date +%s)

  while [[ $iteration -lt $max_iterations ]]; do
    # Check for stop signal
    if [[ -f "$RALPH_DIR/.stop" ]]; then
      rm -f "$RALPH_DIR/.stop"
      print_warning "Stop signal received. Exiting gracefully."
      local passed failed
      passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      failed=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      send_notification "🛑 Ralph stopped: $passed passed, $failed remaining"
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
      print_progress_summary "$start_time" "$total_attempts" "${#skipped_stories[@]}"
      send_notification "✅ Ralph finished: All stories passed!"
      archive_feature
      return 0
    fi

    ((total_attempts++))

    # Track repeated failures on same story
    if [[ "$story" == "$last_story" ]]; then
      ((consecutive_failures++))

      # Circuit breaker: skip to next story after max retries
      if [[ $consecutive_failures -gt $max_story_retries ]]; then
        print_error "Circuit breaker: $story failed $max_story_retries times, skipping to next story"
        echo ""
        echo "  Saved failure context to: $RALPH_DIR/failures/$story.txt"
        mkdir -p "$RALPH_DIR/failures"
        cp "$RALPH_DIR/last_failure.txt" "$RALPH_DIR/failures/$story.txt" 2>/dev/null || true
        # Clear failure context so it doesn't leak into next story
        rm -f "$RALPH_DIR/last_failure.txt"
        skipped_stories+=("$story")
        # Mark as skipped (not passed, but move on)
        jq --arg id "$story" '(.stories[] | select(.id==$id)) |= . + {skipped: true}' "$RALPH_DIR/prd.json" > "$RALPH_DIR/prd.json.tmp" && mv "$RALPH_DIR/prd.json.tmp" "$RALPH_DIR/prd.json"
        last_story=""
        consecutive_failures=0
        continue
      fi

      # Quick retry - no delay needed (Claude API isn't rate-limited)
      print_warning "Retry $consecutive_failures/$max_story_retries for $story"
    else
      consecutive_failures=1
      last_story="$story"
    fi

    # 2. Session startup checklist (skip on retries)
    [[ $consecutive_failures -gt 1 ]] && startup_checklist "true" || startup_checklist "false"

    # 3. Build prompt with current story context (including failure context if any)
    print_info "Preparing prompt for $story..."
    local prompt_file
    prompt_file=$(create_temp_file ".md") || {
      print_error "Failed to create temp file for prompt"
      return 1
    }

    # Only load failure context if it's for the CURRENT story (prevents stale context leaks)
    local failure_context=""
    if [[ -f "$RALPH_DIR/last_failure.txt" ]]; then
      # Check if failure context is for this story (first line contains story ID)
      if grep -q "for $story" "$RALPH_DIR/last_failure.txt" 2>/dev/null; then
        failure_context=$(cat "$RALPH_DIR/last_failure.txt")
      else
        # Stale context from different story - clear it
        rm -f "$RALPH_DIR/last_failure.txt"
      fi
    fi

    # Temporarily disable errexit to capture build_prompt errors
    set +e
    build_prompt "$story" "$failure_context" "$session_started" > "$prompt_file" 2>&1
    local build_status=$?
    set -e

    if [[ $build_status -ne 0 ]]; then
      print_error "Failed to build prompt (see $prompt_file for errors)"
      cat "$prompt_file" | head -20
      rm -f "$prompt_file"
      return 1
    fi

    # Save git state before Claude runs (for migration detection)
    local pre_story_sha=""
    if command -v git &>/dev/null && [[ -d ".git" ]]; then
      pre_story_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
    fi

    # 4. Spawn Claude (fresh context, with timeout)
    # Get story details for banner (single jq call for performance)
    local story_json story_title story_desc story_type story_emoji
    story_json=$(jq --arg id "$story" '.stories[] | select(.id==$id)' "$RALPH_DIR/prd.json")
    story_title=$(echo "$story_json" | jq -r '.title // "Untitled"')
    story_desc=$(echo "$story_json" | jq -r '.description // ""' | head -c 50)
    story_type=$(echo "$story_json" | jq -r '.type // "general"')
    story_emoji=$(type_emoji "$story_type")

    # Get progress
    local total_stories passed_stories current_num
    total_stories=$(jq '[.stories[]] | length' "$RALPH_DIR/prd.json")
    passed_stories=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json")
    current_num=$((passed_stories + 1))

    # Display dynamic banner (truncate long text to fit box)
    local max_width=53
    local display_title="$story_title"
    local display_desc="$story_desc"
    [[ ${#display_title} -gt $max_width ]] && display_title="${display_title:0:$((max_width-3))}..."
    [[ ${#display_desc} -gt $max_width ]] && display_desc="${display_desc:0:$((max_width-3))}..."

    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│  %s %-14s                     [%d/%d] %s  │\n" "$story_emoji" "$story" "$current_num" "$total_stories" "$(progress_bar $current_num $total_stories)"
    printf "│  %-55s│\n" "$display_title"
    printf "│  %-55s│\n" "$display_desc"
    printf "│  Type: %-49s│\n" "$story_type"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    local timeout_seconds
    timeout_seconds=$(get_config '.maxSessionSeconds' "$DEFAULT_TIMEOUT_SECONDS")

    # Run Claude - first story gets fresh session, subsequent continue the session
    local -a claude_args=(-p --dangerously-skip-permissions --verbose)
    if [[ "$session_started" == "true" ]]; then
      claude_args=(--continue "${claude_args[@]}")
    fi

    if ! cat "$prompt_file" | run_with_timeout "$timeout_seconds" claude "${claude_args[@]}"; then
      print_warning "Claude session ended (timeout or error)"
      log_progress "$story" "TIMEOUT" "Claude session ended after ${timeout_seconds}s"
      rm -f "$prompt_file"

      # Session may be broken - reset for next attempt
      session_started=false

      # If running specific story, exit on failure
      [[ -n "$specific_story" ]] && return 1
      continue
    fi

    rm -f "$prompt_file"
    session_started=true  # Mark session as active for subsequent stories

    # 5. Run migrations BEFORE verification (tests need DB schema)
    if ! run_migrations_if_needed "$pre_story_sha"; then
      log_progress "$story" "FAILED" "Migration failed"
      save_failure_context "$story"  # Include migration error in next prompt
      print_error "Migration failed for $story, will retry with error context..."
      continue
    fi

    # 6. Run verification pipeline
    echo ""
    # Capture verification output for failure context
    local verify_log="$RALPH_DIR/last_verification.log"
    set -o pipefail
    if run_verification "$story" 2>&1 | tee "$verify_log"; then
      # Mark story as complete
      update_json "$RALPH_DIR/prd.json" \
        --arg id "$story" '(.stories[] | select(.id==$id) | .passes) = true'

      # Clear failure context on success
      rm -f "$RALPH_DIR/last_failure.txt"
      rm -f "$RALPH_DIR/last_verification.log"

      # Auto-commit if git is available
      if command -v git &>/dev/null && [[ -d ".git" ]]; then
        local title commit_log commit_success
        title=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .title' "$RALPH_DIR/prd.json")
        commit_log=$(mktemp)
        commit_success=false

        # Try up to 3 times to handle auto-fix chains (some hooks always modify files)
        for attempt in 1 2 3; do
          git add -A
          if git commit -m "feat($story): $title" > "$commit_log" 2>&1; then
            commit_success=true
            break
          fi

          # Check if failure is due to file modifications (auto-fix)
          if grep -q "files were modified by this hook" "$commit_log" 2>/dev/null; then
            # Check for REAL errors (not just file modifications or warnings)
            if grep -qE "^error:|: error:|Error:|SyntaxError" "$commit_log" 2>/dev/null; then
              # Real errors - stop retrying
              break
            fi
            # ESLint with actual errors (not just warnings)
            if grep -qE "✖ [0-9]+ problems? \([1-9][0-9]* errors?" "$commit_log" 2>/dev/null; then
              break
            fi
            # Only file modifications - retry
            if [[ $attempt -lt 3 ]]; then
              continue
            fi
            # Max attempts with only file mods - try one more commit
            git add -A
            if git commit -m "feat($story): $title" --no-verify > "$commit_log" 2>&1; then
              commit_success=true
              print_warning "(committed with --no-verify due to auto-fix loop)"
            fi
            break
          else
            # Failed for other reason - check if it's a real error
            if ! grep -qE "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems? \([1-9]" "$commit_log" 2>/dev/null; then
              # No real errors found - might just be warnings
              # Try committing with --no-verify
              git add -A
              if git commit -m "feat($story): $title" --no-verify > "$commit_log" 2>&1; then
                commit_success=true
                print_warning "(committed with --no-verify - only warnings detected)"
              fi
            fi
            break
          fi
        done

        if [[ "$commit_success" != "true" ]]; then
          print_warning "Pre-commit hooks failed, needs fixes..."
          cp "$commit_log" "$RALPH_DIR/last_precommit_failure.log"
          rm -f "$commit_log"
          save_failure_context "$story"
          log_progress "$story" "FAILED" "Pre-commit hooks failed"
          continue
        fi
        rm -f "$commit_log"
      fi

      log_progress "$story" "COMPLETED"

      # Show completion summary
      print_story_complete "$story" "$title"

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
  print_progress_summary "$start_time" "$total_attempts" "${#skipped_stories[@]}"
  local passed failed
  passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  failed=$(jq '[.stories[] | select(.passes==false and .skipped!=true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  send_notification "⚠️ Ralph stopped: $passed passed, $failed remaining (max iterations reached)"
  return 1
}

# Display startup checklist (only full version on first iteration)
# Usage: startup_checklist [is_retry]
startup_checklist() {
  local is_retry="${1:-false}"

  # On retries, just show minimal info
  if [[ "$is_retry" == "true" ]]; then
    return 0
  fi

  echo "--- Startup Checklist ---"
  echo "Working directory: $(pwd)"
  echo ""

  # Show progress summary instead of full list
  local passed_count total_count
  passed_count=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  total_count=$(jq '[.stories[]] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  echo "Progress: $passed_count/$total_count stories complete"
  echo ""

  # Only show last few progress entries
  if [[ -f "$RALPH_DIR/progress.txt" ]]; then
    echo "Recent:"
    tail -3 "$RALPH_DIR/progress.txt" | sed 's/^/  /'
    echo ""
  fi

  # Show git status only if there are changes
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    local git_changes
    git_changes=$(git status --short 2>/dev/null | head -5)
    if [[ -n "$git_changes" ]]; then
      echo "Uncommitted:"
      echo "$git_changes" | sed 's/^/  /'
      echo ""
    fi
  fi
}

# Helper: Build delta prompt for continuing session
# Minimal context - just story ID + any failure info
_build_delta_prompt() {
  local story="$1"
  local failure_context="${2:-}"

  echo ""
  echo "---"
  echo ""

  # If this is a retry (failure context exists), note it
  if [[ -n "$failure_context" ]]; then
    echo "## Retry: Fix the errors below"
    echo ""
    echo "Read \`.ralph/last_failure.txt\` for full error details."
    echo ""
    echo '```'
    echo "$failure_context" | head -50
    echo '```'
    echo ""
  else
    # New story - note previous completion
    local completed_count
    completed_count=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
    if [[ "$completed_count" -gt 0 ]]; then
      echo "## Previous story complete. Moving to next."
      echo ""
    fi
  fi

  echo "## Current Story: $story"
  echo ""
  echo "Read full story details from \`.ralph/prd.json\`"
}

# Helper: Inject signs (learned patterns) - ALWAYS inject these
_inject_signs() {
  [[ ! -f "$RALPH_DIR/signs.json" ]] && return

  local sign_count
  sign_count=$(jq '.signs | length' "$RALPH_DIR/signs.json" 2>/dev/null || echo "0")
  [[ "$sign_count" == "0" ]] && return

  echo ""
  echo "## Signs (Learned Patterns) - FOLLOW THESE"
  echo ""
  jq -r '.signs[] | "- [\(.category)] \(.pattern)"' "$RALPH_DIR/signs.json" 2>/dev/null
}

# Build the prompt - LEAN version
# Claude reads context from prd.json, we just provide the story ID and signs
# Usage: build_prompt <story_id> [failure_context] [is_continuation]
build_prompt() {
  local story="$1"
  local failure_context="${2:-}"
  local is_continuation="${3:-false}"

  if [[ "$is_continuation" == "true" ]]; then
    # Delta prompt for continuing session
    _build_delta_prompt "$story" "$failure_context"
    return
  fi

  # Full prompt for fresh session - LEAN
  cat "$PROMPT_FILE"

  echo ""
  echo "---"
  echo ""
  echo "## Current Story: $story"
  echo ""
  echo "Read full story details from \`.ralph/prd.json\` - it contains everything you need:"
  echo "- \`story.files\` - which files to create/modify"
  echo "- \`story.acceptanceCriteria\` - what must be true"
  echo "- \`story.testSteps\` - verification commands"
  echo "- \`story.contextFiles\` - idea files, styleguides to read"
  echo "- \`story.mcp\` - browser tools for verification"
  echo "- \`story.skills\` - relevant skills to reference"
  echo ""
  echo "Also read:"
  echo "- \`prd.techStack\` - technologies in use"
  echo "- \`prd.globalConstraints\` - rules for all stories"
  echo "- \`.ralph/config.json\` - URLs and directories"

  # Failure context if retrying
  if [[ -n "$failure_context" ]]; then
    echo ""
    echo "## Previous Iteration Failed"
    echo ""
    echo "Read \`.ralph/last_failure.txt\` for details. Key error:"
    echo ""
    echo '```'
    echo "$failure_context" | head -30
    echo '```'
  fi

  # Signs are critical - always inject to prevent repeated mistakes
  _inject_signs
}

# Print story completion summary
print_story_complete() {
  local story="$1"
  local title="$2"

  # Get stats
  local passed_count total_count remaining
  passed_count=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  total_count=$(jq '[.stories[]] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  remaining=$((total_count - passed_count))

  # Get commit info
  local commit_hash=""
  local files_changed="0"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "")
    files_changed=$(git diff --name-only HEAD~1 2>/dev/null | wc -l | tr -d ' ')
  fi

  # Build progress bar
  local bar_filled=$((passed_count * 10 / total_count))
  local bar_empty=$((10 - bar_filled))
  local progress_bar=""
  for ((i=0; i<bar_filled; i++)); do progress_bar+="█"; done
  for ((i=0; i<bar_empty; i++)); do progress_bar+="░"; done

  # Truncate title if too long
  local display_title="$story: $title"
  [[ ${#display_title} -gt 50 ]] && display_title="${display_title:0:47}..."

  echo ""
  echo "  ┌──────────────────────────────────────────────────────┐"
  echo "  │  ✅ STORY COMPLETE                                   │"
  echo "  ├──────────────────────────────────────────────────────┤"
  printf "  │  %-52s│\n" "$display_title"
  echo "  ├──────────────────────────────────────────────────────┤"
  printf "  │  Progress: [%s] %d/%d stories               │\n" "$progress_bar" "$passed_count" "$total_count"
  [[ -n "$commit_hash" ]] && printf "  │  Commit:   %-42s│\n" "$commit_hash ($files_changed files)"
  if [[ $remaining -eq 0 ]]; then
    echo "  │  Status:   All stories complete!                    │"
  else
    printf "  │  Remaining: %-41s│\n" "$remaining stories"
  fi
  echo "  └──────────────────────────────────────────────────────┘"
  echo ""
}

# Print progress summary at end of run
print_progress_summary() {
  local start_time="$1"
  local total_attempts="$2"
  local skipped_count="$3"

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local hours=$((duration / 3600))
  local minutes=$(((duration % 3600) / 60))

  local passed failed total
  passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  failed=$(jq '[.stories[] | select(.passes==false and .skipped!=true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  total=$(jq '.stories | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_success "COMPLETE"
  echo ""
  echo "  Stories:    $passed/$total passed"
  [[ "$skipped_count" -gt 0 ]] && echo "  Skipped:    $skipped_count (hit circuit breaker)"
  echo "  Attempts:   $total_attempts total iterations"
  if [[ $hours -gt 0 ]]; then
    echo "  Duration:   ${hours}h ${minutes}m"
  else
    echo "  Duration:   ${minutes}m"
  fi
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Mark feature as complete (keep PRD for appending new stories)
archive_feature() {
  local feature_name
  feature_name=$(jq -r '.feature.name' "$RALPH_DIR/prd.json")

  print_success "Feature '$feature_name' complete!"

  # Update status to complete (don't archive - user may want to append stories)
  update_json "$RALPH_DIR/prd.json" '.feature.status = "complete"'

  # Final commit if git available
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    git add -A
    if ! git commit -m "feat: complete $feature_name" 2>/dev/null; then
      # Retry after pre-commit auto-fixes
      git add -A
      if ! git commit -m "feat: complete $feature_name" 2>/dev/null; then
        # Check if it's "nothing to commit" vs real error
        if git diff --cached --quiet 2>/dev/null; then
          echo "    (no changes to commit)"
        else
          print_warning "Final commit failed - check git status"
        fi
      fi
    fi
  fi

  log_progress "FEATURE" "COMPLETE" "$feature_name"

  echo ""
  echo "All stories passed! PRD kept at: $RALPH_DIR/prd.json"
  echo ""
  echo "Next:"
  echo "  /idea 'new feature'     # Add more stories (will append)"
  echo "  ralph status            # See completed stories"
}
