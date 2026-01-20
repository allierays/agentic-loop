# Vibe and Thrive

**Ship quality code faster with AI.**

A toolkit for implementing [RALPH](https://ghuntley.com/ralph/) with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that helps you go from idea to shipped code.

> You focus on what matters: your ideas. Brainstorm with `/idea`, then let Ralph handle the rest - coding, testing, and committing in an iterative loop until everything passes.

### This repo includes: 
#### Customize
- **`/my-dna`** - Add your own voice and values to your claude.md
- **`/styleguide`** - Generate a UI component reference for consistent design

#### Ship Features
- **`npx ralph run`** - RALPH Autonomous loop: Brainstorm ideas → turn ideas into atomic prds → implement → verify → commit → repeat

#### Guardrails
- **`/vibe-check`** - manually run the same automated tests and guardrail checks at any time
- **`/review`** - manually run the same automated Security-focused code review with OWASP checks
- **Pre-commit hooks** - Automatically Block secrets, hardcoded URLs, and security issues with precommit hooks. Catch and fix issues before your CI/CD does

---
See More for on how the [RALPH loop](docs/RALPH.md) works in this repo

---


## Getting Started

### Prerequisites

- Node.js 18+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed and authenticated
- `jq` (for config management): `brew install jq` or `apt install jq`
- Optional: [Playwright](https://playwright.dev/) for browser verification (installed automatically by `/tour`)


## Step 0: Install 

```bash
cd [your-project]
npm install vibe-and-thrive
```
This automatically sets up slash commands, pre-commit hooks, to make the Ralph loop autonomous.

## Step 1: Start claude (--dangerously-skip-permissions is optional)

```bash
claude --dangerously-skip-permissions 
```

## Step 1b: Optional run tour and customizations 
Inside of a claude session run 
```
 /tour
```
1. The tour auto-detects your project settings and walks you through the workflow.
2. You can set up your own styleguide for all your frontend work to reference. I highly recommend you do this. 
3. run /my-dna to add your own writing style, core values, and things you want represented in your application so that your app represents you and what you want.   

### Step 2: Brainstorm Your Idea

```
/idea [describe your next feature]
```

Claude asks clarifying questions, explores your codebase, then generates:
- `docs/ideas/your-feature.md` - The documented idea
- `.ralph/prd.json` - Atomic stories for Ralph

Review and approve when prompted.

> **Note:** If Claude skips writing to `docs/ideas/`, tell it: "Please write the idea to docs/ideas/ and generate the PRD as the /idea command specifies"

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

```
┌─────────────────────────────────────────────────────────────┐
│                        RALPH LOOP                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Read prd.json → find next story where passes=false      │
│  2. Build prompt (story + context + failures + signs)       │
│  3. Spawn Claude with prompt                                │
│  4. Run verification (build, tests, browser, code review)   │
│  5. Pass? → commit, next story                              │
│     Fail? → save error, retry with failure context          │
│  6. Repeat until all stories pass                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### What Ralph Reads

| File | Purpose |
|------|---------|
| `.ralph/prd.json` | Stories to implement (the work) |
| `PROMPT.md` | Base instructions (how to code) |
| `.ralph/config.json` | Project settings (URLs, commands) |
| `.ralph/signs.json` | Learned patterns from past runs |
| `~/.claude/DNA.md` | Your personal preferences |

### Verification Pipeline

1. **Build** - `npm run build` (catches compile errors)
2. **Code review** - Claude reviews diff for security/patterns
3. **Unit tests** - Runs `testSteps` from story
4. **E2E tests** - Playwright tests if `e2e: true`
5. **Browser check** - Console errors, network failures, missing elements

All stories complete → all tests passing → all commits made → push when ready.

📖 **[Full Ralph documentation →](docs/RALPH.md)**

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

## Documentation

| Doc | Description |
|-----|-------------|
| [Ralph Architecture](docs/RALPH.md) | How the autonomous loop works |
| [Workflow Guide](docs/WORKFLOW.md) | End-to-end development process |
| [Cheatsheet](docs/CHEATSHEET.md) | Quick reference for all commands |
| [Bad Patterns](docs/BAD-PATTERNS.md) | AI code issues vibe-check catches |
| [Prompting Guide](docs/PROMPTING-GUIDE.md) | Writing effective PROMPT.md |
| [TDD Guide](docs/TDD.md) | Test-driven development with Ralph |
| [Styleguide](docs/STYLEGUIDE.md) | Creating UI component references |
| [Contributing](docs/CONTRIBUTING.md) | How to contribute |

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
