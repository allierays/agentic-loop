#!/usr/bin/env bash
# shellcheck shell=bash
# Check for unused bash functions in ralph/*.sh and bin/*.sh
# Used by pre-commit hook - only runs when .sh files are changed

set -euo pipefail

# Colors
RED='\033[0;31m'
NC='\033[0m'

unused_count=0

# Find all bash files to analyze (including subdirectories)
bash_files=()
while IFS= read -r -d '' file; do
  bash_files+=("$file")
done < <(find ralph bin -name '*.sh' -type f -print0 2>/dev/null)

# Get all function definitions across all files
for file in "${bash_files[@]}"; do
  [[ -f "$file" ]] || continue

  # Match function definitions: name() { or function name
  while IFS= read -r func; do
    [[ -z "$func" ]] && continue

    # Skip private/helper functions (prefixed with _)
    [[ "$func" == _* ]] && continue

    # Skip functions marked as public API (have # public-api comment on same line)
    if grep -qE "^${func}\s*\(\).*#.*public-api" "$file" 2>/dev/null; then
      continue
    fi

    # Count total occurrences across all files (definition + calls)
    total_count=0
    for f in "${bash_files[@]}"; do
      [[ -f "$f" ]] || continue
      count=$(grep -cE "\b${func}\b" "$f" 2>/dev/null || true)
      count="${count:-0}"
      [[ "$count" =~ ^[0-9]+$ ]] || count=0
      total_count=$((total_count + count))
    done

    # If only 1 occurrence, it's just the definition (unused)
    if [[ $total_count -le 1 ]]; then
      echo -e "${RED}Unused function:${NC} $func in $file"
      unused_count=$((unused_count + 1))
    fi
  done < <(grep -oE '^[a-zA-Z][a-zA-Z0-9_]*\s*\(\)' "$file" 2>/dev/null | sed 's/()//;s/[[:space:]]//g')
done

if [[ $unused_count -gt 0 ]]; then
  echo ""
  echo "Found $unused_count unused function(s). Remove them or prefix with _ if internal."
  exit 1
fi

exit 0
