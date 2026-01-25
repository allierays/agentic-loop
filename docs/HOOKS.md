# Hooks Reference

agentic-loop provides two types of hooks:

1. **Pre-commit hooks** - Run at git commit time (catch issues before they're committed)
2. **Claude Code hooks** - Run during Claude sessions (real-time feedback while coding)

---

## Claude Code Hooks (Real-time)

These hooks fire during Claude Code sessions, providing real-time feedback while Ralph or Claude works.

### Installation

```bash
# Install to project (recommended)
npx ralph hooks

# Install globally (all projects)
npx ralph hooks --global

# Force reinstall (fixes broken hooks)
npx ralph hooks --force
```

> **Requirement:** Claude Code hooks require `jq`. On macOS with Homebrew, it's installed automatically. On Linux, install with `sudo apt install jq` (Ubuntu) or your package manager.

### Important: Machine-Specific Paths

`.claude/settings.json` contains absolute paths to hook scripts and should **not** be committed to git. The installer automatically adds it to `.gitignore`.

If you move your project or clone on a new machine, reinstall hooks with `npx ralph hooks --force`.

### Available Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `protect-prd.sh` | PreToolUse | Blocks edits to prd.json (Ralph manages it) |
| `warn-debug.sh` | PostToolUse | Warns about console.log/debugger in new code |
| `warn-secrets.sh` | PostToolUse | Warns about hardcoded secrets/API keys |
| `warn-urls.sh` | PostToolUse | Warns about hardcoded localhost URLs |
| `warn-empty-catch.sh` | PostToolUse | Warns about empty catch/except blocks |
| `inject-context.sh` | SessionStart | Loads signs + progress into session context |
| `save-learnings.sh` | Stop | Extracts learnings for potential signs |
| `log-tools.sh` | PostToolUse | Logs tool usage to .ralph/tool-log.txt |

### Security Hooks (synced with pre-commit)

The `warn-secrets.sh` and `warn-urls.sh` hooks use the same patterns as the pre-commit hooks, providing consistent checks:

**Secrets detected:**
- AWS Access Keys (AKIA...)
- Stripe API keys (sk_live_*, sk_test_*)
- GitHub tokens (ghp_*, gho_*, etc.)
- Slack tokens (xoxb-*, xoxp-*, etc.)
- SendGrid API keys (SG.*)
- Private keys (-----BEGIN PRIVATE KEY-----)
- Generic API key patterns

**URLs detected:**
- localhost URLs (http://localhost:3000)
- 127.0.0.1 URLs
- Hardcoded production URLs (excluding safe CDNs)

### Manual Configuration

If you prefer manual setup, add to `~/.claude/settings.json` or `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "/path/to/protect-prd.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "/path/to/warn-debug.sh" }]
      }
    ],
    "SessionStart": [
      {
        "hooks": [{ "type": "command", "command": "/path/to/inject-context.sh" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "/path/to/save-learnings.sh" }]
      }
    ]
  }
}
```

### Hook Output

Claude Code hooks produce:
- `.ralph/tool-log.txt` - Record of all tools used in session
- `.ralph/suggested-signs.txt` - Potential patterns to add as signs

---

## Pre-commit Hooks (Git)

All 16 pre-commit hooks available in agentic-loop.

## Hooks That Block Commits

These hooks return exit code 1 to prevent commits with security issues.

| Hook | What it catches |
|------|-----------------|
| `check-secrets` | API keys, passwords, tokens, private keys |
| `check-hardcoded-urls` | `localhost` and `127.0.0.1` URLs |

## Hooks That Warn Only

These hooks warn but allow commits to proceed.

| Hook | What it catches |
|------|-----------------|
| `check-debug-statements` | `console.log`, `print()`, `debugger`, `breakpoint()` |
| `check-todo-fixme` | `TODO`, `FIXME`, `XXX`, `HACK`, `BUG` comments |
| `check-empty-catch` | Empty `catch` or `except: pass` blocks |
| `check-snake-case-ts` | `snake_case` properties in TypeScript interfaces |
| `check-dry-violations-python` | Duplicate code blocks, repeated strings, identical functions |
| `check-dry-violations-js` | Same for JS/TS, plus repeated className patterns |
| `check-magic-numbers` | Hardcoded numbers that should be constants |
| `check-docker-platform` | Missing `--platform` in Docker builds (ARM/x86 issues) |
| `check-any-types` | TypeScript `any` type usage |
| `check-function-length` | Functions over 50 lines |
| `check-commented-code` | Large blocks of commented-out code |
| `check-deep-nesting` | 4+ levels of nested if/for/while |
| `check-console-error` | `console.log` used for error handling |
| `check-unsafe-html` | `innerHTML`/`dangerouslySetInnerHTML` without sanitization |

## Full Configuration

```yaml
repos:
  - repo: https://github.com/allthriveai/agentic-loop
    rev: v0.2.0
    hooks:
      # Security (blocks commits)
      - id: check-secrets
      - id: check-hardcoded-urls

      # Code quality (warnings)
      - id: check-debug-statements
      - id: check-todo-fixme
      - id: check-empty-catch
      - id: check-snake-case-ts
      - id: check-dry-violations-python
      - id: check-dry-violations-js
      - id: check-magic-numbers
      - id: check-docker-platform

      # AI-specific issues (warnings)
      - id: check-any-types
      - id: check-function-length
      - id: check-commented-code
      - id: check-deep-nesting
      - id: check-console-error
      - id: check-unsafe-html
```

## Excluding Files

Each hook supports standard pre-commit exclude patterns:

```yaml
- id: check-debug-statements
  exclude: |
    (?x)^(
      .*/tests/.*|
      .*\.test\.(ts|js|py)$
    )$
```

## Suppressing Warnings

Add comments to suppress specific warnings:

```python
print("Starting server...")  # noqa: debug
```

```javascript
console.log('Initializing...'); // noqa: debug
```

## Running Manually

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hook
pre-commit run check-secrets --all-files

# Run with verbose output
pre-commit run check-dry-violations-python --all-files --verbose
```

## CLI Commands

Install via npm and use the `vibe-check` CLI:

```bash
# Install
npm install agentic-loop

# Check all files
npx vibe-check .

# Check specific files
npx vibe-check src/app.ts src/utils.ts

# Run specific checks only
npx vibe-check . --only secrets,urls,debug

# Skip specific checks
npx vibe-check . --skip any-types,snake-case

# Different output formats
npx vibe-check . --format pretty   # Default: colored terminal
npx vibe-check . --format json     # JSON for CI/scripts
npx vibe-check . --format compact  # One line per issue
```

## Updating

```bash
pre-commit autoupdate --repo https://github.com/allthriveai/agentic-loop
pre-commit install
```
