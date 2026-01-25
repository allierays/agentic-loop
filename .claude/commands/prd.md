---
description: Generate an executable PRD for Ralph from an idea file or description.
---

# /prd - Generate PRD for Ralph

Generate executable stories for Ralph's autonomous development loop.

**CRITICAL: This command does NOT write code. It produces `.ralph/prd.json` only.**

## User Input

```text
$ARGUMENTS
```

## Workflow

### Step 1: Determine Input Type

**If `$ARGUMENTS` is empty:**
1. Check for idea files:
   ```bash
   ls docs/ideas/*.md 2>/dev/null || echo "No ideas found"
   ```
2. Ask: "Would you like to:
   - Convert an idea file (e.g., `/prd auth` for `docs/ideas/auth.md`)
   - Describe a feature directly (e.g., `/prd 'Add user logout button'`)"

**If `$ARGUMENTS` looks like a file reference** (no spaces, matches `docs/ideas/*.md`):
- If it's a full path, use it directly
- If it's just a name like `content-engine`, look for `docs/ideas/content-engine.md`
- Proceed to "Read and Understand the Idea"

**If `$ARGUMENTS` is a description** (has spaces, is a sentence):
- This is the **quick PRD flow** - no `docs/ideas/` file created
- Good for small features that don't need documentation
- Skip to "Confirm Understanding" below

### Step 2a: Read and Understand the Idea (from file)

Read the idea file and summarize:

Say: "I've read `{path}`. Here's my understanding:

**Feature:** {name}
**Problem:** {one line}
**Solution:** {one line}
**Scope:** {key items}

I'll now split this into {N} stories for Ralph. Continue?"

**STOP and wait for user confirmation.**

### Step 2b: Confirm Understanding (from description)

If working from a direct description, first explore the codebase briefly:
```bash
ls -la src/ app/ 2>/dev/null | head -20
cat package.json 2>/dev/null | jq '{name, dependencies}' || true
cat pyproject.toml 2>/dev/null | head -20 || true
```

Then say: "I'll create a PRD for: **{description}**

Before I generate stories, quick questions:
1. **Type:** Frontend, backend, or fullstack?
2. **Scale:** Any specific limits (users, items, rate limits)?
3. **Anything else** I should know?

(Or say 'go' to proceed with defaults)"

**STOP and wait for user input** (can be brief or 'go').

### Step 3: Check for Existing PRD

```bash
cat .ralph/prd.json 2>/dev/null
```

If it exists, read it and say:
"`.ralph/prd.json` exists with {N} stories ({M} completed, {P} pending).

Options:
- **'append'** - Add new stories to the existing PRD (recommended)
- **'overwrite'** - Replace it entirely
- **'cancel'** - Stop here"

**STOP and wait for user choice.**

If user chooses **'append'**:
- Find highest existing story number (ignore prefix - could be US-005 or TASK-005)
- **Always use TASK- prefix** for new stories (e.g., if highest is US-005 or TASK-005, new stories start at TASK-006)
- New stories will be added after existing ones

### Step 4: Split into Stories

Break the idea into small, executable stories:

- Each story completable in one Claude session (~10-15 min)
- Max 3-4 acceptance criteria per story
- Order by dependency
- Max 10 stories (suggest phases if more needed)
- If appending, start IDs from the next available number

### Step 5: Write PRD

1. Ensure .ralph directory exists and allow PRD edit:
   ```bash
   mkdir -p .ralph && touch .ralph/.prd-edit-allowed
   ```

2. Write to `.ralph/prd.json`:
   - If **overwriting** or no existing PRD: Create new file with full structure
   - If **appending**: Read existing JSON, add new stories to the `stories` array, update `metadata.estimatedStories` count, write back

3. Say: "I've {created|updated} the PRD with {N} stories ({X} new).

   Review `.ralph/prd.json` and let me know:
   - **'approved'** - Ready for `ralph run`
   - **'edit [changes]'** - Tell me what to change
   - Or edit the JSON directly and say **'done'**"

**STOP and wait for user response.**

### Step 6: Final Instructions

Once approved, say:

"PRD is ready!

**Source:** `{idea-file-path}`
**PRD:** `.ralph/prd.json` ({N} stories)

To start autonomous development:
```bash
ralph run
```

Ralph will work through each story, running tests and committing as it goes."

**DO NOT start implementing code.**

---

## Complete PRD JSON Schema

```json
{
  "feature": {
    "name": "Feature Name",
    "ideaFile": "docs/ideas/{feature-name}.md",
    "branch": "feature/{feature-name}",
    "status": "pending"
  },

  "originalContext": "docs/ideas/{feature-name}.md",

  "techStack": {
    "frontend": "React 18 + TypeScript",
    "backend": "FastAPI + Python 3.11",
    "database": "PostgreSQL",
    "testing": "Vitest + Playwright"
  },

  "devServer": {
    "command": "npm run dev",
    "url": "http://localhost:3000",
    "backend": "http://localhost:8000"
  },

  "architecture": {
    "frontend": "src/components",
    "backend": "src/api",
    "doNotCreate": ["new database tables without migration"]
  },

  "globalConstraints": [
    "All API calls must have error handling",
    "No console.log in production code",
    "Use existing UI components from src/components/ui"
  ],

  "testUsers": {
    "admin": {"email": "admin@test.com", "password": "test123"},
    "user": {"email": "user@test.com", "password": "test123"}
  },

  "metadata": {
    "createdAt": "ISO timestamp",
    "estimatedStories": 5,
    "complexity": "low|medium|high"
  },

  "stories": [
    {
      "id": "TASK-001",
      "type": "frontend|backend|fullstack",
      "title": "Short description",
      "priority": 1,
      "passes": false,

      "files": {
        "create": ["paths to new files"],
        "modify": ["paths to existing files"],
        "reuse": ["existing files to import from"]
      },

      "acceptanceCriteria": [
        "What it should do"
      ],

      "errorHandling": [
        "What happens when things fail"
      ],

      "testSteps": [
        "Executable shell commands - see examples below"
      ],

      "testUrl": "http://localhost:3000/feature-page",

      "mcp": ["playwright", "devtools"],

      "contextFiles": [
        "docs/ideas/feature.md",
        "src/styles/styleguide.html"
      ],

      "skills": [
        {"name": "styleguide", "usage": "Reference for UI components"},
        {"name": "vibe-check", "usage": "Run after implementation"}
      ],

      "apiContract": {
        "endpoint": "GET /api/resource",
        "response": {"field": "type"}
      },

      "prerequisites": [
        "Backend server running",
        "Database seeded"
      ],

      "notes": "Human guidance - preferences, warnings, tips",

      "scale": "small|medium|large",

      "architecture": {
        "pattern": "React Query for data fetching",
        "constraints": ["No Redux"]
      },

      "dependsOn": []
    }
  ]
}
```

