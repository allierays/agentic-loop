---
description: Brainstorm a feature idea, then generate PRDs for Ralph autonomous execution.
---

# /idea - From Brainstorm to PRD

You are helping the user go from a rough idea to executable PRDs for Ralph.

**CRITICAL: This command does NOT write code. It produces documentation files only.**

## When to Use

| Workflow | Best For |
|----------|----------|
| **`/idea`** | Structured brainstorming with guided questions - Claude leads |
| **Plan mode → save to `docs/ideas/`** | Free-form exploration - you lead the thinking |
| **`/prd "description"`** | Quick PRD, no docs artifact needed |

**Both `/idea` and plan mode can produce `docs/ideas/*.md` files.** The difference is who drives the conversation:
- `/idea` asks you structured questions (scope, UX, edge cases, etc.)
- Plan mode lets you explore freely with Claude's help

Use `/idea` when you want the structured checklist. Use plan mode when you prefer to think through it your way.

## User Input

```text
$ARGUMENTS
```

## Workflow

### Step 1: Start Brainstorming

If `$ARGUMENTS` is empty, ask: "What feature or idea would you like to brainstorm?"

If `$ARGUMENTS` has content, acknowledge it and proceed.

Say: "Let's brainstorm this idea. I'll help you think it through, then we'll create documentation for Ralph to execute."

### Step 2: Explore and Ask Questions

Help the user flesh out the idea through conversation:

1. **Understand the goal** - What problem does this solve? Who benefits?
2. **Explore the codebase** - Use Glob/Grep/Read to understand what exists and what patterns to follow
3. **Ask clarifying questions** - Up to 5 questions about:
   - Scope boundaries (what's in/out)
   - User experience (what does the user see/do)
   - Edge cases (what could go wrong)
   - Dependencies (what does this touch)
   - Security/permissions (who can do what)
   - Scale (how many users/items/requests?)

### Step 3: Summarize Before Writing

When you have enough information, summarize what you've learned:

Say: "Here's what I understand about the feature:

**Problem:** [summary]
**Solution:** [summary]
**Key decisions:** [list]

Ready to write this to `docs/ideas/{feature-name}.md`? Say **'yes'** or tell me what to adjust."

**STOP and wait for user confirmation before writing any files.**

### Step 4: Write the Idea File

Once the user confirms, write the idea file:

1. Create the directory if needed:
   ```bash
   mkdir -p docs/ideas
   ```

2. Write to `docs/ideas/{feature-name}.md` with this structure:
   ```markdown
   # {Feature Name}

   ## Problem
   What problem does this solve?

   ## Solution
   High-level description of the solution.

   ## User Stories
   - As a [user], I want to [action] so that [benefit]
   - ...

   ## Scope
   ### In Scope
   - ...

   ### Out of Scope
   - ...

   ## Architecture
   ### Directory Structure
   - Where new files should go (be specific: `src/components/forms/`, not just `src/`)

   ### Patterns to Follow
   - Existing components/utilities to reuse
   - Naming conventions

   ### Do NOT Create
   - List things that already exist (avoid duplication)

   ## Technical Notes
   - Dependencies
   - Security considerations

   ## Open Questions
   - Any unresolved decisions
   ```

3. Say: "I've written the idea to `docs/ideas/{feature-name}.md`.

   Review it and let me know:
   - **'approved'** - Ready to generate PRD
   - **'edit [changes]'** - Tell me what to change"

**STOP and wait for user response. Do not proceed until they say 'approved' or 'done'.**

### Step 5: Generate PRD

**Only proceed here after user explicitly approves the idea file.**

Say: "Now I'll generate the PRD from your idea file."

**Use the Skill tool** to invoke `/prd` with the idea file path:
```
Skill: prd
Args: docs/ideas/{feature-name}.md
```

This hands off to `/prd` which handles:
- Reading the idea file
- Splitting into stories
- Writing `.ralph/prd.json`
- All PRD schema details (testing, testSteps, MCP tools, etc.)

**DO NOT duplicate the PRD schema or guidelines here - /prd is the single source of truth.**

---

## Error Handling

- If user provides no arguments, ask what they want to brainstorm
- If user abandons mid-flow, the idea file is still saved for later
- If /prd fails, check the idea file has enough detail

---

## Guidelines

### Idea File Quality

A good idea file has:
- **Clear problem statement** - What's broken or missing?
- **Specific solution** - Not vague ("improve UX") but concrete ("add inline validation")
- **Scope boundaries** - What's explicitly out of scope?
- **Architecture hints** - Where do files go? What patterns to follow?

### ASCII Art for UI

If the feature involves UI, include ASCII mockups in the idea file:

```
┌─────────────────────────────────────┐
│  Dashboard                    [⚙️]  │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────┐  ┌─────────┐          │
│  │ Card 1  │  │ Card 2  │          │
│  │  $1,234 │  │  89%    │          │
│  └─────────┘  └─────────┘          │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ Recent Activity              │   │
│  │ • Item 1                     │   │
│  │ • Item 2                     │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

Ralph will read these from the idea file via `story.contextFiles`.
