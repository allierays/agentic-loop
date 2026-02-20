# Make It Yours

Ralph works out of the box, but every project is different. This guide shows you how to teach Ralph your preferences so the code it writes feels like yours.

---

## What Happens Automatically

These features are set up and run for you — no manual steps needed.

### Setup (`npx agentic-loop setup`)

When you run setup, Ralph automatically:

- **Detects your project type** (Node.js, Python, Go, Rust, fullstack) and creates `.ralph/config.json` with sensible defaults — test commands, URLs, directories
- **Installs pre-commit hooks** that block secrets, hardcoded URLs, debug statements, and TODO/FIXME comments from being committed
- **Installs Claude Code hooks** that warn in real-time while Claude is coding — catching secrets, hardcoded URLs, and debug statements before they're even saved
- **Installs timeout utilities** on macOS (via `brew install coreutils`) so session time limits are enforced reliably

### During the Loop (`npx agentic-loop run`)

Each time Ralph starts or processes a story, it automatically:

- **Checks for updates** — once per day, Ralph checks npm for a newer version. If one is available, it offers to update and restart automatically.
- **Tints the terminal background** — on macOS Terminal.app, Ralph applies a subtle dark teal background so you can instantly tell it apart from your Claude Code terminal. The original color is restored when the loop ends (Ctrl+C, completion, or error). Run `/color` in a Claude session to pick a different tint, or disable it entirely. No-op on Linux, iTerm2, VS Code, and other terminals.
- **Runs preflight checks** — verifies API/frontend connectivity, Docker services, database migrations, and timeout utilities before starting
- **Validates your PRD** — checks for missing test steps, vague requirements, and structural issues. If it finds problems, Claude auto-fixes them
- **Verifies code after Claude writes it** — runs a 5-step pipeline: lint, unit tests, PRD test steps, API smoke test, frontend smoke test
- **Learns from retries** — when a story fails then passes after retries, Ralph extracts what went wrong as a "sign" and remembers it for future stories

---

## What You Can Customize

These are things you run yourself to teach Ralph your preferences.

### Tell Claude How You Like to Code

Run `/my-dna` in a Claude session. Claude will ask you questions about how you like your code — naming style, how you handle errors, whether you prefer comments or self-documenting code. Your answers get saved and included in every Ralph session from that point on.

```
/my-dna
```

> **Tip:** You don't need to know the "right" answers. Just describe how you work. "I like short functions" or "I always want error messages to be user-friendly" is enough.

---

### Keep Your UI Consistent

If your project has a frontend, run `/styleguide` to generate a visual reference of your colors, typography, and component patterns. Ralph will use this as a reference when building new UI.

```
/styleguide
```

This creates an HTML file you can open in your browser to see everything at a glance. Frontend stories reference it automatically.

---

### Teach Ralph From Its Mistakes

When Ralph keeps making the same mistake — wrong import path, wrong naming convention, anything — you can teach it with `/sign`:

```
/sign "Always use camelCase for API response fields" backend
```

```
/sign "Import Button from @/components/ui, not shadcn directly" frontend
```

Think of signs as sticky notes for Ralph. They get included in every prompt so it doesn't forget. Ralph also learns signs automatically — when a story fails then succeeds after retries, it extracts what went wrong and saves it to `.ralph/signs.json`.

---

### Add Your Own PRD Rules

Every project has its own standards. You can add custom checks that run alongside the built-in ones. Just ask Claude:

```
Create a prd-check that ensures every story has a description
```

```
Add a custom prd-check that warns if a story touches more than 10 files
```

```
Write a prd-check that requires backend stories to have error handling in their test steps
```

Claude will create the check script and put it in the right place (`.ralph/checks/prd/` inside your project). These checks run automatically every time Ralph validates a PRD.

> **Good to know:** Built-in checks get auto-fixed by Claude when possible. Custom checks get reported for you to review — Ralph won't try to guess what your custom rules mean.

If you want to temporarily turn off a custom check, ask Claude:

```
Disable the check-complexity prd-check
```

---

### Tune Your Config

If you need to change how Ralph behaves — session length, retry limits, which URLs to test against — ask Claude:

```
Set Ralph's max session time to 10 minutes
```

```
Turn off linting checks in Ralph
```

Claude will update `.ralph/config.json` for you. See [Configuration Reference](RALPH.md#configuration-reference) for everything that's configurable.

---

### On-Demand Quality Checks

These aren't part of the automated loop — they're tools you can use whenever you want a second opinion:

| Type this | What it does |
|-----------|-------------|
| `/vibe-check` | Scans for common AI coding patterns — leftover console.logs, TODOs, dead code |
| `/review` | Full code review with suggestions for improvements |

---

## Quick Reference

| Feature | When it runs | Automatic or manual? |
|---------|-------------|---------------------|
| Project detection + config | `npx agentic-loop setup` | Automatic |
| Pre-commit hooks | Every `git commit` | Automatic (installed during setup) |
| Claude Code hooks | While Claude edits files | Automatic (installed during setup) |
| Timeout utility install | `npx agentic-loop setup` | Automatic (macOS with Homebrew) |
| Auto-update check | Start of `npx agentic-loop run` | Automatic (once per day) |
| Terminal background tint | Start of `npx agentic-loop run` | Automatic (macOS Terminal.app only) |
| Preflight checks | Start of `npx agentic-loop run` | Automatic |
| PRD validation + auto-fix | Start of loop | Automatic |
| Code verification (5-step) | After Claude writes each story | Automatic |
| Sign auto-promotion | After story retry succeeds | Automatic |
| `/color` | When you run it | Manual |
| `/tab-rename` | When you run it | Manual |
| `/my-dna` | When you run it | Manual |
| `/styleguide` | When you run it | Manual |
| `/sign` | When you run it | Manual |
| Custom PRD checks | When you create them | Manual (then runs automatically) |
| `/vibe-check` | When you run it | Manual |
| `/review` | When you run it | Manual |

---

## See Also

- [Cheatsheet](CHEATSHEET.md) — All commands at a glance
- [How Ralph Works](RALPH.md) — Full architecture
- [Hooks Reference](HOOKS.md) — Details on the safety checks
