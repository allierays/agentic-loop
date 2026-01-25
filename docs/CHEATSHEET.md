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
| `npx agentic-loop run` | Execute stories autonomously |
| `npx agentic-loop run --fast` | Skip code review (~2x faster) |
| `npx agentic-loop run --max 10` | Limit iterations |
| `npx agentic-loop stop` | Stop after current story |
| `npx agentic-loop status` | Show progress |
| `npx agentic-loop check` | Run verification only |
| `npx agentic-loop verify TASK-001` | Verify specific story |
| `npx agentic-loop signs` | List learned patterns |
| `npx agentic-loop sign "pattern" category` | Add a pattern |
| `npx agentic-loop progress` | Show recent log entries |

---

## Slash Commands (in Claude Code)

| Command | Purpose |
|---------|---------|
| `/idea` | Brainstorm feature → generate PRD |
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
| `protect-prd.sh` | Blocks edits to prd.json |

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

## Links

- [How Ralph Works](RALPH.md)
- [Hooks Reference](HOOKS.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)
