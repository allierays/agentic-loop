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
    # Debug: Show which failure logs exist
    echo "Saving failure context..."
    [[ -f "$RALPH_DIR/last_lint_failure.log" ]] && echo "  - Found lint failure log"
    [[ -f "$RALPH_DIR/last_test_failure.log" ]] && echo "  - Found test failure log"
    [[ -f "$RALPH_DIR/last_typescript_failure.log" ]] && echo "  - Found typescript failure log"
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

    if [[ -f "$RALPH_DIR/last_migration_failure.log" ]]; then
      echo "--- Migration Failure ---"
      echo "Database migrations failed. Fix the migration or the code causing it:"
      tail -50 "$RALPH_DIR/last_migration_failure.log"
      echo ""
    fi

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

    if [[ -f "$RALPH_DIR/last_lint_failure.log" ]]; then
      echo "--- Lint Failure ---"
      echo "Fix these lint errors. The auto-fixer couldn't resolve them, but you can:"
      echo ""
      cat "$RALPH_DIR/last_lint_failure.log"
      echo ""
      echo "Common fixes:"
      echo "  - E722 bare except: Change 'except:' to 'except Exception:'"
      echo "  - F401 unused import: Remove the unused import"
      echo "  - F841 unused variable: Remove or use the variable"
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_typescript_failure.log" ]]; then
      echo "--- TypeScript Failure ---"
      echo "Fix these TypeScript type errors:"
      echo ""
      cat "$RALPH_DIR/last_typescript_failure.log"
      echo ""
      echo "Common fixes:"
      echo "  - TS2322: Type mismatch - ensure assigned value matches expected type"
      echo "  - TS2339: Property not found - check spelling or add to interface"
      echo "  - TS2345: Argument type mismatch - cast or fix the argument type"
      echo "  - TS7006: Implicit any - add explicit type annotation"
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_build_failure.log" ]]; then
      echo "--- Build Failure ---"
      echo "Fix these build errors:"
      echo ""
      cat "$RALPH_DIR/last_build_failure.log"
      echo ""
      echo "Common causes:"
      echo "  - Import errors: Check file paths and exports"
      echo "  - SSR issues (Next.js): Use dynamic imports for client-only code"
      echo "  - Missing dependencies: Run npm install"
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_go_failure.log" ]]; then
      echo "--- Go Failure ---"
      echo "Fix these Go errors:"
      echo ""
      cat "$RALPH_DIR/last_go_failure.log"
      echo ""
      echo "Common fixes:"
      echo "  - Unused variable: Remove or use with _ prefix"
      echo "  - Undefined: Check imports and spelling"
      echo "  - Type mismatch: Ensure types align or use type assertion"
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_rust_failure.log" ]]; then
      echo "--- Rust Failure ---"
      echo "Fix these Rust errors:"
      echo ""
      cat "$RALPH_DIR/last_rust_failure.log"
      echo ""
      echo "Common fixes:"
      echo "  - Unused variable: Prefix with _ or remove"
      echo "  - Borrow checker: Check ownership and lifetimes"
      echo "  - Missing trait: Add #[derive(...)] or impl"
      echo ""
    fi

    if [[ -f "$RALPH_DIR/last_precommit_failure.log" ]]; then
      echo "--- Pre-commit / Lint Failure ---"
      echo "Fix these errors before the story can be completed:"
      echo ""
      # Extract actual error lines (not warnings-only or file modification messages)
      grep -E "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems|^[^:]+:[0-9]+:[0-9]+: [EF][0-9]+" "$RALPH_DIR/last_precommit_failure.log" | head -30
      # If no errors shown, show the full log tail
      if ! grep -qE "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems" "$RALPH_DIR/last_precommit_failure.log"; then
        echo "(Full output):"
        tail -40 "$RALPH_DIR/last_precommit_failure.log"
      fi
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
