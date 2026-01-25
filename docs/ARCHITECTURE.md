# Agentic Loop - Technical Architecture

Deep dive into how agentic-loop works under the hood.

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AGENTIC LOOP                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │  setup   │───▶│   prd    │───▶│   loop   │───▶│  verify  │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│       │               │               │               │                  │
│       ▼               ▼               ▼               ▼                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐          │
│  │ config/  │    │ prd.json │    │  Claude  │    │  lint/   │          │
│  │ hooks/   │    │          │    │   CLI    │    │  test/   │          │
│  │ commands │    │          │    │          │    │  browser │          │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
ralph/
├── utils.sh          # Shared constants, logging, config helpers
├── loop.sh           # Main autonomous loop orchestrator
├── verify.sh         # Verification pipeline coordinator
├── verify/
│   ├── lint.sh       # Linting and auto-fix
│   ├── tests.sh      # Unit test runner
│   ├── review.sh     # Code review (optional)
│   └── browser.sh    # Browser validation (deprecated - MCP handles this)
├── prd.sh            # PRD generation from ideas
├── signs.sh          # Learned patterns management
├── test.sh           # Nightly test runner
├── ci.sh             # GitHub Actions generator
├── setup.sh          # Project initialization
├── init.sh           # Legacy init (calls setup)
├── backup.sh         # Database backup/restore
└── hooks/
    ├── protect-prd.sh    # Block marking passes=true
    ├── warn-debug.sh     # Warn on console.log
    ├── warn-secrets.sh   # Warn on hardcoded secrets
    ├── warn-urls.sh      # Warn on localhost URLs
    ├── warn-empty-catch.sh
    ├── inject-context.sh # Session start context
    ├── log-tools.sh      # Tool usage logging
    └── save-learnings.sh # Session end learnings
```

## Core Loop (`loop.sh`)

### Execution Flow

```
ralph_loop()
    │
    ├─▶ find_next_story()        # Query prd.json for passes=false
    │       │
    │       └─▶ Returns story JSON or empty
    │
    ├─▶ build_prompt()           # Assemble full prompt
    │       │
    │       ├─▶ cat PROMPT.md              # Base instructions
    │       ├─▶ _inject_story_context()    # Current story details
    │       ├─▶ _inject_file_guidance()    # files.create/modify/reuse
    │       ├─▶ _inject_story_scale()      # Scale requirements
    │       ├─▶ _inject_styleguide()       # UI styleguide reference
    │       ├─▶ _inject_mcp_instructions() # MCP tools for story
    │       ├─▶ _inject_original_context() # Original idea file
    │       ├─▶ _inject_feature_context()  # Feature metadata
    │       ├─▶ _inject_scalability()      # Scalability rules
    │       ├─▶ _inject_architecture()     # Architecture guidelines
    │       ├─▶ _inject_failure_context()  # Last failure (if retry)
    │       ├─▶ _inject_signs()            # Learned patterns
    │       └─▶ _inject_developer_dna()    # Personal preferences
    │
    ├─▶ run_claude()             # Execute Claude CLI
    │       │
    │       ├─▶ First story: claude -p --dangerously-skip-permissions
    │       └─▶ Subsequent:  claude --continue -p ...
    │
    ├─▶ run_verification()       # Verification pipeline
    │       │
    │       ├─▶ verify/lint.sh   # Build + lint + typecheck
    │       ├─▶ verify/tests.sh  # Unit tests + test file check
    │       └─▶ testSteps[]      # PRD-defined commands
    │
    ├─▶ handle_result()
    │       │
    │       ├─▶ Pass: mark_story_passed(), git commit, next story
    │       └─▶ Fail: save_failure(), increment retry, same story
    │
    └─▶ Loop until all stories pass or max iterations
```

### Session Continuity

The loop maintains Claude session context across stories:

```bash
# First story - fresh session
local -a claude_args=(-p --dangerously-skip-permissions --verbose)

# Subsequent stories - continue session
if [[ "$session_started" == "true" ]]; then
  claude_args=(--continue "${claude_args[@]}")
fi

