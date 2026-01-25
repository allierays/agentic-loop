# Agentic Loop - Technical Architecture

How agentic-loop works under the hood.

---

## The Loop

This is the core of everything:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           RALPH LOOP                                     │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   1. Read .ralph/prd.json                                                │
│      └─▶ Find next story where passes=false                             │
│                                                                          │
│   2. Build prompt                                                        │
│      └─▶ PROMPT.md + story + signs + failure context + DNA              │
│                                                                          │
│   3. Run Claude                                                          │
│      └─▶ First story: fresh session                                     │
│      └─▶ Subsequent: --continue (preserves context)                     │
│                                                                          │
│   4. Verify                                                              │
│      └─▶ Lint → Tests → testSteps from PRD                              │
│                                                                          │
│   5. Result                                                              │
│      └─▶ Pass: mark passes=true, git commit, next story                 │
│      └─▶ Fail: save error to last_failure.txt, retry same story         │
│                                                                          │
│   6. Repeat until all stories pass or max iterations                    │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
your-project/
├── .ralph/
│   ├── config.json         # Project settings (paths, commands, checks)
│   ├── prd.json            # Current PRD with stories
│   ├── signs.json          # Learned patterns
│   ├── progress.txt        # Activity log
│   ├── last_failure.txt    # Last error (for retries)
│   ├── hooks/              # Claude Code hooks (copied during setup)
│   └── archive/            # Completed PRDs
│
├── .claude/
│   ├── settings.json       # Claude hooks configuration
│   └── commands/           # Slash commands (/idea, /review, etc.)
│
├── .github/
│   └── workflows/
│       ├── pr.yml          # Fast PR checks (lint, typecheck, build)
│       └── nightly.yml     # Full tests + PRD testSteps
│
├── PROMPT.md               # Base instructions for Claude
├── CLAUDE.md               # Project context
└── .pre-commit-config.yaml # Pre-commit hooks
```

---

## Prompt Assembly

When Ralph runs a story, it builds a prompt by combining multiple sources:

| Source | What it provides |
|--------|------------------|
| `PROMPT.md` | Base coding instructions, verification checklist |
| Story from `prd.json` | id, title, acceptanceCriteria, errorHandling, testSteps |
| `story.files` | Which files to create, modify, reuse |
| `story.mcp` | Which MCP tools to use (playwright, devtools) |
| `prd.originalContext` | Full text of original idea file |
| `prd.feature` | Feature name and metadata |
| `prd.architecture` | Directory rules, doNotCreate |
| `.ralph/last_failure.txt` | Previous error (if retrying) |
| `.ralph/signs.json` | Learned patterns from past failures |
| `~/.claude/DNA.md` | Your personal coding preferences |

The assembled prompt is piped to Claude:
```bash
echo "$prompt" | claude -p --dangerously-skip-permissions
```

---

## Session Continuity

Stories within a single Ralph run share Claude's context:

**First story:** Fresh session with full prompt
```bash
claude -p --dangerously-skip-permissions
```

**Subsequent stories:** Continue with delta prompt (just new story info)
```bash
claude --continue -p --dangerously-skip-permissions
```

This means Claude remembers what it built in TASK-001 when working on TASK-002.

---

## Verification Pipeline

After Claude finishes coding, Ralph runs verification:

```
┌─────────────────────────────────────────────────────────┐
│  1. LINT                                                │
│     └─▶ Auto-fix (eslint --fix, ruff --fix)            │
│     └─▶ Build check (npm run build)                    │
│     └─▶ Lint check (npm run lint, ruff check)          │
│     └─▶ Type check (tsc --noEmit, mypy)                │
├─────────────────────────────────────────────────────────┤
│  2. TESTS                                               │
│     └─▶ Check test files exist (if requireTests=true)  │
│     └─▶ Run unit tests (pytest, npm test, go test)     │
├─────────────────────────────────────────────────────────┤
│  3. PRD TEST STEPS                                      │
│     └─▶ Execute each command in story.testSteps[]      │
│     └─▶ All must pass for story to pass                │
└─────────────────────────────────────────────────────────┘
```

If any step fails, error is saved to `last_failure.txt` and Claude retries with that context.

---

## Skills (Slash Commands)

Skills are markdown files in `.claude/commands/` that expand into full prompts.

| Skill | File | Purpose |
|-------|------|---------|
| `/idea` | `idea.md` | Brainstorm feature → generate PRD |
| `/prd` | `prd.md` | Generate PRD from idea file |
| `/review` | `review.md` | Security-focused code review |
| `/vibe-check` | `vibe-check.md` | Code quality audit |
| `/sign` | `sign.md` | Add a learned pattern |
| `/explain` | `explain.md` | Explain code line by line |
| `/styleguide` | `styleguide.md` | Generate UI component reference |
| `/my-dna` | `my-dna.md` | Set up personal preferences |
| `/tour` | `tour.md` | Interactive walkthrough |

When you type `/idea`, Claude reads `.claude/commands/idea.md` and follows those instructions.

---

## Claude Code Hooks

Hooks run during Claude's operation. Defined in `.claude/settings.json`:

### PreToolUse Hooks
Run BEFORE Claude uses a tool. Can block the operation.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `protect-prd.sh` | Edit\|Write | Blocks marking `passes: true` |

### PostToolUse Hooks
Run AFTER Claude uses a tool. Can warn but not block.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `warn-debug.sh` | Edit\|Write | Warns on console.log, debugger |
| `warn-secrets.sh` | Edit\|Write | Warns on hardcoded API keys |
| `warn-urls.sh` | Edit\|Write | Warns on localhost URLs |
| `warn-empty-catch.sh` | Edit\|Write | Warns on empty catch blocks |
| `log-tools.sh` | * | Logs all tool usage |

### Session Hooks

| Hook | When | Purpose |
|------|------|---------|
| `inject-context.sh` | SessionStart | Inject context at start |
| `save-learnings.sh` | Stop | Save learnings at end |

### Hook Input/Output

Hooks receive JSON on stdin:
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/path/to/file",
    "new_string": "..."
  }
}
```

