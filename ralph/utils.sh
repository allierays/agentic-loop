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

# Constants - Timeouts (centralized to avoid magic numbers)
readonly ITERATION_DELAY_SECONDS=0
readonly DEFAULT_TIMEOUT_SECONDS=600
readonly DEFAULT_MAX_ITERATIONS=20
readonly CODE_REVIEW_TIMEOUT_SECONDS=120
readonly BROWSER_TIMEOUT_SECONDS=60
readonly BROWSER_PAGE_TIMEOUT_MS=30000
readonly CURL_TIMEOUT_SECONDS=10

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

# Require a file to exist
require_file() {
  local file="$1"
  local msg="${2:-File not found: $file}"
  if [[ ! -f "$file" ]]; then
    print_error "$msg"
    exit 1
  fi
}

# Require a directory to exist
require_dir() {
  local dir="$1"
  local msg="${2:-Directory not found: $dir}"
  if [[ ! -d "$dir" ]]; then
    print_error "$msg"
    exit 1
  fi
}

# Require a command to be available
require_command() {
  local cmd="$1"
  local msg="${2:-Command not found: $cmd}"
  if ! command -v "$cmd" &>/dev/null; then
    print_error "$msg"
    exit 1
  fi
}

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
validate_url() {
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

# Validate PRD structure
# Returns 0 if valid, 1 if invalid with helpful error messages
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

  # Check feature name exists
  local feature_name
  feature_name=$(jq -r '.feature.name // empty' "$prd_file" 2>/dev/null)
  if [[ -z "$feature_name" ]]; then
    print_warning "PRD is missing feature name (will show as 'unnamed')"
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

  # Validate and fix individual stories
  validate_and_fix_stories "$prd_file" || return 1

  return 0
}

# Validate individual stories and auto-fix with Claude if needed
# Checks: testSteps quality, apiContract, testUrl, contextFiles, security, scale
validate_and_fix_stories() {
  local prd_file="$1"
  local needs_fix=false
  local issues=""

  echo "  Validating story quality..."

  # Get all story IDs
  local story_ids
  story_ids=$(jq -r '.stories[].id' "$prd_file" 2>/dev/null)

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
    elif [[ "$story_type" == "backend" ]]; then
      # Backend must have curl, not just npm test/pytest
      if ! echo "$test_steps" | grep -q "curl "; then
        story_issues+="backend needs curl tests (npm test alone uses mocks), "
      fi
    elif [[ "$story_type" == "frontend" ]]; then
      # Frontend must have tsc or playwright
      if ! echo "$test_steps" | grep -qE "(tsc --noEmit|playwright)"; then
        story_issues+="frontend needs tsc --noEmit or playwright tests, "
      fi
    fi

    # Check 2: Backend needs apiContract
    if [[ "$story_type" == "backend" ]]; then
      local has_contract
      has_contract=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .apiContract // empty' "$prd_file")
      if [[ -z "$has_contract" || "$has_contract" == "null" ]]; then
        story_issues+="backend missing apiContract, "
      fi
    fi

    # Check 3: Frontend needs testUrl and contextFiles
    if [[ "$story_type" == "frontend" ]]; then
      local has_url
      has_url=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .testUrl // empty' "$prd_file")
      if [[ -z "$has_url" || "$has_url" == "null" ]]; then
        story_issues+="frontend missing testUrl, "
      fi

      local context_files
      context_files=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .contextFiles // [] | length' "$prd_file")
      if [[ "$context_files" == "0" ]]; then
        story_issues+="frontend missing contextFiles (idea file + styleguide), "
      fi
    fi

    # Check 4: Auth stories need security criteria
    if echo "$story_title" | grep -qiE "(login|auth|password|register|signup|sign.?up)"; then
      local criteria
      criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
      if ! echo "$criteria" | grep -qiE "(hash|bcrypt|sanitiz|inject|rate.?limit)"; then
        story_issues+="auth story missing security criteria (password hashing/rate limiting), "
      fi
    fi

    # Check 5: List endpoints need scale criteria
    # Note: "search" excluded - search endpoints often return single/filtered results
    if echo "$story_title" | grep -qiE "(list|get all|fetch all|index)"; then
      local criteria
      criteria=$(jq -r --arg id "$story_id" '.stories[] | select(.id==$id) | .acceptanceCriteria // [] | join(" ")' "$prd_file")
      if ! echo "$criteria" | grep -qiE "(pagina|limit|page=|per.?page)"; then
        story_issues+="list endpoint missing pagination criteria, "
      fi
    fi

    # Report issues for this story
    if [[ -n "$story_issues" ]]; then
      needs_fix=true
      issues+="$story_id: ${story_issues%%, }
"
    fi
  done <<< "$story_ids"

  # If issues found, attempt to fix with Claude
  if [[ "$needs_fix" == "true" ]]; then
    print_warning "Story quality issues found:"
    echo "$issues" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo "    $line"
    done
    echo ""

    # Check if Claude is available for auto-fix
    if command -v claude &>/dev/null; then
      echo "  Attempting auto-fix with Claude..."
      fix_stories_with_claude "$prd_file" "$issues"
    else
      echo "  Claude CLI not found - fix these issues manually or regenerate PRD."
      echo ""
      return 1
    fi
  else
    print_success "All stories validated"
  fi

  return 0
}

