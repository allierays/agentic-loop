#!/usr/bin/env bash
# shellcheck shell=bash
# uat.sh - UAT + Chaos Agent: Autonomous Testing Loops
#
# ============================================================================
# OVERVIEW
# ============================================================================
# Two commands share this file:
#   uat   — Acceptance testing team. "Does this work correctly?"
#   chaos-agent — Chaos Agent red team. "Can we break it?"
#
# Both use Agent Teams for coordinated discovery, then strict TDD per test case:
#   RED:   Claude writes the test only (no app changes)
#   GREEN: Claude fixes the app only (no test changes)
#
# 3-Phase Flow:
#   Phase 1: DISCOVER + PLAN  — Agent team explores app, generates plan
#   Phase 2: EXECUTE LOOP     — Per test case: RED (test) → GREEN (fix)
#   Phase 3: REPORT           — Summary of findings
#
# ============================================================================
# DEPENDENCIES: Requires utils.sh sourced first (get_config, print_*, etc.)
# ============================================================================

# UAT-specific directory variables (initialized by _init_uat_dirs)
UAT_MODE_DIR=""
UAT_PLAN_FILE=""
UAT_PROGRESS_FILE=""
UAT_FAILURE_FILE=""
UAT_SCREENSHOTS_DIR=""
UAT_MODE_LABEL=""
UAT_CONFIG_NS=""    # config namespace: "uat" or "chaos"
UAT_CMD_NAME=""     # CLI command name: "uat" or "chaos-agent"

# TDD phases
readonly UAT_PHASE_RED="RED"
readonly UAT_PHASE_GREEN="GREEN"

# Defaults (overridable via config)
readonly DEFAULT_UAT_MAX_ITERATIONS=20
readonly DEFAULT_UAT_MAX_SESSION_SECONDS=600
readonly DEFAULT_UAT_MAX_CASE_RETRIES=5

# Team mode timeouts (longer — Claude coordinates parallel agents)
readonly DEFAULT_UAT_SESSION_SECONDS=1800
readonly DEFAULT_CHAOS_SESSION_SECONDS=1800

# ============================================================================
# DIRECTORY INIT
# ============================================================================

_init_uat_dirs() {
  local subdir="${1:-uat}"
  local label="${2:-UAT}"
  local cmd="${3:-$subdir}"
  UAT_MODE_DIR="$RALPH_DIR/$subdir"
  UAT_PLAN_FILE="$UAT_MODE_DIR/plan.json"
  UAT_PROGRESS_FILE="$UAT_MODE_DIR/progress.txt"
  UAT_FAILURE_FILE="$UAT_MODE_DIR/last_failure.txt"
  UAT_SCREENSHOTS_DIR="$UAT_MODE_DIR/screenshots"
  UAT_MODE_LABEL="$label"
  UAT_CONFIG_NS="$subdir"
  UAT_CMD_NAME="$cmd"
}

# ============================================================================
# SHARED ARG PARSING
# ============================================================================

# Sets: _ARG_FOCUS, _ARG_PLAN_ONLY, _ARG_FORCE_REVIEW, _ARG_NO_FIX,
#       _ARG_MAX_ITERATIONS, _ARG_QUIET_MODE
_parse_uat_args() {
  _ARG_FOCUS=""
  _ARG_PLAN_ONLY=false
  _ARG_FORCE_REVIEW=false
  _ARG_NO_FIX=false
  _ARG_MAX_ITERATIONS=""
  _ARG_QUIET_MODE=$(get_config '.quiet' "false")

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --focus)
        _ARG_FOCUS="$2"
        shift 2
        ;;
      --plan-only)
        _ARG_PLAN_ONLY=true
        shift
        ;;
      --review)
        _ARG_FORCE_REVIEW=true
        shift
        ;;
      --no-fix)
        _ARG_NO_FIX=true
        shift
        ;;
      --max)
        _ARG_MAX_ITERATIONS="$2"
        shift 2
        ;;
      --quiet)
        _ARG_QUIET_MODE=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
}

# ============================================================================
# ENTRY POINT
# ============================================================================

