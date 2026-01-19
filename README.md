# Vibe and Thrive

**Ship quality code faster with AI.**

Vibe-and-thrive is a toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that helps you go from idea to shipped code. It includes:

- **Ralph** - Autonomous coding loop that writes, tests, and commits until done
- **`/vibe-check`** - Code quality audits to catch common AI-generated issues
- **`/review`** - Security-focused code review with OWASP checks
- **Pre-commit hooks** - Block secrets, localhost URLs, and security issues
- **`/styleguide`** - Generate a UI component reference from your codebase
- **`/my-dna`** - Interactive guide to adding your personal voice to CLAUDE.md

## Install

### Prerequisites

- Node.js 18+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated

### Install

```bash
cd your-project
npm install vibe-and-thrive
```

This launches an interactive setup that installs slash commands, pre-commit hooks, and Ralph.

### Verify

```bash
claude
> /vibe-help
```

If you see the command reference, you're ready to go.

## How It Works

Three steps: **Spec → Tasks → Execute**

### 1. Spec → `/idea`

Brainstorm with Claude. Output: `docs/ideas/feature.md`

### 2. Tasks → Approve PRD

Break into atomic stories. Output: `.ralph/prd.json`

### 3. Execute → `ralph run`

Run in your **terminal** (not inside Claude). Ralph loops through stories one at a time, writes tests, verifies, and commits.

## Usage

### In Claude (planning)

```bash
claude
> /idea "add user auth"
> [review and approve idea]
> [review and approve PRD]
> /exit
```

### In Terminal (execution)

```bash
ralph run
```

That's it. Ralph handles the rest.

> **Pro tip:** Use two terminals - plan with Claude in one, run Ralph in another. This lets you monitor progress or jump back into Claude while Ralph works.

## Ralph Details

When you run `ralph run`, Ralph:

1. Gets the next TODO story from `.ralph/prd.json`
2. Spawns a fresh Claude session to implement it
3. Runs 6-step verification (code review, lint, tests, e2e, browser, PRD steps)
4. Auto-runs migrations if new migration files are detected
5. Commits on success, retries on failure
6. Repeats until all stories are done

All stories complete → all tests passing → all commits made → push when ready.

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
