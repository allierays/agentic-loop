#!/usr/bin/env bash
# shellcheck shell=bash
# loop.sh - The autonomous development loop

# Check for newer version on npm and offer to update
check_for_updates() {
  local cache_file="$RALPH_DIR/.update_cache"

  # Skip if checked recently (once per day)
  if [[ -f "$cache_file" ]]; then
    local cached_time
    read -r cached_time _ < "$cache_file"
    local now
    now=$(date +%s)
    if [[ $(( now - cached_time )) -lt $UPDATE_CHECK_TTL_SECONDS ]]; then
      return 0
    fi
  fi

  local latest
  latest=$(timeout 5 npm view agentic-loop version --json 2>/dev/null | tr -d '"' || echo "")
  # Fall back to gtimeout on macOS if timeout isn't available
  if [[ -z "$latest" ]] && command -v gtimeout &>/dev/null; then
    latest=$(gtimeout 5 npm view agentic-loop version --json 2>/dev/null | tr -d '"' || echo "")
  fi

  # Write cache regardless of result (don't retry on failure)
  echo "$(date +%s) $latest" > "$cache_file"

  # If registry unreachable or empty, skip silently
  [[ -z "$latest" ]] && return 0

  # Compare versions — if already current or newer, skip
  if [[ "$RALPH_VERSION" == "$latest" ]]; then
    return 0
  fi

  # Simple semver comparison: split on dots and compare numerically
  local IFS='.'
  # shellcheck disable=SC2206  # Intentional word-split on IFS='.'
  local -a current_parts=($RALPH_VERSION)
  # shellcheck disable=SC2206
  local -a latest_parts=($latest)

  local i
  for i in 0 1 2; do
    local c="${current_parts[$i]:-0}"
    local l="${latest_parts[$i]:-0}"
    if [[ "$c" -gt "$l" ]]; then
      return 0  # Current is ahead (dev build)
    elif [[ "$c" -lt "$l" ]]; then
      break  # Current is behind — needs update
    fi
  done

  echo ""
  print_warning "Update available: v$RALPH_VERSION → v$latest"

  # Detect install method to determine update command
  local update_cmd=""
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  if [[ "$script_path" == *"node_modules/agentic-loop"* ]]; then
    # Local install
    update_cmd="npm update agentic-loop"
  elif npm list -g agentic-loop --depth=0 &>/dev/null 2>&1; then
    # Global install
    update_cmd="npm update -g agentic-loop"
  else
    # npx or unknown — use npx with latest
    update_cmd="npx agentic-loop@latest"
  fi

  read -r -p "  Update now and restart? [Y/n] " response
  if [[ "$response" =~ ^[Nn] ]]; then
    echo "  Skipping update. Run: $update_cmd"
    echo ""
    return 0
  fi

  echo "  Updating..."
  if [[ "$update_cmd" == "npx agentic-loop@latest" ]]; then
    # For npx users, clear the cache so next npx call fetches latest
    local npx_cache
    npx_cache=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
    rm -rf "${npx_cache}/_npx" 2>/dev/null || true
    print_success "  npx cache cleared — restarting with v$latest..."
    echo ""
    exec npx agentic-loop@latest run "$@"
  else
    if $update_cmd 2>&1 | tail -3; then
      print_success "  Updated to v$latest — restarting..."
      echo ""
      # Re-exec ralph.sh with "run" + original args
      local ralph_bin
      ralph_bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/ralph.sh"
      exec "$ralph_bin" run "$@"
    else
      print_warning "  Update failed. Run manually: $update_cmd"
      echo ""
    fi
  fi
}

# Pre-loop checks to catch common issues before wasting iterations
preflight_checks() {
  echo ""
  echo "  ┌──────────────────────────────────┐"
  echo "  │  ✅ Pre-Loop Checks              │"
  echo "  └──────────────────────────────────┘"
  echo ""
  local warnings=0

  # Check API connectivity if configured
  local api_url
  api_url=$(get_config '.api.baseUrl' "")
  if [[ -n "$api_url" ]]; then
    printf "  API connectivity ($api_url)... "
    if curl -sf --connect-timeout 5 "$api_url" >/dev/null 2>&1 || \
       curl -sf --connect-timeout 5 "${api_url}/health" >/dev/null 2>&1 || \
       curl -sf --connect-timeout 5 "${api_url}/api/health" >/dev/null 2>&1; then
      print_success "ok"
    else
      print_warning "unreachable"
      echo "    Is your API server running?"
      ((warnings++))
    fi
  fi

  # Check frontend connectivity if configured
  local test_url
  test_url=$(get_config '.urls.frontend' "")
  if [[ -n "$test_url" ]]; then
    printf "  Frontend connectivity ($test_url)... "
    if curl -sf --connect-timeout 5 "$test_url" >/dev/null 2>&1; then
      print_success "ok"
    else
      print_warning "unreachable"
      echo "    Is your frontend dev server running?"
      ((warnings++))
    fi
  fi

  # Check for common migration issues in Python projects
  local backend_dir
  backend_dir=$(get_config '.directories.backend' "")
  if [[ -n "$backend_dir" && -d "$backend_dir" ]]; then
    # Check for alembic migrations
    if [[ -d "$backend_dir/alembic" ]] || [[ -d "$backend_dir/migrations" ]]; then
      printf "  Database migrations... "
      # Detect Python runner (python3 for macOS compatibility)
      local py_runner="python3"
      if [[ -f "$backend_dir/uv.lock" ]]; then
        py_runner="uv run"
      elif [[ -f "$backend_dir/poetry.lock" ]]; then
        py_runner="poetry run"
      fi
      # Try to verify DB connection via alembic
      if [[ -f "$backend_dir/alembic.ini" ]]; then
        if (cd "$backend_dir" && $py_runner alembic current >/dev/null 2>&1); then
          print_success "ok"
        elif docker compose exec -T api alembic current >/dev/null 2>&1; then
          # Try via Docker if local fails
          print_success "ok (via docker)"
        else
          print_warning "check DB connection"
          echo "    Run: cd $backend_dir && $py_runner alembic current"
          ((warnings++))
        fi
      fi
    fi
  fi

  # Check Docker if docker-compose exists
  for compose_file in "docker-compose.yml" "docker-compose.yaml" "compose.yml"; do
    if [[ -f "$compose_file" ]]; then
      printf "  Docker services... "
      if docker compose ps --quiet 2>/dev/null | grep -q .; then
        print_success "running"
      elif docker-compose ps --quiet 2>/dev/null | grep -q .; then
        print_success "running"
      else
        print_warning "not running"
        echo "    Run: docker compose up -d"
        ((warnings++))
      fi
      break
    fi
  done

  # Check for timeout utility (critical for session enforcement)
  printf "  Timeout utility... "
  if command -v timeout &>/dev/null; then
    print_success "ok (timeout)"
  elif command -v gtimeout &>/dev/null; then
    print_success "ok (gtimeout)"
  else
    print_warning "not found (using bash fallback)"
    echo "    Session timeouts use a bash fallback. For better reliability:"
    if [[ "$(uname)" == "Darwin" ]]; then
      echo "    brew install coreutils"
    else
      echo "    Install GNU coreutils"
    fi
    ((warnings++))
  fi

  echo ""
  if [[ $warnings -gt 0 ]]; then
    print_warning "$warnings pre-loop warning(s) - loop may fail on connectivity issues"
    echo ""
    read -r -p "Continue anyway? [Y/n] " response
    if [[ "$response" =~ ^[Nn] ]]; then
      echo "Aborted. Fix the issues and try again."
      exit 1
    fi
    return 1  # Had warnings — don't cache this result
  fi
}

# ============================================================================
# PREFLIGHT / PRD CACHE
# ============================================================================
# Caches preflight and PRD validation results so restarts within 10 minutes
# skip the slow connectivity checks and Claude auto-fix.
# Cache is invalidated by TTL expiry or config/PRD file changes (by hash).

