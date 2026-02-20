#!/usr/bin/env bash
# shellcheck shell=bash
#
# prd-check.sh - PRD validation and optimization for Ralph
#
# ============================================================================
# OVERVIEW
# ============================================================================
# Validates PRD structure and story quality BEFORE the loop starts. Catches
# issues early (missing test steps, vague requirements) rather than failing
# 50+ times during execution.
#
# This runs once at loop startup, not after each story.
#
# ============================================================================
# WHAT IT CHECKS
# ============================================================================
#
# Structure validation:
#   - Valid JSON syntax
#   - Has .feature.name
#   - Has .stories array (non-empty)
#   - Each story has id and title
#   - Initializes passes=false for new stories
#
# Story quality checks (per story type):
#
#   ALL STORIES:
#     - Has testSteps (not empty)
#     - testSteps are executable commands, not prose
#       Good: "curl -s POST /api/login | jq -e '.token'"
#       Bad:  "Verify the user can log in"
#
#   BACKEND STORIES:
#     - Has curl commands in testSteps (not just "npm test")
#     - Has apiContract with endpoint, request, response
#
#   FRONTEND STORIES:
#     - Has tsc or playwright in testSteps
#     - Has testUrl for browser verification
#     - Has contextFiles (design specs, etc.)
#
#   AUTH STORIES (login, register, password):
#     - Has security criteria (bcrypt, sanitize, rate limit)
#
#   LIST ENDPOINTS (get all, index):
#     - Has pagination criteria (limit, page params)
#
#   CUSTOM CHECKS (.ralph/checks/prd/):
#     - User-provided scripts that receive story JSON on stdin
#     - Output issue descriptions to stdout (one per line)
#     - Excluded from auto-fix (reported for manual review)
#
# API configuration validation:
#   - If api.baseUrl configured, checks health endpoint is reachable
#   - Warns if default /health returns 404 (misconfigured healthEndpoint)
#   - Catches endpoint mismatches before loop starts
#
# ============================================================================
# AUTO-FIX
# ============================================================================
# When issues are found, a two-tier fix runs automatically:
#
#   Tier 1 — Mechanical fixes (instant, no LLM):
#     - Missing mcp on frontend → ["playwright", "devtools"]
#     - Bare pytest → prefixed with detected runner (uv/poetry/pipenv)
#     - Missing camelCase note → standard text appended to .notes
#     - Server-only testSteps → offline fallback appended
#
#   Tier 2 — Parallel Claude subagents (one per story, concurrent):
#     - For issues needing creative input (apiContract, prose testSteps, etc.)
#     - Each story gets a small prompt with just its JSON + specific issues
#     - All stories fix in parallel (wall-clock = time for 1 story)
#     - Results merged back via update_json; failures left unchanged
#
#   Timestamped backup preserved before any modifications.
#
# If Claude is unavailable or fix fails, loop continues with warnings.
#
# ============================================================================
# CONFIGURATION
# ============================================================================
#
#   .checks.requireTests  - Warn if no test directory configured
#   .tests.directory      - Where tests live (for requireTests check)
#   .api.baseUrl          - API base URL (enables API config validation)
#   .api.healthEndpoint   - Health check path (default: /health, empty to disable)
#   .ralph/checks/prd/check-*     - Project-level custom checks (per-story)
#   .checks.custom.<name>         - Enable/disable individual custom checks
#
# ============================================================================
# USAGE
# ============================================================================
#
#   source ralph/prd-check.sh
#
#   # Full validation with auto-fix
#   validate_prd ".ralph/prd.json"
#
#   # Quick check without auto-fix (returns issues string)
#   issues=$(validate_stories_quick ".ralph/prd.json")
#
# ============================================================================

