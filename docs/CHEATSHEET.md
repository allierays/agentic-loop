# Agentic Loop Cheatsheet

Quick reference for all commands.

---

## The Workflow

```
/prd "your feature"            → Brainstorm, generate & validate PRD
npx agentic-loop run           → Autonomous coding loop
npx agentic-loop status        → Check progress
/vibe-check                    → Audit before shipping
```

---

## CLI Commands

| Command | Purpose |
|---------|---------|
| `npx agentic-loop setup` | Set up hooks, commands, and config |
| `npx agentic-loop run` | Execute stories autonomously (activity feed + terminal tint on macOS) |
| `npx agentic-loop run --max 10` | Limit to 10 iterations (no limit by default) |
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
| `npx agentic-loop uat` | Team acceptance testing (explore, test, fix) |
| `npx agentic-loop uat --plan-only` | Generate UAT plan without executing |
| `npx agentic-loop chaos-agent` | Chaos Agent red team (adversarial testing) |
| `npx agentic-loop chaos-agent --plan-only` | Generate chaos plan without executing |
| `npx agentic-loop lessons` | List learned patterns |
| `npx agentic-loop lesson "pattern" category` | Add a pattern |
| `npx agentic-loop progress` | Show recent log entries |

---

## Slash Commands (in Claude Code)

| Command | Purpose |
|---------|---------|
| `/prd` | Brainstorm, harden, generate & validate PRD (runs prd-check automatically) |
| `/prd-check` | Re-validate PRD after manual edits |
| `/tour` | Interactive walkthrough |
| `/vibe-check` | Code quality audit |
| `/review` | Security-focused code review |
| `/lesson` | Add a learned pattern |
| `/explain` | Explain code line by line |
| `/styleguide` | Generate UI component reference |
| `/color` | Pick Ralph's terminal background tint |
| `/tab-rename` | Rename terminal tab |
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

## UAT & Chaos Agent

```bash
# Acceptance testing — "does this work correctly?"
npx agentic-loop uat                    # Team → plan → TDD loop
npx agentic-loop uat --plan-only        # Generate plan only
npx agentic-loop uat --focus auth       # Focus on one area
npx agentic-loop uat --no-fix           # Write tests, don't fix bugs

# Adversarial testing — "can we break it?"
npx agentic-loop chaos-agent                  # Red team → plan → TDD loop
npx agentic-loop chaos-agent --plan-only      # Generate chaos plan only
npx agentic-loop chaos-agent --no-fix         # Find vulns without fixing
```

Both use Agent Teams for coordinated browser exploration, then strict TDD (RED writes test, GREEN fixes app).

---

## Links

- [How Ralph Works](RALPH.md)
- [UAT & Chaos Agent](UAT.md)
- [Hooks Reference](HOOKS.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)
