# Vibe and Thrive

**From idea to shipped code with AI.**

A complete system for agentic coding: brainstorm ideas, generate PRDs, execute autonomously, ship with guardrails. Inspired by [RALPH](https://ghuntley.com/ralph/).

## The System

```
/idea "your feature"  →  PRD  →  ralph run  →  Ship
```

1. **`/idea`** - Brainstorm in plan mode, approve the idea, auto-split into PRDs
2. **`ralph run`** - Autonomous coding until all tests pass
3. **Pre-commit hooks** - Guard every commit

Start messy. End with working code.

## Quick Start

```bash
# Install in your project
npm install vibe-and-thrive

# In Claude Code, take the tour
/tour
```

## Take the Tour

Run `/tour` in Claude Code for an interactive walkthrough. The tour:

- Explains the idea → PRD → Ralph → ship workflow
- Offers to **auto-detect your tech stack** and add it to CLAUDE.md
- Offers to **set up your DNA** - your personal coding preferences

New to vibe-and-thrive? Start with `/tour`.

## The Workflow

### Step 1: /idea - Brainstorm to PRD

```
/idea "add user profiles"
    ↓
Plan mode: brainstorm, explore, ask questions
    ↓
Write docs/ideas/user-profiles.md
    ↓
Open in TextEdit for review → You approve
    ↓
Auto-split into small PRDs
    ↓
Write .ralph/prd.json
    ↓
Open in TextEdit for review → You approve
    ↓
Ready for ralph run
```

Two approval gates. Nothing happens without your say-so.

### Step 2: Ralph - Autonomous Execution

```bash
ralph run      # Start the autonomous loop
ralph status   # Check progress anytime
ralph check    # Run verification only
ralph signs    # Show learned patterns
```

Ralph works through PRD stories one by one:
- Picks a story
- Writes code to make it pass
- Runs test steps to verify
- Commits when tests pass
- Moves to next story

### Step 3: Pre-commit Hooks - Guardrails

Every `git commit` runs checks automatically:

**Blocked (errors):**
- Hardcoded secrets and API keys
- Hardcoded localhost URLs
- Security vulnerabilities

**Warned:**
- TypeScript `any` types
- Empty catch blocks
- Debug statements

## CLI: vibe-check

### Claude Code

Run `/vibe-check` in Claude Code for a full code quality audit.

### Terminal

Scan code for common AI-generated issues:

```bash
npx vibe-check .                    # Check current directory
npx vibe-check src/                 # Check specific folder
npx vibe-check . --only secrets,urls # Specific checks only
npx vibe-check . --format json      # JSON output for CI
```

## Pre-commit Hooks

Add to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/allthriveai/vibe-and-thrive
    rev: v1.0.0
    hooks:
      - id: vibe-check             # All checks
      - id: vibe-check-security    # Security only (blocking)
      - id: vibe-check-quality     # Quality only (non-blocking)
```

Then: `pre-commit install`

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
| Function Length | `function-length` | Functions over 50 lines | Warning |
| Deep Nesting | `deep-nesting` | Code nested more than 4 levels | Warning |

## ESLint Plugin

```javascript
// eslint.config.js
import vibe from 'vibe-and-thrive/eslint-plugin';

export default [
  vibe.configs.recommended,
];
```

## Philosophy

- **Guardrails, not gatekeepers** - Warn about most issues, block only security-critical problems
- **Human in the loop** - Two approval gates before any code runs
- **Start messy, end clean** - Brainstorm freely, then structure for execution
- **Little and often make much** - Small PRDs, frequent commits, steady progress

## All Commands (vibe-list)

Run `/vibe-list` in Claude Code for the full reference, or see below.

### Slash Commands (Claude Code)

| Command | Description |
|---------|-------------|
| `/idea "feature"` | Brainstorm in plan mode, generate PRD for Ralph |
| `/tour` | Interactive walkthrough of vibe-and-thrive |
| `/my-dna` | Set up your personal style preferences |
| `/vibe-check` | Audit code quality before shipping |
| `/review` | Code review with OWASP security checks |
| `/explain` | Explain code line by line |
| `/styleguide` | Generate UI component design system |
| `/vibe-help` | Quick reference cheatsheet |
| `/vibe-list` | Complete command reference |

### Ralph CLI (Terminal)

| Command | Description |
|---------|-------------|
| `ralph run` | Run autonomous loop until all stories pass |
| `ralph run --max 10` | Limit to N iterations |
| `ralph status` | Show feature, stories, pass/fail counts |
| `ralph check` | Run all configured checks |
| `ralph verify US-001` | Verify a specific story |
| `ralph signs` | List all learned patterns |
| `ralph sign "pattern"` | Add a pattern Ralph should follow |
| `ralph progress` | Show last 50 lines of progress log |
| `ralph init` | Initialize .ralph/ in current directory |
| `ralph prd "notes"` | Generate PRD interactively |

### Vibe CLI (Terminal)

| Command | Description |
|---------|-------------|
| `vibe help` | Show terminal quick reference |

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