Hooks output:
```json
{"continue": true}                    // Allow
{"continue": true, "message": "..."}  // Allow with warning
// Exit code 2 = Block
```

---

## Pre-commit Hooks

Git hooks that run before each commit. Defined in `.pre-commit-config.yaml`:

| Hook | What it catches |
|------|-----------------|
| `check-secrets` | API keys, passwords, tokens in code |
| `check-hardcoded-urls` | localhost URLs, hardcoded domains |
| `check-debug` | console.log, print(), debugger statements |
| `backup-db` | Backs up database before commit |

Run manually:
```bash
pre-commit run --all-files
```

Suppress a warning with inline comment:
```typescript
console.log('Server starting...'); // noqa: debug
```

---

## Configuration

### .ralph/config.json

```json
{
  "directories": {
    "frontend": "apps/web",
    "backend": "apps/api"
  },

  "checks": {
    "build": true,
    "lint": true,
    "test": true,
    "testCommand": "cd apps/api && uv run pytest -x -q",
    "requireTests": false
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

### Key Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `directories.frontend` | `.` | Frontend source directory |
| `directories.backend` | `.` | Backend source directory |
| `checks.test` | `true` | `true`, `false`, or `"final"` (only last story) |
| `checks.testCommand` | auto-detect | Custom test command |
| `checks.requireTests` | `false` | Fail if new Python/Go files lack tests |
| `maxIterations` | `20` | Max retries before giving up |

---

## PRD Structure

```json
{
  "feature": {
    "name": "User Dashboard",
    "branch": "feature/user-dashboard",
    "status": "pending"
  },

  "originalContext": "Full text of the idea file...",

  "stories": [
    {
      "id": "TASK-001",
      "type": "frontend",
      "title": "Create dashboard layout",
      "passes": false,

      "files": {
        "create": ["src/components/Dashboard.tsx"],
        "modify": ["src/App.tsx"],
        "reuse": ["src/components/ui/Card.tsx"]
      },

      "acceptanceCriteria": [
        "Shows user name in header",
        "Responsive layout"
      ],

      "errorHandling": [
        "Show loading state while fetching",
        "Show error message if fetch fails"
      ],

      "testSteps": [
        "npm test -- Dashboard",
        "npm run build"
      ],

      "mcp": ["playwright", "devtools"],

      "dependsOn": []
    }
  ],

  "architecture": {
    "frontend": "src/components",
    "doNotCreate": ["new API routes without backend story"]
  }
}
```

---

## MCP Tools

MCP (Model Context Protocol) tools give Claude browser access.

### Configuration (~/.claude.json)

```json
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

