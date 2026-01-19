---
description: Take an interactive tour of vibe-and-thrive - the system for going from idea to shipped code with AI.
---

# Vibe & Thrive Tour

## Step 1: Welcome

Print this exactly:

```
  ╦  ╦╦╔╗ ╔═╗   ┬   ╔╦╗╦ ╦╦═╗╦╦  ╦╔═╗
  ╚╗╔╝║╠╩╗║╣   ┌┼─   ║ ╠═╣╠╦╝║╚╗╔╝║╣
   ╚╝ ╩╚═╝╚═╝  └┘    ╩ ╩ ╩╩╚═╩ ╚╝ ╚═╝

  Setup complete! Here's what's configured:
```

Then check what was set up and list it:
- ✓ Slash commands installed (check `.claude/commands/` exists)
- ✓ Pre-commit hooks (check `.pre-commit-config.yaml` exists)
- ✓ Ralph initialized (check `.ralph/` exists)
- ✓ CLAUDE.md created (check `CLAUDE.md` exists)

---

## Step 2: Check for DNA

Check if `~/.claude/DNA.md` exists.

**If DNA.md does NOT exist:**

Use AskUserQuestion:
- **Question:** "Want to set up your personal preferences? This teaches me how you like to work."
- **Header:** "DNA setup"
- **Options:**
  - **Yes, set up my DNA** - "Takes ~2 minutes, makes our collaboration better"
  - **Skip for now** - "You can run /my-dna anytime"

If user selects "Yes, set up my DNA":
- Run the `/my-dna` command inline (execute its full flow)
- After completing, continue to Step 3

If user selects "Skip for now":
- Say: "No problem! Run `/my-dna` anytime."
- Continue to Step 3

**If DNA.md EXISTS:**

Skip this step entirely. Move to Step 3.

---

## Step 3: What's Next?

Use AskUserQuestion:
- **Question:** "What would you like to do?"
- **Header:** "Next step"
- **Options:**
  - **Walk me through the workflow** - "See how /idea → ralph → ship works"
  - **Show quick reference** - "Just the commands cheatsheet"
  - **I'm good, let me explore** - "You know where to find me"

---

### If "Walk me through the workflow":

Print this:

```
The System: Idea → PRD → Ralph → Ship

┌─────────────────────────────────────────────────┐
│  /idea "add user auth"                          │
│      ↓                                          │
│  Brainstorm → Write idea doc → You approve      │
│      ↓                                          │
│  Auto-split into testable stories (PRD)         │
│      ↓                                          │
│  ralph run                                      │
│      ↓                                          │
│  Autonomous loop: code → verify → fix → repeat  │
│      ↓                                          │
│  All tests pass → commit → next story           │
│      ↓                                          │
│  Done! Pre-commit hooks guard the code.         │
└─────────────────────────────────────────────────┘
```

Then say:

"**Try it:** Run `/idea "your feature here"` to start.

**Key commands:**
- `/idea` - Brainstorm and create PRDs
- `ralph run` - Execute PRDs autonomously
- `ralph status` - Check progress
- `/review` - Review changes before committing
- `/vibe-check` - Audit code quality"

---

### If "Show quick reference":

Print this:

```
Quick Reference
───────────────

Workflow:
  /idea "feature"     Brainstorm → PRD
  ralph run           Execute autonomously
  ralph status        Check progress

Quality:
  /vibe-check         Audit code quality
  /review             Review changes
  ralph check         Run verification

Other:
  /my-dna             Personal preferences
  /explain            Understand code
  /styleguide         Generate design system
  /vibe-help          This cheatsheet
```

---

### If "I'm good, let me explore":

Say: "You got it! I'm here when you need me. Try `/vibe-help` for a quick reference anytime."
