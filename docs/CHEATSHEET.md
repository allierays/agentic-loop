# Vibe and Thrive Cheatsheet

Extended reference for AI-assisted coding. For quick reference, use `/vibe-help` in Claude Code.

---

## The Loop

```
/idea "your feature"     Brainstorm & generate PRD
ralph run                Autonomous coding, commits when done
ralph status             Check progress
/vibe-check              Audit before shipping
```

---

## Pre-commit Hooks

| Hook | What it catches | Blocks? |
|------|-----------------|---------|
| `check-secrets` | API keys, passwords, tokens | Yes |
| `check-hardcoded-urls` | localhost URLs | Yes |
| `check-debug-statements` | console.log, print() | No |
| `check-todo-fixme` | TODO, FIXME comments | No |
| `check-empty-catch` | Empty catch blocks | No |
| `check-snake-case-ts` | snake_case in TypeScript | No |
| `check-dry-violations-python` | Duplicate code (Python) | No |
| `check-dry-violations-js` | Duplicate code (JS/TS) | No |
| `check-magic-numbers` | Hardcoded numbers | No |
| `check-any-types` | TypeScript `any` usage | No |
| `check-function-length` | Functions > 50 lines | No |
| `check-commented-code` | Large commented blocks | No |

**Commands:**
```bash
pre-commit run --all-files          # Run all hooks
pre-commit run check-secrets        # Run specific hook
```

---

## Claude Code Commands

| Command | Purpose |
|---------|---------|
| `/idea` | Brainstorm → PRD → Ready for Ralph |
| `/vibe-help` | Quick reference cheatsheet |
| `/tour` | Interactive walkthrough |
| `/vibe-check` | Full code quality audit |
| `/review` | Code review with security checks |
| `/explain` | Explain code line by line |
| `/styleguide` | Generate design system reference |

---

## Ralph Commands (terminal)

| Command | Purpose |
|---------|---------|
| `ralph run` | Execute stories autonomously |
| `ralph run --max 10` | Limit iterations |
| `ralph status` | Show progress |
| `ralph check` | Run verification only |
| `ralph verify TASK-001` | Verify specific task |
| `ralph signs` | List learned patterns |
| `ralph sign "pattern"` | Teach Ralph a pattern |
| `ralph prd "idea"` | Generate PRD from description |

---

## Common AI Mistakes

| Mistake | Fix |
|---------|-----|
| Uses `any` type | "Create proper interfaces, don't use any" |
| 100+ line function | "Break this into smaller functions" |
| `catch (e) {}` | "Handle the error, don't swallow it" |
| `localhost` URLs | "Use environment variables" |
| `console.log` | "Use proper logging or remove" |
| Copy-paste code | "Extract into reusable function" |
| No error handling | "Add loading, error, empty states" |
| `dangerouslySetInnerHTML` | "Sanitize HTML or use text content" |

---

## Good Prompts

### Be Specific
```
❌ "Build a form"
✅ "Build a login form with email validation,
    error messages, loading state, using
    react-hook-form and our Button component"
```

### Ask for Tests First
```
"Before implementing, write the failing test.
 I want to see it fail, then we'll implement."
```

### Ask What Could Go Wrong
```
"What could go wrong with this code?
 What errors should we handle?"
```

### Reference Existing Patterns
```
"Follow the same pattern as UserForm.tsx"
```

---

## Code Review Checklist

Before committing AI code:

- [ ] No `any` types (unless justified)
- [ ] Functions under 50 lines
- [ ] Errors are handled (not swallowed)
- [ ] URLs use environment variables
- [ ] No console.log in production code
- [ ] No copy-pasted duplicate code
- [ ] Loading/error states handled
- [ ] No security vulnerabilities
- [ ] Tests written (for non-trivial code)

---

## The Vibe Workflow

```
1. IDEA      - /idea "your feature" (brainstorm in plan mode)
2. APPROVE   - Review idea file, approve or edit
3. PRD       - Auto-split into small stories
4. APPROVE   - Review PRD, approve or edit
5. RUN       - ralph run (autonomous execution)
6. CHECK     - ralph status (monitor progress)
7. AUDIT     - /vibe-check (before shipping)
```

---

## Suppress Warnings

When a warning is intentional:

```python
print("Server starting...")  # noqa: debug
```

```typescript
console.log('Initializing...'); // noqa: debug
```

---

## Quick Setup

```bash
npm install vibe-and-thrive
```

That's it. The postinstall sets up everything automatically.

### What Gets Installed

| Item | Location | Purpose |
|------|----------|---------|
| Slash commands | `.claude/commands/` | /idea, /tour, /vibe-check, etc. |
| Ralph config | `.ralph/config.json` | Project settings for verification |
| Pre-commit hooks | `.pre-commit-config.yaml` | Block secrets and security issues |
| Project guide | `CLAUDE.md` | Auto-detected project info for Claude |
| Gitignore entries | `.gitignore` | Ignore Ralph temp files |

---

## Links

- [Bad Patterns Guide](docs/BAD-PATTERNS.md)
- [Prompting Guide](docs/PROMPTING-GUIDE.md)
- [Workflow Guide](docs/WORKFLOW.md)
- [GitHub Repo](https://github.com/allthriveai/vibe-and-thrive)
