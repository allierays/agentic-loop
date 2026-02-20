# Plan: `/color` Skill — Let Users Pick Ralph's Terminal Tint

## Context

We already implemented automatic terminal background tinting in `ralph/utils.sh` and `ralph/loop.sh`. The `set_terminal_bg` function accepts a hex color argument (defaults to `#1a2e2e`). Currently the color is hardcoded — users have no way to change it. This plan adds a `/color` slash command skill that lets users pick their preferred tint color and saves it to `.ralph/config.json`.

## Files to Create/Modify

| File | Change |
|---|---|
| `.claude/skills/color/SKILL.md` | **Create** — the skill definition |
| `.claude/commands/color.md` | **Create** — command file (copy of SKILL.md, per convention) |
| `ralph/loop.sh` | **Modify** — read `terminalTint` from config and pass to `set_terminal_bg` |
| `docs/CHEATSHEET.md` | **Modify** — add `/color` to slash commands table |
| `docs/CUSTOMIZATION.md` | **Modify** — mention `/color` in the terminal tint bullet |
| `docs/RALPH.md` | **Modify** — add `terminalTint` to config reference table |

## Implementation

### Step 1: Create `.claude/skills/color/SKILL.md`

The skill follows the `/my-dna` pattern — use `AskUserQuestion` to present preset colors, then save the choice to `.ralph/config.json`.

```markdown
---
description: Pick the terminal background color Ralph uses to distinguish its terminal from Claude Code.
---

# Terminal Color

The user wants to change Ralph's terminal background tint — the color applied during `npx agentic-loop run` to visually distinguish Ralph's terminal from Claude Code.

> **Note:** This only works in macOS Terminal.app. On other terminals (iTerm2, VS Code, Linux), Ralph skips tinting automatically.

## Step 1: Show Current Color

Read `.ralph/config.json` and check for `terminalTint`. Show the current setting:
- If set: "Current tint: `{value}`"
- If not set: "Current tint: `#1a2e2e` (default dark teal)"

## Step 2: Ask Color Preference

Use AskUserQuestion:

**Question:** "What color should Ralph's terminal background be?"
**Header:** "Tint color"
**Options:**
- **Dark Teal (default)** — "`#1a2e2e` — subtle blue-green, easy on the eyes"
- **Dark Purple** — "`#1a1a2e` — cool and distinct from standard dark themes"
- **Dark Red** — "`#2e1a1a` — warm undertone, clearly different"
- **Off** — "Disable terminal tinting entirely"

If the user selects "Other", ask them to provide a hex color (e.g., `#2e2e1a`).

## Step 3: Validate (if custom hex)

If the user provided a custom hex:
- Must match `#` followed by exactly 6 hex characters (`/^#[0-9a-fA-F]{6}$/`)
- If invalid, say "That doesn't look like a valid hex color (e.g., `#1a2e2e`). Try again." and re-ask.

## Step 4: Save to Config

Read `.ralph/config.json`, set the `terminalTint` field, and write it back.

- **If a color was chosen:** Set `"terminalTint": "#xxxxxx"`
- **If "Off" was chosen:** Set `"terminalTint": "off"`

Use jq to update:
```bash
jq --arg color "THE_HEX_VALUE" '.terminalTint = $color' .ralph/config.json > .ralph/config.json.tmp && mv .ralph/config.json.tmp .ralph/config.json
```

## Step 5: Preview (macOS Terminal.app only)

If running in Terminal.app, apply the color immediately so the user can see it:

```bash
# Apply preview (will be restored when Claude session ends)
osascript -e 'tell application "Terminal" to set background color of front window to {R, G, B}' 2>/dev/null
```

Where R, G, B are the hex values converted to 16-bit (multiply each 8-bit value by 257).

If "Off" was chosen, skip the preview.

## Step 6: Confirm

Say:

"Done! Ralph will use `#xxxxxx` as the terminal tint.

Next time you run `npx agentic-loop run`, the terminal background will change to this color. It restores to your original background when the loop ends.

Run `/color` again anytime to change it."

If "Off" was chosen, say:

"Done! Terminal tinting is now disabled. Ralph will run without changing your terminal background."
```

### Step 2: Create `.claude/commands/color.md`

Identical copy of the SKILL.md (follows project convention — commands mirror skills).

### Step 3: Modify `ralph/loop.sh` (~line 642-643)

Change the hardcoded `set_terminal_bg` call to read the config value:

**Before:**
```bash
# Tint terminal background so Ralph's terminal is visually distinct
set_terminal_bg
```

**After:**
```bash
# Tint terminal background so Ralph's terminal is visually distinct
local tint_color
tint_color=$(get_config '.terminalTint' "#1a2e2e")
if [[ "$tint_color" != "off" ]]; then
  set_terminal_bg "$tint_color"
fi
```

### Step 4: Update docs

- **`docs/CHEATSHEET.md`** — Add `/color` row to Slash Commands table: `| /color | Pick Ralph's terminal background tint |`
- **`docs/CUSTOMIZATION.md`** — Update the terminal tint bullet to mention `/color`: "Run `/color` in a Claude session to pick a different tint, or disable it entirely."
- **`docs/RALPH.md`** — Add `terminalTint` to the Configuration Reference table: `| terminalTint | "#1a2e2e" | Terminal background hex color, or "off" to disable |`

## Verification

1. Run `/color` in a Claude session — should show presets and accept a choice
2. Check `.ralph/config.json` has the `terminalTint` field set
3. Run `npx agentic-loop run` — should use the configured color (not hardcoded default)
4. Run `/color` again and choose "Off" — config should show `"off"`
5. Run `npx agentic-loop run` — should NOT tint the background
