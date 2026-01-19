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

### Step 1: Start Claude

```bash
claude
```

### Step 2: Brainstorm Your Idea

```
/idea add user authentication
```

Claude asks clarifying questions, explores your codebase, then generates:
- `docs/ideas/your-feature.md` - The documented idea
- `.ralph/prd.json` - Atomic stories for Ralph

Review and approve when prompted.

### Step 3: Execute with Ralph

Exit Claude, then in your **terminal**:

```bash
npx ralph run
```

Ralph loops through stories one at a time, writes tests, verifies, and commits.

> **Pro tip:** Use two terminals - plan with Claude in one, run Ralph in another.

**Troubleshooting:** If you see "Invalid API key", check your `.env` file for `ANTHROPIC_API_KEY`. Remove or comment it out - Ralph uses your Claude Max subscription, not an API key.

## Ralph Details

When you run `ralph run`, Ralph:

1. Gets the next TODO story from `.ralph/prd.json`
2. Spawns a fresh Claude session to implement it
3. Runs 6-step verification (code review, lint, tests, e2e, browser, PRD steps)
4. Auto-runs migrations if new migration files are detected
5. Commits on success, retries on failure
6. Repeats until all stories are done

All stories complete → all tests passing → all commits made → push when ready.

## Project Structure

```
vibe-and-thrive/
├── bin/                    # CLI entry points (ralph, vibe, vibe-check)
├── lib/ralph/              # Ralph core logic (loop, verify, init, etc.)
├── skills/                 # Reusable skills for Claude
│   └── browser-verify/     # Playwright-based page verification
│       ├── SKILL.md        # Documentation for Claude
│       └── verify.ts       # Verification script
├── templates/              # Config templates for different project types
├── .claude/commands/       # Slash commands (/idea, /prd, /vibe-check, etc.)
└── integrations/           # ESLint plugin, lint-staged config
```

### Skills

Skills bundle documentation with tools so Claude knows both **what** a skill does and **how** to use it. The `browser-verify` skill, for example, launches a real Chromium browser to verify pages work correctly—detecting console errors, failed network requests, and missing elements.

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
| `npx ralph run` | Start autonomous loop |
| `npx ralph status` | Check progress |
| `npx ralph check` | Run verification only |
| `npx ralph verify TASK-001` | Verify specific task |
| `npx ralph signs` | Show learned patterns |
| `npx ralph sign "pattern"` | Teach Ralph a pattern |

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
