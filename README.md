# Vibe and Thrive

**Start messy. End with working code.**

A complete system for agentic coding. Inspired by [RALPH](https://ghuntley.com/ralph/).

## TL;DR

```bash
npm install vibe-and-thrive
```

```
/idea "your feature"  →  PRD  →  ralph run  →  Ship
```

## The Flow

### Step 1: /idea - Brainstorm to PRD

```
/idea "add user profiles"
    ↓
Plan mode: brainstorm, explore, ask questions
    ↓
Write docs/ideas/user-profiles.md
    ↓
You approve → auto-split into PRDs
    ↓
Write .ralph/prd.json
    ↓
You approve → ready for ralph run
```

Two approval gates. Nothing happens without your say-so.

### Step 2: Ralph - Autonomous Execution

```bash
ralph run      # Start the autonomous loop
ralph status   # Check progress anytime
```

Ralph works through PRD stories one by one:
- Picks a story → writes code → runs tests → commits when passing → next story

### Step 3: Pre-commit Hooks - Guardrails

Every `git commit` runs checks automatically. Secrets and security issues are blocked. Code quality issues are warned.

## Take the Tour

New to vibe-and-thrive? Run `/tour` in Claude Code.

The tour:
- Walks through the idea → PRD → Ralph → ship workflow
- Offers to auto-detect your tech stack and add it to CLAUDE.md
- Offers to set up your DNA (personal coding preferences)

## All Commands

### Slash Commands (Claude Code)

| Command | Description |
|---------|-------------|
| `/idea "feature"` | Brainstorm in plan mode, generate PRD for Ralph |
| `/tour` | Interactive walkthrough of vibe-and-thrive |
| `/my-dna` | Set up your personal style preferences |
| `/vibe-check` | Audit code quality before shipping |
| `/review` | Code review with OWASP security checks |
| `/explain` | Explain code line by line |
| `/styleguide` | Generate UI component design system |
| `/vibe-help` | Quick reference cheatsheet |
| `/vibe-list` | Complete command reference |

### Ralph CLI (Terminal)

| Command | Description |
|---------|-------------|
| `ralph run` | Run autonomous loop until all stories pass |
| `ralph run --max 10` | Limit to N iterations |
| `ralph status` | Show feature, stories, pass/fail counts |
| `ralph check` | Run all configured checks |
| `ralph verify US-001` | Verify a specific story |
| `ralph signs` | List all learned patterns |
| `ralph sign "pattern"` | Add a pattern Ralph should follow |
| `ralph progress` | Show last 50 lines of progress log |
| `ralph init` | Initialize .ralph/ in current directory |
| `ralph prd "notes"` | Generate PRD interactively |

### Vibe CLI (Terminal)

| Command | Description |
|---------|-------------|
| `vibe help` | Show terminal quick reference |

## License

MIT - see [LICENSE](LICENSE)

---

Built by [AllThrive AI](https://allthrive.ai)