# Build prompt
prompt=$(build_prompt "$story_json" "$failure_context" "$is_continuation")
echo "$prompt" | claude "${claude_args[@]}"
```

For continuing sessions, `build_delta_prompt()` sends only:
- New story context
- File guidance for new story
- Any failure context from previous attempt

This preserves Claude's memory of previous stories while reducing token usage.

### Prompt Assembly

The full prompt structure:

```
┌─────────────────────────────────────────────────────────────────┐
│ PROMPT.md                                                        │
│ - Session startup checklist                                      │
│ - Implementation requirements                                    │
│ - Testing requirements                                           │
│ - Verification checklist                                         │
│ - Code quality standards                                         │
├─────────────────────────────────────────────────────────────────┤
│ ## Current Story                                                 │
│ {id, title, type, acceptanceCriteria, errorHandling, testSteps} │
├─────────────────────────────────────────────────────────────────┤
│ ## File Guidance                                                 │
│ Create: [...], Modify: [...], Reuse: [...]                      │
├─────────────────────────────────────────────────────────────────┤
│ ## MCP Tools (if story.mcp defined)                             │
│ Playwright MCP instructions, DevTools MCP instructions          │
├─────────────────────────────────────────────────────────────────┤
│ ## Original Idea Context                                         │
│ {full text of idea file that inspired this PRD}                 │
├─────────────────────────────────────────────────────────────────┤
│ ## Feature Context                                               │
│ {feature name, metadata from prd.json}                          │
├─────────────────────────────────────────────────────────────────┤
│ ## Architecture Guidelines                                       │
│ {directories, doNotCreate rules from prd.json}                  │
├─────────────────────────────────────────────────────────────────┤
│ ## Previous Iteration Failed (if retrying)                      │
│ {error output from .ralph/last_failure.txt}                     │
├─────────────────────────────────────────────────────────────────┤
│ ## Signs (Learned Patterns)                                      │
│ - [backend] Always use camelCase...                             │
│ - [frontend] Import Button from...                              │
├─────────────────────────────────────────────────────────────────┤
│ ## Developer DNA (if ~/.claude/DNA.md exists)                   │
│ {personal coding preferences}                                    │
└─────────────────────────────────────────────────────────────────┘
```

## Verification Pipeline (`verify.sh`)

### Pipeline Stages

```
run_verification()
    │
    ├─▶ Stage 1: Lint
    │   └─▶ verify/lint.sh
    │       ├─▶ run_auto_fix()     # ESLint --fix, ruff --fix
    │       ├─▶ run_build()        # npm run build / cargo build
    │       ├─▶ run_lint()         # npm run lint / ruff check
    │       └─▶ run_typecheck()    # tsc --noEmit / mypy
    │
    ├─▶ Stage 2: Tests
    │   └─▶ verify/tests.sh
    │       ├─▶ verify_test_files_exist()  # Check test files for new code
    │       └─▶ run_unit_tests()           # pytest / npm test / go test
    │
    └─▶ Stage 3: PRD testSteps
        └─▶ Execute each command in story.testSteps[]
```

### Story Type Detection

```bash
get_story_type() {
  local story_json="$1"
  echo "$story_json" | jq -r '.type // "frontend"'
}

