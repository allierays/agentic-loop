# Claude Code Commands Reference

Slash commands for Claude Code that power the agentic-loop workflow.

## Installation

```bash
npm install agentic-loop
```

The postinstall automatically copies commands to your project's `.claude/commands/`.

---

## Available Commands

### `/idea`

**The core workflow command.** Brainstorm a feature and generate a PRD for Ralph.

```
/idea "add user authentication with OAuth"
```

Claude will:
1. Enter plan mode
2. Explore your codebase
3. Ask clarifying questions
4. Write idea to `docs/ideas/{feature}.md`
5. Open for your approval
6. Split into stories in `.ralph/prd.json`
7. Open PRD for your approval

Two approval gates. Nothing executes without your say-so.

---

### `/vibe-help`

Quick reference cheatsheet for all commands.

```
/vibe-help
```

Shows the workflow, all slash commands, Ralph commands, and setup instructions.

---

### `/tour`

Interactive walkthrough of agentic-loop.

```
/tour
```

Great for new users. Explains:
- The /idea → Ralph → Ship workflow
- How pre-commit hooks work
- Available commands

---

### `/vibe-check`

Full code quality audit. Scans for common AI-generated issues.

```
/vibe-check
```

**Checks for:**
- Debug statements (console.log, print)
- Hardcoded secrets
- Empty catch blocks
- TODO/FIXME comments
- TypeScript `any` usage
- Hardcoded URLs

**Output:**
```
## Vibe Check Report

### High Priority
- api.ts:15 - localhost URL should use env var
- config.py:42 - Looks like an API key

### Low Priority
- utils.py:23 - print() statement
- auth.py:67 - TODO: implement refresh token
```

---

### `/review`

Code review with security checks. More thorough than `/vibe-check`.

```
/review
/review src/api/auth.ts
```

**Checks for:**
- OWASP Top 10 vulnerabilities
- SQL injection, XSS, CSRF
- Error handling gaps
- Type safety issues
- Performance problems
- Code quality

**Output includes severity levels:**
- Critical (must fix before merge)
- High (should fix)
- Medium (consider fixing)
- Low (nice to have)

---

### `/explain`

Explain code line by line. Great for understanding unfamiliar code.

```
/explain
/explain src/services/auth.ts
```

Claude will:
1. Provide high-level overview
2. Walk through each section
3. Highlight key patterns
4. Note potential gotchas

---

### `/styleguide`

Generate a design system reference page.

```
/styleguide
```

Claude will:
1. Detect your tech stack
2. Ask about your design preferences (vibe, colors, radius)
3. Generate a `/styleguide` route
4. Create components if needed

Great for ensuring consistent UI across AI-generated code.

---

## CLAUDE.md

The setup also creates a `CLAUDE.md` file that teaches Claude your coding standards:

- Don't leave debug statements
- Use environment variables for URLs
- Use camelCase in TypeScript
- Handle errors properly
- Never hardcode secrets

Customize it for your project's patterns.

---

## Pre-commit Hooks

The setup installs pre-commit hooks that run on every `git commit`:

| Hook | Blocks? | What it catches |
|------|---------|-----------------|
| `check-secrets` | Yes | API keys, passwords, tokens |
| `check-hardcoded-urls` | Yes | localhost URLs |
| `check-debug-statements` | No | console.log, print() |
| `check-empty-catch` | No | Empty catch blocks |
| `check-any-types` | No | TypeScript `any` usage |

Hooks that block will prevent the commit. Warnings let you commit but alert you.

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `/idea` | Brainstorm → PRD → Ready for Ralph |
| `/vibe-help` | Quick reference cheatsheet |
| `/tour` | Interactive walkthrough |
| `/vibe-check` | Code quality audit |
| `/review` | Deep code review |
| `/explain` | Explain code line by line |
| `/styleguide` | Generate design system |
