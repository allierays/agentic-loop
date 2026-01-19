#!/usr/bin/env bash
# prd.sh - PRD generation functions

ralph_prd() {
  local notes=""
  local from_file=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file|-f)
        from_file="$2"
        shift 2
        ;;
      --accept)
        ralph_prd_accept
        return $?
        ;;
      *)
        notes="$notes $1"
        shift
        ;;
    esac
  done

  # Read from file if specified
  if [[ -n "$from_file" ]]; then
    if [[ ! -f "$from_file" ]]; then
      print_error "File not found: $from_file"
      exit 1
    fi
    notes=$(cat "$from_file")
  fi

  # Trim whitespace
  notes=$(echo "$notes" | xargs)

  if [[ -z "$notes" ]]; then
    print_error "No notes provided. Usage: ralph prd <description>"
    echo ""
    echo "Examples:"
    echo "  ralph prd 'Add user authentication with OAuth'"
    echo "  ralph prd --file docs/feature-spec.md"
    exit 1
  fi

  # Check if PRD already exists
  if [[ -f "$RALPH_DIR/prd.json" ]]; then
    print_warning "A PRD already exists. Archive or delete it first."
    echo "  Current feature: $(jq -r '.feature.name' "$RALPH_DIR/prd.json")"
    echo ""
    echo "Options:"
    echo "  1. Archive it: mv .ralph/prd.json .ralph/archive/"
    echo "  2. Delete it:  rm .ralph/prd.json"
    echo "  3. Check status: ralph status"
    return 1
  fi

  # Check Claude CLI is available
  if ! command -v claude &>/dev/null; then
    print_error "Claude CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
    exit 1
  fi

  echo ""
  print_info "Starting interactive PRD generation..."
  echo "Claude will ask clarifying questions to refine the PRD."
  echo ""

  # Get testUrlBase from config (default to localhost:3000)
  local test_url_base
  test_url_base=$(get_config "testUrlBase" "http://localhost:3000")

  # Create the PRD generation prompt using printf to avoid heredoc issues
  local prompt_file
  prompt_file=$(create_temp_file ".md") || return 1

  printf '%s\n' "You are generating a PRD (Product Requirements Document) for an autonomous coding agent called Ralph." > "$prompt_file"
  printf '\n%s\n' "The user provided these feature notes:" >> "$prompt_file"
  printf '\n%s\n' "---" >> "$prompt_file"
  printf '%s\n' "$notes" >> "$prompt_file"
  printf '%s\n' "---" >> "$prompt_file"
  printf '\n%s\n' "## Your Task" >> "$prompt_file"
  printf '\n%s\n' "1. First, ask up to 5 clarifying questions about:" >> "$prompt_file"
  printf '%s\n' "   - Security requirements (auth, permissions, data access)" >> "$prompt_file"
  printf '%s\n' "   - Scaling concerns (caching, pagination, rate limits)" >> "$prompt_file"
  printf '%s\n' "   - Edge cases (empty states, error handling)" >> "$prompt_file"
  printf '%s\n' "   - Related features (what existing features does this touch?)" >> "$prompt_file"
  printf '%s\n' "   - Scope boundaries (what is explicitly OUT of scope?)" >> "$prompt_file"
  printf '\n%s\n' "2. After the user answers, generate a prd.json file with this exact structure:" >> "$prompt_file"
  printf '\n%s\n' '{' >> "$prompt_file"
  printf '%s\n' '  "feature": {' >> "$prompt_file"
  printf '%s\n' '    "name": "Feature Name",' >> "$prompt_file"
  printf '%s\n' '    "branch": "feature/feature-name",' >> "$prompt_file"
  printf '%s\n' '    "status": "pending"' >> "$prompt_file"
  printf '%s\n' '  },' >> "$prompt_file"
  printf '%s\n' '  "metadata": {' >> "$prompt_file"
  printf '%s\n' '    "security": ["list of security requirements"],' >> "$prompt_file"
  printf '%s\n' '    "scaling": ["list of scaling concerns"],' >> "$prompt_file"
  printf '%s\n' '    "relatedFeatures": ["list of related features"],' >> "$prompt_file"
  printf '%s\n' '    "estimatedStories": 5,' >> "$prompt_file"
  printf '%s\n' '    "complexity": "low|medium|high"' >> "$prompt_file"
  printf '%s\n' '  },' >> "$prompt_file"
  printf '%s\n' '  "scalability": {' >> "$prompt_file"
  printf '%s\n' '    "expectedScale": "100s | 1000s | 10000s+ users",' >> "$prompt_file"
  printf '%s\n' '    "pagination": "cursor | offset | none",' >> "$prompt_file"
  printf '%s\n' '    "caching": "none | in-memory | redis",' >> "$prompt_file"
  printf '%s\n' '    "rateLimiting": "if needed, requests per minute"' >> "$prompt_file"
  printf '%s\n' '  },' >> "$prompt_file"
  printf '%s\n' '  "architecture": {' >> "$prompt_file"
  printf '%s\n' '    "directories": {' >> "$prompt_file"
  printf '%s\n' '      "components": "src/components/{feature}/",' >> "$prompt_file"
  printf '%s\n' '      "api": "src/api/",' >> "$prompt_file"
  printf '%s\n' '      "types": "src/types/",' >> "$prompt_file"
  printf '%s\n' '      "scripts": "scripts/",' >> "$prompt_file"
  printf '%s\n' '      "docs": "docs/"' >> "$prompt_file"
  printf '%s\n' '    },' >> "$prompt_file"
  printf '%s\n' '    "patterns": {' >> "$prompt_file"
  printf '%s\n' '      "reuse": ["existing components/utils to use"],' >> "$prompt_file"
  printf '%s\n' '      "follow": ["existing patterns to match"]' >> "$prompt_file"
  printf '%s\n' '    },' >> "$prompt_file"
  printf '%s\n' '    "principles": {' >> "$prompt_file"
  printf '%s\n' '      "maxFileLines": 300,' >> "$prompt_file"
  printf '%s\n' '      "singleResponsibility": true' >> "$prompt_file"
  printf '%s\n' '    },' >> "$prompt_file"
  printf '%s\n' '    "doNotCreate": ["things that already exist"]' >> "$prompt_file"
  printf '%s\n' '  },' >> "$prompt_file"
  printf '%s\n' '  "stories": [' >> "$prompt_file"
  printf '%s\n' '    {' >> "$prompt_file"
  printf '%s\n' '      "id": "US-001",' >> "$prompt_file"
  printf '%s\n' '      "title": "Story title",' >> "$prompt_file"
  printf '%s\n' '      "passes": false,' >> "$prompt_file"
  printf '%s\n' "      \"testUrl\": \"${test_url_base}/path/to/test\"," >> "$prompt_file"
  printf '%s\n' '      "files": {' >> "$prompt_file"
  printf '%s\n' '        "create": ["paths to new files"],' >> "$prompt_file"
  printf '%s\n' '        "modify": ["paths to existing files"],' >> "$prompt_file"
  printf '%s\n' '        "reuse": ["paths to files to import from"]' >> "$prompt_file"
  printf '%s\n' '      },' >> "$prompt_file"
  printf '%s\n' '      "acceptanceCriteria": ["AC 1", "AC 2"],' >> "$prompt_file"
  printf '%s\n' '      "errorHandling": ["what happens on failure"],' >> "$prompt_file"
  printf '%s\n' '      "testSteps": ["curl command or playwright test command"]' >> "$prompt_file"
  printf '%s\n' '    }' >> "$prompt_file"
  printf '%s\n' '  ]' >> "$prompt_file"
  printf '%s\n' '}' >> "$prompt_file"
  printf '\n%s\n' "## Context Rot Check" >> "$prompt_file"
  printf '\n%s\n' "Before finalizing, validate:" >> "$prompt_file"
  printf '%s\n' "- If > 10 stories, recommend splitting into phases" >> "$prompt_file"
  printf '%s\n' '- If complexity is "high" AND > 5 stories, MUST split' >> "$prompt_file"
  printf '%s\n' "- Each story should be completable in one Claude session (~10 min)" >> "$prompt_file"
  printf '\n%s\n' "If splitting is needed, generate ONLY phase 1 and note deferred items." >> "$prompt_file"
  printf '\n%s\n' "## Output" >> "$prompt_file"
  printf '\n%s\n' "After questions are answered, output the prd.json content between these exact markers:" >> "$prompt_file"
  printf '%s\n' "--- BEGIN PRD.JSON ---" >> "$prompt_file"
  printf '%s\n' "{the json here}" >> "$prompt_file"
  printf '%s\n' "--- END PRD.JSON ---" >> "$prompt_file"

  # Run Claude interactively (not -p mode so user can answer questions)
  local output_file
  output_file=$(create_temp_file ".txt") || return 1

  claude < "$prompt_file" | tee "$output_file"

  # Save output for --accept command (store in RALPH_DIR for security)
  mkdir -p "$RALPH_DIR"
  cp "$output_file" "$RALPH_DIR/prd_output.txt"

  rm -f "$prompt_file" "$output_file"

  echo ""
  echo "---"
  echo ""
  print_info "PRD generation complete."
  echo ""
  echo "To save the PRD, run: ralph prd --accept"
  echo "Or manually copy the JSON to .ralph/prd.json"
}

