#!/bin/bash
# setup-vibe-and-thrive.sh
#
# Sets up vibe-and-thrive for a project:
# - Copies Claude Code skills (/vibe-check, /tdd-feature, /e2e-scaffold)
# - Copies CLAUDE.md template
# - Creates .pre-commit-config.yaml
# - Installs pre-commit hooks
# - Configures Chrome DevTools MCP server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_JSON="$HOME/.claude.json"
VERSION="v1.0.0"  # Update this when releasing new versions

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [PROJECT_PATH]

Sets up vibe-and-thrive for better AI-assisted coding.

Arguments:
  PROJECT_PATH    Path to your project (default: current directory)

Options:
  --mcp-only      Only configure MCP servers (no project setup)
  --no-mcp        Skip MCP server configuration
  --no-hooks      Skip pre-commit hooks setup
  --help          Show this help message

Examples:
  $(basename "$0") ~/Sites/my-project    # Full setup for a project
  $(basename "$0") --mcp-only            # Just configure MCP servers
  $(basename "$0") .                      # Setup current directory

EOF
}

setup_mcp() {
    print_step "Configuring Chrome DevTools MCP server..."

    # Check if Claude CLI is installed
    if ! command -v claude &> /dev/null; then
        print_warning "Claude CLI not found. Install it first: npm install -g @anthropic-ai/claude-code"
        print_warning "Skipping MCP configuration."
        return 1
    fi

    # Create ~/.claude.json if it doesn't exist
    if [ ! -f "$CLAUDE_JSON" ]; then
        echo '{}' > "$CLAUDE_JSON"
        print_success "Created $CLAUDE_JSON"
    fi

    # Check if jq is available for JSON manipulation
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found. Please install jq and run again, or manually add MCP config."
        print_warning "brew install jq (macOS) or apt install jq (Linux)"
        echo ""
        echo "Manual config - add this to $CLAUDE_JSON:"
        cat << 'MCPEOF'
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools@latest"]
    }
  }
}
MCPEOF
        return 1
    fi

    # Add Chrome DevTools MCP server to config
    local tmp_file
    tmp_file=$(mktemp) || {
        print_error "Failed to create temporary file"
        return 1
    }
    if jq '.mcpServers["chrome-devtools"] = {
        "command": "npx",
        "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools@latest"]
    }' "$CLAUDE_JSON" > "$tmp_file"; then
        mv "$tmp_file" "$CLAUDE_JSON"
    else
        rm -f "$tmp_file"
        print_error "Failed to update MCP configuration"
        return 1
    fi

    print_success "Added Chrome DevTools MCP server to $CLAUDE_JSON"
    echo "    This lets Claude interact with Chrome for E2E testing."
}

setup_project() {
    local project_path="$1"

    # Resolve to absolute path
    project_path="$(cd "$project_path" 2>/dev/null && pwd)" || {
        print_error "Directory not found: $1"
        exit 1
    }

    print_step "Setting up vibe-and-thrive for: $project_path"
    echo ""

    # Copy Claude skills
    print_step "Copying Claude Code skills..."
    if [ -d "$project_path/.claude/commands" ]; then
        print_warning ".claude/commands already exists. Merging..."
    fi
    mkdir -p "$project_path/.claude/commands"
    cp -r "$SCRIPT_DIR/.claude/commands/"* "$project_path/.claude/commands/"
    print_success "Copied 10 Claude skills:"
    echo "    /prd, /tdd-feature, /e2e-scaffold, /vibe-check"
    echo "    /explain, /review, /refactor"
    echo "    /add-tests, /fix-types, /security-check"

    # Copy CLAUDE.md template
    print_step "Setting up CLAUDE.md..."
    if [ -f "$project_path/CLAUDE.md" ]; then
        print_warning "CLAUDE.md already exists. Skipping (won't overwrite)."
        print_warning "Check CLAUDE.md.template for new patterns you might want to add."
    else
        cp "$SCRIPT_DIR/CLAUDE.md.template" "$project_path/CLAUDE.md"
        print_success "Created CLAUDE.md from template"
        echo "    Edit this file to customize for your project."
    fi

    echo ""
}

