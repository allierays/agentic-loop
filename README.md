# Vibe and Thrive

**Idea → PRD → Code → Tests → Commit. Autonomously.**

A toolkit for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that ships features while you sleep.

## Quick Start

```bash
npm install vibe-and-thrive
claude
> /tour
```

## The Workflow

```
┌──────────────────────────────────────────────────────────────┐
│  YOU                          RALPH                          │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  claude                                                      │
│  > /idea add user dashboard                                  │
│                                                              │
│  ↓ Claude asks questions, explores code, generates PRD       │
│                                                              │
│  npx ralph run                                               │
│                                    → implement story 1       │
│                                    → verify (build/test/e2e) │
│                                    → commit ✓                │
│                                    → implement story 2       │
│                                    → verify                  │
│                                    → commit ✓                │
│                                    → ...                     │
│                                    → "All stories complete!" │
│  git push                                                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## What's Included

| Tool | Purpose |
|------|---------|
| **Ralph** | Autonomous loop: implement → verify → commit → repeat |
| **`/idea`** | Brainstorm features, generate PRDs |
| **`/vibe-check`** | Catch AI-generated code issues |
| **`/review`** | Security review with OWASP checks |
| **`/styleguide`** | Generate UI component reference |
| **Pre-commit hooks** | Block secrets, bad URLs, security issues |

## Commands

```bash
# In Claude
/idea [feature]       # Brainstorm → PRD
/vibe-check           # Code quality audit
/review               # Security review
/tour                 # Setup walkthrough

# In terminal
npx ralph run         # Start autonomous loop
npx ralph status      # Check progress
npx ralph stop        # Stop after current story
```

## Documentation

| Doc | What's in it |
|-----|--------------|
| [Ralph Architecture](docs/RALPH.md) | How the autonomous loop works |
| [Workflow Guide](docs/WORKFLOW.md) | End-to-end development process |
| [Cheatsheet](docs/CHEATSHEET.md) | Quick reference for all commands |
| [Bad Patterns](docs/BAD-PATTERNS.md) | AI code issues to avoid |
| [Prompting Guide](docs/PROMPTING-GUIDE.md) | Writing effective PROMPT.md |
| [TDD Guide](docs/TDD.md) | Test-driven development with Ralph |
| [Styleguide](docs/STYLEGUIDE.md) | Creating UI component references |
| [Contributing](docs/CONTRIBUTING.md) | How to contribute |

## Requirements

- Node.js 18+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- `jq`: `brew install jq` or `apt install jq`

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Invalid API key" | Remove `ANTHROPIC_API_KEY` from `.env` |
| "jq not found" | `brew install jq` or `apt install jq` |
| Browser check skipped | `npm install playwright && npx playwright install chromium` |

## License

MIT

---

Built by [AllThrive AI](https://allthrive.ai)