# Extract PRD from Claude output and save
ralph_prd_accept() {
  local output_file="$RALPH_DIR/prd_output.txt"

  if [[ ! -f "$output_file" ]]; then
    print_error "No PRD output found. Run 'ralph prd' first."
    return 1
  fi

  # Extract JSON between markers
  local prd_json
  prd_json=$(sed -n '/--- BEGIN PRD.JSON ---/,/--- END PRD.JSON ---/p' "$output_file" | sed '1d;$d')

  if [[ -z "$prd_json" ]]; then
    print_error "Could not find PRD JSON in output"
    echo ""
    echo "The output should contain JSON between markers:"
    echo "  --- BEGIN PRD.JSON ---"
    echo "  {...}"
    echo "  --- END PRD.JSON ---"
    return 1
  fi

  # Validate JSON syntax
  if ! echo "$prd_json" | jq . > /dev/null 2>&1; then
    print_error "Invalid JSON in PRD"
    echo ""
    echo "JSON parsing error. Content:"
    echo "$prd_json" | head -20
    return 1
  fi

  # Validate required fields exist
  if ! echo "$prd_json" | jq -e '.feature.name and .stories' > /dev/null 2>&1; then
    print_error "PRD JSON missing required fields (feature.name or stories)"
    echo ""
    echo "Ensure the PRD has this structure:"
    echo '  { "feature": { "name": "..." }, "stories": [...] }'
    return 1
  fi

  # Ensure .ralph directory exists
  mkdir -p "$RALPH_DIR"

  # Save
  echo "$prd_json" > "$RALPH_DIR/prd.json"

  # Show summary
  local name stories complexity
  name=$(echo "$prd_json" | jq -r '.feature.name')
  stories=$(echo "$prd_json" | jq '.stories | length')
  complexity=$(echo "$prd_json" | jq -r '.metadata.complexity // "unknown"')

  print_success "PRD saved to $RALPH_DIR/prd.json"
  echo ""
  echo "Feature:    $name"
  echo "Stories:    $stories"
  echo "Complexity: $complexity"
  echo ""
  echo "Next: Run ralph run to start the autonomous loop"

  # Clean up
  rm -f "$RALPH_DIR/prd_output.txt"

  return 0
}
