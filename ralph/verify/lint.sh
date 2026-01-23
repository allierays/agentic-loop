#!/usr/bin/env bash
# shellcheck shell=bash
# lint.sh - Lint and auto-fix verification module for ralph

# Auto-fix lint issues before running checks
run_auto_fix() {
  echo "    Auto-fixing lint issues..."

  # Python: ruff fix (auto-fix what we can)
  if command -v ruff &>/dev/null; then
    ruff check --fix . 2>/dev/null || true
  fi

  # JavaScript/TypeScript: eslint fix (root)
  if [[ -f "package.json" ]] && command -v npx &>/dev/null; then
    if grep -q '"eslint"' package.json 2>/dev/null || [[ -f ".eslintrc.js" ]] || [[ -f "eslint.config.js" ]]; then
      npx eslint --fix . 2>/dev/null || true
    fi
  fi

  # Check frontend directories (monorepo support)
  local fe_dirs
  fe_dirs=$(get_frontend_dirs)

  while IFS= read -r fe_dir; do
    [[ -z "$fe_dir" ]] && continue
    [[ ! -f "$fe_dir/package.json" ]] && continue
    # ESLint fix
    if grep -q '"eslint"' "$fe_dir/package.json" 2>/dev/null; then
      (cd "$fe_dir" && npx eslint --fix . 2>/dev/null) || true
    fi

    # Next.js lint fix
    if grep -q '"next"' "$fe_dir/package.json" 2>/dev/null; then
      (cd "$fe_dir" && npx next lint --fix 2>/dev/null) || true
    fi

    # Prettier fix (common in frontend)
    if grep -q '"prettier"' "$fe_dir/package.json" 2>/dev/null; then
      (cd "$fe_dir" && npx prettier --write . 2>/dev/null) || true
    fi
  done <<< "$fe_dirs"

  # Prettier fix (root - for non-monorepo)
  if [[ -f "package.json" ]] && grep -q '"prettier"' package.json 2>/dev/null; then
    npx prettier --write . 2>/dev/null || true
  fi
}

# Verify lint passes after auto-fix (catch unfixable errors)
verify_lint() {
  local failed=0

  # Python: ruff lint check
  if command -v ruff &>/dev/null && [[ -f "pyproject.toml" || -f "ruff.toml" ]]; then
    echo -n "    Ruff lint check... "
    if ruff check . --quiet 2>/dev/null; then
      print_success "passed"
    else
      print_error "failed"
      echo ""
      echo "    Unfixable lint errors:"
      ruff check . 2>/dev/null | head -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
      failed=1
    fi
  fi

  # Check for monorepo backend directories
  local api_dirs
  api_dirs=$(get_backend_dirs)

  while IFS= read -r api_dir; do
    [[ -z "$api_dir" ]] && continue
    if [[ -f "$api_dir/pyproject.toml" || -f "$api_dir/ruff.toml" ]]; then
      echo -n "    Ruff lint check ($api_dir)... "
      if (cd "$api_dir" && ruff check . --quiet 2>/dev/null); then
        print_success "passed"
      else
        print_error "failed"
        echo ""
        echo "    Unfixable lint errors in $api_dir:"
        (cd "$api_dir" && ruff check . 2>/dev/null) | head -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
        failed=1
      fi
    fi
  done <<< "$api_dirs"

  return $failed
}

# Check FastAPI endpoints have Pydantic response models (for Swagger docs)
run_fastapi_response_check() {
  # Use RALPH_LIB which points to the ralph/ directory
  local check_script="${RALPH_LIB:-$(dirname "${BASH_SOURCE[0]}")/..}/checks/check-fastapi-responses.py"

  # Skip if check script doesn't exist
  [[ ! -f "$check_script" ]] && return 0

  # Find FastAPI directories (check root + backend dirs)
  local fastapi_dirs=()
  local all_dirs=(".")
  while IFS= read -r dir; do
    [[ -n "$dir" ]] && all_dirs+=("$dir")
  done < <(get_backend_dirs)

  for dir in "${all_dirs[@]}"; do
    [[ ! -d "$dir" ]] && continue
    # Check for FastAPI imports
    if grep -rq "from fastapi" "$dir"/*.py 2>/dev/null || \
       grep -rq "from fastapi" "$dir"/**/*.py 2>/dev/null; then
      fastapi_dirs+=("$dir")
    fi
  done

  [[ ${#fastapi_dirs[@]} -eq 0 ]] && return 0

  local failed=0
  for dir in "${fastapi_dirs[@]}"; do
    echo -n "    FastAPI response models ($dir)... "

    local output
    local log_file="$RALPH_DIR/last_fastapi_response_check.log"

    if output=$(python3 "$check_script" "$dir" 2>&1); then
      print_success "passed"
      rm -f "$log_file"
    else
      print_error "failed"
      echo ""
      echo "$output" | head -"$MAX_ERROR_PREVIEW_LINES" | sed 's/^/      /'
      # Save for failure context so Claude can fix
      echo "$output" > "$log_file"
      failed=1
    fi
  done

  return $failed
}

# Run all checks defined in config.json
run_configured_checks() {
  local config="$RALPH_DIR/config.json"

  # ALWAYS run auto-fix and lint verification, even without config.json
  run_auto_fix

  # Verify lint passes after auto-fix (catch unfixable errors)
  if ! verify_lint; then
    return 1
  fi

  # Auto-detect and run FastAPI response model check
  run_fastapi_response_check

  # Run pre-commit hooks if available (catches errors before commit attempt)
  if command -v pre-commit &>/dev/null && [[ -f ".pre-commit-config.yaml" ]]; then
    echo -n "    pre-commit hooks... "
    local precommit_log="$RALPH_DIR/last_precommit_failure.log"

    # First run - let hooks auto-fix files
    if pre-commit run --all-files > "$precommit_log" 2>&1; then
      print_success "passed"
      rm -f "$precommit_log"
    elif grep -q "files were modified by this hook" "$precommit_log"; then
      # Hooks auto-fixed files - stage them and run again
      echo "auto-fixing..."
      git add -A 2>/dev/null || true

      # Second run - should pass now unless there are real errors
      if pre-commit run --all-files > "$precommit_log" 2>&1; then
        print_success "passed (after auto-fix)"
        rm -f "$precommit_log"
      else
        # Still failing - these are real errors
        print_error "failed"
        echo ""
        echo "    Pre-commit hook errors (after auto-fix):"
        grep -A 20 "Failed\|error\|Error" "$precommit_log" | head -"$MAX_ERROR_PREVIEW_LINES" | sed 's/^/      /'
        return 1
      fi
    else
      # First run failed with real errors (not just auto-fix)
      print_error "failed"
      echo ""
      echo "    Pre-commit hook errors:"
      grep -A 20 "Failed\|error\|Error" "$precommit_log" | head -"$MAX_ERROR_PREVIEW_LINES" | sed 's/^/      /'
      return 1
    fi
  fi

  # Config-based checks are optional
  if [[ ! -f "$config" ]]; then
    echo "    (no config.json for additional checks)"
    return 0
  fi

  # Get list of check names (excluding 'test' which we run separately)
  local check_names
  check_names=$(jq -r '.checks | keys[] | select(. != "test")' "$config" 2>/dev/null)

  if [[ -z "$check_names" ]]; then
    echo "    (no additional checks configured)"
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
