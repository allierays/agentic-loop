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
#   MIGRATION STORIES (alembic, migrations, models):
#     - Has prerequisites array with DB reset command
#     - Prevents infinite retries on schema mismatch errors
#
# ============================================================================
# AUTO-FIX
# ============================================================================
# When issues are found, Claude is invoked to fix them automatically:
#
#   1. Issues are summarized (e.g., "3x backend: add curl tests")
#   2. Claude receives the PRD + issues + fix rules
#   3. Fixed PRD is validated and saved
#   4. Timestamped backup preserved (prd.json.20240115-143022.bak)
#
# If Claude is unavailable or fix fails, loop continues with warnings.
#
# ============================================================================
# CONFIGURATION
# ============================================================================
#
#   .checks.requireTests  - Warn if no test directory configured
#   .tests.directory      - Where tests live (for requireTests check)
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
    echo "  /idea 'your feature'"
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
    echo "  /idea 'your feature'"
    echo ""
    return 1
  fi

  # Check for stories array
  if ! jq -e '.stories' "$prd_file" >/dev/null 2>&1; then
    print_error "prd.json is missing 'stories' array."
    echo ""
    echo "Regenerate with: /idea 'your feature'"
    echo ""
    return 1
  fi

  # Check stories is not empty
  local story_count
  story_count=$(jq '.stories | length' "$prd_file" 2>/dev/null || echo "0")
  if [[ "$story_count" == "0" ]]; then
    print_error "prd.json has no stories."
    echo ""
    echo "Regenerate with: /idea 'your feature'"
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
    echo "Fix the PRD or regenerate with: /idea 'your feature'"
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
      echo "  Without tests, Ralph can only verify syntax and API responses."
      echo "  Import errors and integration issues won't be caught."
      echo ""
      echo "  To fix: Add tests, or set in .ralph/config.json:"
      echo "    {\"tests\": {\"directory\": \"src\", \"patterns\": \"*.test.ts\"}}"
      echo "  To silence: {\"checks\": {\"requireTests\": false}}"
      echo ""
    fi
  fi

  # Replace hardcoded paths with config placeholders
  fix_hardcoded_paths "$prd_file" "$config"

  # Validate and fix individual stories
  _validate_and_fix_stories "$prd_file" || return 1

  return 0
}

# ============================================================================
# INTERNAL FUNCTIONS
# ============================================================================

