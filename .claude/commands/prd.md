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
- Note the highest existing story ID (e.g., if US-005 exists, new stories start at US-006)
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

- **Keep stories small** - If > 3-4 acceptance criteria, split it
- **Concrete test steps** - "curl /api/x returns 200" not "user can see X"
- **Order by dependency** - Foundation stories first
- **Specify files explicitly** - Every story says which files to create/modify
- **Define error handling** - Every story specifies failure behavior
