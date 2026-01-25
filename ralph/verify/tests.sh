#!/usr/bin/env bash
# shellcheck shell=bash
# tests.sh - Test verification module for ralph

# Check that new/modified source files have corresponding test files
# This catches the case where Claude writes code but forgets tests
verify_test_files_exist() {
  local story_type="${RALPH_STORY_TYPE:-general}"

  # Skip for frontend stories (handled differently with .test.tsx pattern)
  [[ "$story_type" == "frontend" ]] && return 0

  echo -n "    Test files exist for new code... "

  # Get list of modified Python files (excluding tests themselves)
  local modified_files
  modified_files=$(git diff --name-only HEAD~1 2>/dev/null | grep '\.py$' | grep -v 'test_' | grep -v '_test\.py' | grep -v '/tests/' || true)

  # If no Python files modified, skip
  if [[ -z "$modified_files" ]]; then
    print_success "skipped (no new Python files)"
    return 0
  fi

  local missing_tests=()
  local checked=0

  while IFS= read -r src_file; do
    [[ -z "$src_file" ]] && continue
    [[ ! -f "$src_file" ]] && continue

    # Skip __init__.py, migrations, config files
    [[ "$src_file" == *"__init__.py" ]] && continue
    [[ "$src_file" == *"/migrations/"* ]] && continue
    [[ "$src_file" == *"/alembic/"* ]] && continue
    [[ "$src_file" == *"config"* ]] && continue
    [[ "$src_file" == *"settings"* ]] && continue

    ((checked++))

    # Determine expected test file location
    local base_name dir_name test_file
    base_name=$(basename "$src_file" .py)
    dir_name=$(dirname "$src_file")

    # Common patterns: tests/test_foo.py or foo_test.py
    local possible_tests=(
      "$dir_name/tests/test_${base_name}.py"
      "$dir_name/test_${base_name}.py"
      "${dir_name}/tests/${base_name}_test.py"
      "tests/test_${base_name}.py"
      "tests/${base_name}_test.py"
    )

    # Check for backend dir patterns
    local backend_dir
    backend_dir=$(get_config '.directories.backend' "")
    if [[ -n "$backend_dir" ]]; then
      possible_tests+=(
        "$backend_dir/tests/test_${base_name}.py"
        "$backend_dir/tests/${base_name}_test.py"
      )
    fi

    local found=false
    for test_path in "${possible_tests[@]}"; do
      if [[ -f "$test_path" ]]; then
        found=true
        break
      fi
    done

    if [[ "$found" == "false" ]]; then
      missing_tests+=("$src_file")
    fi
  done <<< "$modified_files"

  if [[ ${#missing_tests[@]} -eq 0 ]]; then
    print_success "passed ($checked files checked)"
    return 0
  else
    print_error "missing tests"
    echo ""
    echo "    The following files need test files:"
    for file in "${missing_tests[@]}"; do
      local base_name
      base_name=$(basename "$file" .py)
      echo "      $file → test_${base_name}.py"
    done
    echo ""
    echo "    Create test files for new code before completing the story."

    # Save for failure context
    {
      echo "Missing test files for new code:"
      for file in "${missing_tests[@]}"; do
        echo "  $file"
      done
    } > "$RALPH_DIR/last_test_existence_failure.log"

    return 1
  fi
}

# Run unit tests
run_unit_tests() {
  local log_file
  log_file=$(create_temp_file ".log") || return 1

  # Check if tests should run (supports true, false, "final")
  local test_setting
  test_setting=$(get_config '.checks.test' "")

  # Handle "final" - only run on last story
  if [[ "$test_setting" == "final" ]]; then
    local remaining
    remaining=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "1")
    if [[ "$remaining" -gt 1 ]]; then
      echo "    (tests set to 'final' - will run on last story)"
      return 0
    fi
    # Last story - use testCommand if specified, otherwise auto-detect
    test_setting=$(get_config '.checks.testCommand' "")
  fi

  # Try common test commands
  local test_cmd
  test_cmd="$test_setting"

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
  local prd_failure_log="$RALPH_DIR/last_prd_failure.log"
  log_file=$(create_temp_file ".log") || return 1

  # Clear previous PRD failure log
  rm -f "$prd_failure_log"

  local step_index=0
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

      # Save failure details for retry context
      {
        echo "PRD test step $step_index failed for $story:"
        echo "  Command: $step"
        echo "  Error output:"
        tail -30 "$log_file" | sed 's/^/    /'
        echo ""
      } >> "$prd_failure_log"

      failed=1
    fi
    ((step_index++)) || true
  done <<< "$test_steps"

  rm -f "$log_file"
  return $failed
}
