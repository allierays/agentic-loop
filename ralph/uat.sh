#!/usr/bin/env bash
# shellcheck shell=bash
# uat.sh - UAT Ralph: Autonomous User Acceptance Testing Loop
#
# ============================================================================
# OVERVIEW
# ============================================================================
# UAT Ralph explores the live app via Claude + Playwright MCP, generates a
# test plan, then uses strict TDD (Red-Green) per test case:
#   RED:   Claude writes the test only (no app changes)
#   GREEN: Claude fixes the app only (no test changes)
#
# 3-Phase Flow:
#   Phase 1: DISCOVER + PLAN  — Claude + MCP explores app, generates plan
#   Phase 2: EXECUTE LOOP     — Per test case: RED (test) → GREEN (fix)
#   Phase 3: REPORT           — Summary of findings
#
# ============================================================================
# DEPENDENCIES: Requires utils.sh sourced first (get_config, print_*, etc.)
# ============================================================================

# UAT-specific constants
readonly UAT_DIR="$RALPH_DIR/uat"
readonly UAT_PLAN_FILE="$UAT_DIR/plan.json"
readonly UAT_PROGRESS_FILE="$UAT_DIR/progress.txt"
readonly UAT_FAILURE_FILE="$UAT_DIR/last_failure.txt"
readonly UAT_SCREENSHOTS_DIR="$UAT_DIR/screenshots"

# TDD phases
readonly UAT_PHASE_RED="RED"
readonly UAT_PHASE_GREEN="GREEN"

# Defaults (overridable via config)
readonly DEFAULT_UAT_MAX_ITERATIONS=20
readonly DEFAULT_UAT_MAX_SESSION_SECONDS=600
readonly DEFAULT_UAT_MAX_CASE_RETRIES=5

# Swarm defaults
readonly DEFAULT_UAT_SCOUT_TIMEOUT=120
readonly DEFAULT_UAT_AGENT_TIMEOUT=300
readonly DEFAULT_UAT_MAX_CONCURRENT=6

# Attack vectors for swarm agents
readonly UAT_VECTORS=("happy-path" "chaos" "security")

# ============================================================================
# ENTRY POINT
# ============================================================================

run_uat() {
  local focus=""
  local plan_only=false
  local force_review=false
  local no_fix=false
  local max_iterations=""
  local swarm_mode=false
  local fresh_mode=false
  local quiet_mode
  quiet_mode=$(get_config '.quiet' "false")

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --focus)
        focus="$2"
        shift 2
        ;;
      --plan-only)
        plan_only=true
        shift
        ;;
      --review)
        force_review=true
        shift
        ;;
      --no-fix)
        no_fix=true
        shift
        ;;
      --max)
        max_iterations="$2"
        shift 2
        ;;
      --quiet)
        quiet_mode=true
        shift
        ;;
      --swarm)
        swarm_mode=true
        shift
        ;;
      --fresh)
        fresh_mode=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # Validate prerequisites
  check_dependencies

  # Concurrent execution guard
  _acquire_uat_lock

  # Ensure UAT directory structure
  mkdir -p "$UAT_DIR" "$UAT_SCREENSHOTS_DIR"

  # Banner
  _print_uat_banner

  # Phase 1: Discover + Plan
  if [[ ! -f "$UAT_PLAN_FILE" ]] || [[ "$force_review" == "true" ]] || [[ "$plan_only" == "true" ]]; then
    if [[ -f "$UAT_PLAN_FILE" ]] && [[ "$force_review" == "true" ]]; then
      print_info "Re-reviewing existing plan..."
    else
      echo ""
      print_info "Phase 1: Discovery + Plan Generation"
      echo ""
      local discover_ok=false
      if [[ "$swarm_mode" == "true" ]]; then
        if _swarm_discover_and_plan "$fresh_mode" "$quiet_mode"; then
          discover_ok=true
        else
          print_warning "Swarm discovery failed, falling back to single-session..."
          # Clean up partial swarm artifacts to avoid stale data on next --swarm run
          rm -f "$UAT_DIR"/app-map.json "$UAT_DIR"/findings-*.json
          if _discover_and_plan "$quiet_mode"; then
            discover_ok=true
          fi
        fi
      else
        if _discover_and_plan "$quiet_mode"; then
          discover_ok=true
        fi
      fi
      if [[ "$discover_ok" != "true" ]]; then
        print_error "Discovery failed. Check $UAT_PROGRESS_FILE for details."
        return 1
      fi
    fi

    # Review the plan
    if ! _review_plan; then
      print_info "Plan review cancelled."
      return 0
    fi

    if [[ "$plan_only" == "true" ]]; then
      print_success "Plan generated. Run 'npx agentic-loop uat' to execute."
      return 0
    fi
  else
    local remaining
    remaining=$(jq '[.testCases[] | select(.passes==false)] | length' "$UAT_PLAN_FILE" 2>/dev/null || echo "0")
    print_info "Resuming existing plan ($remaining test cases remaining)"
  fi

  # Phase 2: Execute Loop
  echo ""
  print_info "Phase 2: Execute UAT Loop"
  echo ""
  _run_uat_loop "$focus" "$no_fix" "$max_iterations" "$quiet_mode"
  local loop_exit=$?

  # Phase 3: Report
  _print_report

  return $loop_exit
}

# ============================================================================
# CONCURRENT EXECUTION GUARD
# ============================================================================

_acquire_uat_lock() {
  local lockfile="$RALPH_DIR/.lock"
  if [[ -f "$lockfile" ]]; then
    local pid
    pid=$(cat "$lockfile")
    if kill -0 "$pid" 2>/dev/null; then
      print_error "Another Ralph process is running (PID $pid). Stop it first."
      exit 1
    fi
    rm -f "$lockfile"  # Stale lock
  fi
  echo $$ > "$lockfile"
  # Chain cleanup: lock removal + kill child processes
  # This replaces the trap from ralph.sh, so we handle both concerns
  trap '_uat_cleanup' EXIT
  trap '_uat_interrupt' INT TERM
}

_uat_cleanup() {
  rm -f "$RALPH_DIR/.lock"
}

_uat_interrupt() {
  echo ""
  print_warning "Interrupted. Stopping UAT loop..."
  # Kill all child processes (Claude sessions, test runners)
  kill 0 2>/dev/null || true
  _uat_cleanup
  exit 130
}

# ============================================================================
# PHASE 1: DISCOVER + PLAN
# ============================================================================

_discover_and_plan() {
  local quiet="${1:-false}"
  local prompt_file output_file
  prompt_file=$(create_temp_file ".uat-discover-prompt.md")
  output_file=$(create_temp_file ".uat-discover-output.log")

  local timeout
  timeout=$(get_config '.uat.maxSessionSeconds' "$DEFAULT_UAT_MAX_SESSION_SECONDS")

  # Build discovery prompt
  _build_discovery_prompt "$prompt_file"

  _log_uat "DISCOVER" "Starting discovery + plan generation"

  # Run Claude with MCP exploration
  local claude_exit=0
  (
    set -o pipefail
    cat "$prompt_file" | run_with_timeout "$timeout" claude -p \
      --dangerously-skip-permissions \
      --verbose \
      --output-format stream-json \
      2>&1 | tee "$output_file" | _parse_uat_activity "$quiet"
  ) &
  local pipeline_pid=$!
  wait "$pipeline_pid" || claude_exit=$?

  if [[ $claude_exit -ne 0 ]]; then
    _log_uat "DISCOVER" "Claude session failed (exit $claude_exit)"
    print_error "Discovery session failed"
    if [[ -f "$output_file" ]]; then
      echo "  Last output:"
      tail -10 "$output_file" | sed 's/^/    /'
    fi
    return 1
  fi

  # Validate plan was generated
  if [[ ! -f "$UAT_PLAN_FILE" ]]; then
    print_error "Claude did not generate a test plan at $UAT_PLAN_FILE"
    echo ""
    echo "  The discovery session completed but no plan.json was created."
    echo "  Check the output above for errors."
    return 1
  fi

  if ! _validate_plan; then
    print_error "Generated plan is invalid"
    return 1
  fi

  # Check if project-specific prompt was generated
  if [[ ! -f "$UAT_DIR/UAT-PROMPT.md" ]]; then
    print_warning "Project-specific UAT-PROMPT.md was not generated."
    echo "    Test cases will use the generic template instead."
    echo "    For better results, re-run with 'npx agentic-loop uat --plan-only'."
  fi

  # Mark plan as generated
  update_json "$UAT_PLAN_FILE" '.testSuite.status = "planned"'

  local case_count
  case_count=$(jq '.testCases | length' "$UAT_PLAN_FILE")
  _log_uat "DISCOVER" "Plan generated with $case_count test cases"
  print_success "Plan generated: $case_count test cases"

  return 0
}

