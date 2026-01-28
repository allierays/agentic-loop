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

## See Also

- [Code Check](CODE-CHECK.md) - Verification after each story
- [How Ralph Works](RALPH.md) - Full architecture details
