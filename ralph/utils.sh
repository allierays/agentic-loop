#!/usr/bin/env bash
# shellcheck shell=bash
# utils.sh - Shared utility functions for ralph

# Get utils.sh directory to locate package.json
_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PACKAGE_JSON="$_UTILS_DIR/../package.json"

# Version constant (read from package.json)
RALPH_VERSION="$(jq -r '.version' "$_PACKAGE_JSON" 2>/dev/null || echo "unknown")"
readonly RALPH_VERSION

# Loop protocol version (for stream-json activity feed)
RALPH_LOOP_VERSION="2"
readonly RALPH_LOOP_VERSION

# Constants - Output limits
readonly MAX_LOG_LINES=30
readonly MAX_PROGRESS_LINES=10
readonly MAX_GIT_STATUS_LINES=10
readonly MAX_OUTPUT_PREVIEW_LINES=20
readonly MAX_ERROR_PREVIEW_LINES=40
readonly MAX_LINT_ERROR_LINES=20
readonly MAX_PROGRESS_FILE_LINES=1000
readonly MAX_SIGN_CONTEXT_LINES=150
readonly MAX_SIGN_DEDUP_EXISTING=20

# Constants - Timeouts (centralized to avoid magic numbers)
readonly ITERATION_DELAY_SECONDS=0
readonly DEFAULT_TIMEOUT_SECONDS=600
readonly CODE_REVIEW_TIMEOUT_SECONDS=120
readonly BROWSER_TIMEOUT_SECONDS=60
readonly BROWSER_PAGE_TIMEOUT_MS=30000
readonly CURL_TIMEOUT_SECONDS=10
readonly SIGN_EXTRACTION_TIMEOUT_SECONDS=30
readonly PREFLIGHT_CACHE_TTL_SECONDS=600

# Common project directories (avoid duplication across files)
readonly FRONTEND_DIRS=("apps/web" "frontend" "client" "web")
readonly BACKEND_DIRS=("apps/api" "api" "backend" "server")