run_uat() {
  _parse_uat_args "$@"

  local focus="$_ARG_FOCUS"
  local plan_only="$_ARG_PLAN_ONLY"
  local force_review="$_ARG_FORCE_REVIEW"
  local no_fix="$_ARG_NO_FIX"
  local max_iterations="$_ARG_MAX_ITERATIONS"
  local quiet_mode="$_ARG_QUIET_MODE"

  # Initialize directories for UAT mode
  _init_uat_dirs "uat" "UAT"

  # Validate prerequisites
  check_dependencies

  # Concurrent execution guard
  _acquire_uat_lock

  # Ensure directory structure
  mkdir -p "$UAT_MODE_DIR" "$UAT_SCREENSHOTS_DIR"

  # Banner
  _print_uat_banner

  # Phase 1: Discover + Plan
  if [[ ! -f "$UAT_PLAN_FILE" ]] || [[ "$force_review" == "true" ]] || [[ "$plan_only" == "true" ]]; then
    if [[ -f "$UAT_PLAN_FILE" ]] && [[ "$force_review" == "true" ]]; then
      print_info "Re-reviewing existing plan..."
    else
      echo ""
      print_info "Phase 1: Exploring your app and building a test plan"
      echo ""
      if ! _discover_and_plan "$quiet_mode" "uat"; then
        print_error "Something went wrong while exploring your app. See the progress log for details."
        return 1
      fi
    fi

    # Review the plan
    if ! _review_plan; then
      print_info "Plan review cancelled. No changes were made."
      return 0
    fi

    if [[ "$plan_only" == "true" ]]; then
      print_success "Plan generated. Run 'npx agentic-loop uat' to execute."
      return 0
    fi
  else
    local remaining
    remaining=$(jq '[.testCases[] | select(.passes==false)] | length' "$UAT_PLAN_FILE" 2>/dev/null || echo "0")
    print_info "Picking up where we left off ($remaining tests still to go)"
  fi

  # Phase 2: Execute Loop
  echo ""
  print_info "Phase 2: Running tests and fixing issues"
  echo ""
  _run_uat_loop "$focus" "$no_fix" "$max_iterations" "$quiet_mode"
  local loop_exit=$?

  # Phase 3: Report
  _print_report

  return $loop_exit
}

# ============================================================================
# CHAOS AGENT ENTRY POINT
# ============================================================================

run_chaos() {
  _parse_uat_args "$@"

  local focus="$_ARG_FOCUS"
  local plan_only="$_ARG_PLAN_ONLY"
  local force_review="$_ARG_FORCE_REVIEW"
  local no_fix="$_ARG_NO_FIX"
  local max_iterations="$_ARG_MAX_ITERATIONS"
  local quiet_mode="$_ARG_QUIET_MODE"

  # Initialize directories for chaos mode
  _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"

  # Validate prerequisites
  check_dependencies

  # Concurrent execution guard
  _acquire_uat_lock

  # Ensure directory structure
  mkdir -p "$UAT_MODE_DIR" "$UAT_SCREENSHOTS_DIR"

  # Banner
  _print_chaos_banner

  # Phase 1: Adversarial Discovery + Plan
  if [[ ! -f "$UAT_PLAN_FILE" ]] || [[ "$force_review" == "true" ]] || [[ "$plan_only" == "true" ]]; then
    if [[ -f "$UAT_PLAN_FILE" ]] && [[ "$force_review" == "true" ]]; then
      print_info "Re-reviewing existing plan..."
    else
      echo ""
      print_info "Phase 1: Red team exploring your app for vulnerabilities"
      echo ""
      if ! _discover_and_plan "$quiet_mode" "chaos"; then
        print_error "Something went wrong during red team exploration. See the progress log for details."
        return 1
      fi
    fi

    # Review the plan
    if ! _review_plan; then
      print_info "Plan review cancelled. No changes were made."
      return 0
    fi

    if [[ "$plan_only" == "true" ]]; then
      print_success "Plan generated. Run 'npx agentic-loop chaos-agent' to execute."
      return 0
    fi
  else
    local remaining
    remaining=$(jq '[.testCases[] | select(.passes==false)] | length' "$UAT_PLAN_FILE" 2>/dev/null || echo "0")
    print_info "Picking up where we left off ($remaining tests still to go)"
  fi

  # Phase 2: Testing for vulnerabilities and fixing issues
  echo ""
  print_info "Phase 2: Running attack tests and fixing issues"
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
      print_error "Another $UAT_MODE_LABEL session is already running. Stop it first with 'npx agentic-loop stop'."
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
  print_warning "Interrupted. Wrapping up $UAT_MODE_LABEL..."
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
  local mode="${2:-uat}"
  local prompt_file output_file
  prompt_file=$(create_temp_file ".uat-discover-prompt.md")
  output_file=$(create_temp_file ".uat-discover-output.log")

  local timeout
  if [[ "$mode" == "chaos" ]]; then
    timeout=$(get_config '.chaos.sessionSeconds' "$DEFAULT_CHAOS_SESSION_SECONDS")
    _build_chaos_agent_prompt "$prompt_file"
    _log_uat "DISCOVER" "Starting Chaos Agent discovery (timeout: ${timeout}s)"
  else
    timeout=$(get_config '.uat.sessionSeconds' "$DEFAULT_UAT_SESSION_SECONDS")
    _build_uat_team_prompt "$prompt_file"
    _log_uat "DISCOVER" "Starting UAT team discovery (timeout: ${timeout}s)"
  fi

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
    print_error "App exploration session failed"
    if [[ -f "$output_file" ]]; then
      echo "  Last output:"
      tail -10 "$output_file" | sed 's/^/    /'
    fi
    return 1
  fi

  # Validate plan was generated
  if [[ ! -f "$UAT_PLAN_FILE" ]]; then
    print_error "No test plan was created"
    echo ""
    echo "  The exploration finished but didn't produce a plan."
    echo "  Check the output above for what went wrong."
    return 1
  fi

  if ! _validate_plan; then
    print_error "The generated plan has errors and can't be used"
    return 1
  fi

  # Check if project-specific prompt was generated
  if [[ ! -f "$UAT_MODE_DIR/UAT-PROMPT.md" ]]; then
    print_warning "No project-specific test instructions were created."
    echo "    Tests will use generic patterns instead."
    echo "    For better results, re-run with 'npx agentic-loop $UAT_CMD_NAME --plan-only'."
  fi

  # Mark plan as generated
  update_json "$UAT_PLAN_FILE" '.testSuite.status = "planned"'

  local case_count
  case_count=$(jq '.testCases | length' "$UAT_PLAN_FILE")
  _log_uat "DISCOVER" "Plan generated with $case_count test cases"
  print_success "Plan generated: $case_count test cases"

  return 0
}