_build_discovery_prompt() {
  local prompt_file="$1"

  # Start with UAT prompt template
  cat "$RALPH_TEMPLATES/UAT-PROMPT.md" > "$prompt_file"

  cat >> "$prompt_file" << 'PROMPT_SECTION'

---

## Phase: Discovery + Plan Generation

You are in the DISCOVERY phase. Your tasks:

1. **Read context** — Read `.ralph/config.json` for URLs, directories, auth config
2. **Read PRD** — Read `.ralph/prd.json` for completed stories (what features exist)
3. **Explore the live app** — Use Playwright MCP to navigate pages, click around, fill forms, take screenshots
4. **Read source code** — Understand what's behind the UI you explored
5. **Generate the test plan** — Write `.ralph/uat/plan.json`
6. **Generate project-specific UAT prompt** — Write `.ralph/uat/UAT-PROMPT.md`

### Exploration Strategy

- Start at the frontend URL from config
- Navigate to every page you can find
- Try all forms and interactive elements
- Check the browser console for errors
- Take screenshots of each major page (save to `.ralph/uat/screenshots/`)
- Note anything that looks wrong, slow, or broken

### Test Plan Format

Write `.ralph/uat/plan.json` with this structure:

```json
{
  "testSuite": {
    "name": "UAT Ralph",
    "generatedAt": "<ISO timestamp>",
    "status": "pending"
  },
  "testCases": [
    {
      "id": "UAT-001",
      "title": "Feature area — happy path + edge cases",
      "category": "auth|forms|navigation|api|ui|data",
      "type": "e2e|integration",
      "userStory": "As a user, I...",
      "testApproach": "What to test and how",
      "testFile": "tests/e2e/feature/test-name.spec.ts",
      "targetFiles": ["src/pages/feature.tsx", "api/routes/feature.py"],
      "edgeCases": ["Edge case 1", "Edge case 2"],
      "assertions": [
        {
          "input": "Fill name='John', email='john@test.com', submit form",
          "expected": "Redirect to /dashboard, page shows 'Welcome, John'",
          "strategy": "keyword"
        },
        {
          "input": "Fill name='<script>alert(1)</script>', submit form",
          "expected": "Name displayed as literal text, no script execution",
          "strategy": "security"
        },
        {
          "input": "Submit form with all fields empty",
          "expected": "Validation errors shown, form NOT submitted, URL unchanged",
          "strategy": "structural"
        }
      ],
      "passes": false,
      "retryCount": 0
    }
  ]
}
```

### Assertions: The Core of Every Test Case

Each assertion is an **input → expected output** pair that you discovered during exploration.
These are NOT guesses — they come from actually using the app via MCP and recording what you saw.

**Assertion strategies:**
- `keyword` — expected output contains specific text (names, numbers, messages)
- `structural` — expected output has specific structure (N items, error visible, URL changed)
- `navigation` — expected redirect or page change
- `security` — input is an attack vector, expected output is safe handling
- `llm-judge` — freeform/AI output, needs rubric-based judging

**Every test case MUST have at least 3 assertions:**
1. One happy-path assertion (correct input → correct output)
2. One edge-case assertion (bad input → proper error handling)
3. One content assertion (page shows the RIGHT data, not just that it loads)

### Project-Specific UAT Prompt

After exploring the app, write `.ralph/uat/UAT-PROMPT.md` — a project-specific testing guide.
This file will be used for ALL subsequent test case executions, so make it concrete and specific.

Include these sections based on what you ACTUALLY FOUND during exploration:

```markdown
# UAT Guide — [Project Name]

## App Overview
- What the app does (1-2 sentences)
- Tech stack observed (framework, API patterns, auth method)
- Base URLs (frontend, API if applicable)

## Pages & Routes Discovered
For each page you found:
- URL pattern and what it shows
- Key interactive elements (forms, buttons, links)
- Selectors that work (data-testid, roles, labels)

## Auth Flow
- How login works (form fields, redirect after login)
- Test credentials if available (from config or .env)
- What pages require auth vs. public

## Known Forms & Inputs
For each form:
- Fields with their labels/names/selectors
- Required vs optional fields
- Validation behavior observed
- What happens on successful submit

## What "Correct" Looks Like
For each feature area:
- Expected behavior you observed
- Specific text/numbers that should appear
- Response times that seem normal

## Console & Network Observations
- Any existing console errors/warnings
- API endpoints observed
- Response patterns (JSON structure, status codes)
```

This is NOT a copy of the template — it's the ground truth from YOUR exploration.

### Rules for Plan Generation

- Test auth flows FIRST (they gate everything else)
- One test case per feature area (not per edge case)
- Include edge cases as a list within each test case
- **Every test case MUST have assertions with input/expected pairs**
- `type: "e2e"` for anything involving browser interaction
- `type: "integration"` for API-only tests
- `targetFiles` should list the app source files the test covers
- `testFile` path should use the project's test directory conventions
- Aim for 5-15 test cases depending on app complexity
PROMPT_SECTION

  # Inject PRD context if available
  if [[ -f "$RALPH_DIR/prd.json" ]]; then
    echo "" >> "$prompt_file"
    echo "### Completed Stories (from PRD)" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "These features have been built and should be testable:" >> "$prompt_file"
    echo '```json' >> "$prompt_file"
    jq '[.stories[] | select(.passes==true) | {id, title, type, testUrl: .testUrl}]' \
      "$RALPH_DIR/prd.json" >> "$prompt_file" 2>/dev/null
    echo '```' >> "$prompt_file"
  fi

  # Inject config context
  if [[ -f "$RALPH_DIR/config.json" ]]; then
    echo "" >> "$prompt_file"
    echo "### Project Config" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "Read \`.ralph/config.json\` for URLs and directories." >> "$prompt_file"
  fi

  # Inject signs
  _inject_signs >> "$prompt_file"
}

_validate_plan() {
  # Check JSON is valid
  if ! jq -e '.' "$UAT_PLAN_FILE" >/dev/null 2>&1; then
    print_error "plan.json is not valid JSON"
    return 1
  fi

  # Check required structure
  if ! jq -e '.testSuite and .testCases' "$UAT_PLAN_FILE" >/dev/null 2>&1; then
    print_error "plan.json missing testSuite or testCases"
    return 1
  fi

  # Check test cases have required fields
  local invalid_cases
  invalid_cases=$(jq '[.testCases[] | select(.id == null or .title == null or .testFile == null)] | length' "$UAT_PLAN_FILE" 2>/dev/null)
  if [[ "$invalid_cases" -gt 0 ]]; then
    print_error "$invalid_cases test case(s) missing required fields (id, title, testFile)"
    return 1
  fi

  # Check test cases have assertions (the eval contract)
  local missing_assertions
  missing_assertions=$(jq '[.testCases[] | select((.assertions // []) | length < 1)] | length' "$UAT_PLAN_FILE" 2>/dev/null)
  if [[ "$missing_assertions" -gt 0 ]]; then
    print_warning "$missing_assertions test case(s) have no assertions — tests may be shallow"
    echo "    Each test case should have assertions with input/expected pairs."
    echo "    Run 'npx agentic-loop uat --review' to edit the plan and add them."
    # Warning only, not a hard failure — Claude may add assertions during execution
  fi

  return 0
}

# ============================================================================
# PLAN REVIEW
# ============================================================================

_review_plan() {
  echo ""
  echo "  ┌──────────────────────────────────────────────────────┐"
  echo "  │  UAT Test Plan                                       │"
  echo "  └──────────────────────────────────────────────────────┘"
  echo ""

  local total_cases
  total_cases=$(jq '.testCases | length' "$UAT_PLAN_FILE")

  # Print summary table
  local idx=0
  while IFS=$'\t' read -r id title category tc_type edge_count assert_count; do
    ((idx++))
    local type_icon=""
    case "$tc_type" in
      e2e) type_icon="🌐" ;;
      integration) type_icon="🔌" ;;
      *) type_icon="📝" ;;
    esac

    # Truncate title
    local display_title="$title"
    [[ ${#display_title} -gt 40 ]] && display_title="${display_title:0:37}..."

    printf "  %s %-10s %-40s [%s edges, %s asserts]\n" "$type_icon" "$id" "$display_title" "$edge_count" "$assert_count"
  done < <(jq -r '.testCases[] | [.id, .title, .category, .type, (.edgeCases | length | tostring), ((.assertions // []) | length | tostring)] | @tsv' "$UAT_PLAN_FILE" 2>/dev/null)

  echo ""
  echo "  Total: $total_cases test cases"
  echo ""

  # Prompt for review
  local response
  read -r -p "  Execute this plan? [Y/n/e(dit)] " response

  case "$response" in
    [Nn])
      return 1
      ;;
    [Ee])
      local editor="${EDITOR:-vi}"
      "$editor" "$UAT_PLAN_FILE"
      # Re-validate after edit
      if ! _validate_plan; then
        print_error "Edited plan is invalid. Fix and try again."
        return 1
      fi
      # Mark as reviewed
      update_json "$UAT_PLAN_FILE" \
        --arg ts "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)" \
        '.testSuite.reviewedAt = $ts'
      ;;
    *)
      # Mark as reviewed
      update_json "$UAT_PLAN_FILE" \
        --arg ts "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)" \
        '.testSuite.reviewedAt = $ts'
      ;;
  esac

  return 0
}

# ============================================================================
# PHASE 2: EXECUTE LOOP
# ============================================================================

