# Agentic Loop

**Autonomous AI coding loop for Claude Code.**

A toolkit for implementing [RALPH](https://ghuntley.com/ralph/) with [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that helps you go from idea to shipped code.

> **Optimized for:** Python, TypeScript, React, Go/Hugo, and Docker projects.

---

## What It Does

**Customize your AI output:**
- `/my-dna` - Add your voice and values to claude.md
- `/styleguide` - Generate a UI component reference for consistent design

**Run autonomous coding loops:**
- `npx agentic-loop run` - Implement → verify → commit → repeat
- `npx agentic-loop run --fast` - Skip code review (~2x faster)

**Built-in guardrails:**
- `/vibe-check`, `/review` - On-demand quality checks
- Pre-commit hooks - Block secrets, URLs, debug statements
- Claude Code hooks - Real-time warnings while coding

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
/tour                    # Guided walkthrough
/idea 'your feature'     # Generate a PRD
```

**Terminal 2 - Ralph Loop:**
```bash
npx agentic-loop run       # Execute PRDs autonomously
npx agentic-loop run --fast  # Skip code review (~2x faster)
```

---

## How Ralph Works

```
┌─────────────────────────────────────────────────────────────┐
│                        RALPH LOOP                           │
├─────────────────────────────────────────────────────────────┤
│  1. Read prd.json → find next story where passes=false      │
│  2. Build prompt (story + context + failures + signs)       │
│  3. Spawn Claude with prompt                                │
│  4. Run verification (lint, tests, browser, code review)    │
│  5. Pass? → commit, next story                              │
│     Fail? → save error, retry with failure context          │
│  6. Repeat until all stories pass                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Docs

[How Ralph Works](docs/RALPH.md) · [Cheatsheet](docs/CHEATSHEET.md) · [Hooks](docs/HOOKS.md) · [Troubleshooting](docs/TROUBLESHOOTING.md) · [Contributing](docs/CONTRIBUTING.md)

---

MIT License - [AllThrive AI](https://allthrive.ai)
