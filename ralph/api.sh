#!/usr/bin/env bash
# api.sh - API validation for backend stories

# Validate API endpoints for a backend story
run_api_validation() {
  local story="$1"

  # Get API endpoints from story
  local endpoints
  endpoints=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .apiEndpoints[]?' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$endpoints" ]]; then
    echo "  (no apiEndpoints defined, skipping API validation)"
    return 0
  fi

  # Get base URL from config or use default
  local base_url
  base_url=$(get_config '.api.baseUrl' "http://localhost:3000")

  local failed=0

  echo "  Validating API endpoints..."

  while IFS= read -r endpoint; do
    [[ -z "$endpoint" ]] && continue

    # Skip WebSocket endpoints - they can't be tested with HTTP curl
    if [[ "$endpoint" =~ ^wss?:// ]] || [[ "$endpoint" =~ ^(GET|POST|PUT|PATCH|DELETE)[[:space:]]+wss?:// ]]; then
      echo "    Skipping WebSocket endpoint: $endpoint (use integration tests)"
      continue
    fi

    # Parse method and path (e.g., "POST /api/contact" or just "/api/contact")
    local method="GET"
    local path="$endpoint"

    if [[ "$endpoint" =~ ^(GET|POST|PUT|PATCH|DELETE)[[:space:]]+(.*) ]]; then
      method="${BASH_REMATCH[1]}"
      path="${BASH_REMATCH[2]}"
    fi

    # Handle full URLs vs relative paths
    local full_url
    if [[ "$path" =~ ^https?:// ]]; then
      full_url="$path"
    else
      full_url="${base_url}${path}"
    fi

    echo -n "    $method $path... "

    # Make the request (10 second timeout)
    local response_code
    response_code=$(curl -sf -m 10 -o /dev/null -w "%{http_code}" -X "$method" "$full_url" 2>/dev/null)

    if [[ "$response_code" =~ ^2[0-9][0-9]$ ]]; then
      print_success "$response_code"
    elif [[ "$response_code" == "000" ]]; then
      print_error "connection failed"
      failed=1
    else
      print_error "$response_code"
      failed=1
    fi
  done <<< "$endpoints"

  return $failed
}

# Run comprehensive API tests for a story
run_api_tests() {
  local story="$1"

  # Get test steps that look like API calls
  local test_steps
  test_steps=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testSteps[]?' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$test_steps" ]]; then
    return 0
  fi

  local failed=0
  local log_file
  log_file=$(create_temp_file ".log") || return 1

  echo "  Running API test steps..."

  while IFS= read -r step; do
    [[ -z "$step" ]] && continue

    # Check if this looks like a curl command or API test
    if [[ "$step" =~ ^curl ]]; then
      echo -n "    $step... "

      if safe_exec "$step" "$log_file"; then
        print_success "passed"
      else
        print_error "failed"
        echo ""
        echo "    Response:"
        tail -"$MAX_OUTPUT_PREVIEW_LINES" "$log_file" | sed 's/^/      /'
        failed=1
      fi
    fi
  done <<< "$test_steps"

  rm -f "$log_file"
  return $failed
}

# Validate error handling for API
run_api_error_tests() {
  local story="$1"

  # Get error handling requirements
  local error_handling
  error_handling=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .errorHandling[]?' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$error_handling" ]]; then
    return 0
  fi

  # Get base URL and endpoints
  local base_url
  base_url=$(get_config '.api.baseUrl' "http://localhost:3000")

  local endpoints
  endpoints=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .apiEndpoints[0]?' "$RALPH_DIR/prd.json" 2>/dev/null)

  if [[ -z "$endpoints" ]]; then
    return 0
  fi

  # Skip WebSocket endpoints
  if [[ "$endpoints" =~ ^wss?:// ]] || [[ "$endpoints" =~ ^(GET|POST|PUT|PATCH|DELETE)[[:space:]]+wss?:// ]]; then
    echo "  Skipping error tests for WebSocket endpoint"
    return 0
  fi

  # Parse endpoint
  local method="POST"
  local path="$endpoints"
  if [[ "$endpoints" =~ ^(GET|POST|PUT|PATCH|DELETE)[[:space:]]+(.*) ]]; then
    method="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
  fi

  # Handle full URLs vs relative paths
  local full_url
  if [[ "$path" =~ ^https?:// ]]; then
    full_url="$path"
  else
    full_url="${base_url}${path}"
  fi
  local failed=0

  echo "  Testing API error handling..."

  # Test common error cases
  while IFS= read -r error_case; do
    [[ -z "$error_case" ]] && continue

    # Check for 400 tests (bad input)
    if [[ "$error_case" =~ 400 ]]; then
      echo -n "    Testing 400 (bad request)... "

      local response_code
      response_code=$(curl -sf -m 10 -o /dev/null -w "%{http_code}" \
        -X "$method" \
        -H "Content-Type: application/json" \
        -d '{}' \
        "$full_url" 2>/dev/null)

      if [[ "$response_code" == "400" ]]; then
        print_success "correctly returns 400"
      else
        print_warning "got $response_code (expected 400)"
      fi
    fi

    # Check for 401 tests (unauthorized)
    if [[ "$error_case" =~ 401 ]]; then
      echo -n "    Testing 401 (unauthorized)... "

      local response_code
      response_code=$(curl -sf -m 10 -o /dev/null -w "%{http_code}" \
        -X "$method" \
        "$full_url" 2>/dev/null)

      if [[ "$response_code" == "401" ]]; then
        print_success "correctly returns 401"
      else
        print_warning "got $response_code (expected 401)"
      fi
    fi
  done <<< "$error_handling"

  return $failed
}
