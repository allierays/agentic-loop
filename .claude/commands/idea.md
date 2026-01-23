---
description: Brainstorm a feature idea, then generate PRDs for Ralph autonomous execution.
---

# /idea - From Brainstorm to PRD

You are helping the user go from a rough idea to executable PRDs for Ralph.

**CRITICAL: This command does NOT write code. It produces documentation files only.**

## When to Use

| Workflow | Best For |
|----------|----------|
| **`/idea`** | Structured brainstorming with guided questions - Claude leads |
| **Plan mode → save to `docs/ideas/`** | Free-form exploration - you lead the thinking |
| **`/prd "description"`** | Quick PRD, no docs artifact needed |

**Both `/idea` and plan mode can produce `docs/ideas/*.md` files.** The difference is who drives the conversation:
- `/idea` asks you structured questions (scope, UX, edge cases, etc.)
- Plan mode lets you explore freely with Claude's help

Use `/idea` when you want the structured checklist. Use plan mode when you prefer to think through it your way.

## User Input

```text
$ARGUMENTS
```

## Workflow

### Step 1: Start Brainstorming

If `$ARGUMENTS` is empty, ask: "What feature or idea would you like to brainstorm?"

If `$ARGUMENTS` has content, acknowledge it and proceed.

Say: "Let's brainstorm this idea. I'll help you think it through, then we'll create documentation for Ralph to execute."

### Step 2: Explore and Ask Questions

Help the user flesh out the idea through conversation:

