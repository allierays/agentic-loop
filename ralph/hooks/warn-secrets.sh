#!/usr/bin/env bash
# warn-secrets.sh - Warn about potential secrets in written code
# Hook: PostToolUse matcher: "Edit|Write"
#
# Mirrors the pre-commit check-secrets patterns for consistency

set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Only check code files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.py|*.json|*.yaml|*.yml|*.env*)
    ;;
  *)
    echo '{"continue": true}'
    exit 0
    ;;
esac

# Get the content that was written
NEW_CONTENT=""
if [[ "$TOOL_NAME" == "Write" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""')
elif [[ "$TOOL_NAME" == "Edit" ]]; then
  NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""')
fi

WARNINGS=""

# AWS Access Key (AKIA followed by 16 alphanumeric chars)
if echo "$NEW_CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  WARNINGS="🚨 SECURITY: Possible AWS Access Key detected! Use environment variables."
fi

# Stripe keys (sk_live_* or sk_test_*)
if echo "$NEW_CONTENT" | grep -qE 'sk_(live|test)_[0-9a-zA-Z]{24,}'; then
  WARNINGS="${WARNINGS}\n🚨 SECURITY: Stripe API key detected! Use environment variables."
fi

# GitHub tokens (ghp_, gho_, ghu_, ghs_, ghr_)
if echo "$NEW_CONTENT" | grep -qE 'gh[pousr]_[A-Za-z0-9_]{36,}'; then
  WARNINGS="${WARNINGS}\n🚨 SECURITY: GitHub token detected! Use environment variables."
fi

# Slack tokens (xoxb-, xoxp-, xoxa-, xoxr-, xoxs-)
if echo "$NEW_CONTENT" | grep -qE 'xox[baprs]-[0-9]{10,}-[0-9a-zA-Z]{24,}'; then
  WARNINGS="${WARNINGS}\n🚨 SECURITY: Slack token detected! Use environment variables."
fi

# SendGrid keys (SG.*)
if echo "$NEW_CONTENT" | grep -qE 'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'; then
  WARNINGS="${WARNINGS}\n🚨 SECURITY: SendGrid API key detected! Use environment variables."
fi

# Private keys
if echo "$NEW_CONTENT" | grep -qE '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
  WARNINGS="${WARNINGS}\n🚨 SECURITY: Private key detected! Never commit private keys."
fi

# Generic API key patterns (api_key = "...", apikey: "...", etc.)
if echo "$NEW_CONTENT" | grep -qiE '(api[_-]?key|api[_-]?secret)\s*[:=]\s*['"'"'"][a-zA-Z0-9_\-]{20,}['"'"'"]'; then
  # Check it's not a placeholder
  if ! echo "$NEW_CONTENT" | grep -qiE '(example|placeholder|your[_-]?key|xxx|test|dummy|fake|sample|demo)'; then
    WARNINGS="${WARNINGS}\n⚠️  Possible hardcoded API key - use environment variables."
  fi
fi

# Generic secrets (password = "...", token = "...", etc.)
if echo "$NEW_CONTENT" | grep -qiE '(password|passwd|pwd|secret|token)\s*[:=]\s*['"'"'"][^'"'"'"]{8,}['"'"'"]'; then
  # Check it's not a placeholder or type annotation
  if ! echo "$NEW_CONTENT" | grep -qiE '(example|placeholder|xxx|test|dummy|type|interface|password:)'; then
    WARNINGS="${WARNINGS}\n⚠️  Possible hardcoded secret - use environment variables."
  fi
fi

# Output warning as additional context (non-blocking)
if [[ -n "$WARNINGS" ]]; then
  jq -n --arg warn "$WARNINGS" '{
    "continue": true,
    "hookSpecificOutput": {
      "additionalContext": $warn
    }
  }'
else
  echo '{"continue": true}'
fi