# Validate individual stories and auto-fix with Claude if needed
_validate_and_fix_stories() {
  local prd_file="$1"
  local needs_fix=false
  local issues=""
  local story_count=0

  # Issue counters (bash 3.2 compatible - no associative arrays)
  local cnt_no_tests=0 cnt_backend_curl=0 cnt_backend_contract=0
  local cnt_frontend_tsc=0 cnt_frontend_url=0 cnt_frontend_context=0
  local cnt_auth_security=0 cnt_list_pagination=0 cnt_prose_steps=0
  local cnt_migration_prereq=0 cnt_naming_convention=0

  echo "  Checking test coverage..."

  # Only validate incomplete stories (skip stories that already passed)
  local story_ids
  story_ids=$(jq -r '.stories[] | select(.passes != true) | .id' "$prd_file" 2>/dev/null)

  while IFS= read -r story_id; do
    [[ -z "$story_id" ]] && continue

    local story_issues=""
    local story_type
    story_type=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .type // "unknown"' "$prd_file")
    local story_title
    story_title=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .title // ""' "$prd_file")

    # Check 1: testSteps quality
    local test_steps
    test_steps=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps // [] | join(" ")' "$prd_file")

    if [[ -z "$test_steps" ]]; then
      story_issues+="no testSteps, "
      cnt_no_tests=$((cnt_no_tests + 1))
    else
      # Check test steps are executable commands, not prose
      # Good: "curl -s POST /api/login | jq -e '.token'"
      # Bad: "Verify the user can log in successfully"
      if ! echo "$test_steps" | grep -qE "(curl |npm |pytest|go test|cargo test|mix test|rails test|bundle exec|python |node |sh |bash |\| jq)"; then
        story_issues+="testSteps look like prose (need executable commands), "
        cnt_prose_steps=$((cnt_prose_steps + 1))
      fi

      # Type-specific checks
      if [[ "$story_type" == "backend" ]]; then
        # Backend must have curl, not just npm test/pytest
        if ! echo "$test_steps" | grep -q "curl "; then
          story_issues+="backend needs curl tests, "
          cnt_backend_curl=$((cnt_backend_curl + 1))
        fi
      elif [[ "$story_type" == "frontend" ]]; then
        # Frontend must have tsc or playwright
        if ! echo "$test_steps" | grep -qE "(tsc --noEmit|playwright)"; then
          story_issues+="frontend needs tsc/playwright tests, "
          cnt_frontend_tsc=$((cnt_frontend_tsc + 1))
        fi
      fi
    fi

    # Check 2: Backend needs apiContract
    if [[ "$story_type" == "backend" ]]; then
      local has_contract
      has_contract=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .apiContract // empty' "$prd_file")
      if [[ -z "$has_contract" || "$has_contract" == "null" ]]; then
        story_issues+="missing apiContract, "
        cnt_backend_contract=$((cnt_backend_contract + 1))
      fi
    fi

    # Check 3: Frontend needs testUrl and contextFiles
    if [[ "$story_type" == "frontend" ]]; then
      local has_url
      has_url=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testUrl // empty' "$prd_file")
      if [[ -z "$has_url" || "$has_url" == "null" ]]; then
        story_issues+="missing testUrl, "
        cnt_frontend_url=$((cnt_frontend_url + 1))
      fi

      local context_files
      context_files=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .contextFiles // [] | length' "$prd_file")
      if [[ "$context_files" == "0" ]]; then
        story_issues+="missing contextFiles, "
        cnt_frontend_context=$((cnt_frontend_context + 1))
      fi
    fi

    # Check 4: Auth stories need security criteria
    if echo "$story_title" | grep -qiE "(login|auth|password|register|signup|sign.?up)"; then
      local criteria
      criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
      if ! echo "$criteria" | grep -qiE "(hash|bcrypt|sanitiz|inject|rate.?limit)"; then
        story_issues+="missing security criteria, "
        cnt_auth_security=$((cnt_auth_security + 1))
      fi
    fi

    # Check 5: List endpoints need scale criteria
    # Note: "search" excluded - search endpoints often return single/filtered results
    if echo "$story_title" | grep -qiE "(list|get all|fetch all|index)"; then
      local criteria
      criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
      if ! echo "$criteria" | grep -qiE "(pagina|limit|page=|per.?page)"; then
        story_issues+="missing pagination criteria, "
        cnt_list_pagination=$((cnt_list_pagination + 1))
      fi
    fi

    # Check 6: Migration stories need DB prerequisites
    # If story creates migration files or modifies models, it needs resetDb prerequisite
    local story_files
    story_files=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | (.files.create // []) + (.files.modify // []) | join(" ")' "$prd_file")
    if echo "$story_files" | grep -qiE "(alembic/versions|migrations/|\.migration\.|models\.py|models/|schema\.)"; then
      local has_prereq
      has_prereq=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .prerequisites // [] | length' "$prd_file")
      if [[ "$has_prereq" == "0" ]]; then
        story_issues+="migration story needs prerequisites (DB reset), "
        cnt_migration_prereq=$((cnt_migration_prereq + 1))
      fi
    fi

    # Check 7: Frontend stories consuming APIs need naming convention notes
    # If story is frontend/general AND mentions API/fetch/axios, ensure notes include camelCase guidance
    if [[ "$story_type" == "frontend" || "$story_type" == "general" ]]; then
      local story_desc
      story_desc=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | (.title + " " + (.acceptanceCriteria // [] | join(" ")) + " " + (.notes // ""))' "$prd_file")
      if echo "$story_desc" | grep -qiE "(api|fetch|axios|endpoint|backend|response)"; then
        local story_notes
        story_notes=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .notes // ""' "$prd_file")
        if ! echo "$story_notes" | grep -qiE "(camelCase|snake_case|naming)"; then
          story_issues+="API consumer needs camelCase transformation note, "
          cnt_naming_convention=$((cnt_naming_convention + 1))
        fi
      fi
    fi

    # Track this story if it has issues
    if [[ -n "$story_issues" ]]; then
      needs_fix=true
      story_count=$((story_count + 1))
      issues+="$story_id: ${story_issues%%, }
"
    fi
  done <<< "$story_ids"

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
    [[ $cnt_auth_security -gt 0 ]] && echo "    ${cnt_auth_security}x auth: add security criteria"
    [[ $cnt_list_pagination -gt 0 ]] && echo "    ${cnt_list_pagination}x list: add pagination"
    [[ $cnt_migration_prereq -gt 0 ]] && echo "    ${cnt_migration_prereq}x migration: add prerequisites (DB reset)"
    [[ $cnt_naming_convention -gt 0 ]] && echo "    ${cnt_naming_convention}x API consumer: add camelCase transformation note"

    # Check if Claude is available for auto-fix
    if command -v claude &>/dev/null; then
      _fix_stories_with_claude "$prd_file" "$issues"
    else
      print_warning "Claude CLI not found - run manually to optimize test coverage"
      return 1
    fi
  else
    print_success "Test coverage looks good"
  fi

  return 0
}

# Optimize story test coverage using Claude
_fix_stories_with_claude() {
  local prd_file="$1"
  local issues="$2"

  local fix_prompt="Enhance test coverage for these stories. Output the COMPLETE updated prd.json.

STORIES TO OPTIMIZE:
$issues

RULES:
1. Backend stories MUST have testSteps with curl commands that hit real endpoints
   Example: curl -s -X POST {config.urls.backend}/api/users -d '...' | jq -e '.id'
2. Backend stories MUST have apiContract with endpoint, request, response
3. Frontend stories MUST have testUrl set to {config.urls.frontend}/page
4. Frontend stories MUST have contextFiles array (include idea file path from originalContext)
5. Auth stories MUST have security acceptanceCriteria:
   - Passwords hashed with bcrypt (cost 10+)
   - Passwords NEVER in API responses
   - Rate limiting on login attempts
6. List endpoints MUST have pagination acceptanceCriteria:
   - Returns paginated results (max 100 per page)
   - Accepts ?page=N&limit=N query params
7. Migration stories (creating alembic/versions, migrations/, or modifying models) MUST have prerequisites:
   Example: \"prerequisites\": [{\"name\": \"Reset test DB\", \"command\": \"npm run db:reset:test\", \"when\": \"schema changes\"}]
8. Frontend/general stories that consume APIs MUST have notes about naming conventions:
   Example: \"notes\": \"Transform API responses from snake_case to camelCase. Create typed interfaces with camelCase properties and map: const user = { userName: data.user_name }\"

CURRENT PRD:
$(cat "$prd_file")

Output ONLY the fixed JSON, no explanation. Start with { and end with }."

  local raw_response
  raw_response=$(echo "$fix_prompt" | run_with_timeout "$CODE_REVIEW_TIMEOUT_SECONDS" claude -p 2>/dev/null)

  # Extract JSON from response (Claude often wraps in markdown code fences)
  local fixed_prd
  # First strip markdown code fences if present
  fixed_prd=$(echo "$raw_response" | sed 's/^```json//; s/^```$//' | sed -n '/^[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p' | head -1000)

  # If sed extraction failed, try removing fences and using raw
  if [[ -z "$fixed_prd" ]]; then
    fixed_prd=$(echo "$raw_response" | sed 's/^```json//; s/^```//; s/```$//')
  fi

  # Validate the response is valid JSON with required structure
  if echo "$fixed_prd" | jq -e '.stories' >/dev/null 2>&1; then
    # Timestamped backup (preserves history across multiple fixes)
    local backup_file="${prd_file}.$(date +%Y%m%d-%H%M%S).bak"
    cp "$prd_file" "$backup_file"

    # Write fixed PRD
    echo "$fixed_prd" > "$prd_file"
    print_success "Test coverage optimized (backup at $backup_file)"

    # Re-validate to confirm
    local remaining_issues
    remaining_issues=$(validate_stories_quick "$prd_file")
    if [[ -n "$remaining_issues" ]]; then
      echo "  Some stories may need manual review"
    fi
  else
    print_warning "Could not auto-optimize - continuing with current PRD"
    return 0  # Don't fail, just continue
  fi
}

# Quick validation without auto-fix (for re-checking after fix)
# Returns issues string (empty if all good)
validate_stories_quick() {
  local prd_file="$1"
  local issues=""

  # Only check incomplete stories
  local story_ids
  story_ids=$(jq -r '.stories[] | select(.passes != true) | .id' "$prd_file" 2>/dev/null)

  while IFS= read -r story_id; do
    [[ -z "$story_id" ]] && continue

    local story_type
    story_type=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .type // "unknown"' "$prd_file")
    local story_title
    story_title=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .title // ""' "$prd_file")
    local test_steps
    test_steps=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testSteps // [] | join(" ")' "$prd_file")

    # Check 1: testSteps quality
    if [[ "$story_type" == "backend" ]] && ! echo "$test_steps" | grep -q "curl "; then
      issues+="$story_id: missing curl tests, "
    fi
    if [[ "$story_type" == "frontend" ]] && ! echo "$test_steps" | grep -qE "(tsc --noEmit|playwright)"; then
      issues+="$story_id: missing tsc/playwright tests, "
    fi

    # Check 2: Backend needs apiContract
    if [[ "$story_type" == "backend" ]]; then
      local has_contract
      has_contract=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .apiContract // empty' "$prd_file")
      if [[ -z "$has_contract" || "$has_contract" == "null" ]]; then
        issues+="$story_id: missing apiContract, "
      fi
    fi

    # Check 3: Frontend needs testUrl and contextFiles
    if [[ "$story_type" == "frontend" ]]; then
      local has_url
      has_url=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testUrl // empty' "$prd_file")
      [[ -z "$has_url" || "$has_url" == "null" ]] && issues+="$story_id: missing testUrl, "

      local context_files
      context_files=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .contextFiles // [] | length' "$prd_file")
      [[ "$context_files" == "0" ]] && issues+="$story_id: missing contextFiles, "
    fi

    # Check 4: Auth stories need security criteria
    if echo "$story_title" | grep -qiE "(login|auth|password|register|signup|sign.?up)"; then
      local criteria
      criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
      if ! echo "$criteria" | grep -qiE "(hash|bcrypt|sanitiz|inject|rate.?limit)"; then
        issues+="$story_id: missing security criteria, "
      fi
    fi

    # Check 5: List endpoints need scale criteria
    if echo "$story_title" | grep -qiE "(list|get all|fetch all|index)"; then
      local criteria
      criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
      if ! echo "$criteria" | grep -qiE "(pagina|limit|page=|per.?page)"; then
        issues+="$story_id: missing pagination criteria, "
      fi
    fi

    # Check 6: Migration stories need prerequisites
    local story_files
    story_files=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | (.files.create // []) + (.files.modify // []) | join(" ")' "$prd_file")
    if echo "$story_files" | grep -qiE "(alembic/versions|migrations/|\.migration\.|models\.py|models/|schema\.)"; then
      local has_prereq
      has_prereq=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .prerequisites // [] | length' "$prd_file")
      if [[ "$has_prereq" == "0" ]]; then
        issues+="$story_id: migration needs prerequisites, "
      fi
    fi

    # Check 7: Frontend/general stories consuming APIs need naming convention notes
    if [[ "$story_type" == "frontend" || "$story_type" == "general" ]]; then
      local story_desc
      story_desc=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | (.title + " " + (.acceptanceCriteria // [] | join(" ")))' "$prd_file")
      if echo "$story_desc" | grep -qiE "(api|fetch|axios|endpoint|backend|response)"; then
        local story_notes
        story_notes=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .notes // ""' "$prd_file")
        if ! echo "$story_notes" | grep -qiE "(camelCase|snake_case|naming)"; then
          issues+="$story_id: needs camelCase transformation note, "
        fi
      fi
    fi
  done <<< "$story_ids"

  echo "$issues"
}