_build_uat_team_prompt() {
  local prompt_file="$1"

  # Start with UAT prompt template
  cat "$RALPH_TEMPLATES/UAT-PROMPT.md" > "$prompt_file"

  cat >> "$prompt_file" << 'PROMPT_SECTION'

---

## Phase: UAT Team Discovery + Plan Generation

You are the **team lead** of an acceptance testing team. Your job is to coordinate a team of
agents that explore a live app, verify features work correctly, and produce a comprehensive
UAT plan.

### Step 1: Recon (~60 seconds)

Before spawning anyone, do a quick recon yourself:

1. **Read `.ralph/config.json`** for URLs, auth config, and directories
2. **Read `.ralph/prd.json`** if it exists — completed stories tell you what was built
3. **Navigate the app** using Playwright MCP — click through nav, find pages, note the tech stack
4. **Take 2-3 screenshots** of key pages (save to `.ralph/uat/screenshots/`)
5. **Map the feature areas** — what exists? (auth, forms, API, navigation, etc.)

Don't go deep. Just map what's there. ~60 seconds max.

### Step 2: Assemble the UAT Team

Create a team and spawn teammates:

```
TeamCreate: "uat-team"
```

Spawn these teammates using the Task tool with `team_name: "uat-team"`:

1. **"recon"** (`subagent_type: "general-purpose"`) — Deep recon. Maps all routes/endpoints,
   catalogs forms with selectors, identifies tech stack and auth. Shares intel with teammates
   via SendMessage.

2. **"happy-path-{area}"** (`subagent_type: "general-purpose"`) — One per feature area.
   Completes primary user journeys, records correct behavior as ground truth assertions
   (exact text, redirects, success messages).

3. **"edge-cases"** (`subagent_type: "general-purpose"`) — Tests boundary conditions across
   all areas. Empty fields, long input, required-field validation, back button after submit,
   refresh mid-flow. Focus: does the app handle these gracefully?

**Only spawn agents for areas that exist.** If there are no forms, don't spawn a forms specialist.
If there's no auth, skip auth testing.

Mindset: **"Verify the app works correctly for real users."**

### Agent Instructions Template

Every agent prompt MUST include:

1. **Their role and focus area** (from above)
2. **The recon intel** — pages, URLs, tech stack you discovered in Step 1
3. **Browser tab isolation** — "Open your own browser tab via `browser_tabs(action: 'new')`
   before navigating. Do NOT use the existing tab."
4. **Communication** — "Share important discoveries with teammates via SendMessage.
   Examples: 'Login redirects to /dashboard after success', 'Registration form has 4 required fields',
   'Profile page shows user email and name'. Read messages from teammates and adapt your testing."
5. **Output format** — "When done, send your findings to the team lead via SendMessage.
   Format each finding as a test case with: title, category, testFile path, targetFiles,
   assertions (input/expected/strategy), and edgeCases."

### Step 3: Coordinate

While your team works:

- **Monitor messages** from teammates as they report findings
- **Redirect effort** if needed — if recon discovers something important, message the
  relevant specialist
- **Create tasks** in the shared task list for any new areas discovered

### Step 4: Collect + Merge + Write Plan

After all teammates finish:

1. Collect findings from all agent messages
2. Dedup by test file path (keep the case with more assertions)
3. Assign sequential IDs: `UAT-001`, `UAT-002`, ...
4. Write `.ralph/uat/plan.json` (schema below)
5. Write `.ralph/uat/UAT-PROMPT.md` (schema below)
6. Shut down all teammates via SendMessage with `type: "shutdown_request"`
7. Clean up with TeamDelete

### plan.json Schema

Write `.ralph/uat/plan.json`:

```json
{
  "testSuite": {
    "name": "UAT Loop",
    "generatedAt": "<ISO timestamp>",
    "status": "pending",
    "discoveryMethod": "uat-team"
  },
  "testCases": [
    {
      "id": "UAT-001",
      "title": "Feature area — what the test checks",
      "category": "auth|forms|navigation|api|ui|data",
      "type": "e2e|integration",
      "userStory": "As a user, I...",
      "testApproach": "What to test and how",
      "testFile": "tests/e2e/feature/test-name.spec.ts",
      "targetFiles": ["src/pages/feature.tsx"],
      "edgeCases": ["Edge case 1", "Edge case 2"],
      "assertions": [
        {
          "input": "Fill name='John', submit form",
          "expected": "Shows 'Welcome, John'",
          "strategy": "keyword"
        }
      ],
      "passes": false,
      "retryCount": 0,
      "source": "uat-team:agent-name"
    }
  ]
}
```

**Every test case MUST have at least 3 assertions** with concrete input/expected pairs:
1. One happy-path assertion (correct input → correct output)
2. One edge-case assertion (bad input → proper error handling)
3. One content assertion (page shows the RIGHT data, not just that it loads)

### UAT-PROMPT.md Schema

Write `.ralph/uat/UAT-PROMPT.md` — a project-specific testing guide based on what the
team ACTUALLY FOUND. Include:

```markdown
# UAT Guide — [Project Name]

## App Overview
- What the app does (1-2 sentences)
- Tech stack observed (framework, API patterns, auth method)
- Base URLs (frontend, API if applicable)

## Pages & Routes Discovered
For each page:
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

## What "Correct" Looks Like
For each feature area:
- Expected behavior observed
- Specific text/numbers that should appear

## Console & Network Observations
- Any existing console errors/warnings
- API endpoints observed
- Response patterns (JSON structure, status codes)
```

This is NOT a copy of the template — it's ground truth from the team's exploration.

### Rules

- Test auth flows FIRST (they gate everything else)
- One test case per feature area (not per edge case)
- Include edge cases as a list within each test case
- **Every test case MUST have assertions with input/expected pairs**
- `type: "e2e"` for anything involving browser interaction
- `type: "integration"` for API-only tests
- `targetFiles` should list the app source files the test covers
- `testFile` path should use the project's test directory conventions
- Aim for 5-15 test cases depending on app complexity
- Always clean up: shutdown teammates and delete team when done
PROMPT_SECTION

  _inject_prompt_context "$prompt_file"
}

