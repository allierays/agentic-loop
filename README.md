# Vibe and Thrive

**Tools to help you thrive with agentic coding in the Claude CLI.**

Vibe-and-thrive is a toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that helps you ship quality code faster with AI. It includes:

- **Ralph** - Autonomous coding loop that writes, tests, and commits until done (inspired by [RALPH](https://ghuntley.com/ralph/))
- **`/vibe-check`** - Code quality audits to catch common AI-generated issues
- **`/review`** - Security-focused code review with OWASP checks
- **Pre-commit hooks** - Block secrets, localhost URLs, and security issues
- **`/styleguide`** - Generate a UI component reference from your codebase
- **`/my-dna`** - Interactive guide to adding your personal voice to CLAUDE.md

## How It Works

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  /idea   │ ──▶ │ Approve  │ ──▶ │  ralph   │ ──▶ │   Ship   │
│          │     │   PRD    │     │   run    │     │          │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
```

### 1. `/idea` → `docs/ideas/feature.md`

Describe your feature to Claude. Together you brainstorm, explore the codebase, and write a feature doc to `docs/ideas/`. You review and approve the idea.

### 2. Approve → `.ralph/prd.json`

Claude splits your approved idea into small, testable stories and writes them to `.ralph/prd.json`. Each story has acceptance criteria, test steps, error handling requirements, and more. You review and approve the PRD.

### 3. `ralph run` → Loop until done

Ralph picks the first incomplete story from `prd.json` and loops:

1. **Claude writes code** to implement the story
2. **6-step verification** runs:
   - Code review (security, error handling, edge cases)
   - Lint/build checks
   - Unit tests
   - E2E tests (Playwright) or API tests
   - Browser validation via MCP
   - PRD test steps
3. **If verification fails** → errors saved, Claude tries again
4. **If verification passes** → story marked `done` in `prd.json`, git commit, next story

Ralph keeps looping until all stories are done.

### 4. Ship

All stories complete. All tests passing. All commits made. Push when ready.

## Install

```bash
npm install -g vibe-and-thrive
```

## Quick Start

In Claude Code:

```
/idea "add a contact form with email validation"
```

Review and approve the generated PRD, then:

```bash
ralph run
```

Watch it work. Check progress anytime with `ralph status`.

## Take the Tour

New here? Run `/tour` in Claude Code for an interactive walkthrough that:
- Explains the full workflow
- Auto-detects your tech stack
- Sets up your personal coding preferences

## The Ralph Loop

Ralph doesn't just write code—it verifies everything actually works:

```
              ┌─────────────────────────┐
              │ Get next incomplete     │
              │ story (TODO)            │
              └─────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │  Claude writes code     │
              └─────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │  6-Step Verification    │
              │  1. Code review         │
              │  2. Lint/build          │
              │  3. Unit tests          │
              │  4. E2E/API tests       │
              │  5. Browser validation  │
              │  6. PRD test steps      │
              └─────────────────────────┘
                            │
                   ┌────────┴────────┐
                   ▼                 ▼
              ┌─────────┐      ┌──────────┐
              │  DONE   │      │ NOT YET  │───┐
              └─────────┘      └──────────┘   │
                   │                          │
                   ▼                          │
              ┌─────────────────────────┐     │
              │  git commit             │     │
              │  → Next story           │     │
              └─────────────────────────┘     │
                                              │
                   ◄──────────────────────────┘
                      Save errors, try again
```

## Commands

### Claude Code Slash Commands

| Command | What it does |
|---------|--------------|
| `/idea "feature"` | Brainstorm and generate PRD for Ralph |
| `/tour` | Interactive walkthrough for new users |
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
| `ralph init` | Set up Ralph in a project |

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
