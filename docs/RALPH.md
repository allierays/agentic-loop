# Ralph: Autonomous Development Loop

Ralph is an autonomous coding agent that implements features from a PRD (Product Requirements Document). It spawns fresh Claude sessions, runs verification, and iterates until all stories pass.

## How Ralph Works

```
┌─────────────────────────────────────────────────────────────┐
│                        RALPH LOOP                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Read prd.json → find next story where passes=false      │
│  2. Build prompt (story + context + failures + signs)       │
│  3. Run Claude (first story fresh, subsequent --continue)   │
│  4. Run verification pipeline                               │
│  5. Pass? → commit, next story                              │
│     Fail? → save error, retry same story                    │
│  6. Repeat until all stories pass or max iterations         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Session Continuity

Ralph maintains Claude session context across stories within a single run:
- **First story**: Fresh session with full prompt
- **Subsequent stories**: `--continue` with delta prompt (just new story context)
- **Retries**: Same session, remembers previous attempts

This means Claude remembers what it built in TASK-001 when working on TASK-002.

## Data Sources

Ralph reads from multiple files to give Claude full context:

| File | Purpose |
|------|---------|
| `.ralph/prd.json` | Stories to implement (the work) |
| `PROMPT.md` | Base instructions for Claude (how to code) |
| `.ralph/config.json` | Project settings (URLs, commands, paths) |
| `.ralph/signs.json` | Learned patterns from past runs |
| `~/.claude/DNA.md` | Your personal coding preferences |
| `.ralph/last_failure.txt` | Accumulated failure history across retries |

### prd.json (The Work)

The PRD is the **single source of truth** - everything Claude needs is here.

**See full example:** [`templates/prd-example.json`](../templates/prd-example.json)

```json
{
  "feature": {
    "name": "User Dashboard",
    "branch": "feature/user-dashboard",
    "status": "pending"
  },
  "originalContext": "docs/ideas/dashboard.md",
  "techStack": {
    "frontend": "React 19, TypeScript, Vite",
    "backend": "Python, FastAPI"
  },
  "testing": {
    "approach": "TDD",
    "unit": {"frontend": "vitest", "backend": "pytest"},
    "e2e": "playwright"
  },
  "globalConstraints": [
    "All API calls must have error handling",
    "No console.log in production code"
  ],
  "stories": [
    {
      "id": "TASK-001",
      "type": "frontend",
      "title": "Create dashboard layout",
      "passes": false,
      "files": {
        "create": ["src/components/Dashboard.tsx"],
        "modify": ["src/App.tsx"]
      },
      "acceptanceCriteria": [
        "Shows user name in header",
        "Responsive layout"
      ],
      "testing": {
        "types": ["unit", "e2e"],
        "approach": "TDD",
        "files": {
          "unit": ["src/components/Dashboard.test.tsx"],
          "e2e": ["tests/e2e/dashboard.spec.ts"]
        }
      },
      "testSteps": [
        "npx tsc --noEmit",
        "npm test -- Dashboard",
        "npx playwright test tests/e2e/dashboard.spec.ts"
      ],
      "testUrl": "{config.urls.frontend}/dashboard",
      "mcp": ["playwright", "devtools"],
      "contextFiles": ["docs/ideas/dashboard.md"],
      "skills": [
        {"name": "styleguide", "usage": "Reference for UI components"}
      ]
    }
  ]
}
```

Key fields:
- `type` - Story type: `frontend` or `backend` (keep stories atomic)
- `testing` - Test types, approach (TDD/test-after), files to create
- `testSteps` - Executable shell commands (use `{config.urls.backend}` for URLs)
- `testUrl` - URL to verify (use `{config.urls.frontend}`)
- `contextFiles` - Idea files, styleguides Claude should read
- `skills` - Relevant skills with usage hints
- `mcp` - MCP tools for browser verification

**URLs use placeholders** like `{config.urls.backend}` - Ralph expands these from `.ralph/config.json` before running testSteps.

### PROMPT.md (How to Code)

Base instructions that apply to every story:

```markdown
# Project Coding Guide

## Stack
- Next.js 14 with App Router
- TypeScript strict mode
- Tailwind CSS

