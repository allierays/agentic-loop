# Merge /idea into /prd and Accept Plan Files

## Context

The `/idea` skill is a separate brainstorming step that asks hardening questions (security, scale, scope, migration) then hands off to `/prd`. Meanwhile, Claude Code's plan mode writes plans to `docs/plans/` with no path into `/prd`.

This change:
1. Moves `/idea`'s hardening questions into `/prd` as a new step
2. Makes `/prd` accept plan files from `docs/plans/`
3. Removes the `/idea` skill entirely
4. Updates all docs and README with the new workflow

New workflow: **plan mode → `/prd plans/my-feature` → hardening questions → stories → ralph run**

5. Enhances `/prd-check` to cross-reference PRD against signs and learned patterns

---

## Part 1: Enhance `/prd` skill

**Files:** `.claude/skills/prd/SKILL.md` + `.claude/commands/prd.md` (identical copies, both change)

### Step 1 — Expand input detection (lines 20-38)

Add plan file scanning and detection:
- Empty args: scan both `docs/ideas/*.md` and `docs/plans/*.md`
- New branch for plan file: `plans/` prefix or `docs/plans/` path
- Bare names: check `docs/ideas/{name}.md` first, fall back to `docs/plans/{name}.md`

### New Step 2c — "Read and Understand the Plan" (after Step 2b)

Read freeform plan file, summarize Feature/Goal/Approach/Files, then hand off to hardening step.

### New Step 2.5 — "Harden the Requirements" (after ALL Step 2 variants, before Step 3)

This is `/idea`'s structured questioning, now built into `/prd`. Runs for every input type. Asks only about gaps the input doesn't already cover:

- **Scope & UX:** In scope vs out? User-facing? Edge cases?
- **Security** (if auth/input/data): Auth, passwords, validation, rate limiting, sensitive data
- **Scale** (if lists/data/APIs): Volume, pagination, caching, indexes
- **Migration** (if restructuring): Source→dest mapping, phases, verification commands

### Consolidate Step 2b questions into Step 2.5

Current Step 2b asks "Type? Scale? Anything else?" which overlaps with the new hardening step. Simplify Step 2b to just: explore codebase, summarize understanding, confirm. Move all questioning to Step 2.5.

### Other changes to SKILL.md

- Step 6e (line 179): "source file" instead of "idea file" in contextFiles validation
- Step 6 fix table (line 217): "source file (idea or plan)" instead of "idea file"
- Schema `ideaFile` (line 299): note it accepts plan paths too
- Field Reference (line 407): "(idea or plan path)"
- Step 9 (line 277): `{source-file-path}` instead of `{idea-file-path}`
- Context Files section (line 786): add plan file example

---

## Part 2: Delete `/idea` skill

- Delete `.claude/skills/idea/SKILL.md`
- Delete `.claude/commands/idea.md`

---

## Part 3: Update README.md

**Current** (lines 21-28):
```
│  /idea 'your feature or bugfix'        │  │ Validate all stories upfront     │
```

**New** — replace Terminal 1 planning section:
```
│  PLAN FEATURES                         │
│  /prd 'your feature or bugfix'         │
│  → Claude asks hardening questions     │
│  → Explores codebase                   │
│  → Generates PRD                       │
│  (or use plan mode first, then         │
│   /prd plans/my-feature.md)            │
```

**Quick Start** (lines 67-76) — replace:
```bash
claude
/tour                    # Guided walkthrough (recommended first time)
/prd 'your feature'      # Generate a PRD (asks hardening questions first)

---
# Already have a plan file from plan mode?
/prd plans/my-plan       # Turn a plan into a PRD
```

---

## Part 4: Update docs

### `docs/WORKFLOW.md`

**Step 1** (lines 15-29): Replace `/idea` workflow with `/prd`:
- Title: "Plan Your Feature" instead of "Brainstorm Your Idea"
- Show two paths: `/prd "description"` (direct) or plan mode → `/prd plans/file`
- Output is `.ralph/prd.json` directly (no intermediate docs/ideas/ step)

**Quick Reference table** (line 171): `/idea` → `/prd`

**Bug fix workflow** (line 196): "Describe the bug in `/prd`"

**Quick changes** (line 225): "for anything non-trivial, use `/prd`"

**The Goal** (line 261): "Clear requirements in `.ralph/prd.json`" instead of "docs/ideas/"

### `docs/GETTING-STARTED.md`

