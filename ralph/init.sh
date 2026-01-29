#!/usr/bin/env bash
# shellcheck shell=bash
# init.sh - Initialize ralph in a project

ralph_init() {
  # Check if already initialized (progress.txt is created by full init)
  if [[ -f "$RALPH_DIR/progress.txt" ]]; then
    echo "Ralph already initialized in this directory."
    echo "Use 'ralph run' to start the loop or 'ralph status' to check status."
    return 0
  fi

  echo "Initializing ralph..."

  # Create directory structure
  mkdir -p "$RALPH_DIR/archive" "$RALPH_DIR/screenshots"

  # Detect project type and generate appropriate config
  local project_type
  project_type=$(detect_project_type)
  echo "Detected project type: $project_type"

  # Copy config template based on project type (only if missing)
  if [[ ! -f "$RALPH_DIR/config.json" ]]; then
    local config_template="$RALPH_TEMPLATES/config/${project_type}.json"
    if [[ -f "$config_template" ]]; then
      cp "$config_template" "$RALPH_DIR/config.json"
    else
      # Fall back to minimal config
      cp "$RALPH_TEMPLATES/config/minimal.json" "$RALPH_DIR/config.json"
    fi
  fi

  # Create signs with defaults (only if missing)
  if [[ ! -f "$RALPH_DIR/signs.json" ]]; then
    if [[ -f "$RALPH_TEMPLATES/signs.json" ]]; then
      cp "$RALPH_TEMPLATES/signs.json" "$RALPH_DIR/signs.json"
    else
      echo '{"signs": []}' > "$RALPH_DIR/signs.json"
    fi
  fi

  # Create progress log (only if missing)
  if [[ ! -f "$RALPH_DIR/progress.txt" ]]; then
    local timestamp
    timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    echo "[$timestamp] INIT Ralph initialized" > "$RALPH_DIR/progress.txt"
  fi

  # Copy PROMPT.md template if it doesn't exist in project
  if [[ ! -f "PROMPT.md" ]]; then
    cp "$RALPH_TEMPLATES/PROMPT.md" "PROMPT.md"
    echo "Created PROMPT.md template"
  fi

  # Auto-detect and configure project-specific settings
  echo ""
  echo "Auto-configuring project settings..."
  auto_configure_project

  print_success "Ralph initialized!"
  echo ""

  # Prompt for test credentials
  configure_test_auth

  echo ""
  echo "Next steps:"
  echo "  1. Review .ralph/config.json (test credentials, checks, etc.)"
  echo "  2. Generate PRD:"
  echo "     - Thorough: /idea 'feature description' (brainstorm + architecture + scalability)"
  echo "     - Quick:    ralph prd 'feature description' (basic PRD)"
  echo "  3. Start loop: ralph run"
}

# Configure test authentication credentials
configure_test_auth() {
  # Skip if not running in an interactive terminal
  if [[ ! -t 0 ]]; then
    return 0
  fi

  echo ""
  print_info "=== Test Authentication Setup ==="
  echo ""
  echo "Ralph needs test credentials to verify authenticated endpoints."
  echo "(You can skip this and edit .ralph/config.json later)"
  echo ""

  # Ask if they want to configure auth
  read -p "Configure test credentials now? [y/N] " -n 1 -r
  echo ""

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Skipped. Edit .ralph/config.json to add credentials later."
    return 0
  fi

  echo ""
  read -p "Test user email/username: " test_user
  read -s -p "Test user password: " test_password
  echo ""

  if [[ -z "$test_user" || -z "$test_password" ]]; then
    print_warning "Credentials not provided."
    echo "  Options to add them later:"
    echo "    1. Edit .ralph/config.json (stored in plain text)"
    echo "    2. Set RALPH_TEST_USER and RALPH_TEST_PASSWORD env vars (recommended)"
    return 0
  fi

  # Update config.json with credentials
  local config="$RALPH_DIR/config.json"
  if [[ -f "$config" ]]; then
    local tmpfile
    tmpfile=$(mktemp)
    if jq --arg user "$test_user" --arg pass "$test_password" \
       '.auth.testUser = $user | .auth.testPassword = $pass' \
       "$config" > "$tmpfile" 2>/dev/null; then
      mv "$tmpfile" "$config"
      print_success "Test credentials saved to .ralph/config.json"
      print_warning "Note: Credentials stored in plain text. Consider using env vars instead:"
      echo "    export RALPH_TEST_USER='$test_user'"
      echo "    export RALPH_TEST_PASSWORD='****'"
    else
      rm -f "$tmpfile"
      print_warning "Failed to update config. Edit .ralph/config.json manually."
    fi
  fi
}

