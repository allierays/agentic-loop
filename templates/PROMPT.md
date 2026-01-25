# Ralph Autonomous Loop

You're implementing a story from `.ralph/prd.json`. This file contains everything you need.

---

## Step 1: Orient (MANDATORY)

Before writing any code, run these commands:

```bash
git log --oneline -5                    # Recent commits
cat .ralph/progress.txt | tail -30      # Recent activity
```

Then read these files:
- `.ralph/prd.json` - Find your story, note `techStack`, `globalConstraints`
- `CLAUDE.md` - Project conventions and coding standards
- Files listed in `story.contextFiles[]` - Idea files, styleguides, ASCII mockups
- `~/.claude/DNA.md` - Personal coding preferences (if exists)

---

## Step 2: Check for Failures

If `.ralph/last_failure.txt` exists, read it carefully. Understand what went wrong. Don't repeat that mistake.

---

## Step 3: Read Learned Patterns

Read `.ralph/signs.json` - these are patterns learned from past failures. Follow them strictly.

---

## Step 4: Verify Prerequisites

Check `story.prerequisites[]` in your story. Ensure:
- Required servers are running (check `.ralph/config.json` for URLs)
- Database is seeded if needed
- Dependencies are installed

---

## Step 5: Implement

Work on your story following these rules:

### From Your Story
- **story.acceptanceCriteria** - What must be true when done
- **story.files** - Which files to create, modify, reuse (don't touch others)
- **story.testing** - Test types, approach (TDD/test-after), and test files to create
- **story.errorHandling** - How to handle failures
- **story.apiContract** - Expected request/response format (if applicable)
- **story.notes** - Human guidance and preferences
- **story.skills** - Read `.claude/commands/{skill}.md` for patterns

### From the PRD
- **prd.globalConstraints** - Rules that apply to ALL stories
- **prd.testing** - Testing strategy (TDD, tools, coverage)

### From Config (.ralph/config.json)
- **config.urls.backend** - API base URL for curl tests
- **config.urls.frontend** - Frontend URL for browser tests
- **config.directories** - Where frontend/backend code lives

### Code Quality
- **Readability First** - Code is read more than written
- **KISS** - Keep it simple, avoid over-engineering
- **DRY** - Don't repeat yourself
- **YAGNI** - Don't build features you don't need yet

### Removing UI? Update Tests!
When removing or modifying UI elements:
1. `grep -r "element text or testid" tests/` to find related tests
2. Update or remove tests that reference removed elements
3. Verify with: `grep -r "removed text" tests/ && exit 1 || echo "clean"`

### Error Handling
Every async operation needs proper error handling:
```typescript
try {
  const data = await fetchData();
  return { success: true, data };
} catch (error) {
  console.error('Failed to fetch:', error);
  return { success: false, error: error.message };
}
```

### Testing (Follow story.testing)

**Check `story.testing.approach`:**
- **TDD**: Write failing test FIRST, then implement to make it pass
- **test-after**: Implement first, then write tests

**Test Types** (from `story.testing.types`):
| Type | What to Test |
|------|--------------|
| `unit` | Individual functions/components in isolation |
| `integration` | How pieces work together (API + DB, Component + Hook) |
| `e2e` | Full user flows in browser |

**Test Files** (from `story.testing.files`):
Create the exact test files specified in the story.

**TDD Workflow:**
```
1. Write test for first acceptance criterion → FAIL
2. Write minimum code to pass → PASS
3. Refactor if needed
4. Repeat for next criterion
```

---

## Step 6: Verify

### Run Test Steps
Execute each command in `story.testSteps[]`. All must pass.

### Browser Verification (if story.mcp includes browser tools)
Use the MCP tools specified in `story.mcp[]`:

**Playwright MCP** (`playwright`):
- Navigate to `story.testUrl`
- Take screenshots to verify UI
- Click elements and fill forms
- Check accessibility

**Chrome DevTools MCP** (`devtools`):
- Check console for errors
- Inspect network requests
- Debug DOM issues

**Do NOT mark complete until:**
- All test steps pass
- Browser verification confirms it works
- Console has no errors

---

## Step 7: End Clean

After completing the story:

1. **Update progress notes**
   ```bash
   echo "$(date): Completed TASK-XXX - [brief summary]" >> .ralph/progress.txt
   ```

2. **Note files changed**
   - List files created/modified in progress.txt
   - Note any key decisions made

3. **Leave code ready for commit**
   - No console.log or debug statements
   - No commented-out code
   - All tests passing

---

## Rules

1. **Focus** - Implement ONLY the current story
2. **Follow the PRD** - It has all the context you need
3. **Read before coding** - Understand existing patterns first
4. **Test frequently** - Run tests after each significant change
5. **NEVER edit prd.json** - Ralph handles story completion
6. **Don't give up** - If verification fails, fix and retry

---

## If Blocked

If you encounter a blocker you cannot resolve:
1. Document the issue in `.ralph/progress.txt`
2. Note what you tried and why it didn't work
3. Suggest potential solutions
4. Do NOT mark the story as passing

---

## Current Story

(Story ID will be provided below - read full details from .ralph/prd.json)