setup_precommit() {
    local project_path="$1"

    print_step "Setting up pre-commit hooks..."

    # Check if pre-commit is installed
    if ! command -v pre-commit &> /dev/null; then
        print_warning "pre-commit not found. Installing..."
        if command -v brew &> /dev/null; then
            brew install pre-commit
        elif command -v pip &> /dev/null; then
            pip install pre-commit
        else
            print_error "Could not install pre-commit. Please install manually:"
            echo "    brew install pre-commit  OR  pip install pre-commit"
            return 1
        fi
        print_success "Installed pre-commit"
    fi

    # Create .pre-commit-config.yaml if it doesn't exist
    if [ -f "$project_path/.pre-commit-config.yaml" ]; then
        print_warning ".pre-commit-config.yaml already exists."
        echo "    Add vibe-and-thrive hooks manually if needed. See README.md"
    else
        cat > "$project_path/.pre-commit-config.yaml" << PRECOMMITEOF
repos:
  - repo: https://github.com/allthriveai/vibe-and-thrive
    rev: $VERSION
    hooks:
      # Run all checks (recommended)
      - id: vibe-check

      # Or use individual checks:
      # - id: vibe-check-security  # Security only (blocking)
      # - id: vibe-check-quality   # Quality only (non-blocking)
      # - id: check-secrets        # Hardcoded secrets
      # - id: check-hardcoded-urls # Localhost URLs
      # - id: check-debug          # Debug statements
      # - id: check-empty-catch    # Empty catch blocks
      # - id: check-any-types      # TypeScript any usage
      # - id: check-snake-case     # snake_case in TS
PRECOMMITEOF
        print_success "Created .pre-commit-config.yaml"
    fi

    # Install hooks
    print_step "Installing pre-commit hooks..."
    (cd "$project_path" && pre-commit install)
    print_success "Pre-commit hooks installed"

    echo ""
}

# Parse arguments
MCP_ONLY=false
NO_MCP=false
NO_HOOKS=false
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --mcp-only)
            MCP_ONLY=true
            shift
            ;;
        --no-mcp)
            NO_MCP=true
            shift
            ;;
        --no-hooks)
            NO_HOOKS=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        -*)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            PROJECT_PATH="$1"
            shift
            ;;
    esac
done

# Main execution
echo ""
echo "┌─────────────────────────────────────┐"
echo "│     vibe-and-thrive setup           │"
echo "│     Better AI-assisted coding       │"
echo "└─────────────────────────────────────┘"
echo ""

if [ "$MCP_ONLY" = true ]; then
    setup_mcp
else
    # Default to current directory if no path provided
    if [ -z "$PROJECT_PATH" ]; then
        PROJECT_PATH="."
    fi

    setup_project "$PROJECT_PATH"

    if [ "$NO_HOOKS" = false ]; then
        setup_precommit "$PROJECT_PATH"
    fi

    if [ "$NO_MCP" = false ]; then
        setup_mcp
    fi
fi

echo ""
echo "┌─────────────────────────────────────┐"
echo "│           Setup complete!           │"
echo "└─────────────────────────────────────┘"
echo ""
echo "Available Claude Code commands:"
echo "  /prd             - Generate PRD via questions"
echo "  /tdd-feature     - Build feature with TDD"
echo "  /e2e-scaffold    - Generate E2E test structure"
echo "  /vibe-check      - Run code quality audit"
echo "  /explain         - Explain code line by line"
echo "  /review          - Review code for issues"
echo "  /refactor        - Guided refactoring"
echo "  /add-tests       - Add tests to existing code"
echo "  /fix-types       - Fix TypeScript without any"
echo "  /security-check  - Check for vulnerabilities"
echo ""
echo "Pre-commit hooks will run automatically on each commit."
echo ""
echo "Documentation:"
echo "  docs/BAD-PATTERNS.md    - Common AI coding mistakes"
echo "  docs/PROMPTING-GUIDE.md - How to prompt AI effectively"
echo "  docs/WORKFLOW.md        - The TDD workflow"
echo "  CHEATSHEET.md           - Quick reference"
echo ""
