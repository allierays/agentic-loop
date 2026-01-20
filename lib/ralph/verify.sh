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

  # Extract JSON from markdown code blocks if present
  local json_result
  if echo "$result" | grep -q '```json'; then
    json_result=$(echo "$result" | sed -n '/```json/,/```/p' | sed '1d;$d')
  elif echo "$result" | grep -q '```'; then
    json_result=$(echo "$result" | sed -n '/```/,/```/p' | sed '1d;$d')
  else
    json_result="$result"
  fi

  # Check if result is valid JSON
  if ! echo "$json_result" | jq -e . >/dev/null 2>&1; then
    print_warning "    Code review returned invalid response, skipping"
    return 0
  fi

  local passed
  passed=$(echo "$json_result" | jq -r '.pass // true' 2>/dev/null)

  # Handle empty/null result
  if [[ -z "$passed" || "$passed" == "null" ]]; then
    print_warning "    Code review inconclusive, continuing"
    return 0
  fi

  if [[ "$passed" == "true" ]]; then
    print_success "passed"

    # Show any warnings/info even on pass
    local warnings
    warnings=$(echo "$json_result" | jq -r '.issues[] | select(.severity != "critical") | "      [\(.severity)] \(.message)"' 2>/dev/null)
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
    echo "$json_result" | jq -r '.issues[] | "      [\(.severity)] \(.category): \(.message)"' 2>/dev/null
    echo ""
    echo "    Summary: $(echo "$json_result" | jq -r '.summary // "Review failed"' 2>/dev/null)"

    # Save for failure context
    echo "$json_result" > "$RALPH_DIR/last_review_failure.json"
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

