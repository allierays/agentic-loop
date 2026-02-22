# Update README.md to Feature Plan Mode Workflow

## Context

The README currently shows a two-terminal workflow where `/prd 'description'` is the primary entry point, with plan mode as a parenthetical aside. The actual workflow is now a clear pipeline:

**plan mode → `/prd` → `/prd-check` → `ralph run`**

There is no more `/idea`. Plan mode is how you think through features. `/prd` turns plans into executable stories. `/prd-check` validates them. `ralph run` executes.

## Changes — `README.md`

### 1. Rewrite the two-terminal ASCII diagram (lines 13-48)

New left column (Terminal 1) shows the linear pipeline:

```
  THE PIPELINE
  1. Plan mode
     → Think through the feature
     → Claude explores codebase
     → Plan saved to docs/plans/

  2. /prd plans/my-feature
     → Hardening questions
     → Generates .ralph/prd.json

  3. /prd-check
     → Validate stories
     → Cross-ref signs
     → Auto-fix issues

  ENHANCE AS YOU LEARN
  /sign         → teach patterns
  /my-dna       → your coding style
  /styleguide   → UI consistency
  config.json   → tune your setup
```

Right column (Terminal 2) stays the same: `npx agentic-loop run` with the loop flow.

### 2. Update Quick Start section (lines 57-86)

Show plan mode as the primary path:

```bash
# Terminal 1 - Plan with Claude:
claude --dangerously-skip-permissions

# 1. Use plan mode to think through your feature
#    (Claude explores codebase, you discuss, plan saved to docs/plans/)

# 2. Turn the plan into executable stories:
/prd plans/my-feature

# 3. Validate before running:
/prd-check

# Terminal 2 - Run the loop:
npx agentic-loop run
```

### 3. Update framing text (lines 50-53, 83-85)

Replace "Your loop gets smarter..." paragraph to explain the pipeline. Update the tip to reflect the plan-first workflow.

## File to modify

- `README.md` — rewrite lines 9-86 (diagram, quick start, framing)

## Verification

1. View on GitHub — ASCII diagram renders correctly
2. All commands are accurate (`/prd plans/...`, `/prd-check`, `npx agentic-loop run`)
3. No broken markdown links
4. No references to `/idea`
