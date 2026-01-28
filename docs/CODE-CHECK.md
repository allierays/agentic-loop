# Code Check: Quality Gates After Every Story

After Claude writes code, a 5-step verification pipeline runs. It fails fast—no point running browser tests if linting fails.

## The Pipeline

```
[1/5] Lint        → ESLint, Ruff, etc. (auto-fix enabled)
[2/5] Tests       → Verify test files exist + run unit tests
[3/5] PRD steps   → Execute the curl/playwright commands from your story
[4/5] API smoke   → Hit health endpoint (catches server crashes)
[5/5] Frontend    → Load page, check for console errors
```

## What Happens on Failure

| Scenario | What Ralph Does |
|----------|-----------------|
| **First failure** | Saves error context to `last_failure.txt`, Claude retries knowing what broke |
| **Same error 3x** | Flags as pattern: "You've tried this approach 3 times—consider a different strategy" |
| **Structural error detected** | Recognizes "column does not exist" isn't a code bug—suggests DB reset instead of more code changes |
| **15 failures on one story** | Circuit breaker trips, skips to next story, saves failure log for manual review |

## Failure Context Accumulation

Errors are **accumulated across retries**, not just the last failure:

```
=== Attempt 1 failed for TASK-001 ===
ERROR: relation "users" does not exist
---
=== Attempt 2 failed for TASK-001 ===
ERROR: relation "users" does not exist
---
>>> STRUCTURAL ISSUE: Database schema mismatch
>>> ACTION NEEDED: Reset test database, don't just retry code
```

This helps Claude identify patterns like "same error 3 times = structural issue."

## Structural Error Detection

Some errors indicate structural issues (not code bugs) that can't be fixed by retrying:

| Error Pattern | What Ralph Suggests |
|---------------|---------------------|
| "column does not exist" | DB reset (schema mismatch) |
| "relation does not exist" | DB reset (missing table) |
| "pending migration" | Run migrations |
| "connection refused" | Start services |

## Configuration

In `.ralph/config.json`:

```json
{
  "checks": {
    "lint": true,
    "test": true,
    "build": "npm run build"
  },
  "maxStoryRetries": 15,
  "maxSessionSeconds": 600
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `checks.lint` | `true` | Run linting |
| `checks.test` | `true` | Run tests (`true`, `false`, or `"final"`) |
| `checks.build` | auto-detect | Build command |
| `maxStoryRetries` | `15` | Circuit breaker threshold |
| `maxSessionSeconds` | `600` | Claude session timeout |

## Running Manually

```bash
# Run verification without Claude
npx agentic-loop check

# Verify specific story
npx agentic-loop verify TASK-001

# Check failure context
cat .ralph/last_failure.txt
```

## See Also

- [PRD Check](PRD-CHECK.md) - Validation before coding starts
- [How Ralph Works](RALPH.md) - Full architecture details
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues and fixes
