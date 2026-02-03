# PRD Check: Catch Problems Before They Multiply

Before writing any code, Ralph validates every story. This catches issues that would otherwise cause dozens of failed retries.

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

## Run On Demand

Use `/prd-check` in Claude Code or from the CLI:

```bash
npx agentic-loop prd-check              # Validate with auto-fix
npx agentic-loop prd-check --dry-run    # Report issues without auto-fix
```

The `/prd-check` skill runs in dry-run mode so you can review issues before deciding what to fix.

---

## Custom Checks

Add your own per-story validation scripts. They run alongside the built-in checks but are excluded from auto-fix (reported for manual review).

### Setup

Place executable scripts in either location:

- `.ralph/checks/prd/check-*` — project-level (checked into repo)
- `~/.config/ralph/checks/prd/check-*` — user-global (applies to all projects)

### Script Interface

| Input | Source |
|-------|--------|
| **stdin** | Story JSON object |
| **$1** | Story ID |
| **$2** | PRD file path |
| **stdout** | Issue descriptions, one per line (empty = pass) |

Scripts can be any language (bash, python, node). They must be executable (`chmod +x`).

### Example

```bash
#!/usr/bin/env bash
# .ralph/checks/prd/check-description.sh
story_json=$(cat)
has_description=$(echo "$story_json" | jq -r '.description // empty')
if [[ -z "$has_description" ]]; then
  echo "missing description field"
fi
```

A full example template is at `templates/checks/prd/check-example.sh`.

### Disable a Check

In `.ralph/config.json`:

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

- [Code Check](CODE-CHECK.md) - Verification after each story
- [How Ralph Works](RALPH.md) - Full architecture details