# Validate PRD structure and story quality
# Returns 0 if valid (possibly after auto-fix), 1 if unrecoverable error
validate_prd() {
  local prd_file="$1"
  local dry_run="${2:-false}"

  # Check file exists
  if [[ ! -f "$prd_file" ]]; then
    print_error "PRD file not found: $prd_file"
    return 1
  fi

  # Check valid JSON
  if ! jq -e . "$prd_file" >/dev/null 2>&1; then
    print_error "prd.json is not valid JSON."
    echo ""
    echo "Fix it manually or regenerate with:"
    echo "  /prd 'your feature'"
    echo ""
    return 1
  fi

  # Check feature.name is set
  local feature_name
  feature_name=$(jq -r '.feature.name // empty' "$prd_file" 2>/dev/null)
  if [[ -z "$feature_name" || "$feature_name" == "null" ]]; then
    print_error "prd.json is missing .feature.name"
    echo ""
    echo "Add a feature name to your PRD or regenerate with:"
    echo "  /prd 'your feature'"
    echo ""
    return 1
  fi

  # Check for stories array
  if ! jq -e '.stories' "$prd_file" >/dev/null 2>&1; then
    print_error "prd.json is missing 'stories' array."
    echo ""
    echo "Regenerate with: /prd 'your feature'"
    echo ""
    return 1
  fi

  # Check stories is not empty
  local story_count
  story_count=$(jq '.stories | length' "$prd_file" 2>/dev/null || echo "0")
  if [[ "$story_count" == "0" ]]; then
    print_error "prd.json has no stories."
    echo ""
    echo "Regenerate with: /prd 'your feature'"
    echo ""
    return 1
  fi

  # Check each story has required fields
  local invalid_stories
  invalid_stories=$(jq -r '.stories[] | select(.id == null or .id == "" or .title == null or .title == "") | .id // "unnamed"' "$prd_file" 2>/dev/null)
  if [[ -n "$invalid_stories" ]]; then
    print_error "Some stories are missing required fields (id, title):"
    echo "$invalid_stories" | head -5
    echo ""
    echo "Fix the PRD or regenerate with: /prd 'your feature'"
    echo ""
    return 1
  fi

  # Check stories have passes field (initialize if missing)
  local missing_passes
  missing_passes=$(jq '[.stories[] | select(.passes == null)] | length' "$prd_file" 2>/dev/null || echo "0")
  if [[ "$missing_passes" != "0" ]]; then
    print_info "Initializing $missing_passes stories with passes=false..."
    update_json "$prd_file" '(.stories[] | select(.passes == null) | .passes) = false'
  fi

  # Check if project has tests (from config)
  local config="$RALPH_DIR/config.json"
  if [[ -f "$config" ]]; then
    local require_tests
    require_tests=$(jq -r '.checks.requireTests // true' "$config" 2>/dev/null)
    local test_dir
    test_dir=$(jq -r '.tests.directory // empty' "$config" 2>/dev/null)

    if [[ "$require_tests" == "true" && -z "$test_dir" ]]; then
      echo ""
      print_warning "No test directory configured in .ralph/config.json"
      echo "  Without tests, Ralph relies on lint, type-checking, and PRD test steps."
      echo "  Consider adding tests or PRD testCommands for better verification."
      echo ""
      echo "  To fix: Add tests, or set in .ralph/config.json:"
      echo "    {\"tests\": {\"directory\": \"src\", \"patterns\": \"*.test.ts\"}}"
      echo "  To silence: {\"checks\": {\"requireTests\": false}}"
      echo ""
    fi
  fi

  # Auto-remove deprecated root-level fields (no longer used, safe to strip)
  local deprecated_fields=""
  local deprecated_keys=("techStack" "globalConstraints" "originalContext" "testing" "architecture" "testUsers")
  for key in "${deprecated_keys[@]}"; do
    if jq -e ".$key" "$prd_file" >/dev/null 2>&1; then
      deprecated_fields+="$key "
    fi
  done
  if [[ -n "$deprecated_fields" ]]; then
    echo ""
    print_info "Removing deprecated root-level fields: $deprecated_fields"
    update_json "$prd_file" \
      'del(.techStack, .globalConstraints, .originalContext, .testing, .architecture, .testUsers)'
  fi

  # Validate API smoke test configuration in background (skip in fast/cached mode)
  # Capture output to a temp file to avoid garbled terminal output
  local api_check_pid="" api_check_output=""
  if [[ "$dry_run" != "true" ]]; then
    api_check_output=$(create_temp_file ".api-check.out")
    _validate_api_config "$config" > "$api_check_output" 2>&1 &
    api_check_pid=$!
  fi

  # Validate batch assignments (warn, don't block)
  local batch_errors batch_rc=0
  batch_errors=$(validate_batch_assignments "$prd_file" 2>/dev/null) || batch_rc=$?
  if [[ $batch_rc -ne 0 && -n "$batch_errors" ]]; then
    echo ""
    print_warning "Batch assignment issues:"
    echo "$batch_errors" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo "    $line"
    done
    echo ""
  fi

  # Replace hardcoded paths with config placeholders
  fix_hardcoded_paths "$prd_file" "$config"

  # Validate and fix individual stories
  # dry_run flag — when "true", report issues but skip auto-fix
  _validate_and_fix_stories "$prd_file" "$dry_run" || return 1

  # Wait for background API health check and print its output
  if [[ -n "$api_check_pid" ]]; then
    wait "$api_check_pid" 2>/dev/null
    [[ -s "$api_check_output" ]] && cat "$api_check_output"
  fi

  return 0
}

# ============================================================================
# INTERNAL FUNCTIONS
# ============================================================================