## Patterns
- Use server components by default
- Client components only for interactivity
- All API routes in app/api/

## Testing
- Jest for unit tests
- Playwright for e2e
```

### config.json (Project Settings)

Project-specific configuration:

```json
{
  "paths": {
    "frontend": "frontend",
    "backend": "backend"
  },
  "urls": {
    "frontend": "http://localhost:3000",
    "backend": "http://localhost:8000"
  },
  "commands": {
    "dev": "npm run dev"
  },
  "checks": {
    "build": "npm run build",
    "test": "npm test"
  },
  "docker": {
    "enabled": true
  },
  "playwright": {
    "enabled": true
  },
  "styleguide": "docs/styleguide.html"
}
```

#### FastMCP Projects

For FastMCP (MCP server) projects, Ralph auto-detects:

- **Server module** from `[project.scripts]` in pyproject.toml
- **MCP port** from `.env` or docker-compose.yml
- **Subprojects** (directories with package.json like UI builders)

```json
{
  "projectType": "fastmcp",
  "mcp": {
    "serverModule": "gopa",
    "transport": "stdio",
    "tools": [],
    "resources": [],
    "prompts": []
  },
  "commands": {
    "dev": "python -m gopa.server",
    "lint": "ruff check src/",
    "test": "pytest"
  },
  "api": {
    "baseUrl": "http://localhost:9847"
  },
  "checks": {
    "lint": true,
    "typecheck": true,
    "test": true,
    "fastmcp": true
  },
  "subprojects": {
    "diagram-builder": {
      "path": "diagram-builder",
      "commands": {
        "lint": "npm run lint",
        "build": "npm run build"
      }
    }
  }
}
```

### signs.json (Learned Patterns)

Patterns Ralph learned from failures:

```json
{
  "signs": [
    {
      "id": "sign-001",
      "pattern": "Always use camelCase for API response fields",
      "category": "backend",
      "learnedFrom": "TASK-003"
    },
    {
      "id": "sign-002",
      "pattern": "Import Button from @/components/ui, not shadcn directly",
      "category": "frontend",
      "learnedFrom": "TASK-007"
    }
  ]
}
```

Add signs manually when you notice patterns:
```bash
npx ralph sign "Always run migrations before seeding" backend
```

## The Lean Prompt Model

Ralph uses a **lean prompt** approach inspired by [Anthropic's guidance](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents):

```
┌─────────────────────────────────────────────────────────────────┐
│   PROMPT.md = HOW to work (7-step framework, ~150 lines)       │
│   prd.json  = WHAT to build (all context per story)            │
└─────────────────────────────────────────────────────────────────┘
```

Instead of injecting thousands of tokens, Claude **reads files during orientation**:

| Injected into Prompt | Claude Reads During Orient |
|---------------------|---------------------------|
| PROMPT.md (7-step framework) | `.ralph/prd.json` (full story details) |
| Story ID | `story.contextFiles[]` (idea files, styleguides) |
| Signs (learned patterns) | `CLAUDE.md` (project conventions) |
| Failure context (if retrying) | `~/.claude/DNA.md` (personal preferences) |

The prompt is piped to Claude:
```bash
echo "$prompt" | claude -p --dangerously-skip-permissions
```

This approach gives Claude better comprehension because it actively reads context rather than passively receiving it.

## Verification Pipeline

Ralph has two verification phases:

### 1. PRD Validation (prd-check.sh) - Before Loop

Runs once at startup to catch issues early:

```
┌─────────────────────────────────────────────────────────────┐
│                   PRD VALIDATION                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ✓ Valid JSON structure                                      │
│  ✓ Has feature name and stories                              │
│  ✓ testSteps are executable commands (not prose)             │
│  ✓ Backend stories have curl tests + apiContract             │
│  ✓ Frontend stories have testUrl + contextFiles              │
│  ✓ Auth stories have security criteria                       │
│  ✓ List endpoints have pagination criteria                   │
│                                                              │
│  Issues found? → Claude auto-fixes them                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2. Code Verification (code-check.sh) - After Claude Writes

Runs after each story:

