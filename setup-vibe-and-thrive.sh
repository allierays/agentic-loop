#!/bin/bash
# setup-vibe-and-thrive.sh
#
# Sets up vibe-and-thrive for a project:
# - Copies Claude Code commands (/idea, /vibe-check, /review, etc.)
# - Copies CLAUDE.md template
# - Initializes Ralph (.ralph/, PROMPT.md)
# - Creates .pre-commit-config.yaml
# - Installs pre-commit hooks
# - Configures Chrome DevTools MCP server

set -euo pipefail

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

install_jq() {
    print_step "Installing jq..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &>/dev/null; then
            brew install jq
            print_success "Installed jq via Homebrew"
            return 0
        else
            print_error "Homebrew not found. Install jq manually: brew install jq"
            return 1
        fi
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y jq
        print_success "Installed jq via apt"
        return 0
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y jq
        print_success "Installed jq via dnf"
        return 0
    elif command -v yum &>/dev/null; then
        sudo yum install -y jq
        print_success "Installed jq via yum"
        return 0
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm jq
        print_success "Installed jq via pacman"
        return 0
    elif command -v apk &>/dev/null; then
        sudo apk add jq
        print_success "Installed jq via apk"
        return 0
    else
        print_error "Could not detect package manager. Install jq manually."
        return 1
    fi
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [PROJECT_PATH]

Sets up vibe-and-thrive for better AI-assisted coding.

Arguments:
  PROJECT_PATH    Path to your project (default: current directory)

Options:
  --quick         Skip intro banner (for postinstall)
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

    # Check if jq is available, install if missing
    if ! command -v jq &> /dev/null; then
        install_jq || {
            print_warning "Could not install jq. Manual config required."
            echo ""
            echo "Add this to $CLAUDE_JSON:"
            cat << 'MCPEOF'
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools@0.0.5"]
    }
  }
}
MCPEOF
            return 1
        }
    fi

    # Add Chrome DevTools MCP server to config
    local tmp_file
    tmp_file=$(mktemp) || {
        print_error "Failed to create temporary file"
        return 1
    }
    if jq '.mcpServers["chrome-devtools"] = {
        "command": "npx",
        "args": ["-y", "@anthropic-ai/mcp-server-chrome-devtools@0.0.5"]
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
    print_success "Copied Claude commands:"
    echo "    /idea       - Brainstorm to PRD workflow"
    echo "    /tour       - Interactive tour of vibe-and-thrive"
    echo "    /vibe-check - Run code quality audit"
    echo "    /review     - Code review (includes security)"
    echo "    /explain    - Explain code line by line"
    echo "    /styleguide - Generate HTML/React styleguide"

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

    # Initialize Ralph
    print_step "Initializing Ralph..."
    (cd "$project_path" && ralph init 2>/dev/null) || {
        # ralph init might not be in PATH yet, do it manually
        mkdir -p "$project_path/.ralph/archive" "$project_path/.ralph/screenshots"
        if [ ! -f "$project_path/.ralph/config.json" ]; then
            cp "$SCRIPT_DIR/templates/config/minimal.json" "$project_path/.ralph/config.json" 2>/dev/null || \
            echo '{"maxSessionSeconds": 600, "autoCommit": true}' > "$project_path/.ralph/config.json"
        fi
        echo '{"signs": []}' > "$project_path/.ralph/signs.json"
        if [ ! -f "$project_path/PROMPT.md" ]; then
            cp "$SCRIPT_DIR/templates/PROMPT.md" "$project_path/PROMPT.md" 2>/dev/null || \
            cat > "$project_path/PROMPT.md" << 'PROMPTEOF'
# System Prompt for Ralph

You are an AI developer working on this project. Complete the current story by:

1. Reading the acceptance criteria carefully
2. Writing code to satisfy each criterion
3. Running the test steps to verify

Keep changes minimal and focused. Commit when tests pass.
PROMPTEOF
        fi
    }
    print_success "Ralph initialized"
    echo "    .ralph/ directory created"
    echo "    PROMPT.md created (customize for your project)"

    echo ""
}

setup_claude_hooks() {
    local project_path="$1"

    print_step "Setting up Claude Code hooks..."

    # Check if jq is available, install if missing
    if ! command -v jq &> /dev/null; then
        install_jq || {
            print_warning "Could not install jq. Claude Code hooks not configured."
            print_warning "Install jq and run: npx ralph hooks"
            return 1
        }
    fi

    # Run the hooks installer
    if [ -f "$SCRIPT_DIR/ralph/hooks/install.sh" ]; then
        "$SCRIPT_DIR/ralph/hooks/install.sh" --force
    else
        print_warning "Hooks installer not found. Run: npx ralph hooks"
        return 1
    fi
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
QUICK=false
PROJECT_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --quick)
            QUICK=true
            shift
            ;;
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
if [ "$QUICK" = false ]; then
    echo ""
    echo "┌─────────────────────────────────────┐"
    echo "│     vibe-and-thrive setup           │"
    echo "│     Better AI-assisted coding       │"
    echo "└─────────────────────────────────────┘"
    echo ""
fi

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

    # Always set up Claude Code hooks (real-time warnings)
    setup_claude_hooks "$PROJECT_PATH"
fi

if [ "$QUICK" = true ]; then
    echo ""
    print_success "vibe-and-thrive ready! Run /vibe-help in Claude Code for commands."
    echo ""
else
    echo ""
    echo "┌─────────────────────────────────────┐"
    echo "│           Setup complete!           │"
    echo "└─────────────────────────────────────┘"
    echo ""
    echo "The workflow:"
    echo "  /idea        - Brainstorm → PRD → Ready for Ralph"
    echo "  ralph run    - Autonomous coding until tests pass"
    echo ""
    echo "Commands:"
    echo "  /tour        - Interactive tour of vibe-and-thrive"
    echo "  /my-dna      - Set up your personal style preferences"
    echo "  /vibe-check  - Run code quality audit"
    echo "  /review      - Code review (includes security)"
    echo "  /explain     - Explain code line by line"
    echo "  /styleguide  - Generate HTML/React styleguide"
    echo "  /vibe-help   - Quick reference cheatsheet"
    echo ""
    echo "Tip: Run /my-dna to teach Claude your preferred working style."
    echo ""
    echo "Pre-commit hooks will run automatically on each commit."
    echo ""
fi