# Validate API smoke test configuration
# Checks that configured health endpoint is reachable (warns if not)
_validate_api_config() {
  local config="$1"

  [[ ! -f "$config" ]] && return 0

  local base_url
  base_url=$(jq -r '.api.baseUrl // empty' "$config" 2>/dev/null)

  # No API configured, skip
  [[ -z "$base_url" ]] && return 0

  echo "  Validating API configuration..."

  local health_endpoint
  local health_endpoint_raw
  health_endpoint_raw=$(jq -r '.api.healthEndpoint' "$config" 2>/dev/null)

  # If explicitly set to empty string, disable health check
  if [[ "$health_endpoint_raw" == "" ]]; then
    print_info "Health check disabled (healthEndpoint is empty)"
    return 0
  fi

  # If not configured at all (null), warn about the default
  if [[ "$health_endpoint_raw" == "null" ]]; then
    echo ""
    print_warning "No api.healthEndpoint configured - defaulting to /health"
    echo "  If your API uses a different health endpoint, add to .ralph/config.json:"
    echo "    {\"api\": {\"baseUrl\": \"$base_url\", \"healthEndpoint\": \"/your/health/path\"}}"
    echo ""
    health_endpoint="/health"
  else
    health_endpoint="$health_endpoint_raw"
  fi

  # Test the health endpoint
  local url="${base_url}${health_endpoint}"
  local http_code

  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null) || http_code="000"

  if [[ "$http_code" == "000" ]]; then
    print_warning "API not reachable at $base_url (server may not be running yet)"
    return 0
  elif [[ "$http_code" == "404" ]]; then
    echo ""
    print_error "API health endpoint not found: $health_endpoint (HTTP 404)"
    echo ""
    echo "  The configured health endpoint doesn't exist at: $url"
    echo ""
    echo "  Fix in .ralph/config.json:"
    echo "    {\"api\": {\"baseUrl\": \"$base_url\", \"healthEndpoint\": \"/correct/path\"}}"
    echo ""
    echo "  Common health endpoints:"
    echo "    /api/health, /api/v1/health, /healthz, /status, /"
    echo ""
    echo "  Set to empty string to disable health check:"
    echo "    {\"api\": {\"healthEndpoint\": \"\"}}"
    echo ""
    # Don't fail - API tests will fail later with more context
    return 0
  elif [[ "$http_code" =~ ^5 ]]; then
    print_warning "API health check returned error: HTTP $http_code"
    return 0
  else
    print_success "API health check passed: $health_endpoint (HTTP $http_code)"
  fi

  return 0
}