_file_hash() {
  [[ ! -f "$1" ]] && echo "no_file" && return
  if command -v md5sum &>/dev/null; then
    md5sum "$1" 2>/dev/null | cut -d' ' -f1
  else
    md5 -q "$1" 2>/dev/null
  fi
}

_is_preflight_cached() {
  local cache_file="$RALPH_DIR/.preflight_cache"
  [[ ! -f "$cache_file" ]] && return 1

  local cached_time cached_hash
  read -r cached_time cached_hash < "$cache_file"

  local now
  now=$(date +%s)
  [[ $(( now - cached_time )) -gt $PREFLIGHT_CACHE_TTL_SECONDS ]] && return 1

  local config_hash
  config_hash=$(_file_hash "$RALPH_DIR/config.json")
  [[ "$cached_hash" != "$config_hash" ]] && return 1

  return 0
}

_write_preflight_cache() {
  local config_hash
  config_hash=$(_file_hash "$RALPH_DIR/config.json")
  echo "$(date +%s) $config_hash" > "$RALPH_DIR/.preflight_cache"
}

_prd_structure_hash() {
  # Hash only the fields that PRD validation cares about (story structure, testSteps, etc.)
  # Ignores runtime state (passes, retryCount, skipped) so loop progress doesn't
  # invalidate the validation cache and trigger expensive re-fixes on every restart.
  jq '[.stories[] | del(.passes, .retryCount, .skipped, .skipReason)] | sort_by(.id)' \
    "$RALPH_DIR/prd.json" 2>/dev/null | _file_hash_stdin
}

_file_hash_stdin() {
  if command -v md5sum &>/dev/null; then
    md5sum | cut -d' ' -f1
  else
    md5 -q
  fi
}

_is_prd_cached() {
  local cache_file="$RALPH_DIR/.prd_validated"
  [[ ! -f "$cache_file" ]] && return 1

  local cached_time cached_hash
  read -r cached_time cached_hash < "$cache_file"

  local now
  now=$(date +%s)
  [[ $(( now - cached_time )) -gt $PREFLIGHT_CACHE_TTL_SECONDS ]] && return 1

  local prd_hash
  prd_hash=$(_prd_structure_hash)
  [[ "$cached_hash" != "$prd_hash" ]] && return 1

  return 0
}

_write_prd_cache() {
  local prd_hash
  prd_hash=$(_prd_structure_hash)
  echo "$(date +%s) $prd_hash" > "$RALPH_DIR/.prd_validated"
}

# Check if failure context is trivial (lint/format-only retries)
# Returns 0 (trivial) if ALL error lines match trivial patterns
_is_trivial_failure() {
  local context="$1"

  # Count non-empty, non-whitespace lines
  local total_lines
  total_lines=$(printf '%s\n' "$context" | grep -cE '\S' || echo "0")

  # If very short context, consider trivial
  [[ "$total_lines" -lt 3 ]] && return 0

  # Count error/warning/fail lines that do NOT match trivial patterns
  # Trivial patterns: auto-fix, formatting tools, style-only issues
  local non_trivial_errors
  non_trivial_errors=$(printf '%s\n' "$context" | grep -iE '(error|warning|fail)' | \
    grep -cviE '(auto.?fix|prettier|eslint --fix|trailing whitespace|import order|isort|black|ruff format|ruff check.*--fix|no-unused-vars|Missing semicolon|Expected indentation)' \
    || echo "0")

  # Trivial if no error lines survive the trivial-pattern filter
  [[ "$non_trivial_errors" -eq 0 ]] && return 0

  return 1
}