```
┌─────────────────────────────────────────────────────────────┐
│                   CODE VERIFICATION                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Lint Checks                                              │
│     └─ Build, lint, typecheck from config                    │
│                                                              │
│  2. Unit Tests                                               │
│     └─ Runs test command from config                         │
│                                                              │
│  3. PRD Test Steps                                           │
│     └─ Custom commands from testSteps                        │
│                                                              │
│  4. API Smoke Test                                           │
│     └─ Health endpoint check                                 │
│                                                              │
│  5. Frontend Smoke Test                                      │
│     └─ Page loads without errors                             │
│                                                              │
│  Browser verification is done BY CLAUDE using MCP tools:     │
│  - Playwright MCP for automation & testing                   │
│  - Chrome DevTools MCP for debugging                         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Failure Accumulation

When verification fails, errors are **accumulated across retries** (not just the last failure):

```
=== Attempt 1 failed for TASK-001 ===
ERROR: relation "users" does not exist
---
=== Attempt 2 failed for TASK-001 ===
ERROR: relation "users" does not exist
---
```

This helps Claude identify patterns like "same error 3 times = structural issue, try something different."

If any step fails:
1. Error is appended to `.ralph/last_failure.txt`
2. Story stays `passes: false`
3. Ralph retries with accumulated failure context in the prompt
4. After 15 failures (configurable), story is skipped with explanation

## Iteration and Learning

Ralph learns from failures:

```
Iteration 1: Claude implements story
             → Build fails: "Module not found: @/lib/utils"
             → Error saved to last_failure.txt

Iteration 2: Prompt includes "Previous Iteration Failed" section
             → Claude reads error, fixes import
             → Build passes, tests pass
             → Story marked passes: true
             → Commit: "feat(TASK-001): Create dashboard layout"

