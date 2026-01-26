#!/usr/bin/env bash
# shellcheck shell=bash
# api.sh - API and frontend smoke test verification module for ralph
#
# Catches broken APIs/frontends that unit tests miss (because they mock everything).
# Uses config.json for endpoints - no project-specific hardcoding.

# Run API smoke test against configured endpoints
# Config options:
#   api.baseUrl        - Base URL (e.g., http://localhost:8001)
#   api.healthEndpoint - Health check path (e.g., /health)
#   api.smokeEndpoints - Array of paths to test (e.g., ["/api/v1/users", "/api/v1/items"])
#
# Also tests story-specific apiEndpoints from PRD if defined.
run_api_smoke_test() {
  local story="$1"

  # Check if API smoke tests are enabled (default: true if baseUrl configured)
  local base_url
  base_url=$(get_config '.api.baseUrl' "")

  # No API configured, skip silently
  [[ -z "$base_url" ]] && return 0

  echo ""
  echo "  [4/4] Running API smoke tests..."

  local failed=0
  local endpoints_tested=0

  # 1. Health endpoint (most important)
  local health_endpoint
  health_endpoint=$(get_config '.api.healthEndpoint' "/health")
  if [[ -n "$health_endpoint" ]]; then
    if ! _smoke_test_endpoint "$base_url" "$health_endpoint" "health"; then
      failed=1
    fi
    ((endpoints_tested++))
  fi

  # 2. Configured smoke endpoints
  local smoke_endpoints
  smoke_endpoints=$(get_config '.api.smokeEndpoints' "[]")
  if [[ "$smoke_endpoints" != "[]" && "$smoke_endpoints" != "null" ]]; then
    while IFS= read -r endpoint; do
      [[ -z "$endpoint" ]] && continue
      if ! _smoke_test_endpoint "$base_url" "$endpoint" "smoke"; then
        failed=1
      fi
      ((endpoints_tested++))
    done < <(echo "$smoke_endpoints" | jq -r '.[]' 2>/dev/null)
  fi

  # 3. Story-specific apiEndpoints from PRD
  local story_endpoints
  story_endpoints=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .apiEndpoints[]?' "$RALPH_DIR/prd.json" 2>/dev/null)
  if [[ -n "$story_endpoints" ]]; then
    while IFS= read -r endpoint_spec; do
      [[ -z "$endpoint_spec" ]] && continue
      # Format: "GET /api/v1/users" or "POST /api/v1/items" or just "/api/v1/users"
      local method="GET"
      local path="$endpoint_spec"
      if [[ "$endpoint_spec" =~ ^(GET|POST|PUT|DELETE|PATCH)[[:space:]]+(.*) ]]; then
        method="${BASH_REMATCH[1]}"
        path="${BASH_REMATCH[2]}"
      fi
      if ! _smoke_test_endpoint "$base_url" "$path" "story" "$method"; then
        failed=1
      fi
      ((endpoints_tested++))
    done <<< "$story_endpoints"
  fi

  if [[ $endpoints_tested -eq 0 ]]; then
    echo "    (no endpoints configured, skipping)"
    return 0
  fi

  return $failed
}

