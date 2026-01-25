#!/usr/bin/env bash
# shellcheck shell=bash
# verify.sh - Lightweight verification for ralph
#
# Philosophy: Claude verifies its own work using MCP browser tools.
# Ralph just runs lint, tests, and testSteps from the PRD.

# Source verification modules
VERIFY_DIR="${RALPH_LIB:-$(dirname "${BASH_SOURCE[0]}")}"
source "$VERIFY_DIR/verify/lint.sh"
source "$VERIFY_DIR/verify/tests.sh"

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

  # ========================================
  # STEP 1: Run lint checks
  # ========================================
  echo "  [1/3] Running lint checks..."
  if ! run_configured_checks "$story_type"; then
    failed=1
  fi

  # ========================================
  # STEP 2: Verify tests exist + run them
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [2/3] Running tests..."
    # First check that test files exist for new code
    if ! verify_test_files_exist; then
      failed=1
    elif ! run_unit_tests; then
      failed=1
    fi
  fi

  # ========================================
  # STEP 3: Run PRD test steps
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [3/3] Running PRD test steps..."
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