# Track temp files for safe cleanup
RALPH_TEMP_FILES=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get existing frontend directories in this project
get_frontend_dirs() {
  local dirs=()
  for d in "${FRONTEND_DIRS[@]}"; do
    [[ -d "$d" ]] && dirs+=("$d")
  done
  [[ ${#dirs[@]} -gt 0 ]] && printf '%s\n' "${dirs[@]}"
}

# Get existing backend directories in this project
get_backend_dirs() {
  local dirs=()
  for d in "${BACKEND_DIRS[@]}"; do
    [[ -d "$d" ]] && dirs+=("$d")
  done
  [[ ${#dirs[@]} -gt 0 ]] && printf '%s\n' "${dirs[@]}"
}

# Progress bar for story display
progress_bar() {
  local current=$1 total=$2 width=${3:-6}
  local filled=$((current * width / total))
  local empty=$((width - filled))
  printf '%*s' "$filled" '' | tr ' ' '█'
  printf '%*s' "$empty" '' | tr ' ' '░'
}

# Emoji for story type
type_emoji() {
  case "$1" in
    frontend) echo "📦" ;;
    backend)  echo "⚙️" ;;
    testing)  echo "🧪" ;;
    *)        echo "📝" ;;
  esac
}

# Print colored output
print_error() { echo -e "${RED}Error: $1${NC}" >&2; }
print_success() { echo -e "${GREEN}$1${NC}"; }
print_warning() { echo -e "${YELLOW}$1${NC}"; }
print_info() { echo -e "${BLUE}$1${NC}"; }

# Check all required dependencies
check_dependencies() {
  local missing=()

  # Required
  command -v jq &>/dev/null || missing+=("jq (brew install jq)")
  command -v claude &>/dev/null || missing+=("claude CLI (npm install -g @anthropic-ai/claude-code)")

  # Optional but recommended
  if ! command -v git &>/dev/null; then
    print_warning "Warning: git not found, auto-commit disabled"
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    print_error "Missing required dependencies:"
    printf '  - %s\n' "${missing[@]}"
    exit 1
  fi
}

# Log progress to progress.txt (with rotation to prevent unbounded growth)
log_progress() {
  local story="$1"
  local status="$2"
  local msg="${3:-}"
  local timestamp
  local progress_file="$RALPH_DIR/progress.txt"

  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  echo "[$timestamp] $status $story $msg" >> "$progress_file"

  # Rotate if file exceeds max lines (keep last half)
  if [[ -f "$progress_file" ]]; then
    local line_count
    line_count=$(wc -l < "$progress_file" 2>/dev/null || echo "0")
    if [[ "$line_count" -gt "$MAX_PROGRESS_FILE_LINES" ]]; then
      local keep_lines=$((MAX_PROGRESS_FILE_LINES / 2))
      tail -"$keep_lines" "$progress_file" > "$progress_file.tmp" && mv "$progress_file.tmp" "$progress_file"
    fi
  fi
}

# Get a value from config.json with a default
get_config() {
  local key="$1"
  local default="$2"
  local config="$RALPH_DIR/config.json"

  if [[ -f "$config" ]]; then
    local value
    value=$(jq -r "$key // empty" "$config" 2>/dev/null)
    if [[ -n "$value" && "$value" != "null" ]]; then
      echo "$value"
      return
    fi
  fi
  echo "$default"
}

# Migrate deprecated config fields in-place
# Safe to call multiple times - only writes if changes are needed
_migrate_config() {
  local config="$RALPH_DIR/config.json"
  [[ ! -f "$config" ]] && return 0

  # testUrlBase -> urls.frontend
  local legacy_url
  legacy_url=$(jq -r '.testUrlBase // empty' "$config" 2>/dev/null)
  if [[ -n "$legacy_url" ]]; then
    local current_frontend
    current_frontend=$(jq -r '.urls.frontend // empty' "$config" 2>/dev/null)
    if [[ -z "$current_frontend" ]]; then
      jq --arg url "$legacy_url" '.urls.frontend = $url | del(.testUrlBase)' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    else
      jq 'del(.testUrlBase)' "$config" > "${config}.tmp" && mv "${config}.tmp" "$config"
    fi
  fi
}

# Deep merge user config with project config
# User config provides defaults, project config overrides
_merge_user_config() {
  local project_config="$RALPH_DIR/config.json"
  local user_config="$HOME/.config/ralph/config.json"

  # Skip if no user config
  [[ ! -f "$user_config" ]] && return 0

  # Skip if no project config
  [[ ! -f "$project_config" ]] && return 0

  # Deep merge: user config * project config (project wins)
  local merged
  merged=$(jq -s '.[0] * .[1]' "$user_config" "$project_config" 2>/dev/null)

  if [[ -n "$merged" && "$merged" != "null" ]]; then
    echo "$merged" > "$project_config"
  fi
}

# Manage user-level Ralph configuration
ralph_config() {
  local cmd="${1:-show}"
  local user_config_dir="$HOME/.config/ralph"
  local user_config="$user_config_dir/config.json"

  case "$cmd" in
    show)
      echo "=== User Config ==="
      echo "Location: $user_config"
      if [[ -f "$user_config" ]]; then
        jq '.' "$user_config"
      else
        echo "(not configured - run 'ralph config init')"
      fi
      echo ""
      echo "=== Global Hooks ==="
      if [[ -d "$user_config_dir/hooks" ]]; then
        ls -1 "$user_config_dir/hooks" 2>/dev/null || echo "(none)"
      else
        echo "(none)"
      fi
      ;;

    init)
      mkdir -p "$user_config_dir/hooks" "$user_config_dir/templates/config"
      if [[ ! -f "$user_config" ]]; then
        echo '{}' > "$user_config"
        echo "Created $user_config"
      else
        echo "User config already exists: $user_config"
      fi
      echo ""
      echo "Directories created:"
      echo "  $user_config_dir/hooks/      - Add global hooks here"
      echo "  $user_config_dir/templates/  - Override default templates"
      ;;

    get)
      # ralph config get commands.test
      local key="$2"
      if [[ -z "$key" ]]; then
        echo "Usage: ralph config get <key>"
        echo "Example: ralph config get commands.test"
        return 1
      fi
      local value
      value=$(jq -r ".$key // empty" "$user_config" 2>/dev/null)
      if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$value"
      else
        echo "(not set)"
      fi
      ;;

    set)
      # ralph config set commands.test "uv run pytest"
      local key="$2"
      local value="$3"
      if [[ -z "$key" || -z "$value" ]]; then
        echo "Usage: ralph config set <key> <value>"
        echo "Example: ralph config set commands.test 'uv run pytest'"
        return 1
      fi
      mkdir -p "$user_config_dir"
      [[ ! -f "$user_config" ]] && echo '{}' > "$user_config"

      # Build jq path from dot notation: commands.test -> .commands.test
      local jq_path=".$key"
      jq --arg v "$value" "$jq_path = \$v" "$user_config" > "${user_config}.tmp" \
        && mv "${user_config}.tmp" "$user_config"
      echo "Set $key = $value"
      ;;

    unset)
      # ralph config unset commands.test
      local key="$2"
      if [[ -z "$key" ]]; then
        echo "Usage: ralph config unset <key>"
        return 1
      fi
      [[ ! -f "$user_config" ]] && return 0
      local jq_path=".$key"
      jq "del($jq_path)" "$user_config" > "${user_config}.tmp" \
        && mv "${user_config}.tmp" "$user_config"
      echo "Removed $key"
      ;;

    path)
      echo "$user_config_dir"
      ;;

    *)
      echo "Usage: ralph config <command>"
      echo ""
      echo "Commands:"
      echo "  show           Show current user config"
      echo "  init           Initialize user config directory"
      echo "  get <key>      Get a config value"
      echo "  set <key> <v>  Set a config value"
      echo "  unset <key>    Remove a config value"
      echo "  path           Print config directory path"
      echo ""
      echo "Examples:"
      echo "  ralph config init"
      echo "  ralph config set commands.test 'uv run pytest'"
      echo "  ralph config get commands.test"
      ;;
  esac
}

