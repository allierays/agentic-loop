# Ralph: Autonomous Execution

Ralph is the autonomous coding agent that executes your PRDs.

---

## How Ralph Works

```
┌─────────────────────────────────────────────────────────────┐
│  Pick Story  →  Code  →  Test  →  Commit  →  Next Story     │
└─────────────────────────────────────────────────────────────┘
```

1. **Pick Story** - Gets next failing story from `.ralph/prd.json`
2. **Code** - Spawns Claude to implement the story
3. **Test** - Runs verification steps to check if it works
4. **Commit** - Auto-commits with `feat(TASK-001): Task title`
5. **Next** - Moves to next story, repeats until done

---

## Commands

```bash
ralph run                # Start the autonomous loop
ralph run --max 10       # Limit to 10 iterations
ralph status             # Show progress
ralph check              # Run verification only
ralph verify TASK-001    # Verify specific task
```

---

## The PRD Format

Ralph reads from `.ralph/prd.json`:

```json
{
  "feature": {
    "name": "User Authentication",
    "status": "in_progress"
  },
  "stories": [
    {
      "id": "TASK-001",
      "title": "Add login endpoint",
      "passes": false,
      "acceptanceCriteria": [
        "POST /api/auth/login accepts email and password",
        "Returns JWT token on success",
        "Returns 401 on invalid credentials"
      ],
      "testSteps": [
        "curl -X POST http://localhost:3000/api/auth/login -d '{\"email\":\"test@example.com\",\"password\":\"password123\"}' returns 200",
        "curl -X POST http://localhost:3000/api/auth/login -d '{\"email\":\"test@example.com\",\"password\":\"wrong\"}' returns 401"
      ],
      "dependsOn": []
    }
  ]
}
```

### Key Fields

| Field | Purpose |
|-------|---------|
| `id` | Unique task identifier (TASK-001, TASK-002, etc.) |
| `title` | Short description for commit messages |
| `passes` | Whether story verification succeeded |
| `acceptanceCriteria` | What the code must do |
| `testSteps` | How to verify it works (curl, scripts, etc.) |
| `dependsOn` | Stories that must pass first |

---

## Writing Good Test Steps

Test steps should be **concrete and executable**.

### Good Test Steps

```json
"testSteps": [
  "curl http://localhost:3000/api/users returns 200",
  "curl http://localhost:3000/api/users | jq '.users | length' returns > 0",
  "npm test -- --grep 'user api' passes"
]
```

### Bad Test Steps

```json
"testSteps": [
  "The API should work",
  "Users can log in",
  "Check the database"
]
```

### Test Step Types

**API checks:**
```
curl http://localhost:3000/api/health returns 200
curl -X POST http://localhost:3000/api/users -d '{"name":"test"}' returns 201
```

**Script execution:**
```
npm test passes
python -m pytest tests/test_auth.py passes
```

**File checks:**
```
test -f src/components/Button.tsx exists
grep "export function Button" src/components/Button.tsx found
```

---

## Signs: Learned Patterns

Ralph learns from past sessions. Use signs to teach patterns:

```bash
ralph sign "Always use camelCase for API response fields" api
ralph sign "Import from @/components, not relative paths" frontend
ralph signs  # List all signs
```

Signs are stored in `.ralph/signs.json` and injected into every Claude session.

---

## Configuration

`.ralph/config.json`:

```json
{
  "maxSessionSeconds": 600,
  "autoCommit": true
}
```

| Setting | Default | Purpose |
|---------|---------|---------|
| `maxSessionSeconds` | 600 | Timeout per story (10 min) |
| `autoCommit` | true | Commit after each story passes |

---

## Progress Tracking

Ralph logs to `.ralph/progress.txt`:

```
[2024-01-15T10:30:00] STARTED TASK-001
[2024-01-15T10:32:15] COMPLETED TASK-001
[2024-01-15T10:32:20] STARTED TASK-002
[2024-01-15T10:35:45] FAILED TASK-002 Verification failed, will retry
[2024-01-15T10:38:00] COMPLETED TASK-002
```

View recent progress:
```bash
ralph progress
```

---

## Archiving

When all stories pass, Ralph archives the PRD:

```
.ralph/archive/prd-20240115-103800.json
```

Start a new feature with:
```bash
/idea "next feature"
# or
ralph prd "feature description"
```

---

## Troubleshooting

### Story keeps failing

1. Check `ralph status` for which story
2. Run `ralph verify TASK-001` to see the failure
3. Check if test steps are correct in `.ralph/prd.json`
4. Manually edit the PRD if needed

### Ralph times out

Increase timeout in `.ralph/config.json`:
```json
{
  "maxSessionSeconds": 900
}
```

### Want to skip a story

Mark it as passing manually:
```bash
jq '.stories[0].passes = true' .ralph/prd.json > tmp.json && mv tmp.json .ralph/prd.json
```

Or remove it from the PRD entirely.

---

## Best Practices

1. **Small stories** - Each story should be completable in one session
2. **Concrete test steps** - Use curl, scripts, or file checks
3. **Clear acceptance criteria** - Tell Claude exactly what to build
4. **Use signs** - Teach patterns that apply across stories
5. **Monitor progress** - Check `ralph status` periodically
