#!/usr/bin/env bash
# browser.sh - Browser validation module for ralph

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

  # Get base URL from config (required for relative URLs)
  local base_url
  base_url=$(get_config '.testUrlBase' "")

  # Check if Docker mode - Playwright needs special handling
  local docker_enabled
  docker_enabled=$(get_config '.docker.enabled' "false")
  if [[ "$docker_enabled" == "true" ]]; then
    echo "    (Docker mode: using curl check - set verification.browserEnabled=false to hide this)"
    # In Docker, fall back to curl unless they've set up remote browser
    local url
    url=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testUrl // empty' "$RALPH_DIR/prd.json" 2>/dev/null)
    if [[ -n "$url" ]]; then
      # Handle relative URLs
      if [[ "$url" =~ ^/ ]]; then
        if [[ -z "$base_url" ]]; then
          print_error "testUrlBase not set in config.json (needed for relative URL: $url)"
          return 1
        fi
        url="${base_url}${url}"
      fi
      return run_curl_check "$url"
    fi
    return 0
  fi

  local url
  url=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testUrl // empty' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$url" ]]; then
    echo "    skipped (no testUrl - infrastructure or backend story)"
    return 0
  fi

  # Handle relative URLs by prepending base URL from config
  if [[ "$url" =~ ^/ ]]; then
    if [[ -z "$base_url" ]]; then
      print_error "testUrlBase not set in config.json (needed for relative URL: $url)"
      return 1
    fi
    url="${base_url}${url}"
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

  # If either is missing, auto-install (Ralph runs autonomously)
  if [[ "$playwright_installed" == "false" ]] || [[ "$browser_installed" == "false" ]]; then
    echo ""
    print_info "    Installing Playwright for browser verification (~150MB)..."
    if npm install playwright &>/dev/null && npx playwright install chromium &>/dev/null; then
      print_success "    Playwright installed!"
    else
      print_warning "    Installation failed, falling back to curl check"
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
  local verify_script="$RALPH_LIB/browser-verify/verify.ts"

  if [[ ! -f "$verify_script" ]]; then
    print_warning "    browser-verify.ts not found, falling back to curl check"
    return run_curl_check "$url"
  fi

  # Check for auth config
  local auth_login=""
  local login_url
  local test_user
  local test_password
  login_url=$(get_config '.auth.loginUrl' "")
  test_user=$(get_config '.auth.testUser' "")
  test_password=$(get_config '.auth.testPassword' "")

  if [[ -n "$login_url" && -n "$test_user" && -n "$test_password" ]]; then
    # Build auth login JSON
    local username_selector
    local password_selector
    local submit_selector
    local success_indicator
    username_selector=$(get_config '.auth.usernameSelector' "input[name='email'], input[name='username'], input[type='email']")
    password_selector=$(get_config '.auth.passwordSelector' "input[name='password'], input[type='password']")
    submit_selector=$(get_config '.auth.submitSelector' "button[type='submit'], input[type='submit']")
    success_indicator=$(get_config '.auth.successIndicator' "")

    auth_login=$(jq -n \
      --arg loginUrl "$login_url" \
      --arg usernameSelector "$username_selector" \
      --arg passwordSelector "$password_selector" \
      --arg submitSelector "$submit_selector" \
      --arg username "$test_user" \
      --arg password "$test_password" \
      --arg successIndicator "$success_indicator" \
      '{
        loginUrl: $loginUrl,
        usernameSelector: $usernameSelector,
        passwordSelector: $passwordSelector,
        submitSelector: $submitSelector,
        username: $username,
        password: $password,
        successIndicator: (if $successIndicator == "" then null else $successIndicator end)
      }')
  fi

  echo "    Running Playwright verification..."

  local result
  local exit_code=0

  # Build the command with optional auth
  local cmd_args=(
    npx tsx "$verify_script" "$url"
    --selectors "$selectors"
    --screenshot "$screenshot_path"
    --timeout 30000
  )

  if [[ -n "$auth_login" ]]; then
    cmd_args+=(--auth-login "$auth_login")
  fi

  # Run browser verification with 60s wrapper timeout (in case Playwright hangs)
  result=$(run_with_timeout 60 "${cmd_args[@]}" 2>&1) || exit_code=$?

  # Check for timeout
  if [[ $exit_code -eq 124 ]]; then
    print_error "failed (timed out after 60s)"
    echo "    The page may be stuck loading or the dev server isn't responding."
    echo "    Check: curl -I $url"
    return run_curl_check "$url"
  fi

  # Check if we got any output
  if [[ -z "$result" ]]; then
    print_error "failed (no output from Playwright)"
    echo "    Exit code: $exit_code"
    echo "    This usually means Playwright crashed or isn't installed correctly."
    echo "    Try: npm install playwright && npx playwright install chromium"
    return run_curl_check "$url"
  fi

  # Check if result is valid JSON
  if ! echo "$result" | jq -e . >/dev/null 2>&1; then
    print_error "failed (invalid response)"
    echo "    Raw output:"
    echo "$result" | head -20 | sed 's/^/      /'
    return run_curl_check "$url"
  fi

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
      mobile_result=$(run_with_timeout 60 npx tsx "$verify_script" "$url" \
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
