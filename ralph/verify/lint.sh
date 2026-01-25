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

# Verify lint passes after auto-fix (catch remaining errors that need manual fix)
# Usage: verify_lint [story_type]
verify_lint() {
  local story_type="${1:-general}"
  local failed=0
  local lint_log="$RALPH_DIR/last_lint_failure.log"

  # Clear previous lint failure log
  rm -f "$lint_log"

  # Python: ruff lint check (skip for frontend-only stories)
  if [[ "$story_type" != "frontend" ]]; then
    if command -v ruff &>/dev/null && [[ -f "pyproject.toml" || -f "ruff.toml" ]]; then
      echo -n "    Ruff lint check... "
      if ruff check . --quiet 2>/dev/null; then
        print_success "passed"
      else
        print_error "failed"
        echo ""
        echo "    Lint errors (auto-fix couldn't resolve - Claude should fix these):"
        local lint_output
        lint_output=$(ruff check . 2>/dev/null | head -"$MAX_LINT_ERROR_LINES")
        echo "$lint_output" | sed 's/^/      /'
        {
          echo "Lint errors in root directory:"
          echo "$lint_output"
        } >> "$lint_log"
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
          echo "    Lint errors in $api_dir (auto-fix couldn't resolve - Claude should fix these):"
          local lint_output
          lint_output=$(cd "$api_dir" && ruff check . 2>/dev/null | head -"$MAX_LINT_ERROR_LINES")
          echo "$lint_output" | sed 's/^/      /'
          {
            echo ""
            echo "Lint errors in $api_dir:"
            echo "$lint_output"
          } >> "$lint_log"
          failed=1
        fi
      fi
    done <<< "$api_dirs"
  else
    echo "    Ruff lint check... skipped (frontend story)"
  fi

  # JavaScript/TypeScript: ESLint check (skip for backend-only stories)
  if [[ "$story_type" != "backend" ]]; then
    if [[ -f "package.json" ]] && command -v npx &>/dev/null; then
      if grep -q '"eslint"' package.json 2>/dev/null || [[ -f ".eslintrc.js" ]] || [[ -f "eslint.config.js" ]]; then
        echo -n "    ESLint check... "
        local eslint_output
        if eslint_output=$(npx eslint . 2>&1); then
          print_success "passed"
        else
          # Check if it's real errors or just warnings
          if echo "$eslint_output" | grep -qE "✖ [0-9]+ problems? \([1-9][0-9]* errors?"; then
            print_error "failed"
            echo ""
            echo "    ESLint errors:"
            echo "$eslint_output" | tail -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
            {
              echo ""
              echo "ESLint errors in root:"
              echo "$eslint_output"
            } >> "$lint_log"
            failed=1
          else
            # Warnings only - pass without showing them
            local warning_count
            warning_count=$(echo "$eslint_output" | grep -oE "[0-9]+ warnings?" | head -1 | grep -oE "[0-9]+" || echo "0")
            print_success "passed ($warning_count warnings)"
          fi
        fi
      fi
    fi

    # Check frontend directories (monorepo support)
    local fe_dirs
    fe_dirs=$(get_frontend_dirs)

    while IFS= read -r fe_dir; do
      [[ -z "$fe_dir" ]] && continue
      [[ ! -f "$fe_dir/package.json" ]] && continue
      grep -q '"eslint"' "$fe_dir/package.json" 2>/dev/null || continue

      echo -n "    ESLint check ($fe_dir)... "
      local eslint_output
      if eslint_output=$(cd "$fe_dir" && npx eslint . 2>&1); then
        print_success "passed"
      else
        if echo "$eslint_output" | grep -qE "✖ [0-9]+ problems? \([1-9][0-9]* errors?"; then
          print_error "failed"
          echo ""
          echo "    ESLint errors in $fe_dir:"
          echo "$eslint_output" | tail -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
          {
            echo ""
            echo "ESLint errors in $fe_dir:"
            echo "$eslint_output"
          } >> "$lint_log"
          failed=1
        else
          # Warnings only - pass without showing them
          local warning_count
          warning_count=$(echo "$eslint_output" | grep -oE "[0-9]+ warnings?" | head -1 | grep -oE "[0-9]+" || echo "0")
          print_success "passed ($warning_count warnings)"
        fi
      fi
    done <<< "$fe_dirs"
  else
    echo "    ESLint check... skipped (backend story)"
  fi

  return $failed
}

