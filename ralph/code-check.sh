#!/usr/bin/env bash
# shellcheck shell=bash
#
# code-check.sh - Code verification pipeline for Ralph autonomous development loop
#
# ============================================================================
# OVERVIEW
# ============================================================================
# After Claude writes code for a story, this pipeline verifies the work before
# marking it complete. If verification fails, context is saved and Claude
# retries with knowledge of what went wrong.
#
# Philosophy: Claude handles complex verification (visual, UX, logic) using
# MCP browser tools. Ralph handles deterministic checks (lint, tests, commands).
#
# ============================================================================
# VERIFICATION PIPELINE (5 steps, fail-fast)
# ============================================================================
#
#   [1/5] Lint checks      - ESLint, Ruff, golangci-lint, etc.
#   [2/5] Tests            - Verify test files exist + run unit tests
#   [3/5] PRD test steps   - Execute testSteps commands from prd.json
#   [4/5] API smoke test   - Hit health endpoint (if configured)
#   [5/5] Frontend smoke   - Load page, check for errors (if configured)
#
# Pipeline stops at first failure to save time.
#
# ============================================================================
# FAILURE CONTEXT & LEARNING
# ============================================================================
# When verification fails, save_failure_context() ACCUMULATES errors across
# retries (not just the last failure). This lets Claude see patterns:
#
#   === Attempt 1 failed for TASK-001 ===
#   ERROR: relation "users" does not exist
#   ---
#   === Attempt 2 failed for TASK-001 ===
#   ERROR: relation "users" does not exist
#   ---
#
# Seeing "same error 3 times" signals a structural issue (missing migration,
# wrong prerequisites) rather than a simple bug to fix.
#
# Context is:
#   - Appended per attempt (not overwritten)
#   - Capped at 200 lines to avoid huge prompts
#   - Cleared when switching to a new story
#   - Cleared on success
#
# STRUCTURAL ERROR DETECTION:
# Some errors indicate structural issues (not code bugs) that can't be fixed
# by retrying. These are detected and flagged with actionable suggestions:
#
#   - "column does not exist" → Suggest DB reset (schema mismatch)
#   - "pending migration"     → Suggest running migrations
#   - "connection refused"    → Suggest starting services
#
# This prevents infinite retry loops on issues that need manual intervention.
#
# ============================================================================
# CONFIGURATION (via .ralph/config.json)
# ============================================================================
#
#   .checks.lint        - Run linting (default: true)
#   .checks.test        - Run tests: true, false, or "final" (last story only)
#   .checks.requireTests - Require test files for new code (default: false)
#   .api.baseUrl        - API URL for smoke tests
#   .api.healthEndpoint - Health check path (default: /api/v1/health)
#   .urls.frontend      - Frontend URL for smoke tests
#
# ============================================================================
# MODULES
# ============================================================================
#   verify/lint.sh  - Linting and auto-fix (run_configured_checks)
#   verify/tests.sh - Test existence + execution (verify_test_files_exist,
#                     run_unit_tests, verify_prd_criteria)
#   verify/api.sh   - API/frontend smoke tests (run_api_smoke_test,
#                     run_frontend_smoke_test)
#
# DEPENDENCIES: Requires utils.sh to be sourced first (for get_config, print_*)
#
# ============================================================================

# Source verification modules
VERIFY_DIR="${RALPH_LIB:-$(dirname "${BASH_SOURCE[0]}")}"
source "$VERIFY_DIR/verify/lint.sh"
source "$VERIFY_DIR/verify/tests.sh"
source "$VERIFY_DIR/verify/api.sh"