Next story...
```

For persistent issues, add a sign:
```bash
npx ralph sign "Import from @/lib/utils not @/utils" frontend
```

Or use the `/sign` slash command during a Claude session to add patterns interactively.

Now every future story will see this pattern.

## Commands

| Command | What it does |
|---------|--------------|
| `npx agentic-loop run` | Start the loop |
| `npx agentic-loop run --story TASK-001` | Run specific story only |
| `npx agentic-loop run --max 5` | Limit to 5 iterations |
| `npx agentic-loop stop` | Stop after current story |
| `npx agentic-loop status` | Show story progress |
| `npx agentic-loop check` | Run verification without Claude |
| `npx agentic-loop verify TASK-001` | Verify specific story |
| `npx agentic-loop test` | Run full test suite + PRD tests (for nightly CI) |
| `npx agentic-loop test prd` | Run only PRD testSteps |
| `npx agentic-loop coverage` | Generate test coverage report |
| `npx agentic-loop ci` | Install GitHub Actions workflows |
| `npx agentic-loop signs` | List learned patterns |
| `npx agentic-loop sign "pattern" category` | Add a pattern |
| `npx agentic-loop unsign "pattern"` | Remove a pattern |
| `npx agentic-loop progress` | Show recent log entries |

## Configuration Reference

### .ralph/config.json

```json
{
  "paths": {
    "frontend": "frontend",
    "backend": "backend"
  },
  "urls": {
    "frontend": "http://localhost:3000",
    "backend": "http://localhost:8000",
    "testUrlBase": "http://localhost:3000"
  },
  "commands": {
    "dev": "npm run dev"
  },
  "checks": {
    "build": "npm run build",
    "test": "npm test",
    "lint": "npm run lint"
  },
  "docker": {
    "enabled": false
  },
  "playwright": {
    "enabled": true,
    "testDir": "tests/e2e"
  },
  "styleguide": "docs/styleguide.html",
  "maxSessionSeconds": 600,
  "auth": {
    "testUser": "test@example.com",
    "testPassword": "testpass123"
  }
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `paths.frontend` | `"."` | Frontend source directory |
| `paths.backend` | `""` | Backend source directory |
| `urls.frontend` | `"http://localhost:3000"` | Frontend dev server URL |
| `urls.testUrlBase` | (frontend URL) | Base URL for relative testUrl paths |

### URL Expansion

Use `{config.urls.backend}` and `{config.urls.frontend}` in testSteps. Ralph expands these before running:

```json
// In prd.json
"testSteps": ["curl -s {config.urls.backend}/users | jq '.data'"]

// Ralph expands to
"testSteps": ["curl -s http://localhost:8000/users | jq '.data'"]
```
| `checks.build` | `"npm run build"` | Build command |
| `checks.test` | `true` | Run tests (`true`, `false`, or `"final"`) |
| `checks.testCommand` | (auto-detect) | Custom test command |
| `checks.requireTests` | `true` | Warn if no test directory found |
| `tests.directory` | (auto-detect) | Where tests live (`tests/`, `test/`, `src/`, etc.) |
| `tests.patterns` | (auto-detect) | Test file patterns (`*.test.ts`, `*_test.py`, etc.) |
| `docker.enabled` | `false` | Run commands in Docker |
| `playwright.enabled` | `true` | Enable e2e tests |
| `styleguide` | `""` | Path to styleguide for frontend stories |
| `maxSessionSeconds` | `600` | Claude session timeout |

### Test Detection

Ralph auto-detects your test setup during `init`:

```json
{
  "tests": {
    "directory": "tests",
    "patterns": "*.test.ts,*.spec.ts,*_test.py"
  },
  "checks": {
    "requireTests": true
  }
}
```

If no tests are found, Ralph warns you. To silence the warning:
```json
{ "checks": { "requireTests": false } }
```

### Test Modes

The `checks.test` field supports:
- `true` - Run tests on every story (default)
- `false` - Skip tests entirely
- `"final"` - Only run tests on the last story (faster iteration)

## File Structure

```
your-project/
├── .ralph/
│   ├── config.json      # Project settings
│   ├── prd.json         # Current feature PRD
│   ├── signs.json       # Learned patterns
│   ├── progress.txt     # Activity log
│   ├── last_failure.txt # Accumulated errors (for retries)
│   └── archive/         # Completed PRDs
├── PROMPT.md            # Base coding instructions
├── CLAUDE.md            # Project context for Claude
└── docs/
    └── ideas/           # Documented feature ideas
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Invalid API key" | Remove `ANTHROPIC_API_KEY` from `.env` - Ralph uses Claude Max subscription |
| "jq: command not found" | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |
| Browser verification skipped | Install Playwright: `npm install playwright && npx playwright install chromium` |
| "pre-commit: command not found" | Install pre-commit: `pip install pre-commit` then `pre-commit install` |
| Story keeps failing | Check `.ralph/last_failure.txt` for the error |
| Claude times out | Increase `maxSessionSeconds` in config.json |

## Tips

### Writing Good PRDs

The `/idea` command generates PRDs, but you can improve them:

1. **Atomic stories** - Each story should be independently testable
2. **Clear acceptance criteria** - Specific, verifiable outcomes
3. **Test URLs** - Include `testUrl` for any visible feature
4. **E2E flag** - Set `e2e: true` for user-facing interactions

### Debugging Failures

```bash
# Check what failed
cat .ralph/last_failure.txt

# See recent activity
npx ralph progress

# Run verification manually
npx ralph verify TASK-001

# Run just the checks (no Claude)
npx ralph check
```

### Performance Tips

1. **Good PROMPT.md** - Clear instructions reduce iterations
2. **Signs** - Teach patterns early to avoid repeated failures
3. **Styleguide** - Consistent UI reduces failures
4. **Atomic stories** - Smaller scope = faster verification
5. **MCP browser tools** - Claude verifies its own work in real-time

## GitHub Actions CI/CD

Ralph can set up GitHub Actions workflows for your project:

```bash
npx agentic-loop ci install
```

This creates two workflows:

| Workflow | Trigger | What it runs |
|----------|---------|--------------|
| `.github/workflows/pr.yml` | Pull requests | Fast lint + typecheck + build |
| `.github/workflows/nightly.yml` | Daily at 3am UTC | Full test suite + PRD testSteps |

### Running Nightly Tests Locally

```bash
npx agentic-loop test        # Full suite + PRD tests
npx agentic-loop test unit   # Just unit tests
npx agentic-loop test prd    # Just PRD testSteps
npx agentic-loop coverage    # Generate coverage report
```