---

## Field Reference

### PRD-Level Fields

| Field | Required | Description |
|-------|----------|-------------|
| `feature` | Yes | Feature name, branch, status |
| `originalContext` | Yes | Path to idea file (Claude reads this for full context) |
| `techStack` | Yes | Technologies in use (helps Claude make correct choices) |
| `devServer` | Yes | How to run the app (command, URLs) |
| `architecture` | Yes | Directory structure, patterns, constraints |
| `globalConstraints` | Yes | Rules that apply to ALL stories |
| `testUsers` | No | Test accounts for auth flows |
| `metadata` | Yes | Created date, complexity estimate |

### Story-Level Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique ID (TASK-001, TASK-002, etc.) |
| `type` | Yes | frontend, backend, or fullstack |
| `title` | Yes | Short description |
| `priority` | No | Order of importance (1 = highest) |
| `passes` | Yes | Always starts as `false` |
| `files` | Yes | create, modify, reuse arrays |
| `acceptanceCriteria` | Yes | What must be true when done |
| `errorHandling` | Yes | How to handle failures |
| `testSteps` | Yes | Executable shell commands |
| `testUrl` | Frontend | URL to verify the feature |
| `mcp` | Frontend | MCP tools for verification |
| `contextFiles` | No | Files Claude should read (idea files, styleguides) |
| `skills` | No | Relevant skills with usage hints |
| `apiContract` | Fullstack | Expected request/response |
| `prerequisites` | No | What must be running/ready |
| `notes` | No | Human guidance for Claude |
| `scale` | No | small, medium, large |
| `architecture` | No | Story-specific patterns/constraints |
| `dependsOn` | No | Story IDs that must complete first |

---

## MCP Tools

Specify which MCP tools Claude should use for verification:

| Tool | When to Use |
|------|-------------|
| `playwright` | UI testing, screenshots, form interactions, a11y |
| `devtools` | Console errors, network inspection, DOM debugging |
| `postgres` | Database verification (future) |

**Frontend stories** default to `["playwright", "devtools"]`.
**Backend-only stories** can use `[]` or omit.

---

## Skills Reference

Point Claude to relevant skills for guidance:

| Skill | When to Use |
|-------|-------------|
| `styleguide` | Frontend stories - reference UI components |
| `vibe-check` | Any story - check for AI anti-patterns after |
| `review` | Security-sensitive stories - OWASP checks |
| `explain` | Complex logic - document decisions |

Example:
```json
"skills": [
  {"name": "styleguide", "usage": "Use existing Card, Button components"},
  {"name": "vibe-check", "usage": "Run after implementation to catch issues"}
]
```

---

## Test Steps - CRITICAL

**Test steps MUST be executable shell commands.** Ralph runs them with bash.

### Good Test Steps (executable)
```json
"testSteps": [
  "curl -s http://localhost:3000/api/health | jq -e '.status == \"ok\"'",
  "test -f frontend/src/components/Button.tsx",
  "grep -q 'export function Button' frontend/src/components/Button.tsx",
  "cd frontend && npx tsc --noEmit",
  "npx playwright test tests/e2e/dashboard.spec.ts",
  "cd frontend && npm test -- --testPathPattern=Button.test.tsx"
]
```

### Bad Test Steps (will fail)
```json
"testSteps": [
  "Visit http://localhost:3000/dashboard",
  "User can see the dashboard",
  "Click the submit button"
]
```

**If a step can't be automated**, put it in `acceptanceCriteria` instead. Claude will verify it visually using MCP tools.

---

## Context Files

Use `contextFiles` to point Claude to important reference material:

```json
"contextFiles": [
  "docs/ideas/dashboard.md",
  "src/styles/styleguide.html",
  "docs/api-spec.md"
]
```

This is where ASCII mockups, design specs, and detailed requirements live. Claude reads these during the Orient step.

---

## Guidelines

- **Keep stories small** - Max 3-4 acceptance criteria (~1000 tokens)
- **Order by dependency** - Foundation stories first
- **Specify files explicitly** - Max 3-4 files per story
- **Define error handling** - Every story specifies failure behavior
- **Include contextFiles** - Point to idea files with full context (ASCII art, mockups)
- **Add relevant skills** - Help Claude find the right patterns

### UI Stories Must Include
- `testUrl` - Where to verify
- `mcp: ["playwright", "devtools"]` - Browser tools
- Acceptance criteria for: page loads, elements render, mobile works

### API Stories Must Include
- `apiContract` - Expected request/response
- `errorHandling` - What happens on 400, 401, 500, etc.
- `testSteps` with curl commands to verify endpoints