# Check if a proposed sign pattern is a duplicate of existing signs
# Returns 0 (is duplicate) if pattern is too similar to existing
_sign_is_duplicate() {
  local pattern="$1"

  [[ ! -f "$RALPH_DIR/signs.json" ]] && return 1

  # Normalize: lowercase, strip punctuation
  local normalized
  normalized=$(printf '%s\n' "$pattern" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr -s ' ')

  # Check each existing sign
  local existing_patterns
  existing_patterns=$(jq -r '.signs[].pattern' "$RALPH_DIR/signs.json" 2>/dev/null)

  while IFS= read -r existing; do
    [[ -z "$existing" ]] && continue

    local existing_normalized
    existing_normalized=$(printf '%s\n' "$existing" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr -s ' ')

    # Substring match in either direction (only for patterns long enough to be meaningful)
    local shorter_len=${#normalized}
    [[ ${#existing_normalized} -lt $shorter_len ]] && shorter_len=${#existing_normalized}
    if [[ $shorter_len -ge 30 ]]; then
      if [[ "$normalized" == *"$existing_normalized"* ]] || [[ "$existing_normalized" == *"$normalized"* ]]; then
        return 0
      fi
    fi

    # Keyword overlap: extract words 4+ chars, flag as duplicate if >60% overlap
    local new_words existing_words
    new_words=$(printf '%s\n' "$normalized" | tr ' ' '\n' | awk 'length >= 4' | sort -u)
    existing_words=$(printf '%s\n' "$existing_normalized" | tr ' ' '\n' | awk 'length >= 4' | sort -u)

    local new_count overlap_count
    new_count=$(printf '%s\n' "$new_words" | grep -cE '\S' || echo "0")
    [[ "$new_count" -eq 0 ]] && continue

    # Count overlapping words (use -xF for whole-line match, not substring)
    overlap_count=0
    while IFS= read -r word; do
      [[ -z "$word" ]] && continue
      if printf '%s\n' "$existing_words" | grep -qxF "$word"; then
        overlap_count=$((overlap_count + 1))
      fi
    done <<< "$new_words"

    # >60% overlap = duplicate
    if [[ $((overlap_count * 100 / new_count)) -gt 60 ]]; then
      return 0
    fi
  done <<< "$existing_patterns"

  return 1
}

# Auto-promote a sign from retry failure context
# Called when a story passes after multiple retries
_maybe_promote_sign() {
  local story="$1"
  local retries="$2"
  local config="$RALPH_DIR/config.json"

  # Check config: read .autoPromoteSigns directly (avoid get_config - its // operator
  # treats false as falsy and returns the default). Default to true if key is absent/null.
  if [[ -f "$config" ]]; then
    local auto_promote
    auto_promote=$(jq -r '.autoPromoteSigns' "$config" 2>/dev/null)
    if [[ "$auto_promote" == "false" ]]; then
      return 0
    fi
  fi

  # Read failure context (safety check - caller also gates on file existence)
  local failure_context
  if [[ ! -f "$RALPH_DIR/last_failure.txt" ]]; then
    return 0
  fi
  failure_context=$(head -"$MAX_SIGN_CONTEXT_LINES" "$RALPH_DIR/last_failure.txt")

  # Skip trivial failures (lint/format only)
  if _is_trivial_failure "$failure_context"; then
    log_progress "$story" "SIGN_AUTO" "Skipped - trivial failure (lint/format only)"
    return 0
  fi

  # Load existing sign patterns for dedup context
  local existing_signs=""
  if [[ -f "$RALPH_DIR/signs.json" ]]; then
    existing_signs=$(jq -r '.signs[].pattern' "$RALPH_DIR/signs.json" 2>/dev/null | head -"$MAX_SIGN_DEDUP_EXISTING")
  fi

  # Build extraction prompt
  local prompt
  prompt="You are analyzing a development failure that was resolved after $retries attempts.

Extract ONE reusable pattern (a \"sign\") that would prevent this failure in future stories.

## Failure Context
\`\`\`
$failure_context
\`\`\`

## Existing Signs (do NOT duplicate these)
$existing_signs

## Rules
- Extract a single, actionable pattern that prevents this class of failure
- The pattern should be general enough to apply to future stories, not specific to this one
- NEVER include credentials, passwords, API keys, tokens, emails, or secrets in the pattern
  Instead of: \"Login with admin@example.com / Password123\"
  Write: \"Use Playwright to login with test credentials from environment variables\"
- If the failure is trivial, unclear, or you can't extract a useful pattern, respond with just: NONE
- Category must be one of: backend, frontend, testing, general, database, security

## Good Examples
CATEGORY: backend
PATTERN: Always run database migrations before executing test suites

CATEGORY: testing
PATTERN: Use waitFor() instead of fixed delays when testing async UI updates

CATEGORY: frontend
PATTERN: Import CSS modules with .module.css extension in Next.js projects

## Bad Examples (too specific, too vague)
PATTERN: Fix the login button color  (too specific to one story)
PATTERN: Write better code  (too vague to be actionable)
PATTERN: Always check for errors  (too vague)

## Response Format
Respond with exactly two lines (or just NONE):
CATEGORY: <category>
PATTERN: <pattern>"

  # Call Claude with timeout (one-shot, non-interactive)
  local response
  response=$(printf '%s\n' "$prompt" | run_with_timeout "$SIGN_EXTRACTION_TIMEOUT_SECONDS" claude -p 2>/dev/null) || {
    log_progress "$story" "SIGN_AUTO" "Skipped - Claude extraction timed out"
    return 0
  }

  # Check for NONE response
  if printf '%s\n' "$response" | grep -qi '^NONE'; then
    log_progress "$story" "SIGN_AUTO" "Skipped - no actionable pattern found"
    return 0
  fi

  # Parse response for CATEGORY: and PATTERN: lines (use sed, not grep -P for macOS)
  local category pattern
  category=$(echo "$response" | sed -n 's/^CATEGORY:[[:space:]]*//p' | head -1 | tr -d '\r')
  pattern=$(echo "$response" | sed -n 's/^PATTERN:[[:space:]]*//p' | head -1 | tr -d '\r')

  # Validate extracted values
  if [[ -z "$category" || -z "$pattern" ]]; then
    log_progress "$story" "SIGN_AUTO" "Skipped - could not parse Claude response"
    return 0
  fi

  # Validate category
  case "$category" in
    backend|frontend|testing|general|database|security) ;;
    *)
      log_progress "$story" "SIGN_AUTO" "Skipped - invalid category: $category"
      return 0
      ;;
  esac

  # Reject signs that contain credentials or secrets
  if echo "$pattern" | grep -qiE '([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|password[[:space:]]*[:=]|[[:space:]][A-Za-z0-9_]*_?(pass|pwd|token|secret|key|api.?key)[[:space:]]*[:=]|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36})'; then
    log_progress "$story" "SIGN_AUTO" "Skipped - pattern contains credentials"
    return 0
  fi

  # Check for duplicates before adding
  if _sign_is_duplicate "$pattern"; then
    log_progress "$story" "SIGN_AUTO" "Skipped - duplicate of existing sign"
    return 0
  fi

  # Add the sign (3rd arg = autoPromoted, 4th arg = learnedFrom override)
  if ralph_sign "$pattern" "$category" "true" "$story"; then
    log_progress "$story" "SIGN_AUTO" "Added [$category]: $pattern"
    print_info "Auto-promoted sign: [$category] $pattern"
  else
    log_progress "$story" "SIGN_AUTO" "Failed to add sign"
  fi

  return 0
}

# Generate a starter docker-compose.yml based on detected project type
_generate_docker_compose() {
  local project_type
  project_type=$(detect_project_type)

  local compose_content=""

  case "$project_type" in
    fullstack|django|fastapi|python|node)
      compose_content="services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
      POSTGRES_DB: app_dev
    ports:
      - \"5432:5432\"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U app\"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - \"6379:6379\"
    healthcheck:
      test: [\"CMD\", \"redis-cli\", \"ping\"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:"
      ;;
    go|rust)
      compose_content="services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
      POSTGRES_DB: app_dev
    ports:
      - \"5432:5432\"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U app\"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:"
      ;;
    elixir)
      compose_content="services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app_dev
    ports:
      - \"5432:5432\"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: [\"CMD-SHELL\", \"pg_isready -U postgres\"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:"
      ;;
    fastmcp)
      compose_content="services:
  app:
    build: .
    ports:
      - \"8000:8000\"
    volumes:
      - .:/app
    environment:
      - LOG_LEVEL=debug"
      ;;
    *)
      # minimal or unknown — shouldn't reach here but handle gracefully
      print_warning "No Docker template for project type: $project_type"
      return 1
      ;;
  esac

  echo "$compose_content" > docker-compose.yml
  print_success "Generated docker-compose.yml for $project_type project"
  echo ""
  echo "  Services:"
  grep -E '^[[:space:]]{2}[a-z]' docker-compose.yml | sed 's/:$//' | sed 's/^/    /'
  echo ""
  echo "  Next steps:"
  echo "    docker compose up -d"
  echo "    docker compose ps        # verify services are healthy"
  echo ""
  echo "  Update your .env to point at the Docker services:"
  case "$project_type" in
    elixir)
      echo "    DATABASE_URL=ecto://postgres:postgres@localhost:5432/app_dev"
      ;;
    fastmcp)
      ;;
    *)
      echo "    DATABASE_URL=postgresql://app:app@localhost:5432/app_dev"
      echo "    REDIS_URL=redis://localhost:6379"
      ;;
  esac
  echo ""
}

# Check for Docker compose files and warn if missing
# Called from run_loop() before preflight checks
_docker_safety_warning() {
  # Skip if env var is set
  [[ "${RALPH_SKIP_DOCKER_WARNING:-}" == "1" ]] && return 0

  # Skip if docker.enabled is true in config
  local docker_enabled
  docker_enabled=$(get_config '.docker.enabled' "false")
  if [[ "$docker_enabled" == "true" ]]; then
    return 0
  fi

  # Skip if project type doesn't need services
  local project_type
  project_type=$(detect_project_type)
  if [[ "$project_type" == "minimal" || "$project_type" == "hugo" ]]; then
    return 0
  fi

  # Check for any compose file
  for compose_file in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
    if [[ -f "$compose_file" ]]; then
      return 0
    fi
  done

  # No compose file found — show warning
  echo ""
  echo "  ╔══════════════════════════════════════════════════════════════════╗"
  echo "  ║                                                                  ║"
  echo "  ║   ⚠️  YOUR PROJECT IS NOT USING DOCKER                          ║"
  echo "  ║                                                                  ║"
  echo "  ║   Ralph runs autonomously — it writes code, runs commands,       ║"
  echo "  ║   and executes migrations without asking.                        ║"
  echo "  ║                                                                  ║"
  echo "  ║   Without Docker, Ralph operates directly on your local          ║"
  echo "  ║   machine. A bad migration can corrupt real databases.           ║"
  echo "  ║   A runaway command can affect services outside this repo.       ║"
  echo "  ║                                                                  ║"
  echo "  ║   With Docker, your project's services are isolated:             ║"
  echo "  ║     - Databases and caches run in containers, not locally        ║"
  echo "  ║     - Nothing outside the project is touched                     ║"
  echo "  ║     - Reset anytime: docker compose down -v && up -d             ║"
  echo "  ║                                                                  ║"
  echo "  ║   Suppress: RALPH_SKIP_DOCKER_WARNING=1 npx agentic-loop run    ║"
  echo "  ║                                                                  ║"
  echo "  ╚══════════════════════════════════════════════════════════════════╝"
  echo ""

  local response
  read -r -p "  [S]et up Docker now  |  [C]ontinue without Docker  |  [Q]uit: " response

  case "$response" in
    [Ss])
      echo ""
      if ! _generate_docker_compose; then
        print_info "You can create a docker-compose.yml manually, or continue without Docker."
      fi
      ;;
    [Qq])
      echo ""
      echo "  Exiting. Set up Docker and try again, or suppress with:"
      echo "    RALPH_SKIP_DOCKER_WARNING=1 npx agentic-loop run"
      echo ""
      exit 0
      ;;
    *)
      # Default: continue
      echo ""
      print_info "Continuing without Docker. Suppress future warnings with:"
      echo "    RALPH_SKIP_DOCKER_WARNING=1 npx agentic-loop run"
      echo ""
      ;;
  esac
}

run_loop() {
  # Save original args for update restart
  local _original_args=("$@")

  # PID of the currently running Claude pipeline (used by trap to kill it)
  _CLAUDE_PIPELINE_PID=""

  # Trap Ctrl+C to kill Claude and stop the loop.
  # When Claude runs as a foreground pipeline, bash defers trap handling until the
  # pipeline exits — so Ctrl+C just gets swallowed. We solve this by running the
  # pipeline in a background subshell and `wait`ing for it, which lets the trap
  # fire immediately. The trap kills the subshell, touches .stop, then exits.
  trap '
    restore_terminal_bg
    echo ""
    print_warning "Ctrl+C received — stopping loop..."
    [[ -n "$_CLAUDE_PIPELINE_PID" ]] && kill -TERM "$_CLAUDE_PIPELINE_PID" 2>/dev/null
    touch "$RALPH_DIR/.stop"
    kill 0 2>/dev/null
    exit 130
  ' INT

  # Tint terminal background so Ralph's terminal is visually distinct
  local tint_color
  tint_color=$(get_config '.terminalTint' "#1a2e2e")
  if [[ "$tint_color" != "off" ]]; then
    set_terminal_bg "$tint_color"
  fi

  local max_iterations=""  # No cap by default — per-story circuit breaker is the safety net
  local specific_story=""
  local fast_mode=false
  local quiet_mode
  quiet_mode=$(get_config '.quiet' "false")

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max)
        max_iterations="$2"
        shift 2
        ;;
      --story)
        specific_story="$2"
        shift 2
        ;;
      --fast)
        fast_mode=true
        shift
        ;;
      --quiet)
        quiet_mode=true
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # Export for use in verification
  export RALPH_FAST_MODE="$fast_mode"

  # Validate prerequisites
  check_dependencies

  # Check for newer version on npm (once per day, non-blocking if offline)
  check_for_updates "${_original_args[@]}"

  # Warn if no Docker compose file (safety net for autonomous execution)
  _docker_safety_warning

  # Pre-loop checks to catch issues before wasting iterations
  if [[ "$fast_mode" == "true" ]]; then
    print_info "Fast mode: skipping connectivity checks"
  elif _is_preflight_cached; then
    print_info "Pre-loop checks passed recently, skipping"
  else
    if preflight_checks; then
      _write_preflight_cache
    fi
  fi

  if [[ ! -f "$RALPH_DIR/prd.json" ]]; then
    # Check for misplaced PRD in subdirectories
    local found_prd
    found_prd=$(find . -path "./.ralph" -prune -o -name "prd.json" -path "*/.ralph/prd.json" -print 2>/dev/null | head -1)

    if [[ -n "$found_prd" ]]; then
      print_warning "PRD found in wrong location: $found_prd"
      echo ""
      echo "PRD should be at root: .ralph/prd.json"
      echo ""
      read -r -p "Move it to root? [Y/n] " response
      if [[ "$response" =~ ^[Nn] ]]; then
        echo "Aborted. Move it manually:"
        echo "  mv $found_prd .ralph/prd.json"
        exit 1
      fi
      mkdir -p "$RALPH_DIR"
      mv "$found_prd" "$RALPH_DIR/prd.json"
      print_success "Moved PRD to .ralph/prd.json"
      echo ""
    else
      print_error "No PRD found."
      echo ""
      echo "  You need to create a plan before Ralph can run."
      echo ""
      echo "  1. Open Claude in your terminal:"
      echo ""
      echo "       claude --dangerously-skip-permissions"
      echo ""
      echo "  2. Inside Claude, type:"
      echo ""
      echo "       /prd \"your feature description\""
      echo ""
      echo "  Note: /prd is a Claude skill — it only works inside an active"
      echo "  Claude session, not from your regular terminal."
      echo ""
      echo "  See Step 4 of the Getting Started guide:"
      echo "    docs/GETTING-STARTED.md"
      echo ""
      exit 1
    fi
  fi

  if [[ ! -f "$PROMPT_FILE" ]]; then
    print_error "PROMPT.md not found."
    echo ""
    echo "Create it with: ralph init"
    echo ""
    exit 1
  fi

  # Validate PRD structure
  if [[ "$fast_mode" == "true" ]]; then
    print_info "Fast mode: structural PRD check only"
    validate_prd "$RALPH_DIR/prd.json" "true" || return 1
  elif _is_prd_cached; then
    print_info "PRD validated recently, structural check only"
    validate_prd "$RALPH_DIR/prd.json" "true" || return 1
  else
    if ! validate_prd "$RALPH_DIR/prd.json"; then
      return 1
    fi
    _write_prd_cache
  fi

  local iteration=0
  local last_story=""
  local consecutive_failures=0
  local consecutive_timeouts=0
  local max_story_retries
  local max_timeouts=5  # Skip after 5 consecutive timeouts (likely too large/complex)
  # Default to 5 retries - enough for transient issues, stops before wasting cycles
  # Override with config.json: "maxStoryRetries": 8
  max_story_retries=$(get_config '.maxStoryRetries' "5")
  # Read timeout once at loop start — not per iteration, so Claude can't extend it mid-run
  local timeout_seconds
  timeout_seconds=$(get_config '.maxSessionSeconds' "$DEFAULT_TIMEOUT_SECONDS")
  local total_attempts=0
  local skipped_stories=()
  local start_time
  local session_started=false  # Track if we've started a Claude session
  start_time=$(date +%s)

  while [[ -z "$max_iterations" || $iteration -lt $max_iterations ]]; do
    # Check for stop signal
    if [[ -f "$RALPH_DIR/.stop" ]]; then
      rm -f "$RALPH_DIR/.stop"
      print_warning "Stop signal received. Exiting gracefully."
      local passed failed
      passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      failed=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      send_notification "🛑 Ralph stopped: $passed passed, $failed remaining"
      return 0
    fi

    ((iteration++))
    echo ""
    if [[ -n "$max_iterations" ]]; then
      print_info "=== Iteration $iteration/$max_iterations ==="
    else
      print_info "=== Iteration $iteration ==="
    fi
    echo ""

    # 1. Get next incomplete story
    local story
    if [[ -n "$specific_story" ]]; then
      story="$specific_story"
      # Verify it exists
      local exists
      exists=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .id' "$RALPH_DIR/prd.json" 2>/dev/null)
      if [[ -z "$exists" ]]; then
        print_error "Story $story not found in PRD"
        return 1
      fi
    else
      story=$(jq -r '.stories[] | select(.passes==false) | .id' "$RALPH_DIR/prd.json" 2>/dev/null | head -1)
    fi

    if [[ -z "$story" ]]; then
      # Safety check: verify PRD is valid before claiming all stories passed
      # An empty/corrupt PRD would also result in no stories found
      local total_stories
      total_stories=$(jq '.stories | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      if [[ "$total_stories" == "0" || "$total_stories" == "null" ]]; then
        print_error "PRD appears to be empty or corrupted!"
        echo ""
        echo "  The prd.json file has no stories. This usually means:"
        echo "    - The file was accidentally cleared"
        echo "    - A write operation failed"
        echo ""
        echo "  Check for backups: ls -la $RALPH_DIR/*.bak"
        echo "  Or restore from git: git checkout $RALPH_DIR/prd.json"
        return 1
      fi
      print_progress_summary "$start_time" "$total_attempts" "${#skipped_stories[@]}"
      send_notification "✅ Ralph finished: All stories passed!"
      archive_feature
      return 0
    fi

    ((total_attempts++))

    # Track repeated failures on same story (also load from prd.json for restart persistence)
    if [[ "$story" == "$last_story" ]]; then
      ((consecutive_failures++))
    else
      # New story - clear failure history from previous story
      rm -f "$RALPH_DIR/last_failure.txt"
      # Load retry count from prd.json (persists across restarts)
      consecutive_failures=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .retryCount // 0' "$RALPH_DIR/prd.json")
      consecutive_failures=$((consecutive_failures + 1))
      consecutive_timeouts=0
      last_story="$story"
    fi

    # Persist retry count to prd.json (survives restarts)
    jq --arg id "$story" --argjson count "$consecutive_failures" \
      '(.stories[] | select(.id==$id)) |= . + {retryCount: $count}' \
      "$RALPH_DIR/prd.json" > "$RALPH_DIR/prd.json.tmp" && mv "$RALPH_DIR/prd.json.tmp" "$RALPH_DIR/prd.json"

    # Circuit breaker: stop the loop after max retries (stories depend on each other)
    # If a story consistently fails after this many tries, it needs manual review.
    if [[ $consecutive_failures -gt $max_story_retries ]]; then
      print_error "Story $story has failed $consecutive_failures times - stopping loop"
      echo ""
      mkdir -p "$RALPH_DIR/failures"
      cp "$RALPH_DIR/last_failure.txt" "$RALPH_DIR/failures/$story.txt" 2>/dev/null || true
      # Show the actual last error instead of generic guesses
      if [[ -f "$RALPH_DIR/last_failure.txt" ]]; then
        echo "  Last failure:"
        tail -20 "$RALPH_DIR/last_failure.txt" | sed 's/^/    /'
      fi
      echo ""
      echo "  Full failure context saved to: $RALPH_DIR/failures/$story.txt"
      local passed failed
      passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      failed=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      send_notification "🛑 Ralph stopped: $story failed $consecutive_failures times. $passed passed, $failed remaining"
      print_progress_summary "$start_time" "$total_attempts" "0"
      return 1
    fi

    # Show retry status (but don't make it scary - retrying is normal!)
    if [[ $consecutive_failures -gt 1 ]]; then
      if [[ $consecutive_failures -le 3 ]]; then
        print_info "Attempt $consecutive_failures for $story (normal - refining solution)"
      else
        print_warning "Attempt $consecutive_failures/$max_story_retries for $story (getting close to limit)"
      fi
    fi

    # 2. Session startup checklist (skip on retries)
    [[ $consecutive_failures -gt 1 ]] && startup_checklist "true" || startup_checklist "false"

    # 3. Build prompt with current story context (including failure context if any)
    print_info "Preparing prompt for $story..."
    local prompt_file
    prompt_file=$(create_temp_file ".md") || {
      print_error "Failed to create temp file for prompt"
      return 1
    }

    # Only load failure context if it's for the CURRENT story (prevents stale context leaks)
    local failure_context=""
    if [[ -f "$RALPH_DIR/last_failure.txt" ]]; then
      # Check if failure context is for this story (first line contains story ID)
      if grep -q "for $story" "$RALPH_DIR/last_failure.txt" 2>/dev/null; then
        failure_context=$(cat "$RALPH_DIR/last_failure.txt")
      else
        # Stale context from different story - clear it
        rm -f "$RALPH_DIR/last_failure.txt"
      fi
    fi

    # Temporarily disable errexit to capture build_prompt errors
    set +e
    build_prompt "$story" "$failure_context" "$session_started" > "$prompt_file" 2>&1
    local build_status=$?
    set -e

    if [[ $build_status -ne 0 ]]; then
      print_error "Failed to build prompt (see $prompt_file for errors)"
      cat "$prompt_file" | head -20
      rm -f "$prompt_file"
      return 1
    fi

    # Save git state before Claude runs (for migration detection)
    local pre_story_sha=""
    if command -v git &>/dev/null && [[ -d ".git" ]]; then
      pre_story_sha=$(git rev-parse HEAD 2>/dev/null || echo "")
    fi

    # 4. Spawn Claude (fresh context, with timeout)
    # Get story details for banner (single jq call for performance)
    local story_json story_title story_desc story_type story_emoji
    story_json=$(jq --arg id "$story" '.stories[] | select(.id==$id)' "$RALPH_DIR/prd.json")
    story_title=$(echo "$story_json" | jq -r '.title // "Untitled"')
    story_desc=$(echo "$story_json" | jq -r '.description // ""' | head -c 50)
    story_type=$(echo "$story_json" | jq -r '.type // "general"')
    story_emoji=$(type_emoji "$story_type")

    # Get progress
    local total_stories passed_stories current_num
    total_stories=$(jq '[.stories[]] | length' "$RALPH_DIR/prd.json")
    passed_stories=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json")
    current_num=$((passed_stories + 1))

    # Display dynamic banner (truncate long text to fit box)
    local max_width=53
    local display_title="$story_title"
    local display_desc="$story_desc"
    [[ ${#display_title} -gt $max_width ]] && display_title="${display_title:0:$((max_width-3))}..."
    [[ ${#display_desc} -gt $max_width ]] && display_desc="${display_desc:0:$((max_width-3))}..."

    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│  %s %-14s                     [%d/%d] %s  │\n" "$story_emoji" "$story" "$current_num" "$total_stories" "$(progress_bar $current_num $total_stories)"
    printf "│  %-55s│\n" "$display_title"
    printf "│  %-55s│\n" "$display_desc"
    printf "│  Type: %-49s│\n" "$story_type"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Snapshot PRD passes state before Claude runs (detect tampering after)
    local passes_before
    passes_before=$(jq '[.stories[] | {id, passes}]' "$RALPH_DIR/prd.json" 2>/dev/null)

    # Run Claude - first story gets fresh session, subsequent continue the session
    local -a claude_args=(-p --dangerously-skip-permissions --verbose --output-format stream-json)
    if [[ "$session_started" == "true" ]]; then
      claude_args=(--continue "${claude_args[@]}")
    fi

    # Run Claude with crash detection and retry logic
    local claude_output_log claude_exit_code max_crash_retries=5 crash_attempt=0
    claude_output_log=$(create_temp_file ".log") || { rm -f "$prompt_file"; return 1; }

    # Parse stream-json output from Claude CLI and display a live activity feed.
    # Shows tool usage (Read, Edit, Bash, etc.) as clean one-line summaries.
    # Non-JSON lines (crash messages) are passed through for crash detection.
    # Usage: _parse_stream_activity "true"|"false"
    _parse_stream_activity() {
      local quiet="${1:-false}"
      local dim=$'\033[2m' green=$'\033[0;32m' nc=$'\033[0m'
      local line
      while IFS= read -r line; do
        # Non-JSON lines (crash messages, errors) — always pass through
        if [[ "$line" != "{"* ]]; then
          echo "$line"
          continue
        fi

        # In quiet mode, skip all JSON parsing (activity suppressed)
        if [[ "$quiet" == "true" ]]; then
          continue
        fi

        # Fast pre-filter: only parse assistant (tool activity) and result (summary)
        # events. Skip system/user/etc. to avoid unnecessary jq calls.
        if [[ "$line" != *'"assistant"'* && "$line" != *'"result"'* ]]; then
          continue
        fi

        local msg_type
        msg_type=$(jq -r '.type // empty' <<< "$line" 2>/dev/null) || continue

        if [[ "$msg_type" == "assistant" ]]; then
          # Show Claude's explanation if present (the "what/why" before tool calls)
          local explanation
          explanation=$(jq -r '
            [.message.content[]? | select(.type == "text") | .text] | join(" ")
          ' <<< "$line" 2>/dev/null)
          if [[ -n "$explanation" ]]; then
            # Take first sentence and truncate at word boundary
            explanation="${explanation%%.*}"
            if [[ ${#explanation} -gt 72 ]]; then
              explanation="${explanation:0:72}"
              explanation="${explanation% *}..."
            fi
            printf "  ${dim}— %s${nc}\n" "$explanation"
          fi

          # Extract tool_use content blocks
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
                # Prefer human-readable description over raw command
                detail=$(jq -r '.description // empty' <<< "$tool_input" 2>/dev/null)
                if [[ -z "$detail" ]]; then
                  detail=$(jq -r '.command // empty' <<< "$tool_input" 2>/dev/null)
                  detail="${detail:0:60}"
                fi
                ;;
              Grep)
                label="Searching"
                detail=$(jq -r '.pattern // empty' <<< "$tool_input" 2>/dev/null)
                detail="for \"$detail\""
                ;;
              Glob)
                label="Finding"
                detail=$(jq -r '.pattern // empty' <<< "$tool_input" 2>/dev/null)
                detail="files matching $detail"
                ;;
              Task)
                label="Spawning"
                detail=$(jq -r '.description // empty' <<< "$tool_input" 2>/dev/null)
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
          elif [[ -n "$dur_str" ]]; then
            echo -e "  ${green}✓ Done${nc} ${dim}(${dur_str})${nc}"
          fi
        fi
      done
    }

    while [[ $crash_attempt -lt $max_crash_retries ]]; do
      claude_exit_code=0
      # Run Claude in a background subshell so the INT trap can fire immediately.
      # Without this, bash defers SIGINT handling until the foreground pipeline exits,
      # making Ctrl+C unresponsive while Claude is running.
      (
        set -o pipefail
        cat "$prompt_file" | run_with_timeout "$timeout_seconds" claude "${claude_args[@]}" 2>&1 | tee "$claude_output_log" | _parse_stream_activity "$quiet_mode"
      ) &
      _CLAUDE_PIPELINE_PID=$!
      wait "$_CLAUDE_PIPELINE_PID" || claude_exit_code=$?
      _CLAUDE_PIPELINE_PID=""

      # Check for recoverable CLI crashes (transient API failures)
      if grep -qE "(No messages returned|unhandled.*promise.*rejection)" "$claude_output_log" 2>/dev/null; then
        ((crash_attempt++))
        # Exponential backoff: 5s, 10s, 20s, 40s, 80s
        local backoff_seconds=$((5 * (2 ** (crash_attempt - 1))))
        echo ""  # Clean line after any partial output
        print_warning "API returned empty response - retrying in ${backoff_seconds}s (attempt $crash_attempt/$max_crash_retries)"
        print_info "This is usually a transient issue with the Claude API"
        log_progress "$story" "CLI_CRASH" "API empty response, retry $crash_attempt (backoff ${backoff_seconds}s)"
        session_started=false  # Reset session on crash
        sleep "$backoff_seconds"
        continue
      fi

      # Not a crash - exit retry loop
      break
    done

    if [[ $crash_attempt -ge $max_crash_retries ]]; then
      echo ""
      print_warning "Claude API unavailable after $max_crash_retries attempts"
      if [[ -f "$claude_output_log" ]]; then
        echo "  Last error:"
        tail -5 "$claude_output_log" | sed 's/^/    /'
      fi
      print_info "Waiting 60s before retrying... (Ctrl+C to stop, then 'npx agentic-loop run' to restart)"
      log_progress "$story" "CLI_CRASH" "API unavailable, waiting 60s before next iteration"
      rm -f "$prompt_file" "$claude_output_log"
      sleep 60  # Longer cooldown before retrying
      continue  # Continue main loop instead of stopping
    fi

    rm -f "$claude_output_log"

    # Check for skip signal (user ran `ralph skip` while Claude was running)
    if [[ -f "$RALPH_DIR/.skip" ]]; then
      rm -f "$RALPH_DIR/.skip"
      print_warning "Skip signal received — skipping $story"
      log_progress "$story" "SKIPPED" "User requested skip"
      skipped_stories+=("$story")
      jq --arg id "$story" '(.stories[] | select(.id==$id)) |= . + {skipped: true, skipReason: "user skipped"}' \
        "$RALPH_DIR/prd.json" > "$RALPH_DIR/prd.json.tmp" && mv "$RALPH_DIR/prd.json.tmp" "$RALPH_DIR/prd.json"
      last_story=""
      consecutive_failures=0
      consecutive_timeouts=0
      session_started=false
      rm -f "$prompt_file"
      continue
    fi

    # Check for blocked signal (Claude created .blocked to indicate it's stuck)
    if [[ -f "$RALPH_DIR/.blocked" ]]; then
      local block_reason
      block_reason=$(cat "$RALPH_DIR/.blocked" 2>/dev/null | head -1)
      rm -f "$RALPH_DIR/.blocked"
      print_error "Story $story blocked — ${block_reason:-no reason given}"
      log_progress "$story" "BLOCKED" "${block_reason:-Claude signaled blocked}"
      echo ""
      echo "  Claude signaled it cannot complete this story."
      echo "  Check .ralph/progress.txt for details on what was attempted."
      echo ""
      mkdir -p "$RALPH_DIR/failures"
      echo "${block_reason:-Claude signaled blocked}" > "$RALPH_DIR/failures/$story.txt"
      local passed failed
      passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      failed=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      send_notification "🛑 Ralph stopped: $story blocked. $passed passed, $failed remaining"
      print_progress_summary "$start_time" "$total_attempts" "0"
      rm -f "$prompt_file"
      return 1
    fi

    # Check for stop signal (user ran `ralph stop` or Ctrl+C while Claude was running)
    if [[ -f "$RALPH_DIR/.stop" ]]; then
      rm -f "$RALPH_DIR/.stop" "$prompt_file"
      print_warning "Stop signal received. Exiting gracefully."
      local passed failed
      passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      failed=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
      send_notification "🛑 Ralph stopped: $passed passed, $failed remaining"
      return 0
    fi

    if [[ $claude_exit_code -ne 0 ]]; then
      ((consecutive_timeouts++))
      print_warning "Claude session ended (timeout or error) - timeout $consecutive_timeouts/$max_timeouts"
      log_progress "$story" "TIMEOUT" "Claude session ended after ${timeout_seconds}s (timeout $consecutive_timeouts)"
      rm -f "$prompt_file"

      # Session may be broken - reset for next attempt
      session_started=false

      # Stop loop on repeated timeouts — story needs manual intervention
      if [[ $consecutive_timeouts -ge $max_timeouts ]]; then
        print_error "Story $story timed out $max_timeouts consecutive times — stopping loop"
        echo ""
        echo "  The story timed out ${max_timeouts}x (${timeout_seconds}s each). This usually means:"
        echo "    - The story is too large for a single Claude session"
        echo "    - Claude is stuck in a retry loop within the session"
        echo ""
        echo "  To fix:"
        echo "    - Break the story into smaller stories"
        echo "    - Increase maxSessionSeconds in .ralph/config.json"
        echo "    - Check .ralph/progress.txt for what Claude was attempting"
        echo ""
        mkdir -p "$RALPH_DIR/failures"
        echo "Story $story timed out $max_timeouts consecutive times (${timeout_seconds}s each)" > "$RALPH_DIR/failures/$story.txt"
        local passed failed
        passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
        failed=$(jq '[.stories[] | select(.passes==false)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
        send_notification "🛑 Ralph stopped: $story timed out ${max_timeouts}x. $passed passed, $failed remaining"
        print_progress_summary "$start_time" "$total_attempts" "0"
        return 1
      fi

      # If running specific story, exit on failure
      [[ -n "$specific_story" ]] && return 1
      continue
    fi

    # Reset timeout counter on successful Claude run
    consecutive_timeouts=0

    rm -f "$prompt_file"
    session_started=true  # Mark session as active for subsequent stories

    # Reset any story state changes Claude made — Ralph owns passes/retryCount/skipped
    local passes_after
    passes_after=$(jq '[.stories[] | {id, passes}]' "$RALPH_DIR/prd.json" 2>/dev/null)
    if [[ "$passes_before" != "$passes_after" ]]; then
      print_info "Resetting story state — verification will determine pass/fail"
      log_progress "$story" "RESET" "Story state modified during session, restored before verification"
      local restored
      restored=$(jq --argjson before "$passes_before" '
        .stories |= [.[] | . as $s | ($before[] | select(.id == $s.id)) as $orig |
          if $orig then $s + {passes: $orig.passes} else $s end]
      ' "$RALPH_DIR/prd.json") && echo "$restored" > "$RALPH_DIR/prd.json"
    fi

    # 5. Run migrations BEFORE verification (tests need DB schema)
    if ! run_migrations_if_needed "$pre_story_sha"; then
      log_progress "$story" "FAILED" "Migration failed"
      save_failure_context "$story"  # Include migration error in next prompt
      print_error "Migration failed for $story, will retry with error context..."
      continue
    fi

    # 6. Run verification pipeline
    echo ""
    # Capture verification output for failure context
    local verify_log="$RALPH_DIR/last_verification.log"
    local verify_exit=0
    run_verification "$story" 2>&1 | tee "$verify_log" || verify_exit=$?
    if [[ $verify_exit -eq 0 ]]; then
      # Mark story as complete and reset retry count
      update_json "$RALPH_DIR/prd.json" \
        --arg id "$story" '(.stories[] | select(.id==$id)) |= . + {passes: true, retryCount: 0}'

      # Auto-promote sign if story required retries
      if [[ $consecutive_failures -gt 1 && -f "$RALPH_DIR/last_failure.txt" ]]; then
        _maybe_promote_sign "$story" "$consecutive_failures"
      fi

      # Clear failure context on success
      rm -f "$RALPH_DIR/last_failure.txt"
      rm -f "$RALPH_DIR"/last_*_failure.log
      rm -f "$RALPH_DIR"/last_*_check.log
      rm -f "$RALPH_DIR/last_verification.log"

      # Get story title for commit message and completion display
      local title
      title=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .title' "$RALPH_DIR/prd.json")

      # Auto-commit if git is available
      if command -v git &>/dev/null && [[ -d ".git" ]]; then
        local commit_log commit_success
        commit_log=$(mktemp)
        commit_success=false

        # Try up to 3 times to handle auto-fix chains (some hooks always modify files)
        for attempt in 1 2 3; do
          git add -A
          if git commit -m "feat($story): $title" > "$commit_log" 2>&1; then
            commit_success=true
            break
          fi

          # Check if failure is due to file modifications (auto-fix)
          if grep -q "files were modified by this hook" "$commit_log" 2>/dev/null; then
            # Check for REAL errors (not just file modifications or warnings)
            if grep -qE "^error:|: error:|Error:|SyntaxError" "$commit_log" 2>/dev/null; then
              # Real errors - stop retrying
              break
            fi
            # ESLint with actual errors (not just warnings)
            if grep -qE "✖ [0-9]+ problems? \([1-9][0-9]* errors?" "$commit_log" 2>/dev/null; then
              break
            fi
            # Only file modifications - retry
            if [[ $attempt -lt 3 ]]; then
              continue
            fi
            # Max attempts with only file mods - try one more commit
            git add -A
            if git commit -m "feat($story): $title" --no-verify > "$commit_log" 2>&1; then
              commit_success=true
              print_warning "(committed with --no-verify due to auto-fix loop)"
            fi
            break
          else
            # Failed for other reason - check if it's a real error
            if ! grep -qE "^error:|: error:|Error:|SyntaxError|✖ [0-9]+ problems? \([1-9]" "$commit_log" 2>/dev/null; then
              # No real errors found - might just be warnings
              # Try committing with --no-verify
              git add -A
              if git commit -m "feat($story): $title" --no-verify > "$commit_log" 2>&1; then
                commit_success=true
                print_warning "(committed with --no-verify - only warnings detected)"
              fi
            fi
            break
          fi
        done

        if [[ "$commit_success" != "true" ]]; then
          print_warning "Pre-commit hooks failed, needs fixes..."
          cp "$commit_log" "$RALPH_DIR/last_precommit_failure.log"
          rm -f "$commit_log"
          save_failure_context "$story"
          log_progress "$story" "FAILED" "Pre-commit hooks failed"
          continue
        fi
        rm -f "$commit_log"
      fi

      log_progress "$story" "COMPLETED"

      # Show completion summary
      print_story_complete "$story" "$title"

      # If running specific story, we're done
      [[ -n "$specific_story" ]] && return 0
    else
      # Show which step failed so users can diagnose stuck loops
      local failed_at=""
      if [[ -f "$verify_log" ]]; then
        # Strip ANSI codes before searching (print_error adds color)
        failed_at=$(sed 's/\x1b\[[0-9;]*m//g' "$verify_log" | grep -o "Verification failed at: .*" | sed 's/ =*$//' | tail -1)
      fi
      if [[ -n "$failed_at" ]]; then
        log_progress "$story" "FAILED" "$failed_at"
        print_warning "$failed_at — will retry $story..."
      else
        log_progress "$story" "FAILED" "Verification failed, will retry"
        print_warning "Verification failed for $story, iterating..."
      fi

      # If running specific story, exit on failure
      [[ -n "$specific_story" ]] && return 1
    fi

    sleep "$ITERATION_DELAY_SECONDS"  # Brief pause between iterations
  done

  print_warning "Max iterations ($max_iterations) reached"
  print_progress_summary "$start_time" "$total_attempts" "${#skipped_stories[@]}"
  local passed failed
  passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  failed=$(jq '[.stories[] | select(.passes==false and .skipped!=true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  send_notification "⚠️ Ralph stopped: $passed passed, $failed remaining (max iterations reached)"
  return 1
}

# Display startup checklist (only full version on first iteration)
# Usage: startup_checklist [is_retry]
startup_checklist() {
  local is_retry="${1:-false}"

  # On retries, just show minimal info
  if [[ "$is_retry" == "true" ]]; then
    return 0
  fi

  echo "--- Startup Checklist ---"
  echo "Working directory: $(pwd)"
  echo ""

  # Show progress summary instead of full list
  local passed_count total_count
  passed_count=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  total_count=$(jq '[.stories[]] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  echo "Progress: $passed_count/$total_count stories complete"
  echo ""

  # Only show last few progress entries
  if [[ -f "$RALPH_DIR/progress.txt" ]]; then
    echo "Recent:"
    tail -3 "$RALPH_DIR/progress.txt" | sed 's/^/  /'
    echo ""
  fi

  # Show git status only if there are changes
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    local git_changes
    git_changes=$(git status --short 2>/dev/null | head -5)
    if [[ -n "$git_changes" ]]; then
      echo "Uncommitted:"
      echo "$git_changes" | sed 's/^/  /'
      echo ""
    fi
  fi
}

# Helper: Check if files listed in a story's files.create/files.modify already exist on disk
# Returns newline-separated list of existing files (empty string if none)
_check_story_files_exist() {
  local story_id="$1"
  local prd_file="$RALPH_DIR/prd.json"
  [[ ! -f "$prd_file" ]] && return

  local file_list
  file_list=$(jq -r --arg id "$story_id" '
    .stories[] | select(.id == $id) |
    ((.files.create // []) + (.files.modify // [])) | .[]
  ' "$prd_file" 2>/dev/null) || return

  [[ -z "$file_list" ]] && return

  local existing=""
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if [[ -f "$f" ]]; then
      if [[ -z "$existing" ]]; then
        existing="$f"
      else
        existing="$existing"$'\n'"$f"
      fi
    fi
  done <<< "$file_list"

  [[ -n "$existing" ]] && echo "$existing"
}

# Helper: Build delta prompt for continuing session
# Minimal context - just story ID + any failure info
_build_delta_prompt() {
  local story="$1"
  local failure_context="${2:-}"

  echo ""
  echo "---"
  echo ""

  # If this is a retry (failure context exists), note it
  if [[ -n "$failure_context" ]]; then
    echo "## Retry: Fix the errors below"
    echo ""

    # Check if story files already exist — if so, skip re-implementation
    local existing_files
    existing_files=$(_check_story_files_exist "$story")
    if [[ -n "$existing_files" ]]; then
      echo "**The code is ALREADY WRITTEN.** Do NOT rewrite. Fix ONLY the errors below, then verify."
      echo ""
    fi

    echo "Read \`.ralph/last_failure.txt\` for full error details."
    echo ""
    echo '```'
    echo "$failure_context" | head -50
    echo '```'
    echo ""
  else
    # New story - note previous completion
    local completed_count
    completed_count=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
    if [[ "$completed_count" -gt 0 ]]; then
      echo "## Previous story complete. Moving to next."
      echo ""
    fi
  fi

  echo "## Current Story: $story"
  echo ""
  echo "Read full story details from \`.ralph/prd.json\`"
}

# Helper: Inject signs (learned patterns) - ALWAYS inject these
_inject_signs() {
  [[ ! -f "$RALPH_DIR/signs.json" ]] && return

  local sign_count
  sign_count=$(jq '.signs | length' "$RALPH_DIR/signs.json" 2>/dev/null || echo "0")
  [[ "$sign_count" == "0" ]] && return

  echo ""
  echo "## Signs (Learned Patterns) - FOLLOW THESE"
  echo ""
  jq -r '.signs[] | "- [\(.category)] \(.pattern)"' "$RALPH_DIR/signs.json" 2>/dev/null
}

# Build the prompt - LEAN version
# Claude reads context from prd.json, we just provide the story ID and signs
# Usage: build_prompt <story_id> [failure_context] [is_continuation]
build_prompt() {
  local story="$1"
  local failure_context="${2:-}"
  local is_continuation="${3:-false}"

  if [[ "$is_continuation" == "true" ]]; then
    # Delta prompt for continuing session
    _build_delta_prompt "$story" "$failure_context"
    return
  fi

  # Full prompt for fresh session - LEAN
  cat "$PROMPT_FILE"

  echo ""
  echo "---"
  echo ""
  echo "## Current Story: $story"
  echo ""
  echo "Read full story details from \`.ralph/prd.json\` - it contains everything you need:"
  echo "- \`story.techStack\` - technologies relevant to this story"
  echo "- \`story.constraints\` - rules for this story"
  echo "- \`story.files\` - which files to create/modify"
  echo "- \`story.acceptanceCriteria\` - what must be true"
  echo "- \`story.testSteps\` - verification commands"
  echo "- \`story.contextFiles\` - idea files, styleguides to read"
  echo "- \`story.mcp\` - browser tools for verification"
  echo "- \`story.skills\` - relevant skills to reference"
  echo ""
  echo "Also read:"
  echo "- \`.ralph/config.json\` - URLs and directories"

  # Failure context if retrying
  if [[ -n "$failure_context" ]]; then
    echo ""
    echo "## Previous Iteration Failed"
    echo ""

    # Check if story files already exist — if so, skip re-implementation
    local existing_files
    existing_files=$(_check_story_files_exist "$story")
    if [[ -n "$existing_files" ]]; then
      echo "**IMPORTANT: The code for this story is ALREADY WRITTEN.** These files exist:"
      echo '```'
      echo "$existing_files"
      echo '```'
      echo "Do NOT rewrite or re-implement. Read the existing code, then fix ONLY the"
      echo "specific errors below. Go straight to verification after fixing."
      echo ""
    fi

    echo "Read \`.ralph/last_failure.txt\` for details. Key error:"
    echo ""
    echo '```'
    echo "$failure_context" | head -30
    echo '```'
  fi

  # Session boundaries — Ralph controls story state, not Claude
  echo ""
  echo "## Session Rules"
  echo ""
  echo "- **When done implementing, stop.** Ralph runs verification (lint, tests, build) after your session and marks the story."
  echo "- **Don't edit prd.json** — Ralph manages story state. Any changes to passes/retryCount/skipped are reset before verification."
  echo "- **If blocked**, write the reason and stop:"
  echo '  ```'
  echo '  echo "BLOCKED: [describe the issue]" > .ralph/.blocked'
  echo '  ```'
  echo "  Ralph will stop the loop so the issue can be resolved."

  # Signs are critical - always inject to prevent repeated mistakes
  _inject_signs
}

# Print story completion summary
print_story_complete() {
  local story="$1"
  local title="$2"

  # Get stats
  local passed_count total_count remaining
  passed_count=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  total_count=$(jq '[.stories[]] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  remaining=$((total_count - passed_count))

  # Get commit info
  local commit_hash=""
  local files_changed="0"
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    commit_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "")
    files_changed=$(git diff --name-only HEAD~1 2>/dev/null | wc -l | tr -d ' ')
  fi

  # Build progress bar
  local bar_filled=$((passed_count * 10 / total_count))
  local bar_empty=$((10 - bar_filled))
  local progress_bar=""
  for ((i=0; i<bar_filled; i++)); do progress_bar+="█"; done
  for ((i=0; i<bar_empty; i++)); do progress_bar+="░"; done

  # Truncate title if too long
  local display_title="$story: $title"
  [[ ${#display_title} -gt 50 ]] && display_title="${display_title:0:47}..."

  echo ""
  echo "  ┌──────────────────────────────────────────────────────┐"
  echo "  │  ✅ STORY COMPLETE                                   │"
  echo "  ├──────────────────────────────────────────────────────┤"
  printf "  │  %-52s│\n" "$display_title"
  echo "  ├──────────────────────────────────────────────────────┤"
  printf "  │  Progress: [%s] %d/%d stories               │\n" "$progress_bar" "$passed_count" "$total_count"
  [[ -n "$commit_hash" ]] && printf "  │  Commit:   %-42s│\n" "$commit_hash ($files_changed files)"
  if [[ $remaining -eq 0 ]]; then
    echo "  │  Status:   All stories complete!                    │"
  else
    printf "  │  Remaining: %-41s│\n" "$remaining stories"
  fi
  echo "  └──────────────────────────────────────────────────────┘"
  echo ""
}

# Print progress summary at end of run
print_progress_summary() {
  local start_time="$1"
  local total_attempts="$2"
  local skipped_count="$3"

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local hours=$((duration / 3600))
  local minutes=$(((duration % 3600) / 60))

  local passed failed total
  passed=$(jq '[.stories[] | select(.passes==true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  failed=$(jq '[.stories[] | select(.passes==false and .skipped!=true)] | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")
  total=$(jq '.stories | length' "$RALPH_DIR/prd.json" 2>/dev/null || echo "0")

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_success "COMPLETE"
  echo ""
  echo "  Stories:    $passed/$total passed"
  [[ "$skipped_count" -gt 0 ]] && echo "  Skipped:    $skipped_count (hit circuit breaker)"
  echo "  Attempts:   $total_attempts total iterations"
  if [[ $hours -gt 0 ]]; then
    echo "  Duration:   ${hours}h ${minutes}m"
  else
    echo "  Duration:   ${minutes}m"
  fi
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Mark feature as complete (keep PRD for appending new stories)
archive_feature() {
  local feature_name
  feature_name=$(jq -r '.feature.name' "$RALPH_DIR/prd.json")

  print_success "Feature '$feature_name' complete!"

  # Update status to complete (don't archive - user may want to append stories)
  update_json "$RALPH_DIR/prd.json" '.feature.status = "complete"'

  # Final commit if git available
  if command -v git &>/dev/null && [[ -d ".git" ]]; then
    git add -A
    if ! git commit -m "feat: complete $feature_name" 2>/dev/null; then
      # Retry after pre-commit auto-fixes
      git add -A
      if ! git commit -m "feat: complete $feature_name" 2>/dev/null; then
        # Check if it's "nothing to commit" vs real error
        if git diff --cached --quiet 2>/dev/null; then
          echo "    (no changes to commit)"
        else
          print_warning "Final commit failed - check git status"
        fi
      fi
    fi
  fi

  log_progress "FEATURE" "COMPLETE" "$feature_name"

  echo ""
  echo "All stories passed! PRD kept at: $RALPH_DIR/prd.json"
  echo ""
  echo "Next:"
  echo "  Start a Claude Code session and run /prd to brainstorm your next feature."
  echo "  ralph status            # See completed stories"
}