# Verify TypeScript types compile
verify_typescript() {
  local failed=0
  local ts_log="$RALPH_DIR/last_typescript_failure.log"

  # Clear previous failure log
  rm -f "$ts_log"

  # Check root tsconfig
  if [[ -f "tsconfig.json" ]] && command -v npx &>/dev/null; then
    echo -n "    TypeScript typecheck... "
    local ts_output
    if ts_output=$(npx tsc --noEmit 2>&1); then
      print_success "passed"
    else
      print_error "failed"
      echo ""
      echo "    TypeScript errors:"
      echo "$ts_output" | head -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
      # Save for retry context
      {
        echo "TypeScript errors in root:"
        echo "$ts_output"
      } >> "$ts_log"
      failed=1
    fi
  fi

  # Check frontend directories (monorepo support)
  local fe_dirs
  fe_dirs=$(get_frontend_dirs)

  while IFS= read -r fe_dir; do
    [[ -z "$fe_dir" ]] && continue
    [[ ! -f "$fe_dir/tsconfig.json" ]] && continue

    echo -n "    TypeScript typecheck ($fe_dir)... "
    local ts_output
    if ts_output=$(cd "$fe_dir" && npx tsc --noEmit 2>&1); then
      print_success "passed"
    else
      print_error "failed"
      echo ""
      echo "    TypeScript errors in $fe_dir:"
      echo "$ts_output" | head -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
      # Save for retry context
      {
        echo ""
        echo "TypeScript errors in $fe_dir:"
        echo "$ts_output"
      } >> "$ts_log"
      failed=1
    fi
  done <<< "$fe_dirs"

  return $failed
}

# Verify npm build succeeds (catches bundling/SSR issues)
verify_build() {
  local failed=0
  local build_log="$RALPH_DIR/last_build_failure.log"

  # Clear previous failure log
  rm -f "$build_log"

  # Check root package.json for build script
  if [[ -f "package.json" ]] && grep -q '"build"' package.json 2>/dev/null; then
    echo -n "    npm build... "
    local build_output
    if build_output=$(npm run build 2>&1); then
      print_success "passed"
    else
      print_error "failed"
      echo ""
      echo "    Build errors:"
      echo "$build_output" | tail -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
      # Save for retry context
      {
        echo "Build errors in root:"
        echo "$build_output"
      } >> "$build_log"
      failed=1
    fi
  fi

  # Check frontend directories (monorepo support)
  local fe_dirs
  fe_dirs=$(get_frontend_dirs)

  while IFS= read -r fe_dir; do
    [[ -z "$fe_dir" ]] && continue
    [[ ! -f "$fe_dir/package.json" ]] && continue
    # Skip if no build script
    grep -q '"build"' "$fe_dir/package.json" 2>/dev/null || continue

    echo -n "    npm build ($fe_dir)... "
    local build_output
    if build_output=$(cd "$fe_dir" && npm run build 2>&1); then
      print_success "passed"
    else
      print_error "failed"
      echo ""
      echo "    Build errors in $fe_dir:"
      echo "$build_output" | tail -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
      # Save for retry context
      {
        echo ""
        echo "Build errors in $fe_dir:"
        echo "$build_output"
      } >> "$build_log"
      failed=1
    fi
  done <<< "$fe_dirs"

  return $failed
}

# Verify Go code compiles and passes vet
verify_go() {
  local go_log="$RALPH_DIR/last_go_failure.log"

  # Skip if not a Go project
  [[ ! -f "go.mod" ]] && return 0
  command -v go &>/dev/null || return 0

  # Clear previous failure log
  rm -f "$go_log"

  # Go vet (catches common mistakes)
  echo -n "    Go vet... "
  local vet_output
  if vet_output=$(go vet ./... 2>&1); then
    print_success "passed"
  else
    print_error "failed"
    echo ""
    echo "    Go vet errors:"
    echo "$vet_output" | head -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
    {
      echo "Go vet errors:"
      echo "$vet_output"
    } >> "$go_log"
    return 1
  fi

  # Go build (catches compile errors)
  echo -n "    Go build... "
  local build_output
  if build_output=$(go build ./... 2>&1); then
    print_success "passed"
  else
    print_error "failed"
    echo ""
    echo "    Go build errors:"
    echo "$build_output" | head -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
    {
      echo ""
      echo "Go build errors:"
      echo "$build_output"
    } >> "$go_log"
    return 1
  fi

  return 0
}