# Run frontend smoke test
# Config options:
#   urls.frontend      - Frontend URL (e.g., http://localhost:3000)
#   frontend.smokePages - Array of paths to test (e.g., ["/", "/login", "/dashboard"])
run_frontend_smoke_test() {
  local story="$1"
  local story_type="${RALPH_STORY_TYPE:-general}"

  # Get frontend URL from config (try multiple locations)
  local frontend_url
  frontend_url=$(get_config '.urls.frontend' "")
  [[ -z "$frontend_url" ]] && frontend_url=$(get_config '.playwright.baseUrl' "")

  # No frontend configured, skip silently
  [[ -z "$frontend_url" ]] && return 0

  # Skip for backend-only stories (optional optimization)
  # [[ "$story_type" == "backend" ]] && return 0

  echo ""
  echo "  [5/5] Running frontend smoke tests..."

  local failed=0
  local pages_tested=0

  # 1. Test root page (most important)
  if ! _smoke_test_page "$frontend_url" "/" "root"; then
    failed=1
  fi
  ((pages_tested++))

  # 2. Configured smoke pages
  local smoke_pages
  smoke_pages=$(get_config '.frontend.smokePages' "[]")
  if [[ "$smoke_pages" != "[]" && "$smoke_pages" != "null" ]]; then
    while IFS= read -r page; do
      [[ -z "$page" ]] && continue
      [[ "$page" == "/" ]] && continue  # Already tested root
      if ! _smoke_test_page "$frontend_url" "$page" "smoke"; then
        failed=1
      fi
      ((pages_tested++))
    done < <(echo "$smoke_pages" | jq -r '.[]' 2>/dev/null)
  fi

  # 3. Story-specific testUrl from PRD
  local test_url
  test_url=$(jq -r --arg id "$story" '.stories[] | select(.id==$id) | .testUrl // empty' "$RALPH_DIR/prd.json" 2>/dev/null)
  if [[ -n "$test_url" ]]; then
    # testUrl can be full URL or just path
    if [[ "$test_url" =~ ^https?:// ]]; then
      if ! _smoke_test_page "" "$test_url" "story"; then
        failed=1
      fi
    else
      if ! _smoke_test_page "$frontend_url" "$test_url" "story"; then
        failed=1
      fi
    fi
    ((pages_tested++))
  fi

  return $failed
}

# Test a single page
# Usage: _smoke_test_page <base_url> <path> <type>
_smoke_test_page() {
  local base_url="$1"
  local path="$2"
  local test_type="$3"

  local url
  if [[ -z "$base_url" ]]; then
    url="$path"
  else
    url="${base_url}${path}"
  fi

  echo -n "    GET $path... "

  local response_file
  response_file=$(mktemp)
  local http_code

  http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
    --max-time "$CURL_TIMEOUT_SECONDS" \
    "$url" 2>/dev/null) || http_code="000"

  # Check response
  if [[ "$http_code" == "000" ]]; then
    print_error "connection failed (is frontend running?)"
    rm -f "$response_file"
    return 1
  elif [[ "$http_code" =~ ^5 ]]; then
    print_error "HTTP $http_code - Server Error"

    # Save for failure context
    {
      echo "Frontend smoke test failed: $url"
      echo "HTTP Status: $http_code"
      echo "Response (first 50 lines):"
      head -50 "$response_file"
    } >> "$RALPH_DIR/last_frontend_failure.log"

    rm -f "$response_file"
    return 1
  elif [[ "$http_code" =~ ^4 ]]; then
    # 404 on a specific page is a real error (unlike API auth)
    if [[ "$http_code" == "404" ]]; then
      print_error "HTTP 404 - Page not found"
      rm -f "$response_file"
      return 1
    fi
    # Other 4xx (401, 403) might be OK - auth required
    print_warning "HTTP $http_code (may need auth)"
    rm -f "$response_file"
    return 0
  else
    # Check for React/Next.js error boundary or crash indicators
    if grep -qi "application error\|something went wrong\|error boundary\|chunk load error" "$response_file" 2>/dev/null; then
      print_error "HTTP $http_code but page shows error"
      {
        echo "Frontend smoke test failed: $url"
        echo "Page loaded but contains error indicators"
        head -50 "$response_file"
      } >> "$RALPH_DIR/last_frontend_failure.log"
      rm -f "$response_file"
      return 1
    fi
    print_success "HTTP $http_code"
    rm -f "$response_file"
    return 0
  fi
}

# Test a single endpoint
# Usage: _smoke_test_endpoint <base_url> <path> <type> [method]
_smoke_test_endpoint() {
  local base_url="$1"
  local path="$2"
  local test_type="$3"
  local method="${4:-GET}"

  local url="${base_url}${path}"
  echo -n "    $method $path... "

  local response_file
  response_file=$(mktemp)
  local http_code

  # Make request with timeout, capture status code
  if [[ "$method" == "GET" ]]; then
    http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
      --max-time "$CURL_TIMEOUT_SECONDS" \
      "$url" 2>/dev/null) || http_code="000"
  else
    # For non-GET, just check endpoint exists (OPTIONS or empty body)
    http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
      --max-time "$CURL_TIMEOUT_SECONDS" \
      -X "$method" \
      -H "Content-Type: application/json" \
      -d '{}' \
      "$url" 2>/dev/null) || http_code="000"
  fi

  # Check response
  if [[ "$http_code" == "000" ]]; then
    print_error "connection failed (is server running?)"
    rm -f "$response_file"
    return 1
  elif [[ "$http_code" =~ ^5 ]]; then
    print_error "HTTP $http_code - Internal Server Error"
    echo ""
    echo "    Response body:"
    head -20 "$response_file" | sed 's/^/      /'

    # Save for failure context
    {
      echo "API smoke test failed: $method $url"
      echo "HTTP Status: $http_code"
      echo "Response:"
      cat "$response_file"
    } >> "$RALPH_DIR/last_api_failure.log"

    rm -f "$response_file"
    return 1
  elif [[ "$http_code" =~ ^4 ]]; then
    # 4xx might be OK (auth required, etc.) - warn but don't fail
    print_warning "HTTP $http_code (may need auth)"
    rm -f "$response_file"
    return 0
  else
    print_success "HTTP $http_code"
    rm -f "$response_file"
    return 0
  fi
}
