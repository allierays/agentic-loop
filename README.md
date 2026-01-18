# Vibe and Thrive

**Tools to help you thrive with agentic coding in the Claude CLI.**

Vibe-and-thrive is a toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that helps you ship quality code faster with AI. It includes:

- **Ralph** - Autonomous coding loop that writes, tests, and commits until done (inspired by [RALPH](https://ghuntley.com/ralph/))
- **`/vibe-check`** - Code quality audits to catch common AI-generated issues
- **`/review`** - Security-focused code review with OWASP checks
- **Pre-commit hooks** - Block secrets, localhost URLs, and security issues
- **`/styleguide`** - Generate a UI component reference from your codebase
- **`/my-dna`** - Interactive guide to adding your personal voice to CLAUDE.md

## Install

```bash
npm install vibe-and-thrive
```

## Quick Start

New here? Run `/tour` in Claude Code for an interactive walkthrough that explains the workflow, auto-detects your tech stack, and sets up your preferences.

Or jump right in:

```
/idea "add a contact form with email validation"
```

Review and approve the generated PRD, then:

```bash
ralph run
```

Check progress anytime with `ralph status`.

## How Ralph Works

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│             │     │             │     │             │     │             │
│   /idea     │────▶│   Approve   │────▶│ ralph run   │────▶│    Ship     │
│             │     │             │     │             │     │             │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │                   │
       ▼                   ▼                   ▼                   ▼
 docs/ideas/        .ralph/prd.json      Loop until           Push to
 feature.md         with stories         all stories          remote
                                         are done
```

### 1. `/idea` → `docs/ideas/feature.md`

Describe your feature to Claude. Together you brainstorm, explore the codebase, and write a feature doc to `docs/ideas/`. You review and approve the idea.

### 2. Approve → `.ralph/prd.json`

Claude splits your approved idea into small, testable stories and writes them to `.ralph/prd.json`. Each story has acceptance criteria, test steps, error handling requirements, and more. You review and approve the PRD.

### 3. `ralph run` → Loop until done

```
                 ┌─────────────────────────┐
                 │   Get next story from   │
                 │   prd.json (TODO)       │
                 └───────────┬─────────────┘
                             │
                             ▼
                 ┌─────────────────────────┐
                 │   Claude writes code    │
                 └───────────┬─────────────┘
                             │
                             ▼
                 ┌─────────────────────────┐
                 │   6-Step Verification   │
                 │                         │
                 │   1. Code review        │
                 │   2. Lint/build         │
                 │   3. Unit tests         │
                 │   4. E2E/API tests      │
                 │   5. Browser validation │
                 │   6. PRD test steps     │
                 └───────────┬─────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
       ┌─────────────┐               ┌─────────────┐
       │    DONE     │               │  NOT YET    │
       └──────┬──────┘               └──────┬──────┘
              │                             │
              ▼                             │
       ┌─────────────┐                      │
       │ Mark story  │                      │
       │ done in     │                      │
       │ prd.json    │                      │
       └──────┬──────┘                      │
              │                             │
              ▼                             │
       ┌─────────────┐                      │
       │ git commit  │                      │
       └──────┬──────┘                      │
              │                             │
              ▼                             │
       ┌─────────────┐    Save errors,      │
       │ Next story  │    try again         │
       └──────┬──────┘         ┌────────────┘
              │                │
              └────────────────┘
```

### 4. Ship

All stories complete. All tests passing. All commits made. Push when ready.

## Commands

### Claude Code Slash Commands

| Command | What it does |
|---------|--------------|
| `/idea "feature"` | Brainstorm and generate PRD for Ralph |
| `/tour` | Interactive walkthrough for new users |
| `/my-dna` | Set up your personal voice in CLAUDE.md |
| `/vibe-check` | Audit code quality before shipping |
| `/review` | Code review with security checks |
| `/explain` | Understand existing code line by line |
| `/styleguide` | Generate UI component reference |
| `/vibe-help` | Quick reference cheatsheet |

### Terminal Commands

| Command | What it does |
|---------|--------------|
| `ralph run` | Start autonomous loop |
| `ralph status` | Check progress |
| `ralph check` | Run verification only |
| `ralph verify US-001` | Verify specific story |
| `ralph signs` | Show learned patterns |
| `ralph sign "pattern"` | Teach Ralph a pattern |

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
