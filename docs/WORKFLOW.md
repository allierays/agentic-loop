# The Vibe Coding Workflow

From idea to shipped code with AI.

---

## The Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  1. IDEA  →  2. APPROVE  →  3. RUN  →  4. AUDIT  →  5. SHIP │
└─────────────────────────────────────────────────────────────┘
```

### Step 1: Brainstorm Your Idea

Start with `/idea` in Claude Code:

```
/idea "add user authentication with OAuth"
```

Claude enters plan mode and helps you:
- Understand the goal
- Explore the codebase for existing patterns
- Ask clarifying questions
- Design the approach

**Output:** `docs/ideas/user-authentication.md`

### Step 2: Approve the PRD

Review the idea file, then approve. Claude splits it into small, executable stories with:
- **Architecture** - Where to put files, what to reuse, naming conventions
- **Scalability** - Pagination, caching, indexes, rate limits
- **Files** - Exactly which files to create/modify/reuse

```json
{
  "architecture": {
    "directories": { "api": "src/api/", "types": "src/types/" },
    "doNotCreate": ["New fetch wrapper (use existing)"]
  },
  "stories": [
    {
      "id": "TASK-001",
      "title": "Add OAuth provider configuration",
      "files": { "create": ["src/api/auth/config.ts"], "reuse": ["src/lib/db.ts"] },
      "acceptanceCriteria": ["..."],
      "scale": { "caching": "cache for 1hr", "rateLimit": "100/min" }
    }
  ]
}
```

**Output:** `.ralph/prd.json`

Two approval gates:
1. Approve the idea before splitting
2. Approve the PRD before executing

Nothing happens without your say-so.

### Step 3: Let Ralph Run

In your terminal:

```bash
ralph run
```

Ralph works through stories autonomously:

```
┌─────────────────────────────────────────────────────────────┐
│                     ralph run                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │ Get next incomplete     │
              │ story (TODO)            │
              └─────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │  Build prompt with:     │
              │  - Story details        │
              │  - Previous errors      │◄──────────────┐
              │  - Signs (patterns)     │               │
              └─────────────────────────┘               │
                            │                          │
                            ▼                          │
              ┌─────────────────────────┐               │
              │  Claude writes code     │               │
              └─────────────────────────┘               │
                            │                          │
                            ▼                          │
              ┌─────────────────────────┐               │
              │  6-Step Verification    │               │
              │  1. Code review         │               │
              │  2. Lint/build          │               │
              │  3. Unit tests          │               │
              │  4. E2E/API tests       │               │
              │  5. Browser/API check   │               │
              │  6. PRD test steps      │               │
              └─────────────────────────┘               │
                            │                          │
                   ┌────────┴────────┐                 │
                   │                 │                 │
                   ▼                 ▼                 │
              ┌─────────┐      ┌──────────┐            │
              │  DONE   │      │ NOT YET  │────────────┘
              └─────────┘      └──────────┘
                   │             Save errors,
                   ▼             try again
              ┌─────────────────────────┐
              │  git commit             │
              │  Mark story DONE        │
              │  → Next story           │
              └─────────────────────────┘
```

Monitor progress anytime:

```bash
ralph status
```

### Step 4: Audit Before Shipping

Run a code quality check:

```
/vibe-check
```

Catches common AI-generated issues:
- Debug statements
- Hardcoded secrets
- Empty catch blocks
- TODO comments
- Type issues

### Step 5: Ship It

Pre-commit hooks run automatically on `git commit`:

**Blocked (errors):**
- Hardcoded secrets and API keys
- Hardcoded localhost URLs
- Security vulnerabilities

**Warned:**
- TypeScript `any` types
- Empty catch blocks
- Debug statements

---

## Quick Reference

| Step | Action | Tool |
|------|--------|------|
| 1. Idea | Brainstorm feature | `/idea` |
| 2. Approve | Review idea + PRD | TextEdit |
| 3. Run | Autonomous coding | `ralph run` |
| 4. Audit | Check quality | `/vibe-check` |
| 5. Ship | Commit with guards | `git commit` |

---

## Supporting Commands

| Command | When to use |
|---------|-------------|
| `/review` | Deep code review before merge |
| `/explain` | Understand existing code |
| `/styleguide` | Generate design system reference |
| `/vibe-help` | Quick reference cheatsheet |
| `ralph status` | Check progress |
| `ralph signs` | List learned patterns |

---

## Workflow Variations

### For Bug Fixes

1. **Describe** the bug in `/idea`
2. **Approve** the fix PRD
3. **Run** Ralph to implement
4. **Verify** with `/vibe-check`

### For Quick Changes

Not everything needs the full workflow. For trivial changes:

1. Make the change
2. Run `/vibe-check`
3. Commit

Use judgment—but for anything non-trivial, use `/idea`.

---

## Common Pitfalls

### Skipping the Idea Phase

Jumping straight to code means:
- Unclear requirements
- Missed edge cases
- Scope creep

Take time to brainstorm. It pays off.

### Not Reviewing Ralph's Work

Ralph commits working code, but "works" doesn't mean "optimal."

Always run `/vibe-check` before shipping.

### Ignoring Warnings

Pre-commit warnings exist for a reason. Don't just suppress them.

If a warning is intentional:
```typescript
console.log('Server starting...'); // noqa: debug
```

---

## The Goal

After following this workflow, you should have:

- **Clear requirements** documented in `docs/ideas/`
- **Working code** that passes test steps
- **Clean code** audited for issues
- **Version control** with meaningful commits

Ship confidently. The guardrails have your back.
