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

Review the idea file, then approve. Claude splits it into small, executable stories:

```json
{
  "stories": [
    {
      "id": "US-001",
      "title": "Add OAuth provider configuration",
      "acceptanceCriteria": ["..."],
      "testSteps": ["curl /api/auth/config returns 200"]
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
1. Picks the next failing story
2. Codes to satisfy acceptance criteria
3. Runs test steps to verify
4. Commits when tests pass
5. Moves to next story
6. Repeats until done

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