# Fix story issues using Claude
fix_stories_with_claude() {
  local prd_file="$1"
  local issues="$2"

  local fix_prompt="Fix the following issues in this PRD. Output the COMPLETE fixed prd.json.

ISSUES FOUND:
$issues

RULES FOR FIXING:
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

CURRENT PRD:
$(cat "$prd_file")

Output ONLY the fixed JSON, no explanation. Start with { and end with }."

  local raw_response
  raw_response=$(echo "$fix_prompt" | run_with_timeout "$CODE_REVIEW_TIMEOUT_SECONDS" claude -p 2>/dev/null)

  # Extract JSON from response (Claude sometimes adds text before/after)
  local fixed_prd
  fixed_prd=$(echo "$raw_response" | sed -n '/^[[:space:]]*{/,/^[[:space:]]*}[[:space:]]*$/p' | head -1000)

  # If sed extraction failed, try the raw response
  if [[ -z "$fixed_prd" ]]; then
    fixed_prd="$raw_response"
  fi

  # Validate the response is valid JSON with required structure
  if echo "$fixed_prd" | jq -e '.stories' >/dev/null 2>&1; then
    # Timestamped backup (preserves history across multiple fixes)
    local backup_file="${prd_file}.$(date +%Y%m%d-%H%M%S).bak"
    cp "$prd_file" "$backup_file"

    # Write fixed PRD
    echo "$fixed_prd" > "$prd_file"
    print_success "PRD auto-fixed (backup at $backup_file)"

    # Re-validate to confirm fixes
    echo "  Re-validating..."
    local remaining_issues
    remaining_issues=$(validate_stories_quick "$prd_file")
    if [[ -n "$remaining_issues" ]]; then
      print_warning "Some issues remain - may need manual fixes:"
      echo "$remaining_issues" | tr ',' '\n' | while IFS= read -r line; do
        [[ -n "$line" ]] && echo "    $line"
      done
    else
      print_success "All issues resolved"
    fi
  else
    print_error "Claude returned invalid JSON - fix manually"
    echo "  Response preview: $(echo "$raw_response" | head -3)"
    return 1
  fi
}

# Quick validation without auto-fix (for re-checking after fix)
# Checks all the same things as validate_and_fix_stories() but returns issues string
validate_stories_quick() {
  local prd_file="$1"
  local issues=""

  local story_ids
  story_ids=$(jq -r '.stories[].id' "$prd_file" 2>/dev/null)

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
  done <<< "$story_ids"

  echo "$issues"
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
