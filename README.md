# Agentic Loop

**Autonomous AI coding loop for Claude Code.**

You describe what you want to build. Claude Code writes a PRD (Product Requirements Document) with small, testable stories. Ralph executes each story automatically - coding, testing, and committing in a loop until everything passes.

---

## What It Does and How to work with Agentic Loop

### The Two-Terminal Workflow

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  TERMINAL 1: Claude CLI                │  TERMINAL 2: Execute                    │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│                                        │                                         │
│  claude --dangerously-skip-permissions │  npx agentic-loop run                   │
│                                        │                                         │
│  PLAN FEATURES                         │  ┌─ prd-check (once) ───────────────┐   │
│  /idea 'your feature or bugfix'        │  │ Validate all stories upfront     │   │
│  → Claude asks questions               │  │ Auto-fix missing test steps      │   │
│  → Explores codebase                   │  └──────────────────────────────────┘   │
│  → Generates PRD                       │            ↓                            │
│                                        │  ┌─ loop (per story) ───────────────┐   │
│  ENHANCE AS YOU LEARN                  │  │                                  │   │
│  → Add signs when Ralph repeats        │  │ Read prd.json → get next story   │   │
│    the same mistake                    │  │ Load PROMPT.md, signs, config    │   │
│  → Tune timeouts, retries, checks      │  │ Load last_failure.txt (if retry) │   │
│  → Refine test commands for your       │  │ Build prompt with full context   │   │
│    stack                               │  │ Spawn Claude → write code        │   │
│                                        │  │                                  │   │
│  (OPTIONAL) CUSTOMIZE YOUR LOOP        │  │ code-check:                      │   │
│  /my-dna      → your coding style      │  │   [1] Lint                       │   │
│  /styleguide  → UI consistency         │  │   [2] Tests                      │   │
│  /sign        → teach patterns         │  │   [3] PRD test steps             │   │
│  config.json  → tune your setup        │  │   [4] API smoke                  │   │
│                                        │  │   [5] Frontend smoke             │   │
│                                        │  │                                  │   │
│                                        │  │ Pass → commit, next story        │   │
│                                        │  │ Fail → save to last_failure.txt, │   │
│                                        │  │        retry                     │   │
│                                        │  └──────────────────────────────────┘   │
│                                        │                                         │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Terminal 1** is where you shape *what* gets built and *how* Ralph builds it.
**Terminal 2** is where Ralph executes autonomously.

Your loop gets smarter over time. When Ralph struggles with something, add a sign. When tests flake, tune the config. The customization never really stops—it's how you make Ralph work for *your* project.

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

## Docs

- **[Beginners Guide](docs/BEGINNERS.md)** - New to this? Start here (no coding experience required)
- [PRD Check](docs/PRD-CHECK.md) - Story validation before coding starts
- [Code Check](docs/CODE-CHECK.md) - Verification pipeline after each story
- [Customization](docs/CUSTOMIZATION.md) - Personalization and guardrails
- [How Ralph Works](docs/RALPH.md) - Architecture, config, full reference
- [Cheatsheet](docs/CHEATSHEET.md) - All commands at a glance
- [Hooks Reference](docs/HOOKS.md) - Pre-commit and Claude Code hooks
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and fixes
- [Contributing](docs/CONTRIBUTING.md) - How to contribute

---

Inspired by [Ralph](https://ghuntley.com/ralph/) and [Anthropic's guidance on long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

Built by [@allierays](https://github.com/allierays) | MIT License - [AllThrive AI](https://allthrive.ai)
