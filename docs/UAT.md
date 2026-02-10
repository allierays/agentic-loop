# UAT & Chaos Agent: Autonomous Testing Loops

Two commands for autonomous testing — same TDD engine, different mindsets.

| Command | Mindset | Team |
|---------|---------|------|
| `npx agentic-loop uat` | "Does this work correctly?" | recon, happy-path, edge-cases |
| `npx agentic-loop chaos-agent` | "Can we break it?" | recon, chaos, security |

Both use [Agent Teams](https://docs.anthropic.com/en/docs/claude-code) for coordinated browser exploration, then strict TDD per test case.

---

## How It Works

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Phase 1: DISCOVER + PLAN                                              │
│                                                                        │
│  Agent team explores the live app with Playwright:                     │
│  - Recon agent maps routes, forms, endpoints                           │
│  - Specialist agents test their areas                                  │
│  - Agents share intel via SendMessage                                  │
│  - Team lead merges findings → plan.json                               │
│                                                                        │
├──────────────────────────────────────────────────────────────────────────┤
│  Plan Review                                                           │
│                                                                        │
│  You review the plan before anything executes:                         │
│  [Y] Execute  |  [n] Cancel  |  [e] Edit in $EDITOR                   │
│                                                                        │
├──────────────────────────────────────────────────────────────────────────┤
│  Phase 2: TDD LOOP (per test case)                                     │
│                                                                        │
│  ┌─ RED ──────────────────────────────┐                                │
│  │ Claude writes the test ONLY        │                                │
│  │ No app changes allowed             │                                │
│  │ Test must have content assertions  │                                │
│  └────────────────────────────────────┘                                │
│           │                                                            │
│           ▼                                                            │
│  Test passes? → App already correct → commit, next case                │
│  Test fails?  → Classify: test bug or app bug?                         │
│           │                                                            │
│           ▼  (app bug)                                                 │
│  ┌─ GREEN ────────────────────────────┐                                │
│  │ Claude fixes the app ONLY          │                                │
│  │ No test changes allowed            │                                │
│  │ Regression check before commit     │                                │
│  └────────────────────────────────────┘                                │
│                                                                        │
├──────────────────────────────────────────────────────────────────────────┤
│  Phase 3: REPORT                                                       │
│                                                                        │
│  Summary: cases passed/failed, bugs found/fixed, files changed         │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## UAT: Acceptance Testing

Verifies that features work correctly for real users.

```bash
npx agentic-loop uat
```

### Team Composition

| Agent | Role |
|-------|------|
| **recon** | Maps all routes/endpoints, catalogs forms with selectors, identifies tech stack and auth |
| **happy-path-{area}** | One per feature area. Completes primary user journeys, records correct behavior as ground truth |
| **edge-cases** | Tests boundary conditions: empty fields, long input, validation, back button, refresh mid-flow |

Only spawns agents for areas that exist. No forms? No forms specialist.

### Example Output

```
  _   _   _  _____   _
 | | | | / \|_   _| | |    ___   ___  _ __
 | | | |/ _ \ | |   | |   / _ \ / _ \| '_ \
 | |_| / ___ \| |   | |__| (_) | (_) | |_) |
  \___/_/   \_\_|   |_____\___/ \___/| .__/
                                      |_|

  Phase 1: Discovery + Plan Generation

  ⟳ Browser    navigate to http://localhost:3000
  ⟳ Reading    .ralph/config.json
  ⟳ Browser    take_screenshot
  ...

  ✓ Plan generated: 8 test cases

  Execute this plan? [Y/n/e(dit)]
```

---

## Chaos Agent: Adversarial Red Team

Tries to break the app with XSS, injection, chaos inputs, auth bypass.

```bash
npx agentic-loop chaos-agent
```

### Docker Isolation (default)

By default, the chaos-agent spins up an **isolated Docker copy** of your app so your live dev server is never touched. It parses your `docker-compose.yml`, offsets all ports by 10000 (e.g., `:5173` becomes `:15173`), and runs the red team against the isolated copy.

```
$ npx agentic-loop chaos-agent

  Starting isolated Docker environment...
    → Parsing docker-compose.yml for port mappings
    → Generated override: api 8001→18001, web 5173→15173
    → Isolated environment ready (frontend: :15173, api: :18001)

  Phase 1: Red team exploring your app for vulnerabilities
    → Agents attack http://localhost:15173 (your :5173 is untouched)

  Tearing down isolated environment...
    → Done. Your dev server was never touched.
```

**Requirements:** Docker and a compose file (`docker-compose.yml`, `compose.yml`, etc.)

**Fallback:** If Docker isn't available or no compose file exists, the chaos-agent falls back to testing against your live app with non-destructive guardrails (no DELETE endpoints, no mass mutations, etc.).

### Team Composition

| Agent | Role |
|-------|------|
| **recon** | Attack surface mapping. Catalogs every input, auth mechanism, API endpoint. Shares intel: "login uses JWT in localStorage" |
| **chaos** | Chaos testing. For every input: empty strings, 10000-char payloads, special characters, unicode/emoji, null bytes. Double-submit, missing fields, rapid-fire interactions |
| **security** | XSS in every input, SQL injection, auth bypass via direct URL, IDOR via ID manipulation, sensitive data in localStorage/console/page source, missing CSRF tokens |

Agents coordinate — recon shares discoveries, security acts on them.

---

## Usage

```bash
# Acceptance testing
npx agentic-loop uat                    # Full: team → plan → TDD loop
npx agentic-loop uat --plan-only        # Generate plan only
npx agentic-loop uat --focus auth       # Focus on auth tests only
npx agentic-loop uat --focus UAT-003    # Focus on specific test case
npx agentic-loop uat --no-fix           # Write tests but don't fix app bugs
npx agentic-loop uat --max 10           # Limit to 10 iterations
npx agentic-loop uat --quiet            # Suppress activity feed
npx agentic-loop uat --review           # Re-review existing plan

# Adversarial testing
npx agentic-loop chaos-agent                  # Full: red team → plan → TDD loop
npx agentic-loop chaos-agent --plan-only      # Generate chaos plan only
npx agentic-loop chaos-agent --no-fix         # Find vulnerabilities without fixing
npx agentic-loop chaos-agent --focus security # Focus on security tests
npx agentic-loop chaos-agent --quiet          # Suppress activity feed
```

### Flags

| Flag | Description |
|------|-------------|
| `--plan-only` | Generate plan without executing the TDD loop |
| `--focus <id\|category>` | Run specific test case (UAT-003) or category (auth, security, forms) |
| `--no-fix` | Write failing tests as documented bugs — skip GREEN phase |
| `--max N` | Limit total iterations (default: 20) |
| `--quiet` | Suppress the live activity feed |
| `--review` | Re-review an existing plan before executing |

---

## The TDD Engine

Both commands share the same strict TDD loop.

### RED Phase (test-only)

Claude writes the test file. Constraints enforced:

- **No app changes** — if Claude modifies app code, changes are rolled back and the phase retries
- **Content assertions required** — tests that only check "page loads" are rejected as shallow
- **Minimum 2 assertions** — at least one content assertion (toContain, toHaveText, toBe, etc.)
- **Input-output pattern** — e2e tests must fill/click AND verify the result

If the test passes in RED, the app is already correct — commit and move on.
If the test fails with an assertion error, it's an app bug — commit the RED test and transition to GREEN.
If the test fails with a syntax/import error, it's a test bug — retry RED with feedback.

### GREEN Phase (fix-only)

Claude fixes the application code. Constraints enforced:

- **No test changes** — if Claude modifies the test file, it's restored from the last commit
- **Regression check** — existing tests must still pass after the fix
- **Rollback on regression** — if the fix breaks other tests, all changes are rolled back

### Circuit Breaker

If a test case exceeds the retry limit (default: 5 combined RED + GREEN retries), it's skipped and flagged for human attention.

---

## plan.json Schema

Generated during Phase 1 discovery. Stored at `.ralph/uat/plan.json` or `.ralph/chaos/plan.json`.

```json
{
  "testSuite": {
    "name": "UAT Loop",
    "generatedAt": "2026-02-09T10:30:00Z",
    "status": "pending",
    "discoveryMethod": "uat-team"
  },
  "testCases": [
    {
      "id": "UAT-001",
      "title": "Login — valid credentials redirect to dashboard",
      "category": "auth",
      "type": "e2e",
      "userStory": "As a user, I can log in and see my dashboard",
      "testApproach": "Fill login form, verify redirect and welcome message",
      "testFile": "tests/e2e/auth/login.spec.ts",
      "targetFiles": ["src/pages/login.tsx", "src/api/auth.ts"],
      "edgeCases": ["Empty password", "Wrong credentials", "SQL injection in email"],
      "assertions": [
        {
          "input": "Fill email='user@test.com', password='pass123', submit",
          "expected": "Redirects to /dashboard, shows 'Welcome, User'",
          "strategy": "keyword"
        },
        {
          "input": "Submit with empty password",
          "expected": "Shows 'Password is required'",
          "strategy": "keyword"
        },
        {
          "input": "Fill email with XSS payload, submit",
          "expected": "Payload displayed as text, no script execution",
          "strategy": "security"
        }
      ],
      "passes": false,
      "retryCount": 0,
      "source": "uat-team:happy-path-auth"
    }
  ]
}
```

### Key Fields

| Field | Description |
|-------|-------------|
| `discoveryMethod` | `"uat-team"` or `"chaos-agent"` |
| `type` | `"e2e"` (browser) or `"integration"` (API-only) |
| `assertions` | Input/expected pairs that become `expect()` calls — at least 3 per case |
| `passes` | Tracks completion state through the TDD loop |
| `phase` | `null` (start RED), `"red"` (RED done, resume GREEN) |
| `redRetries` / `greenRetries` | Per-phase retry counts for the circuit breaker |
| `source` | Which agent discovered this test case |

---

## Configuration

In `.ralph/config.json`:

```json
{
  "uat": {
    "sessionSeconds": 1800,
    "maxIterations": 20,
    "maxCaseRetries": 5,
    "maxSessionSeconds": 600
  },
  "chaos": {
    "sessionSeconds": 1800,
    "maxIterations": 20,
    "maxCaseRetries": 5,
    "maxSessionSeconds": 600,
    "isolate": true,
    "docker": {
      "portOffset": 10000,
      "healthTimeout": 120,
      "build": true
    }
  },
  "docker": {
    "composeFile": "docker-compose.yml"
  }
}
```

### Shared Config

| Field | Default | Description |
|-------|---------|-------------|
| `*.sessionSeconds` | `1800` | Timeout for the Phase 1 discovery session (Agent Teams) |
| `*.maxIterations` | `20` | Maximum TDD loop iterations |
| `*.maxCaseRetries` | `5` | Circuit breaker — max combined RED + GREEN retries per case |
| `*.maxSessionSeconds` | `600` | Timeout per individual Claude session (RED or GREEN) |

### Docker Isolation Config (Chaos Agent)

| Field | Default | Description |
|-------|---------|-------------|
| `chaos.isolate` | `true` | Enable Docker isolation for chaos-agent runs |
| `chaos.docker.portOffset` | `10000` | Offset added to host ports (e.g., 5173 → 15173) |
| `chaos.docker.healthTimeout` | `120` | Seconds to wait for containers to be healthy |
| `chaos.docker.build` | `true` | Pass `--build` to rebuild images each run |
| `docker.composeFile` | auto-detect | Path to compose file (checks `docker-compose.yml`, `compose.yml`, etc.) |

UAT and Chaos Agent are configured independently — you can give Chaos Agent more retries or a longer discovery timeout.

---

## Directory Structure

```
.ralph/
  uat/                      # UAT acceptance testing
    plan.json               # Generated test plan
    progress.txt            # Activity log
    last_failure.txt        # Failure context for retries
    UAT-PROMPT.md           # Project-specific testing guide (generated)
    screenshots/            # Screenshots from discovery
    last_test_output.log    # Most recent test output

  chaos/                    # Chaos Agent adversarial testing
    plan.json               # Generated attack plan
    progress.txt            # Activity log
    last_failure.txt        # Failure context for retries
    UAT-PROMPT.md           # Project-specific red team guide (generated)
    screenshots/            # Screenshots from discovery
    last_test_output.log    # Most recent test output
```

UAT and Chaos Agent use separate directories — they don't clobber each other. Both share the same lockfile (`.ralph/.lock`) so they can't run simultaneously, since both modify app code via git.

---

## Resuming

If you stop mid-run (Ctrl+C or `npx agentic-loop stop`), re-running the same command resumes where you left off:

```bash
npx agentic-loop uat     # Resumes existing plan, picks up next incomplete case
npx agentic-loop chaos-agent   # Same — resumes from last position
```

To start fresh, delete the plan and re-run:

```bash
rm .ralph/uat/plan.json && npx agentic-loop uat
rm .ralph/chaos/plan.json && npx agentic-loop chaos-agent
```

---

## Test Quality

Ralph rejects shallow tests that only check structure. A test must verify *content* — the right data, not just that the page loads.

| Rejected (shallow) | Accepted (content) |
|---------------------|--------------------|
| `expect(page).toHaveURL('/dashboard')` | `expect(page.getByText('Welcome, John')).toBeVisible()` |
| `expect(form).toBeVisible()` | `expect(page.getByText('Email is required')).toBeVisible()` |
| `expect(response.status).toBe(200)` | `expect(response.json().user.name).toBe('John')` |

When a test is rejected as shallow, Ralph saves specific feedback about what's wrong and retries with guidance.

---

## See Also

- [Code Check](CODE-CHECK.md) — Verification pipeline after each story
- [How Ralph Works](RALPH.md) — Full architecture details
- [Cheatsheet](CHEATSHEET.md) — All commands at a glance
