# Technical Architecture

Complete technical breakdown of the agentic-loop codebase.

## Table of Contents

1. [Overview](#overview)
2. [System Flow](#system-flow)
3. [Entry Points](#entry-points)
4. [Core Loop](#core-loop)
5. [Verification Pipeline](#verification-pipeline)
6. [Prompt Assembly](#prompt-assembly)
7. [Slash Commands](#slash-commands)
8. [Claude Code Hooks](#claude-code-hooks)
9. [Vibe-Check Engine](#vibe-check-engine)
10. [Configuration](#configuration)
11. [Templates](#templates)
12. [Data Files](#data-files)

---

## Overview

Agentic-loop is a Bash-based orchestration system that runs Claude Code in an autonomous loop. It reads stories from a PRD, spawns Claude sessions, verifies the output, and commits on success.

```
┌─────────────────────────────────────────────────────────────┐
│                      AGENTIC-LOOP                           │
├──────────────┬──────────────┬──────────────┬───────────────┤
│   CLI        │  Core Loop   │  Vibe-Check  │  Templates    │
│  (Bash)      │  (Bash)      │  (TypeScript)│  (MD/JSON)    │
├──────────────┼──────────────┼──────────────┼───────────────┤
│ bin/         │ ralph/       │ src/         │ templates/    │
│ agentic-     │ loop.sh      │ checks/      │ config/       │
│ loop.sh      │ verify.sh    │ cli.ts       │ PROMPT.md     │
│ ralph.sh     │ utils.sh     │              │ signs.json    │
└──────────────┴──────────────┴──────────────┴───────────────┘
```

**Languages:**
- Bash (core loop, verification, CLI)
- TypeScript (vibe-check static analysis)
- Markdown (slash commands, templates)
- JSON (configuration, PRD, signs)

---

## System Flow

```
User runs: npx agentic-loop run
                │
                ▼
        bin/agentic-loop.sh
                │
                ▼
        ralph/loop.sh ◄─────────────────────┐
                │                           │
                ▼                           │
        Read .ralph/prd.json                │
        Find next story (passes=false)      │
                │                           │
                ▼                           │
        Build prompt (ralph/loop.sh)        │
        - PROMPT.md                         │
        - Story ID                          │
        - Signs                             │
        - Failure context                   │
                │                           │
                ▼                           │
        Spawn Claude CLI                    │
        claude -p --dangerously-skip...     │
                │                           │
                ▼                           │
        ralph/verify.sh                     │
        ├── verify/lint.sh                  │
        ├── verify/tests.sh                 │
        └── testSteps from PRD              │
                │                           │
        ┌───────┴───────┐                   │
        ▼               ▼                   │
      PASS            FAIL                  │
        │               │                   │
        ▼               ▼                   │
   git commit     Save error to             │
   Mark passes    last_failure.txt          │
   =true          ─────────────────────────►┘
        │
        ▼
   Next story or done
```

---

## Entry Points

### bin/agentic-loop.sh

Main CLI entry point. Dispatches to subcommands.

```bash
npx agentic-loop <command> [args]
```

| Command | Handler | Description |
|---------|---------|-------------|
| `setup` | `ralph/setup.sh` | Initialize project |
| `run` | `ralph/loop.sh` | Start autonomous loop |
| `stop` | Sets stop flag | Stop after current story |
| `status` | `ralph/loop.sh` | Show PRD progress |
| `check` | `ralph/verify.sh` | Run verification only |
| `verify` | `ralph/verify.sh` | Verify specific story |
| `test` | `ralph/test.sh` | Run full test suite |
| `signs` | `ralph/signs.sh` | List/add/remove signs |
| `ci` | `ralph/ci.sh` | Generate GitHub Actions |

### bin/ralph.sh

Symlink to `agentic-loop.sh`. Allows `npx ralph run`.

### bin/vibe-check.js

Standalone vibe-check runner. Calls TypeScript checks.

```bash
npx vibe-check [path] [--json]
```

---

## Core Loop

### ralph/loop.sh

Main orchestrator. Key functions:

| Function | Purpose |
|----------|---------|
| `run_loop()` | Main loop - iterate through stories |
| `process_story()` | Handle single story execution |
| `build_prompt()` | Assemble prompt for Claude |
| `run_claude()` | Spawn Claude CLI with prompt |
| `handle_result()` | Process pass/fail, commit if pass |

**Session continuity:** First story uses fresh session. Subsequent stories use `--continue` to preserve context.

```bash
# First story
echo "$prompt" | claude -p --dangerously-skip-permissions

# Subsequent stories
echo "$delta_prompt" | claude --continue -p --dangerously-skip-permissions
```

### ralph/utils.sh

Shared utilities sourced by all scripts.

| Function | Purpose |
|----------|---------|
| `get_config()` | Read from config.json with default |
| `log_progress()` | Write to progress.txt |
| `create_temp_file()` | Create temp file with cleanup |
| `safe_exec()` | Execute command with timeout |
| `print_success/error()` | Colored output |

**Constants:**
```bash
RALPH_DIR=".ralph"
MAX_LOG_LINES=50
DEFAULT_TIMEOUT_SECONDS=120
```

---

## Verification Pipeline

### ralph/verify.sh

Orchestrates verification steps in order.

```bash
run_verification() {
    verify_lint || return 1      # Build, lint, typecheck
    verify_tests || return 1     # Unit tests
    verify_prd_criteria || return 1  # testSteps from PRD
}
```

### ralph/verify/lint.sh

Build and lint checks.

| Function | What it runs |
|----------|--------------|
| `run_auto_fix()` | `eslint --fix`, `ruff --fix` |
| `run_build()` | `npm run build`, `cargo build` |
| `run_lint()` | `npm run lint`, `ruff check` |
| `run_typecheck()` | `tsc --noEmit`, `mypy` |

### ralph/verify/tests.sh

Test execution and PRD testSteps.

| Function | Purpose |
|----------|---------|
| `run_unit_tests()` | Auto-detect and run test command |
| `verify_test_files_exist()` | Check new code has tests |
| `verify_prd_criteria()` | Execute story.testSteps[] |
| `_expand_config_vars()` | Expand `{config.urls.backend}` |

**URL Expansion:** testSteps can use `{config.urls.backend}` which gets expanded from config.json before execution.

---

## Prompt Assembly

### build_prompt() in ralph/loop.sh

Assembles the prompt sent to Claude.

```
┌─────────────────────────────────────┐
│ templates/PROMPT.md                 │  ← 7-step framework
├─────────────────────────────────────┤
│ ## Current Story: TASK-001          │  ← Story ID only
├─────────────────────────────────────┤
│ ## Previous Iteration Failed        │  ← If retrying
│ [error output]                      │
├─────────────────────────────────────┤
│ ## Signs                            │  ← From signs.json
│ - [backend] Use camelCase...        │
└─────────────────────────────────────┘
```

**Lean prompt model:** Claude reads full story details from prd.json during Orient step rather than receiving them in the prompt.

### templates/PROMPT.md

7-step framework Claude follows:

1. **Orient** - Read prd.json, CLAUDE.md, contextFiles
2. **Check for Failures** - Read last_failure.txt
3. **Read Learned Patterns** - Read signs.json
4. **Verify Prerequisites** - Check servers running
5. **Implement** - Write code following story specs
6. **Verify** - Run testSteps, browser checks
7. **End Clean** - Update progress.txt, clean up

---

## Slash Commands

Located in `.claude/commands/`. Claude reads these when user types `/command`.

### Command Files

| File | Command | Purpose |
|------|---------|---------|
| `idea.md` | `/idea` | Brainstorm → idea file → calls /prd |
| `prd.md` | `/prd` | Generate PRD from idea file |
| `review.md` | `/review` | Security-focused code review |
| `vibe-check.md` | `/vibe-check` | Code quality audit |
| `sign.md` | `/sign` | Add learned pattern |
| `explain.md` | `/explain` | Explain code line by line |
| `styleguide.md` | `/styleguide` | Generate UI component reference |
| `my-dna.md` | `/my-dna` | Set personal preferences |
| `tour.md` | `/tour` | Interactive walkthrough |

### /idea → /prd Flow

`/idea` handles brainstorming and creates `docs/ideas/{feature}.md`, then delegates to `/prd` for PRD generation. Single source of truth for PRD schema is in `prd.md`.

---

## Claude Code Hooks

Located in `ralph/hooks/`. Installed to `.ralph/hooks/` during setup.

### Hook Types

**PreToolUse** - Run before Claude uses a tool. Can block.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `protect-prd.sh` | Edit, Write | Block marking passes=true |

**PostToolUse** - Run after Claude uses a tool. Can warn.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `warn-debug.sh` | Edit, Write | Warn on console.log |
| `warn-secrets.sh` | Edit, Write | Warn on API keys |
| `warn-urls.sh` | Edit, Write | Warn on localhost URLs |
| `warn-empty-catch.sh` | Edit, Write | Warn on empty catch |
| `log-tools.sh` | * | Log all tool usage |

### Hook Protocol

Hooks receive JSON on stdin:
```json
{
  "tool_name": "Edit",
  "tool_input": {"file_path": "...", "new_string": "..."}
}
```

Output:
```json
{"continue": true}                     // Allow
{"continue": true, "message": "..."}   // Allow with warning
// Exit code 2 = Block
```

---

## Vibe-Check Engine

TypeScript-based static analysis tool.

### Source Structure

```
src/
├── cli.ts              # CLI entry point
├── index.ts            # Programmatic API
├── checks/
│   ├── index.ts        # Check registry
│   ├── check-secrets.ts
│   ├── check-debug-statements.ts
│   ├── check-hardcoded-urls.ts
│   ├── check-empty-catch.ts
│   ├── check-any-types.ts
│   └── ... (16 checks total)
└── utils/
    ├── file-reader.ts  # File parsing
    ├── patterns.ts     # Regex patterns
    ├── reporters.ts    # Output formatting
    └── types.ts        # TypeScript types
```

### Check Interface

Each check implements:

```typescript
interface Check {
  name: string;
  description: string;
  run(files: FileContent[]): CheckResult[];
}

interface CheckResult {
  file: string;
  line: number;
  message: string;
  severity: 'error' | 'warning';
  code: string;
}
```

### Available Checks

| Check | Severity | What it catches |
|-------|----------|-----------------|
| `check-secrets` | error | API keys, passwords, tokens |
| `check-hardcoded-urls` | error | localhost URLs |
| `check-debug-statements` | warning | console.log, print() |
| `check-empty-catch` | warning | Empty catch blocks |
| `check-any-types` | warning | TypeScript `any` |
| `check-todo-fixme` | warning | TODO/FIXME comments |
| `check-unsafe-html` | error | innerHTML with user data |
| `check-function-length` | warning | Functions > 50 lines |
| `check-deep-nesting` | warning | Nesting > 4 levels |

---

## Configuration

### .ralph/config.json

Project-specific settings.

```json
{
  "directories": {
    "frontend": "apps/web",
    "backend": "apps/api"
  },
  "urls": {
    "frontend": "http://localhost:3000",
    "backend": "http://localhost:8000"
  },
  "checks": {
    "build": true,
    "lint": true,
    "test": true,
    "testCommand": "pytest -x -q",
    "requireTests": false
  },
  "maxIterations": 20,
  "maxSessionSeconds": 600
}
```

### .claude/settings.json

Claude Code hook configuration.

```json
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit|Write", "command": ".ralph/hooks/protect-prd.sh"}
    ],
    "PostToolUse": [
      {"matcher": "Edit|Write", "command": ".ralph/hooks/warn-debug.sh"}
    ]
  }
}
```

---

## Templates

### templates/config/

Project-type specific configs copied during setup.

| Template | For |
|----------|-----|
| `node.json` | Node.js/TypeScript projects |
| `python.json` | Python projects |
| `go.json` | Go projects |
| `rust.json` | Rust projects |
| `fullstack.json` | Frontend + backend |
| `minimal.json` | Minimal config |

### templates/examples/

Example CLAUDE.md files for different stacks:

- `CLAUDE-react.md` - React/TypeScript
- `CLAUDE-node.md` - Node.js backend
- `CLAUDE-fastapi.md` - Python FastAPI
- `CLAUDE-django.md` - Python Django
- `CLAUDE-fullstack.md` - Full stack

### templates/signs.json

Default signs copied to new projects:

```json
{
  "signs": [
    {"pattern": "Never hardcode AI model names", "category": "backend"},
    {"pattern": "Use environment variables for secrets", "category": "general"},
    {"pattern": "Handle loading, error, empty states", "category": "frontend"},
    {"pattern": "Add data-testid for e2e tests", "category": "frontend"},
    {"pattern": "Update tests when removing UI", "category": "testing"}
  ]
}
```

---

## Data Files

### .ralph/prd.json

Current PRD with stories. Schema defined in `.claude/commands/prd.md`.

Key fields:
- `feature` - Name, branch, status
- `techStack` - Auto-detected technologies
- `testing` - TDD approach, tools, coverage
- `globalConstraints` - Rules for all stories
- `stories[]` - Individual tasks with testSteps

### .ralph/signs.json

Learned patterns injected into every prompt.

### .ralph/progress.txt

Activity log with timestamps.

```
2024-01-15 10:30:00 | START  | TASK-001 | Create dashboard
2024-01-15 10:41:00 | PASS   | TASK-001 | All checks passed
```

### .ralph/last_failure.txt

Error output from last failed verification. Included in retry prompt.

### .ralph/tool-log.txt

Log of all Claude tool usage (if log-tools.sh hook enabled).