# Detect the type of project based on files present
detect_project_type() {
  local project_type="minimal"

  # Check for fullstack patterns first (more specific)
  if [[ -d "frontend" && -d "core" ]]; then
    project_type="fullstack"
  elif [[ -d "frontend" && -d "backend" ]]; then
    project_type="fullstack"
  elif [[ -d "apps" ]]; then
    project_type="fullstack"  # Monorepo
  # Then check for single-language projects
  elif [[ -f "Cargo.toml" ]]; then
    project_type="rust"
  elif [[ -f "go.mod" ]]; then
    project_type="go"
  elif [[ -f "mix.exs" ]]; then
    project_type="elixir"
  # Check for Python framework variants (more specific first)
  elif [[ -f "pyproject.toml" ]]; then
    # FastMCP detection (check for fastmcp in any quote style)
    if grep -qiE "(fastmcp|\"fastmcp\"|'fastmcp')" pyproject.toml 2>/dev/null; then
      project_type="fastmcp"
    # Django detection
    elif grep -qiE "(django|\"django\"|'django')" pyproject.toml 2>/dev/null || [[ -f "manage.py" ]]; then
      project_type="django"
    # FastAPI detection
    elif grep -qiE "(fastapi|\"fastapi\"|'fastapi')" pyproject.toml 2>/dev/null; then
      project_type="fastapi"
    else
      project_type="python"
    fi
  elif [[ -f "requirements.txt" || -f "setup.py" ]]; then
    # Check requirements.txt for frameworks
    if [[ -f "requirements.txt" ]]; then
      if grep -qi 'fastmcp' requirements.txt 2>/dev/null; then
        project_type="fastmcp"
      elif grep -qi 'django' requirements.txt 2>/dev/null || [[ -f "manage.py" ]]; then
        project_type="django"
      elif grep -qi 'fastapi' requirements.txt 2>/dev/null; then
        project_type="fastapi"
      else
        project_type="python"
      fi
    else
      project_type="python"
    fi
  elif [[ -f "package.json" ]]; then
    project_type="node"
  fi

  echo "$project_type"
}

