# Getting Started: End-to-End User Flow

A step-by-step walkthrough from zero to running your first autonomous coding loop.

**The idea:** You think, Claude codes. You use Claude as a thought partner to plan features, talk through decisions, and debug problems. The loop handles the software engineering — writing code, running tests, fixing lint errors, committing. Think of it like CI/CD for AI coding: you define what you want, and the loop builds, verifies, and ships it.

> **Platform note:** This guide is optimized for macOS. It should work on Linux with minor adjustments (e.g., `apt` instead of `brew`). For Windows, we recommend using [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) — or ask Claude for help adapting any step to your environment.

---

## Step 1: Prerequisites

Before you start, make sure you have these installed:

| Tool | Why | Install |
|------|-----|---------|
| **Node.js 18+** | Runtime for agentic-loop | [nodejs.org](https://nodejs.org/) |
| **Claude Code CLI** | The AI that writes your code | `npm install -g @anthropic-ai/claude-code` |
| **jq** | JSON parsing (used by Ralph internally) | `brew install jq` (Mac) or `sudo apt install jq` (Linux) |
| **Git** | Version control and auto-commits | [git-scm.com](https://git-scm.com/) |

Verify everything is ready:

```bash
node --version    # Should be 18+
claude --version  # Should return a version
jq --version      # Should return a version
git --version     # Should return a version
```

---

## Step 2: Get a Git Repo

You need a git repository with code in it. This can be an existing project or a fresh one.

**Using an existing project:**

```bash
cd ~/Sites/my-project
```

**Starting from scratch:**

```bash
mkdir my-project && cd my-project
git init
npm init -y
```

Now install agentic-loop and run setup:

```bash
npm install agentic-loop
npx agentic-loop setup
```

Setup auto-detects your project type (Node, Python, Go, etc.) and creates:
- `.ralph/config.json` — project-specific configuration
- `.ralph/progress.txt` — execution log
- `PROMPT.md` — the template prompt Ralph feeds to Claude

> **Note:** If you already have a project with tests, linting, and a dev server, Ralph will pick up on those automatically from your `package.json`, `pyproject.toml`, or equivalent.

---

## Step 3: Plan Your Feature (Terminal 1)

This is where you use Claude as a **thought partner**. You're not writing code here — you're thinking out loud about what you want to build, and Claude helps you shape it into something the loop can execute.

Open your first terminal:

```bash
claude --dangerously-skip-permissions
```

> The `--dangerously-skip-permissions` flag lets Claude edit files without asking for confirmation each time. This is needed for autonomous workflows.

Now describe what you want to build:

```
/idea "add a contact form that sends emails"
```

Claude enters **plan mode**. It will:

1. **Ask clarifying questions** — "Should it have a captcha?" "What email service?" "What fields?"
2. **Explore your codebase** — Find existing patterns, routes, components, and conventions
3. **Generate an idea file** — Saved to `docs/ideas/contact-form.md`
4. **Split into stories** — Small, testable tasks saved to `.ralph/prd.json`

Answer Claude's questions honestly. The more specific you are, the better the PRD will be. You don't need to know *how* to build it — just *what* you want. Claude figures out the technical approach.

---

## Step 4: Review the Plan

After Claude generates the PRD, it opens `.ralph/prd.json` in TextEdit so you can read through it yourself. This is your chance to eyeball the stories before anything runs.

You don't need to understand everything in this file. Skim it — do the stories make sense at a high level? Does the order feel right? Close TextEdit when you're done.

### Talk it through with Claude

Back in **Terminal 1**, use Claude as a sounding board. You don't need to know the technical details — that's Claude's job. Just ask in plain language:

```
Review the PRD one more time. Does the story order make sense?
Is anything missing? Are there any problems you'd fix?
```

Claude will re-read the PRD, point out issues, and fix them automatically.

**Ask Claude to explain anything you don't understand:**

```
What does story 3 actually do? Why does it need to come before story 4?
```

```
Is the PRD in the right order? Does each story have what it needs from the one before it?
```

```
Are all the test steps actually passable? I don't want false positives —
make sure each test can really run and verify the story works.
```

```
What are test steps? Are the ones in this PRD good enough?
```

```
Is this PRD too ambitious? Should we simplify it?
```

The point is: **you don't need to know the technical answer yourself.** Ask Claude. It will explain what's going on and fix whatever needs fixing. Your job is to make sure the feature description matches what you actually want — Claude handles the technical correctness.

Once Claude says the PRD looks good, you're ready to hand it off to the loop.

---

## Step 5: Run the Loop (Terminal 2)

This is where the automated engineering happens. The loop takes your plan and turns it into working, tested, committed code — story by story.

Open a **second terminal** window:

```bash
cd ~/Sites/my-project
npx agentic-loop run
```

Ralph takes over:

```
[ralph] PRD check passed ✓
[ralph] Starting story TASK-001: Create contact form component
[ralph] Spawning Claude session...
[ralph] Verification: lint ✓ tests ✓ prd-steps ✓
[ralph] Committed: feat(TASK-001): Create contact form component
[ralph] Starting story TASK-002: Add email sending service
...
```

For each story, the loop:
1. Spawns a Claude session with the story requirements
2. Claude writes the code
3. Ralph verifies it — lint, tests, and the PRD's own test steps
4. If it passes, Ralph commits and moves to the next story
5. If it fails, Ralph retries with the error context

While it runs, you can monitor progress:

```bash
# In any terminal
npx agentic-loop status     # Current story and progress
npx agentic-loop progress   # Recent log entries
```

You can also stop gracefully at any time:

```bash
npx agentic-loop stop       # Finishes current story, then stops
```

Or press `Ctrl+C` to stop immediately. Progress is saved — you can resume with `npx agentic-loop run`.

---

## Step 6: When the Loop Fails

The loop will fail sometimes. That's normal — just like CI/CD pipelines fail. Ralph retries automatically up to 8 times per story, but if it keeps hitting the same wall, it will skip the story and move on.

Here's where the two-terminal workflow shines: **Terminal 2 runs the code, Terminal 1 helps you think through problems.**

### Check what failed

Look at the failure output in your execution terminal, or read the failure log:

```bash
cat .ralph/last_failure.txt
```

### Paste the error into your planning terminal

Switch back to **Terminal 1** (where Claude is still running) and paste the error. Ask directly:

```
The loop failed on TASK-003 with this error:

[paste the error here]

Why did this fail and what should I change so it doesn't fail again?
```

Claude will analyze the error and suggest fixes. You don't need to understand the error yourself — just copy-paste it and let Claude explain. Common causes:

| Error | Likely cause | Fix |
|-------|-------------|-----|
| `column does not exist` | Missing database migration | Run migrations or reset DB |
| `connection refused` | Dev server not running | Start your dev server |
| `test file not found` | Story references tests that don't exist yet | Reorder stories or add test creation |
| `lint error` | Code style violations | Usually auto-fixes on retry |
| `timeout` | Story is too large for one session | Split into smaller stories |

### Apply the fix

If Claude identifies a structural issue (like a missing migration or wrong story order), fix it:

- **PRD issue:** Ask Claude to update `.ralph/prd.json` for you
- **Code issue:** Let Claude fix the code in Terminal 1, then re-run the loop
- **Config issue:** Ask Claude to update `.ralph/config.json` (see Step 7)

Then re-run:

```bash
npx agentic-loop run
```

Ralph picks up where it left off, skipping completed stories.

---

## Step 7: Update Your Config

After your first loop run, you might want to tweak how Ralph behaves. The good news: you don't need to edit config files by hand. Just ask Claude.

Back in **Terminal 1**, tell Claude what you want to change:

```
The loop kept timing out on big stories. Can you increase the session timeout?
```

```
I don't want Ralph to run the linter — my project doesn't have one set up yet.
Can you turn that off in the config?
```

```
Ralph should try more times before giving up on a story. Can you bump up the retry limit?
```

Claude will update `.ralph/config.json` for you.

If you want to see what's currently configured:

```bash
npx agentic-loop config show
```

> **Note:** Most of the config is set up automatically during `npx agentic-loop setup`. You only need to change things if something isn't working the way you want.

---

## Step 8: Teach Ralph with Signs

**Signs** are learned patterns — things Ralph should always remember across every story and every loop run. They're injected into every Claude prompt automatically.

Think of signs as persistent instructions: "Hey, every time you write code for this project, remember this."

### When to add a sign

Add a sign when you notice the same mistake happening more than once:

- Claude keeps using the wrong import path
- Tests fail because Claude forgets to mock a specific dependency
- Claude uses `var` instead of `const` or forgets a project convention

You can describe these in plain language — you don't need to know the fix, just the pattern you're seeing:

```
/sign "Stop using moment.js — use date-fns instead" frontend
```

```
/sign "The database client is at src/lib/db, not src/db" general
```

### From the command line

```bash
npx agentic-loop sign "Always use bcrypt with cost 12 for password hashing" backend
npx agentic-loop sign "All API responses must include a requestId field" backend
```

### View your signs

```bash
npx agentic-loop signs
```

### Remove a sign

```bash
npx agentic-loop unsign "sign-001"       # By ID
npx agentic-loop unsign "bcrypt"          # By pattern substring match
```

Signs live in `.ralph/signs.json` and persist across loop runs. They're one of the most powerful tools for improving loop quality over time — the more you teach Ralph about your project's conventions, the fewer retries you'll need.

---

## Step 9: Run the Loop Again

Now that you've:
- Fixed any issues from the first run
- Tuned your config
- Added signs for recurring patterns

Run the loop again:

```bash
npx agentic-loop run
```

Ralph continues from where it left off. Completed stories are skipped. Failed stories are retried with:
- The accumulated failure context from previous attempts
- Your new signs injected into every prompt
- Updated config settings

Each loop run should go smoother than the last. Over time, your signs and config build up a project-specific knowledge base that makes Ralph increasingly effective.

---

## The Full Picture

Here's how the two terminals work together — you think, the loop builds:

```
┌──────────────────────────────┐    ┌──────────────────────────────┐
│  TERMINAL 1: You + Claude    │    │  TERMINAL 2: The Loop        │
│  (thinking & planning)       │    │  (building & testing)        │
│                              │    │                              │
│  1. /idea "feature"          │    │                              │
│  2. Answer questions         │    │                              │
│  3. Review PRD               │    │                              │
│                              │    │  4. npx agentic-loop run     │
│                              │    │     [stories execute...]     │
│                              │    │                              │
│  5. Paste failures here      │    │  ← failures happen           │
│     "Why did this fail?"     │    │                              │
│  6. /sign "learned pattern"  │    │                              │
│                              │    │  7. npx agentic-loop run     │
│                              │    │     [continues...]           │
│                              │    │                              │
│  8. /vibe-check              │    │                              │
│  9. Review & ship            │    │                              │
└──────────────────────────────┘    └──────────────────────────────┘
```

---

## What's Next

- **Take the tour:** Run `/tour` in Claude Code for a guided walkthrough of all features
- **Validate your PRD:** Run `/prd-check` to catch story issues before the loop runs
- **Add custom checks:** Write your own PRD validation rules — see [PRD Check](PRD-CHECK.md)
- **Run a quality check:** Use `/vibe-check` after the loop completes to catch AI-generated anti-patterns
- **Set your preferences:** Run `/my-dna` to tell Claude how you like to work
- **Explore the commands:** Run `/vibe-list` for a full command reference
- **Read the deep dive:** [RALPH.md](RALPH.md) explains the architecture in detail
- **Troubleshooting:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues
