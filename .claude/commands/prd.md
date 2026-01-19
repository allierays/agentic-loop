---
description: Convert an idea file from docs/ideas into an executable PRD for Ralph.
---

# /prd - Idea to PRD

Convert an existing idea file into executable stories for Ralph.

**CRITICAL: This command does NOT write code. It produces `.ralph/prd.json` only.**

## User Input

```text
$ARGUMENTS
```

## Workflow

### Step 1: Find the Idea File

If `$ARGUMENTS` is empty:
1. List available ideas:
   ```bash
   ls docs/ideas/*.md 2>/dev/null || echo "No ideas found"
   ```
2. Ask: "Which idea would you like to convert to a PRD? (e.g., `content-engine` or full path)"

If `$ARGUMENTS` is provided:
- If it's a full path, use it directly
- If it's just a name like `content-engine`, look for `docs/ideas/content-engine.md`

### Step 2: Read and Understand the Idea

Read the idea file and summarize:

Say: "I've read `{path}`. Here's my understanding:

**Feature:** {name}
**Problem:** {one line}
**Solution:** {one line}
**Scope:** {key items}

I'll now split this into {N} stories for Ralph. Continue?"

**STOP and wait for user confirmation.**

### Step 3: Check for Existing PRD

```bash
cat .ralph/prd.json 2>/dev/null
```

If it exists, read it and say:
"📋 `.ralph/prd.json` exists with {N} stories ({M} completed, {P} pending).

Options:
- **'append'** - Add new stories to the existing PRD (recommended)
- **'overwrite'** - Replace it entirely
- **'cancel'** - Stop here"

**STOP and wait for user choice.**

If user chooses **'append'**:
- Note the highest existing task ID (e.g., if TASK-005 exists, new tasks start at TASK-006)
- New stories will be added after existing ones

### Step 4: Split into Stories

Break the idea into small, executable stories:

- Each story completable in one Claude session (~10-15 min)
- Max 3-4 acceptance criteria per story
- Order by dependency
- Max 10 stories (suggest phases if more needed)
- If appending, start IDs from the next available number

### Step 5: Write PRD

1. Ensure .ralph directory exists:
   ```bash
   mkdir -p .ralph
   ```

2. Write to `.ralph/prd.json`:
   - If **overwriting** or no existing PRD: Create new file with full structure
   - If **appending**: Read existing JSON, add new stories to the `stories` array, update `metadata.estimatedStories` count, write back

3. Open for review:
   ```bash
   open -a TextEdit .ralph/prd.json
   ```

4. Say: "I've {created|updated} the PRD with {N} stories ({X} new).

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

## PRD JSON Structure

```json
{
  "feature": {
    "name": "Feature Name",
    "ideaFile": "docs/ideas/{feature-name}.md",
    "branch": "feature/{feature-name}",
    "status": "pending"
  },
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

      "acceptanceCriteria": [
        "What it should do"
      ],

      "errorHandling": [
        "What happens when things fail"
      ],

      "testSteps": [
        "MUST be executable shell commands - see examples below"
      ],

      "dependsOn": [],

      "notes": ""
    }
  ]
}
```

### Frontend stories also need:
- `testUrl` - URL to test
- `loadingState` - What shows during async operations
- `a11y` - Accessibility requirements
- `mobile` - How it works on mobile

### Backend stories also need:
- `apiEndpoints` - Endpoints to test
- `validation` - Input validation rules
- `auth` - Authentication requirements
- `scale` - Rate limiting, pagination (for list endpoints), caching

---

## Guidelines

- **Keep stories small** - If > 3-4 acceptance criteria, split it (~1000 tokens max)
- **Order by dependency** - Foundation stories first
- **Specify files explicitly** - Every story says which files to create/modify (max 3-4 files)
- **Define error handling** - Every story specifies failure behavior
- **Notes field** - Claude fills this as it works (files created, decisions made)

### Context Size Limits
Each story must be completable in ONE Claude session:
- **Max ~1000 tokens** for story description
- **Max 3-4 files** per story
- If too big, split it

### UI Stories Must Include Browser Verification
For frontend stories, acceptance criteria MUST include:
- "Page loads without console errors"
- "Required elements render" (specify which)
- "Works on mobile viewport (375px)"

These get verified by Playwright automatically.

### Test Steps - CRITICAL
**Test steps MUST be executable shell commands.** Ralph runs them with bash.

✅ **GOOD test steps (executable):**
```json
"testSteps": [
  "curl -s http://localhost:3000/api/health | jq -e '.status == \"ok\"'",
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/api/users | grep 200",
  "test -f frontend/src/components/Button.tsx",
  "grep -q 'export function Button' frontend/src/components/Button.tsx",
  "cd frontend && npx tsc --noEmit",
  "docker compose exec -T web python manage.py test app.tests.TestUserAPI",
  "npx playwright test tests/e2e/dashboard.spec.ts",
  "npx playwright test --grep 'login flow'",
  "cd frontend && npm test -- --testPathPattern=Button.test.tsx"
]
```

**For UI/visual verification, use Playwright tests:**
```json
"testSteps": [
  "npx playwright test tests/e2e/chat-panel.spec.ts"
]
```

The Playwright test file can check:
- Element visibility and positioning
- Console errors (no errors in DevTools)
- Network requests completing
- Visual layout (screenshots, viewport checks)
- Accessibility (axe-core integration)

❌ **BAD test steps (not executable - will fail):**
```json
"testSteps": [
  "Visit http://localhost:3000/dashboard",
  "User can see the dashboard",
  "Click the submit button",
  "Form validates correctly",
  "Chat panel renders in top 60%",
  "Check DevTools for errors"
]
```

**If a step can't be automated**, leave it out of testSteps and put it in acceptanceCriteria instead. Ralph will verify acceptanceCriteria via code review, not by running commands.
