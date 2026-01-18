---
description: Brainstorm a feature idea in plan mode, then generate PRDs for Ralph autonomous execution.
---

# /idea - From Brainstorm to PRD

You are helping the user go from a rough idea to executable PRDs for Ralph.

## User Input

```text
$ARGUMENTS
```

## Workflow

### Step 1: Enter Plan Mode

First, enter plan mode to explore this idea thoroughly. Use the EnterPlanMode tool.

Say: "Let's explore this idea. Entering plan mode to brainstorm..."

### Step 2: Brainstorm

In plan mode, help the user flesh out the idea:

1. **Understand the goal** - What problem does this solve? Who benefits?
2. **Explore the codebase** - What exists? What patterns should we follow?
3. **Ask clarifying questions** - Up to 5 questions about:
   - Scope boundaries (what's in/out)
   - User experience (what does the user see/do)
   - Edge cases (what could go wrong)
   - Dependencies (what does this touch)
   - Security/permissions (who can do what)
4. **Design the approach** - How should this be built?

Take your time. This is the creative phase.

### Step 3: Write the Idea File

When the brainstorm feels complete, write a markdown file:

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

   ## Technical Notes
   - Existing patterns to follow
   - Dependencies
   - Security considerations

   ## Open Questions
   - Any unresolved decisions
   ```

3. Open the file for review:
   ```bash
   open -a TextEdit docs/ideas/{feature-name}.md
   ```

4. Say: "I've written the idea to `docs/ideas/{feature-name}.md` and opened it in TextEdit. Review it and let me know:
   - **'approved'** - Ready to split into PRDs
   - **'edit'** - Tell me what to change
   - Or just make edits in the file and say 'done'"

### Step 4: Wait for Approval

Wait for the user to approve or request changes. If they request changes, make them and re-open the file.

### Step 5: Split into PRDs

Once the idea is approved, break it into small, executable PRDs:

1. Each PRD should be completable in one Claude session (~10-15 min of work)
2. Each PRD needs:
   - Clear acceptance criteria
   - Specific test steps (curl commands, UI checks, etc.)
   - Dependencies on other PRDs (if any)

Generate the PRD JSON structure:
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
      "title": "Story title",
      "passes": false,
      "acceptanceCriteria": ["AC 1", "AC 2"],
      "testSteps": ["curl command or manual verification step"],
      "dependsOn": []
    }
  ]
}
```

### Step 6: Write PRD and Review

1. Ensure .ralph directory exists:
   ```bash
   mkdir -p .ralph
   ```

2. Write to `.ralph/prd.json`

3. Open both files for review:
   ```bash
   open -a TextEdit docs/ideas/{feature-name}.md .ralph/prd.json
   ```

4. Say: "I've created the PRD with {N} stories. Both files are open in TextEdit:
   - `docs/ideas/{feature-name}.md` - The full idea (source of truth)
   - `.ralph/prd.json` - The executable stories for Ralph

   Review the PRD and let me know:
   - **'approved'** - Ready for `ralph run`
   - **'edit'** - Tell me what to change
   - Or edit the JSON directly and say 'done'"

### Step 7: Final Approval

Wait for the user to approve the PRD. If they request changes, update the JSON and re-open.

Once approved, say:

"Your idea is ready for execution!

**Idea:** `docs/ideas/{feature-name}.md`
**PRD:** `.ralph/prd.json` ({N} stories)

To start autonomous development:
```bash
ralph run
```

Ralph will work through each story, running tests and committing as it goes. You can check progress anytime with `ralph status`."

## Guidelines

- **Keep stories small** - If a story has more than 3-4 acceptance criteria, split it
- **Make test steps concrete** - "User can see X" is vague; "curl /api/x returns 200 with {field}" is testable
- **Order by dependency** - Stories that depend on others should come later
- **Max 10 stories** - If more, suggest splitting into phases
- **Stay in plan mode** - Don't write code during brainstorming

## Error Handling

- If user provides no arguments, ask: "What feature or idea would you like to brainstorm?"
- If .ralph/prd.json already exists, warn: "A PRD already exists. Archive it first: `mv .ralph/prd.json .ralph/archive/`"
- If user abandons mid-flow, the idea file is still saved for later