_validate_plan() {
  # Check JSON is valid
  if ! jq -e '.' "$UAT_PLAN_FILE" >/dev/null 2>&1; then
    print_error "Test plan file is corrupted (not valid JSON)"
    return 1
  fi

  # Check required structure
  if ! jq -e '.testSuite and .testCases' "$UAT_PLAN_FILE" >/dev/null 2>&1; then
    print_error "Test plan is incomplete — missing required sections"
    return 1
  fi

  # Check test cases have required fields
  local invalid_cases
  invalid_cases=$(jq '[.testCases[] | select(.id == null or .title == null or .testFile == null)] | length' "$UAT_PLAN_FILE" 2>/dev/null)
  if [[ "$invalid_cases" -gt 0 ]]; then
    print_error "$invalid_cases test case(s) are incomplete — each needs an ID, title, and test file"
    return 1
  fi

  # Check test cases have assertions (the eval contract)
  local missing_assertions
  missing_assertions=$(jq '[.testCases[] | select((.assertions // []) | length < 1)] | length' "$UAT_PLAN_FILE" 2>/dev/null)
  if [[ "$missing_assertions" -gt 0 ]]; then
    print_warning "$missing_assertions test case(s) have no expected results defined — tests may not catch real issues"
    echo "    Each test case should describe what to check (input and expected outcome)."
    echo "    Run 'npx agentic-loop $UAT_CMD_NAME --review' to edit the plan and add them."
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
  printf "  │  %-54s│\n" "$UAT_MODE_LABEL Test Plan"
  echo "  └──────────────────────────────────────────────────────┘"
  echo ""

  local total_cases
  total_cases=$(jq '.testCases | length' "$UAT_PLAN_FILE")

  # Print summary table
  local idx=0
  while IFS=$'\t' read -r id title category tc_type edge_count assert_count; do
    idx=$((idx + 1))
    local type_icon=""
    case "$tc_type" in
      e2e) type_icon="🌐" ;;
      integration) type_icon="🔌" ;;
      *) type_icon="📝" ;;
    esac

    # Truncate title
    local display_title="$title"
    [[ ${#display_title} -gt 40 ]] && display_title="${display_title:0:37}..."

    printf "  %s %-10s %-40s [%s edge cases, %s checks]\n" "$type_icon" "$id" "$display_title" "$edge_count" "$assert_count"
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
        print_error "Your edits made the plan invalid. Please fix and try again."
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
  max_iterations="${max_iterations_arg:-$(get_config ".$UAT_CONFIG_NS.maxIterations" "$DEFAULT_UAT_MAX_ITERATIONS")}"
  local max_case_retries
  max_case_retries=$(get_config ".$UAT_CONFIG_NS.maxCaseRetries" "$DEFAULT_UAT_MAX_CASE_RETRIES")
  local timeout
  timeout=$(get_config ".$UAT_CONFIG_NS.maxSessionSeconds" "$DEFAULT_UAT_MAX_SESSION_SECONDS")

  local iteration=0

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
      print_warning "Stop requested. Finishing up..."
      break
    fi

    iteration=$((iteration + 1))

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
      print_warning "$case_id tried $max_case_retries times without success — skipping (needs manual review)"
      _flag_for_human "$case_id" "Tried $max_case_retries times without success"
      UAT_CASES_SKIPPED=$((UAT_CASES_SKIPPED + 1))
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
    local phase_label="Writing test"
    [[ "$current_phase" == "$UAT_PHASE_GREEN" ]] && phase_label="Fixing app"
    printf "│  %-14s  Type: %-6s  Attempt: %-3s                │\n" "$phase_label" "$case_type" "$((total_retries + 1))"
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
    print_warning "Test-writing session ended unexpectedly — will retry"
    _log_uat "$case_id" "RED: Session failed (exit $claude_exit)"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Check if test file was created
  if [[ ! -f "$test_file" ]]; then
    print_warning "$case_id: Test file was not created — will retry"
    _log_uat "$case_id" "RED: Test file not created"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Enforce RED constraint: no app changes allowed
  if _has_app_changes "$test_file"; then
    print_warning "$case_id: App code was changed during test-writing (not allowed) — undoing changes"
    _log_uat "$case_id" "RED: App changes detected — rollback"
    _rollback_to_snapshot "$case_id"
    _save_red_violation_feedback "$case_id"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  UAT_TESTS_WRITTEN=$((UAT_TESTS_WRITTEN + 1))

  # Validate test quality — reject shallow tests
  if ! _validate_test_quality "$test_file" "$case_id"; then
    print_warning "$case_id: Test doesn't check enough — will retry with better guidance"
    _save_shallow_test_feedback "$case_id" "$test_file"
    _increment_red_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Run the test
  if _run_test "$test_file" "$case_type"; then
    # PASS in RED — app already correct, no fix needed
    print_success "$case_id: Test passes — app already works correctly"
    _mark_passed "$case_id"
    _commit_result "$case_id" "$test_file"
    UAT_CASES_PASSED=$((UAT_CASES_PASSED + 1))
    UAT_RED_ONLY_PASSED=$((UAT_RED_ONLY_PASSED + 1))
    _log_uat "$case_id" "RED: PASSED (app already correct)"
  else
    # FAIL — classify: test bug or app bug?
    local failure_type
    failure_type=$(_classify_red_failure "$test_file" "$case_id")

    if [[ "$failure_type" == "test_bug" ]]; then
      print_warning "$case_id: Test has errors — will retry"
      _save_failure_context "$case_id" "$output_file"
      _increment_red_retry "$case_id"
    else
      # App bug found — commit the RED test, transition to GREEN
      print_info "$case_id: Found an app bug — now fixing it"
      UAT_BUGS_FOUND=$((UAT_BUGS_FOUND + 1))

      if [[ "$no_fix" == "true" ]]; then
        # --no-fix mode: commit failing test as documented bug
        print_info "$case_id: Saving test as a documented bug (fix skipped with --no-fix)"
        _commit_red_test "$case_id" "$test_file"
        _mark_passed "$case_id"
        UAT_CASES_PASSED=$((UAT_CASES_PASSED + 1))
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

  UAT_GREEN_ATTEMPTS=$((UAT_GREEN_ATTEMPTS + 1))

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
    print_warning "Fix session ended unexpectedly — will retry"
    _log_uat "$case_id" "GREEN: Session failed (exit $claude_exit)"
    _increment_green_retry "$case_id"
    rm -f "$output_file"
    return
  fi

  # Enforce GREEN constraint: no test file modifications
  if _test_file_modified "$test_file"; then
    print_warning "$case_id: Test file was changed during fix (not allowed) — restoring original"
    _restore_test_file "$test_file" "$case_id"
    _log_uat "$case_id" "GREEN: Test file restored after modification"
  fi

  # Run the test
  if _run_test "$test_file" "$case_type"; then
    # PASS — check for regressions before committing
    if _check_regressions; then
      print_success "$case_id: Fixed! Test passes and nothing else broke"
      _mark_passed "$case_id"
      _track_fixed_files "$case_id"
      UAT_BUGS_FIXED=$((UAT_BUGS_FIXED + 1))
      _commit_result "$case_id" "$test_file"
      UAT_CASES_PASSED=$((UAT_CASES_PASSED + 1))
      _log_uat "$case_id" "GREEN: PASSED"
    else
      # Regression detected — rollback
      print_error "$case_id: Fix broke other tests — undoing the change"
      _rollback_to_snapshot "$case_id"
      _flag_for_human "$case_id" "Fix broke other tests"
      _increment_green_retry "$case_id"
      _log_uat "$case_id" "GREEN: ROLLBACK — fix caused regression"
    fi
  else
    # FAIL — retry GREEN
    print_warning "$case_id: Fix didn't work — test still fails, will retry"
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
    cp "$log_file" "$UAT_MODE_DIR/last_test_output.log"
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
  assertion_count=$(grep -cE 'expect\(|assert\(|\.should\(' "$test_file" 2>/dev/null || true)

  if [[ "$assertion_count" -lt 2 ]]; then
    _log_uat "$case_id" "SHALLOW: only $assertion_count assertion(s)"
    return 1
  fi

  # Count content assertions — these verify the RIGHT data, not just structure
  # Includes: toContain, toHaveText, toBe, toEqual, toMatch, textContent, innerText
  local content_assertions
  content_assertions=$(grep -cE 'toContain\(|toHaveText\(|toBe\(|toEqual\(|toMatch\(|textContent|innerText|toHaveValue\(' "$test_file" 2>/dev/null || true)

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
  assertion_count=$(grep -cE 'expect\(|assert\(|\.should\(' "$test_file" 2>/dev/null || true)
  content_assertions=$(grep -cE 'toContain\(|toHaveText\(|toBe\(|toEqual\(|toMatch\(|textContent|innerText|toHaveValue\(' "$test_file" 2>/dev/null || true)

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
    echo "Fix: Read the assertions in .ralph/$UAT_CONFIG_NS/plan.json for this test case."
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
    if [[ -f "$UAT_MODE_DIR/last_test_output.log" ]]; then
      echo "--- Test Output ---"
      tail -50 "$UAT_MODE_DIR/last_test_output.log"
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
  local test_output="$UAT_MODE_DIR/last_test_output.log"
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
      git commit -m "$UAT_CONFIG_NS: snapshot before $case_id" --no-verify 2>/dev/null || true
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
      print_info "Reverted changes for $case_id"
    fi
  fi
}

_has_app_changes() {
  local test_file="$1"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    # Check if any files OTHER than the test file were modified
    local changed_files
    changed_files=$(git diff --name-only HEAD 2>/dev/null | grep -Fxv "$test_file" | grep -v '\.ralph/' || true)
    [[ -n "$changed_files" ]]
  else
    return 1
  fi
}

_check_regressions() {
  echo "  Making sure other tests still pass..."

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
    print_success "  All other tests still pass"
    rm -f "$log_file"
    return 0
  else
    print_error "  Some other tests broke!"
    echo "    Output (last 20 lines):"
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
    commit_msg="test($case_id): $UAT_CONFIG_NS test"
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
  if [[ -f "$UAT_MODE_DIR/UAT-PROMPT.md" ]]; then
    uat_prompt="$UAT_MODE_DIR/UAT-PROMPT.md"
  fi
  cat "$uat_prompt" > "$prompt_file"

  cat >> "$prompt_file" << PROMPT_SECTION

---

## Phase: RED — Write Test Only

You are in the **RED phase** of TDD. Your ONLY job is to write the test.

**CRITICAL: DO NOT modify any application source files. Test files ONLY.**

Your tasks:

1. **Read the test case** from \`.ralph/$UAT_CONFIG_NS/plan.json\` (case ID: $case_id)
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
2. **Read the test case** from \`.ralph/$UAT_CONFIG_NS/plan.json\` (case ID: $case_id) for context
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
  if [[ -f "$UAT_MODE_DIR/last_test_output.log" ]]; then
    echo "" >> "$prompt_file"
    echo "## Last Test Output" >> "$prompt_file"
    echo "" >> "$prompt_file"
    echo '```' >> "$prompt_file"
    tail -80 "$UAT_MODE_DIR/last_test_output.log" >> "$prompt_file"
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
  printf "║             %-14s Results                        ║\n" "$UAT_MODE_LABEL"
  echo "╠══════════════════════════════════════════════════════════╣"
  printf "║  Test cases:  %-3s total, %-3s passed, %-3s failed, %-3s skipped  ║\n" \
    "$total_cases" "$passed_cases" "$failed_cases" "$skipped_cases"
  printf "║  App bugs found: %-3s   Fixed: %-3s                        ║\n" \
    "$UAT_BUGS_FOUND" "$UAT_BUGS_FIXED"
  printf "║  Already working: %-3s   Needed fixing: %-3s                ║\n" \
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
    echo "║  Needs your attention:                                   ║"
    for item in "${UAT_NEEDS_HUMAN[@]}"; do
      local display="$item"
      [[ ${#display} -gt 54 ]] && display="${display:0:51}..."
      printf "║    %-54s║\n" "$display"
    done
  fi

  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  # Send notification
  send_notification "$UAT_MODE_LABEL: $passed_cases/$total_cases passed, $UAT_BUGS_FIXED bugs fixed"
}

# ============================================================================
# BANNER
# ============================================================================

_print_uat_banner() {
  echo ""
  echo "  _   _   _  _____   _                    "
  echo " | | | | / \\|_   _| | |    ___   ___  _ __"
  echo " | | | |/ _ \\ | |   | |   / _ \\ / _ \\| '_ \\"
  echo " | |_| / ___ \\| |   | |__| (_) | (_) | |_) |"
  echo "  \\___/_/   \\_\\_|   |_____\\___/ \\___/| .__/"
  echo "                                      |_|"
  echo ""
}

_print_chaos_banner() {
  echo ""
  echo "   ____ _                       _                    _   "
  echo "  / ___| |__   __ _  ___  ___  / \\   __ _  ___ _ __ | |_ "
  echo " | |   | '_ \\ / _\` |/ _ \\/ __|| _ \\ / _\` |/ _ \\ '_ \\| __|"
  echo " | |___| | | | (_| | (_) \\__ \\/ ___ \\ (_| |  __/ | | | |_ "
  echo "  \\____|_| |_|\\__,_|\\___/|___/_/   \\_\\__, |\\___|_| |_|\\__|"
  echo "                                      |___/               "
  echo "  Red team mode — trying to break things"
  echo ""
}

# ============================================================================
# CHAOS AGENT PROMPT
# ============================================================================

_build_chaos_agent_prompt() {
  local prompt_file="$1"

  # Start with UAT prompt template
  cat "$RALPH_TEMPLATES/UAT-PROMPT.md" > "$prompt_file"

  cat >> "$prompt_file" << 'PROMPT_SECTION'

---

## Phase: Chaos Agent Red Team Discovery

You are the **team lead** of a red team. Your job is to coordinate a team of adversarial
agents that attack a live app, share intel, and produce a battle-tested plan of
vulnerabilities to fix.

**Mindset: "You are a red team. Coordinate to find every vulnerability."**

### Step 1: Recon (~60 seconds)

Before spawning anyone, do a quick recon yourself:

1. **Read `.ralph/config.json`** for URLs, auth config, and directories
2. **Read `.ralph/prd.json`** if it exists — completed stories tell you what was built
3. **Navigate the app** using Playwright MCP — click through nav, find pages, note the tech stack
4. **Take 2-3 screenshots** of key pages (save to `.ralph/chaos/screenshots/`)
5. **Map the attack surface** — what feature areas exist? (auth, forms, API, navigation, etc.)

Don't go deep. Just map what's there. ~60 seconds max.

### Step 2: Assemble the Red Team

Create a team and spawn teammates:

```
TeamCreate: "chaos-agent"
```

Spawn these teammates using the Task tool with `team_name: "chaos-agent"`:

1. **"recon"** (`subagent_type: "general-purpose"`) — Attack surface mapping. Catalogs every
   input, form, API endpoint, auth mechanism. Shares intel with team: "login uses JWT in
   localStorage", "admin panel at /admin has no auth check".

2. **"chaos"** (`subagent_type: "general-purpose"`) — Chaos testing. For every input: empty
   strings, 10000-char payloads, special characters (`<>&"'/\`), unicode/emoji, null bytes.
   For every form: double-submit, missing fields, back button after submit. Rapid-fire
   interactions.

3. **"security"** (`subagent_type: "general-purpose"`) — Security testing. XSS in every
   input (`<script>alert(1)</script>`), SQL injection (`'; DROP TABLE users; --`), auth bypass
   via direct URL, IDOR via ID manipulation, sensitive data in localStorage/console/page source,
   missing CSRF tokens.

**Only spawn agents for areas that exist.** If there are no forms, don't spawn a forms specialist.
If there's no auth, skip auth testing.

Agents communicate via SendMessage — recon shares discoveries, security acts on them.

### Agent Instructions Template

Every agent prompt MUST include:

1. **Their role and focus area** (from above)
2. **The recon intel** — pages, URLs, tech stack you discovered in Step 1
3. **Browser tab isolation** — "Open your own browser tab via `browser_tabs(action: 'new')`
   before navigating. Do NOT use the existing tab."
4. **Communication** — "Share important discoveries with teammates via SendMessage.
   Examples: 'Auth uses JWT in localStorage', 'Found unprotected admin route at /admin',
   'Form at /profile has no CSRF token'. Read messages from teammates and adapt your testing."
5. **Output format** — "When done, send your findings to the team lead via SendMessage.
   Format each finding as a test case with: title, category, testFile path, targetFiles,
   assertions (input/expected/strategy), and edgeCases."

### Step 3: Coordinate

While your team works:

- **Monitor messages** from teammates as they report findings
- **Redirect effort** if needed — if recon discovers something important, message the
  relevant specialist ("recon found an admin panel at /admin — security, check it for auth bypass")
- **Create tasks** in the shared task list for any new areas discovered

### Step 4: Collect + Merge + Write Plan

After all teammates finish:

1. Collect findings from all agent messages
2. Dedup by test file path (keep the case with more assertions)
3. Assign sequential IDs: `UAT-001`, `UAT-002`, ...
4. Write `.ralph/chaos/plan.json` (schema below)
5. Write `.ralph/chaos/UAT-PROMPT.md` (schema below)
6. Shut down all teammates via SendMessage with `type: "shutdown_request"`
7. Clean up with TeamDelete

### plan.json Schema

Write `.ralph/chaos/plan.json`:

```json
{
  "testSuite": {
    "name": "Chaos Agent",
    "generatedAt": "<ISO timestamp>",
    "status": "pending",
    "discoveryMethod": "chaos-agent"
  },
  "testCases": [
    {
      "id": "UAT-001",
      "title": "Feature area — what the test checks",
      "category": "auth|forms|navigation|api|ui|data|security",
      "type": "e2e|integration",
      "userStory": "As a user, I...",
      "testApproach": "What to test and how",
      "testFile": "tests/e2e/feature/test-name.spec.ts",
      "targetFiles": ["src/pages/feature.tsx"],
      "edgeCases": ["Edge case 1", "Edge case 2"],
      "assertions": [
        {
          "input": "Fill name='<script>alert(1)</script>', submit form",
          "expected": "Name displayed as literal text, no script execution",
          "strategy": "security"
        }
      ],
      "passes": false,
      "retryCount": 0,
      "source": "chaos-agent:agent-name"
    }
  ]
}
```

**Every test case MUST have at least 3 assertions** with concrete input/expected pairs:
1. One happy-path assertion (correct input → correct output)
2. One edge-case assertion (bad input → proper error handling)
3. One content assertion (page shows the RIGHT data, not just that it loads)

### UAT-PROMPT.md Schema

Write `.ralph/chaos/UAT-PROMPT.md` — a project-specific testing guide based on what the
red team ACTUALLY FOUND. Include:

```markdown
# Chaos Agent Guide — [Project Name]

## App Overview
- What the app does (1-2 sentences)
- Tech stack observed (framework, API patterns, auth method)
- Base URLs (frontend, API if applicable)

## Pages & Routes Discovered
For each page:
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

## What "Correct" Looks Like
For each feature area:
- Expected behavior observed
- Specific text/numbers that should appear

## Console & Network Observations
- Any existing console errors/warnings
- API endpoints observed
- Response patterns (JSON structure, status codes)

## Red Team Findings
- Vulnerabilities discovered (XSS, injection, auth bypass, etc.)
- Edge cases that broke the app
- Areas that need hardening
```

This is NOT a copy of the template — it's ground truth from the red team's exploration.

### Rules

- Test auth flows FIRST (they gate everything else)
- One test case per feature area per attack vector
- `type: "e2e"` for anything involving browser interaction
- `targetFiles` should list the app source files the test covers
- `testFile` path should use the project's test directory conventions
- Always clean up: shutdown teammates and delete team when done
PROMPT_SECTION

  _inject_prompt_context "$prompt_file"
}

# ============================================================================
# HELPERS
# ============================================================================

_inject_prompt_context() {
  local prompt_file="$1"

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

_log_uat() {
  local id="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  echo "[$timestamp] $id $msg" >> "$UAT_PROGRESS_FILE"
}