# Used to skip irrelevant checks
# Backend stories skip: ESLint, TypeScript
# Frontend stories skip: Python lint, pytest
```

### Test File Verification

When `checks.requireTests: true`:

```bash
verify_test_files_exist() {
  # Python: foo.py → tests/test_foo.py
  # Go: foo.go → foo_test.go (same directory)

  local new_files=$(git diff --name-only --diff-filter=A HEAD~1)

  for file in $new_files; do
    case "$file" in
      *.py)
        test_file="tests/test_$(basename "$file")"
        [[ ! -f "$test_file" ]] && fail
        ;;
      *.go)
        test_file="${file%.go}_test.go"
        [[ ! -f "$test_file" ]] && fail
        ;;
    esac
  done
}
```

## Configuration System

### Config File Location

```
.ralph/config.json    # Project-specific config
```

### Config Schema

```json
{
  "directories": {
    "frontend": "apps/web",      // Frontend source directory
    "backend": "apps/api"        // Backend source directory
  },

  "checks": {
    "build": true,               // Run build check
    "lint": true,                // Run linter
    "test": true | false | "final",  // Test mode
    "testCommand": "pytest -x",  // Custom test command
    "requireTests": false        // Require test files for new code
  },

  "playwright": {
    "enabled": true,
    "testDir": "tests/e2e"
  },

  "urls": {
    "frontend": "http://localhost:3000",
    "backend": "http://localhost:8000"
  },

  "maxIterations": 20,
  "maxSessionSeconds": 600
}
```

### Config Helper

```bash
# Usage: get_config '.path.to.value' 'default'
get_config() {
  local path="$1"
  local default="$2"

  if [[ -f "$RALPH_DIR/config.json" ]]; then
    local value
    value=$(jq -r "$path // empty" "$RALPH_DIR/config.json" 2>/dev/null)
    [[ -n "$value" && "$value" != "null" ]] && echo "$value" || echo "$default"
  else
    echo "$default"
  fi
}
```

## PRD Schema

### Full Structure

```json
{
  "feature": {
    "name": "Feature Name",
    "ideaFile": "docs/ideas/feature.md",
    "branch": "feature/feature-name",
    "status": "pending"
  },

  "originalContext": "Full text of idea file...",

  "metadata": {
    "createdAt": "ISO timestamp",
    "estimatedStories": 5,
    "complexity": "low|medium|high"
  },

  "stories": [
    {
      "id": "TASK-001",
      "type": "frontend|backend",
      "title": "Short description",
      "passes": false,

      "files": {
        "create": ["paths to new files"],
        "modify": ["paths to existing files"],
        "reuse": ["existing files to import from"]
      },

      "acceptanceCriteria": ["What it should do"],
      "errorHandling": ["What happens when things fail"],

      "testSteps": ["shell commands to verify"],
      "testUrl": "/path/to/test",

      "mcp": ["playwright", "devtools"],

      "dependsOn": ["TASK-000"],
      "notes": ""
    }
  ],

  "architecture": {
    "frontend": "src/components",
    "backend": "src/api",
    "doNotCreate": ["rules about what not to create"]
  },

  "scalability": {
    "pagination": "cursor-based",
    "caching": "Redis with 5min TTL"
  }
}
```

### Story Lifecycle

```
passes: false  ──▶  Claude implements  ──▶  Verification
                                               │
                          ┌────────────────────┴────────────────────┐
                          │                                         │
                          ▼                                         ▼
                    PASS: passes: true                        FAIL: retry
                    git commit                                save error
                    next story                                same story
```

## Hooks System

### Claude Code Hooks

Hooks are shell scripts that run at specific points in Claude's execution:

```json
// .claude/settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": ".ralph/hooks/protect-prd.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": ".ralph/hooks/warn-debug.sh"},
          {"type": "command", "command": ".ralph/hooks/warn-secrets.sh"}
        ]
      }
    ],
    "SessionStart": [...],
    "Stop": [...]
  }
}
```

### Hook Input/Output

Hooks receive JSON on stdin:

```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file",
    "old_string": "...",
    "new_string": "..."
  }
}
```

Hooks output JSON:

```json
{"continue": true}           // Allow the operation
{"continue": true, "message": "Warning: ..."}  // Allow with warning
// Exit code 2 = block the operation
```

### protect-prd.sh Logic

```bash
# Only blocks edits that mark passes=true
if echo "$NEW_STRING" | grep -qE '"passes"\s*:\s*true'; then
  echo "BLOCKED: Cannot mark stories as passed." >&2
  exit 2
fi

# All other prd.json edits allowed
echo '{"continue": true}'
```

## CI/CD Integration

### Dynamic Workflow Generation

`npx agentic-loop ci install` generates workflows from config:

```bash
generate_pr_workflow() {
  local backend_dir="$1"    # From config.directories.backend
  local frontend_dir="$2"   # From config.directories.frontend

  # Generate YAML with correct paths
  cat >> .github/workflows/pr.yml << EOF
      - name: Python tests
        run: cd $backend_dir && pytest
EOF
}
```

### Nightly Test Command

```bash
# Run locally
npx agentic-loop test        # Full suite + PRD testSteps
npx agentic-loop test unit   # Just unit tests
npx agentic-loop test prd    # Just PRD testSteps