**Step 4** (lines 111-131): Replace `/idea` with `/prd`:
```
/prd "add a contact form that sends emails"
```
Claude will:
1. Ask hardening questions (security, scale, scope)
2. Explore your codebase
3. Split into stories in `.ralph/prd.json`
4. Open for your approval

Mention plan mode as alternative path.

**The Full Picture diagram** (lines 438-462): Replace `/idea "feature"` with `/prd "feature"` on line 443.

### `docs/CHEATSHEET.md`

**Workflow** (line 10): `/prd "your feature"` instead of `/idea`

**Slash Commands table** (lines 47-59): Remove `/idea` row, update `/prd` description to "Brainstorm, harden, and generate PRD from description, idea file, or plan file"

### `docs/SKILLS.md`

**Remove `/idea` section** (lines 19-36). Update `/prd` section (lines 40-49) to be the primary command:

```markdown
### `/prd`

**The core workflow command.** Generate an executable PRD for Ralph.

/prd "add user authentication with OAuth"
/prd docs/ideas/auth.md
/prd plans/my-feature

Claude will:
1. Read your input (description, idea file, or plan file)
2. Ask hardening questions (security, scale, scope)
3. Explore your codebase
4. Split into stories in `.ralph/prd.json`
5. Open for your approval
```

**Quick Reference table** (line 253): Remove `/idea` row, update `/prd` to "Brainstorm → Harden → PRD → Ready for Ralph"

**Tour section** (line 74): "The /prd → Ralph → Ship workflow"

### `docs/customizing-ralph.md`

**Section "The basics"** (lines 7-29): Remove `/idea` subsection. Restructure as:

```markdown
## The basics: /prd vs prd.json

### /prd — from idea to execution plan

Run `/prd` when you want to turn an idea into executable stories. You can:
- Describe it directly: `/prd "add user auth"`
- Point to a plan file: `/prd plans/auth-feature`
- Point to an idea file: `/prd auth`

Claude asks hardening questions (security, scale, scope), explores your codebase,
and splits the feature into small, ordered stories.

### prd.json — the execution plan

This is the file Ralph actually reads when it runs...
```

**Quick reference table** (line 159): Remove `/idea` row.

### `docs/ARCHITECTURE.md`

**Phase 1 box** (lines 62-71): Replace `/idea` with `/prd` in the ASCII diagram
**Phase 2 box** (line 77): Remove "called automatically by /idea"
**`/idea` Command section** (lines 108-114): Replace with `/prd` command description
**Table** (line 512): Remove `idea.md` row, update `prd.md` row

### `docs/RALPH.md`

**Line 569**: "The `/prd` command generates PRDs" instead of "/idea"

### `docs/BEGINNERS.md`

**Line 124**: "Start over with a new `/prd`"

### `docs/PRD-CHECK.md`

**Line 109**: "Signs, custom checks, /prd" instead of "/idea vs /prd"

### `docs/LOOPGRAM.md`

**Lines 19, 101**: Update `/save` references to mention `/prd` instead of `/idea`

---

## Part 5: Update skills/commands that reference `/idea`

### `.claude/skills/tour/SKILL.md` + `.claude/commands/tour.md`

- Line 340: `/prd [feature]       Brainstorm → PRD`
- Line 357: `Run /prd [your next feature]`

### `.claude/skills/prd-check/SKILL.md`

- Line 20: "Generate one first with `/prd`" (remove `/idea`)

### `.claude/skills/vibe-help/SKILL.md` + `.claude/commands/vibe-help.md`

- Line 14: `/prd [feature]          brainstorm & generate PRD`

### `.claude/skills/vibe-list/SKILL.md` + `.claude/commands/vibe-list.md`

- Remove `/idea` entries from all tables
- Update `/prd` description to include brainstorming + plan file support

### `.claude/skills/loopgram/SKILL.md`

- Lines 17, 19: Update workflow to reference `/prd` instead of `/idea`

---

## Part 6: Update bash scripts

### `ralph/prd.sh`

- Line 121: Update contextFiles example from `docs/ideas/feature.md` to include plan file path option

### `ralph/prd-check.sh`

- Lines 122, 134, 143, 154, 166: `/idea` → `/prd` in error messages

### `ralph/init.sh`

- Lines 71, 680-681, 693, 732, 737: `/idea` → `/prd`

### `ralph/loop.sh`

- Lines 723, 725, 1703: `/idea` → `/prd`

### `ralph/setup.sh`

