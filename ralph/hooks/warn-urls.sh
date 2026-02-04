#!/usr/bin/env bash
# shellcheck shell=bash
# warn-urls.sh - Warn about hardcoded URLs in written code
# Hook: PostToolUse matcher: "Edit|Write"
#
# Mirrors the pre-commit check-hardcoded-urls patterns for consistency

source "$(dirname "$0")/common.sh"

SAFE_DOMAINS="cdn.jsdelivr.net|cdnjs.cloudflare.com|unpkg.com|fonts.googleapis.com|fonts.gstatic.com|api.github.com|raw.githubusercontent.com|registry.npmjs.org|schema.org|www.w3.org|example.com|example.org"

_check_urls() {
  # Check for localhost URLs
  if echo "$NEW_CONTENT" | grep -qE 'https?://localhost(:[0-9]+)?'; then
    if ! echo "$NEW_CONTENT" | grep -qE '(\|\||\?\?|default|fallback).*localhost'; then
      WARNINGS="⚠️  Hardcoded localhost URL detected - use environment variable (e.g., process.env.API_URL)"
    fi
  fi

  # Check for 127.0.0.1 URLs
  if echo "$NEW_CONTENT" | grep -qE 'https?://127\.0\.0\.1(:[0-9]+)?'; then
    if ! echo "$NEW_CONTENT" | grep -qE '(\|\||\?\?|default|fallback).*127\.0\.0\.1'; then
      WARNINGS="${WARNINGS}${WARNINGS:+\\n}⚠️  Hardcoded 127.0.0.1 URL detected - use environment variable"
    fi
  fi

  # Look for https:// URLs that aren't safe domains
  local prod_urls
  prod_urls=$(echo "$NEW_CONTENT" | grep -oE 'https://[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | grep -vE "$SAFE_DOMAINS" || true)

  if [[ -n "$prod_urls" ]]; then
    prod_urls=$(echo "$prod_urls" | grep -v -E '(example|placeholder|test|mock)' || true)
    if [[ -n "$prod_urls" ]]; then
      local first_url
      first_url=$(echo "$prod_urls" | head -1)
      WARNINGS="${WARNINGS}${WARNINGS:+\\n}⚠️  Hardcoded URL ($first_url) - consider using environment variable"
    fi
  fi
}

run_warn_hook "ts,tsx,js,jsx,py" _check_urls --skip-tests
