# Troubleshooting

## "SessionStart: startup hook error"

Claude Code hooks are configured but the hook scripts can't be found.

```bash
npx agentic-loop setup
```

## Hooks not working after moving project

Claude Code hooks use absolute paths. After moving a project or cloning on a new machine:

```bash
npx agentic-loop setup
```

## Team members getting hook errors

`.claude/settings.json` contains machine-specific paths and should not be committed to git. The setup script automatically adds it to `.gitignore`.

If it was accidentally committed:
```bash
git rm --cached .claude/settings.json
echo ".claude/settings.json" >> .gitignore
git commit -m "Remove machine-specific settings from git"
```

## jq not installed

Claude Code hooks require `jq` for JSON manipulation.

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Fedora/RHEL
sudo dnf install jq

# Then reinstall
npx agentic-loop setup
```

## Terminal background stuck after force kill

If you `kill -9` the Ralph process, the terminal background won't restore automatically (forced kill bypasses cleanup traps). Fix it by closing and reopening the tab, or manually:

```bash
# Reset to black background
osascript -e 'tell application "Terminal" to set background color of front window to {0, 0, 0}'
```

> **Note:** The terminal tint only applies to macOS Terminal.app. iTerm2, VS Code terminal, and Linux terminals are unaffected.

## API validation failing with 422/400

These are warnings, not failures. The endpoint exists but needs parameters or authentication. Check your `.ralph/config.json` for auth settings.

## Ralph keeps retrying the same story

Check `.ralph/last_failure.txt` for the error. Common causes:
- Tests actually failing (check test output)
- Lint errors (run `npm run lint` manually)
- Missing dependencies

## Claude session times out

Increase the timeout in `.ralph/config.json`:
```json
{
  "maxSessionSeconds": 900
}
```

## Browser validation skipped

Install Playwright:
```bash
npm install playwright
npx playwright install chromium
```
