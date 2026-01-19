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

## Step 3: Quick Reference

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
  /my-dna             Set project values and voice
  /explain            Understand code
  /styleguide         Generate design system
  /vibe-help          This cheatsheet
```

Say: "You're all set. Run `/idea "your feature"` to get started."
