#!/usr/bin/env bash
# shellcheck shell=bash
# verify.sh - Full UAT verification pipeline for ralph
#
# This file orchestrates the verification pipeline by sourcing modular components:
#   - verify/review.sh  - Code review logic
#   - verify/lint.sh    - Auto-fix + lint checks
#   - verify/tests.sh   - Unit tests + PRD criteria
#   - verify/browser.sh - Browser validation

# Validate required source files exist before sourcing
if [[ ! -f "$RALPH_LIB/playwright.sh" ]]; then
  echo "Error: Missing $RALPH_LIB/playwright.sh" >&2
  exit 1
fi
if [[ ! -f "$RALPH_LIB/api.sh" ]]; then
  echo "Error: Missing $RALPH_LIB/api.sh" >&2
  exit 1
fi

# Source verification modules
source "$RALPH_LIB/playwright.sh"
source "$RALPH_LIB/api.sh"

# Determine the directory where this script lives
VERIFY_DIR="${RALPH_LIB:-$(dirname "${BASH_SOURCE[0]}")}"

# Source modular verification components
source "$VERIFY_DIR/verify/review.sh"
source "$VERIFY_DIR/verify/lint.sh"
source "$VERIFY_DIR/verify/tests.sh"
source "$VERIFY_DIR/verify/browser.sh"

run_verification() {
  local story="$1"

  echo ""
  print_info "=== Verification: $story ==="
  echo ""

  # Clear old failure logs (so smart-skip logic uses fresh state)
  rm -f "$RALPH_DIR/last_precommit_failure.log" \
        "$RALPH_DIR/last_test_failure.log" \
        "$RALPH_DIR/last_review_failure.json" 2>/dev/null

  # Check for fast mode
  local fast_mode="${RALPH_FAST_MODE:-false}"
  if [[ "$fast_mode" == "true" ]]; then
    echo "  (fast mode - skipping code review)"
  fi

  # Determine story type (single jq call for all story info)
  local story_json
  story_json=$(jq --arg id "$story" '.stories[] | select(.id==$id)' "$RALPH_DIR/prd.json" 2>/dev/null)

  local story_type has_test_url has_api_endpoints
  story_type=$(echo "$story_json" | jq -r '.type // "frontend"')
  has_test_url=$(echo "$story_json" | jq -r '.testUrl // empty')
  has_api_endpoints=$(echo "$story_json" | jq -r '.apiEndpoints[0] // empty')

  # Auto-detect type if not specified
  if [[ -n "$has_api_endpoints" && -z "$has_test_url" ]]; then
    story_type="backend"
  fi

  local failed=0
  local lint_failed=0
  local test_failed=0

  # ========================================
  # STEP 1: Code review (skip in fast mode or if last failure was lint/test)
  # ========================================
  local skip_review=false
  if [[ "$fast_mode" == "true" ]]; then
    skip_review=true
  elif [[ -f "$RALPH_DIR/last_precommit_failure.log" ]] || [[ -f "$RALPH_DIR/last_test_failure.log" ]]; then
    # Skip review if last failure was lint/test - review won't help
    skip_review=true
    echo "  [1/5] Skipping code review (last failure was lint/test)"
  fi

  if [[ "$skip_review" == "false" ]]; then
    echo "  [1/5] Running code review..."
    if ! run_code_review "$story"; then
      failed=1
    fi
  fi

  # ========================================
  # STEP 2+3: Run lint and tests IN PARALLEL
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [2/5] Running lint + tests (parallel)..."

    # Create temp files for results
    local lint_log test_log
    lint_log=$(mktemp)
    test_log=$(mktemp)

    # Run lint in background
    (run_configured_checks > "$lint_log" 2>&1; echo $? > "${lint_log}.exit") &
    local lint_pid=$!

    # Run tests in background
    (run_unit_tests > "$test_log" 2>&1; echo $? > "${test_log}.exit") &
    local test_pid=$!

    # Wait for both
    wait $lint_pid 2>/dev/null
    wait $test_pid 2>/dev/null

    # Check results
    lint_failed=$(cat "${lint_log}.exit" 2>/dev/null || echo "1")
    test_failed=$(cat "${test_log}.exit" 2>/dev/null || echo "1")

    # Show lint output
    echo "    Lint:"
    cat "$lint_log" | sed 's/^/      /'

    # Show test output
    echo "    Tests:"
    cat "$test_log" | sed 's/^/      /'

    # Cleanup
    rm -f "$lint_log" "${lint_log}.exit" "$test_log" "${test_log}.exit"

    if [[ "$lint_failed" != "0" ]] || [[ "$test_failed" != "0" ]]; then
      failed=1
    fi
  fi

  # ========================================
  # STEP 3: Run Playwright tests (frontend) or API tests (backend)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    if [[ "$story_type" == "backend" ]]; then
      echo "  [3/5] Running API tests..."
      if ! run_api_validation "$story"; then
        failed=1
      elif ! run_api_error_tests "$story"; then
        failed=1
      fi
    else
      echo "  [3/5] Running Playwright tests..."
      if ! run_playwright_tests "$story"; then
        failed=1
      fi
    fi
  fi

  # ========================================
  # STEP 4: Run browser validation (frontend) or API validation (backend)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    if [[ "$story_type" == "backend" ]]; then
      echo "  [4/5] Running API validation..."
      if ! run_api_tests "$story"; then
        failed=1
      fi
    else
      echo "  [4/5] Running browser validation..."
      if ! run_browser_validation "$story"; then
        failed=1
      fi
    fi
  fi

  # ========================================
  # STEP 5: Run PRD test steps
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [5/5] Running PRD test steps..."
    if ! verify_prd_criteria "$story"; then
      failed=1
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
    print_error "=== Verification failed ==="
    # Save failure context for next iteration
    save_failure_context "$story"
    return 1
  fi
}

# Save failure context for next iteration
save_failure_context() {
  local story="$1"
  local context_file="$RALPH_DIR/last_failure.txt"

  {
    echo "=== Verification failed for $story ==="
    echo ""
    # Just include the verification output - Claude can figure out what went wrong
    if [[ -f "$RALPH_DIR/last_verification.log" ]]; then
      tail -100 "$RALPH_DIR/last_verification.log"
    fi
  } > "$context_file"
}