# In CI
npx agentic-loop test prd    # Verifies all testSteps still pass
```

## MCP Integration

### MCP Tools Configuration

```json
// ~/.claude.json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"]
    },
    "chrome-devtools": {
      "command": "npx",
      "args": ["chrome-devtools-mcp@latest"]
    }
  }
}
```

### Per-Story MCP Config

```json
{
  "id": "TASK-001",
  "type": "frontend",
  "mcp": ["playwright", "devtools"],  // Tools to use for this story
  ...
}
```

Injected as:

```markdown
## MCP Tools - USE THESE FOR VERIFICATION

**Playwright MCP** (browser automation & testing):
- Navigate to URLs and verify page content
- Take screenshots to verify UI renders correctly
...

**Do NOT mark this story complete until you have verified with these tools.**
```

## Signs (Learned Patterns)

### Storage

```json
// .ralph/signs.json
{
  "signs": [
    {
      "id": "sign-001",
      "pattern": "Always use camelCase for API response fields",
      "category": "backend",
      "learnedFrom": "TASK-003",
      "createdAt": "2024-01-15T10:30:00Z"
    }
  ]
}
```

### Injection

Signs are injected into every prompt:

```markdown
## Signs (Learned Patterns)

These patterns were learned from previous iterations. Follow them:

- [backend] Always use camelCase for API response fields
- [frontend] Import Button from @/components/ui, not shadcn directly
```

### CLI Management

```bash
npx agentic-loop signs              # List all signs
npx agentic-loop sign "pattern" category  # Add a sign
npx agentic-loop unsign "pattern"   # Remove a sign
```

## Error Handling

### Failure Context

When verification fails, the error is saved:

```bash
# verify.sh
save_failure() {
  local error="$1"
  echo "$error" > "$RALPH_DIR/last_failure.txt"
  log_progress "Verification failed: ${error:0:200}..."
}
```

On retry, this is injected into the prompt:

```markdown
## Previous Iteration Failed

The last attempt failed with this error:

```
Error: Cannot find module '@/lib/utils'
  at Module._resolveFilename (node:internal/modules/cjs/loader:1048:15)
```

Fix this issue before proceeding.
```

### Max Retries

```bash
MAX_RETRIES=3  # Per story

if [[ $retry_count -ge $MAX_RETRIES ]]; then
  log_progress "SKIP: $story_id failed after $MAX_RETRIES attempts"
  # Move to next story, don't block forever
fi
```

## Logging

### Progress File

```bash
# .ralph/progress.txt
2024-01-15 10:30:00 | START | TASK-001 | Create user dashboard
2024-01-15 10:35:00 | CLAUDE | TASK-001 | Session started
2024-01-15 10:40:00 | VERIFY | TASK-001 | Running verification
2024-01-15 10:41:00 | PASS | TASK-001 | All checks passed
2024-01-15 10:41:00 | COMMIT | TASK-001 | feat(TASK-001): Create user dashboard
```

### Tool Log

```bash
# .ralph/tool-log.txt
2024-01-15 10:35:15 | Edit | src/components/Dashboard.tsx
2024-01-15 10:35:20 | Write | src/components/Dashboard.test.tsx
2024-01-15 10:36:00 | Bash | npm test
```

## Performance Considerations

### Token Usage

- Fresh session: ~2000-5000 tokens for full prompt
- Continuation: ~500-1000 tokens for delta prompt
- Signs add ~50 tokens per pattern
- Original context can add 1000+ tokens

### Parallelization

Stories are executed sequentially (dependency order), but within verification:

```bash
# These could run in parallel but don't currently
run_lint &
run_typecheck &
wait
```

### Caching

- Config is read once per loop iteration
- PRD is re-read each iteration (may have changed)
- Signs are read once per story

## Extension Points

### Custom Verification

Add to `verify/`:

```bash
# verify/custom.sh
run_custom_check() {
  # Your custom verification logic
  return 0  # or 1 for failure
}
```

### Custom Hooks

Add to `.ralph/hooks/`:

```bash
# .ralph/hooks/my-hook.sh
INPUT=$(cat)
# Process input
echo '{"continue": true}'
```

Register in `.claude/settings.json`.

### Custom Config

Add fields to `.ralph/config.json`:

```json
{
  "myFeature": {
    "enabled": true,
    "setting": "value"
  }
}
```

Access with:

```bash
my_setting=$(get_config '.myFeature.setting' 'default')
```