# Verify Rust code with clippy
verify_rust() {
  local rust_log="$RALPH_DIR/last_rust_failure.log"

  # Skip if not a Rust project
  [[ ! -f "Cargo.toml" ]] && return 0
  command -v cargo &>/dev/null || return 0

  # Clear previous failure log
  rm -f "$rust_log"

  # Cargo clippy (Rust's official linter - catches more than cargo check)
  echo -n "    Cargo clippy... "
  local clippy_output
  if clippy_output=$(cargo clippy --all-targets --all-features -- -D warnings 2>&1); then
    print_success "passed"
    return 0
  fi

  # Check if clippy is installed
  if echo "$clippy_output" | grep -q "can't find.*clippy"; then
    echo -n "not installed, trying cargo check... "
    if clippy_output=$(cargo check 2>&1); then
      print_success "passed"
      return 0
    fi
  fi

  # Failed
  print_error "failed"
  echo ""
  echo "    Rust errors:"
  echo "$clippy_output" | head -"$MAX_LINT_ERROR_LINES" | sed 's/^/      /'
  {
    echo "Rust errors:"
    echo "$clippy_output"
  } >> "$rust_log"
  return 1
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

# Check if a verification step is enabled in config
# Values: true, false, "final" (only on last story)
check_enabled() {
  local check_name="$1"
  local default="${2:-true}"
  local value
  value=$(get_config ".checks.$check_name" "$default")

  # Handle "final" - only run on last story
  if [[ "$value" == "final" ]]; then
    local remaining
    remaining=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "1")
    [[ "$remaining" -eq 1 ]]
    return
  fi

  [[ "$value" == "true" ]]
}

# Run all checks based on config.json flags and story type
# Usage: run_configured_checks [story_type]
# story_type: "backend", "frontend", or "general" (default)
run_configured_checks() {
  local story_type="${1:-general}"

  # ALWAYS run auto-fix (harmless, just formats code)
  run_auto_fix

  # Lint check - skip irrelevant checks based on story type
  if check_enabled "lint"; then
    if ! verify_lint "$story_type"; then
      return 1
    fi
  fi

  # TypeScript type checking - skip for backend-only stories
  if check_enabled "typecheck"; then
    if [[ "$story_type" == "backend" ]]; then
      echo "    TypeScript typecheck... skipped (backend story)"
    else
      if ! verify_typescript; then
        return 1
      fi
    fi
  fi

  # Build verification - skip frontend build for backend stories
  if check_enabled "build"; then
    if [[ "$story_type" == "backend" ]]; then
      echo "    npm build... skipped (backend story)"
    else
      if ! verify_build; then
        return 1
      fi
    fi
    if ! verify_go; then
      return 1
    fi
    if ! verify_rust; then
      return 1
    fi
  fi

  # FastAPI response model check
  if check_enabled "fastapi" "false"; then
    run_fastapi_response_check
  fi

  # Run pre-commit hooks if available (catches errors before commit attempt)
  run_precommit_hooks

  return 0
}

# Run pre-commit hooks with auto-fix retry logic
run_precommit_hooks() {
  # Skip if pre-commit not available
  command -v pre-commit &>/dev/null || return 0
  [[ -f ".pre-commit-config.yaml" ]] || return 0

  echo -n "    pre-commit hooks... "
  local precommit_log="$RALPH_DIR/last_precommit_failure.log"

  # Helper function: check if pre-commit output has REAL errors
  has_real_errors() {
    local log_file="$1"

    # Check for actual error indicators (not warnings-only)
    if grep -qE "^error:|: error:|Error:|SyntaxError|TypeError|NameError" "$log_file" 2>/dev/null; then
      return 0
    fi

    # Check ESLint output - fail only if errors > 0
    if grep -qE "✖ [0-9]+ problems? \([1-9][0-9]* errors?" "$log_file" 2>/dev/null; then
      return 0
    fi

    # Check ruff output - actual errors have file:line:col: error pattern
    if grep -qE "^[^:]+:[0-9]+:[0-9]+: [EF][0-9]+" "$log_file" 2>/dev/null; then
      return 0
    fi

    return 1
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
      if has_real_errors "$precommit_log"; then
        break  # Real errors exist
      fi

      # Only file modifications - stage and retry
      if [[ $attempt -lt $max_attempts ]]; then
        echo -n "auto-fixing (attempt $attempt)... "
        git add -A 2>/dev/null || true
        ((attempt++))
        continue
      else
        git add -A 2>/dev/null || true
        passed=true
        break
      fi
    else
      if has_real_errors "$precommit_log"; then
        break
      else
        passed=true
        break
      fi
    fi

    ((attempt++))
  done

  if [[ "$passed" == "true" ]]; then
    [[ $attempt -gt 1 ]] && print_success "passed (after auto-fix)" || print_success "passed"
    rm -f "$precommit_log"
    return 0
  else
    print_error "failed"
    echo ""
    echo "    Pre-commit hook errors:"
    grep -E "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems|^[^:]+:[0-9]+:[0-9]+:" "$precommit_log" 2>/dev/null | head -"$MAX_ERROR_PREVIEW_LINES" | sed 's/^/      /'
    if ! grep -qE "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems" "$precommit_log" 2>/dev/null; then
      echo "    Full output:"
      tail -30 "$precommit_log" | sed 's/^/      /'
    fi
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
