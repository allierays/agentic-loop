# Agentic Loop for Beginners

**No coding experience required to understand this page.**

---

## What Is This?

Agentic Loop is a tool that lets you describe what you want to build in plain English, and an AI builds it for you—automatically.

Think of it like having a junior developer who:
- Asks clarifying questions before starting
- Writes the code
- Tests their own work
- Fixes their mistakes
- Keeps going until it's done

You describe the feature. The AI does the rest.

---

## How Does It Work?

### Step 1: You Describe What You Want

You type something like:

> "Add a login page with email and password"

The AI (Claude) asks follow-up questions:
- "Should users be able to reset their password?"
- "Do you want a 'remember me' checkbox?"
- "Should it show error messages for wrong passwords?"

### Step 2: The AI Creates a Plan

Based on your answers, Claude creates a checklist of small tasks. Each task is something that can be built and tested independently.

For example, a login feature might become:
1. Create the login form
2. Add password validation
3. Connect to the database
4. Show error messages
5. Add "forgot password" link

This checklist is saved in a file called a "PRD" (Product Requirements Document).

### Step 3: The AI Builds Each Task

A program called "Ralph" takes over. For each task on the checklist:

1. **Read** - Ralph reads what needs to be built
2. **Build** - Ralph tells Claude to write the code
3. **Check** - Ralph runs automated tests to verify it works
4. **Save** - If tests pass, Ralph saves the work
5. **Repeat** - Move to the next task

If something fails, Ralph shows Claude the error and asks it to try again. This loop continues until everything works.

### Step 4: You Review the Result

When Ralph finishes, you have working code. You can:
- Test it yourself
- Ask for changes
- Add more features the same way

---

## Why Use This?

### Without Agentic Loop
1. You describe what you want to an AI
2. AI gives you code
3. You copy-paste it
4. It doesn't work
5. You go back and forth fixing errors
6. Repeat for hours

### With Agentic Loop
1. You describe what you want
2. Go do something else
3. Come back to working code

The AI handles the tedious back-and-forth of fixing errors, running tests, and making sure everything works together.

---

## What Do I Need?

### Required
- A computer (Mac, Windows, or Linux)
- [Node.js](https://nodejs.org/) installed (version 18 or newer)
- A [Claude](https://claude.ai/) account with Claude Code access

### Helpful But Not Required
- Basic familiarity with using the terminal/command line
- A code editor like [VS Code](https://code.visualstudio.com/)

---

## Ready to Try It?

When you're ready to set up and run your first loop, follow the step-by-step walkthrough in [Getting Started](GETTING-STARTED.md). It covers installation, setup, and the full two-terminal workflow.

---

## Common Questions

### "What if something goes wrong?"

Ralph automatically retries when things fail. It shows Claude the error and asks it to fix the problem. Most issues resolve themselves within a few attempts.

If Ralph gets stuck on the same error repeatedly, it will skip that task and move on. You can review what went wrong later.

### "Can I stop it?"

Yes. Press `Ctrl+C` in the Ralph window to stop. Your progress is saved—you can restart anytime and Ralph will continue where it left off.

### "What if I don't like what it built?"

You can:
- Ask Claude to change it (in Window 1)
- Edit the code yourself
- Start over with a new `/prd`

### "Is my code safe?"

Agentic Loop includes safety checks:
- Won't commit passwords or API keys
- Runs tests before saving changes
- Creates backups before modifying files

### "Do I need to know how to code?"

To use the basic features, no. To customize the results or fix edge cases, some coding knowledge helps.

---

## Glossary

| Term | Plain English |
|------|---------------|
| **Terminal** | The text-based app where you type commands |
| **Claude** | The AI that writes code |
| **Ralph** | The program that runs Claude in a loop |
| **PRD** | The checklist of tasks to build |
| **Story** | One task on the checklist |
| **Commit** | Saving your work (like hitting "Save" but for code) |
| **Loop** | Doing something repeatedly until it works |

---

## Next Steps

1. **Follow the full walkthrough**: [Getting Started](GETTING-STARTED.md) — installation, setup, and your first loop run
2. **Take the tour**: Run `/tour` in Claude for a guided walkthrough
3. **Explore customization**: [CUSTOMIZATION.md](CUSTOMIZATION.md) explains how to personalize your setup

---

## Getting Help

- **Something not working?** Check [Troubleshooting](TROUBLESHOOTING.md)
- **Want to learn more?** See [How Ralph Works](RALPH.md)
- **Have feedback?** Open an issue on [GitHub](https://github.com/anthropics/agentic-loop/issues)
