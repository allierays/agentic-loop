# Vibe and Thrive

**Catch common AI-generated code issues before they hit your codebase.**

Whether you're using AI coding agents or building your own—these tools catch patterns that lead to technical debt automatically.

## Install

```bash
npm install vibe-and-thrive
```

## Usage

### CLI

```bash
# Check all files in current directory
npx vibe-check .

# Check specific files
npx vibe-check src/app.ts src/utils.ts

# Check with specific hooks only
npx vibe-check . --only secrets,urls,debug

# Skip specific hooks
npx vibe-check . --skip any-types,snake-case

# Output formats
npx vibe-check . --format pretty   # Default: colored terminal output
npx vibe-check . --format json     # JSON for CI/scripts
npx vibe-check . --format compact  # One line per issue

# Severity filtering
npx vibe-check . --fail-on error   # Only fail on blocking issues (default)
npx vibe-check . --fail-on warning # Fail on warnings too
```

### ESLint Plugin

```bash
npm install -D vibe-and-thrive eslint
```

```javascript
// eslint.config.js
import vibe from 'vibe-and-thrive/eslint-plugin';

export default [
  // Use recommended config
  vibe.configs.recommended,

  // Or configure individually
  {
    plugins: { vibe },
    rules: {
      'vibe/no-any-type': 'warn',
      'vibe/no-snake-case-props': 'warn',
      'vibe/no-debug-statements': 'error',
      'vibe/no-empty-catch': 'warn',
      'vibe/no-magic-numbers': 'off',
      'vibe/no-deep-nesting': 'warn',
      'vibe/max-function-length': ['warn', { max: 50 }],
    }
  }
];
```

### Pre-commit Hooks

Add to your `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/allthriveai/vibe-and-thrive
    rev: v1.0.0
    hooks:
      - id: check-secrets          # BLOCKS commits
      - id: check-hardcoded-urls   # BLOCKS commits
      - id: check-debug            # Warns
      - id: check-empty-catch      # Warns
      - id: check-any-types        # Warns (TypeScript only)
      - id: check-snake-case       # Warns (TypeScript only)
      - id: vibe-check             # All checks
      - id: vibe-check-security    # Security only (blocking)
      - id: vibe-check-quality     # Quality only (non-blocking)
```

Then: `pre-commit install`

### lint-staged

```json
{
  "lint-staged": {
    "*.{js,ts,jsx,tsx}": "vibe-check --fail-on error"
  }
}
```

### Claude Code

Run `/vibe-check` in Claude Code for a full code quality audit.

## Available Checks

| Check | ID | Description | Severity |
|-------|-----|-------------|----------|
| Secrets | `secrets` | Hardcoded API keys, passwords, tokens | Error |
| URLs | `urls` | Hardcoded localhost/production URLs | Error |
| Unsafe HTML | `unsafe-html` | innerHTML, dangerouslySetInnerHTML, eval | Error |
| Debug | `debug` | console.log, print(), debugger statements | Warning |
| Empty Catch | `empty-catch` | Empty catch/except blocks | Warning |
| Any Types | `any-types` | TypeScript `any` type usage | Warning |
| Snake Case | `snake-case` | snake_case in TypeScript interfaces | Warning |
| Magic Numbers | `magic-numbers` | Hardcoded numbers without names | Warning |
| Function Length | `function-length` | Functions over 50 lines | Warning |
| Deep Nesting | `deep-nesting` | Code nested more than 4 levels | Warning |
| DRY | `dry` | Duplicated code blocks | Warning |
| TODO/FIXME | `todo` | Incomplete work markers | Info |
| Commented Code | `commented-code` | Commented-out code blocks | Info |
| Console Error | `console-error` | console.error in catch blocks | Info |
| Docker Platform | `docker-platform` | Missing --platform in Dockerfiles | Info |

## ESLint Rules

| Rule | Fixable | Description |
|------|---------|-------------|
| `vibe/no-any-type` | No | Disallow `any` type |
| `vibe/no-snake-case-props` | Yes | Disallow snake_case properties |
| `vibe/no-debug-statements` | No | Disallow console.log, debugger |
| `vibe/no-empty-catch` | No | Disallow empty catch blocks |
| `vibe/no-magic-numbers` | No | Disallow magic numbers |
| `vibe/no-deep-nesting` | No | Disallow deep nesting |
| `vibe/max-function-length` | No | Enforce max function length |

## Claude Code Skills

| Skill | Purpose |
|-------|---------|
| `/vibe-check` | Full code quality audit |
| `/styleguide` | Generate a styleguide from design preferences |
| `/tdd-feature` | Build features test-first with AI |
| `/e2e-scaffold` | Generate E2E test structure |
| `/review` | Code review for issues |
| `/explain` | Explain code line by line |
| `/refactor` | Guided refactoring |
| `/add-tests` | Add tests to existing code |
| `/fix-types` | Fix TypeScript without `any` |
| `/security-check` | Check for vulnerabilities |

## Philosophy

These are **guardrails, not gatekeepers**:
- Warn about most issues (awareness > blocking)
- Block only security-critical problems
- Support `# noqa:` and `// eslint-disable` suppression
- Little and often make much

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai) for the vibe coding community.