run_verification() {
  local story="$1"

  echo ""
  print_info "=== Verification: $story ==="
  echo ""

  # Get story type for targeted checks
  local story_type
  story_type=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .type // "general"' "$RALPH_DIR/prd.json" 2>/dev/null)
  export RALPH_STORY_TYPE="$story_type"

  local failed=0
  local failed_step=""

  # ========================================
  # STEP 1: Run lint checks
  # ========================================
  echo "  [1/5] Running lint checks..."
  if ! run_configured_checks "$story_type"; then
    failed=1
    failed_step="lint"
  fi

  # ========================================
  # STEP 2: Verify tests exist + run them
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [2/5] Running tests..."
    # First check that test files exist for new code
    if ! verify_test_files_exist; then
      failed=1
      failed_step="test files missing"
    elif ! run_unit_tests; then
      failed=1
      failed_step="unit tests"
    fi
  fi

  # ========================================
  # STEP 3: Run PRD test steps
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [3/5] Running PRD test steps..."
    if ! verify_prd_criteria "$story"; then
      failed=1
      failed_step="PRD test steps"
    fi
  fi

  # ========================================
  # STEP 4: API smoke test (if configured)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    if ! run_api_smoke_test "$story"; then
      failed=1
      failed_step="API smoke test"
    fi
  fi

  # ========================================
  # STEP 5: Frontend smoke test (if configured)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    if ! run_frontend_smoke_test "$story"; then
      failed=1
      failed_step="frontend smoke test"
    fi
  fi

  # ========================================
  # Final result
  # ========================================
  echo ""
  if [[ $failed -eq 0 ]]; then
    print_success "=== All verification passed ==="
    return 0
  else
    print_error "=== Verification failed at: $failed_step ==="
    save_failure_context "$story"
    return 1
  fi
}

# ============================================================================
# FAILURE CONTEXT
# ============================================================================
# Accumulates failure history across retries so Claude can identify patterns.
# If the same error appears multiple times, it's likely a structural issue
# (missing prerequisites, wrong approach) not a simple bug.
#
# Output format in .ralph/last_failure.txt:
#   === Attempt 1 failed for STORY-ID ===
#   <verification output>
#   ---
#   === Attempt 2 failed for STORY-ID ===
#   <verification output>
#   ---
#
save_failure_context() {
  local story="$1"
  local context_file="$RALPH_DIR/last_failure.txt"

  # Get current attempt number from prd.json
  local attempt
  attempt=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .retryCount // 1' "$RALPH_DIR/prd.json" 2>/dev/null || echo "1")

  # Append to failure history (not overwrite)
  {
    echo ""
    echo "=== Attempt $attempt failed for $story ==="
    echo ""
    # Include migration failure if present (verification may not have run)
    if [[ -f "$RALPH_DIR/last_migration_failure.log" ]]; then
      echo "--- Migration Error ---"
      tail -30 "$RALPH_DIR/last_migration_failure.log"
      echo ""
    fi
    # Include pre-commit failure if present
    if [[ -f "$RALPH_DIR/last_precommit_failure.log" ]]; then
      echo "--- Pre-commit Error ---"
      tail -30 "$RALPH_DIR/last_precommit_failure.log"
      echo ""
    fi
    # Include verification output (lint, tests, API, etc.)
    if [[ -f "$RALPH_DIR/last_verification.log" ]]; then
      tail -50 "$RALPH_DIR/last_verification.log"
    fi
    echo ""
    echo "---"
  } >> "$context_file"

  # Cap file size - keep last ~200 lines to avoid huge prompts
  if [[ -f "$context_file" ]]; then
    local line_count
    line_count=$(wc -l < "$context_file" | tr -d ' ')
    if [[ $line_count -gt 200 ]]; then
      tail -200 "$context_file" > "$context_file.tmp" && mv "$context_file.tmp" "$context_file"
    fi
  fi

  # Detect structural errors and add actionable suggestions
  _detect_structural_errors "$context_file"
}