1. **Understand the goal** - What problem does this solve? Who benefits?
2. **Explore the codebase** - Use Glob/Grep/Read to understand what exists and what patterns to follow
3. **Ask clarifying questions** - Up to 5 questions about:
   - Scope boundaries (what's in/out)
   - User experience (what does the user see/do)
   - Edge cases (what could go wrong)
   - Dependencies (what does this touch)
   - Security/permissions (who can do what)
   - Scale (how many users/items/requests?)

### Step 3: Summarize Before Writing

When you have enough information, summarize what you've learned:

Say: "Here's what I understand about the feature:

**Problem:** [summary]
**Solution:** [summary]
**Key decisions:** [list]

Ready to write this to `docs/ideas/{feature-name}.md`? Say **'yes'** or tell me what to adjust."

**STOP and wait for user confirmation before writing any files.**

### Step 4: Write the Idea File

Once the user confirms, write the idea file:

1. Create the directory if needed:
   ```bash
   mkdir -p docs/ideas
   ```

2. Write to `docs/ideas/{feature-name}.md` with this structure:
   ```markdown
   # {Feature Name}

   ## Problem
   What problem does this solve?

   ## Solution
   High-level description of the solution.

   ## User Stories
   - As a [user], I want to [action] so that [benefit]
   - ...

   ## Scope
   ### In Scope
   - ...

   ### Out of Scope
   - ...

   ## Architecture
   ### Directory Structure
   - Where new files should go (be specific: `src/components/forms/`, not just `src/`)

   ### Patterns to Follow
   - Existing components/utilities to reuse
   - Naming conventions

   ### Do NOT Create
   - List things that already exist (avoid duplication)

   ## Technical Notes
   - Dependencies
   - Security considerations

   ## Open Questions
   - Any unresolved decisions
   ```

3. Open the file for review:
   ```bash
   open -a TextEdit docs/ideas/{feature-name}.md
   ```

4. Say: "I've written the idea to `docs/ideas/{feature-name}.md` and opened it in TextEdit.

   Review it and let me know:
   - **'approved'** - Ready to split into PRDs
   - **'edit [changes]'** - Tell me what to change
   - Or make edits in the file and say **'done'**"

**STOP and wait for user response. Do not proceed until they say 'approved' or 'done'.**

### Step 5: Split into PRDs

**Only proceed here after user explicitly approves the idea file.**

Say: "Now I'll split this into executable PRDs for Ralph. Each story will be small enough to complete in one session."

Break the idea into small, executable PRDs following the JSON structure below.

### Step 6: Write PRD

1. Ensure .ralph directory exists and allow PRD edit:
   ```bash
   mkdir -p .ralph && touch .ralph/.prd-edit-allowed
   ```

2. Write to `.ralph/prd.json` ensuring:
   - Valid JSON syntax
   - `feature.name` is set (not null/empty)
   - `feature.status` is "pending"
   - `stories` array is not empty
   - Each story has `id`, `title`, and `passes: false`

3. Validate the PRD was written correctly:
   ```bash
   jq -e '.feature.name and (.stories | length > 0) and (.stories | all(.id and .title and .passes == false))' .ralph/prd.json && echo "PRD valid" || echo "PRD invalid"
   ```

4. Say: "I've created the PRD with {N} stories in `.ralph/prd.json`.

   Review and let me know:
   - **'approved'** - Ready for `npx ralph run`
   - **'edit [changes]'** - Tell me what to change"

**STOP and wait for user response. Do not proceed until they approve.**

### Step 7: Final Instructions

Once the user approves the PRD, say:

"Ready for autonomous development!

**Idea:** `docs/ideas/{feature-name}.md`
**PRD:** `.ralph/prd.json` ({N} stories)

Run:
```bash
npx ralph run
```

**DO NOT start implementing code. The user will run `npx ralph run` separately.**

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

### E2E Tests
Add `"e2e": true` to **any frontend story where users interact** with the feature:
- Forms, buttons, inputs, modals, wizards → e2e
- Real-time features, drag & drop, file uploads → e2e
- Multi-page flows, navigation → e2e
- Static display-only components (no interaction) → skip e2e

When `e2e: true`, the story should:
- Create a Playwright test file in `tests/e2e/{story-id}.spec.ts`
- Include the test in `testSteps`: `"npx playwright test tests/e2e/{story-id}.spec.ts"`
- **Skip in CI** (runs nightly instead): Add `test.skip(!!process.env.CI, 'Runs nightly');` at top of test

Don't ask - if users touch it, test it.

### Backend stories also need:
- `apiEndpoints` - Endpoints to test
- `validation` - Input validation rules
- `auth` - Authentication requirements
- `scale` - Rate limiting, pagination (for list endpoints), caching

---

## Guidelines

### Story Guidelines
- **Keep stories small** - Max 3-4 acceptance criteria per story, ~1000 tokens max description
- **Order by dependency** - Stories that depend on others come later
- **Max 10 stories** - If more, suggest splitting into phases
- **Define error handling** - Every story specifies what happens on failure
- **Notes field** - Claude fills this as it works (files created, decisions made, context for next story)

### Context Size Limits
Each story must be completable in ONE Claude session without context overflow:
- **Max ~1000 tokens** for story description (title + criteria + error handling)
- **Max 3-4 files** created or modified per story
- If a story feels too big, split it

### UI Stories Must Include Browser Verification
For frontend stories, acceptance criteria MUST include:
- "Page loads without console errors"
- "Required elements render" (specify which: header, form, button, etc.)
- "Works on mobile viewport (375px)"

These get verified by Playwright, not just code review.

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

### Architecture Guidelines
- **Domain-driven directories** - Group by feature (`src/contact/`) not type (`src/components/`)
- **Max 300 lines per file** - Split large files
- **Reuse over recreate** - Check for existing utilities first
- **Explicit file paths** - Every story specifies exactly which files

---

## Error Handling

- If user provides no arguments, ask what they want to brainstorm
- If user abandons mid-flow, the idea file is still saved for later

### If PRD Already Exists

Before writing to `.ralph/prd.json`, check if it exists:

```bash
cat .ralph/prd.json 2>/dev/null | jq '{stories: .stories | length, completed: [.stories[] | select(.passes == true)] | length}'
```

If it exists, say:
"📋 `.ralph/prd.json` already exists with {N} stories ({M} completed, {P} pending).

Options:
- **'append'** - Add new stories to existing PRD (recommended)
- **'overwrite'** - Replace entirely
- **'cancel'** - Stop here"

**STOP and wait for user choice.**

If **'append'**:
- Find highest existing story number (ignore prefix - could be US-019 or TASK-019)
- **Always use TASK- prefix** for new stories (e.g., if highest is US-019 or TASK-019, new stories start at TASK-020)
- Read existing PRD, add new stories to the `stories` array
- Update `metadata.estimatedStories` count
- Write back to `.ralph/prd.json`

If **'overwrite'**:
- Archive first: `mkdir -p .ralph/archive && mv .ralph/prd.json .ralph/archive/prd-$(date +%Y%m%d-%H%M%S).json`
- Allow edit: `touch .ralph/.prd-edit-allowed`
- Write new PRD
