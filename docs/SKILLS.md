# Claude Code Skills Reference

Slash commands (skills) for Claude Code that power the agentic-loop workflow.

> **Note:** Skills are stored in `.claude/skills/<name>/SKILL.md` format.

## Installation

```bash
npm install agentic-loop
```

The postinstall automatically copies skills to your project's `.claude/skills/`.

---

## Available Commands

### `/prd`

**The core workflow command.** Generate an executable PRD for Ralph.

```
/prd "add user authentication with OAuth"
/prd docs/ideas/auth.md
/prd plans/my-feature
```

Claude will:
1. Read your input (description, idea file, or plan file)
2. Ask hardening questions (security, scale, scope)
3. Explore your codebase
4. Split into stories in `.ralph/prd.json`
5. Run prd-check validation automatically (structural checks + lessons cross-reference)
6. Auto-fix any issues found
7. Open for your approval

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
- The /prd → Ralph → Ship workflow
- How pre-commit hooks work
- Available commands

---

### `/prd-check`

**Re-validate your PRD** after manual edits. (Runs automatically as part of `/prd`.)

```
/prd-check
```

Claude will:
1. Run validation in dry-run mode (no auto-fix)
2. Present any issues found
3. Ask if you want to fix them

Note: `/prd` now runs prd-check automatically during generation, so you only need `/prd-check` standalone when you've manually edited `.ralph/prd.json` and want to re-validate. Also runs any custom checks in `.ralph/checks/prd/`.

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

### `/lesson`

**Add a learned pattern** that Ralph will remember for future stories.

```
/lesson "Always use environment variables for API keys" backend
/lesson "Import from @/components, not relative paths" frontend
```

Lessons are stored in `.ralph/lessons.json` and injected into every Claude session. Use this to teach patterns from past failures.

---

### `/my-dna`

**Set up your personal coding preferences.** Creates `~/.claude/DNA.md`.

```
/my-dna
```

Claude will ask about your:
- Coding style preferences
- Error handling approach
- Comment philosophy
- Testing habits

Your DNA is read during every Ralph session, so code reflects your personal style.

---

### `/color`

**Pick the terminal background tint** Ralph uses during `npx agentic-loop run`.

```
/color
```

Choose from presets (dark navy, teal, red) or enter a custom hex. macOS Terminal.app only.

---

### `/tab-rename`

**Rename the current terminal tab** so you can tell your Claude Code sessions apart.

```
/tab-rename my-api
/tab-rename
```

When called with an argument, sets the tab title immediately. Without an argument, auto-detects a name from your project. Works in macOS Terminal.app and iTerm2.

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
| `/prd` | Brainstorm → Harden → PRD → Validate → Ready for Ralph |
| `/prd-check` | Re-validate PRD after manual edits |
| `/vibe-help` | Quick reference cheatsheet |
| `/tour` | Interactive walkthrough |
| `/vibe-check` | Code quality audit |
| `/review` | Deep code review |
| `/explain` | Explain code line by line |
| `/styleguide` | Generate design system |
| `/lesson` | Add a learned pattern |
| `/my-dna` | Set up personal coding preferences |
| `/color` | Pick Ralph's terminal background tint |
| `/tab-rename` | Rename terminal tab |
