---
description: Rename the current terminal tab so you can tell your Claude Code tabs apart.
---

# Tab Rename

The user wants to rename the current terminal tab. This is useful when you have multiple Claude Code sessions open and every tab just shows "...skip-permissions".

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

Use `$TERM_PROGRAM` (via Bash: `echo $TERM_PROGRAM`) to detect the terminal, then apply the right method. **Important:** Escape any double quotes in the tab name before embedding in AppleScript strings.

### iTerm2 (`TERM_PROGRAM=iTerm.app`)

Use iTerm2's proprietary escape sequence — this is the most reliable method:

```bash
printf '\033]1337;SetUserVar=tab_title=%s\007' "$(echo -n 'TAB_NAME' | base64)"
```

Then also set the session name via osascript as a fallback:

```bash
osascript -e 'tell application "iTerm2" to tell current session of current window to set name to "TAB_NAME"' 2>/dev/null
```

### Terminal.app (`TERM_PROGRAM=Apple_Terminal`)

Terminal.app requires **two steps** — set the custom title AND enable the custom title display (otherwise the shell's auto-title overrides it):

```bash
osascript -e '
tell application "Terminal"
  set t to selected tab of front window
  set custom title of t to "TAB_NAME"
end tell' 2>/dev/null
```

Then use the ANSI escape to set the window/tab title (this is what actually sticks):

```bash
printf '\033]0;TAB_NAME\007'
```

### Other terminals / fallback

Use the standard ANSI escape sequence:

```bash
printf '\033]0;TAB_NAME\007'
```

## Step 3: Confirm

If the rename succeeded, say:

"Tab renamed to **{tab_name}**."

> **Tip:** If your shell resets the title on each prompt (common with oh-my-zsh), add `export DISABLE_AUTO_TITLE="true"` to your `~/.zshrc`, then restart your shell.
