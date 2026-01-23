#!/usr/bin/env bash
# review.sh - Code review verification module for ralph

# Run code review on changes
run_code_review() {
  local story="$1"

  # Check if code review is enabled in config
  local review_enabled
  review_enabled=$(get_config '.verification.codeReviewEnabled' "true")
  if [[ "$review_enabled" == "false" ]]; then
    echo "    (code review disabled in config, skipping)"
    return 0
  fi

  # Check if git is available
  if ! command -v git &>/dev/null || [[ ! -d ".git" ]]; then
    echo "    (no git repository, skipping)"
    return 0
  fi

  # Get the diff of uncommitted changes
  local diff
  diff=$(git diff HEAD 2>/dev/null)

  if [[ -z "$diff" ]]; then
    # No uncommitted changes, check staged
    diff=$(git diff --cached 2>/dev/null)
  fi

  if [[ -z "$diff" ]]; then
    echo "    (no changes to review)"
    return 0
  fi

  # Get story context for the review
  local story_json
  story_json=$(jq --arg id "$story" '.stories[] | select(.id==$id)' "$RALPH_DIR/prd.json" 2>/dev/null)

  # Build the code review prompt
  local prompt
  prompt=$(cat <<EOF
You are a senior code reviewer. Review this diff for a story implementation.

## Story Context
\`\`\`json
$story_json
\`\`\`

## Code Diff
\`\`\`diff
$diff
\`\`\`

## Review Checklist

Check for these issues:

1. **Security** - SQL injection, XSS, command injection, hardcoded secrets, OWASP top 10
2. **Error handling** - Missing try/catch, unhandled promise rejections, silent failures
3. **Edge cases** - Null/undefined checks, empty arrays, boundary conditions
4. **Code quality** - Unused variables, dead code, overly complex logic
5. **Performance** - N+1 queries, unnecessary re-renders, memory leaks
6. **Scalability** - Unbounded queries? Missing pagination? Missing indexes? No caching strategy?
7. **Accessibility** - Missing ARIA labels, keyboard navigation, color contrast (if frontend)
8. **Story compliance** - Does the code actually implement what the story requires?
9. **Architecture** - Files in correct directories? Reusing existing components? File size < 300 lines?
10. **No duplication** - Creating something that already exists? Reinventing utilities?

## Response Format

Respond with ONLY a JSON object:
{
  "pass": true/false,
  "issues": [
    {
      "severity": "critical|warning|info",
      "category": "security|error-handling|edge-case|quality|performance|scalability|a11y|architecture|compliance",
      "file": "path/to/file",
      "line": 123,
      "message": "Description of the issue",
      "suggestion": "How to fix it"
    }
  ],
  "summary": "Brief overall assessment"
}

Only fail (pass: false) for critical or multiple warning-level issues.
EOF
)

  echo "    Reviewing changes..."

  local result
  # Timeout for code review (defined in utils.sh)
  result=$(echo "$prompt" | run_with_timeout "$CODE_REVIEW_TIMEOUT_SECONDS" claude -p --dangerously-skip-permissions 2>/dev/null) || {
    print_warning "    Code review skipped (Claude unavailable or timed out)"
    return 0
  }

  # Save review result
  mkdir -p "$RALPH_DIR/reviews"
  echo "$result" > "$RALPH_DIR/reviews/${story}-review.json"

  # Extract JSON from markdown code blocks if present
  local json_result
  if echo "$result" | grep -q '```json'; then
    json_result=$(echo "$result" | sed -n '/```json/,/```/p' | sed '1d;$d')
  elif echo "$result" | grep -q '```'; then
    json_result=$(echo "$result" | sed -n '/```/,/```/p' | sed '1d;$d')
  else
    json_result="$result"
  fi

  # Check if result is valid JSON
  if ! echo "$json_result" | jq -e . >/dev/null 2>&1; then
    print_warning "    Code review returned invalid response, skipping"
    return 0
  fi

  local passed
  passed=$(echo "$json_result" | jq -r '.pass // true' 2>/dev/null)

  # Handle empty/null result
  if [[ -z "$passed" || "$passed" == "null" ]]; then
    print_warning "    Code review inconclusive, continuing"
    return 0
  fi

  if [[ "$passed" == "true" ]]; then
    print_success "passed"

    # Show any warnings/info even on pass
    local warnings
    warnings=$(echo "$json_result" | jq -r '.issues[] | select(.severity != "critical") | "      [\(.severity)] \(.message)"' 2>/dev/null)
    if [[ -n "$warnings" ]]; then
      echo "    Notes:"
      echo "$warnings"
    fi
    return 0
  else
    print_error "failed"
    echo ""

    # Show all issues
    echo "    Issues found:"
    echo "$json_result" | jq -r '.issues[] | "      [\(.severity)] \(.category): \(.message)"' 2>/dev/null
    echo ""
    echo "    Summary: $(echo "$json_result" | jq -r '.summary // "Review failed"' 2>/dev/null)"

    # Save for failure context
    echo "$json_result" > "$RALPH_DIR/last_review_failure.json"
    return 1
  fi
}
