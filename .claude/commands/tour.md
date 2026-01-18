---
description: Take an interactive tour of vibe-and-thrive - the system for going from idea to shipped code with AI.
---

# Vibe & Thrive Tour

Print this welcome message exactly as shown:

```
  ╦  ╦╦╔╗ ╔═╗   ┬   ╔╦╗╦ ╦╦═╗╦╦  ╦╔═╗
  ╚╗╔╝║╠╩╗║╣   ┌┼─   ║ ╠═╣╠╦╝║╚╗╔╝║╣
   ╚╝ ╩╚═╝╚═╝  └┘    ╩ ╩ ╩╩╚═╩ ╚╝ ╚═╝

  Tools to help you thrive with agentic coding
  by AllThrive.ai
  ─────────────────────────────────
```

Then say: "Welcome to the tour! Let me show you how vibe-and-thrive works."

---

## The System

**Idea → PRD → Ralph → Ship**

1. **`/idea`** - Brainstorm in plan mode, write to `docs/ideas/`, approve
2. **Auto-split** - Your idea becomes small, testable PRDs
3. **`ralph run`** - Autonomous coding until all tests pass
4. **Pre-commit hooks** - Guard every commit

Start messy. End with working code.

---

## Step 1: /idea - Brainstorm to PRD

**What it does:** Takes you from a rough idea to executable PRDs.

**The flow:**
```
/idea "add user profiles"
    ↓
Plan mode: brainstorm, explore, ask questions
    ↓
Write docs/ideas/user-profiles.md
    ↓
Open in TextEdit for review
    ↓
You approve → auto-split into PRDs
    ↓
Write .ralph/prd.json
    ↓
Open in TextEdit for review
    ↓
You approve → ready for ralph run
```

**Two approval gates:**
- Approve the idea before splitting
- Approve the PRDs before executing

Nothing happens without your say-so.

**Try it:** `/idea "your feature here"`

---

## Step 2: Ralph - Autonomous Execution

**What it does:** Works through your PRD stories one by one, coding until tests pass.

**How it works:**
1. Picks one story from `.ralph/prd.json`
2. Writes code to make it pass
3. Runs test steps to verify
4. Commits when tests pass
5. Moves to next story
6. Repeats until done

**Commands:**
```bash
ralph run      # Start the loop
ralph status   # Check progress
ralph check    # Run verification only
ralph signs    # Show learned patterns
```

**The loop runs autonomously.** You can step away. Ralph commits working code as it goes.

---

## Step 3: Pre-commit Hooks - Guardrails

**What it does:** Catches problems on every `git commit`.

**What gets blocked:**
- Hardcoded secrets and API keys
- Hardcoded localhost URLs
- Security vulnerabilities

**What gets warned:**
- TypeScript `any` types
- Empty catch blocks
- Debug statements
- Overly complex functions

```bash
git commit -m "add feature"
# ✓ check-secrets........passed
# ✗ check-hardcoded-urls..FAILED
# Commit blocked! Fix the issue first.
```

Pre-commit hooks run automatically. Bad code doesn't ship.

---

## CLAUDE.md - Teaching Claude Your Project

**What it is:** A markdown file that teaches Claude about your project.

**What goes in it:**
- Tech stack (Python, React, PostgreSQL, etc.)
- Coding standards (naming conventions, patterns)
- Project-specific rules ("always use our Button component")
- Architecture notes and gotchas

**Where it lives:** `CLAUDE.md` in your project root

**Why it matters:** Claude reads this file automatically. A good CLAUDE.md means Claude writes code that fits your project from the start.

**Example:**
```markdown
## Tech Stack
- Backend: Django 4.2, Python 3.11
- Frontend: React 18, TypeScript
- Database: PostgreSQL 15

## Patterns
- Use `@api_view` decorator for all endpoints
- Frontend components go in `src/components/`
- Always use our custom `useApi` hook for data fetching
```

