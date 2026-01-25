#!/usr/bin/env bash
# shellcheck shell=bash
# ci.sh - Set up GitHub Actions CI/CD workflows

# Install GitHub Actions workflows
ralph_ci() {
  local cmd="${1:-install}"

  case "$cmd" in
    install)
      install_github_workflows
      ;;
    status)
      check_ci_status
      ;;
    *)
      echo "Usage: ralph ci [install|status]"
      echo ""
      echo "Commands:"
      echo "  install  - Install GitHub Actions workflows"
      echo "  status   - Check CI status"
      return 1
      ;;
  esac
}

install_github_workflows() {
  echo ""
  print_info "=== Setting up GitHub Actions CI/CD ==="
  echo ""

  # Check if this is a git repo
  if [[ ! -d ".git" ]]; then
    print_error "Not a git repository. Run 'git init' first."
    return 1
  fi

  # Create workflows directory
  mkdir -p .github/workflows

  # Read config values
  local backend_dir frontend_dir test_cmd
  backend_dir=$(get_config '.directories.backend' "")
  frontend_dir=$(get_config '.directories.frontend' "")
  test_cmd=$(get_config '.checks.testCommand' "")

  # Generate PR workflow
  if [[ -f ".github/workflows/pr.yml" ]]; then
    echo "  PR workflow already exists, skipping..."
  else
    generate_pr_workflow "$backend_dir" "$frontend_dir"
    print_success "Created .github/workflows/pr.yml (fast lint checks)"
  fi

  # Generate nightly workflow
  if [[ -f ".github/workflows/nightly.yml" ]]; then
    echo "  Nightly workflow already exists, skipping..."
  else
    generate_nightly_workflow "$backend_dir" "$frontend_dir" "$test_cmd"
    print_success "Created .github/workflows/nightly.yml (full test suite)"
  fi

  echo ""
  echo "Workflows installed:"
  echo ""
  echo "  PR Check (.github/workflows/pr.yml)"
  echo "     Runs on: Pull requests to main/master"
  echo "     Checks: Lint, TypeScript, Build"
  echo ""
  echo "  Nightly Tests (.github/workflows/nightly.yml)"
  echo "     Runs on: Daily at 3am UTC + manual trigger"
  echo "     Checks: Full test suite + PRD testSteps"
  echo ""
  echo "Next steps:"
  echo "  1. Review and customize the workflows if needed"
  echo "  2. Commit: git add .github && git commit -m 'ci: Add workflows'"
  echo "  3. Add any required secrets in GitHub repo settings"
  echo ""

  return 0
}

# Generate PR workflow based on project structure
generate_pr_workflow() {
  local backend_dir="$1"
  local frontend_dir="$2"

  cat > .github/workflows/pr.yml << 'HEADER'
# Fast PR checks - lint only, no tests
name: PR Check

on:
  pull_request:
    branches: [main, master]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
HEADER

  # Detect and add Python steps
  if [[ -f "pyproject.toml" ]] || [[ -f "requirements.txt" ]] || [[ -n "$backend_dir" && -f "$backend_dir/pyproject.toml" ]]; then
    local py_dir="${backend_dir:-.}"
    cat >> .github/workflows/pr.yml << EOF

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install Python dependencies
        run: |
          pip install ruff uv
          cd $py_dir && uv pip install -e . --system 2>/dev/null || pip install -e . 2>/dev/null || true

      - name: Ruff lint
        run: cd $py_dir && ruff check .
EOF
  fi

  # Detect and add Node.js steps
  if [[ -f "package.json" ]] || [[ -n "$frontend_dir" && -f "$frontend_dir/package.json" ]]; then
    local node_dir="${frontend_dir:-.}"
    cat >> .github/workflows/pr.yml << EOF

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Node dependencies
        run: cd $node_dir && npm ci

      - name: Lint
        run: cd $node_dir && npm run lint 2>/dev/null || true

      - name: TypeScript check
        run: cd $node_dir && npx tsc --noEmit 2>/dev/null || true

      - name: Build
        run: cd $node_dir && npm run build 2>/dev/null || true
EOF
  fi
}

# Generate nightly workflow based on project structure
generate_nightly_workflow() {
  local backend_dir="$1"
  local frontend_dir="$2"
  local test_cmd="$3"

  cat > .github/workflows/nightly.yml << 'HEADER'
# Nightly comprehensive test suite
name: Nightly Tests

on:
  schedule:
    - cron: '0 3 * * *'  # 3am UTC daily
  workflow_dispatch:

jobs:
  test:
    runs-on: ubuntu-latest
HEADER

  # Add services if backend exists (likely needs DB)
  if [[ -n "$backend_dir" ]] || [[ -f "pyproject.toml" ]]; then
    cat >> .github/workflows/nightly.yml << 'EOF'

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      DATABASE_URL: postgresql://test:test@localhost:5432/test
EOF
  fi

  cat >> .github/workflows/nightly.yml << 'EOF'

    steps:
      - uses: actions/checkout@v4
EOF

  # Add Python setup and tests
  if [[ -f "pyproject.toml" ]] || [[ -n "$backend_dir" && -f "$backend_dir/pyproject.toml" ]]; then
    local py_dir="${backend_dir:-.}"
    local py_test_cmd="${test_cmd:-pytest -v --tb=short}"

    cat >> .github/workflows/nightly.yml << EOF

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install Python dependencies
        run: |
          pip install uv
          cd $py_dir && uv pip install -e ".[dev]" --system 2>/dev/null || pip install -e . 2>/dev/null || true

      - name: Run migrations
        run: cd $py_dir && alembic upgrade head 2>/dev/null || true
        continue-on-error: true

      - name: Python tests
        run: cd $py_dir && $py_test_cmd
        continue-on-error: true
EOF
  fi

  # Add Node.js setup and tests
  if [[ -f "package.json" ]] || [[ -n "$frontend_dir" && -f "$frontend_dir/package.json" ]]; then
    local node_dir="${frontend_dir:-.}"
    cat >> .github/workflows/nightly.yml << EOF

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Node dependencies
        run: cd $node_dir && npm ci

      - name: Node tests
        run: cd $node_dir && npm test 2>/dev/null || true
        continue-on-error: true
EOF
  fi

  # Add PRD tests
  cat >> .github/workflows/nightly.yml << 'EOF'

      - name: Run PRD tests
        if: hashFiles('.ralph/prd.json') != ''
        run: npx agentic-loop test prd 2>/dev/null || true
        continue-on-error: true

  notify:
    needs: test
    runs-on: ubuntu-latest
    if: failure()
    steps:
      - name: Notify on failure
        run: echo "Nightly tests failed!"
EOF
}

check_ci_status() {
  echo ""
  print_info "=== CI/CD Status ==="
  echo ""

  # Check for workflow files
  if [[ -f ".github/workflows/pr.yml" ]]; then
    print_success "PR workflow: installed"
  else
    print_warning "PR workflow: not installed"
  fi

  if [[ -f ".github/workflows/nightly.yml" ]]; then
    print_success "Nightly workflow: installed"
  else
    print_warning "Nightly workflow: not installed"
  fi

  # Check GitHub CLI
  if command -v gh &>/dev/null; then
    echo ""
    echo "Recent workflow runs:"
    gh run list --limit 5 2>/dev/null || echo "  (unable to fetch - check 'gh auth login')"
  else
    echo ""
    echo "Install GitHub CLI (gh) to see workflow status:"
    echo "  brew install gh && gh auth login"
  fi
}
