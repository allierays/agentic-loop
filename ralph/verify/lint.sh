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

    # Helper function: check if pre-commit output has REAL errors (not just file modifications or warnings)
    has_real_errors() {
      local log_file="$1"

      # If all "Failed" hooks only have "files were modified" - not real errors
      # Real errors have patterns like: "error:", "Error:", numbered errors "✖ N problems (N errors"
      # But ESLint "0 errors, N warnings" is NOT a real error

      # Check for actual error indicators (not warnings-only)
      if grep -qE "^error:|: error:|Error:|SyntaxError|TypeError|NameError" "$log_file" 2>/dev/null; then
        return 0  # Has real errors
      fi

      # Check ESLint output - fail only if errors > 0
      if grep -qE "✖ [0-9]+ problems? \([1-9][0-9]* errors?" "$log_file" 2>/dev/null; then
        return 0  # Has real ESLint errors
      fi

      # Check ruff output - actual errors have file:line:col: error pattern
      if grep -qE "^[^:]+:[0-9]+:[0-9]+: [EF][0-9]+" "$log_file" 2>/dev/null; then
        return 0  # Has real ruff errors
      fi

      # Check for hooks that failed for reasons OTHER than file modification
      # Get all "Failed" hooks and check if any DON'T have "files were modified"
      local failed_hooks
      failed_hooks=$(grep -B 5 "^- hook id:" "$log_file" | grep -B 1 "Failed" | grep "hook id:" | sed 's/.*hook id: //' 2>/dev/null)

      while IFS= read -r hook_id; do
        [[ -z "$hook_id" ]] && continue
        # Check if this hook's failure section contains "files were modified"
        if ! grep -A 3 "hook id: $hook_id" "$log_file" | grep -q "files were modified"; then
          # This hook failed for a real reason
          return 0
        fi
      done <<< "$failed_hooks"

      return 1  # No real errors found
    }

    # Run pre-commit up to 3 times to handle auto-fix chains
    local max_attempts=3
    local attempt=1
    local passed=false

    while [[ $attempt -le $max_attempts ]]; do
      if pre-commit run --all-files > "$precommit_log" 2>&1; then
        passed=true
        break
      fi

      # Check if failure is due to file modifications (auto-fix)
      if grep -q "files were modified by this hook" "$precommit_log"; then
        # Check if there are also REAL errors (not just file mods)
        if has_real_errors "$precommit_log"; then
          # Real errors exist - fail
          break
        fi

        # Only file modifications - stage and retry
        if [[ $attempt -lt $max_attempts ]]; then
          echo -n "auto-fixing (attempt $attempt)... "
          git add -A 2>/dev/null || true
          ((attempt++))
          continue
        else
          # Max attempts reached, but only file mods - consider it passed
          # Some hooks (like backup-database) always modify files
          echo -n "auto-fix complete... "
          git add -A 2>/dev/null || true
          passed=true
          break
        fi
      else
        # Failed without "files were modified" - check for real errors
        if has_real_errors "$precommit_log"; then
          break  # Real errors
        else
          # No real errors detected (warnings only, etc.)
          passed=true
          break
        fi
      fi

      ((attempt++))
    done

    if [[ "$passed" == "true" ]]; then
      if [[ $attempt -gt 1 ]]; then
        print_success "passed (after auto-fix)"
      else
        print_success "passed"
      fi
      rm -f "$precommit_log"
    else
      print_error "failed"
      echo ""
      echo "    Pre-commit hook errors:"
      # Show actual errors, not just "Failed" status lines
      grep -E "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems|^[^:]+:[0-9]+:[0-9]+:" "$precommit_log" | head -"$MAX_ERROR_PREVIEW_LINES" | sed 's/^/      /'
      # If no errors shown, show more context
      if ! grep -qE "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems" "$precommit_log"; then
        echo "    Full output:"
        tail -30 "$precommit_log" | sed 's/^/      /'
      fi
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