# Check a single story for common issues
# Outputs issue strings to stdout (one per line: "issue description")
# $1: story_id  $2: prd_file
_check_story_issues() {
  local story_id="$1"
  local prd_file="$2"

  local story_type
  story_type=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .type // "unknown"' "$prd_file")
  local story_title
  story_title=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .title // ""' "$prd_file")
  local test_steps
  test_steps=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps // [] | join(" ")' "$prd_file")

  # Backend must have curl tests
  if [[ "$story_type" == "backend" ]] && [[ -n "$test_steps" ]] && ! echo "$test_steps" | grep -q "curl "; then
    echo "backend needs curl tests"
  fi

  # Frontend must have tsc or playwright
  if [[ "$story_type" == "frontend" ]] && [[ -n "$test_steps" ]] && ! echo "$test_steps" | grep -qE "(tsc --noEmit|playwright)"; then
    echo "frontend needs tsc/playwright tests"
  fi

  # Backend needs apiContract
  if [[ "$story_type" == "backend" ]]; then
    local has_contract
    has_contract=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .apiContract // empty' "$prd_file")
    if [[ -z "$has_contract" || "$has_contract" == "null" ]]; then
      echo "missing apiContract"
    fi
  fi

  # Frontend needs testUrl, contextFiles, and mcp
  if [[ "$story_type" == "frontend" ]]; then
    local has_url
    has_url=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testUrl // empty' "$prd_file")
    [[ -z "$has_url" || "$has_url" == "null" ]] && echo "missing testUrl"

    local context_files
    context_files=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .contextFiles // [] | length' "$prd_file")
    [[ "$context_files" == "0" ]] && echo "missing contextFiles"

    local mcp_tools
    mcp_tools=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .mcp // [] | length' "$prd_file")
    [[ "$mcp_tools" == "0" ]] && echo "missing mcp (browser tools)"
  fi

  # Auth stories need security criteria
  if echo "$story_title" | grep -qiE "(login|auth|password|register|signup|sign.?up)"; then
    local criteria
    criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
    if ! echo "$criteria" | grep -qiE "(hash|bcrypt|sanitiz|inject|rate.?limit)"; then
      echo "missing security criteria"
    fi
  fi

  # List endpoints need pagination criteria
  if echo "$story_title" | grep -qiE "(list|get all|fetch all|index)"; then
    local criteria
    criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
    if ! echo "$criteria" | grep -qiE "(pagina|limit|page=|per.?page)"; then
      echo "missing pagination criteria"
    fi
  fi

  # API consumer needs camelCase transformation note
  if [[ "$story_type" == "frontend" || "$story_type" == "general" ]]; then
    local story_desc
    story_desc=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | (.title + " " + (.acceptanceCriteria // [] | join(" ")) + " " + (.notes // ""))' "$prd_file")
    if echo "$story_desc" | grep -qiE "(api|fetch|axios|endpoint|backend|response)"; then
      local story_notes
      story_notes=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .notes // ""' "$prd_file")
      if ! echo "$story_notes" | grep -qiE "(camelCase|snake_case|naming)"; then
        echo "API consumer needs camelCase transformation note"
      fi
    fi
  fi

  # Import-check anti-pattern: python -c "from X import Y" or hasattr()
  if [[ -n "$test_steps" ]] && echo "$test_steps" | grep -qE '(python[3]? -c .*(from |import |hasattr))'; then
    echo "testSteps use import-checks (python -c 'from/import/hasattr') — replace with real behavioral tests"
  fi

  # Frontend stories must include Playwright MCP visual verification guidance in notes
  if [[ "$story_type" == "frontend" ]]; then
    local story_notes
    story_notes=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .notes // ""' "$prd_file")
    if ! echo "$story_notes" | grep -qiE "(playwright.*mcp|mcp.*playwright|visual.*verif|screenshot|navigate.*screenshot)"; then
      echo "frontend notes should include Playwright MCP visual verification guidance"
    fi
  fi

  # All testSteps are server-dependent
  if [[ -n "$test_steps" ]]; then
    local has_offline=false has_server=false
    local step_list
    step_list=$(jq -r --arg id "$story_id" \
      '.stories[] | select(.id==$id) | .testSteps[]?' "$prd_file")

    while IFS= read -r single_step; do
      [[ -z "$single_step" ]] && continue
      if echo "$single_step" | grep -qE "^(curl |wget |http )"; then
        has_server=true
      else
        has_offline=true
      fi
    done <<< "$step_list"

    if [[ "$has_server" == "true" && "$has_offline" == "false" ]]; then
      echo "all testSteps need a live server (add offline test: npm test, tsc --noEmit, pytest)"
    fi
  fi
}

# Validate individual stories and auto-fix with Claude if needed
# $1: prd_file  $2: optional "dry_run" — when "true", report issues but skip auto-fix
_validate_and_fix_stories() {
  local prd_file="$1"
  local dry_run="${2:-false}"
  local needs_fix=false
  local issues=""
  local story_count=0

  # Issue counters (bash 3.2 compatible - no associative arrays)
  local cnt_no_tests=0 cnt_backend_curl=0 cnt_backend_contract=0
  local cnt_frontend_tsc=0 cnt_frontend_url=0 cnt_frontend_context=0 cnt_frontend_mcp=0
  local cnt_auth_security=0 cnt_list_pagination=0 cnt_prose_steps=0
  local cnt_naming_convention=0 cnt_bare_pytest=0 cnt_bare_python=0
  local cnt_server_only=0
  local cnt_custom=0
  local cnt_import_check=0
  local cnt_playwright_notes=0

  echo "  Checking test coverage..."

  # Truncate custom check log per validation pass (name says "last", keep only current run)
  : > "$RALPH_DIR/last_custom_check.log"

  # Only validate incomplete stories (skip stories that already passed)
  local story_ids
  story_ids=$(jq -r '.stories[] | select(.passes != true) | .id' "$prd_file" 2>/dev/null)

  while IFS= read -r story_id; do
    [[ -z "$story_id" ]] && continue

    local story_issues=""
    local test_steps
    test_steps=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps // [] | join(" ")' "$prd_file")

    # Checks unique to full validation: empty testSteps, prose detection, bare pytest
    if [[ -z "$test_steps" ]]; then
      story_issues+="no testSteps, "
      cnt_no_tests=$((cnt_no_tests + 1))
    else
      if ! echo "$test_steps" | grep -qE "(curl |npm |pytest|go test|cargo test|mix test|rails test|bundle exec|python |node |sh |bash |\| jq)"; then
        story_issues+="testSteps look like prose (need executable commands), "
        cnt_prose_steps=$((cnt_prose_steps + 1))
      fi

      local py_runner
      py_runner=$(detect_python_runner ".")
      if [[ -n "$py_runner" ]]; then
        if echo "$test_steps" | grep -qE '(^|[; ])pytest ' && ! echo "$test_steps" | grep -qE "(uv run|poetry run|pipenv run) pytest"; then
          story_issues+="use '$py_runner pytest' not bare 'pytest', "
          cnt_bare_pytest=$((cnt_bare_pytest + 1))
        fi
      fi

      # Check for bare 'python' (fails on macOS which only has python3)
      if echo "$test_steps" | grep -qE '(^|[;&| ])python ' && ! echo "$test_steps" | grep -qE "(uv run|poetry run|pipenv run|python3) "; then
        if [[ -n "$py_runner" ]]; then
          story_issues+="use '$py_runner python' not bare 'python', "
        else
          story_issues+="use 'python3' not bare 'python' (macOS has no 'python'), "
        fi
        cnt_bare_python=$((cnt_bare_python + 1))
      fi
    fi

    # Shared checks (same as validate_stories_quick)
    local shared_issues
    shared_issues=$(_check_story_issues "$story_id" "$prd_file")
    while IFS= read -r issue; do
      [[ -z "$issue" ]] && continue
      story_issues+="$issue, "
      # Count by category for summary display
      case "$issue" in
        "backend needs curl tests") cnt_backend_curl=$((cnt_backend_curl + 1)) ;;
        "frontend needs tsc/playwright tests") cnt_frontend_tsc=$((cnt_frontend_tsc + 1)) ;;
        "missing apiContract") cnt_backend_contract=$((cnt_backend_contract + 1)) ;;
        "missing testUrl") cnt_frontend_url=$((cnt_frontend_url + 1)) ;;
        "missing contextFiles") cnt_frontend_context=$((cnt_frontend_context + 1)) ;;
        "missing mcp (browser tools)") cnt_frontend_mcp=$((cnt_frontend_mcp + 1)) ;;
        "missing security criteria") cnt_auth_security=$((cnt_auth_security + 1)) ;;
        "missing pagination criteria") cnt_list_pagination=$((cnt_list_pagination + 1)) ;;
        "API consumer needs camelCase transformation note") cnt_naming_convention=$((cnt_naming_convention + 1)) ;;
        "all testSteps need a live server"*) cnt_server_only=$((cnt_server_only + 1)) ;;
        "testSteps use import-checks"*) cnt_import_check=$((cnt_import_check + 1)) ;;
        "frontend notes should include Playwright"*) cnt_playwright_notes=$((cnt_playwright_notes + 1)) ;;
      esac
    done <<< "$shared_issues"

    # Snapshot built-in issues before custom checks append
    local builtin_story_issues="$story_issues"

    # User-defined custom checks (.ralph/checks/prd/)
    if [[ -d ".ralph/checks/prd" ]]; then
      local story_json
      story_json=$(jq --arg id "$story_id" '.stories[] | select(.id==$id)' "$prd_file")
      local custom_output
      custom_output=$(_run_custom_prd_checks "$story_id" "$prd_file" "$story_json")
      if [[ -n "$custom_output" ]]; then
        story_issues+="$custom_output"
        cnt_custom=$((cnt_custom + 1))
      fi
    fi

    # Track this story if it has issues
    if [[ -n "$story_issues" ]]; then
      needs_fix=true
      story_count=$((story_count + 1))
      # Only include built-in issues in auto-fix context
      # Custom issues are user-defined rules that Claude auto-fix can't meaningfully address
      if [[ -n "$builtin_story_issues" ]]; then
        issues+="$story_id: ${builtin_story_issues%%, }