### Per-Story MCP

Stories can specify which MCP tools to use:

```json
{
  "id": "TASK-001",
  "type": "frontend",
  "mcp": ["playwright", "devtools"]
}
```

This injects instructions telling Claude to use those tools for verification.

---

## Signs (Learned Patterns)

Signs are patterns Ralph learns from failures.

### Storage (.ralph/signs.json)

```json
{
  "signs": [
    {
      "id": "sign-001",
      "pattern": "Always use camelCase for API response fields",
      "category": "backend",
      "learnedFrom": "TASK-003"
    }
  ]
}
```

### Usage

```bash
npx agentic-loop signs                          # List all
npx agentic-loop sign "Use camelCase" backend   # Add
npx agentic-loop unsign "Use camelCase"         # Remove
```

Signs are injected into every prompt so Claude learns from past mistakes.

---

## CI/CD

### Dynamic Workflow Generation

`npx agentic-loop ci install` generates workflows from your config:

- Reads `directories.backend` and `directories.frontend`
- Reads `checks.testCommand`
- Generates YAML with correct paths for your project

### PR Workflow (.github/workflows/pr.yml)

Fast checks on pull requests:
- Lint (ruff, eslint)
- Type check (mypy, tsc)
- Build

### Nightly Workflow (.github/workflows/nightly.yml)

Comprehensive tests at 3am UTC:
- Full unit test suite
- All PRD testSteps
- Coverage report

### Run Locally

```bash
npx agentic-loop test        # Full suite + PRD testSteps
npx agentic-loop test unit   # Just unit tests
npx agentic-loop test prd    # Just PRD testSteps
npx agentic-loop coverage    # Coverage report
```

---

## CLI Commands

| Command | Description |
|---------|-------------|
| `npx agentic-loop setup` | Initialize project |
| `npx agentic-loop run` | Start the loop |
| `npx agentic-loop run --max 5` | Limit iterations |
| `npx agentic-loop run --story TASK-001` | Run specific story |
| `npx agentic-loop stop` | Stop after current story |
| `npx agentic-loop status` | Show progress |
| `npx agentic-loop check` | Run verification only |
| `npx agentic-loop verify TASK-001` | Verify specific story |
| `npx agentic-loop test` | Run nightly tests locally |
| `npx agentic-loop ci install` | Generate GitHub workflows |
| `npx agentic-loop signs` | List learned patterns |
| `npx agentic-loop sign "..." cat` | Add a pattern |
| `npx agentic-loop progress` | Show recent log |

---

## Source Files

```
ralph/
├── utils.sh        # Constants, logging, config helpers
├── loop.sh         # Main loop orchestrator
├── verify.sh       # Verification coordinator
├── verify/
│   ├── lint.sh     # Build, lint, typecheck
│   └── tests.sh    # Unit tests, test file check
├── prd.sh          # PRD generation
├── signs.sh        # Signs management
├── test.sh         # Nightly test runner
├── ci.sh           # GitHub Actions generator
├── setup.sh        # Project setup
└── hooks/          # Claude Code hooks
```

---

## Logging

### Progress Log (.ralph/progress.txt)

```
2024-01-15 10:30:00 | START  | TASK-001 | Create dashboard
2024-01-15 10:35:00 | CLAUDE | TASK-001 | Session started
2024-01-15 10:40:00 | VERIFY | TASK-001 | Running verification
2024-01-15 10:41:00 | PASS   | TASK-001 | All checks passed
2024-01-15 10:41:00 | COMMIT | TASK-001 | feat(TASK-001): Create dashboard
```

### Tool Log (.ralph/tool-log.txt)

```
2024-01-15 10:35:15 | Edit  | src/components/Dashboard.tsx
2024-01-15 10:35:20 | Write | src/components/Dashboard.test.tsx
2024-01-15 10:36:00 | Bash  | npm test
```
