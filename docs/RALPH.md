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
│  3. Spawn Claude with prompt → claude -p                    │
│  4. Run verification pipeline                               │
│  5. Pass? → commit, next story                              │
│     Fail? → save error, retry same story                    │
│  6. Repeat until all stories pass or max iterations         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Data Sources

Ralph reads from multiple files to give Claude full context:

| File | Purpose |
|------|---------|
| `.ralph/prd.json` | Stories to implement (the work) |
| `PROMPT.md` | Base instructions for Claude (how to code) |
| `.ralph/config.json` | Project settings (URLs, commands, paths) |
| `.ralph/signs.json` | Learned patterns from past runs |
| `~/.claude/DNA.md` | Your personal coding preferences |
| `.ralph/last_failure.txt` | Why the last attempt failed |

### prd.json (The Work)

The PRD contains everything about what to build:

```json
{
  "feature": {
    "name": "User Dashboard",
    "description": "A dashboard showing user activity"
  },
  "stories": [
    {
      "id": "TASK-001",
      "title": "Create dashboard layout",
      "description": "Build the main dashboard container...",
      "acceptanceCriteria": ["Shows user name", "Responsive layout"],
      "testUrl": "/dashboard",
      "testSteps": ["npm test -- dashboard"],
      "e2e": true,
      "passes": false
    }
  ],
  "architecture": {
    "frontend": "frontend/src/components",
    "doNotCreate": ["new API routes without backend story"]
  }
}
```

Key fields:
- `stories[].passes` - Ralph tracks completion state here
- `stories[].testUrl` - URL to verify in browser after implementation
- `stories[].testSteps` - Commands to run for verification
- `stories[].e2e` - Whether Playwright e2e test is required
- `architecture` - Where to put files, what to avoid

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

## The Prompt Assembly

When Ralph starts a story, it builds a prompt by combining:

```
┌────────────────────────────────────────────────────────────┐
│ PROMPT.md                        (base instructions)       │
├────────────────────────────────────────────────────────────┤
│ ## Current Story                                           │
│ {story JSON from prd.json}                                 │
├────────────────────────────────────────────────────────────┤
│ ## File Guidance (if story has .files)                     │
│ Create: [...], Modify: [...], Reuse: [...]                 │
├────────────────────────────────────────────────────────────┤
│ ## Styleguide (if frontend + configured)                   │
│ FIRST: Read styleguide at docs/styleguide.html             │
├────────────────────────────────────────────────────────────┤
│ ## Feature Context                                         │
│ {feature name, metadata from prd.json}                     │
├────────────────────────────────────────────────────────────┤
│ ## Architecture Guidelines (if defined)                    │
│ {architecture rules from prd.json}                         │
├────────────────────────────────────────────────────────────┤
│ ## Previous Iteration Failed (if retrying)                 │
│ {error output from last_failure.txt}                       │
├────────────────────────────────────────────────────────────┤
│ ## Signs (Learned Patterns)                                │
│ - [backend] Always use camelCase...                        │
│ - [frontend] Import Button from...                         │
├────────────────────────────────────────────────────────────┤
│ ## Developer DNA (if ~/.claude/DNA.md exists)              │
│ {your personal preferences}                                │
└────────────────────────────────────────────────────────────┘
```

This assembled prompt is piped to Claude:
```bash
cat assembled_prompt.md | claude -p --dangerously-skip-permissions
```

## Verification Pipeline

After Claude finishes, Ralph runs verification:

```
┌─────────────────────────────────────────────────────────────┐
│                   VERIFICATION PIPELINE                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Build Check                                              │
│     └─ npm run build (or configured command)                 │
│                                                              │
│  2. Code Review                                              │
│     └─ Claude reviews diff for security/patterns             │
│                                                              │
│  3. Unit Tests                                               │
│     └─ Runs testSteps from story                             │
│                                                              │
│  4. Playwright E2E (if e2e: true)                            │
│     └─ Runs tests/e2e/{story-id}.spec.ts                     │
│                                                              │
│  5. Browser Validation (if testUrl set)                      │
│     └─ Loads page, checks for console errors,                │
│        network failures, missing elements                    │
│                                                              │
│  6. Custom Test Steps                                        │
│     └─ Any additional commands from testSteps                │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

If any step fails:
1. Error is saved to `.ralph/last_failure.txt`
2. Story stays `passes: false`
3. Ralph retries with failure context in the prompt

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

Now every future story will see this pattern.

## Commands

| Command | What it does |
|---------|--------------|
| `npx ralph run` | Start the loop |
| `npx ralph run --story TASK-001` | Run specific story only |
| `npx ralph run --max 5` | Limit to 5 iterations |
| `npx ralph stop` | Stop after current story |
| `npx ralph status` | Show story progress |
| `npx ralph check` | Run verification without Claude |
| `npx ralph verify TASK-001` | Verify specific story |
| `npx ralph signs` | List learned patterns |
| `npx ralph sign "pattern" category` | Add a pattern |
| `npx ralph unsign "pattern"` | Remove a pattern |
| `npx ralph progress` | Show recent log entries |

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
| `checks.build` | `"npm run build"` | Build command |
| `checks.test` | `"npm test"` | Test command |
| `docker.enabled` | `false` | Run commands in Docker |
| `playwright.enabled` | `true` | Enable e2e tests |
| `styleguide` | `""` | Path to styleguide for frontend stories |
| `maxSessionSeconds` | `600` | Claude session timeout |

## File Structure

```
your-project/
├── .ralph/
│   ├── config.json      # Project settings
│   ├── prd.json         # Current feature PRD
│   ├── signs.json       # Learned patterns
│   ├── progress.txt     # Activity log
│   ├── last_failure.txt # Last error (for retries)
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
3. **Styleguide** - Consistent UI reduces review failures
4. **Atomic stories** - Smaller scope = faster verification