_run_uat_loop() {
  local focus="$1"
  local no_fix="$2"
  local max_iterations_arg="$3"
  local quiet="$4"

  local max_iterations
  max_iterations="${max_iterations_arg:-$(get_config '.uat.maxIterations' "$DEFAULT_UAT_MAX_ITERATIONS")}"
  local max_case_retries
  max_case_retries=$(get_config '.uat.maxCaseRetries' "$DEFAULT_UAT_MAX_CASE_RETRIES")
  local timeout
  timeout=$(get_config '.uat.maxSessionSeconds' "$DEFAULT_UAT_MAX_SESSION_SECONDS")

  local iteration=0
  local start_time
  start_time=$(date +%s)

  # Track results for report
  UAT_TESTS_WRITTEN=0
  UAT_BUGS_FOUND=0
  UAT_BUGS_FIXED=0
  UAT_CASES_PASSED=0
  UAT_CASES_FAILED=0
  UAT_CASES_SKIPPED=0
  UAT_RED_ONLY_PASSED=0
  UAT_GREEN_ATTEMPTS=0
  UAT_FILES_FIXED=()
  UAT_NEEDS_HUMAN=()

  while [[ $iteration -lt $max_iterations ]]; do
    # Check for stop signal
    if [[ -f "$RALPH_DIR/.stop" ]]; then
      rm -f "$RALPH_DIR/.stop"
      print_warning "Stop signal received. Exiting gracefully."
      break
    fi

    ((iteration++))

    # Pick next incomplete test case (with optional focus filter)
    local case_id
    if [[ -n "$focus" ]]; then
      # Focus can be a case ID (UAT-003) or category (auth)
      case_id=$(jq -r --arg f "$focus" '
        .testCases[] |
        select(.passes==false) |
        select(.id==$f or .category==$f) |
        .id
      ' "$UAT_PLAN_FILE" | head -1)
    else
      case_id=$(jq -r '.testCases[] | select(.passes==false) | .id' "$UAT_PLAN_FILE" | head -1)
    fi

    # All done?
    if [[ -z "$case_id" ]]; then
      break
    fi

    # Get case details
    local case_json case_title case_type
    case_json=$(jq --arg id "$case_id" '.testCases[] | select(.id==$id)' "$UAT_PLAN_FILE")
    case_title=$(echo "$case_json" | jq -r '.title')
    case_type=$(echo "$case_json" | jq -r '.type // "e2e"')

    # Read TDD phase state (null = start RED, "red" = resume GREEN)
    local phase
    phase=$(echo "$case_json" | jq -r '.phase // "null"')

    # Compute per-phase retry counts (default 0 for old plan.json files)
    local red_retries green_retries
    red_retries=$(echo "$case_json" | jq -r '.redRetries // 0')
    green_retries=$(echo "$case_json" | jq -r '.greenRetries // 0')

    # Circuit breaker: combined red + green retries
    local total_retries=$((red_retries + green_retries))
    if [[ $total_retries -ge $max_case_retries ]]; then
      print_warning "$case_id exceeded max retries ($max_case_retries) — skipping"
      _flag_for_human "$case_id" "Exceeded max retries ($max_case_retries)"
      ((UAT_CASES_SKIPPED++))
      update_json "$UAT_PLAN_FILE" \
        --arg id "$case_id" '(.testCases[] | select(.id==$id)) |= . + {passes: true, skipped: true}'
      continue
    fi

    # Determine current phase
    local current_phase="$UAT_PHASE_RED"
    if [[ "$phase" == "red" ]]; then
      current_phase="$UAT_PHASE_GREEN"
    fi

    # Display case banner with phase
    local display_title="$case_title"
    [[ ${#display_title} -gt 50 ]] && display_title="${display_title:0:47}..."

    echo ""
    echo "┌──────────────────────────────────────────────────────────┐"
    printf "│  %-10s  %-45s│\n" "$case_id" "$display_title"
    printf "│  Phase: %-5s  Type: %-6s  Attempt: %-3s                │\n" "$current_phase" "$case_type" "$((total_retries + 1))"
    echo "└──────────────────────────────────────────────────────────┘"
    echo ""

    # Git snapshot for rollback
    _git_snapshot "$case_id"

    local test_file
    test_file=$(jq -r --arg id "$case_id" '.testCases[] | select(.id==$id) | .testFile' "$UAT_PLAN_FILE")

    if [[ "$current_phase" == "$UAT_PHASE_RED" ]]; then
      _run_red_phase "$case_id" "$case_type" "$test_file" "$no_fix" "$timeout" "$quiet"
    else
      _run_green_phase "$case_id" "$case_type" "$test_file" "$timeout" "$quiet"
    fi

    # Brief pause between iterations
    sleep 1
  done

  # Update suite status
  local all_passed
  all_passed=$(jq '[.testCases[] | select(.passes==false)] | length' "$UAT_PLAN_FILE" 2>/dev/null)
  if [[ "$all_passed" -eq 0 ]]; then
    update_json "$UAT_PLAN_FILE" '.testSuite.status = "complete"'
  else
    update_json "$UAT_PLAN_FILE" '.testSuite.status = "partial"'
  fi

  [[ "$all_passed" -eq 0 ]] && return 0
  return 1
}

# ============================================================================
# TDD PHASES: RED (test-only) and GREEN (fix-only)
# ============================================================================

_run_red_phase() {
  local case_id="$1"
  local case_type="$2"
  local test_file="$3"
  local no_fix="$4"
  local timeout="$5"
  local quiet="$6"

  local prompt_file output_file
  prompt_file=$(create_temp_file ".uat-red-prompt.md")
  output_file=$(create_temp_file ".uat-red-output.log")

  _build_red_prompt "$case_id" "$prompt_file"

  _log_uat "$case_id" "RED: Starting test-only session"

  local claude_exit=0
  (
    set -o pipefail
    cat "$prompt_file" | run_with_timeout "$timeout" claude -p \
      --dangerously-skip-permissions \
      --verbose \
      --output-format stream-json \
      2>&1 | tee "$output_file" | _parse_uat_activity "$quiet"
  ) &
  local pipeline_pid=$!
  wait "$pipeline_pid" || claude_exit=$?

  rm -f "$prompt_file"

  if [[ $claude_exit -ne 0 ]] && [[ $claude_exit -ne 124 ]]; then
    print_warning "RED session ended unexpectedly (exit $claude_exit)"
    _log_uat "$case_id" "RED: Session failed (exit $claude_exit)"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Check if test file was created
  if [[ ! -f "$test_file" ]]; then
    print_warning "RED: Test file not created: $test_file"
    _log_uat "$case_id" "RED: Test file not created"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Enforce RED constraint: no app changes allowed
  if _has_app_changes "$test_file"; then
    print_warning "RED violation: Claude modified app code during test-only phase — rolling back"
    _log_uat "$case_id" "RED: App changes detected — rollback"
    _rollback_to_snapshot "$case_id"
    _save_red_violation_feedback "$case_id"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  ((UAT_TESTS_WRITTEN++))

  # Validate test quality — reject shallow tests
  if ! _validate_test_quality "$test_file" "$case_id"; then
    print_warning "$case_id RED: test is too shallow — will retry with feedback"
    _save_shallow_test_feedback "$case_id" "$test_file"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Run the test
  if _run_test "$test_file" "$case_type"; then
    # PASS in RED — app already correct, no fix needed
    print_success "$case_id RED: test passes (app already correct)"
    _mark_passed "$case_id"
    _commit_result "$case_id" "$test_file"
    ((UAT_CASES_PASSED++))
    ((UAT_RED_ONLY_PASSED++))
    _log_uat "$case_id" "RED: PASSED (app already correct)"
  else
    # FAIL — classify: test bug or app bug?
    local failure_type
    failure_type=$(_classify_red_failure "$test_file" "$case_id")

    if [[ "$failure_type" == "test_bug" ]]; then
      print_warning "$case_id RED: test has errors (syntax/import) — will retry"
      _save_failure_context "$case_id" "$output_file"
      _increment_red_retry "$case_id"
    else
      # App bug found — commit the RED test, transition to GREEN
      print_info "$case_id RED: test correctly identifies app bug"
      ((UAT_BUGS_FOUND++))

      if [[ "$no_fix" == "true" ]]; then
        # --no-fix mode: commit failing test as documented bug
        print_info "$case_id: Committing failing test as documented bug (--no-fix)"
        _commit_red_test "$case_id" "$test_file"
        _mark_passed "$case_id"
        ((UAT_CASES_PASSED++))
        _log_uat "$case_id" "RED: Documented bug (--no-fix mode)"
      else
        # Commit the RED test and transition to GREEN
        _commit_red_test "$case_id" "$test_file"
        _mark_phase "$case_id" "red"
        _save_failure_context "$case_id" "$output_file"
        _log_uat "$case_id" "RED: App bug found — transitioning to GREEN"
      fi
    fi
  fi

  rm -f "$output_file"
}

_run_green_phase() {
  local case_id="$1"
  local case_type="$2"
  local test_file="$3"
  local timeout="$4"
  local quiet="$5"

  ((UAT_GREEN_ATTEMPTS++))

  local prompt_file output_file
  prompt_file=$(create_temp_file ".uat-green-prompt.md")
  output_file=$(create_temp_file ".uat-green-output.log")

  _build_green_prompt "$case_id" "$test_file" "$prompt_file"

  _log_uat "$case_id" "GREEN: Starting fix-only session"

  local claude_exit=0
  (
    set -o pipefail
    cat "$prompt_file" | run_with_timeout "$timeout" claude -p \
      --dangerously-skip-permissions \
      --verbose \
      --output-format stream-json \
      2>&1 | tee "$output_file" | _parse_uat_activity "$quiet"
  ) &
  local pipeline_pid=$!
  wait "$pipeline_pid" || claude_exit=$?

  rm -f "$prompt_file"

  if [[ $claude_exit -ne 0 ]] && [[ $claude_exit -ne 124 ]]; then
    print_warning "GREEN session ended unexpectedly (exit $claude_exit)"
    _log_uat "$case_id" "GREEN: Session failed (exit $claude_exit)"
    _increment_green_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Enforce GREEN constraint: no test file modifications
  if _test_file_modified "$test_file"; then
    print_warning "GREEN: Claude modified the test file — restoring"
    _restore_test_file "$test_file" "$case_id"
    _log_uat "$case_id" "GREEN: Test file restored after modification"
  fi

  # Run the test
  if _run_test "$test_file" "$case_type"; then
    # PASS — check for regressions before committing
    if _check_regressions; then
      print_success "$case_id GREEN: fix passes + no regressions"
      _mark_passed "$case_id"
      _track_fixed_files "$case_id"
      ((UAT_BUGS_FIXED++))
      _commit_result "$case_id" "$test_file"
      ((UAT_CASES_PASSED++))
      _log_uat "$case_id" "GREEN: PASSED"
    else
      # Regression detected — rollback
      print_error "GREEN: Fix for $case_id caused regression — rolling back"
      _rollback_to_snapshot "$case_id"
      _flag_for_human "$case_id" "Fix caused regression in existing tests"
      _increment_green_retry "$case_id"
      _log_uat "$case_id" "GREEN: ROLLBACK — fix caused regression"
    fi
  else
    # FAIL — retry GREEN
    print_warning "$case_id GREEN: test still fails — will retry"
    _save_failure_context "$case_id" "$output_file"
    _increment_green_retry "$case_id"
  fi

  rm -f "$output_file"
}

# ============================================================================
# TEST EXECUTION
# ============================================================================

_run_test() {
  local test_file="$1"
  local test_type="$2"
  local log_file
  log_file=$(create_temp_file ".uat-test.log")

  local test_cmd=""

  if [[ "$test_type" == "e2e" ]]; then
    # Playwright
    if [[ -f "playwright.config.ts" ]] || [[ -f "playwright.config.js" ]]; then
      test_cmd="npx playwright test $test_file"
    else
      test_cmd="npx playwright test $test_file --config=playwright.config.ts"
    fi
  else
    # Integration — detect test runner
    if [[ -f "vitest.config.ts" ]] || [[ -f "vitest.config.js" ]] || [[ -f "vite.config.ts" ]]; then
      test_cmd="npx vitest run $test_file"
    elif [[ -f "jest.config.ts" ]] || [[ -f "jest.config.js" ]] || grep -q '"jest"' package.json 2>/dev/null; then
      test_cmd="npx jest $test_file"
    elif [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
      local py_runner
      py_runner=$(detect_python_runner ".")
      test_cmd="${py_runner}${py_runner:+ }pytest $test_file -v"
    else
      test_cmd="npx vitest run $test_file"
    fi
  fi

  echo "  Running: $test_cmd"

  if safe_exec "$test_cmd" "$log_file"; then
    rm -f "$log_file"
    return 0
  else
    echo ""
    echo "  Test output (last 30 lines):"
    tail -30 "$log_file" | sed 's/^/    /'
    cp "$log_file" "$UAT_DIR/last_test_output.log"
    rm -f "$log_file"
    return 1
  fi
}

# ============================================================================
# TEST QUALITY VALIDATION
# ============================================================================

# Reject tests that only check structure (page loads) without verifying content.
# A test that asserts "page has URL /dashboard" proves nothing about correctness.
# A test that asserts "page shows 'Welcome, John'" proves the right data rendered.
_validate_test_quality() {
  local test_file="$1"
  local case_id="$2"

  # Count total assertion calls
  local assertion_count
  assertion_count=$(grep -cE 'expect\(|assert\(|\.should\(' "$test_file" 2>/dev/null || echo "0")

  if [[ "$assertion_count" -lt 2 ]]; then
    _log_uat "$case_id" "SHALLOW: only $assertion_count assertion(s)"
    return 1
  fi

  # Count content assertions — these verify the RIGHT data, not just structure
  # Includes: toContain, toHaveText, toBe, toEqual, toMatch, textContent, innerText
  local content_assertions
  content_assertions=$(grep -cE 'toContain\(|toHaveText\(|toBe\(|toEqual\(|toMatch\(|textContent|innerText|toHaveValue\(' "$test_file" 2>/dev/null || echo "0")

  if [[ "$content_assertions" -eq 0 ]]; then
    _log_uat "$case_id" "SHALLOW: no content assertions (only structural checks)"
    return 1
  fi

  # Check for input→output test pattern: test fills data and checks the result
  # Look for fill/type followed by expect — proves the test verifies a response to input
  local has_input_output=false
  if grep -qE 'fill\(|type\(|press\(|click\(' "$test_file" 2>/dev/null; then
    if grep -qE 'toContain\(|toHaveText\(|toBe\(|toEqual\(|toMatch\(' "$test_file" 2>/dev/null; then
      has_input_output=true
    fi
  fi

  # For e2e tests, require at least one input→output pattern
  if [[ "$has_input_output" == "false" ]]; then
    # Check if it's an API/integration test (no browser interaction expected)
    if grep -qE 'page\.|browser\.|playwright' "$test_file" 2>/dev/null; then
      _log_uat "$case_id" "SHALLOW: e2e test has no input→output assertions"
      return 1
    fi
  fi

  _log_uat "$case_id" "Quality OK: $assertion_count assertions ($content_assertions content)"
  return 0
}

# Save feedback about shallow tests so Claude gets specific guidance on retry
_save_shallow_test_feedback() {
  local case_id="$1"
  local test_file="$2"

  local assertion_count content_assertions
  assertion_count=$(grep -cE 'expect\(|assert\(|\.should\(' "$test_file" 2>/dev/null || echo "0")
  content_assertions=$(grep -cE 'toContain\(|toHaveText\(|toBe\(|toEqual\(|toMatch\(|textContent|innerText|toHaveValue\(' "$test_file" 2>/dev/null || echo "0")

  {
    echo ""
    echo "=== Test quality check failed for $case_id ==="
    echo ""
    echo "Your test is too shallow. It checks structure but not correctness."
    echo ""
    echo "Stats: $assertion_count total assertions, $content_assertions content assertions"
    echo ""
    echo "What's wrong:"
    if [[ "$assertion_count" -lt 2 ]]; then
      echo "  - Only $assertion_count assertion(s). Every test needs at least 2."
    fi
    if [[ "$content_assertions" -eq 0 ]]; then
      echo "  - ZERO content assertions. You're only checking that pages load,"
      echo "    not that they show the RIGHT content."
      echo ""
      echo "  Bad:  await expect(page).toHaveURL('/dashboard');"
      echo "  Good: await expect(page.getByText('Welcome, John')).toBeVisible();"
      echo ""
      echo "  Bad:  await expect(form).toBeVisible();"
      echo "  Good: await expect(page.getByText('Email is required')).toBeVisible();"
    fi
    echo ""
    echo "Fix: Read the assertions in .ralph/uat/plan.json for this test case."
    echo "Each assertion has an 'input' and 'expected' — encode THOSE as expect() calls."
    echo "---"
  } >> "$UAT_FAILURE_FILE"
}

# ============================================================================
# FAILURE HANDLING
# ============================================================================

_save_failure_context() {
  local case_id="$1"
  local output_file="$2"

  local retry_count
  retry_count=$(jq -r --arg id "$case_id" '.testCases[] | select(.id==$id) | .retryCount // 0' "$UAT_PLAN_FILE")

  {
    echo ""
    echo "=== Attempt $((retry_count + 1)) failed for $case_id ==="
    echo ""
    if [[ -f "$UAT_DIR/last_test_output.log" ]]; then
      echo "--- Test Output ---"
      tail -50 "$UAT_DIR/last_test_output.log"
      echo ""
    fi
    echo "---"
  } >> "$UAT_FAILURE_FILE"

  # Cap at 200 lines
  if [[ -f "$UAT_FAILURE_FILE" ]]; then
    local line_count
    line_count=$(wc -l < "$UAT_FAILURE_FILE" | tr -d ' ')
    if [[ $line_count -gt 200 ]]; then
      tail -200 "$UAT_FAILURE_FILE" > "$UAT_FAILURE_FILE.tmp" && mv "$UAT_FAILURE_FILE.tmp" "$UAT_FAILURE_FILE"
    fi
  fi
}

_increment_red_retry() {
  local case_id="$1"
  update_json "$UAT_PLAN_FILE" \
    --arg id "$case_id" \
    '(.testCases[] | select(.id==$id)) |= . + {
      redRetries: ((.redRetries // 0) + 1),
      retryCount: ((.redRetries // 0) + 1 + (.greenRetries // 0))
    }'
}

_increment_green_retry() {
  local case_id="$1"
  update_json "$UAT_PLAN_FILE" \
    --arg id "$case_id" \
    '(.testCases[] | select(.id==$id)) |= . + {
      greenRetries: ((.greenRetries // 0) + 1),
      retryCount: ((.redRetries // 0) + (.greenRetries // 0) + 1)
    }'
}

_mark_phase() {
  local case_id="$1"
  local phase="$2"  # "red" or null
  if [[ "$phase" == "null" ]]; then
    update_json "$UAT_PLAN_FILE" \
      --arg id "$case_id" \
      '(.testCases[] | select(.id==$id)) |= . + {phase: null}'
  else
    update_json "$UAT_PLAN_FILE" \
      --arg id "$case_id" \
      --arg phase "$phase" \
      '(.testCases[] | select(.id==$id)) |= . + {phase: $phase}'
  fi
}

_mark_passed() {
  local case_id="$1"
  update_json "$UAT_PLAN_FILE" \
    --arg id "$case_id" \
    '(.testCases[] | select(.id==$id)) |= . + {passes: true, retryCount: 0, phase: null, redRetries: 0, greenRetries: 0}'
  # Clear failure context for this case
  rm -f "$UAT_FAILURE_FILE"
}

_commit_red_test() {
  local case_id="$1"
  local test_file="$2"

  if ! command -v git &>/dev/null || [[ ! -d ".git" ]]; then
    return 0
  fi

  git add "$test_file" 2>/dev/null || true

  if git diff --cached --quiet 2>/dev/null; then
    return 0
  fi

  local commit_log
  commit_log=$(mktemp)
  local success=false

  for attempt in 1 2 3; do
    if git commit -m "test($case_id): TDD red -- failing test identifies bug" > "$commit_log" 2>&1; then
      success=true
      break
    fi
    if grep -q "files were modified by this hook" "$commit_log" 2>/dev/null; then
      git add "$test_file"
      continue
    fi
    break
  done

  if [[ "$success" != "true" ]]; then
    git add "$test_file"
    git commit -m "test($case_id): TDD red -- failing test identifies bug" --no-verify > "$commit_log" 2>&1 || true
  fi

  rm -f "$commit_log"
}

_classify_red_failure() {
  local test_file="$1"
  local case_id="$2"

  # Check last test output for test-bug patterns (syntax/import errors)
  local test_output="$UAT_DIR/last_test_output.log"
  if [[ -f "$test_output" ]]; then
    # Syntax errors, import failures, module not found = test bug
    if grep -qiE 'SyntaxError|Cannot find module|ModuleNotFoundError|ImportError|TypeError:.*is not a function|ReferenceError:.*is not defined|unexpected token' "$test_output" 2>/dev/null; then
      _log_uat "$case_id" "RED classify: test_bug (syntax/import error)"
      echo "test_bug"
      return
    fi
  fi

  # Assertion failures, timeout waiting for element = app bug (test is correct, app is wrong)
  _log_uat "$case_id" "RED classify: app_bug (assertion failure)"
  echo "app_bug"
}

_test_file_modified() {
  local test_file="$1"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    # Check if test file has uncommitted changes (modified since last commit)
    ! git diff --quiet HEAD -- "$test_file" 2>/dev/null
  else
    return 1
  fi
}

_restore_test_file() {
  local test_file="$1"
  local case_id="${2:-GREEN}"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    git checkout HEAD -- "$test_file" 2>/dev/null || true
    _log_uat "$case_id" "GREEN: Restored test file: $test_file"
  fi
}

_save_red_violation_feedback() {
  local case_id="$1"
  {
    echo ""
    echo "=== RED PHASE VIOLATION for $case_id ==="
    echo ""
    echo "You modified application source files during the RED phase."
    echo "In the RED phase, you must ONLY write the test file."
    echo ""
    echo "DO NOT modify any files in src/, api/, app/, lib/, or similar directories."
    echo "Write ONLY the test file specified in plan.json."
    echo ""
    echo "If the app has a bug, let the test FAIL. A separate GREEN session will fix the app."
    echo "---"
  } >> "$UAT_FAILURE_FILE"
}

_flag_for_human() {
  local case_id="$1"
  local reason="$2"
  UAT_NEEDS_HUMAN+=("$case_id: $reason")
  _log_uat "$case_id" "NEEDS_HUMAN: $reason"
}

# ============================================================================
# GIT OPERATIONS
# ============================================================================

_git_snapshot() {
  local case_id="$1"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    # Commit any pending changes so the tag captures a clean state
    # (tags point at commits, not the working tree)
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
      git add -A 2>/dev/null || true
      git commit -m "uat: snapshot before $case_id" --no-verify 2>/dev/null || true
    fi
    git tag -f "uat-snapshot-${case_id}" 2>/dev/null || true
  fi
}

_rollback_to_snapshot() {
  local case_id="$1"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    local tag="uat-snapshot-${case_id}"
    if git rev-parse "$tag" >/dev/null 2>&1; then
      # Reset to the snapshot commit — undoes both staged and committed changes since
      git reset --hard "$tag" 2>/dev/null || true
      print_info "Rolled back to snapshot for $case_id"
    fi
  fi
}

_has_app_changes() {
  local test_file="$1"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    # Check if any files OTHER than the test file were modified
    local changed_files
    changed_files=$(git diff --name-only HEAD 2>/dev/null | grep -v "^$(echo "$test_file" | sed 's/[.[\/*^$()+?{|]/\\&/g')$" | grep -v '\.ralph/' || true)
    [[ -n "$changed_files" ]]
  else
    return 1
  fi
}

_check_regressions() {
  echo "  Checking for regressions..."

  # Run existing unit tests
  local test_cmd
  test_cmd=$(get_config '.checks.testCommand' "")

  if [[ -z "$test_cmd" ]]; then
    # Auto-detect
    if [[ -f "package.json" ]] && grep -q '"test"' package.json; then
      test_cmd="npm test"
    elif [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
      local py_runner
      py_runner=$(detect_python_runner ".")
      test_cmd="${py_runner}${py_runner:+ }pytest"
    elif [[ -f "Cargo.toml" ]]; then
      test_cmd="cargo test"
    elif [[ -f "go.mod" ]]; then
      test_cmd="go test ./..."
    else
      # No test command — can't check regressions, assume ok
      return 0
    fi
  fi

  local log_file
  log_file=$(create_temp_file ".uat-regression.log")

  if safe_exec "$test_cmd" "$log_file"; then
    print_success "  No regressions detected"
    rm -f "$log_file"
    return 0
  else
    print_error "  Regression detected!"
    echo "    Test output (last 20 lines):"
    tail -20 "$log_file" | sed 's/^/      /'
    rm -f "$log_file"
    return 1
  fi
}

_commit_result() {
  local case_id="$1"
  local test_file="$2"

  if ! command -v git &>/dev/null || [[ ! -d ".git" ]]; then
    return 0
  fi

  # Stage the test file and any app fixes
  git add "$test_file" 2>/dev/null || true
  git add -A 2>/dev/null || true

  # Check if there's anything to commit
  if git diff --cached --quiet 2>/dev/null; then
    return 0
  fi

  local commit_msg
  if _has_app_changes "$test_file"; then
    commit_msg="test+fix($case_id): TDD green -- test + app fix"
  else
    commit_msg="test($case_id): UAT test"
  fi

  # Try commit with retries for auto-fix hooks
  local commit_log
  commit_log=$(mktemp)
  local success=false

  for attempt in 1 2 3; do
    if git commit -m "$commit_msg" > "$commit_log" 2>&1; then
      success=true
      break
    fi
    if grep -q "files were modified by this hook" "$commit_log" 2>/dev/null; then
      git add -A
      continue
    fi
    break
  done

  if [[ "$success" != "true" ]]; then
    # Try with --no-verify as last resort
    git add -A
    git commit -m "$commit_msg" --no-verify > "$commit_log" 2>&1 || true
  fi

  rm -f "$commit_log"

  # Clean up snapshot tag
  git tag -d "uat-snapshot-${case_id}" 2>/dev/null || true
}

_track_fixed_files() {
  local case_id="$1"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    local fixed
    fixed=$(git diff --name-only HEAD~1 2>/dev/null | grep -v 'test' | grep -v '\.ralph/' || true)
    while IFS= read -r f; do
      [[ -n "$f" ]] && UAT_FILES_FIXED+=("$f ($case_id)")
    done <<< "$fixed"
  fi
}

# ============================================================================
# PROMPT BUILDING
# ============================================================================

_build_red_prompt() {
  local case_id="$1"
  local prompt_file="$2"

  # Prefer project-specific UAT prompt (generated during discovery),
  # fall back to the universal template
  local uat_prompt="$RALPH_TEMPLATES/UAT-PROMPT.md"
  if [[ -f "$UAT_DIR/UAT-PROMPT.md" ]]; then
    uat_prompt="$UAT_DIR/UAT-PROMPT.md"
  fi
  cat "$uat_prompt" > "$prompt_file"

  cat >> "$prompt_file" << PROMPT_SECTION

---

## Phase: RED — Write Test Only

You are in the **RED phase** of TDD. Your ONLY job is to write the test.

**CRITICAL: DO NOT modify any application source files. Test files ONLY.**

Your tasks:

1. **Read the test case** from \`.ralph/uat/plan.json\` (case ID: $case_id)
2. **Explore the feature** using Playwright MCP — navigate to the relevant pages, interact with the UI
3. **Write the test file** at the path specified in the test case
4. **Encode every assertion** from the test case as an actual expect() call
5. **Include edge cases** listed in the test case

### Rules

- DO NOT modify any application source files (src/, api/, app/, etc.)
- Write the test to verify CORRECT behavior based on the plan's assertions
- If the app has a bug, the test WILL fail — that is the expected and correct outcome
- Ralph will detect and reject any app code changes in this phase

### Assertions are mandatory

The test case in plan.json has an \`assertions\` array. Each assertion has:
- \`input\`: what to do (fill form, click button, navigate to URL)
- \`expected\`: what should happen (text appears, redirect occurs, error shown)
- \`strategy\`: how to verify (keyword, structural, navigation, security, llm-judge)

**Every assertion MUST become an expect() call in your test.** This is how we verify
correctness, not just that the page loads. Ralph will reject tests that only check
structure without verifying content.

Example — assertion in plan.json:
\`\`\`json
{"input": "Fill name='John', submit", "expected": "Shows 'Welcome, John'", "strategy": "keyword"}
\`\`\`

Becomes in the test:
\`\`\`typescript
await page.getByLabel('Name').fill('John');
await page.getByRole('button', { name: 'Submit' }).click();
await expect(page.getByText('Welcome, John')).toBeVisible();
\`\`\`
PROMPT_SECTION

  # Inject failure context if retrying
  if [[ -f "$UAT_FAILURE_FILE" ]]; then
    echo "" >> "$prompt_file"
    echo "### Previous RED Attempt Failed" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "Your previous test attempt had issues. Fix them:" >> "$prompt_file"
    echo '```' >> "$prompt_file"
    tail -50 "$UAT_FAILURE_FILE" >> "$prompt_file"
    echo '```' >> "$prompt_file"
  fi

  # Inject config context
  echo "" >> "$prompt_file"
  echo "### Config" >> "$prompt_file"
  echo "" >> "$prompt_file"
  echo "Read \`.ralph/config.json\` for URLs and directories." >> "$prompt_file"

  # Inject signs
  _inject_signs >> "$prompt_file"
}

_build_green_prompt() {
  local case_id="$1"
  local test_file="$2"
  local prompt_file="$3"

  # GREEN prompt is focused — no UAT-PROMPT.md preamble needed
  cat > "$prompt_file" << PROMPT_SECTION
# GREEN Phase — Fix Application Code

A test has been written that correctly identifies a bug. Your job is to fix the
APPLICATION CODE so the test passes.

**CRITICAL: DO NOT modify the test file (\`$test_file\`). Fix the app, not the test.**

## Case: $case_id

1. **Read the test file** at \`$test_file\` to understand what it checks
2. **Read the test case** from \`.ralph/uat/plan.json\` (case ID: $case_id) for context
3. **Read the failure output** below to understand what went wrong
4. **Fix the APPLICATION CODE** — make the minimum change needed to pass the test
5. **DO NOT modify the test file** — Ralph will restore it if you do

### Rules

- Make the MINIMUM change needed to fix the bug
- Do NOT modify the test file — it has been validated and committed
- Do NOT add workarounds or hacks — fix the actual bug
- Read .ralph/config.json for project URLs and directories
PROMPT_SECTION

  # Inject failure context (critical for GREEN — this is what guides the fix)
  if [[ -f "$UAT_FAILURE_FILE" ]]; then
    echo "" >> "$prompt_file"
    echo "## Failure Output" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo '```' >> "$prompt_file"
    tail -80 "$UAT_FAILURE_FILE" >> "$prompt_file"
    echo '```' >> "$prompt_file"
  fi

  # Also include last test output if available
  if [[ -f "$UAT_DIR/last_test_output.log" ]]; then
    echo "" >> "$prompt_file"
    echo "## Last Test Output" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo '```' >> "$prompt_file"
    tail -80 "$UAT_DIR/last_test_output.log" >> "$prompt_file"
    echo '```' >> "$prompt_file"
  fi

  # Inject signs
  _inject_signs >> "$prompt_file"
}

# ============================================================================
# ACTIVITY FEED (reuses pattern from loop.sh)
# ============================================================================

_parse_uat_activity() {
  local quiet="${1:-false}"
  local dim=$'\033[2m' green=$'\033[0;32m' nc=$'\033[0m'
  local line
  while IFS= read -r line; do
    # Non-JSON lines — always pass through
    if [[ "$line" != "{"* ]]; then
      echo "$line"
      continue
    fi

    [[ "$quiet" == "true" ]] && continue

    if [[ "$line" != *'"assistant"'* && "$line" != *'"result"'* ]]; then
      continue
    fi

    local msg_type
    msg_type=$(jq -r '.type // empty' <<< "$line" 2>/dev/null) || continue

    if [[ "$msg_type" == "assistant" ]]; then
      local tool_entries
      tool_entries=$(jq -r '
        .message.content[]?
        | select(.type == "tool_use")
        | .name + "\t" + (.input | tostring)
      ' <<< "$line" 2>/dev/null) || continue

      while IFS=$'\t' read -r tool_name tool_input; do
        [[ -z "$tool_name" ]] && continue
        local label="" detail=""
        case "$tool_name" in
          Read)
            label="Reading"
            detail=$(jq -r '.file_path // empty' <<< "$tool_input" 2>/dev/null)
            detail="${detail#"$PWD/"}"
            ;;
          Edit)
            label="Editing"
            detail=$(jq -r '.file_path // empty' <<< "$tool_input" 2>/dev/null)
            detail="${detail#"$PWD/"}"
            ;;
          Write)
            label="Creating"
            detail=$(jq -r '.file_path // empty' <<< "$tool_input" 2>/dev/null)
            detail="${detail#"$PWD/"}"
            ;;
          Bash)
            label="Running"
            detail=$(jq -r '.description // .command // empty' <<< "$tool_input" 2>/dev/null)
            detail="${detail:0:60}"
            ;;
          mcp__playwright__*)
            label="Browser"
            local action="${tool_name#mcp__playwright__browser_}"
            detail="$action"
            ;;
          *)
            label="$tool_name"
            ;;
        esac
        printf "  ${dim}⟳${nc} %-10s %s\n" "$label" "$detail"
      done <<< "$tool_entries"

    elif [[ "$msg_type" == "result" ]]; then
      local cost duration_ms
      cost=$(jq -r '.total_cost_usd // empty' <<< "$line" 2>/dev/null)
      duration_ms=$(jq -r '.duration_ms // empty' <<< "$line" 2>/dev/null)
      local cost_str="" dur_str=""
      [[ -n "$cost" ]] && cost_str=$(printf '$%.2f' "$cost")
      if [[ -n "$duration_ms" ]]; then
        local total_secs=$(( duration_ms / 1000 ))
        if [[ $total_secs -ge 60 ]]; then
          dur_str="$((total_secs / 60))m $((total_secs % 60))s"
        else
          dur_str="${total_secs}s"
        fi
      fi
      echo ""
      if [[ -n "$cost_str" && -n "$dur_str" ]]; then
        echo -e "  ${green}✓ Done${nc} ${dim}(${cost_str}, ${dur_str})${nc}"
      elif [[ -n "$cost_str" ]]; then
        echo -e "  ${green}✓ Done${nc} ${dim}(${cost_str})${nc}"
      fi
    fi
  done
}

# ============================================================================
# PHASE 3: REPORT
# ============================================================================

_print_report() {
  local total_cases passed_cases failed_cases skipped_cases
  total_cases=$(jq '.testCases | length' "$UAT_PLAN_FILE" 2>/dev/null || echo "0")
  passed_cases=$(jq '[.testCases[] | select(.passes==true and .skipped!=true)] | length' "$UAT_PLAN_FILE" 2>/dev/null || echo "0")
  failed_cases=$(jq '[.testCases[] | select(.passes==false)] | length' "$UAT_PLAN_FILE" 2>/dev/null || echo "0")
  skipped_cases=$(jq '[.testCases[] | select(.skipped==true)] | length' "$UAT_PLAN_FILE" 2>/dev/null || echo "0")

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║             UAT Ralph Results                            ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  Test cases:  %-3s total, %-3s passed, %-3s failed, %-3s skipped  ║\n" \
    "$total_cases" "$passed_cases" "$failed_cases" "$skipped_cases"
  printf "║  App bugs found: %-3s   Fixed: %-3s                        ║\n" \
    "$UAT_BUGS_FOUND" "$UAT_BUGS_FIXED"
  printf "║  TDD: %-3s red-only, %-3s green attempts                   ║\n" \
    "$UAT_RED_ONLY_PASSED" "$UAT_GREEN_ATTEMPTS"
  echo "║                                                          ║"

  # List test files
  if [[ $UAT_TESTS_WRITTEN -gt 0 ]]; then
    echo "║  New test files:                                         ║"
    jq -r '.testCases[] | select(.passes==true and .skipped!=true) | "  " + .testFile + " ✅"' "$UAT_PLAN_FILE" 2>/dev/null | while IFS= read -r line; do
      printf "║  %-56s║\n" "$line"
    done
    jq -r '.testCases[] | select(.passes==false) | "  " + .testFile + " ❌"' "$UAT_PLAN_FILE" 2>/dev/null | while IFS= read -r line; do
      printf "║  %-56s║\n" "$line"
    done
  fi

  # List fixed app files
  if [[ ${#UAT_FILES_FIXED[@]} -gt 0 ]]; then
    echo "║                                                          ║"
    echo "║  App files fixed:                                        ║"
    for f in "${UAT_FILES_FIXED[@]}"; do
      local display="$f"
      [[ ${#display} -gt 54 ]] && display="${display:0:51}..."
      printf "║    %-54s║\n" "$display"
    done
  fi

  # List items needing human attention
  if [[ ${#UAT_NEEDS_HUMAN[@]} -gt 0 ]]; then
    echo "║                                                          ║"
    echo "║  Needs human attention:                                  ║"
    for item in "${UAT_NEEDS_HUMAN[@]}"; do
      local display="$item"
      [[ ${#display} -gt 54 ]] && display="${display:0:51}..."
      printf "║    %-54s║\n" "$display"
    done
  fi

  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  # Send notification
  send_notification "UAT Ralph: $passed_cases/$total_cases passed, $UAT_BUGS_FIXED bugs fixed"
}

# ============================================================================
# BANNER
# ============================================================================

_print_uat_banner() {
  echo ""
  echo "  _   _   _  _____   ____       _       _"
  echo " | | | | / \\|_   _| |  _ \\ __ _| |_ __ | |__"
  echo " | | | |/ _ \\ | |   | |_) / _\` | | '_ \\| '_ \\"
  echo " | |_| / ___ \\| |   |  _ < (_| | | |_) | | | |"
  echo "  \\___/_/   \\_\\_|   |_| \\_\\__,_|_| .__/|_| |_|"
  echo "                                  |_|"
  echo ""
}

# ============================================================================
# SWARM DISCOVERY
# ============================================================================

# Orchestrator: scout → swarm → merge → validate
# Falls back to single-session on failure
_swarm_discover_and_plan() {
  local fresh_mode="${1:-false}"
  local quiet="${2:-false}"

  # Clear cache if --fresh
  if [[ "$fresh_mode" == "true" ]]; then
    _log_uat "SWARM" "Fresh mode: clearing cached files"
    rm -f "$UAT_DIR"/app-map.json "$UAT_DIR"/findings-*.json
  fi

  # Phase 1: Scout (skip if cached or config-defined)
  if [[ ! -f "$UAT_DIR/app-map.json" ]]; then
    local config_areas
    config_areas=$(get_config '.uat.featureAreas' "")
    if [[ -n "$config_areas" && "$config_areas" != "null" ]]; then
      _build_app_map_from_config "$config_areas"
    else
      if ! _run_scout "$quiet"; then
        _log_uat "SWARM" "Scout failed"
        return 1
      fi
    fi
  else
    _log_uat "SWARM" "Reusing cached app-map.json (use --fresh to re-scout)"
    print_info "Reusing cached app-map.json (use --fresh to re-scout)"
  fi

  # Validate app-map
  if [[ ! -f "$UAT_DIR/app-map.json" ]]; then
    _log_uat "SWARM" "No app-map.json after scout"
    return 1
  fi

  local area_count
  area_count=$(jq '[.featureAreas | to_entries[] | select(.value.exists==true)] | length' "$UAT_DIR/app-map.json" 2>/dev/null || echo "0")
  if [[ "$area_count" -eq 0 ]]; then
    print_warning "Scout found 0 feature areas — falling back to single-session"
    _log_uat "SWARM" "0 feature areas found"
    return 1
  fi

  print_success "Scout found $area_count feature areas"

  # Phase 2: Swarm (only spawn missing agents)
  if ! _run_agent_swarm "$quiet"; then
    # Check if we got ANY findings
    local findings_count
    findings_count=$(find "$UAT_DIR" -name "findings-*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$findings_count" -eq 0 ]]; then
      _log_uat "SWARM" "All agents failed, no findings"
      return 1
    fi
    print_warning "Some agents failed, merging findings from successful ones"
  fi

  # Phase 3: Merge findings into plan.json
  if ! _merge_findings; then
    _log_uat "SWARM" "Merge produced 0 test cases"
    return 1
  fi

  # Validate the merged plan
  if ! _validate_plan; then
    print_error "Merged plan is invalid"
    return 1
  fi

  # Mark plan as generated
  update_json "$UAT_PLAN_FILE" '.testSuite.status = "planned"'

  local case_count
  case_count=$(jq '.testCases | length' "$UAT_PLAN_FILE")
  _log_uat "SWARM" "Plan generated with $case_count test cases (swarm discovery)"
  print_success "Plan generated: $case_count test cases (swarm: $area_count areas)"

  return 0
}

# Run a single scout session to map the app surface
_run_scout() {
  local quiet="${1:-false}"
  local prompt_file output_file
  prompt_file=$(create_temp_file ".uat-scout-prompt.md")
  output_file=$(create_temp_file ".uat-scout-output.log")

  local timeout
  timeout=$(get_config '.uat.swarm.scoutTimeoutSeconds' "$DEFAULT_UAT_SCOUT_TIMEOUT")

  _build_scout_prompt "$prompt_file"

  _log_uat "SCOUT" "Starting scout session (timeout: ${timeout}s)"
  print_info "Scout: Mapping app surface..."

  local claude_exit=0
  (
    set -o pipefail
    cat "$prompt_file" | run_with_timeout "$timeout" claude -p \
      --dangerously-skip-permissions \
      --verbose \
      --output-format stream-json \
      2>&1 | tee "$output_file" | _parse_uat_activity "$quiet"
  ) &
  local pipeline_pid=$!
  wait "$pipeline_pid" || claude_exit=$?

  rm -f "$prompt_file"

  if [[ $claude_exit -ne 0 ]] && [[ $claude_exit -ne 124 ]]; then
    _log_uat "SCOUT" "Scout session failed (exit $claude_exit)"
    print_error "Scout session failed"
    rm -f "$output_file"
    return 1
  fi

  # Validate app-map was generated
  if [[ ! -f "$UAT_DIR/app-map.json" ]]; then
    print_error "Scout did not generate app-map.json"
    rm -f "$output_file"
    return 1
  fi

  if ! jq -e '.featureAreas' "$UAT_DIR/app-map.json" >/dev/null 2>&1; then
    print_error "app-map.json missing featureAreas"
    rm -f "$UAT_DIR/app-map.json" "$output_file"
    return 1
  fi

  local area_count
  area_count=$(jq '[.featureAreas | to_entries[] | select(.value.exists==true)] | length' "$UAT_DIR/app-map.json" 2>/dev/null || echo "0")
  _log_uat "SCOUT" "Scout complete: $area_count areas mapped"

  rm -f "$output_file"
  return 0
}

# Build app-map.json from config.uat.featureAreas (no Claude needed)
_build_app_map_from_config() {
  local config_areas="$1"
  local base_url
  base_url=$(get_config '.urls.frontend' "http://localhost:3000")

  _log_uat "SWARM" "Building app-map from config featureAreas"
  print_info "Building app-map from config (no scout needed)"

  # config_areas must be a JSON array like ["auth","forms","navigation"]
  if ! echo "$config_areas" | jq -e 'type == "array"' >/dev/null 2>&1; then
    print_error "config.uat.featureAreas must be a JSON array, got: $config_areas"
    return 1
  fi

  local timestamp
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  jq -n --arg ts "$timestamp" --arg url "$base_url" --argjson areas "$config_areas" '
    {
      scoutedAt: $ts,
      baseUrl: $url,
      source: "config",
      featureAreas: (
        $areas | map({key: ., value: {exists: true, pages: [], forms: [], apiEndpoints: [], notes: "from config"}}) | from_entries
      ),
      techStack: {}
    }
  ' > "$UAT_DIR/app-map.json"

  print_success "App-map built from config: $(echo "$config_areas" | jq 'length') areas"
}

# Build the scout prompt
_build_scout_prompt() {
  local prompt_file="$1"

  cat > "$prompt_file" << 'SCOUT_PROMPT'
# Scout Mission — Map the App Surface

You are a SCOUT. Your job is to quickly map the app's feature surface in ~60 seconds.
Do NOT go deep into any feature. Just catalog what exists.

## Tasks

1. **Read `.ralph/config.json`** for the frontend URL and any auth config
2. **Navigate to the app** using Playwright MCP
3. **Catalog every page** you can find — click nav links, check menus, explore routes
4. **Note forms** — what fields they have, where they submit
5. **Note auth** — is there a login page? What method?
6. **Note API patterns** — check network requests, look for REST/GraphQL
7. **Take 1-2 screenshots** of the main pages (save to `.ralph/uat/screenshots/`)
8. **Write `.ralph/uat/app-map.json`** with your findings

## Output Schema

Write `.ralph/uat/app-map.json`:

```json
{
  "scoutedAt": "<ISO timestamp>",
  "baseUrl": "<from config>",
  "source": "scout",
  "featureAreas": {
    "auth": {
      "exists": true,
      "pages": ["/login", "/register"],
      "forms": [{"page": "/login", "fields": ["email", "password"]}],
      "apiEndpoints": ["/api/auth/login"],
      "notes": "Email/password login, JWT tokens"
    },
    "forms": {
      "exists": true,
      "pages": ["/contact", "/settings"],
      "forms": [{"page": "/contact", "fields": ["name", "email", "message"]}],
      "apiEndpoints": [],
      "notes": "Contact form, settings form"
    },
    "navigation": {
      "exists": true,
      "pages": ["/", "/about", "/dashboard"],
      "forms": [],
      "apiEndpoints": [],
      "notes": "Top nav with 5 links, sidebar on dashboard"
    },
    "api": {
      "exists": false,
      "pages": [],
      "forms": [],
      "apiEndpoints": [],
      "notes": "No visible API endpoints"
    }
  },
  "techStack": {
    "framework": "React/Next.js/etc",
    "authMethod": "JWT/session/none",
    "apiPattern": "REST/GraphQL/none"
  }
}
```

## Rules

- **Speed over depth** — 60 seconds max. Don't fill forms, don't test edge cases.
- **Mark `exists: false`** for areas you can't find evidence of.
- **Common feature areas**: auth, forms, navigation, api, data-display, search, settings, file-upload, notifications
- Only include areas that make sense for this app. A static site might only have "navigation".
- **Be honest** — if you're not sure, mark exists: false. Better to skip than to hallucinate.
SCOUT_PROMPT

  # Inject PRD context if available
  if [[ -f "$RALPH_DIR/prd.json" ]]; then
    echo "" >> "$prompt_file"
    echo "### Completed Stories (from PRD)" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "These features have been built — use them as hints for what areas exist:" >> "$prompt_file"
    echo '```json' >> "$prompt_file"
    jq '[.stories[] | select(.passes==true) | {id, title, type}]' \
      "$RALPH_DIR/prd.json" >> "$prompt_file" 2>/dev/null
    echo '```' >> "$prompt_file"
  fi

  # Inject config context
  if [[ -f "$RALPH_DIR/config.json" ]]; then
    echo "" >> "$prompt_file"
    echo "### Project Config" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo "Read \`.ralph/config.json\` for URLs, auth config, and directories." >> "$prompt_file"
  fi

  # Inject signs
  _inject_signs >> "$prompt_file"
}

# Spawn parallel agents for each area × vector combination
_run_agent_swarm() {
  local quiet="${1:-false}"
  local max_concurrent
  max_concurrent=$(get_config '.uat.swarm.maxConcurrent' "$DEFAULT_UAT_MAX_CONCURRENT")

  # Read areas with exists:true from app-map
  local areas=()
  while IFS= read -r area; do
    [[ -n "$area" ]] && areas+=("$area")
  done < <(jq -r '.featureAreas | to_entries[] | select(.value.exists==true) | .key' "$UAT_DIR/app-map.json" 2>/dev/null)

  if [[ ${#areas[@]} -eq 0 ]]; then
    print_warning "No feature areas to explore"
    return 1
  fi

  # Build agent list, skipping those with cached findings
  local agents_to_spawn=()
  local cached_count=0
  for area in "${areas[@]}"; do
    for vector in "${UAT_VECTORS[@]}"; do
      local agent_name="${area}-${vector}"
      local findings_file="$UAT_DIR/findings-${agent_name}.json"
      if [[ -f "$findings_file" ]]; then
        ((cached_count++))
        _log_uat "SWARM" "Reusing cached findings for $agent_name"
      else
        agents_to_spawn+=("${area}:${vector}")
      fi
    done
  done

  local total_agents=$(( ${#agents_to_spawn[@]} + cached_count ))

  if [[ ${#agents_to_spawn[@]} -eq 0 ]]; then
    print_success "All $cached_count findings cached, skipping swarm"
    _log_uat "SWARM" "All findings cached ($cached_count), skipping swarm"
    return 0
  fi

  print_info "Swarm: $total_agents agents total, $cached_count cached, ${#agents_to_spawn[@]} to spawn"
  _log_uat "SWARM" "Spawning ${#agents_to_spawn[@]} agents ($cached_count cached)"

  # Spawn agents in batches respecting max_concurrent
  local spawned=0
  local failed=0
  local succeeded=0
  local batch_pids=""
  local batch_names=""
  local batch_size=0

  # Global return values from _wait_for_all_agents (bash 3.2 lacks namerefs)
  _SWARM_BATCH_SUCCEEDED=0
  _SWARM_BATCH_FAILED=0

  for agent_spec in "${agents_to_spawn[@]}"; do
    local area="${agent_spec%%:*}"
    local vector="${agent_spec##*:}"
    local agent_name="${area}-${vector}"

    # If batch is full, wait for it to complete
    if [[ $batch_size -ge $max_concurrent ]]; then
      _wait_for_all_agents "$batch_pids" "$batch_names"
      succeeded=$((succeeded + _SWARM_BATCH_SUCCEEDED))
      failed=$((failed + _SWARM_BATCH_FAILED))
      batch_pids=""
      batch_names=""
      batch_size=0
    fi

    _log_uat "SWARM" "Spawning agent: $agent_name"
    echo "  Spawning: $agent_name"

    ( _run_single_agent "$area" "$vector" "$quiet" ) &
    batch_pids="$batch_pids $!"
    batch_names="$batch_names $agent_name"
    ((batch_size++))
    ((spawned++))
  done

  # Wait for final batch
  if [[ $batch_size -gt 0 ]]; then
    _wait_for_all_agents "$batch_pids" "$batch_names"
    succeeded=$((succeeded + _SWARM_BATCH_SUCCEEDED))
    failed=$((failed + _SWARM_BATCH_FAILED))
  fi

  echo ""
  print_info "Swarm complete: $spawned spawned, $succeeded succeeded, $failed failed, $cached_count cached"
  _log_uat "SWARM" "Complete: $spawned spawned, $succeeded ok, $failed failed, $cached_count cached"

  # Return failure only if ALL spawned agents failed
  [[ $succeeded -eq 0 && $spawned -gt 0 ]] && return 1
  return 0
}

# Wait for all spawned agents to complete
_wait_for_all_agents() {
  local pid_list="$1"   # space-separated PIDs
  local name_list="$2"  # space-separated agent names (same order)

  # Convert to arrays via word splitting
  local pids_arr=($pid_list)
  local names_arr=($name_list)
  local local_succeeded=0
  local local_failed=0

  for i in "${!pids_arr[@]}"; do
    wait "${pids_arr[$i]}" 2>/dev/null
    local exit_code=$?
    local name="${names_arr[$i]}"

    if [[ $exit_code -eq 0 ]]; then
      echo "  Finished: $name"
      ((local_succeeded++))
    else
      print_warning "  Failed: $name (exit $exit_code)"
      ((local_failed++))
    fi
  done

  # Return counts via global vars (bash 3.2 compatible)
  _SWARM_BATCH_SUCCEEDED=$local_succeeded
  _SWARM_BATCH_FAILED=$local_failed
}

# Run a single exploration agent
# NOTE: This runs in a subshell via ( _run_single_agent ... ) &
# so create_temp_file tracking won't propagate — use mktemp directly.
_run_single_agent() {
  local area="$1"
  local vector="$2"
  local quiet="${3:-false}"
  local agent_name="${area}-${vector}"
  local findings_file="$UAT_DIR/findings-${agent_name}.json"

  local prompt_file output_file
  prompt_file=$(mktemp)
  output_file=$(mktemp)

  local timeout
  timeout=$(get_config '.uat.swarm.agentTimeoutSeconds' "$DEFAULT_UAT_AGENT_TIMEOUT")

  _build_agent_prompt "$area" "$vector" "$prompt_file"

  _log_uat "$agent_name" "Starting agent (timeout: ${timeout}s)"

  # Ensure temp files are cleaned on any exit path
  trap 'rm -f "$prompt_file" "$output_file"' RETURN

  local claude_exit=0
  (
    set -o pipefail
    cat "$prompt_file" | run_with_timeout "$timeout" claude -p \
      --dangerously-skip-permissions \
      --verbose \
      --output-format stream-json \
      2>&1 | tee "$output_file" | _parse_agent_activity "$agent_name" "$quiet"
  ) &
  local inner_pid=$!
  wait "$inner_pid" || claude_exit=$?

  if [[ $claude_exit -ne 0 ]] && [[ $claude_exit -ne 124 ]]; then
    _log_uat "$agent_name" "Agent failed (exit $claude_exit)"
    return 1
  fi

  # Validate findings
  if [[ ! -f "$findings_file" ]]; then
    _log_uat "$agent_name" "No findings file generated"
    return 1
  fi

  if ! jq -e '.testCases' "$findings_file" >/dev/null 2>&1; then
    _log_uat "$agent_name" "Invalid findings file (missing testCases)"
    rm -f "$findings_file"
    return 1
  fi

  local case_count
  case_count=$(jq '.testCases | length' "$findings_file" 2>/dev/null || echo "0")
  _log_uat "$agent_name" "Agent complete: $case_count test cases"

  return 0
}

# Build a focused prompt for a single swarm agent
_build_agent_prompt() {
  local area="$1"
  local vector="$2"
  local prompt_file="$3"
  local agent_name="${area}-${vector}"

  # Start with UAT-PROMPT.md base
  local uat_prompt="$RALPH_TEMPLATES/UAT-PROMPT.md"
  if [[ -f "$UAT_DIR/UAT-PROMPT.md" ]]; then
    uat_prompt="$UAT_DIR/UAT-PROMPT.md"
  fi
  cat "$uat_prompt" > "$prompt_file"

  # Add agent mandate
  cat >> "$prompt_file" << AGENT_SECTION

---

## Agent Mission: ${agent_name}

You are a focused exploration agent. Your job is to deeply test ONE feature area
with ONE attack vector and generate findings.

**Feature Area:** ${area}
**Attack Vector:** ${vector}

AGENT_SECTION

  # Add vector-specific mandate
  case "$vector" in
    happy-path)
      cat >> "$prompt_file" << 'VECTOR_SECTION'
### Your Mandate: Happy Path Testing

Test the NORMAL user flows for this feature area:
- Complete the primary user journey end-to-end
- Verify correct behavior at each step
- Check that data displays correctly
- Ensure navigation works as expected
- Verify success messages, confirmations, redirects
VECTOR_SECTION
      ;;
    chaos)
      cat >> "$prompt_file" << 'VECTOR_SECTION'
### Your Mandate: Chaos Testing

Test EDGE CASES and unexpected inputs for this feature area:
- Empty strings, whitespace-only inputs
- Extremely long strings (1000+ characters)
- Special characters: <>&"'/\` and unicode
- Rapid-fire submissions (double-click, triple-click)
- Form submission with missing required fields
- Back button after form submission
- Refresh mid-flow
- Unexpected state transitions
VECTOR_SECTION
      ;;
    security)
      cat >> "$prompt_file" << 'VECTOR_SECTION'
### Your Mandate: Security Testing

Test SECURITY vulnerabilities for this feature area:
- XSS: inject `<script>alert(1)</script>` in every text input
- SQL injection: try `'; DROP TABLE users; --` in inputs
- Auth bypass: access protected pages directly via URL
- Direct URL manipulation: change IDs, paths, query params
- CSRF: check for token validation on forms
- Check for sensitive data exposure in page source/console
- Test authorization: can you access other users' data?
VECTOR_SECTION
      ;;
  esac

  # Inject area context from app-map
  local area_json
  area_json=$(jq --arg area "$area" '.featureAreas[$area] // {}' "$UAT_DIR/app-map.json" 2>/dev/null)

  cat >> "$prompt_file" << AREA_SECTION

### Feature Area Context (from scout)

\`\`\`json
${area_json}
\`\`\`

AREA_SECTION

  # Self-termination rule
  cat >> "$prompt_file" << 'TERM_SECTION'
### Self-Termination

If your feature area doesn't exist, pages 404, or you can't find anything to test:
write an empty findings file and stop immediately.

```json
{
  "agent": "<agent-name>",
  "featureArea": "<area>",
  "attackVector": "<vector>",
  "testCases": [],
  "notes": "Area not found or not testable"
}
```
TERM_SECTION

  # Output format
  local findings_file="findings-${agent_name}.json"
  cat >> "$prompt_file" << FINDINGS_SECTION

### Output

Write \`.ralph/uat/${findings_file}\` with this structure:

\`\`\`json
{
  "agent": "${agent_name}",
  "featureArea": "${area}",
  "attackVector": "${vector}",
  "testCases": [
    {
      "tempId": "${agent_name}-001",
      "title": "Descriptive title of what the test checks",
      "category": "${area}",
      "type": "e2e",
      "testFile": "tests/e2e/${area}/${agent_name}.spec.ts",
      "targetFiles": ["src/..."],
      "assertions": [
        {
          "input": "What to do (fill form, click button, navigate)",
          "expected": "What should happen (text appears, redirect, error shown)",
          "strategy": "keyword|structural|navigation|security"
        }
      ],
      "edgeCases": ["Edge case 1", "Edge case 2"],
      "source": "swarm:${agent_name}"
    }
  ]
}
\`\`\`

**Every test case MUST have at least 3 assertions** with concrete input/expected pairs.

### Config

Read \`.ralph/config.json\` for URLs, auth config, and directories.
FINDINGS_SECTION

  # Inject signs
  _inject_signs >> "$prompt_file"
}

# Activity parser with agent name prefix
_parse_agent_activity() {
  local agent_name="$1"
  local quiet="${2:-false}"

  # Assign a color based on agent name hash
  local colors=('\033[0;36m' '\033[0;35m' '\033[0;33m' '\033[0;32m' '\033[0;34m' '\033[0;31m')
  local hash=0
  local i
  for (( i=0; i<${#agent_name}; i++ )); do
    hash=$(( (hash + $(printf '%d' "'${agent_name:$i:1}")) % ${#colors[@]} ))
  done
  local color="${colors[$hash]}"
  local nc=$'\033[0m'
  local dim=$'\033[2m'
  local green=$'\033[0;32m'

  local line
  while IFS= read -r line; do
    # Non-JSON lines
    if [[ "$line" != "{"* ]]; then
      [[ "$quiet" != "true" ]] && echo -e "  ${color}[${agent_name}]${nc} $line"
      continue
    fi

    [[ "$quiet" == "true" ]] && continue

    if [[ "$line" != *'"assistant"'* && "$line" != *'"result"'* ]]; then
      continue
    fi

    local msg_type
    msg_type=$(jq -r '.type // empty' <<< "$line" 2>/dev/null) || continue

    if [[ "$msg_type" == "assistant" ]]; then
      local tool_entries
      tool_entries=$(jq -r '
        .message.content[]?
        | select(.type == "tool_use")
        | .name + "\t" + (.input | tostring)
      ' <<< "$line" 2>/dev/null) || continue

      while IFS=$'\t' read -r tool_name tool_input; do
        [[ -z "$tool_name" ]] && continue
        local label="" detail=""
        case "$tool_name" in
          Read)
            label="Reading"
            detail=$(jq -r '.file_path // empty' <<< "$tool_input" 2>/dev/null)
            detail="${detail#"$PWD/"}"
            ;;
          mcp__playwright__*)
            label="Browser"
            local action="${tool_name#mcp__playwright__browser_}"
            detail="$action"
            ;;
          Bash)
            label="Running"
            detail=$(jq -r '.description // .command // empty' <<< "$tool_input" 2>/dev/null)
            detail="${detail:0:60}"
            ;;
          *)
            label="$tool_name"
            ;;
        esac
        printf "  ${color}[${agent_name}]${nc} ${dim}⟳${nc} %-10s %s\n" "$label" "$detail"
      done <<< "$tool_entries"

    elif [[ "$msg_type" == "result" ]]; then
      local cost duration_ms
      cost=$(jq -r '.total_cost_usd // empty' <<< "$line" 2>/dev/null)
      duration_ms=$(jq -r '.duration_ms // empty' <<< "$line" 2>/dev/null)
      local cost_str="" dur_str=""
      [[ -n "$cost" ]] && cost_str=$(printf '$%.2f' "$cost")
      if [[ -n "$duration_ms" ]]; then
        local total_secs=$(( duration_ms / 1000 ))
        if [[ $total_secs -ge 60 ]]; then
          dur_str="$((total_secs / 60))m $((total_secs % 60))s"
        else
          dur_str="${total_secs}s"
        fi
      fi
      if [[ -n "$cost_str" && -n "$dur_str" ]]; then
        echo -e "  ${color}[${agent_name}]${nc} ${green}✓ Done${nc} ${dim}(${cost_str}, ${dur_str})${nc}"
      elif [[ -n "$cost_str" ]]; then
        echo -e "  ${color}[${agent_name}]${nc} ${green}✓ Done${nc} ${dim}(${cost_str})${nc}"
      fi
    fi
  done
}

# Merge all findings-*.json files into plan.json
_merge_findings() {
  local findings_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && findings_files+=("$f")
  done < <(find "$UAT_DIR" -name "findings-*.json" -type f 2>/dev/null | sort)

  if [[ ${#findings_files[@]} -eq 0 ]]; then
    print_error "No findings files to merge"
    return 1
  fi

  print_info "Merging findings from ${#findings_files[@]} files..."
  _log_uat "MERGE" "Merging ${#findings_files[@]} findings files"

  # Collect all test cases, tracking which files contributed
  local all_cases="[]"
  local agent_count=0
  local skipped_files=0

  for findings_file in "${findings_files[@]}"; do
    # Validate JSON
    if ! jq -e '.testCases' "$findings_file" >/dev/null 2>&1; then
      print_warning "  Skipping invalid findings: $(basename "$findings_file")"
      ((skipped_files++))
      continue
    fi

    local case_count
    case_count=$(jq '.testCases | length' "$findings_file" 2>/dev/null || echo "0")
    if [[ "$case_count" -eq 0 ]]; then
      continue
    fi

    ((agent_count++))

    # Append test cases
    all_cases=$(jq -s '.[0] + .[1]' <(echo "$all_cases") <(jq '.testCases' "$findings_file") 2>/dev/null)
  done

  local total_raw
  total_raw=$(echo "$all_cases" | jq 'length')

  if [[ "$total_raw" -eq 0 ]]; then
    print_error "0 test cases across all findings"
    return 1
  fi

  # Filter out cases missing testFile, then dedup by testFile (keep the one with more assertions)
  local deduped
  deduped=$(echo "$all_cases" | jq '
    [.[] | select(.testFile != null and .testFile != "")] |
    group_by(.testFile) |
    map(
      sort_by(-(.assertions | length)) | .[0]
    )
  ')

  local total_deduped
  total_deduped=$(echo "$deduped" | jq 'length')

  # Assign sequential IDs and standard fields
  local timestamp
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  local plan
  plan=$(echo "$deduped" | jq --arg ts "$timestamp" --arg agents "$agent_count" '
    {
      testSuite: {
        name: "UAT Ralph",
        generatedAt: $ts,
        status: "pending",
        discoveryMethod: "swarm",
        agentCount: ($agents | tonumber)
      },
      testCases: [
        to_entries[] |
        .value + {
          id: ("UAT-" + ((.key + 1) | tostring | if length < 3 then ("000" + .)[-3:] else . end)),
          passes: false,
          retryCount: 0
        } |
        del(.tempId)
      ]
    }
  ')

  echo "$plan" > "$UAT_PLAN_FILE"

  local dupes_removed=$((total_raw - total_deduped))
  print_success "Merged: $total_deduped test cases from $agent_count agents ($dupes_removed duplicates removed)"
  _log_uat "MERGE" "Merged $total_deduped cases from $agent_count agents (${total_raw} raw, $dupes_removed dupes, $skipped_files skipped)"

  return 0
}

# ============================================================================
# HELPERS
# ============================================================================

_log_uat() {
  local id="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  echo "[$timestamp] $id $msg" >> "$UAT_PROGRESS_FILE"
}
