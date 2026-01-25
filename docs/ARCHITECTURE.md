# Architecture

How agentic-loop works under the hood.

## The Loop

```
1. Read prd.json → find next story where passes=false
2. Build prompt → PROMPT.md + story ID + signs + failure context
3. Run Claude → first story fresh, subsequent --continue
4. Verify → lint, tests, testSteps
5. Pass → commit, next story / Fail → save error, retry
6. Repeat until done
```

## File Structure

```
.ralph/
├── config.json      # URLs, directories, check settings
├── prd.json         # Stories to implement
├── signs.json       # Learned patterns
├── progress.txt     # Activity log
└── last_failure.txt # Error context for retries

.claude/commands/    # Slash commands (/idea, /prd, /review, etc.)
PROMPT.md            # 7-step framework Claude follows
CLAUDE.md            # Project conventions
```

## Prompt Model

**Lean prompts** - Claude reads files during orientation instead of receiving everything upfront.

Ralph injects:
- `PROMPT.md` - How to work
- Story ID - What to build
- Signs - Patterns to follow
- Failure context - What went wrong (if retrying)

Claude reads during Orient step:
- `.ralph/prd.json` - Full story details
- `story.contextFiles[]` - Idea files, styleguides
- `CLAUDE.md` - Project conventions

## Verification

After Claude codes, Ralph verifies:

1. **Lint** - build, lint, typecheck
2. **Tests** - unit tests
3. **testSteps** - commands from prd.json (curl, playwright, etc.)

Fail? Error saved to `last_failure.txt`, Claude retries with context.

## URL Expansion

Use `{config.urls.backend}` in testSteps. Ralph expands from config.json:

```json
"testSteps": ["curl {config.urls.backend}/users"]
// Becomes: curl http://localhost:8000/users
```

## Signs

Patterns learned from failures. Injected into every prompt.

```bash
npx agentic-loop sign "Always use camelCase" backend
```

## More Info

- [How Ralph Works](RALPH.md) - Detailed walkthrough
- [Cheatsheet](CHEATSHEET.md) - All commands
- [Hooks](HOOKS.md) - Pre-commit and Claude Code hooks
