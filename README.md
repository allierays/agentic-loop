# Agentic Loop

**Autonomous AI coding loop for Claude Code.**

You describe what you want to build. Claude Code writes a PRD (Product Requirements Document) with small, testable stories. Ralph executes each story automatically - coding, testing, and committing in a loop until everything passes.

---

## What It Does and How to work with Agentic Loop

### The Two-Terminal Workflow

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  TERMINAL 1: Plan & Generate           │  TERMINAL 2: Execute                    │
├────────────────────────────────────────┼─────────────────────────────────────────┤
│                                        │                                         │
│  claude --dangerously-skip-permissions │  npx agentic-loop run                   │
│                                        │                                         │
│  THE PIPELINE                          │  ┌─ prd-check (once) ───────────────┐   │
│  1. Plan mode                          │  │ Validate all stories upfront     │   │
│     → Think through the feature        │  │ Auto-fix missing test steps      │   │
│     → Claude explores codebase         │  └──────────────────────────────────┘   │
│     → Plan saved to docs/plans/        │            ↓                            │
│                                        │                                         │
│  2. /prd plans/my-feature              │  ┌──────────────────────────────────┐   │
│     → Hardening questions              │  │ Read prd.json → get next story   │   │
│     → Generates .ralph/prd.json        │  │ Load PROMPT.md, signs, config    │   │
│                                        │  │ Load last_failure.txt (if retry) │   │
│  3. /prd-check                         │  │ Build prompt with full context   │   │
│     → Validate stories                 │  │ Spawn Claude → write code        │   │
│     → Cross-ref signs                  │  │                                  │   │
│     → Auto-fix issues                  │  │ code-check:                      │   │
│                                        │  │   [1] Lint                       │   │
│  ENHANCE AS YOU LEARN                  │  │   [2] Tests                      │   │
│  /sign        → teach patterns         │  │   [3] PRD test steps             │   │
│  /my-dna      → your coding style      │  │   [4] API smoke                  │   │
│  /styleguide  → UI consistency         │  │   [5] Frontend smoke             │   │
│  /color       → terminal tint          │  │                                  │   │
│  /tab-rename  → name your tabs         │  │                                  │   │
│  config.json  → tune your setup        │  │                                  │   │
│                                        │  │ Pass → commit, next story        │   │
│                                        │  │ Fail → save to last_failure.txt, │   │
│                                        │  │        retry                     │   │
│                                        │  └──────────────────────────────────┘   │
│                                        │                                         │
└────────────────────────────────────────┴─────────────────────────────────────────┘
```

**Terminal 1** is where you plan and generate. Plan mode lets you think through a feature with Claude before committing to code. `/prd` turns that plan into executable stories. `/prd-check` validates them.
**Terminal 2** is where Ralph executes autonomously — coding, testing, and committing each story in a loop.

The loop gets smarter over time. When Ralph struggles with something, teach it with `/sign`. Tune timeouts and checks in `config.json`. Capture your coding style with `/my-dna`.

---

## Quick Start

**Prerequisites:** Node.js 18+, [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI, `jq` (`brew install jq`)

```bash
npm install agentic-loop
npx agentic-loop setup
```

**Terminal 1 — Plan and generate with Claude:**
```bash
claude --dangerously-skip-permissions

# 1. Use plan mode to think through your feature
#    Claude explores the codebase, you discuss, plan saved to docs/plans/

# 2. Turn the plan into executable stories
/prd plans/my-feature

# 3. Validate before running
/prd-check
```

**Terminal 2 — Run the loop:**
```bash
npx agentic-loop run         # Execute PRDs autonomously (spins up claude -p)
npx agentic-loop run --quiet # Same, but suppress activity feed
```

Ralph shows a live activity feed as it works — what files it's reading, what code it's writing, and why. Use `--quiet` to suppress it. On macOS Terminal.app, Ralph tints the terminal background dark teal so you can tell the two terminals apart at a glance — the original color is restored when the loop ends.

> **Tip:** Plan first, then generate. Use plan mode to explore and think, `/prd` to create stories, `/prd-check` to validate, and `ralph run` to execute.

---

> [!NOTE]
> **New here?** Follow the **[Getting Started Guide](docs/GETTING-STARTED.md)** for a full step-by-step walkthrough — from install to your first autonomous loop run.

---

## Docs

- **[Getting Started](docs/GETTING-STARTED.md)** - Full walkthrough from zero to your first loop run
- [Beginners Guide](docs/BEGINNERS.md) - New to this? Start here (no coding experience required)
- [PRD Check](docs/PRD-CHECK.md) - Story validation before coding starts
- [Code Check](docs/CODE-CHECK.md) - Verification pipeline after each story
- [Customization](docs/CUSTOMIZATION.md) - Personalization and guardrails
- [How Ralph Works](docs/RALPH.md) - Architecture, config, full reference
- [UAT & Chaos Agent](docs/UAT.md) - Autonomous acceptance testing and adversarial red teaming
- [Cheatsheet](docs/CHEATSHEET.md) - All commands at a glance
- [Hooks Reference](docs/HOOKS.md) - Pre-commit and Claude Code hooks
- [Loopgram](docs/LOOPGRAM.md) - Telegram bot for mobile idea capture and loop monitoring
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and fixes
- [Contributing](docs/CONTRIBUTING.md) - How to contribute

---

Inspired by [Ralph](https://ghuntley.com/ralph/) and [Anthropic's guidance on long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

Built by [@allierays](https://github.com/allierays) | MIT License - [AllThrive AI](https://allthrive.ai)
