---
description: Take an interactive tour of vibe-and-thrive - the system for going from idea to shipped code with AI.
---

# Vibe & Thrive Tour

## Step 1: Check & Fix Setup

Print this exactly:

```
  ╦  ╦╦╔╗ ╔═╗   ┬   ╔╦╗╦ ╦╦═╗╦╦  ╦╔═╗
  ╚╗╔╝║╠╩╗║╣   ┌┼─   ║ ╠═╣╠╦╝║╚╗╔╝║╣
   ╚╝ ╩╚═╝╚═╝  └┘    ╩ ╩ ╩╩╚═╩ ╚╝ ╚═╝

  Checking setup...
```

**Check each item and FIX if missing:**

1. **Check jq installed:**
   ```bash
   command -v jq
   ```
   - If missing: Say "⚠️ jq not found. Install it: `brew install jq` (macOS) or `apt install jq` (Linux)"
   - If found: ✓ jq installed

2. **Check slash commands:**
   ```bash
   test -d .claude/commands && ls .claude/commands/*.md 2>/dev/null | wc -l
   ```
   - If missing or count is 0: Copy from node_modules:
     ```bash
     mkdir -p .claude/commands && cp -r node_modules/vibe-and-thrive/.claude/commands/* .claude/commands/
     ```
   - Then: ✓ Slash commands installed

3. **Check Ralph initialized:**
   ```bash
   test -f .ralph/config.json
   ```
   - If missing: Run `npx ralph init`
   - Then: ✓ Ralph initialized

4. **Check CLAUDE.md:**
   ```bash
   test -f CLAUDE.md
   ```
   - If missing: Create a basic one:
     ```bash
     echo "# Project Guide for Claude" > CLAUDE.md
     ```
   - Then: ✓ CLAUDE.md created

5. **Check Docker:**
   ```bash
   test -f docker-compose.yml || test -f docker-compose.yaml || test -f compose.yml
   ```
   - If found:
     - Update config: `jq '.docker.enabled = true' .ralph/config.json > .ralph/config.tmp && mv .ralph/config.tmp .ralph/config.json`
     - Say: "✓ Docker detected - Ralph will run commands inside containers"
     - **Skip Playwright check** (browser verification uses curl in Docker mode)

6. **Check & Install Playwright (if not Docker):**

   Check BOTH the npm package AND browser binaries:
   ```bash
   # Check npm package
   npm list playwright 2>/dev/null

   # Check browser binaries exist (macOS or Linux path)
   ls ~/Library/Caches/ms-playwright/chromium-* 2>/dev/null || ls ~/.cache/ms-playwright/chromium-* 2>/dev/null
   ```

   - If BOTH exist: Say "✓ Playwright available"
   - If either is missing:
     Say: "Installing Playwright for browser verification (~150MB)..."
     ```bash
     npm install playwright && npx playwright install chromium
     ```
     - If successful: Say "✓ Playwright installed"
     - If failed: Say "⚠️ Playwright installation failed. Browser verification will use basic HTTP checks. You can try manually: `npm install playwright && npx playwright install chromium`"

Say: "Setup verified! Let me configure Ralph for your project..."

---

## Step 2: Auto-Configure Ralph

**Auto-detect and configure project settings:**

### 2a. Detect Project Structure

Check these directories and set `paths` in config:

```bash
# Check what exists
test -d frontend && echo "frontend exists"
test -d client && echo "client exists"
test -d backend && echo "backend exists"
test -d core && echo "core exists"
test -d src && echo "src exists"
```

Based on results, update config:
- `frontend/` exists → set `paths.frontend` to `"frontend"`
- `client/` exists → set `paths.frontend` to `"client"`
- `backend/` exists → set `paths.backend` to `"backend"`
- `core/` exists → set `paths.backend` to `"core"`
- Only `src/` exists → set `paths.frontend` to `"."`

### 2b. Detect URLs

Check `.env`, `.env.example`, or `docker-compose.yml` for port numbers:

```bash
grep -h "PORT\|URL\|localhost" .env .env.example docker-compose.yml 2>/dev/null | head -5
```

Also check `package.json` for port in dev script:
```bash
cat package.json 2>/dev/null | jq -r '.scripts.dev // empty'
```

Set URLs based on findings (defaults: frontend=3000, backend=8000):
```bash
jq '.urls.frontend = "http://localhost:3000" | .urls.backend = "http://localhost:8000"' .ralph/config.json > .ralph/config.tmp && mv .ralph/config.tmp .ralph/config.json
```

### 2c. Detect Commands

Read package.json scripts and update config:

```bash
# Get scripts from package.json (check root and frontend/)
cat package.json 2>/dev/null | jq -r '.scripts | to_entries[] | "\(.key): \(.value)"' | head -10
```

Update config with detected commands:
```bash
# Example: if package.json has "dev": "next dev"
jq '.commands.dev = "npm run dev"' .ralph/config.json > .ralph/config.tmp && mv .ralph/config.tmp .ralph/config.json
```

For fullstack projects with separate frontend:
```bash
jq '.commands.dev = "cd frontend && npm run dev"' .ralph/config.json > .ralph/config.tmp && mv .ralph/config.tmp .ralph/config.json
```

### 2d. Detect Test Framework

```bash
test -f playwright.config.ts && echo "playwright"
test -f vitest.config.ts && echo "vitest"
test -f jest.config.js && echo "jest"
```

Update config:
```bash
# If playwright found
jq '.playwright.enabled = true' .ralph/config.json > .ralph/config.tmp && mv .ralph/config.tmp .ralph/config.json

# If vitest/jest found
jq '.checks.test = "npm test"' .ralph/config.json > .ralph/config.tmp && mv .ralph/config.tmp .ralph/config.json
```

### 2e. Show Results

After updating, read the config and show user:

```bash
cat .ralph/config.json | jq '{paths, urls, commands, checks}'
```

Say: "I've auto-configured Ralph:

[Show the detected settings in a nice format]

Edit `.ralph/config.json` if anything needs adjusting."

### 2f. Test Credentials (Optional)

```bash
cat .ralph/config.json | jq -r '.auth.testUser // empty'
```

**If empty**, use AskUserQuestion:
- **Question:** "Add test credentials? Ralph needs these for authenticated endpoints."
- **Header:** "Test auth"
- **Options:**
  - **Yes** - "I'll ask for email and password"
  - **Skip** - "Edit .ralph/config.json later"

If "Yes":
- Ask for email, then password
- Update config:
  ```bash
  jq --arg u "$EMAIL" --arg p "$PASSWORD" '.auth.testUser = $u | .auth.testPassword = $p' .ralph/config.json > .ralph/config.tmp && mv .ralph/config.tmp .ralph/config.json
  ```
- Say: "✓ Test credentials saved"

If "Skip":
- Say: "No problem! Add credentials to `.ralph/config.json` when needed."

**If already set:**
- Say: "✓ Test credentials configured"

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
  /idea [feature]       Brainstorm → PRD
  npx ralph run         Execute autonomously
  npx ralph status      Check progress
  npx ralph stop        Stop after current story

Quality:
  /vibe-check           Audit code quality
  /review               Review changes
  npx ralph check       Run verification

Other:
  /my-dna               Set preferences
  /explain              Understand code
  /styleguide           Generate design system
  /vibe-help            Full cheatsheet
```

Say: "You're all set! Run `/idea [your next feature]` to get started."
