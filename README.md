# ThriveKit

**Tools to thrive with agentic coding.**

A toolkit for implementing [RALPH](https://ghuntley.com/ralph/) with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that helps you go from idea to shipped code.

> **Optimized for:** Python, TypeScript, React, Go/Hugo, and Docker projects. Auto-detects ports from `docker-compose.yml`, Vite, Next.js, Hugo, FastAPI, and more.

> You focus on what matters: your ideas. Brainstorm with `/idea`, then let Ralph handle the rest - coding, testing, and committing in an iterative loop until everything passes.

### This repo helps you customize your code output, run autonomous coding loops, and adds guardrails to ensure good code little and often:
#### Customize
- **`/my-dna`** - Add your own voice and values to your claude.md (This helps you personalize your experience and output)
- **`/styleguide`** - Generate a UI component reference for consistent design (Stop AI from generating everything in purple add your unique style in an html and then reference it)

#### Autonomous Code Loops with RALPH principles
Run this in the terminal not in a claude cli session. It will use your claude subscription not an API key.
- **`npx thrivekit run`** - RALPH Autonomous loop: Brainstorm ideas → turn ideas into atomic prds → implement → verify → commit → repeat
- **`npx thrivekit run --fast`** - Fast mode: skips code review for quicker iterations (~2-3 min/story vs 5-8 min)

#### Guardrails
- **`/vibe-check`** - manually run the same automated tests and guardrail checks at any time
- **`/review`** - manually run the same automated Security-focused code review with OWASP checks
- **Pre-commit hooks** - Automatically block secrets, hardcoded URLs, and security issues with precommit hooks from entering into your git repo. Catch and fix issues before your CI/CD does
- **Claude Code hooks** - Real-time warnings while coding (debug statements, secrets, hardcoded URLs)

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
npm install thrivekit
npx thrivekit setup
```

This sets up:
- Slash commands (`/idea`, `/review`, etc.)
- Pre-commit hooks (secrets, URLs, debug statements)
- Claude Code hooks (real-time warnings)
- Ralph configuration files

> **Note:** Claude Code hooks require `jq`. On macOS with Homebrew, it's installed automatically. On Linux, if you see a warning, run `sudo apt install jq` (or your package manager) then `npx thrivekit setup`.

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
# Standard mode (with code review)
npx thrivekit run

# Fast mode (skip code review, ~2x faster)
npx thrivekit run --fast

# Limit iterations
npx thrivekit run --max 10
```

Ralph loops through stories one at a time, writes tests, verifies, and commits.

> **Pro tip:** Use two terminals - plan with Claude in one, run Ralph in another.
>
> **Performance:** Fast mode skips the AI code review step, running lint and tests in parallel. Use it when iterating quickly on known-good patterns.

## Ralph Details

```
┌─────────────────────────────────────────────────────────────┐
│                        RALPH LOOP                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Read prd.json → find next story where passes=false      │
│  2. Build prompt (story + context + failures + signs)       │
│  3. Spawn Claude with prompt                                │
│  4. Run verification:                                       │
│     - Code review (skipped in --fast mode)                  │
│     - Lint + tests (run in parallel)                        │
│     - Playwright/API tests                                  │
│     - Browser validation                                    │
│  5. Pass? → commit, next story                              │
│     Fail? → save error, retry with failure context          │
│  6. Repeat until all stories pass                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Performance Options

| Flag | Effect | Best For |
|------|--------|----------|
| `--fast` | Skip code review, parallel lint+tests | Rapid iteration, trusted patterns |
| `--max N` | Limit to N iterations | Preventing runaway loops |
| (default) | Full verification with code review | Production-quality code |

---

## Documentation

| Doc | Description |
|-----|-------------|
| [How Ralph Works](docs/RALPH.md) | Architecture, config, troubleshooting |
| [Cheatsheet](docs/CHEATSHEET.md) | All commands, quick reference |
| [Workflow Guide](docs/WORKFLOW.md) | End-to-end development process |
| [Hooks Reference](docs/HOOKS.md) | Pre-commit and Claude Code hooks |
| [Bad Patterns](docs/BAD-PATTERNS.md) | AI code issues to avoid |
| [Prompting Guide](docs/PROMPTING-GUIDE.md) | Writing effective PROMPT.md |
| [TDD Guide](docs/TDD.md) | Test-driven development with Ralph |
| [Styleguide](docs/STYLEGUIDE.md) | Creating UI component references |
| [Contributing](docs/CONTRIBUTING.md) | How to contribute |

## Project Structure

```
thrivekit/
├── .claude/commands/       # Slash commands (/idea, /review, etc.)
├── ralph/                  # Autonomous loop (Bash)
│   ├── hooks/              # Claude Code hooks (real-time warnings)
│   ├── browser-verify/     # Playwright verification
│   └── setup/              # Setup wizards (/tour)
├── src/                    # Pre-commit checks (TypeScript)
│   └── checks/             # Check implementations (secrets, urls, etc.)
├── templates/              # Files for user projects
│   ├── PROMPT.md           # Base prompt for Ralph sessions
│   ├── config/             # Project type configs (node, python)
│   ├── optional/           # Extra configs (eslint, vscode, etc.)
│   └── examples/           # Example CLAUDE.md files by stack
├── docs/                   # Documentation
└── bin/                    # CLI entry points (thrivekit, vibe-check)
```

### Three Layers of Quality Checks

| Layer | When | What |
|-------|------|------|
| **Slash commands** | In Claude Code CLI | `/vibe-check`, `/review` - on-demand checks |
| **Claude Code hooks** | While Claude writes code | Real-time warnings (debug statements, secrets) |
| **Pre-commit hooks** | At `git commit` | Blocks secrets, URLs, debug statements |

---

## Troubleshooting

### "SessionStart: startup hook error"

This means Claude Code hooks are configured but the hook scripts can't be found. Fix with:

```bash
# Reinstall project hooks
npx thrivekit setup
```

### Hooks not working after moving project

Claude Code hooks use absolute paths. After moving a project or cloning on a new machine, reinstall hooks:

```bash
npx thrivekit setup
```

### Team members getting hook errors

`.claude/settings.json` contains machine-specific paths and should not be committed to git. The setup script automatically adds it to `.gitignore`. Each team member's hooks are configured when they run `npx thrivekit setup`.

If `.claude/settings.json` was accidentally committed:
```bash
git rm --cached .claude/settings.json
echo ".claude/settings.json" >> .gitignore
git commit -m "Remove machine-specific settings from git"
```

### jq not installed

Claude Code hooks require `jq` for JSON manipulation. On macOS with Homebrew, the setup installs it automatically. On Linux:

```bash
# Ubuntu/Debian
sudo apt install jq

# Fedora/RHEL
sudo dnf install jq

# Then run setup
npx thrivekit setup
```

---

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