- Line 189: `/idea` → `/prd`

### `ralph/setup/feature-tour.sh`

- Line 133: `/idea` → `/prd`

### `ralph/setup/tutorial.sh`

- Lines 86, 138, 148: `/idea` → `/prd`

---

## Part 7: Update tests

### `templates/examples/CLAUDE-fullstack.md`

- Lines 252-253: Replace `/idea` workflow with `/prd`

### `tests/install.test.ts`

- Line 34: Remove or update test checking for `/idea` skill presence

---

## Part 8: Enhance `/prd-check` to cross-reference signs and learnings

**File:** `.claude/skills/prd-check/SKILL.md`

Currently `/prd-check` only runs structural validation (`npx ralph prd-check --dry-run`). It doesn't check if the PRD accounts for known patterns from past experience.

### New workflow (replace current SKILL.md content):

```markdown
### Step 1: Check PRD Exists
(same as current)

### Step 2: Load Project Knowledge

Read the project's accumulated knowledge:

1. Read signs:
   ```bash
   cat .ralph/signs.json 2>/dev/null
   ```

2. Read suggested signs (last 50 lines — file can be huge):
   ```bash
   tail -50 .ralph/suggested-signs.txt 2>/dev/null
   ```

3. Read recent progress for failure patterns:
   ```bash
   tail -100 .ralph/progress.txt 2>/dev/null
   ```

### Step 3: Run Structural Validation (dry-run)

```bash
npx ralph prd-check --dry-run 2>&1
```

Present any structural issues found.

### Step 4: Cross-Reference Against Signs

Read `.ralph/prd.json` and for each story, check if any sign applies:

- **Backend signs** → check against backend stories
- **Frontend signs** → check against frontend stories
- **General signs** → check against all stories

For each applicable sign, verify the story's `acceptanceCriteria`, `constraints`,
`notes`, or `testSteps` reflect the pattern. Flag stories that should account for
a sign but don't.

**Examples:**
- Sign: "Always use bcrypt cost 10+ for passwords" → Flag auth stories missing
  bcrypt in acceptanceCriteria
- Sign: "Use date-fns instead of moment.js" → Flag frontend stories that create
  date utilities without this constraint
- Sign: "Add data-testid for Playwright selectors" → Flag frontend stories missing
  this in constraints

### Step 5: Check Against Suggested Learnings

Scan `suggested-signs.txt` for patterns relevant to the current PRD's feature area.
Flag any recurring failure patterns that the PRD's stories don't address.

### Step 6: Present Results

Summarize all findings in categories:

> **Structural Issues** (from prd-check):
> - [list]
>
> **Sign Conflicts** (stories that don't account for known patterns):
> - TASK-003: Missing sign "bcrypt cost 10+" in auth story
> - TASK-005: Missing sign "data-testid attributes" in frontend story
>
> **Suggested Improvements** (from past learnings):
> - [relevant patterns from suggested-signs.txt]

Ask: "Would you like me to fix these issues in the PRD?"

**STOP and wait for user response.**

If yes, update `.ralph/prd.json`:
- Add missing sign patterns to relevant story `constraints` or `acceptanceCriteria`
- Fix structural issues per PRD best practices
- Write the fixed file back
```

---

## No changes needed

| File | Why |
|------|-----|
| `ralph/prd.sh` (logic) | Doesn't parse content, just passes text to Claude |
| `ralph/prd-check.sh` (validation) | Checks `contextFiles` length, not paths |
| `ralph/loop.sh` (loop logic) | Reads `contextFiles` generically |
| `templates/prd-example.json` | `docs/ideas/` paths still valid as input |
| `src/loopgram/saver.ts` | Still saves to `docs/ideas/` — that dir isn't going away |

---

## Verification

1. `/prd plans/test-plan` — reads plan file, asks hardening questions, generates stories
2. `/prd auth` — reads idea file, asks hardening questions (backward compatible)
3. `/prd 'add logout button'` — asks hardening questions from description
4. `/prd` with no args — lists both idea files and plan files
5. `/idea` — should not be found as a skill
6. `grep -r '/idea' .claude/skills/ .claude/commands/` — no remaining references
7. `grep -r '/idea' docs/ README.md` — no remaining references (except docs/ideas/ directory paths which are fine)
8. `grep -r '/idea' ralph/` — no remaining references
9. SKILL.md and prd.md are identical after changes
10. `/prd-check` — reads signs.json, cross-references against PRD stories, reports conflicts
