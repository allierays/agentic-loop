---
description: Rename the current terminal tab so you can tell your Claude Code tabs apart.
---

# Tab Rename

The user wants to rename the current terminal tab. This is useful when you have multiple Claude Code sessions open and every tab just shows "...skip-permissions".

> **Note:** This uses AppleScript and only works in macOS Terminal.app and iTerm2.

## Step 1: Determine the Tab Name

Check if the user provided an argument: `$ARGUMENTS`

- **If provided:** Use it as the tab name (e.g., `/tab-rename my-api` → tab name is "my-api").
- **If not provided:** Auto-detect a sensible name from the project. Read the `name` field from `package.json` if it exists, or use the current directory's basename. Then ask the user to confirm or customize:

Use AskUserQuestion:

**Question:** "What should this tab be called?"
**Header:** "Tab name"
**Options:**
- **{detected_name}** - "Auto-detected from the project"
- **Claude: {detected_name}** - "Prefixed to distinguish from Ralph's terminal"

If the user selects "Other", use their custom text as the tab name.

## Step 2: Set the Tab Title

Detect which terminal is running and set the title:

```bash
# Try Terminal.app first
osascript -e 'tell application "Terminal" to set custom title of selected tab of front window to "TAB_NAME"' 2>/dev/null
```

If that fails (not Terminal.app), try iTerm2:

```bash
osascript -e 'tell application "iTerm2" to tell current session of current window to set name to "TAB_NAME"' 2>/dev/null
```

**Important:** Escape any double quotes in the tab name before embedding in the AppleScript string.

## Step 3: Confirm

If the rename succeeded, say:

"Tab renamed to **{tab_name}**."

If both osascript commands fail, say:

"Tab renaming requires macOS Terminal.app or iTerm2. On other terminals, you can set the tab title manually with: `printf '\033]0;my-title\007'`"