# Cross-platform timeout (macOS needs gtimeout from coreutils)
run_with_timeout() {
  local seconds="$1"
  shift

  if command -v timeout &>/dev/null; then
    timeout "$seconds" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$seconds" "$@"
  else
    # Bash-native fallback: background the command, kill after timeout.
    # Capture stdin to a temp file so the backgrounded process can read it
    # (backgrounded commands lose access to the pipeline's stdin).
    local stdin_file
    stdin_file=$(mktemp)
    cat > "$stdin_file"
    "$@" < "$stdin_file" &
    local cmd_pid=$!
    rm -f "$stdin_file"
    ( sleep "$seconds" && kill -TERM "$cmd_pid" 2>/dev/null ) &
    local watchdog_pid=$!
    wait "$cmd_pid" 2>/dev/null
    local exit_code=$?
    kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null
    # If the process received SIGTERM, return 124 (same as GNU timeout).
    # Note: this cannot distinguish our watchdog from other SIGTERM sources.
    if [[ $exit_code -eq 143 ]]; then  # 143 = 128 + 15 (SIGTERM)
      return 124
    fi
    return "$exit_code"
  fi
}


# Safely update JSON file atomically
# Usage: update_json <file> [jq args...] <filter>
# Example: update_json file.json --arg id "TASK-001" '.stories[] | select(.id==$id)'
update_json() {
  local file="$1"
  shift
  local tmpfile lockdir
  tmpfile=$(mktemp)
  lockdir="${file}.lock"

  # Remove stale locks (from crashed processes)
  if [[ -d "$lockdir" ]]; then
    local lock_age=0
    local now=$(date +%s)
    # Cross-platform: macOS uses -f %m, Linux uses -c %Y
    local lock_mtime=$(stat -f %m "$lockdir" 2>/dev/null || stat -c %Y "$lockdir" 2>/dev/null || echo "$now")
    lock_age=$((now - lock_mtime))
    if [[ $lock_age -gt 30 ]]; then
      print_warning "Removing stale lock (${lock_age}s old): $lockdir"
      rm -rf "$lockdir"
    fi
  fi

  # Acquire lock (mkdir is atomic)
  local attempts=0
  while ! mkdir "$lockdir" 2>/dev/null; do
    ((attempts++))
    if [[ $attempts -gt 50 ]]; then
      print_error "Could not acquire lock on $file (locked for 5s+)"
      rm -f "$tmpfile"
      return 1
    fi
    sleep 0.1
  done

  # All remaining args go to jq (supports --arg, --argjson, etc.)
  local result=0
  if jq "$@" "$file" > "$tmpfile" 2>/dev/null; then
    mv "$tmpfile" "$file"
  else
    rm -f "$tmpfile"
    result=1
  fi

  # Release lock
  rmdir "$lockdir" 2>/dev/null
  return $result
}

# Create a temp file and track it for cleanup
create_temp_file() {
  local suffix="${1:-.tmp}"
  local tmpfile
  # macOS mktemp doesn't support suffixes, so create then rename
  tmpfile=$(mktemp 2>&1) || {
    print_error "mktemp failed: $tmpfile"
    return 1
  }
  if [[ "$suffix" != ".tmp" && -n "$suffix" ]]; then
    if ! mv "$tmpfile" "${tmpfile}${suffix}" 2>/dev/null; then
      print_error "Failed to rename temp file"
      rm -f "$tmpfile"
      return 1
    fi
    tmpfile="${tmpfile}${suffix}"
  fi
  RALPH_TEMP_FILES+=("$tmpfile")
  echo "$tmpfile"
}

