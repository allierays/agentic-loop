#!/usr/bin/env bash
# shellcheck shell=bash
#
# Example custom PRD check for Ralph
#
# Place in: .ralph/checks/prd/  (project) or ~/.config/ralph/checks/prd/ (global)
# Must be executable: chmod +x check-example.sh
#
# Interface:
#   stdin  = story JSON object
#   $1     = story ID
#   $2     = PRD file path
#   stdout = issue descriptions, one per line (empty = pass)
#
# Disable: {"checks": {"custom": {"check-example": false}}}

# story_id="$1"  # available if you need the story ID
# prd_file="$2"  # available if you need full PRD context
story_json=$(cat)

# Example: require all stories to have a description field
has_description=$(echo "$story_json" | jq -r '.description // empty')
if [[ -z "$has_description" ]]; then
  echo "missing description field"
fi
