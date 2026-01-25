#!/usr/bin/env bash
# shellcheck shell=bash
# test.sh - Comprehensive test runner for nightly builds
#
# Runs full test suite + all PRD testSteps from completed stories.
# Use this in nightly CI jobs, not on every PR.

# Run comprehensive tests (for nightly CI)
ralph_test() {
  local mode="${1:-all}"

  echo ""
  print_info "=== Ralph Nightly Test Suite ==="
  echo ""

  local failed=0

  case "$mode" in
    all)
      run_full_test_suite || failed=1
      run_all_prd_tests || failed=1
      ;;
    unit)
      run_full_test_suite || failed=1
      ;;
    prd)
      run_all_prd_tests || failed=1
      ;;
    *)
      echo "Usage: ralph test [all|unit|prd]"
      echo ""
      echo "Modes:"
      echo "  all   - Run unit tests + all PRD testSteps (default)"
      echo "  unit  - Run only unit tests"
      echo "  prd   - Run only PRD testSteps from completed stories"
      return 1
      ;;
  esac

  echo ""
  if [[ $failed -eq 0 ]]; then
    print_success "=== All nightly tests passed ==="
    return 0
  else
    print_error "=== Nightly tests failed ==="
    return 1
  fi
}

# Run the full test suite
run_full_test_suite() {
  echo "--- Unit Tests ---"
  echo ""

  local test_cmd
  test_cmd=$(get_config '.checks.testCommand' "")

  if [[ -z "$test_cmd" ]]; then
    # Auto-detect test command
    if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
      test_cmd="npm test"
    elif [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
      test_cmd="pytest -v"
    elif [[ -f "Cargo.toml" ]]; then
      test_cmd="cargo test"
    elif [[ -f "go.mod" ]]; then
      test_cmd="go test -v ./..."
    else
      print_warning "No test command found, skipping unit tests"
      return 0
    fi
  fi

  echo "Running: $test_cmd"
  echo ""

  local log_file
  log_file=$(mktemp)

  if safe_exec "$test_cmd" "$log_file"; then
    print_success "Unit tests passed"
    rm -f "$log_file"
    return 0
  else
    print_error "Unit tests failed"
    echo ""
    tail -50 "$log_file"
    rm -f "$log_file"
    return 1
  fi
}

# Run all PRD testSteps from all stories (completed and incomplete)
run_all_prd_tests() {
  echo ""
  echo "--- PRD Test Steps ---"
  echo ""

  if [[ ! -f "$RALPH_DIR/prd.json" ]]; then
    print_warning "No PRD found, skipping PRD tests"
    return 0
  fi

  local failed=0
  local total=0
  local passed=0

  # Get all stories
  local stories
  stories=$(jq -r '.stories[].id' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$stories" ]]; then
    echo "No stories found in PRD"
    return 0
  fi

  while IFS= read -r story_id; do
    [[ -z "$story_id" ]] && continue

    local story_title
    story_title=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .title' "$RALPH_DIR/prd.json")

    echo "[$story_id] $story_title"

    local test_steps
    test_steps=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps[]?' "$RALPH_DIR/prd.json" 2>/dev/null)

    if [[ -z "$test_steps" ]]; then
      echo "  (no testSteps)"
      continue
    fi

    while IFS= read -r step; do
      [[ -z "$step" ]] && continue
      ((total++))

      echo -n "  $step... "

      local step_log
      step_log=$(mktemp)
      if safe_exec "$step" "$step_log"; then
        print_success "passed"
        ((passed++))
      else
        print_error "failed"
        ((failed++))
      fi
      rm -f "$step_log"
    done <<< "$test_steps"

    echo ""
  done <<< "$stories"

  echo "PRD Tests: $passed/$total passed"

  [[ $failed -gt 0 ]] && return 1
  return 0
}

# Generate test coverage report
ralph_test_coverage() {
  echo ""
  print_info "=== Test Coverage Report ==="
  echo ""

  # Python coverage
  if [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
    local backend_dir
    backend_dir=$(get_config '.directories.backend' ".")

    echo "Running pytest with coverage..."
    if (cd "$backend_dir" && pytest --cov --cov-report=term-missing 2>/dev/null); then
      return 0
    else
      print_warning "Coverage report failed (pytest-cov may not be installed)"
      return 1
    fi
  fi

  # JS/TS coverage
  if [[ -f "package.json" ]] && grep -q '"test:coverage"' package.json; then
    echo "Running npm test:coverage..."
    npm run test:coverage
    return $?
  fi

  print_warning "No coverage tool detected"
  return 0
}
