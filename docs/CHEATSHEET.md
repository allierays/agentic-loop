# Agentic Loop Cheatsheet

Quick reference for all commands.

---

## The Workflow

```
/idea "your feature"           → Brainstorm & generate PRD
npx agentic-loop run           → Autonomous coding loop
npx agentic-loop status        → Check progress
/vibe-check                    → Audit before shipping
```

---

## CLI Commands

| Command | Purpose |
|---------|---------|
| `npx agentic-loop setup` | Set up hooks, commands, and config |
| `npx agentic-loop run` | Execute stories autonomously (shows live activity feed) |
| `npx agentic-loop run --max 10` | Limit iterations |
| `npx agentic-loop run --quiet` | Suppress the live activity feed |
| `npx agentic-loop stop` | Stop after current story |
| `npx agentic-loop status` | Show progress |
| `npx agentic-loop check` | Run verification only |
| `npx agentic-loop verify TASK-001` | Verify specific story |
| `npx agentic-loop test` | Run full test suite + PRD tests |
| `npx agentic-loop coverage` | Generate test coverage report |
| `npx agentic-loop ci` | Install GitHub Actions workflows |
| `npx agentic-loop prd-check` | Validate PRD with auto-fix |
| `npx agentic-loop prd-check --dry-run` | Validate PRD (report only) |
| `npx agentic-loop signs` | List learned patterns |
| `npx agentic-loop sign "pattern" category` | Add a pattern |
| `npx agentic-loop progress` | Show recent log entries |

---

## Slash Commands (in Claude Code)

| Command | Purpose |
|---------|---------|
| `/idea` | Brainstorm feature → create idea file → generate PRD |
| `/prd` | Generate PRD directly from idea file or description |
| `/prd-check` | Validate PRD before running the loop |
| `/tour` | Interactive walkthrough |
| `/vibe-check` | Code quality audit |
| `/review` | Security-focused code review |
| `/sign` | Add a learned pattern |
| `/explain` | Explain code line by line |
| `/styleguide` | Generate UI component reference |
| `/my-dna` | Set up your coding preferences |

---

## Pre-commit Hooks

| Hook | What it catches |
|------|-----------------|
| `check-secrets` | API keys, passwords, tokens |
| `check-hardcoded-urls` | localhost URLs |
| `check-debug` | console.log, print() |

```bash
pre-commit run --all-files     # Run all hooks
```

---

## Claude Code Hooks

Real-time warnings while Claude writes code:

| Hook | Purpose |
|------|---------|
| `warn-debug.sh` | Warns about console.log/debugger |
| `warn-secrets.sh` | Warns about hardcoded secrets |
| `warn-urls.sh` | Warns about localhost URLs |


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

## CI/CD

```bash
npx agentic-loop ci install      # Set up GitHub Actions
npx agentic-loop ci status       # Check workflow status
```

| Workflow | Runs on | Speed |
|----------|---------|-------|
| PR Check | Pull requests | Fast (~1-2 min) |
| Nightly | Daily 3am UTC | Full (~5-10 min) |

---

## Testing

```bash
npx agentic-loop test            # Full suite + PRD tests
npx agentic-loop test unit       # Unit tests only
npx agentic-loop test prd        # PRD testSteps only
npx agentic-loop coverage        # Coverage report
```

---

## Links

- [How Ralph Works](RALPH.md)
- [Hooks Reference](HOOKS.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)
