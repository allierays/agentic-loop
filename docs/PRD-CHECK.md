# PRD Check: Catch Problems Before They Multiply

Before writing any code, Ralph validates every story. This catches issues that would otherwise cause dozens of failed retries.

> **Note:** `/prd` now runs prd-check automatically during PRD generation (Step 7c). The standalone `/prd-check` command is for re-validation after you've manually edited `.ralph/prd.json`.

## What It Catches

| What It Catches | The Problem Without It | What Ralph Does |
|-----------------|------------------------|-----------------|
| **Prose test steps** | Story says "verify login works"—Ralph has no executable command to run, retries endlessly | Detects non-executable steps, rewrites as `curl -X POST /api/login \| jq -e '.token'` |
| **Backend without API tests** | Story only runs `npm test`—never actually hits the endpoint, misses runtime errors | Adds curl commands that verify real API responses |
| **Frontend without testUrl** | No URL configured—Playwright can't load anything, browser checks skip silently | Requires `testUrl` so browser verification actually runs |
| **Auth without security criteria** | Claude stores passwords in plaintext, no rate limiting—passes "tests" but ships vulnerabilities | Injects criteria: bcrypt hashing, passwords never in responses, rate limiting |
| **List endpoint without pagination** | Returns 10,000 records, crashes browser, passes unit tests | Adds criteria: max 100 per page, accepts `?page=N&limit=N` |
| **Migration without prerequisites** | "Column does not exist" error loops forever—Claude keeps editing code, but the DB schema is wrong | Adds DB reset prerequisite so schema changes apply before tests run |

## How It Works

PRD check runs **once** at the start of `npx agentic-loop run`, before any code is written.

1. Validates JSON structure and required fields
2. Checks each incomplete story for quality issues
3. If issues found, Claude auto-fixes them
4. Creates timestamped backup before any changes

## Example Output

```
Optimizing test coverage for 3 stories...
  2x backend: add curl tests
  1x auth: add security criteria
  1x migration: add prerequisites (DB reset)
✓ Test coverage optimized (backup at .ralph/prd.json.20240115-143022.bak)
```

## When It Runs

- **Automatically** during `/prd` (Step 7c) — structural validation + lessons cross-reference, with auto-fix
- **At loop start** via `npx agentic-loop run` — runs once before any code is written
- **On demand** via `/prd-check` — for re-validation after manual edits

## Run On Demand

Use `/prd-check` in Claude Code or from the CLI after manually editing `.ralph/prd.json`:

```bash
npx agentic-loop prd-check              # Validate with auto-fix
npx agentic-loop prd-check --dry-run    # Report issues without auto-fix
```

The `/prd-check` skill runs in dry-run mode so you can review issues before deciding what to fix.

---

## Custom Checks

You can add your own rules that Ralph checks for in every story. These run alongside the built-in checks but won't be auto-fixed — they're reported so you can decide what to do.

### Adding a custom check

Tell Claude what you want checked. For example:

> "Add a custom PRD check that flags any backend story missing rate limiting in its acceptance criteria"

> "Create a PRD check that requires every story to have a description field"

> "Add a custom check that makes sure story IDs follow the TASK-NNN format"

Claude will create the script in `.ralph/checks/prd/` for you. There's also an example template at `templates/checks/prd/check-example.sh` if you want to see how they work.

Custom checks live in two places:
- `.ralph/checks/prd/` — for this project (commit to your repo so the whole team gets them)
- `~/.config/ralph/checks/prd/` — for you personally (applies to all your projects)

### Turning off a check

If a check is getting in the way, disable it in `.ralph/config.json`:

```json
{
  "checks": {
    "custom": {
      "check-description": false
    }
  }
}
```

---

## Configuration

In `.ralph/config.json`:

```json
{
  "checks": {
    "requireTests": true
  },
  "api": {
    "baseUrl": "http://localhost:8000",
    "healthEndpoint": "/api/health"
  }
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `checks.requireTests` | `true` | Warn if no test directory configured |
| `api.baseUrl` | - | API URL (enables health check validation) |
| `api.healthEndpoint` | `/health` | Health endpoint path (empty to disable) |
| `checks.custom.<name>` | `true` | Enable/disable individual custom checks |

## See Also

- [Customizing Ralph](customizing-ralph.md) - Lessons, custom checks, /prd
- [Code Check](CODE-CHECK.md) - Verification after each story
- [How Ralph Works](RALPH.md) - Full architecture details