# Auto-detect and configure project-specific settings
auto_configure_project() {
  local config="$RALPH_DIR/config.json"
  [[ ! -f "$config" ]] && return 0

  local updated=false
  local tmpfile
  tmpfile=$(mktemp)
  cp "$config" "$tmpfile"

  # 1. Detect Playwright test directory
  local playwright_dir=""
  for dir in "tests/e2e" "e2e" "test/e2e" \
             "apps/web/tests/e2e" "apps/frontend/tests/e2e" \
             "frontend/tests/e2e" "frontend/e2e" \
             "packages/web/tests/e2e"; do
    if [[ -d "$dir" ]]; then
      playwright_dir="$dir"
      break
    fi
  done

  if [[ -n "$playwright_dir" ]]; then
    if jq -e '.playwright.testDir' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg dir "$playwright_dir" '.playwright.testDir = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected playwright.testDir: $playwright_dir"
      updated=true
    fi
  fi

  # 2. Detect testUrlBase by parsing actual config files for port values
  local base_url=""
  local web_port=""

  # Priority 1: docker-compose.yml - parse actual port mappings
  for compose_file in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
    if [[ -f "$compose_file" && -z "$web_port" ]]; then
      # Extract port from web/frontend service: "5173:5173" -> 5173
      web_port=$(grep -A 20 -E '^\s*(web|frontend|client|ui):' "$compose_file" 2>/dev/null | \
                 grep -E '^\s*-\s*"?[0-9]+:[0-9]+"?' | head -1 | \
                 grep -oE '[0-9]+:' | head -1 | tr -d ':' || true)
    fi
  done

  # Priority 2: Vite config - parse server.port
  if [[ -z "$web_port" ]]; then
    for vite_config in "vite.config.ts" "vite.config.js" "apps/web/vite.config.ts" "apps/web/vite.config.js" \
                       "apps/frontend/vite.config.ts" "frontend/vite.config.ts"; do
      if [[ -f "$vite_config" ]]; then
        # Look for port: 3000 or port: '3000'
        web_port=$(grep -E 'port\s*[=:]\s*[0-9]+' "$vite_config" 2>/dev/null | grep -oE '[0-9]{4}' | head -1 || true)
        [[ -z "$web_port" ]] && web_port="5173"  # Vite's documented default
        break
      fi
    done
  fi

  # Priority 3: Hugo config - parse server.port or use documented default
  if [[ -z "$web_port" ]]; then
    for hugo_config in "hugo.toml" "hugo.yaml" "hugo.json" "config.toml"; do
      if [[ -f "$hugo_config" ]] && [[ -d "content" || -d "layouts" || -d "themes" ]]; then
        web_port=$(grep -E 'port\s*=' "$hugo_config" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
        [[ -z "$web_port" ]] && web_port="1313"  # Hugo's documented default
        break
      fi
    done
  fi

  # Priority 4: Next.js - check package.json dev script for -p flag
  if [[ -z "$web_port" ]]; then
    for next_config in "next.config.js" "next.config.ts" "next.config.mjs" \
                       "apps/web/next.config.js" "apps/web/next.config.mjs"; do
      if [[ -f "$next_config" ]]; then
        # Check if package.json has custom port: "dev": "next dev -p 4000"
        local pkg_dir
        pkg_dir=$(dirname "$next_config")
        if [[ -f "$pkg_dir/package.json" ]]; then
          web_port=$(grep -E '"dev".*-p\s*[0-9]+' "$pkg_dir/package.json" 2>/dev/null | grep -oE '\-p\s*[0-9]+' | grep -oE '[0-9]+' || true)
        fi
        [[ -z "$web_port" ]] && web_port="3000"  # Next.js documented default
        break
      fi
    done
  fi

  # Priority 5: Generic package.json port detection
  if [[ -z "$web_port" && -f "package.json" ]]; then
    # Look for explicit port in scripts: --port 3000, -p 3000, :3000
    web_port=$(grep -E '"(dev|start|serve)"' package.json 2>/dev/null | grep -oE '(--port|-p|:)[[:space:]]*[0-9]{4}' | grep -oE '[0-9]{4}' | head -1 || true)
  fi

  if [[ -n "$web_port" ]]; then
    base_url="http://localhost:$web_port"
  fi

  if [[ -n "$base_url" ]]; then
    if jq -e '.testUrlBase' "$tmpfile" >/dev/null 2>&1 && [[ "$(jq -r '.testUrlBase' "$tmpfile")" != "" ]]; then
      : # Already set
    else
      jq --arg url "$base_url" '.testUrlBase = $url' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected testUrlBase: $base_url"
      updated=true
    fi
  fi

  # 3. Detect frontend/backend directories for monorepos
  local frontend_dir="" backend_dir=""
  for dir in "apps/web" "apps/frontend" "frontend" "packages/web" "web"; do
    if [[ -d "$dir" && -f "$dir/package.json" ]]; then
      frontend_dir="$dir"
      break
    fi
  done
  for dir in "apps/api" "apps/backend" "backend" "api" "server"; do
    if [[ -d "$dir" ]] && ([[ -f "$dir/package.json" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/requirements.txt" ]]); then
      backend_dir="$dir"
      break
    fi
  done

  if [[ -n "$frontend_dir" ]]; then
    if jq -e '.directories.frontend' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg dir "$frontend_dir" '.directories.frontend = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected directories.frontend: $frontend_dir"
      updated=true
    fi
  fi

  if [[ -n "$backend_dir" ]]; then
    if jq -e '.directories.backend' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg dir "$backend_dir" '.directories.backend = $dir' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected directories.backend: $backend_dir"
      updated=true
    fi
  fi

  # 4. Detect API baseUrl by parsing actual config files for port values
  local api_url=""
  local api_port=""

  # Priority 1: docker-compose.yml - parse actual port mappings
  for compose_file in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
    if [[ -f "$compose_file" && -z "$api_port" ]]; then
      # Extract port from api/backend service: "8000:8000" -> 8000
      api_port=$(grep -A 20 -E '^\s*(api|backend|server|app):' "$compose_file" 2>/dev/null | \
                 grep -E '^\s*-\s*"?[0-9]+:[0-9]+"?' | head -1 | \
                 grep -oE '[0-9]+:' | head -1 | tr -d ':' || true)
    fi
  done

  # Priority 2: Dockerfile EXPOSE directive
  if [[ -n "$backend_dir" && -z "$api_port" ]]; then
    if [[ -f "$backend_dir/Dockerfile" ]]; then
      api_port=$(grep -i "^EXPOSE" "$backend_dir/Dockerfile" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1 || true)
    fi
  fi

  # Priority 3: Python - check for uvicorn/gunicorn port in scripts or pyproject.toml
  if [[ -n "$backend_dir" && -z "$api_port" ]]; then
    if [[ -f "$backend_dir/pyproject.toml" ]] || [[ -f "$backend_dir/requirements.txt" ]]; then
      # Check pyproject.toml for port config
      if [[ -f "$backend_dir/pyproject.toml" ]]; then
        api_port=$(grep -E 'port\s*=' "$backend_dir/pyproject.toml" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
      fi
      # Check for uvicorn command with --port
      if [[ -z "$api_port" && -f "$backend_dir/Makefile" ]]; then
        api_port=$(grep -E 'uvicorn.*--port' "$backend_dir/Makefile" 2>/dev/null | grep -oE '\-\-port[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1 || true)
      fi
      # Uvicorn/FastAPI default
      [[ -z "$api_port" ]] && api_port="8000"
    fi
  fi

  # Priority 4: Node backend - check package.json for port
  if [[ -n "$backend_dir" && -z "$api_port" && -f "$backend_dir/package.json" ]]; then
    api_port=$(grep -E '"(dev|start|serve)"' "$backend_dir/package.json" 2>/dev/null | grep -oE '(--port|-p|:)[[:space:]]*[0-9]{4}' | grep -oE '[0-9]{4}' | head -1 || true)
  fi

  if [[ -n "$api_port" ]]; then
    api_url="http://localhost:$api_port"
  fi

  if [[ -n "$api_url" ]]; then
    if jq -e '.api.baseUrl' "$tmpfile" >/dev/null 2>&1 && [[ "$(jq -r '.api.baseUrl' "$tmpfile")" != "" ]]; then
      : # Already set
    else
      jq --arg url "$api_url" '.api.baseUrl = $url' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected api.baseUrl: $api_url"
      updated=true
    fi

    # 4b. Detect api.healthEndpoint - probe common endpoints if server is running
    if ! jq -e '.api.healthEndpoint' "$tmpfile" >/dev/null 2>&1 || [[ "$(jq -r '.api.healthEndpoint' "$tmpfile")" == "null" ]]; then
      if command -v curl &>/dev/null; then
        local health_endpoint=""
        # Common health endpoint paths to try (most specific first)
        local health_paths=("/api/v1/health" "/api/health" "/health" "/healthz" "/api/v1/healthz" "/status" "/")

        for path in "${health_paths[@]}"; do
          local http_code
          http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "${api_url}${path}" 2>/dev/null) || http_code="000"
          if [[ "$http_code" =~ ^[23] ]]; then
            health_endpoint="$path"
            break
          fi
        done

        if [[ -n "$health_endpoint" ]]; then
          jq --arg ep "$health_endpoint" '.api.healthEndpoint = $ep' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
          echo "  Auto-detected api.healthEndpoint: $health_endpoint"
          updated=true
        fi
      fi
    fi
  fi

  # 5. Detect package manager
  local pkg_manager="npm"
  if [[ -f "pnpm-lock.yaml" ]]; then
    pkg_manager="pnpm"
  elif [[ -f "yarn.lock" ]]; then
    pkg_manager="yarn"
  elif [[ -f "bun.lockb" ]]; then
    pkg_manager="bun"
  fi

  if [[ "$pkg_manager" != "npm" ]]; then
    if jq -e '.packageManager' "$tmpfile" >/dev/null 2>&1; then
      : # Already set
    else
      jq --arg pm "$pkg_manager" '.packageManager = $pm' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected packageManager: $pkg_manager"
      updated=true
    fi
  fi

  # 6. FastMCP-specific detection
  if [[ -f "pyproject.toml" ]] && grep -qiE "(fastmcp|\"fastmcp\"|'fastmcp')" pyproject.toml 2>/dev/null; then
    # Detect MCP server module from entry points
    local mcp_module=""
    # Look for [project.scripts] section with pattern: name = "module.server:main"
    mcp_module=$(grep -A 20 '^\[project\.scripts\]' pyproject.toml 2>/dev/null | \
                 grep -E '^\w+\s*=\s*"[^"]+\.server:' | head -1 | \
                 sed -E 's/.*"([^"]+)\.server:.*/\1/' || true)

    # Fallback: detect from src directory structure
    if [[ -z "$mcp_module" && -d "src" ]]; then
      for dir in src/*/; do
        if [[ -f "${dir}server.py" ]]; then
          mcp_module=$(basename "${dir%/}")
          break
        fi
      done
    fi

    if [[ -n "$mcp_module" ]]; then
      if ! jq -e '.mcp.serverModule' "$tmpfile" >/dev/null 2>&1 || [[ "$(jq -r '.mcp.serverModule' "$tmpfile")" == "" ]]; then
        jq --arg mod "$mcp_module" '.mcp.serverModule = $mod' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
        # Also update the dev command
        jq --arg cmd "python -m ${mcp_module}.server" '.commands.dev = $cmd' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
        echo "  Auto-detected mcp.serverModule: $mcp_module"
        updated=true
      fi
    fi

    # Detect MCP port from .env or docker-compose
    local mcp_port=""
    if [[ -f ".env" ]]; then
      mcp_port=$(grep -E '^[A-Z_]*PORT=' .env 2>/dev/null | grep -v '#' | head -1 | grep -oE '[0-9]+' || true)
    fi
    if [[ -z "$mcp_port" ]]; then
      for compose_file in "docker-compose.yml" "docker-compose.yaml"; do
        if [[ -f "$compose_file" ]]; then
          # Look for port in main app service
          mcp_port=$(grep -A 20 -E '^\s*(app|gopa|mcp|server):' "$compose_file" 2>/dev/null | \
                     grep -E '^\s*-\s*"?[0-9]+:[0-9]+"?' | head -1 | \
                     grep -oE '[0-9]+:' | head -1 | tr -d ':' || true)
          [[ -n "$mcp_port" ]] && break
        fi
      done
    fi

    if [[ -n "$mcp_port" ]]; then
      if ! jq -e '.api.baseUrl' "$tmpfile" >/dev/null 2>&1 || [[ "$(jq -r '.api.baseUrl' "$tmpfile")" == "http://localhost:8000" ]]; then
        jq --arg url "http://localhost:$mcp_port" '.api.baseUrl = $url | .urls.app = $url' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
        echo "  Auto-detected MCP port: $mcp_port"
        updated=true
      fi
    fi

    # Detect MCP transport from .env
    if [[ -f ".env" ]]; then
      local transport=""
      transport=$(grep -E '^[A-Z_]*TRANSPORT=' .env 2>/dev/null | grep -v '#' | head -1 | cut -d'=' -f2 | tr -d '"'"'" || true)
      if [[ -n "$transport" ]]; then
        jq --arg t "$transport" '.mcp.transport = $t' "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      fi
    fi

    # Detect subprojects (directories with their own package.json)
    for subdir in */; do
      local subdir_name="${subdir%/}"
      if [[ -f "${subdir}package.json" && "$subdir_name" != "node_modules" ]]; then
        # Check if subproject already configured
        if ! jq -e ".subprojects[\"$subdir_name\"]" "$tmpfile" >/dev/null 2>&1; then
          local sub_lint="" sub_build="" sub_dev=""
          # Detect scripts from package.json
          if grep -q '"lint"' "${subdir}package.json" 2>/dev/null; then
            sub_lint="npm run lint"
          fi
          if grep -q '"build"' "${subdir}package.json" 2>/dev/null; then
            sub_build="npm run build"
          fi
          if grep -q '"dev"' "${subdir}package.json" 2>/dev/null; then
            sub_dev="npm run dev"
          fi

          jq --arg name "$subdir_name" \
             --arg path "$subdir_name" \
             --arg lint "$sub_lint" \
             --arg build "$sub_build" \
             --arg dev "$sub_dev" \
             '.subprojects[$name] = {path: $path, commands: {lint: $lint, build: $build, dev: $dev}}' \
             "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
          echo "  Auto-detected subproject: $subdir_name"
          updated=true
        fi
      fi
    done
  fi

  # 7. Detect test directory and patterns
  local test_dir=""
  local test_patterns=""

  # Check for common test directories
  for dir in "tests" "test" "__tests__" "spec" \
             "src/__tests__" "src/test" \
             "apps/api/tests" "apps/web/tests" \
             "backend/tests" "frontend/tests"; do
    if [[ -d "$dir" ]]; then
      test_dir="$dir"
      break
    fi
  done

  # If no directory found, check for colocated test files
  if [[ -z "$test_dir" ]]; then
    # Look for test files anywhere (colocated pattern)
    local test_file=""
    test_file=$(find . -type f \( \
      -name "*_test.py" -o -name "test_*.py" -o \
      -name "*.test.ts" -o -name "*.test.js" -o -name "*.test.tsx" -o \
      -name "*.spec.ts" -o -name "*.spec.js" -o \
      -name "*_test.go" -o -name "*_test.rs" \
    \) -not -path "*/node_modules/*" -not -path "*/.venv/*" -not -path "*/venv/*" \
       -not -path "*/.git/*" -not -path "*/dist/*" -not -path "*/build/*" \
       -not -path "*/__pycache__/*" -not -path "*/coverage/*" 2>/dev/null | head -1 || true)

    if [[ -n "$test_file" ]]; then
      # Tests are colocated with source (e.g., src/component.test.ts)
      test_dir="src"
      [[ ! -d "src" ]] && test_dir="."
    fi
  fi

  # Detect test patterns based on project type (combine for mixed projects)
  test_patterns=""
  if [[ -f "pyproject.toml" || -f "requirements.txt" ]]; then
    test_patterns="*_test.py,test_*.py"
  fi
  if [[ -f "package.json" ]]; then
    [[ -n "$test_patterns" ]] && test_patterns+=","
    test_patterns+="*.test.ts,*.test.tsx,*.test.js,*.spec.ts,*.spec.tsx,*.spec.js"
  fi
  if [[ -f "go.mod" ]]; then
    [[ -n "$test_patterns" ]] && test_patterns+=","
    test_patterns+="*_test.go"
  fi
  if [[ -f "Cargo.toml" ]]; then
    [[ -n "$test_patterns" ]] && test_patterns+=","
    test_patterns+="*_test.rs"
  fi
  if [[ -f "mix.exs" ]]; then
    [[ -n "$test_patterns" ]] && test_patterns+=","
    test_patterns+="*_test.exs"
  fi

  if [[ -n "$test_dir" ]]; then
    if ! jq -e '.tests.directory' "$tmpfile" >/dev/null 2>&1 || [[ "$(jq -r '.tests.directory' "$tmpfile")" == "" ]]; then
      jq --arg dir "$test_dir" --arg patterns "$test_patterns" \
         '.tests.directory = $dir | .tests.patterns = $patterns' \
         "$tmpfile" > "${tmpfile}.new" && mv "${tmpfile}.new" "$tmpfile"
      echo "  Auto-detected tests.directory: $test_dir"
      updated=true
    fi
  else
    # No tests found - check if warning is suppressed
    local require_tests
    require_tests=$(jq -r '.checks.requireTests // true' "$tmpfile" 2>/dev/null)

    if [[ "$require_tests" == "true" ]]; then
      echo ""
      print_warning "No test directory or test files found."
      echo "  Without tests, Ralph relies on lint, type-checking, and PRD test steps."
      echo "  Consider adding tests or PRD testCommands for better verification."
      echo ""
      echo "  To fix: Add tests, or set in .ralph/config.json:"
      echo "    {\"tests\": {\"directory\": \"src\", \"patterns\": \"*.test.ts\"}}"
      echo "  To silence: {\"checks\": {\"requireTests\": false}}"
      echo ""
    fi
  fi

  # Save if updated
  if [[ "$updated" == "true" ]]; then
    mv "$tmpfile" "$config"
  else
    rm -f "$tmpfile"
  fi
}

# Show current ralph status
ralph_status() {
  if [[ ! -d "$RALPH_DIR" ]]; then
    print_error "Ralph not initialized. Run 'ralph init' first."
    return 1
  fi

  echo ""
  print_info "=== Ralph Status ==="
  echo ""

  # Check if PRD exists
  if [[ -f "$RALPH_DIR/prd.json" ]]; then
    local feature_name status
    feature_name=$(jq -r '.feature.name // "Unknown"' "$RALPH_DIR/prd.json")
    status=$(jq -r '.feature.status // "unknown"' "$RALPH_DIR/prd.json")

    echo "Feature: $feature_name"
    echo "Status:  $status"
    echo ""

    # Show stories
    echo "Stories:"
    jq -r '.stories[] | "  \(.id): \(.title) [\(if .passes then "DONE" else "TODO" end)]"' "$RALPH_DIR/prd.json" 2>/dev/null || echo "  (none)"

    # Count pass/fail
    local total passed failed
    total=$(jq '.stories | length' "$RALPH_DIR/prd.json")
    passed=$(jq '[.stories[] | select(.passes == true)] | length' "$RALPH_DIR/prd.json")
    failed=$((total - passed))
    echo ""
    echo "Progress: $passed/$total passed ($failed remaining)"
  else
    # Check for misplaced PRD in subdirectories
    local found_prd
    found_prd=$(find . -path "./.ralph" -prune -o -name "prd.json" -path "*/.ralph/prd.json" -print 2>/dev/null | head -1 || true)

    if [[ -n "$found_prd" ]]; then
      print_warning "PRD found in wrong location: $found_prd"
      echo ""
      echo "Move it to root with:"
      echo "  mv $found_prd .ralph/prd.json"
    else
      echo "No active PRD. Generate one with: ralph prd 'your feature notes...'"
    fi
  fi

  echo ""

  # Show recent progress
  if [[ -f "$RALPH_DIR/progress.txt" ]]; then
    echo "Recent activity:"
    tail -5 "$RALPH_DIR/progress.txt" | sed 's/^/  /'
  fi

  echo ""
}

# Show help
ralph_help() {
  cat <<'EOF'
agentic-loop - Tools to thrive with agentic coding

What is this?
  agentic-loop helps you build features using two terminals working together.

  Terminal 1 - Claude Code (your AI pair programmer):
    claude --dangerously-skip-permissions

    The --dangerously-skip-permissions flag lets Claude edit files and run
    commands without asking permission each time. This enables fluid,
    uninterrupted collaboration while you brainstorm and refine ideas.

    Use /idea to brainstorm big features. Claude saves your ideas to
    docs/ideas/, then breaks them into small, executable PRDs.

  Terminal 2 - Ralph (autonomous execution):
    npx agentic-loop run

    Ralph picks up the PRDs you created and builds them autonomously.
    It writes code, runs tests, and iterates until each feature works.
    Ralph runs separately so you can keep brainstorming in Claude.

Quick Start:
  1. npx agentic-loop setup
  2. Terminal 1: claude --dangerously-skip-permissions
  3. In Claude: /idea "your feature description"
  4. Terminal 2: npx agentic-loop run
  5. Monitor Terminal 2 - it should be autonomous. If issues come up,
     stop the loop (Ctrl+C) and paste the errors into Terminal 1.

Usage:
  npx agentic-loop <command> [options]

Commands:
  setup                   Set up project (hooks, config, CLAUDE.md)
  init                    Initialize Ralph in current directory
  config                  Re-detect and update project config
  prd <notes>             Generate PRD interactively (quick mode)
  prd --file <file>       Generate PRD from file
  run                     Run autonomous loop until all stories pass
  run --max <n>           Run with max iterations (default: 20)
  run --fast              Skip code review for faster iterations
  status                  Show current feature and story status
  check                   Run verification checks only
  verify <story-id>       Verify a specific story
  sign <pattern> [cat]    Add a learned pattern (sign)
  signs                   List all learned patterns
  backup                  Backup detected databases to .backups/
  backups                 List available database backups
  restore <path>          Restore database from backup
  help                    Show this help message

PRD Generation:
  /idea <description>           Thorough brainstorm (in Claude Code)
  npx agentic-loop prd <notes>     Quick PRD generation

Examples:
  npm install agentic-loop && npx agentic-loop setup
  /idea "Add user authentication with OAuth"
  npx agentic-loop prd "Add a contact form"
  npx agentic-loop run
  npx agentic-loop run --max 10
  npx agentic-loop status
  npx agentic-loop sign "Always use camelCase" frontend

Environment:
  RALPH_DIR       Override .ralph directory location (default: .ralph)
  PROMPT_FILE     Override PROMPT.md location (default: PROMPT.md)

For more information, see: https://github.com/allierays/agentic-loop
EOF
}
