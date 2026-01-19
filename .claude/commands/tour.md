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

## Step 2: Check Ralph Config

Check if `.ralph/config.json` exists and has auth configured.

```bash
cat .ralph/config.json 2>/dev/null | jq -r '.auth.testUser // empty'
```

**If auth.testUser is empty:**

Use AskUserQuestion:
- **Question:** "Want to configure test credentials? Ralph needs these to verify authenticated endpoints."
- **Header:** "Test auth"
- **Options:**
  - **Yes, configure now** - "Enter test user email and password"
  - **Skip for now** - "Edit .ralph/config.json later"

If user selects "Yes, configure now":
- Ask: "What's your test user email?"
- Ask: "What's the password?" (note: will be stored in .ralph/config.json)
- Update `.ralph/config.json` with the credentials using jq
- Say: "Test credentials saved to `.ralph/config.json`"

If user selects "Skip for now":
- Say: "No problem! Edit `.ralph/config.json` to add `auth.testUser` and `auth.testPassword` later."

**If auth.testUser is NOT empty:**

Say: "✓ Test credentials configured"

---

## Step 3: Check for DNA

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
- After completing, continue to Step 4

If user selects "Skip for now":
- Say: "No problem! Run `/my-dna` anytime."
- Continue to Step 4

**If DNA.md EXISTS:**

Skip this step entirely. Move to Step 4.

---

## Step 4: Quick Reference

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
