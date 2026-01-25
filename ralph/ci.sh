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

  # Copy workflow templates
  local template_dir="$RALPH_TEMPLATES/github/workflows"

  if [[ ! -d "$template_dir" ]]; then
    print_error "Workflow templates not found at $template_dir"
    return 1
  fi

  # Install PR workflow
  if [[ -f ".github/workflows/pr.yml" ]]; then
    echo "  PR workflow already exists, skipping..."
  else
    cp "$template_dir/pr.yml" .github/workflows/pr.yml
    print_success "Created .github/workflows/pr.yml (fast lint checks)"
  fi

  # Install nightly workflow
  if [[ -f ".github/workflows/nightly.yml" ]]; then
    echo "  Nightly workflow already exists, skipping..."
  else
    cp "$template_dir/nightly.yml" .github/workflows/nightly.yml
    print_success "Created .github/workflows/nightly.yml (full test suite)"
  fi

  echo ""
  echo "Workflows installed:"
  echo ""
  echo "  📋 PR Check (.github/workflows/pr.yml)"
  echo "     Runs on: Pull requests to main/master"
  echo "     Checks: Lint, TypeScript, Build"
  echo "     Speed: Fast (~1-2 min)"
  echo ""
  echo "  🌙 Nightly Tests (.github/workflows/nightly.yml)"
  echo "     Runs on: Daily at 3am UTC + manual trigger"
  echo "     Checks: Full test suite + PRD testSteps + Coverage"
  echo "     Speed: Comprehensive (~5-10 min)"
  echo ""

  # Check if we need to customize for monorepo
  local backend_dir frontend_dir
  backend_dir=$(get_config '.directories.backend' "")
  frontend_dir=$(get_config '.directories.frontend' "")

  if [[ -n "$backend_dir" ]] || [[ -n "$frontend_dir" ]]; then
    print_warning "Monorepo detected. You may need to customize workflow paths."
    echo ""
    echo "  Edit .github/workflows/*.yml to add:"
    [[ -n "$backend_dir" ]] && echo "    - working-directory: $backend_dir"
    [[ -n "$frontend_dir" ]] && echo "    - working-directory: $frontend_dir"
    echo ""
  fi

  # Remind about secrets
  echo "Next steps:"
  echo "  1. Review and customize the workflows if needed"
  echo "  2. Commit and push: git add .github && git commit -m 'ci: Add GitHub Actions workflows'"
  echo "  3. Set up any required secrets in GitHub repo settings"
  echo ""

  return 0
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
