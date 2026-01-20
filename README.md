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
- `jq` (for config management): `brew install jq` or `apt install jq`
- Optional: [Playwright](https://playwright.dev/) for browser verification (installed automatically by `/tour`)

### Install

```bash
cd your-project
npm install vibe-and-thrive
```

This automatically sets up slash commands, pre-commit hooks, and Ralph.

### Get Started

```bash
claude
> /tour
```

The tour auto-detects your project settings and walks you through the workflow.

## How It Works

### Step 1: Start Claude

```bash
claude
```

### Step 2: Brainstorm Your Idea

```
/idea [your next feature]
```

Claude asks clarifying questions, explores your codebase, then generates:
- `docs/ideas/your-feature.md` - The documented idea
- `.ralph/prd.json` - Atomic stories for Ralph

Review and approve when prompted.

### Step 3: Execute with Ralph

Type `/exit` or open a new terminal, then run:

```bash
npx ralph run
```

Ralph loops through stories one at a time, writes tests, verifies, and commits.

> **Pro tip:** Use two terminals - plan with Claude in one, run Ralph in another.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Invalid API key" | Remove `ANTHROPIC_API_KEY` from `.env` - Ralph uses Claude Max subscription |
| "jq: command not found" | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |
| Browser verification skipped | Install Playwright: `npm install playwright && npx playwright install chromium` |
| "pre-commit: command not found" | Install pre-commit: `pip install pre-commit` then `pre-commit install` |

## Ralph Details

When you run `ralph run`, Ralph:

1. Gets the next TODO story from `.ralph/prd.json`
2. Spawns a fresh Claude session to implement it
3. Runs 6-step verification:
   - Code review (security, patterns)
   - Lint and type checks
   - Unit tests
   - Playwright e2e tests
   - Browser validation (console errors, network failures, missing elements)
   - PRD test steps
4. Auto-runs migrations if new migration files are detected
5. Commits on success, retries on failure
6. Repeats until all stories are done

All stories complete → all tests passing → all commits made → push when ready.

## What Gets Installed

When you run `npm install vibe-and-thrive`, postinstall automatically sets up:

| Item | Location | Purpose |
|------|----------|---------|
| Slash commands | `.claude/commands/` | /idea, /tour, /vibe-check, etc. |
| Ralph config | `.ralph/config.json` | Project settings for verification |
| Pre-commit hooks | `.pre-commit-config.yaml` | Block secrets and security issues |
| Project guide | `CLAUDE.md` | Auto-detected project info for Claude |
| Gitignore entries | `.gitignore` | Ignore Ralph temp files |

## Commands

### Claude Code Slash Commands

| Command | What it does |
|---------|--------------|
| `/idea [feature]` | Brainstorm and generate PRD for Ralph |
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
| `npx ralph run` | Start autonomous loop |
| `npx ralph stop` | Stop after current story |
| `npx ralph status` | Check progress |
| `npx ralph check` | Run verification only |
| `npx ralph verify TASK-001` | Verify specific task |
| `npx ralph signs` | Show learned patterns |
| `npx ralph sign "pattern"` | Teach Ralph a pattern |

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
