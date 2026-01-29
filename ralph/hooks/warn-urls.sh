#!/usr/bin/env bash
# shellcheck shell=bash
# warn-urls.sh - Warn about hardcoded URLs in written code
# Hook: PostToolUse matcher: "Edit|Write"
#
# Mirrors the pre-commit check-hardcoded-urls patterns for consistency

source "$(dirname "$0")/common.sh"

parse_hook_input

# Skip test files
if is_test_file; then
  hook_allow
  exit 0
fi

# Only check code files
if ! is_code_file "ts,tsx,js,jsx,py"; then
  hook_allow
  exit 0
fi

WARNINGS=""

# Check for localhost URLs
if echo "$NEW_CONTENT" | grep -qE 'https?://localhost(:[0-9]+)?'; then
  # Skip if it's in a fallback pattern (|| or ?? or default)
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

# Check for hardcoded production-looking URLs (skip CDNs and common safe domains)
SAFE_DOMAINS="cdn.jsdelivr.net|cdnjs.cloudflare.com|unpkg.com|fonts.googleapis.com|fonts.gstatic.com|api.github.com|raw.githubusercontent.com|registry.npmjs.org|schema.org|www.w3.org|example.com|example.org"

# Look for https:// URLs that aren't safe domains
PROD_URLS=$(echo "$NEW_CONTENT" | grep -oE 'https://[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | grep -vE "$SAFE_DOMAINS" || true)

if [[ -n "$PROD_URLS" ]]; then
  # Skip if they look like example/placeholder URLs
  PROD_URLS=$(echo "$PROD_URLS" | grep -v -E '(example|placeholder|test|mock)' || true)
  if [[ -n "$PROD_URLS" ]]; then
    FIRST_URL=$(echo "$PROD_URLS" | head -1)
    WARNINGS="${WARNINGS}${WARNINGS:+\\n}⚠️  Hardcoded URL ($FIRST_URL) - consider using environment variable"
  fi
fi

# Output warning or allow
if [[ -n "$WARNINGS" ]]; then
  hook_warn "$WARNINGS"
else
  hook_allow
fi
