#!/usr/bin/env bash
# shellcheck shell=bash
# lessons.sh - Learned patterns management

# Add a new lesson (learned pattern)
ralph_lesson() {
  if [[ $# -lt 1 ]]; then
    print_error "Usage: ralph lesson 'pattern' [category]"
    echo ""
    echo "Examples:"
    echo "  ralph lesson 'Always use camelCase in WebSocket responses' frontend"
    echo "  ralph lesson 'Run migrations before seeding' backend"
    echo "  ralph lesson 'Check for null before accessing nested props' general"
    return 1
  fi

  local pattern="$1"
  local category="${2:-general}"
  local auto_promoted="${3:-false}"
  local learned_from_override="${4:-}"

  # Ensure .ralph directory exists
  if [[ ! -d "$RALPH_DIR" ]]; then
    print_error "Ralph not initialized. Run 'ralph init' first."
    return 1
  fi

  # Reject lessons that contain credentials or secrets
  if echo "$pattern" | grep -qiE '([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}|password[[:space:]]*[:=]|[[:space:]][A-Za-z0-9_]*_?(pass|pwd|token|secret|key|api.?key)[[:space:]]*[:=]|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36})'; then
    print_error "Lesson contains what looks like credentials (email, password, token, etc.)"
    echo "  Lessons are saved to .ralph/lessons.json which may be committed to git."
    echo "  Use environment variables instead of hardcoded credentials."
    return 1
  fi

  # Ensure lessons.json exists
  if [[ ! -f "$RALPH_DIR/lessons.json" ]]; then
    echo '{"lessons": []}' > "$RALPH_DIR/lessons.json"
  fi

  # Generate lesson ID
  local lesson_count
  lesson_count=$(jq '.lessons | length' "$RALPH_DIR/lessons.json")
  local lesson_id="lesson-$(printf '%03d' $((lesson_count + 1)))"

  # Get current story if available (for learnedFrom field)
  # Override can be passed as 4th arg (used by auto-promote, since story is already marked passed)
  local learned_from=""
  if [[ -n "$learned_from_override" ]]; then
    learned_from="$learned_from_override"
  elif [[ -f "$RALPH_DIR/prd.json" ]]; then
    learned_from=$(jq -r '.stories[] | select(.passes==false) | .id' "$RALPH_DIR/prd.json" 2>/dev/null | head -1)
  fi

  # Get timestamp
  local timestamp
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Add the lesson
  local tmpfile
  tmpfile=$(mktemp)

  if jq --arg id "$lesson_id" \
     --arg pattern "$pattern" \
     --arg category "$category" \
     --arg learnedFrom "$learned_from" \
     --arg createdAt "$timestamp" \
     --argjson autoPromoted "$( [[ "$auto_promoted" == "true" ]] && echo "true" || echo "false" )" \
     '.lessons += [{
       id: $id,
       pattern: $pattern,
       category: $category,
       learnedFrom: (if $learnedFrom == "" then null else $learnedFrom end),
       autoPromoted: $autoPromoted,
       createdAt: $createdAt
     }]' "$RALPH_DIR/lessons.json" > "$tmpfile" && jq -e . "$tmpfile" >/dev/null 2>&1; then
    mv "$tmpfile" "$RALPH_DIR/lessons.json"
    print_success "Added lesson: [$category] $pattern"
    log_progress "LESSON" "ADDED" "$lesson_id: $pattern"
  else
    rm -f "$tmpfile"
    print_error "Failed to add lesson"
    return 1
  fi
}

# List all lessons
ralph_lessons() {
  if [[ ! -f "$RALPH_DIR/lessons.json" ]]; then
    echo "No lessons recorded yet."
    echo ""
    echo "Add one with: ralph lesson 'your learned pattern' [category]"
    return 0
  fi

  local count
  count=$(jq '.lessons | length' "$RALPH_DIR/lessons.json")

  if [[ "$count" -eq 0 ]]; then
    echo "No lessons recorded yet."
    echo ""
    echo "Add one with: ralph lesson 'your learned pattern' [category]"
    return 0
  fi

  echo ""
  print_info "=== Learned Patterns ($count lessons) ==="
  echo ""

  # Group by category
  local categories
  categories=$(jq -r '.lessons[].category' "$RALPH_DIR/lessons.json" | sort -u)

  while IFS= read -r category; do
    [[ -z "$category" ]] && continue

    echo "[$category]"
    jq -r --arg cat "$category" '.lessons[] | select(.category==$cat) | "  - \(.pattern)\(if .autoPromoted == true then " (auto)" else "" end)"' "$RALPH_DIR/lessons.json"
    echo ""
  done <<< "$categories"
}

# Remove a lesson by ID or pattern match
ralph_forget() {
  local target="$1"

  if [[ -z "$target" ]]; then
    print_error "Usage: ralph forget <lesson-id or pattern>"
    return 1
  fi

  if [[ ! -f "$RALPH_DIR/lessons.json" ]]; then
    print_error "No lessons file found"
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp)

  # Try to match by ID first, then by pattern substring
  if jq --arg target "$target" '
    if (.lessons | map(select(.id == $target)) | length) > 0 then
      .lessons |= map(select(.id != $target))
    else
      .lessons |= map(select(.pattern | contains($target) | not))
    end
  ' "$RALPH_DIR/lessons.json" > "$tmpfile"; then
    local before after removed
    before=$(jq '.lessons | length' "$RALPH_DIR/lessons.json")
    after=$(jq '.lessons | length' "$tmpfile")
    removed=$((before - after))

    if [[ $removed -gt 0 ]]; then
      mv "$tmpfile" "$RALPH_DIR/lessons.json"
      print_success "Removed $removed lesson(s)"
    else
      rm -f "$tmpfile"
      print_warning "No matching lessons found"
    fi
  else
    rm -f "$tmpfile"
    print_error "Failed to process lessons"
    return 1
  fi
}
