#!/usr/bin/env bash
# shellcheck shell=bash
# utils.sh - Shared utility functions for ralph

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
readonly DEFAULT_MAX_ITERATIONS=20
readonly CODE_REVIEW_TIMEOUT_SECONDS=120
readonly BROWSER_TIMEOUT_SECONDS=60
readonly BROWSER_PAGE_TIMEOUT_MS=30000
readonly CURL_TIMEOUT_SECONDS=10
readonly SIGN_EXTRACTION_TIMEOUT_SECONDS=30

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

# Get a field from a story in prd.json
# Usage: get_story_field "STORY-001" ".type" "general"
get_story_field() {
  local story_id="$1"
  local field="$2"
  local default="${3:-}"
  local prd="$RALPH_DIR/prd.json"

  if [[ -f "$prd" ]]; then
    local value
    value=$(jq -r --arg id "$story_id" ".stories[] | select(.id==\$id) | $field // empty" "$prd" 2>/dev/null)
    if [[ -n "$value" && "$value" != "null" ]]; then
      echo "$value"
      return
    fi
  fi
  echo "$default"
}

# Clear a failure log file
# Usage: clear_failure_log "lint"  # clears last_lint_failure.log
clear_failure_log() {
  local log_name="$1"
  rm -f "$RALPH_DIR/last_${log_name}_failure.log"
}

# Append content to a failure log file
# Usage: log_failure "lint" "Error details here"
log_failure() {
  local log_name="$1"
  local content="$2"
  echo "$content" >> "$RALPH_DIR/last_${log_name}_failure.log"
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
    # Fallback: just run without timeout (safe - Claude sessions complete on their own)
    "$@"
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
    # Destructive file operations
    'rm[[:space:]]+-rf[[:space:]]+/'              # rm -rf /
    'rm[[:space:]]+-rf[[:space:]]+~'              # rm -rf ~ (home dir)
    'rm[[:space:]]+-rf[[:space:]]+\*'             # rm -rf *
    'rm[[:space:]]+-rf[[:space:]]+\.\.'           # rm -rf ..
    'rm[[:space:]].*--no-preserve-root'           # rm with --no-preserve-root
    # Remote code execution
    'curl.*\|.*bash'                               # curl | bash
    'curl.*\|.*sh[[:space:]]*$'                    # curl | sh
    'wget.*\|.*bash'                               # wget | bash
    'wget.*\|.*sh[[:space:]]*$'                    # wget | sh
    'curl.*>[[:space:]]*/tmp/.*&&.*bash'           # curl > /tmp/x && bash
    # Code injection
    '\$\([^)]*eval'                                # $(eval ...)
    'eval[[:space:]]+\$'                           # eval $var
    'eval[[:space:]]+["\x27]'                      # eval "..." or eval '...'
    # System damage
    '>[[:space:]]*/dev/sd'                         # write to disk devices
    '>[[:space:]]*/dev/nvme'                       # write to nvme devices
    'mkfs\.'                                       # format filesystems
    'dd[[:space:]]+if='                            # dd commands
    ':(){:|:&};:'                                  # fork bomb
    # Credential theft
    'cat.*\.ssh/id_'                               # read SSH keys
    'cat.*/etc/shadow'                             # read shadow file
    'cat.*\.aws/credentials'                       # read AWS creds
    'cat.*\.env'                                   # read env files (often has secrets)
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

# Validate a URL is safe (http/https only, no internal IPs in production)
validate_url() { # public-api
  local url="$1"

  # Must start with http:// or https://
  if [[ ! "$url" =~ ^https?:// ]]; then
    print_error "Invalid URL scheme (must be http or https): $url"
    return 1
  fi

  # Block file:// and other dangerous schemes
  if [[ "$url" =~ ^(file|ftp|data|javascript): ]]; then
    print_error "Dangerous URL scheme: $url"
    return 1
  fi

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

  # Default to plain command (assumes activated venv or global)
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

  # Django
  if [[ -f "$search_dir/manage.py" ]] && [[ -d "$search_dir" ]] && find "$search_dir" -type d -name "migrations" -print -quit | grep -q .; then
    echo "cd $search_dir && ${py_runner}${py_runner:+ }python manage.py migrate"
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