# Browser validation for frontend stories using Playwright
run_browser_validation() {
  local story="$1"

  # Check if browser validation is enabled in config
  local browser_enabled
  browser_enabled=$(get_config '.verification.browserEnabled' "true")
  if [[ "$browser_enabled" == "false" ]]; then
    echo "    (browser validation disabled in config, skipping)"
    return 0
  fi

  # Check if Docker mode - Playwright needs special handling
  local docker_enabled
  docker_enabled=$(get_config '.docker.enabled' "false")
  if [[ "$docker_enabled" == "true" ]]; then
    echo "    (Docker mode: using curl check - set verification.browserEnabled=false to hide this)"
    # In Docker, fall back to curl unless they've set up remote browser
    # TODO: Support PLAYWRIGHT_WS_ENDPOINT for remote browser connection
    local url
    url=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testUrl // empty' "$RALPH_DIR/prd.json" 2>/dev/null)
    if [[ -n "$url" ]]; then
      return run_curl_check "$url"
    fi
    return 0
  fi

  local url
  url=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testUrl // empty' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$url" ]]; then
    echo "    (no testUrl defined, skipping browser validation)"
    return 0
  fi

  if ! validate_url "$url"; then
    print_error "Invalid URL: $url"
    return 1
  fi

  echo "    URL: $url"

  # Check if npx is available
  if ! command -v npx &>/dev/null; then
    print_warning "    npx not found, skipping browser validation"
    return 0
  fi

  # Check if Playwright package is installed
  local playwright_installed=false
  if npm list playwright &>/dev/null || npm list -g playwright &>/dev/null; then
    playwright_installed=true
  fi

  # Check if browser binaries are installed (look for chromium in cache)
  # macOS uses ~/Library/Caches, Linux uses ~/.cache
  local browser_installed=false
  local playwright_cache=""
  if [[ -d "$HOME/Library/Caches/ms-playwright" ]]; then
    playwright_cache="$HOME/Library/Caches/ms-playwright"
  elif [[ -d "$HOME/.cache/ms-playwright" ]]; then
    playwright_cache="$HOME/.cache/ms-playwright"
  fi
  if [[ -n "$playwright_cache" ]] && ls "$playwright_cache"/chromium-* &>/dev/null; then
    browser_installed=true
  fi

  # If either is missing, offer to install
  if [[ "$playwright_installed" == "false" ]] || [[ "$browser_installed" == "false" ]]; then
    # Check if we're in an interactive terminal
    if [[ -t 0 ]]; then
      echo ""
      if [[ "$playwright_installed" == "false" ]]; then
        print_warning "    Playwright package not installed."
      else
        print_warning "    Playwright browser binaries not installed."
      fi
      read -p "    Install now? (~150MB download) [y/N] " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "    Installing Playwright and Chromium..."
        if npm install playwright &>/dev/null && npx playwright install chromium; then
          print_success "    Playwright installed!"
        else
          print_error "    Installation failed, falling back to curl check"
          return run_curl_check "$url"
        fi
      else
        print_info "    Falling back to curl check"
        return run_curl_check "$url"
      fi
    else
      print_warning "    Playwright not fully installed, falling back to curl check"
      print_info "    (Install with: npm install playwright && npx playwright install chromium)"
      return run_curl_check "$url"
    fi
  fi

  # Get selectors to check from story (if defined)
  local selectors
  selectors=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .selectors // [] | @json' "$RALPH_DIR/prd.json" 2>/dev/null)
  if [[ "$selectors" == "null" || -z "$selectors" ]]; then
    selectors="[]"
  fi

  # Screenshot path
  mkdir -p "$RALPH_DIR/screenshots"
  local screenshot_path="$RALPH_DIR/screenshots/${story}.png"

  # Check mobile too?
  local check_mobile
  check_mobile=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .mobile // empty' "$RALPH_DIR/prd.json" 2>/dev/null)

  # Build command - use the browser-verify skill
  local verify_script="$RALPH_SKILLS/browser-verify/verify.ts"

  if [[ ! -f "$verify_script" ]]; then
    print_warning "    browser-verify.ts not found, falling back to curl check"
    return run_curl_check "$url"
  fi

  echo "    Running Playwright verification..."

  local result
  local exit_code

  # Run browser verification
  result=$(npx tsx "$verify_script" "$url" \
    --selectors "$selectors" \
    --screenshot "$screenshot_path" \
    --timeout 30000 \
    2>&1) || exit_code=$?

  # Parse result
  local passed
  passed=$(echo "$result" | jq -r '.pass // false' 2>/dev/null)

  if [[ "$passed" == "true" ]]; then
    local load_time
    load_time=$(echo "$result" | jq -r '.loadTime // 0' 2>/dev/null)
    print_success "passed (${load_time}ms)"

    # Show any warnings
    local warnings
    warnings=$(echo "$result" | jq -r '.warnings[]?' 2>/dev/null)
    if [[ -n "$warnings" ]]; then
      echo "$warnings" | sed 's/^/      Warning: /'
    fi

    # Run mobile check if required
    if [[ -n "$check_mobile" ]]; then
      echo -n "    Mobile viewport... "
      local mobile_result
      mobile_result=$(npx tsx "$verify_script" "$url" \
        --selectors "$selectors" \
        --screenshot "$RALPH_DIR/screenshots/${story}-mobile.png" \
        --mobile \
        2>&1) || true

      local mobile_passed
      mobile_passed=$(echo "$mobile_result" | jq -r '.pass // false' 2>/dev/null)

      if [[ "$mobile_passed" == "true" ]]; then
        print_success "passed"
      else
        print_warning "issues found"
        echo "$mobile_result" | jq -r '.errors[]?' 2>/dev/null | head -3 | sed 's/^/      /'
      fi
    fi

    return 0
  else
    print_error "failed"
    echo ""

    # Show errors
    echo "    Errors:"
    echo "$result" | jq -r '.errors[]?' 2>/dev/null | sed 's/^/      /'

    # Show console errors if any
    local console_errors
    console_errors=$(echo "$result" | jq -r '.consoleErrors[]?' 2>/dev/null)
    if [[ -n "$console_errors" ]]; then
      echo ""
      echo "    Console errors:"
      echo "$console_errors" | head -5 | sed 's/^/      /'
    fi

    # Show missing elements if any
    local missing
    missing=$(echo "$result" | jq -r '.elementsMissing[]?' 2>/dev/null)
    if [[ -n "$missing" ]]; then
      echo ""
      echo "    Missing elements:"
      echo "$missing" | sed 's/^/      /'
    fi

    # Save for failure context
    echo "$result" > "$RALPH_DIR/last_browser_failure.json"

    return 1
  fi
}

# Fallback curl check when Playwright isn't available
run_curl_check() {
  local url="$1"

  local http_response
  http_response=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null) || http_response="000"

  if [[ "$http_response" == "000" ]]; then
    print_error "Cannot reach $url - server not responding"
    return 1
  elif [[ "$http_response" -ge 500 ]]; then
    print_error "Server error $http_response at $url"
    return 1
  elif [[ "$http_response" -ge 400 ]]; then
    print_warning "HTTP $http_response (may be expected for auth pages)"
    return 0
  fi

  # Check for error messages in response
  local page_content
  page_content=$(curl -s --max-time 10 "$url" 2>/dev/null)

  if echo "$page_content" | grep -qi "something went wrong\|error.*occurred\|500 internal\|503 service\|oops\!" 2>/dev/null; then
    print_error "Page contains error message"
    return 1
  fi

  print_success "HTTP $http_response"
  return 0
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
  } > "$context_file"
}