"
      fi
    fi
  done <<< "$story_ids"

  # Global check: if any frontend stories exist, at least one story should have E2E tests
  local has_frontend_stories has_e2e_story
  has_frontend_stories=$(jq -r '[.stories[] | select(.type == "frontend")] | length' "$prd_file" 2>/dev/null)
  has_e2e_story=$(jq -r '[.stories[] | select(.testing.types[]? == "e2e")] | length' "$prd_file" 2>/dev/null)
  if [[ "$has_frontend_stories" -gt 0 && "$has_e2e_story" == "0" ]]; then
    echo ""
    print_warning "No E2E story found — frontend features should have at least one Playwright E2E story"
    echo "  Add a final story with testing.types: [\"e2e\"] and Playwright testSteps"
    echo ""
  fi

  # If issues found, show summary and attempt fix
  if [[ "$needs_fix" == "true" ]]; then
    echo "  Optimizing test coverage for $story_count stories..."

    # Print compact summary (only non-zero counts)
    [[ $cnt_no_tests -gt 0 ]] && echo "    ${cnt_no_tests}x missing testSteps"
    [[ $cnt_prose_steps -gt 0 ]] && echo "    ${cnt_prose_steps}x testSteps are prose (need executable commands)"
    [[ $cnt_backend_curl -gt 0 ]] && echo "    ${cnt_backend_curl}x backend: add curl tests"
    [[ $cnt_backend_contract -gt 0 ]] && echo "    ${cnt_backend_contract}x backend: add apiContract"
    [[ $cnt_frontend_tsc -gt 0 ]] && echo "    ${cnt_frontend_tsc}x frontend: add tsc/playwright"
    [[ $cnt_frontend_url -gt 0 ]] && echo "    ${cnt_frontend_url}x frontend: add testUrl"
    [[ $cnt_frontend_context -gt 0 ]] && echo "    ${cnt_frontend_context}x frontend: add contextFiles"
    [[ $cnt_frontend_mcp -gt 0 ]] && echo "    ${cnt_frontend_mcp}x frontend: add mcp browser tools"
    [[ $cnt_auth_security -gt 0 ]] && echo "    ${cnt_auth_security}x auth: add security criteria"
    [[ $cnt_list_pagination -gt 0 ]] && echo "    ${cnt_list_pagination}x list: add pagination"
    [[ $cnt_naming_convention -gt 0 ]] && echo "    ${cnt_naming_convention}x API consumer: add camelCase transformation note"
    [[ $cnt_bare_pytest -gt 0 ]] && echo "    ${cnt_bare_pytest}x use '${py_runner:-python3} pytest' not bare 'pytest'"
    [[ $cnt_bare_python -gt 0 ]] && echo "    ${cnt_bare_python}x use 'python3' not bare 'python' (macOS compatibility)"
    [[ $cnt_server_only -gt 0 ]] && echo "    ${cnt_server_only}x all testSteps need live server (add offline fallback)"
    [[ $cnt_import_check -gt 0 ]] && echo "    ${cnt_import_check}x testSteps use import-checks (replace with real tests)"
    [[ $cnt_playwright_notes -gt 0 ]] && echo "    ${cnt_playwright_notes}x frontend: add Playwright MCP visual verification to notes"
    [[ $cnt_custom -gt 0 ]] && echo "    ${cnt_custom} stories with custom check issues"

    # Skip auto-fix in dry-run mode
    if [[ "$dry_run" == "true" ]]; then
      return 0
    fi

    # Create backup before any modifications
    local backup_file="${prd_file}.$(date +%Y%m%d-%H%M%S).bak"
    cp "$prd_file" "$backup_file"

    # Tier 1: Instant mechanical fixes (no LLM needed)
    _apply_mechanical_fixes "$prd_file"

    # Re-check what's still broken after mechanical fixes
    # validate_stories_quick returns "ID: issue, ID: issue, ..." on one line
    # Group into one line per story for _fix_stories_parallel
    local remaining_raw
    remaining_raw=$(validate_stories_quick "$prd_file")
    local remaining_grouped=""
    [[ -n "$remaining_raw" ]] && remaining_grouped=$(_group_issues_by_story "$remaining_raw")

    if [[ -n "$remaining_grouped" ]]; then
      # Tier 2: Parallel Claude subagents for creative fixes
      if command -v claude &>/dev/null; then
        _fix_stories_parallel "$prd_file" "$remaining_grouped" "$backup_file"
      else
        print_warning "Claude CLI not found - mechanical fixes applied, but some stories need manual review"
        echo "  Backup at: $backup_file"
        return 0
      fi
    else
      print_success "All issues resolved with mechanical fixes (backup at $backup_file)"
    fi
  else
    print_success "Test coverage looks good"
  fi

  return 0
}

