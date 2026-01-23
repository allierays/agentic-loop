#!/usr/bin/env bash
# shellcheck shell=bash
# api.sh - API validation for backend stories

# Parse an endpoint string into method and path
# Usage: parse_endpoint "POST /api/users" "http://localhost:3000"
# Sets: ENDPOINT_METHOD, ENDPOINT_PATH, ENDPOINT_URL
parse_endpoint() {
  local endpoint="$1"
  local base_url="${2:-}"

  # Defaults
  ENDPOINT_METHOD="GET"
  ENDPOINT_PATH="$endpoint"
  ENDPOINT_URL=""

  # Parse method if present (e.g., "POST /api/contact")
  if [[ "$endpoint" =~ ^(GET|POST|PUT|PATCH|DELETE)[[:space:]]+(.*) ]]; then
    ENDPOINT_METHOD="${BASH_REMATCH[1]}"
    ENDPOINT_PATH="${BASH_REMATCH[2]}"
  fi

  # Build full URL
  if [[ "$ENDPOINT_PATH" =~ ^https?:// ]]; then
    ENDPOINT_URL="$ENDPOINT_PATH"
  elif [[ -n "$base_url" ]]; then
    ENDPOINT_URL="${base_url}${ENDPOINT_PATH}"
  fi
}

# Check if endpoint is a WebSocket (can't be tested with HTTP)
is_websocket_endpoint() {
  local endpoint="$1"
  [[ "$endpoint" =~ ^wss?:// ]] || [[ "$endpoint" =~ ^(GET|POST|PUT|PATCH|DELETE)[[:space:]]+wss?:// ]]
}

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
    if is_websocket_endpoint "$endpoint"; then
      echo "    Skipping WebSocket endpoint: $endpoint (use integration tests)"
      continue
    fi

    # Parse endpoint into method, path, and full URL
    parse_endpoint "$endpoint" "$base_url"

    echo -n "    $ENDPOINT_METHOD $ENDPOINT_PATH... "

    # Make the request
    local response_code
    response_code=$(curl -sf -m "$CURL_TIMEOUT_SECONDS" -o /dev/null -w "%{http_code}" -X "$ENDPOINT_METHOD" "$ENDPOINT_URL" 2>/dev/null)

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
  if is_websocket_endpoint "$endpoints"; then
    echo "  Skipping error tests for WebSocket endpoint"
    return 0
  fi

  # Parse endpoint (default to POST for error tests)
  parse_endpoint "$endpoints" "$base_url"
  [[ "$ENDPOINT_METHOD" == "GET" ]] && ENDPOINT_METHOD="POST"

  local failed=0

  echo "  Testing API error handling..."

  # Test common error cases
  while IFS= read -r error_case; do
    [[ -z "$error_case" ]] && continue

    # Check for 400 tests (bad input)
    if [[ "$error_case" =~ 400 ]]; then
      echo -n "    Testing 400 (bad request)... "

      local response_code
      response_code=$(curl -sf -m "$CURL_TIMEOUT_SECONDS" -o /dev/null -w "%{http_code}" \
        -X "$ENDPOINT_METHOD" \
        -H "Content-Type: application/json" \
        -d '{}' \
        "$ENDPOINT_URL" 2>/dev/null)

      if [[ "$response_code" == "400" ]]; then
        print_success "correctly returns 400"
      else
        print_warning "got $response_code (expected 400)"
        failed=1
      fi
    fi

    # Check for 401 tests (unauthorized)
    if [[ "$error_case" =~ 401 ]]; then
      echo -n "    Testing 401 (unauthorized)... "

      local response_code
      response_code=$(curl -sf -m "$CURL_TIMEOUT_SECONDS" -o /dev/null -w "%{http_code}" \
        -X "$ENDPOINT_METHOD" \
        "$ENDPOINT_URL" 2>/dev/null)

      if [[ "$response_code" == "401" ]]; then
        print_success "correctly returns 401"
      else
        print_warning "got $response_code (expected 401)"
        failed=1
      fi
    fi
  done <<< "$error_handling"

  return $failed
}
