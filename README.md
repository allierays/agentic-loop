# Vibe and Thrive

**Go from idea to shipped code with AI agents.**

Vibe-and-thrive is a toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that turns your ideas into working software. You describe what you want, approve the plan, and an autonomous agent writes the code, tests it, validates it in a browser, and commits when everything passes.

No more copy-pasting between ChatGPT and your editor. No more manually running tests after every change. Just describe → approve → ship.

Inspired by [RALPH](https://ghuntley.com/ralph/).

## How It Works

```
┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│  /idea   │ ──▶ │ Approve  │ ──▶ │  ralph   │ ──▶ │   Ship   │
│          │     │   PRD    │     │   run    │     │          │
└──────────┘     └──────────┘     └──────────┘     └──────────┘
  Brainstorm       Review &         Autonomous        Done!
  with Claude      tweak plan       coding loop
```

1. **`/idea`** - Describe your feature. Claude brainstorms with you, explores your codebase, and creates a detailed plan.

2. **Approve** - Review the plan in your editor. Nothing happens without your approval.

3. **`ralph run`** - The autonomous loop takes over. For each story in the plan:
   - Writes code
   - Runs code review (security, error handling, edge cases)
   - Runs linters and type checks
   - Runs unit tests
   - Runs E2E tests (Playwright) or API tests
   - Validates in browser via MCP
   - If anything fails → fixes and retries
   - When everything passes → commits and moves to next story

4. **Ship** - All stories done, all tests passing, all commits made. You're ready to push.

## Install

```bash
npm install -g vibe-and-thrive
```

Then in any project:

```bash
ralph init
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

## Why This Exists

AI coding assistants are powerful but manual. You prompt, copy, paste, test, fix, repeat. Vibe-and-thrive automates the loop:

- **No manual testing** - Ralph runs your tests and validates in browser
- **No forgotten edge cases** - PRDs require error handling and a11y specs upfront
- **No security slip-ups** - Code review checks for OWASP issues before tests run
- **No context loss** - Failed attempts feed back into the next iteration

The goal: you think about *what* to build, the agent handles *how*.

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