# Run user-defined custom PRD checks for a story
# Stdin to script: full story JSON | $1: story_id | $2: prd_file
# Output: issues on stdout (empty = no issues)
_run_custom_prd_checks() {
  local story_id="$1"
  local prd_file="$2"
  local story_json="$3"
  local custom_issues=""
  local custom_log="$RALPH_DIR/last_custom_check.log"

  local check_dir=".ralph/checks/prd"
  [[ ! -d "$check_dir" ]] && return 0

  for check_script in "$check_dir"/check-*; do
    [[ ! -f "$check_script" || ! -x "$check_script" ]] && continue

    local check_key
    check_key=$(basename "$check_script")
    check_key="${check_key%.*}"
    # Read directly instead of get_config — jq's // operator treats false as falsy
    local enabled="true"
    if [[ -f "$RALPH_DIR/config.json" ]]; then
      local raw
      raw=$(jq -r --arg key "$check_key" '.checks.custom[$key]' "$RALPH_DIR/config.json" 2>/dev/null)
      [[ -n "$raw" && "$raw" != "null" ]] && enabled="$raw"
    fi
    [[ "$enabled" == "false" ]] && continue

    # Run check — capture stdout for issues, stderr to log for debugging
    local output=""
    if ! output=$(echo "$story_json" | run_with_timeout 30 "$check_script" "$story_id" "$prd_file" 2>>"$custom_log"); then
      # Script failed to execute — warn, don't silently swallow
      print_warning "Custom check '$check_key' failed for story $story_id (see .ralph/last_custom_check.log)"
    fi

    if [[ -n "$output" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && custom_issues+="${line}, "
      done <<< "$output"
    fi
  done

  echo "$custom_issues"
}

# Group flat "ID: issue, ID: issue, ..." string into one line per story
# Input:  "S1: missing curl tests, S1: missing apiContract, S2: missing testUrl, "
# Output: "S1: missing curl tests, missing apiContract\nS2: missing testUrl"
_group_issues_by_story() {
  local raw="$1"
  # Split on ", " boundaries that precede a story ID pattern (word: )
  # Use awk to accumulate issues per story ID
  echo "$raw" | tr ',' '\n' | sed 's/^ *//' | while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    if [[ "$entry" =~ ^([A-Za-z0-9._-]+):\ (.+) ]]; then
      echo "${BASH_REMATCH[1]}	${BASH_REMATCH[2]}"
    fi
  done | awk -F'\t' '{
    if (seen[$1]) {
      issues[$1] = issues[$1] ", " $2
    } else {
      seen[$1] = 1
      issues[$1] = $2
      order[++n] = $1
    }
  } END {
    for (i = 1; i <= n; i++) {
      print order[i] ": " issues[order[i]]
    }
  }'
}

# Apply instant mechanical fixes using jq (no LLM needed)
# Fixes: missing mcp, bare pytest, bare python (macOS compat), missing camelCase note,
# missing migration prerequisites, server-only testSteps
_apply_mechanical_fixes() {
  local prd_file="$1"
  local fixed=0

  # Detect Python runner once for bare pytest fixes
  local py_runner
  py_runner=$(detect_python_runner ".")

  local story_ids
  story_ids=$(jq -r '.stories[] | select(.passes != true) | .id' "$prd_file" 2>/dev/null)

  while IFS= read -r story_id; do
    [[ -z "$story_id" ]] && continue

    local story_type
    story_type=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .type // "unknown"' "$prd_file")

    # Fix: Frontend missing mcp → set to ["playwright", "devtools"]
    if [[ "$story_type" == "frontend" ]]; then
      local mcp_len
      mcp_len=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .mcp // [] | length' "$prd_file")
      if [[ "$mcp_len" == "0" ]]; then
        update_json "$prd_file" --arg id "$story_id" \
          '(.stories[] | select(.id==$id) | .mcp) = ["playwright", "devtools"]' && fixed=$((fixed + 1))
      fi
    fi

    # Fix: Bare pytest → prefix with detected runner
    if [[ -n "$py_runner" ]]; then
      local test_steps_raw
      test_steps_raw=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps // [] | join("\n")' "$prd_file")
      if echo "$test_steps_raw" | grep -qE '(^|[; ])pytest ' && ! echo "$test_steps_raw" | grep -qE "(uv run|poetry run|pipenv run) pytest"; then
        update_json "$prd_file" --arg id "$story_id" --arg runner "$py_runner" \
          '(.stories[] | select(.id==$id) | .testSteps) |= [.[]? | gsub("(?<pre>^|[; ])pytest "; "\(.pre)\($runner) pytest ")]' && fixed=$((fixed + 1))
      fi
    fi

    # Fix: Bare python → prefix with runner or replace with python3 (macOS compat)
    local test_steps_for_python
    test_steps_for_python=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps // [] | join("\n")' "$prd_file")
    if echo "$test_steps_for_python" | grep -qE '(^|[;&| ])python ' && ! echo "$test_steps_for_python" | grep -qE "(uv run|poetry run|pipenv run|python3) "; then
      if [[ -n "$py_runner" ]]; then
        update_json "$prd_file" --arg id "$story_id" --arg runner "$py_runner" \
          '(.stories[] | select(.id==$id) | .testSteps) |= [.[]? | gsub("(?<pre>^|[;&| ])python "; "\(.pre)\($runner) python ")]' && fixed=$((fixed + 1))
      else
        update_json "$prd_file" --arg id "$story_id" \
          '(.stories[] | select(.id==$id) | .testSteps) |= [.[]? | gsub("(?<pre>^|[;&| ])python "; "\(.pre)python3 ")]' && fixed=$((fixed + 1))
      fi
    fi

    # Fix: Frontend/general API consumer missing camelCase note
    if [[ "$story_type" == "frontend" || "$story_type" == "general" ]]; then
      local story_desc
      story_desc=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | (.title + " " + (.acceptanceCriteria // [] | join(" ")) + " " + (.notes // ""))' "$prd_file")
      if echo "$story_desc" | grep -qiE "(api|fetch|axios|endpoint|backend|response)"; then
        local story_notes
        story_notes=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .notes // ""' "$prd_file")
        if ! echo "$story_notes" | grep -qiE "(camelCase|snake_case|naming)"; then
          local camel_note="Transform API responses from snake_case to camelCase. Create typed interfaces with camelCase properties."
          if [[ -z "$story_notes" ]]; then
            update_json "$prd_file" --arg id "$story_id" --arg note "$camel_note" \
              '(.stories[] | select(.id==$id) | .notes) = $note' && fixed=$((fixed + 1))
          else
            update_json "$prd_file" --arg id "$story_id" --arg note "$camel_note" \
              '(.stories[] | select(.id==$id) | .notes) += (" " + $note)' && fixed=$((fixed + 1))
          fi
        fi
      fi
    fi

    # Fix: All testSteps are server-dependent → append offline test step
    local test_steps
    test_steps=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps // [] | join(" ")' "$prd_file")
    if [[ -n "$test_steps" ]]; then
      local has_offline=false has_server=false
      local step_list
      step_list=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps[]?' "$prd_file")
      while IFS= read -r single_step; do
        [[ -z "$single_step" ]] && continue
        if echo "$single_step" | grep -qE "^(curl |wget |http )"; then
          has_server=true
        else
          has_offline=true
        fi
      done <<< "$step_list"

      if [[ "$has_server" == "true" && "$has_offline" == "false" ]]; then
        # Pick an offline step based on story type and project tooling
        local offline_step="npx tsc --noEmit"
        if [[ "$story_type" == "backend" ]]; then
          if [[ -n "$py_runner" ]]; then
            offline_step="$py_runner pytest tests/unit/"
          elif [[ -f "go.mod" ]]; then
            offline_step="go test ./..."
          else
            offline_step="npm test"
          fi
        fi
        update_json "$prd_file" --arg id "$story_id" --arg step "$offline_step" \
          '(.stories[] | select(.id==$id) | .testSteps) += [$step]' && fixed=$((fixed + 1))
      fi
    fi

  done <<< "$story_ids"

  if [[ $fixed -gt 0 ]]; then
    echo "    Applied $fixed mechanical fixes (no LLM needed)"
  fi

  return 0
}

# Fix stories with remaining issues using parallel Claude subagents (one per story)
# $1: prd_file  $2: newline-separated "story_id: issues" lines  $3: backup file path
_fix_stories_parallel() {
  local prd_file="$1"
  local issues="$2"
  local backup_file="$3"

  # Read config values for context
  local config_file="$RALPH_DIR/config.json"
  local backend_url="" frontend_url=""
  if [[ -f "$config_file" ]]; then
    backend_url=$(jq -r '.urls.backend // .api.baseUrl // "http://localhost:8000"' "$config_file" 2>/dev/null)
    frontend_url=$(jq -r '.urls.frontend // .playwright.baseUrl // "http://localhost:3000"' "$config_file" 2>/dev/null)
  fi

  # Parse issues into per-story fix jobs
  local pids=()
  local story_ids_to_fix=()
  local output_files=()

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local sid="${line%%:*}"
    local story_issues="${line#*: }"
    [[ -z "$sid" || -z "$story_issues" ]] && continue

    # Extract this story's JSON
    local story_json
    story_json=$(jq --arg id "$sid" '.stories[] | select(.id==$id)' "$prd_file" 2>/dev/null)
    [[ -z "$story_json" ]] && continue

    # Build a small per-story prompt
    local prompt_file
    prompt_file=$(create_temp_file ".prompt.txt")
    local output_file
    output_file=$(create_temp_file ".fix.json")

    cat > "$prompt_file" <<PROMPT_EOF
Fix this story's issues. Output ONLY the fixed story JSON object (not the full PRD).

STORY JSON:
$story_json

ISSUES TO FIX:
$story_issues

CONFIG VALUES:
- Backend URL: $backend_url (use as {config.urls.backend} in testSteps)
- Frontend URL: $frontend_url (use as {config.urls.frontend} in testUrl)

RULES:
- Backend stories MUST have testSteps with curl commands hitting real endpoints
  Example: curl -s -X POST {config.urls.backend}/api/users -d '...' | jq -e '.id'
- Backend stories MUST have apiContract with endpoint, request, response
- Frontend stories MUST have testUrl set to {config.urls.frontend}/[page-path]
- Frontend stories MUST have contextFiles array
- Auth stories MUST have security acceptanceCriteria (bcrypt, rate limiting)
- List endpoints MUST have pagination acceptanceCriteria (?page=N&limit=N)
- Stories with only curl testSteps MUST also have an offline test step (npm test, tsc --noEmit, pytest)
- Keep ALL existing fields. Only add/fix what's missing.

Output ONLY the fixed story JSON object. Start with { and end with }.
PROMPT_EOF

    # Background a Claude call for this story
    ( run_with_timeout 60 claude -p < "$prompt_file" > "$output_file" 2>/dev/null ) &
    pids+=($!)
    story_ids_to_fix+=("$sid")
    output_files+=("$output_file")
  done <<< "$issues"

  local job_count=${#pids[@]}
  if [[ $job_count -eq 0 ]]; then
    return 0
  fi

  echo "    Fixing $job_count stories in parallel..."

  # Wait for all background jobs
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null
  done

  # Merge results back into PRD
  local merged=0 failed=0
  for i in "${!story_ids_to_fix[@]}"; do
    local sid="${story_ids_to_fix[$i]}"
    local output_file="${output_files[$i]}"

    [[ ! -s "$output_file" ]] && { failed=$((failed + 1)); continue; }

    # Extract JSON from response (strip markdown fences if present)
    local raw_response
    raw_response=$(cat "$output_file")
    local fixed_story
    fixed_story=$(echo "$raw_response" | sed 's/^```json//; s/^```$//' | sed -n '/^[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p')

    if [[ -z "$fixed_story" ]]; then
      fixed_story=$(echo "$raw_response" | sed 's/^```json//; s/^```//; s/```$//')
    fi

    # Validate it's a valid JSON object with an id field matching this story
    local response_id
    response_id=$(echo "$fixed_story" | jq -r '.id // empty' 2>/dev/null)
    if [[ "$response_id" != "$sid" ]]; then
      # Try to salvage: if valid JSON, force the correct id
      if echo "$fixed_story" | jq -e '.' >/dev/null 2>&1; then
        fixed_story=$(echo "$fixed_story" | jq --arg id "$sid" '.id = $id')
        response_id="$sid"
      else
        failed=$((failed + 1))
        continue
      fi
    fi

    # Merge fixed story back into PRD using update_json
    local fixed_story_escaped
    fixed_story_escaped=$(echo "$fixed_story" | jq -c '.')
    if update_json "$prd_file" --arg id "$sid" --argjson fixed "$fixed_story_escaped" \
      '(.stories[] | select(.id==$id)) = $fixed'; then
      merged=$((merged + 1))
    else
      failed=$((failed + 1))
    fi
  done

  if [[ $merged -gt 0 ]]; then
    print_success "Fixed $merged stories with Claude (backup at $backup_file)"
  fi
  if [[ $failed -gt 0 ]]; then
    print_warning "$failed stories could not be auto-fixed — review with /prd"
  fi

  # Final validation pass
  local remaining_issues
  remaining_issues=$(validate_stories_quick "$prd_file")
  if [[ -n "$remaining_issues" ]]; then
    echo "  Some stories may still need manual review"
  fi
}

# Quick validation without auto-fix (for re-checking after fix)
# Returns issues string (empty if all good)
validate_stories_quick() {
  local prd_file="$1"
  local issues=""

  local story_ids
  story_ids=$(jq -r '.stories[] | select(.passes != true) | .id' "$prd_file" 2>/dev/null)

  while IFS= read -r story_id; do
    [[ -z "$story_id" ]] && continue

    local story_issues
    story_issues=$(_check_story_issues "$story_id" "$prd_file")
    while IFS= read -r issue; do
      [[ -z "$issue" ]] && continue
      issues+="$story_id: $issue, "
    done <<< "$story_issues"
  done <<< "$story_ids"

  echo "$issues"
}

# CLI entry point for on-demand PRD validation
# Usage: ralph prd-check [--dry-run] [prd-file]
ralph_prd_check() {
  local dry_run=false
  local prd_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true; shift ;;
      *) prd_file="$1"; shift ;;
    esac
  done

  prd_file="${prd_file:-$RALPH_DIR/prd.json}"

  if [[ ! -f "$prd_file" ]]; then
    print_error "PRD not found: $prd_file"
    echo "Generate one with: ralph prd  or  /prd"
    return 1
  fi

  echo ""
  print_info "=== PRD Validation ==="
  echo ""

  if [[ "$dry_run" == "true" ]]; then
    # Dry run: validate structure + show issues without auto-fix
    validate_prd "$prd_file" "true"
    local rc=$?
    local remaining
    remaining=$(validate_stories_quick "$prd_file")
    if [[ -n "$remaining" ]]; then
      echo ""
      echo "  Remaining issues:"
      echo "$remaining" | sed 's/^/    /'
    fi
    return $rc
  else
    if validate_prd "$prd_file"; then
      echo ""
      print_success "PRD validation passed!"
      return 0
    else
      echo ""
      print_error "PRD validation failed"
      return 1
    fi
  fi
}