# Clean up only tracked temp files on exit
cleanup() {
  if [[ ${#RALPH_TEMP_FILES[@]} -gt 0 ]]; then
    for f in "${RALPH_TEMP_FILES[@]}"; do
      rm -f "$f" 2>/dev/null
    done
  fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Validate a command doesn't contain dangerous patterns
# Returns 0 if safe, 1 if dangerous
# Note: This is defense-in-depth. Commands come from user config, so user must trust their own config.
validate_command() {
  local cmd="$1"

  # Block obviously dangerous patterns (defense-in-depth, not security boundary)
  local dangerous_patterns=(
    'rm[[:space:]]+-rf[[:space:]]+/'              # rm -rf /
    'rm[[:space:]]+-rf[[:space:]]+~'              # rm -rf ~ (home dir)
    'rm[[:space:]].*--no-preserve-root'           # rm with --no-preserve-root
    'curl.*\|.*bash'                               # curl | bash
    'curl.*\|.*sh[[:space:]]*$'                    # curl | sh
    'wget.*\|.*bash'                               # wget | bash
    'wget.*\|.*sh[[:space:]]*$'                    # wget | sh
    'eval[[:space:]]+\$'                           # eval $var
    '>[[:space:]]*/dev/sd'                         # write to disk devices
    '>[[:space:]]*/dev/nvme'                       # write to nvme devices
    'mkfs\.'                                       # format filesystems
  )

  for pattern in "${dangerous_patterns[@]}"; do
    if [[ "$cmd" =~ $pattern ]]; then
      print_error "Command blocked (dangerous pattern): $cmd"
      log_progress "BLOCKED dangerous command: $cmd"
      return 1
    fi
  done

  return 0
}

# Safely execute a command (validates first, uses bash -c instead of eval)
safe_exec() {
  local cmd="$1"
  local log_file="${2:-/dev/null}"

  # Validate command first
  if ! validate_command "$cmd"; then
    return 1
  fi

  # Execute with bash -c instead of eval
  bash -c "$cmd" > "$log_file" 2>&1
}

# Set up or show notification config
ralph_notify() {
  local config_dir="$HOME/.config/ralph"
  local config_file="$config_dir/notify"

  if [[ $# -eq 0 ]]; then
    # Show current config
    if [[ -f "$config_file" ]]; then
      echo "Notification config (~/.config/ralph/notify):"
      cat "$config_file"
    else
      echo "No notification configured."
      echo ""
      echo "To set up iMessage notifications (macOS):"
      echo "  npx ralph notify +15551234567"
      echo ""
      echo "Ralph will text you when the loop finishes."
    fi
    return 0
  fi

  local phone="$1"

  # Validate phone format (basic check)
  if [[ ! "$phone" =~ ^\+?[0-9]{10,15}$ ]]; then
    print_error "Invalid phone number format. Use: +15551234567"
    return 1
  fi

  # Create config directory and file
  mkdir -p "$config_dir"
  echo "phone=$phone" > "$config_file"

  print_success "Notification configured!"
  echo "Phone: $phone"
  echo ""
  echo "Ralph will send iMessage when the loop finishes."
  echo "(Requires macOS with Messages signed into your Apple ID)"

  # Test notification
  echo ""
  read -p "Send a test message? [y/N] " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    send_notification "🧪 Test from Ralph - notifications are working!"
  fi
}

# Send notification via iMessage (macOS only)
# Reads phone from ~/.config/ralph/notify (global, one-time setup)
send_notification() {
  local message="$1"
  local config_file="$HOME/.config/ralph/notify"

  # No config file, skip silently
  if [[ ! -f "$config_file" ]]; then
    return 0
  fi

  local phone=""
  phone=$(grep -E '^phone=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)

  # No phone configured, skip silently
  if [[ -z "$phone" ]]; then
    return 0
  fi

  # macOS only - use iMessage
  if [[ "$(uname)" == "Darwin" ]]; then
    # Escape message for AppleScript (replace backslashes and quotes)
    local escaped_message="${message//\\/\\\\}"
    escaped_message="${escaped_message//\"/\\\"}"
    osascript -e "tell application \"Messages\" to send \"$escaped_message\" to buddy \"$phone\"" 2>/dev/null || {
      print_warning "Failed to send iMessage notification (is Messages app signed in?)"
      return 1
    }
    print_info "Notification sent to $phone"
  else
    print_warning "Notifications only supported on macOS"
  fi

  return 0
}

# Escape special regex characters in a string for use in sed
# Usage: escaped=$(escape_sed_pattern "http://localhost:8000")
_escape_sed_pattern() {
  printf '%s' "$1" | sed 's/[.[\/*^$()+?{|]/\\&/g'
}

# Replace hardcoded paths/URLs with config placeholders
# Makes PRDs portable across machines and environments
fix_hardcoded_paths() {
  local prd_file="$1"
  local config_file="$2"
  local modified=false

  # Read current PRD
  local prd_content
  prd_content=$(cat "$prd_file")

  # Safety check - don't proceed if file is empty
  if [[ -z "$prd_content" ]]; then
    return 0
  fi

  # Get URLs from config (if available)
  local backend_url="" frontend_url=""
  if [[ -f "$config_file" ]]; then
    backend_url=$(jq -r '.urls.backend // .api.baseUrl // empty' "$config_file" 2>/dev/null)
    frontend_url=$(jq -r '.urls.frontend // .playwright.baseUrl // empty' "$config_file" 2>/dev/null)
  fi

  # Store original for safety check
  local original_content="$prd_content"

  # Check for hardcoded absolute paths (non-portable)
  # Note: stderr suppressed on echo|grep -q pipes to silence "broken pipe" noise
  # (grep -q exits early on match, closing the pipe while echo is still writing)
  if echo "$prd_content" 2>/dev/null | grep -qE '"/Users/|"/home/|"C:\\|"/var/|"/opt/' ; then
    echo "  Removing hardcoded absolute paths..."
    # Remove common absolute path prefixes, keep relative path
    prd_content=$(echo "$prd_content" | sed -E 's|"/Users/[^"]*/([^"]+)"|"\1"|g')
    prd_content=$(echo "$prd_content" | sed -E 's|"/home/[^"]*/([^"]+)"|"\1"|g')
    modified=true
  fi

  # Replace hardcoded backend URLs with {config.urls.backend}
  if [[ -n "$backend_url" ]] && echo "$prd_content" 2>/dev/null | grep -qF "$backend_url" ; then
    echo "  Replacing hardcoded backend URL with {config.urls.backend}..."
    local escaped_url
    escaped_url=$(_escape_sed_pattern "$backend_url")
    prd_content=$(echo "$prd_content" | sed "s|$escaped_url|{config.urls.backend}|g")
    modified=true
  fi

  # Replace hardcoded frontend URLs with {config.urls.frontend}
  if [[ -n "$frontend_url" ]] && echo "$prd_content" 2>/dev/null | grep -qF "$frontend_url" ; then
    echo "  Replacing hardcoded frontend URL with {config.urls.frontend}..."
    local escaped_url
    escaped_url=$(_escape_sed_pattern "$frontend_url")
    prd_content=$(echo "$prd_content" | sed "s|$escaped_url|{config.urls.frontend}|g")
    modified=true
  fi

  # Replace hardcoded health endpoints with config placeholder
  if echo "$prd_content" 2>/dev/null | grep -qE '/api(/v[0-9]+)?/health|/health' ; then
    echo "  Replacing hardcoded health endpoints with {config.api.healthEndpoint}..."
    prd_content=$(echo "$prd_content" | sed -E 's|/api/v[0-9]+/health|{config.api.healthEndpoint}|g')
    prd_content=$(echo "$prd_content" | sed -E 's|/api/health|{config.api.healthEndpoint}|g')
    prd_content=$(echo "$prd_content" | sed -E 's|"/health"|"{config.api.healthEndpoint}"|g')
    modified=true
  fi

  # Replace common localhost patterns if no config URLs set
  # Note: Use # as delimiter since | appears in regex alternation
  if [[ -z "$backend_url" ]]; then
    # Common backend ports: 8000, 8001, 8080, 3001, 4000, 5000
    if echo "$prd_content" 2>/dev/null | grep -qE 'http://localhost:(8000|8001|8080|3001|4000|5000)' ; then
      echo "  Replacing hardcoded localhost backend URLs with {config.urls.backend}..."
      prd_content=$(echo "$prd_content" | sed -E 's#http://localhost:(8000|8001|8080|3001|4000|5000)#{config.urls.backend}#g')
      modified=true
    fi
  fi

  if [[ -z "$frontend_url" ]]; then
    # Common frontend ports: 3000, 5173, 4200
    if echo "$prd_content" 2>/dev/null | grep -qE 'http://localhost:(3000|5173|4200)' ; then
      echo "  Replacing hardcoded localhost frontend URLs with {config.urls.frontend}..."
      prd_content=$(echo "$prd_content" | sed -E 's#http://localhost:(3000|5173|4200)#{config.urls.frontend}#g')
      modified=true
    fi
  fi

  # Write back if modified, but only if content is still valid
  if [[ "$modified" == "true" ]]; then
    # Safety check: don't write empty or drastically smaller content
    if [[ -z "$prd_content" ]]; then
      print_error "Path replacement resulted in empty content - aborting write"
      return 1
    fi

    # Validate the result is still valid JSON with stories
    if ! echo "$prd_content" | jq -e '.stories' >/dev/null 2>&1; then
      print_error "Path replacement produced invalid JSON - aborting write"
      return 1
    fi

    local orig_len=${#original_content}
    local new_len=${#prd_content}
    if [[ $new_len -lt $((orig_len / 2)) ]]; then
      print_error "Path replacement lost too much content ($orig_len -> $new_len bytes) - aborting write"
      return 1
    fi

    # Create backup before writing
    cp "$prd_file" "${prd_file}.pre-fix.bak"

    echo "$prd_content" > "$prd_file"
    print_success "Paths updated to use config placeholders"

    # Remove backup on success
    rm -f "${prd_file}.pre-fix.bak"
  fi
}

# Detect the type of project based on files present
# Returns one of: fullstack, rust, go, elixir, hugo, fastmcp, django, fastapi, python, node, minimal
detect_project_type() {
  # Check for fullstack patterns first (more specific)
  if [[ -d "frontend" && -d "core" ]]; then
    echo "fullstack"; return
  elif [[ -d "frontend" && -d "backend" ]]; then
    echo "fullstack"; return
  elif [[ -d "apps" ]]; then
    echo "fullstack"; return
  fi

  # Single-language projects
  if [[ -f "Cargo.toml" ]]; then echo "rust"; return; fi
  if [[ -f "go.mod" ]]; then echo "go"; return; fi
  if [[ -f "mix.exs" ]]; then echo "elixir"; return; fi

  # Hugo (Go static site generator)
  for _hc in "hugo.toml" "hugo.yaml" "hugo.json" "config.toml"; do
    if [[ -f "$_hc" ]] && [[ -d "content" || -d "layouts" || -d "themes" ]]; then
      echo "hugo"; return
    fi
  done

  # Python framework variants (most specific first)
  if [[ -f "pyproject.toml" ]]; then
    if grep -qiE "(fastmcp|\"fastmcp\"|'fastmcp')" pyproject.toml 2>/dev/null; then
      echo "fastmcp"; return
    elif grep -qiE "(django|\"django\"|'django')" pyproject.toml 2>/dev/null || [[ -f "manage.py" ]]; then
      echo "django"; return
    elif grep -qiE "(fastapi|\"fastapi\"|'fastapi')" pyproject.toml 2>/dev/null; then
      echo "fastapi"; return
    else
      echo "python"; return
    fi
  elif [[ -f "requirements.txt" || -f "setup.py" ]]; then
    if [[ -f "requirements.txt" ]]; then
      if grep -qi 'fastmcp' requirements.txt 2>/dev/null; then echo "fastmcp"; return; fi
      if grep -qi 'django' requirements.txt 2>/dev/null || [[ -f "manage.py" ]]; then echo "django"; return; fi
      if grep -qi 'fastapi' requirements.txt 2>/dev/null; then echo "fastapi"; return; fi
    fi
    echo "python"; return
  elif [[ -f "manage.py" ]]; then
    echo "django"; return
  fi

  if [[ -f "package.json" ]]; then echo "node"; return; fi

  echo "minimal"
}

# Detect framework type for CLAUDE.md generation
# Returns one of: fastmcp, fastapi, django, react, or empty string
detect_framework_type() {
  if [[ -f "pyproject.toml" ]]; then
    if grep -qiE "(fastmcp|\"fastmcp\"|'fastmcp')" pyproject.toml 2>/dev/null; then
      echo "fastmcp"; return
    elif grep -qiE "(fastapi|\"fastapi\"|'fastapi')" pyproject.toml 2>/dev/null; then
      echo "fastapi"; return
    elif grep -qiE "(django|\"django\"|'django')" pyproject.toml 2>/dev/null || [[ -f "manage.py" ]]; then
      echo "django"; return
    fi
  elif [[ -f "requirements.txt" ]]; then
    if grep -qi 'fastmcp' requirements.txt 2>/dev/null; then echo "fastmcp"; return; fi
    if grep -qi 'fastapi' requirements.txt 2>/dev/null; then echo "fastapi"; return; fi
    if grep -qi 'django' requirements.txt 2>/dev/null || [[ -f "manage.py" ]]; then echo "django"; return; fi
  elif [[ -f "manage.py" ]]; then
    echo "django"; return
  fi

  # Check for React in frontend package.json
  local pkg="package.json"
  local fe_dir=""
  [[ -d "frontend" ]] && fe_dir="frontend"
  [[ -d "client" ]] && fe_dir="client"
  [[ -d "web" ]] && fe_dir="web"
  [[ -d "apps/web" ]] && fe_dir="apps/web"
  [[ -n "$fe_dir" && -f "${fe_dir}/package.json" ]] && pkg="${fe_dir}/package.json"

  if [[ -f "$pkg" ]] && grep -q '"react"' "$pkg" 2>/dev/null; then
    echo "react"; return
  fi

  echo ""
}

# Detect Python runner (uv, poetry, pipenv, or plain python)
detect_python_runner() {
  local search_dir="${1:-.}"

  # Check for uv (uv.lock or pyproject.toml with uv)
  if [[ -f "$search_dir/uv.lock" ]]; then
    echo "uv run"
    return 0
  fi

  # Check for poetry
  if [[ -f "$search_dir/poetry.lock" ]]; then
    echo "poetry run"
    return 0
  fi

  # Check for pipenv
  if [[ -f "$search_dir/Pipfile.lock" ]]; then
    echo "pipenv run"
    return 0
  fi

  # Default to plain command (no runner detected)
  echo ""
  return 0
}

# Auto-detect migration tool and return the command
detect_migration_tool() {
  local search_dir="${1:-.}"
  local py_runner
  py_runner=$(detect_python_runner "$search_dir")

  # Alembic (Python/FastAPI/SQLAlchemy)
  if [[ -f "$search_dir/alembic.ini" ]] || [[ -d "$search_dir/alembic" ]]; then
    echo "cd $search_dir && ${py_runner}${py_runner:+ }alembic upgrade head"
    return 0
  fi

  # Ecto (Elixir/Phoenix)
  if [[ -f "$search_dir/mix.exs" ]] && [[ -d "$search_dir/priv/repo/migrations" ]]; then
    echo "cd $search_dir && mix ecto.migrate"
    return 0
  fi

  # Prisma (Node.js)
  if [[ -d "$search_dir/prisma/migrations" ]] || [[ -f "$search_dir/prisma/schema.prisma" ]]; then
    echo "cd $search_dir && npx prisma migrate deploy"
    return 0
  fi

  # Django (use python3 for macOS compatibility when no runner detected)
  if [[ -f "$search_dir/manage.py" ]] && [[ -d "$search_dir" ]] && find "$search_dir" -type d -name "migrations" -print -quit | grep -q .; then
    local python_cmd="python3"
    [[ -n "$py_runner" ]] && python_cmd="python"
    echo "cd $search_dir && ${py_runner}${py_runner:+ }${python_cmd} manage.py migrate"
    return 0
  fi

  # Sequelize (Node.js)
  if [[ -f "$search_dir/.sequelizerc" ]]; then
    echo "cd $search_dir && npx sequelize-cli db:migrate"
    return 0
  fi

  # TypeORM (Node.js)
  if [[ -f "$search_dir/ormconfig.json" ]] || grep -q '"typeorm"' "$search_dir/package.json" 2>/dev/null; then
    echo "cd $search_dir && npx typeorm migration:run"
    return 0
  fi

  # Knex (Node.js)
  if [[ -f "$search_dir/knexfile.js" ]] || [[ -f "$search_dir/knexfile.ts" ]]; then
    echo "cd $search_dir && npx knex migrate:latest"
    return 0
  fi

  return 1
}

# Find all migration tools in project (searches common app directories)
find_all_migration_tools() {
  local tools=()

  # Check root
  local root_tool
  if root_tool=$(detect_migration_tool "."); then
    tools+=("$root_tool")
  fi

  # Check common app directories
  for dir in apps/* packages/* services/* api backend server; do
    if [[ -d "$dir" ]]; then
      local tool
      if tool=$(detect_migration_tool "$dir"); then
        tools+=("$tool")
      fi
    fi
  done

  # Return unique tools
  printf '%s\n' "${tools[@]}" | sort -u
}

# Validate batch assignments in a PRD file
# Returns 0 if valid (or no batches), 1 with error messages if invalid
# Checks: all-or-none batch field, dependency ordering, file overlap within batch
validate_batch_assignments() {
  local prd_file="$1"
  local errors=""
  local error_count=0

  # Count stories with and without batch
  local total_stories with_batch without_batch
  total_stories=$(jq '.stories | length' "$prd_file" 2>/dev/null || echo "0")
  with_batch=$(jq '[.stories[] | select(.batch != null)] | length' "$prd_file" 2>/dev/null || echo "0")
  without_batch=$((total_stories - with_batch))

  # No batches at all — valid, nothing to check
  [[ "$with_batch" -eq 0 ]] && return 0

  # Some but not all stories have batch — error
  if [[ "$without_batch" -gt 0 ]]; then
    local missing_ids
    missing_ids=$(jq -r '[.stories[] | select(.batch == null) | .id] | join(", ")' "$prd_file" 2>/dev/null)
    errors+="batch field missing on: $missing_ids\n"
    error_count=$((error_count + 1))
  fi

  # Check dependency ordering: no dependsOn pointing to same or later batch
  local dep_violations
  dep_violations=$(jq -r '
    .stories as $all |
    [.stories[] | . as $s |
      ($s.dependsOn // [])[] as $dep |
      ($all[] | select(.id == $dep)) as $dep_story |
      select($dep_story.batch != null and $s.batch != null and $dep_story.batch >= $s.batch) |
      "\($s.id) (batch \($s.batch)) depends on \($dep) (batch \($dep_story.batch))"
    ] | .[]' "$prd_file" 2>/dev/null)

  if [[ -n "$dep_violations" ]]; then
    while IFS= read -r violation; do
      [[ -z "$violation" ]] && continue
      errors+="$violation\n"
      error_count=$((error_count + 1))
    done <<< "$dep_violations"
  fi

  # Check file overlap within same batch (create/modify only)
  local file_overlaps
  file_overlaps=$(jq -r '
    . as $root |
    [$root.stories[] | select(.batch != null) | .batch] | unique | .[] as $b |
    [$root.stories[] | select(.batch == $b)] |
    if length < 2 then empty
    else
      . as $stories |
      range(length) as $i | range($i+1; length) as $j |
      $stories[$i] as $a | $stories[$j] as $b_story |
      (($a.files.create // []) + ($a.files.modify // [])) as $files_a |
      (($b_story.files.create // []) + ($b_story.files.modify // [])) as $files_b |
      ($files_a | map(select(. as $f | $files_b | any(. == $f)))) as $shared |
      select(($shared | length) > 0) |
      "batch \($b): \($a.id) and \($b_story.id) share files: \($shared | join(", "))"
    end
  ' "$prd_file" 2>/dev/null)

  if [[ -n "$file_overlaps" ]]; then
    while IFS= read -r overlap; do
      [[ -z "$overlap" ]] && continue
      errors+="$overlap\n"
      error_count=$((error_count + 1))
    done <<< "$file_overlaps"
  fi

  if [[ $error_count -gt 0 ]]; then
    echo -e "$errors"
    return 1
  fi

  return 0
}

# Ensure database migrations are applied before verification
# Migration commands are idempotent - they no-op if nothing pending
run_migrations_if_needed() {
  local pre_sha="$1"  # unused now, kept for API compatibility
  local config="$RALPH_DIR/config.json"

  local migrate_cmd=""

  # Try config first
  if [[ -f "$config" ]]; then
    migrate_cmd=$(jq -r '.migrations.command // empty' "$config" 2>/dev/null)
  fi

  # Auto-detect if not configured
  if [[ -z "$migrate_cmd" ]]; then
    local detected_tools
    detected_tools=$(find_all_migration_tools)

    if [[ -z "$detected_tools" ]]; then
      return 0  # No migrations to run
    fi

    # Run all detected migration tools
    local failed=0
    while IFS= read -r tool_cmd; do
      [[ -z "$tool_cmd" ]] && continue
      echo -n "  Migrations (auto-detected)... "

      local log_file
      log_file=$(mktemp)

      if safe_exec "$tool_cmd" "$log_file"; then
        if grep -qiE "applying|migrating|running|upgrade" "$log_file" 2>/dev/null; then
          print_success "applied"
        else
          echo "up to date"
        fi
      else
        print_error "failed"
        echo "    Command: $tool_cmd"
        tail -10 "$log_file" | sed 's/^/      /'
        # Save failure context for Claude
        {
          echo "Migration command: $tool_cmd"
          echo ""
          cat "$log_file"
        } > "$RALPH_DIR/last_migration_failure.log"
        failed=1
      fi
      rm -f "$log_file"
    done <<< "$detected_tools"

    return $failed
  fi

  # Always run migrations - commands are idempotent (no-op if nothing pending)
  # This ensures DB schema is always in sync before tests run
  echo -n "  Ensuring migrations applied... "

  local log_file
  log_file=$(mktemp)

  if safe_exec "$migrate_cmd" "$log_file"; then
    # Check if any migrations were actually applied
    if grep -qiE "applying|migrating|running|upgrade" "$log_file" 2>/dev/null; then
      print_success "applied"
    else
      echo "up to date"
    fi
    rm -f "$log_file"
    return 0
  else
    print_error "failed"
    echo ""
    echo "    Migration error:"
    tail -20 "$log_file" | sed 's/^/      /'
    # Save failure context for Claude
    {
      echo "Migration command: $migrate_cmd"
      echo ""
      cat "$log_file"
    } > "$RALPH_DIR/last_migration_failure.log"
    rm -f "$log_file"
    return 1
  fi
}

# Detect the available Docker Compose command.
# Returns "docker compose" (v2) or "docker-compose" (v1), or empty string if neither.
_detect_compose_cmd() {
  if docker compose version &>/dev/null; then
    echo "docker compose"
  elif command -v docker-compose &>/dev/null; then
    echo "docker-compose"
  else
    echo ""
  fi
}