# ============================================================================
# STRUCTURAL ERROR DETECTION
# ============================================================================
# Detects error patterns that indicate structural issues (not code bugs).
# These can't be fixed by retrying - they need specific actions like DB reset.
#
_detect_structural_errors() {
  local context_file="$1"
  [[ ! -f "$context_file" ]] && return

  local error_content
  error_content=$(cat "$context_file")

  # Schema/column errors - detect and flag for Claude context
  # Only show if not already detected (avoid duplicate markers on retry)
  if echo "$error_content" | grep -qiE "(column.*does not exist|relation.*does not exist|no such column|unknown column|undefined column)" && \
     ! grep -q ">>> STRUCTURAL ISSUE: Database schema mismatch" "$context_file" 2>/dev/null; then
    echo ""
    print_warning "STRUCTURAL ISSUE DETECTED: Database schema mismatch"
    echo ""
    echo "  The test database is missing columns/tables that the code expects."
    echo "  This usually happens when:"
    echo "    - Migrations were added but test DB wasn't updated"
    echo "    - Models were modified without running migrations"
    echo ""
    echo "  Run pending migrations to fix the schema."
    echo ""

    # Append suggestion to failure context for Claude
    {
      echo ""
      echo ">>> STRUCTURAL ISSUE: Database schema mismatch"
      echo ">>> ACTION NEEDED: Run pending migrations to update the schema"
      echo ">>> This is NOT a code bug - the test DB is missing schema changes"
    } >> "$context_file"
  fi

  # Migration pending errors
  if echo "$error_content" | grep -qiE "(pending migration|migrations are pending|migrate your database|alembic.*head)" && \
     ! grep -q ">>> STRUCTURAL ISSUE: Pending migrations" "$context_file" 2>/dev/null; then
    echo ""
    print_warning "STRUCTURAL ISSUE DETECTED: Pending migrations"
    echo ""
    echo "  Migrations need to be applied before tests can run."
    echo ""
    echo "  SUGGESTED FIX:"
    local migrate_cmd
    migrate_cmd=$(get_config '.migrations.command' "alembic upgrade head")
    echo "    $migrate_cmd"
    echo ""

    {
      echo ""
      echo ">>> STRUCTURAL ISSUE: Pending migrations"
      echo ">>> ACTION NEEDED: Run migrations before retrying"
    } >> "$context_file"
  fi

  # Connection refused - service not running
  if echo "$error_content" | grep -qiE "(connection refused|ECONNREFUSED|could not connect|connection error)" && \
     ! grep -q ">>> STRUCTURAL ISSUE: Service not running" "$context_file" 2>/dev/null; then
    echo ""
    print_warning "STRUCTURAL ISSUE DETECTED: Service not running"
    echo ""
    echo "  A required service (database, API, etc.) is not running."
    echo ""
    echo "  SUGGESTED FIX:"
    local dev_cmd
    dev_cmd=$(get_config '.commands.dev' "docker compose up -d")
    echo "    $dev_cmd"
    echo ""

    {
      echo ""
      echo ">>> STRUCTURAL ISSUE: Service not running"
      echo ">>> ACTION NEEDED: Start required services before retrying"
    } >> "$context_file"
  fi

  # Unrelated test failures — integration tests, auth timeouts, etc.
  if echo "$error_content" | grep -qiE "(AUTHENTICATION REQUIRED|Failed: Timeout.*pytest-timeout)" && \
     ! grep -q ">>> STRUCTURAL ISSUE: Unrelated test failure" "$context_file" 2>/dev/null; then
    echo ""
    print_warning "STRUCTURAL ISSUE DETECTED: Unrelated test failure (auth/timeout)"
    echo ""
    echo "  A test failed due to missing authentication or timeout — not a code bug."
    echo "  Consider scoping testSteps to unit tests only (e.g., pytest tests/unit/ -x)"
    echo ""

    {
      echo ""
      echo ">>> STRUCTURAL ISSUE: Unrelated test failure (auth timeout or missing credentials)"
      echo ">>> ACTION NEEDED: Scope testSteps to unit tests — use 'pytest tests/unit/ -x' instead of 'pytest -x'"
      echo ">>> This is NOT a code bug — an integration test needs live auth credentials"
    } >> "$context_file"
  fi
}
