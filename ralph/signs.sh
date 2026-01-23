#!/usr/bin/env bash
# shellcheck shell=bash
# signs.sh - Learned patterns management

# Add a new sign (learned pattern)
ralph_sign() {
  if [[ $# -lt 1 ]]; then
    print_error "Usage: ralph sign 'pattern' [category]"
    echo ""
    echo "Examples:"
    echo "  ralph sign 'Always use camelCase in WebSocket responses' frontend"
    echo "  ralph sign 'Run migrations before seeding' backend"
    echo "  ralph sign 'Check for null before accessing nested props' general"
    return 1
  fi

  local pattern="$1"
  local category="${2:-general}"

  # Ensure .ralph directory exists
  if [[ ! -d "$RALPH_DIR" ]]; then
    print_error "Ralph not initialized. Run 'ralph init' first."
    return 1
  fi

  # Ensure signs.json exists
  if [[ ! -f "$RALPH_DIR/signs.json" ]]; then
    echo '{"signs": []}' > "$RALPH_DIR/signs.json"
  fi

  # Generate sign ID
  local sign_count
  sign_count=$(jq '.signs | length' "$RALPH_DIR/signs.json")
  local sign_id="sign-$(printf '%03d' $((sign_count + 1)))"

  # Get current story if available (for learnedFrom field)
  local learned_from=""
  if [[ -f "$RALPH_DIR/prd.json" ]]; then
    learned_from=$(jq -r '.stories[] | select(.passes==false) | .id' "$RALPH_DIR/prd.json" 2>/dev/null | head -1)
  fi

  # Get timestamp
  local timestamp
  timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)

  # Add the sign
  local tmpfile
  tmpfile=$(mktemp)

  if jq --arg id "$sign_id" \
     --arg pattern "$pattern" \
     --arg category "$category" \
     --arg learnedFrom "$learned_from" \
     --arg createdAt "$timestamp" \
     '.signs += [{
       id: $id,
       pattern: $pattern,
       category: $category,
       learnedFrom: (if $learnedFrom == "" then null else $learnedFrom end),
       createdAt: $createdAt
     }]' "$RALPH_DIR/signs.json" > "$tmpfile" && jq -e . "$tmpfile" >/dev/null 2>&1; then
    mv "$tmpfile" "$RALPH_DIR/signs.json"
    print_success "Added sign: [$category] $pattern"
    log_progress "SIGN" "ADDED" "$sign_id: $pattern"
  else
    rm -f "$tmpfile"
    print_error "Failed to add sign"
    return 1
  fi
}

# List all signs
ralph_signs() {
  if [[ ! -f "$RALPH_DIR/signs.json" ]]; then
    echo "No signs recorded yet."
    echo ""
    echo "Add one with: ralph sign 'your learned pattern' [category]"
    return 0
  fi

  local count
  count=$(jq '.signs | length' "$RALPH_DIR/signs.json")

  if [[ "$count" -eq 0 ]]; then
    echo "No signs recorded yet."
    echo ""
    echo "Add one with: ralph sign 'your learned pattern' [category]"
    return 0
  fi

  echo ""
  print_info "=== Learned Patterns ($count signs) ==="
  echo ""

  # Group by category
  local categories
  categories=$(jq -r '.signs[].category' "$RALPH_DIR/signs.json" | sort -u)

  while IFS= read -r category; do
    [[ -z "$category" ]] && continue

    echo "[$category]"
    jq -r --arg cat "$category" '.signs[] | select(.category==$cat) | "  - \(.pattern)"' "$RALPH_DIR/signs.json"
    echo ""
  done <<< "$categories"
}

# Remove a sign by ID or pattern match
ralph_unsign() {
  local target="$1"

  if [[ -z "$target" ]]; then
    print_error "Usage: ralph unsign <sign-id or pattern>"
    return 1
  fi

  if [[ ! -f "$RALPH_DIR/signs.json" ]]; then
    print_error "No signs file found"
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp)

  # Try to match by ID first, then by pattern substring
  if jq --arg target "$target" '
    if (.signs | map(select(.id == $target)) | length) > 0 then
      .signs |= map(select(.id != $target))
    else
      .signs |= map(select(.pattern | contains($target) | not))
    end
  ' "$RALPH_DIR/signs.json" > "$tmpfile"; then
    local before after removed
    before=$(jq '.signs | length' "$RALPH_DIR/signs.json")
    after=$(jq '.signs | length' "$tmpfile")
    removed=$((before - after))

    if [[ $removed -gt 0 ]]; then
      mv "$tmpfile" "$RALPH_DIR/signs.json"
      print_success "Removed $removed sign(s)"
    else
      rm -f "$tmpfile"
      print_warning "No matching signs found"
    fi
  else
    rm -f "$tmpfile"
    print_error "Failed to process signs"
    return 1
  fi
}
