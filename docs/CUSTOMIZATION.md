# Customization & Guardrails

## Customize Your Output

### /my-dna - Your Coding Style

Define your coding preferences so generated code matches your style:

```bash
claude --dangerously-skip-permissions
/my-dna
```

Claude will ask about your preferences (naming conventions, comment style, error handling patterns) and save them to `~/.claude/DNA.md`. Every Ralph session includes this context.

### /styleguide - UI Consistency

Generate a component reference for consistent frontend design:

```bash
/styleguide
```

Creates an HTML styleguide at `docs/styleguide.html` showing your colors, typography, and component patterns. Frontend stories reference this automatically.

### /sign - Teach Patterns

When Ralph makes the same mistake repeatedly, teach it:

```bash
# Via CLI
npx agentic-loop sign "Always use camelCase for API response fields" backend

# Via Claude session
/sign "Import Button from @/components/ui, not shadcn directly" frontend
```

Signs are saved to `.ralph/signs.json` and injected into every prompt.

### config.json - Tune Your Setup

Project-specific configuration in `.ralph/config.json`:

```json
{
  "urls": {
    "frontend": "http://localhost:3000",
    "backend": "http://localhost:8000"
  },
  "checks": {
    "lint": true,
    "test": true
  },
  "maxSessionSeconds": 600,
  "maxStoryRetries": 8
}
```

See [Configuration Reference](RALPH.md#configuration-reference) for all options.

---

## Built-in Guardrails

### On-Demand Quality Checks

| Command | What It Does |
|---------|--------------|
| `/vibe-check` | Scan for AI coding patterns (console.logs, TODOs, dead code) |
| `/review` | Code review for issues, improvements, best practices |

### Pre-commit Hooks

Automatically installed during setup. Block commits that contain:

- Secrets (API keys, passwords, tokens)
- Hardcoded URLs (localhost, 127.0.0.1)
- Debug statements (console.log, debugger, print)
- TODO/FIXME comments

```bash
# Install/reinstall hooks
npx agentic-loop setup
```

See [Hooks Reference](HOOKS.md) for configuration.

### Claude Code Hooks

Real-time warnings while Claude is coding:

- Warns when creating files that might contain secrets
- Warns on hardcoded URLs in code
- Warns on debug statements

Configured in `.claude/settings.json`. See [Hooks Reference](HOOKS.md).

### Test File Enforcement

Code check fails if new code lacks corresponding tests:

```
ERROR: New file src/utils/auth.ts has no test file
Expected: src/utils/auth.test.ts or tests/utils/auth.test.ts
```

Disable in config:
```json
{
  "checks": {
    "requireTests": false
  }
}
```

---

## See Also

- [Hooks Reference](HOOKS.md) - Detailed hook configuration
- [How Ralph Works](RALPH.md) - Full architecture
- [Cheatsheet](CHEATSHEET.md) - All commands at a glance