---

### Interactive: Detect Project Info

Now use the AskUserQuestion tool to ask:

**Question:** "Want me to scan your project and add detected info to CLAUDE.md?"

**Header:** "Auto-detect"

**Options:**
- **Yes, scan my project** - I'll detect your tech stack and append it to CLAUDE.md
- **No, skip this** - You can always do this manually later

**If user selects "Yes, scan my project":**

1. Scan for config files and detect tech stack:
   - `package.json` → Node.js, check for react/next/vue dependencies
   - `tsconfig.json` → TypeScript
   - `tailwind.config.js` or `tailwind.config.ts` → Tailwind CSS
   - `requirements.txt` or `pyproject.toml` → Python
   - `manage.py` → Django
   - `Cargo.toml` → Rust
   - `go.mod` → Go
   - `Gemfile` → Ruby/Rails
   - `playwright.config.ts` or `playwright.config.js` → Playwright

2. Scan for directory patterns:
   - `src/components/` → Component-based architecture
   - `src/hooks/` → Custom hooks
   - `src/api/` or `app/api/` → API routes
   - `tests/` or `__tests__/` → Test directory

3. Show the user what was detected

4. Append to CLAUDE.md (create if doesn't exist) with this format:

```markdown

---

## Detected Project Info (auto-generated)

**Tech Stack:**
- Runtime: [detected]
- Framework: [detected]
- Language: [detected]
- Styling: [detected]
- Testing: [detected]

**Project Structure:**
- Components: `[path]`
- API Routes: `[path]`
- Tests: `[path]`

*Detected by vibe-and-thrive. Add your own rules above this section.*
```

5. Tell the user: "Done! I've appended detected info to CLAUDE.md. You can edit it anytime to add your own rules and patterns."

**If user selects "No, skip this":**

Say: "No problem! You can always edit CLAUDE.md manually or run `/tour` again."

---

## Your Personal Style - /my-dna

**What it is:** Your personal preferences for how Claude should work with you.

**What it captures:**
- Your core values (simplicity vs thoroughness, etc.)
- Communication style (brief vs detailed, casual vs formal)
- How you like to learn (show alternatives? explain why?)

**Where it lives:** `~/.claude/DNA.md` (global, applies to all your projects)

This is separate from CLAUDE.md because:
- CLAUDE.md = project standards (shared with team)
- DNA.md = your personal preferences (just for you)

---

### Interactive: Set Up Your DNA

Now use the AskUserQuestion tool to ask:

**Question:** "Want to set up your personal DNA now?"

**Header:** "DNA setup"

**Options:**
- **Yes, let's do it** - Takes about 2 minutes
- **No, maybe later** - Run /my-dna anytime

**If user selects "Yes, let's do it":**

Run the /my-dna wizard inline. This means you should follow the instructions in `/my-dna` to:
1. Ask about core values (multiSelect)
2. Ask about communication style (explanations detail level, tone)
3. Ask about working preferences (when stuck, proactive suggestions)
4. Ask about learning style (multiSelect)
5. Optionally collect writing samples
6. Generate `~/.claude/DNA.md`

After completing, continue with the tour.

**If user selects "No, maybe later":**

Say: "No problem! Run `/my-dna` anytime to set up your preferences."

---

## Supporting Tools

| Command | When to use |
|---------|-------------|
| `/my-dna` | Set up your personal style preferences |
| `/vibe-check` | Audit code quality anytime |
| `/review` | Review changes before committing |
| `/explain` | Understand existing code |
| `/styleguide` | Generate design system reference |
| `/vibe-help` | Quick reference cheatsheet |

---

## Quick Start

```bash
# 1. Have an idea? Brainstorm it.
/idea "your feature description"

# 2. Review and approve the PRD

# 3. Let Ralph build it
ralph run

# 4. Check progress anytime
ralph status
```

That's it. Idea → PRD → Ralph → Ship.
