# Agentic Loop

**Autonomous AI coding loop for Claude Code.**

You describe what you want to build. Claude Code writes a PRD (Product Requirements Document) with small, testable stories. Ralph executes each story automatically - coding, testing, and committing in a loop until everything passes.

> **Optimized for:** Python, TypeScript, React, Go/Hugo, FastMCP, and Docker projects.

---

## What It Does

**Brainstorm ideas with `/idea`**
Describe a feature in plain English. Claude asks clarifying questions, explores your codebase, and generates a PRD with atomic stories that can be implemented one at a time.

**Execute with Ralph**
Ralph reads the PRD and implements each story autonomously. It spawns Claude, runs verification (lint, tests, browser checks), and either commits on success or retries with error context on failure.

**Customize your output**
- `/my-dna` - Add your voice and values so the code reflects your style
- `/styleguide` - Generate a UI component reference for consistent design

**Built-in guardrails**
- `/vibe-check`, `/review` - On-demand quality and security checks
- Pre-commit hooks - Block secrets, hardcoded URLs, debug statements
- Claude Code hooks - Real-time warnings while coding
- GitHub Actions CI/CD - Fast PR checks + comprehensive nightly tests
- Test file enforcement - Fails if new code lacks corresponding tests

---

## Quick Start

**Prerequisites:** Node.js 18+, [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI, `jq` (`brew install jq`)

```bash
npm install agentic-loop
npx agentic-loop setup
```

**Terminal 1 - Claude Code:**
```bash
claude --dangerously-skip-permissions
/tour                    # Guided walkthrough (recommended first time)
/idea 'your feature'     # Generate a PRD
```

**Terminal 2 - Ralph Loop:**
```bash
npx agentic-loop run         # Execute PRDs autonomously
```

> **Tip:** Use two terminals. Plan with Claude in one, run Ralph in the other.

---

## How Ralph Works

```
┌─────────────────────────────────────────────────────────────┐
│                        RALPH LOOP                           │
├─────────────────────────────────────────────────────────────┤
│  1. Read prd.json → find next story where passes=false      │
│  2. Build prompt (story + context + failures + signs)       │
│  3. Spawn Claude with prompt + MCP browser tools            │
│  4. Run verification (lint, tests, testSteps)               │
│  5. Pass? → commit, next story                              │
│     Fail? → save error, retry with failure context          │
│  6. Repeat until all stories pass                           │
└─────────────────────────────────────────────────────────────┘
```

**What's a PRD?**
A JSON file (`.ralph/prd.json`) containing your feature broken into small stories. Each story has acceptance criteria, test steps, and a test URL. Ralph implements them one by one. See [`templates/prd-example.json`](templates/prd-example.json) for a complete example.

**What are Signs?**
Patterns Ralph learns from failures. If Ralph keeps making the same mistake, add a sign: `npx agentic-loop sign "Always use camelCase for API fields" backend`. Future stories will see this guidance.

---

## Docs

- [How Ralph Works](docs/RALPH.md) - Architecture, config, verification pipeline
- [Technical Architecture](docs/ARCHITECTURE.md) - Deep dive for developers
- [Cheatsheet](docs/CHEATSHEET.md) - All commands at a glance
- [Hooks Reference](docs/HOOKS.md) - Pre-commit and Claude Code hooks
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and fixes
- [Contributing](docs/CONTRIBUTING.md) - How to contribute

---

Inspired by [Ralph](https://ghuntley.com/ralph/) and [Anthropic's guidance on long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

Built by [@allierays](https://github.com/allierays) | MIT License - [AllThrive AI](https://allthrive.ai)
