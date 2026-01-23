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

  # Determine story type
  local story_type
  story_type=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .type // "frontend"' "$RALPH_DIR/prd.json" 2>/dev/null)

  local has_test_url
  has_test_url=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testUrl // empty' "$RALPH_DIR/prd.json" 2>/dev/null)

  local has_api_endpoints
  has_api_endpoints=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .apiEndpoints[0] // empty' "$RALPH_DIR/prd.json" 2>/dev/null)

  # Auto-detect type if not specified
  if [[ -n "$has_api_endpoints" && -z "$has_test_url" ]]; then
    story_type="backend"
  fi

  local failed=0

  # ========================================
  # STEP 1: Code review (catch issues before running tests)
  # ========================================
  echo "  [1/6] Running code review..."
  if ! run_code_review "$story"; then
    failed=1
  fi

  # ========================================
  # STEP 2: Run configured checks (lint, build, etc.)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [2/6] Running configured checks..."
    if ! run_configured_checks; then
      failed=1
    fi
  fi

  # ========================================
  # STEP 3: Run unit tests
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [3/6] Running unit tests..."
    if ! run_unit_tests; then
      failed=1
    fi
  fi

  # ========================================
  # STEP 4: Run Playwright tests (frontend) or API tests (backend)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    if [[ "$story_type" == "backend" ]]; then
      echo "  [4/6] Running API tests..."
      if ! run_api_validation "$story"; then
        failed=1
      elif ! run_api_error_tests "$story"; then
        # Only run error tests if validation passed
        failed=1
      fi
    else
      echo "  [4/6] Running Playwright tests..."
      if ! run_playwright_tests "$story"; then
        failed=1
      fi
    fi
  fi

  # ========================================
  # STEP 5: Run browser validation (frontend) or API validation (backend)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    if [[ "$story_type" == "backend" ]]; then
      echo "  [5/6] Running API validation..."
      if ! run_api_tests "$story"; then
        failed=1
      fi
    else
      echo "  [5/6] Running browser validation..."
      if ! run_browser_validation "$story"; then
        failed=1
      fi
    fi
  fi

  # ========================================
  # STEP 6: Run PRD test steps
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    echo "  [6/6] Running PRD test steps..."
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
    echo "=== Failure Context for $story ==="
    echo "Timestamp: $(date -Iseconds 2>/dev/null || date)"
    echo ""

    if [[ -f "$RALPH_DIR/last_review_failure.json" ]]; then
      echo "--- Code Review Failure ---"
      echo "Issues found by code review:"
      jq -r '.issues[] | "- [\(.severity)] \(.category): \(.message)\n  File: \(.file // "unknown"):\(.line // "?")\n  Fix: \(.suggestion // "See above")"' "$RALPH_DIR/last_review_failure.json" 2>/dev/null
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_test_failure.log" ]]; then
      echo "--- Test Failure ---"
      tail -50 "$RALPH_DIR/last_test_failure.log"
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_playwright_failure.log" ]]; then
      echo "--- Playwright Failure ---"
      tail -50 "$RALPH_DIR/last_playwright_failure.log"
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_browser_failure.json" ]]; then
      echo "--- Browser Validation Failure ---"
      jq -r '"Errors: " + (.errors | join(", "))' "$RALPH_DIR/last_browser_failure.json" 2>/dev/null
      jq -r '"Console errors: " + (.consoleErrors | join(", "))' "$RALPH_DIR/last_browser_failure.json" 2>/dev/null
      jq -r '"Missing elements: " + (.elementsMissing | join(", "))' "$RALPH_DIR/last_browser_failure.json" 2>/dev/null
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_precommit_failure.log" ]]; then
      echo "--- Pre-commit / Lint Failure ---"
      echo "Fix these lint errors before the story can be completed:"
      echo ""
      # Extract just the error lines (skip the hook names and status lines)
      grep -E "^\s*(error|warning|Error|ARG|F841|B007|SIM|-->)" "$RALPH_DIR/last_precommit_failure.log" | head -50
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_fastapi_response_check.log" ]]; then
      echo "--- FastAPI Response Model Failure ---"
      echo "Add Pydantic response_model to these endpoints for proper Swagger docs:"
      echo ""
      cat "$RALPH_DIR/last_fastapi_response_check.log"
      echo ""
      echo "Fix by adding response_model parameter or return type annotation:"
      echo '  @router.get("/items", response_model=list[ItemSchema])'
      echo "  async def get_items() -> list[ItemSchema]:"
      echo ""
    fi
  } > "$context_file"
}
