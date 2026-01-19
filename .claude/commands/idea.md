---
description: Brainstorm a feature idea, then generate PRDs for Ralph autonomous execution.
---

# /idea - From Brainstorm to PRD

You are helping the user go from a rough idea to executable PRDs for Ralph.

**CRITICAL: This command does NOT write code. It produces documentation files only.**

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

### Step 6: Write PRD and Review

1. Ensure .ralph directory exists:
   ```bash
   mkdir -p .ralph
   ```

2. Write to `.ralph/prd.json`

3. Open the PRD for review:
   ```bash
   open -a TextEdit .ralph/prd.json
   ```

4. Say: "I've created the PRD with {N} stories.

   Review `.ralph/prd.json` and let me know:
   - **'approved'** - Ready for `ralph run`
   - **'edit [changes]'** - Tell me what to change
   - Or edit the JSON directly and say **'done'**"

**STOP and wait for user response. Do not proceed until they approve.**

### Step 7: Final Instructions

Once the user approves the PRD, say:

"Your idea is ready for execution!

**Idea:** `docs/ideas/{feature-name}.md`
**PRD:** `.ralph/prd.json` ({N} stories)

To start autonomous development:
```bash
ralph run
```

Ralph will work through each story, running tests and committing as it goes."

**DO NOT start implementing code. The user will run `ralph run` separately.**

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
      "id": "US-001",
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
        "How to verify it works"
      ],

      "dependsOn": []
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

### Story Guidelines
- **Keep stories small** - Max 3-4 acceptance criteria per story
- **Make test steps concrete** - "curl /api/x returns 200" not "user can see X"
- **Order by dependency** - Stories that depend on others come later
- **Max 10 stories** - If more, suggest splitting into phases
- **Define error handling** - Every story specifies what happens on failure

### Architecture Guidelines
- **Domain-driven directories** - Group by feature (`src/contact/`) not type (`src/components/`)
- **Max 300 lines per file** - Split large files
- **Reuse over recreate** - Check for existing utilities first
- **Explicit file paths** - Every story specifies exactly which files

---

## Error Handling

- If user provides no arguments, ask what they want to brainstorm
- If .ralph/prd.json already exists, warn: "A PRD already exists. Archive it first: `mv .ralph/prd.json .ralph/archive/`"
- If user abandons mid-flow, the idea file is still saved for later
