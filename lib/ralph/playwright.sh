#!/usr/bin/env bash
# playwright.sh - Playwright test integration for ralph

# Ensure Playwright is installed and configured
ensure_playwright() {
  # Check if playwright config exists
  if [[ ! -f "playwright.config.ts" ]] && [[ ! -f "playwright.config.js" ]]; then
    print_info "Playwright not configured, initializing..."

    # Check if npx is available
    if ! command -v npx &>/dev/null; then
      print_error "npx not found - cannot install Playwright"
      return 1
    fi

    # Install Playwright package and browsers
    npm install playwright 2>/dev/null && npx playwright install chromium 2>/dev/null || {
      print_warning "Could not install Playwright - run: npm install playwright && npx playwright install chromium"
    }

    # Create minimal config if it doesn't exist
    if [[ ! -f "playwright.config.ts" ]] && [[ ! -f "playwright.config.js" ]]; then
      print_info "Creating playwright.config.ts..."
      cat > playwright.config.ts << 'EOF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'mobile',
      use: { ...devices['iPhone 13'] },
    },
  ],
});
EOF
    fi

    # Create test directory
    mkdir -p tests/e2e

    print_success "Playwright initialized"
  fi

  return 0
}

# Run Playwright tests for a specific story or all tests
run_playwright_tests() {
  local story="$1"

  # Check if Playwright is enabled in config
  local pw_enabled
  pw_enabled=$(get_config '.playwright.enabled' "true")
  if [[ "$pw_enabled" == "false" ]]; then
    echo "    (Playwright disabled in config, skipping)"
    return 0
  fi

  # Ensure Playwright is set up
  if ! ensure_playwright; then
    return 1
  fi

  # Check if npx is available
  if ! command -v npx &>/dev/null; then
    print_error "npx not found - cannot run Playwright"
    return 1
  fi

  # Get test directory from config or use default
  local test_dir
  test_dir=$(get_config '.playwright.testDir' "tests/e2e")

  # Look for story-specific test file
  local test_file="${test_dir}/${story}.spec.ts"
  local alt_test_file="${test_dir}/${story}.spec.js"

  local log_file
  log_file=$(create_temp_file ".log") || return 1

  echo -n "  Running Playwright tests... "

  if [[ -f "$test_file" ]]; then
    # Run story-specific test
    if npx playwright test "$test_file" --reporter=line > "$log_file" 2>&1; then
      print_success "passed"
      rm -f "$log_file"
      return 0
    fi
  elif [[ -f "$alt_test_file" ]]; then
    # Run story-specific test (JS version)
    if npx playwright test "$alt_test_file" --reporter=line > "$log_file" 2>&1; then
      print_success "passed"
      rm -f "$log_file"
      return 0
    fi
  else
    # No story-specific test - check if e2e was expected
    local e2e_required
    e2e_required=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .e2e // false' "$RALPH_DIR/prd.json" 2>/dev/null)

    if [[ "$e2e_required" == "true" ]]; then
      print_warning "missing (e2e: true but no test file created)"
      rm -f "$log_file"
      return 1  # Fail if e2e was expected but not created
    fi

    # Check if any tests exist to run
    if [[ -z "$(find "$test_dir" -name '*.spec.ts' -o -name '*.spec.js' 2>/dev/null | head -1)" ]]; then
      echo "skipped (not required for this story)"
      rm -f "$log_file"
      return 0
    fi

    # Run all tests
    if npx playwright test --reporter=line > "$log_file" 2>&1; then
      print_success "passed"
      rm -f "$log_file"
      return 0
    fi
  fi

  # Tests failed
  print_error "failed"
  echo ""
  echo "  Playwright output (last $MAX_LOG_LINES lines):"
  tail -"$MAX_LOG_LINES" "$log_file" | sed 's/^/    /'

  # Save failure for context
  cp "$log_file" "$RALPH_DIR/last_playwright_failure.log"

  rm -f "$log_file"
  return 1
}

# Run Playwright with accessibility checks
run_playwright_a11y() {
  local story="$1"
  local url="$2"

  # Check if @axe-core/playwright is available
  if ! npm list @axe-core/playwright &>/dev/null 2>&1; then
    print_info "Installing @axe-core/playwright for accessibility testing..."
    npm install -D @axe-core/playwright 2>/dev/null || {
      print_warning "Could not install axe-core, skipping a11y tests"
      return 0
    }
  fi

  # a11y tests are typically part of the Playwright tests
  # This function can be extended to run standalone a11y audits
  return 0
}

# Run Playwright at specific viewport (for mobile testing)
run_playwright_mobile() {
  local story="$1"

  local log_file
  log_file=$(create_temp_file ".log") || return 1

  echo -n "  Running mobile viewport tests... "

  # Run tests with mobile project
  if npx playwright test --project=mobile --reporter=line > "$log_file" 2>&1; then
    print_success "passed"
    rm -f "$log_file"
    return 0
  else
    print_error "failed"
    echo ""
    echo "  Mobile test output:"
    tail -"$MAX_OUTPUT_PREVIEW_LINES" "$log_file" | sed 's/^/    /'
    rm -f "$log_file"
    return 1
  fi
}
