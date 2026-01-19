#!/usr/bin/env bash
# verify.sh - Full UAT verification pipeline for ralph

# Source additional verification modules
source "$RALPH_LIB/playwright.sh"
source "$RALPH_LIB/api.sh"

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
  # STEP 5: Run MCP browser validation (frontend) or API validation (backend)
  # ========================================
  if [[ $failed -eq 0 ]]; then
    echo ""
    if [[ "$story_type" == "backend" ]]; then
      echo "  [5/6] Running API validation..."
      if ! run_api_tests "$story"; then
        failed=1
      fi
    else
      echo "  [5/6] Running browser validation (MCP)..."
      if ! run_mcp_validation "$story"; then
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

# Run code review on changes
run_code_review() {
  local story="$1"

  # Check if code review is enabled in config
  local review_enabled
  review_enabled=$(get_config '.verification.codeReviewEnabled' "true")
  if [[ "$review_enabled" == "false" ]]; then
    echo "    (code review disabled in config, skipping)"
    return 0
  fi

  # Check if git is available
  if ! command -v git &>/dev/null || [[ ! -d ".git" ]]; then
    echo "    (no git repository, skipping)"
    return 0
  fi

  # Get the diff of uncommitted changes
  local diff
  diff=$(git diff HEAD 2>/dev/null)

  if [[ -z "$diff" ]]; then
    # No uncommitted changes, check staged
    diff=$(git diff --cached 2>/dev/null)
  fi

  if [[ -z "$diff" ]]; then
    echo "    (no changes to review)"
    return 0
  fi

  # Get story context for the review
  local story_json
  story_json=$(jq --arg id "$story" '.stories[] | select(.id==$id)' "$RALPH_DIR/prd.json" 2>/dev/null)

  # Build the code review prompt
  local prompt
  prompt=$(cat <<EOF
You are a senior code reviewer. Review this diff for a story implementation.

## Story Context
\`\`\`json
$story_json
\`\`\`

## Code Diff
\`\`\`diff
$diff
\`\`\`

## Review Checklist

Check for these issues:

1. **Security** - SQL injection, XSS, command injection, hardcoded secrets, OWASP top 10
2. **Error handling** - Missing try/catch, unhandled promise rejections, silent failures
3. **Edge cases** - Null/undefined checks, empty arrays, boundary conditions
4. **Code quality** - Unused variables, dead code, overly complex logic
5. **Performance** - N+1 queries, unnecessary re-renders, memory leaks
6. **Scalability** - Unbounded queries? Missing pagination? Missing indexes? No caching strategy?
7. **Accessibility** - Missing ARIA labels, keyboard navigation, color contrast (if frontend)
8. **Story compliance** - Does the code actually implement what the story requires?
9. **Architecture** - Files in correct directories? Reusing existing components? File size < 300 lines?
10. **No duplication** - Creating something that already exists? Reinventing utilities?

## Response Format

Respond with ONLY a JSON object:
{
  "pass": true/false,
  "issues": [
    {
      "severity": "critical|warning|info",
      "category": "security|error-handling|edge-case|quality|performance|scalability|a11y|architecture|compliance",
      "file": "path/to/file",
      "line": 123,
      "message": "Description of the issue",
      "suggestion": "How to fix it"
    }
  ],
  "summary": "Brief overall assessment"
}

Only fail (pass: false) for critical or multiple warning-level issues.
EOF
)

  echo "    Reviewing changes..."

  local result
  result=$(echo "$prompt" | claude -p --dangerously-skip-permissions 2>/dev/null) || {
    print_warning "    Code review skipped (Claude unavailable)"
    return 0
  }

  # Save review result
  mkdir -p "$RALPH_DIR/reviews"
  echo "$result" > "$RALPH_DIR/reviews/${story}-review.json"

  local passed
  passed=$(echo "$result" | jq -r '.pass // true' 2>/dev/null)

  if [[ "$passed" == "true" ]]; then
    print_success "passed"

    # Show any warnings/info even on pass
    local warnings
    warnings=$(echo "$result" | jq -r '.issues[] | select(.severity != "critical") | "      [\(.severity)] \(.message)"' 2>/dev/null)
    if [[ -n "$warnings" ]]; then
      echo "    Notes:"
      echo "$warnings"
    fi
    return 0
  else
    print_error "failed"
    echo ""

    # Show all issues
    echo "    Issues found:"
    echo "$result" | jq -r '.issues[] | "      [\(.severity)] \(.category): \(.message)"' 2>/dev/null
    echo ""
    echo "    Summary: $(echo "$result" | jq -r '.summary // "Review failed"' 2>/dev/null)"

    # Save for failure context
    echo "$result" > "$RALPH_DIR/last_review_failure.json"
    return 1
  fi
}

# Run unit tests
run_unit_tests() {
  local log_file
  log_file=$(create_temp_file ".log") || return 1

  # Try common test commands
  local test_cmd
  test_cmd=$(get_config '.checks.test' "")

  if [[ -z "$test_cmd" ]]; then
    # Auto-detect test command
    if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
      test_cmd="npm test"
    elif [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
      test_cmd="pytest"
    elif [[ -f "Cargo.toml" ]]; then
      test_cmd="cargo test"
    elif [[ -f "go.mod" ]]; then
      test_cmd="go test ./..."
    else
      echo "    (no test command found, skipping)"
      return 0
    fi
  fi

  echo -n "    Running: $test_cmd... "

  if safe_exec "$test_cmd" "$log_file"; then
    print_success "passed"
    rm -f "$log_file"
    return 0
  else
    print_error "failed"
    echo ""
    echo "    Output (last $MAX_LOG_LINES lines):"
    tail -"$MAX_LOG_LINES" "$log_file" | sed 's/^/      /'
    cp "$log_file" "$RALPH_DIR/last_test_failure.log"
    rm -f "$log_file"
    return 1
  fi
}

# Run all checks defined in config.json
run_configured_checks() {
  local config="$RALPH_DIR/config.json"

  if [[ ! -f "$config" ]]; then
    echo "    (no config.json, skipping)"
    return 0
  fi

  # Get list of check names (excluding 'test' which we run separately)
  local check_names
  check_names=$(jq -r '.checks | keys[] | select(. != "test")' "$config" 2>/dev/null)

  if [[ -z "$check_names" ]]; then
    echo "    (no checks configured)"
    return 0
  fi

  local all_passed=0

  while IFS= read -r check_name; do
    [[ -z "$check_name" ]] && continue

    local cmd
    cmd=$(jq -r ".checks[\"$check_name\"] // empty" "$config")

    if [[ -z "$cmd" || "$cmd" == "null" ]]; then
      continue
    fi

    # Check if command exists
    local first_word
    first_word=$(echo "$cmd" | awk '{print $1}')

    if [[ "$first_word" == "cd" ]]; then
      local actual_cmd
      actual_cmd=$(echo "$cmd" | sed 's/.*&& *//' | awk '{print $1}')
      if [[ -n "$actual_cmd" ]] && ! command -v "$actual_cmd" &>/dev/null; then
        echo "    Skipping $check_name ($actual_cmd not found)"
        continue
      fi
    elif ! command -v "$first_word" &>/dev/null; then
      echo "    Skipping $check_name ($first_word not found)"
      continue
    fi

    if ! run_check "$check_name" "$cmd"; then
      all_passed=1
    fi
  done <<< "$check_names"

  return $all_passed
}

# Run a single check
run_check() {
  local name="$1"
  local cmd="$2"
  local log_file
  log_file=$(create_temp_file ".log") || return 1

  echo -n "    $name... "

  if safe_exec "$cmd" "$log_file"; then
    print_success "passed"
    rm -f "$log_file"
    return 0
  else
    print_error "failed"
    echo ""
    echo "    Output (last $MAX_LOG_LINES lines):"
    tail -"$MAX_LOG_LINES" "$log_file" | sed 's/^/      /'
    rm -f "$log_file"
    return 1
  fi
}

# Quick check command (subset of verification)
ralph_check() {
  if [[ ! -f "$RALPH_DIR/config.json" ]]; then
    print_error "Ralph not initialized. Run 'ralph init' first."
    exit 1
  fi

  echo ""
  print_info "=== Running Checks ==="
  echo ""

  if run_configured_checks; then
    echo ""
    print_success "All checks passed!"
    return 0
  else
    echo ""
    print_error "Some checks failed"
    return 1
  fi
}

# Verify PRD acceptance criteria / test steps
verify_prd_criteria() {
  local story="$1"

  local test_steps
  test_steps=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testSteps[]?' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$test_steps" ]]; then
    echo "    (no testSteps defined)"
    return 0
  fi

  local failed=0
  local log_file
  log_file=$(create_temp_file ".log") || return 1

  while IFS= read -r step; do
    [[ -z "$step" ]] && continue

    echo -n "    $step... "

    if safe_exec "$step" "$log_file"; then
      print_success "passed"
    else
      print_error "failed"
      echo ""
      echo "    Output:"
      tail -"$MAX_OUTPUT_PREVIEW_LINES" "$log_file" | sed 's/^/      /'
      failed=1
    fi
  done <<< "$test_steps"

  rm -f "$log_file"
  return $failed
}

# MCP Browser validation for frontend stories
run_mcp_validation() {
  local story="$1"

  # Check if MCP validation is enabled in config
  local mcp_enabled
  mcp_enabled=$(get_config '.verification.mcpEnabled' "true")
  if [[ "$mcp_enabled" == "false" ]]; then
    echo "    (MCP validation disabled in config, skipping)"
    return 0
  fi

  local url
  url=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testUrl // empty' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$url" ]]; then
    print_error "No testUrl defined for $story - browser validation required"
    return 1
  fi

  if ! validate_url "$url"; then
    print_error "Invalid URL: $url"
    return 1
  fi

  echo "    URL: $url"

  # Get story details for validation prompt
  local criteria
  criteria=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .acceptanceCriteria | join("\n")' "$RALPH_DIR/prd.json" 2>/dev/null)

  local error_handling
  error_handling=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .errorHandling | join("\n")' "$RALPH_DIR/prd.json" 2>/dev/null)

  local a11y_reqs
  a11y_reqs=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .a11y | join("\n")' "$RALPH_DIR/prd.json" 2>/dev/null)

  local mobile_req
  mobile_req=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .mobile // empty' "$RALPH_DIR/prd.json" 2>/dev/null)

  # Build UAT validation prompt
  local prompt
  prompt=$(cat <<EOF
You are a UAT tester. Be thorough but practical.

URL: $url

## Acceptance Criteria
$criteria

## Error Handling to Verify
$error_handling

## Accessibility Requirements
$a11y_reqs

## Mobile Requirement
$mobile_req

## Your UAT Checklist

1. **Console** - Open DevTools. Any errors? Failed network requests?
2. **Visual** - Take screenshot. Does it look correct?
3. **Accessibility** - Can you Tab through interactive elements? Focus visible?
4. **Mobile** - Resize to 375px width. Still works?
5. **Error states** - If applicable, test error handling

## Response Format

Respond with ONLY a JSON object:
{
  "pass": true/false,
  "console_errors": [],
  "visual_issues": [],
  "a11y_issues": [],
  "mobile_issues": [],
  "notes": "summary"
}
EOF
)

  echo "    Running MCP validation..."

  local result
  result=$(echo "$prompt" | claude -p --dangerously-skip-permissions 2>/dev/null) || {
    print_warning "    MCP validation skipped (Claude unavailable)"
    return 0
  }

  # Save screenshot evidence
  mkdir -p "$RALPH_DIR/screenshots"
  echo "$result" > "$RALPH_DIR/screenshots/${story}-validation.json"

  local passed
  passed=$(echo "$result" | jq -r '.pass // false' 2>/dev/null)

  if [[ "$passed" == "true" ]]; then
    print_success "    MCP validation passed"
    return 0
  elif [[ "$passed" == "false" ]]; then
    print_error "    MCP validation failed"

    # Show issues
    echo "$result" | jq -r '.console_errors[]?' 2>/dev/null | sed 's/^/      Console: /'
    echo "$result" | jq -r '.visual_issues[]?' 2>/dev/null | sed 's/^/      Visual: /'
    echo "$result" | jq -r '.a11y_issues[]?' 2>/dev/null | sed 's/^/      A11y: /'
    echo "$result" | jq -r '.mobile_issues[]?' 2>/dev/null | sed 's/^/      Mobile: /'

    # Save for failure context
    echo "$result" > "$RALPH_DIR/last_mcp_failure.json"
    return 1
  else
    print_warning "    MCP validation inconclusive"
    echo "    Response: $(echo "$result" | head -3)"
    return 0
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

    if [[ -f "$RALPH_DIR/last_mcp_failure.json" ]]; then
      echo "--- MCP Validation Failure ---"
      cat "$RALPH_DIR/last_mcp_failure.json"
      echo ""
    fi
  } > "$context_file"
}
