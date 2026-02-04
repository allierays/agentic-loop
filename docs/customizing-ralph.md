# Customizing Ralph

Ralph ships with built-in quality checks, but every project is different. This guide covers the tools you have to teach Ralph how *your* project works.

---

## The basics: /idea vs /prd vs prd.json

These three things work together. Here's when to use each.

### /idea — when you're still figuring it out

Run `/idea` when you have a rough concept but haven't nailed down the details. Ralph will ask you questions — what's in scope, what's not, how it should work — and write up a structured idea file in `docs/ideas/`. Think of it as a brainstorming session with a note-taker.

Once you approve the idea, Ralph offers to turn it into a PRD automatically.

**Use /idea when:** you're starting from scratch and want help thinking it through.

### /prd — when you know what you want built

Run `/prd` when you already have a clear picture of the feature. You can point it at an idea file (`/prd my-feature`) or just describe what you want (`/prd Add user authentication with email and password`).

Ralph splits your feature into small, ordered stories that it can execute one at a time. Each story gets its own test steps, acceptance criteria, and file list.

**Use /prd when:** you're ready to generate work for Ralph to execute.

### prd.json — the execution plan

This is the file Ralph actually reads when it runs. It lives at `.ralph/prd.json` and contains your stories in order. You don't usually edit this by hand — `/idea` and `/prd` generate it for you — but you can if you need to.

Each story in the PRD has:
- **testSteps** — shell commands Ralph runs to verify the work (curl, npm test, pytest, etc.)
- **acceptanceCriteria** — what "done" means for this story
- **files** — which files to create or modify
- **type** — backend, frontend, or general

Ralph works through stories one at a time, top to bottom, and marks each one as passed when its test steps succeed.

---

## Signs — teaching Ralph from experience

Signs are short rules that Ralph remembers across every story. When something goes wrong (or you notice a pattern Ralph keeps missing), add a sign so it doesn't happen again.

**Add a sign from the command line:**

```bash
ralph sign 'Always use bcrypt cost 10+ for passwords' backend
ralph sign 'Never hardcode API URLs — use environment variables' general
ralph sign 'Add data-testid attributes for Playwright selectors' frontend
```

**Or use the /sign command** inside a Claude session.

**List your signs:**

```bash
ralph signs
```

**Remove a sign:**

```bash
ralph unsign sign-001
ralph unsign 'bcrypt'   # matches by keyword
```

Signs are stored in `.ralph/signs.json`. Ralph injects them into Claude's context before every story, so they act like project-wide coding standards that Ralph follows automatically.

Ralph can also learn signs on its own. When a story fails and Ralph figures out why, it may auto-promote a pattern as a new sign. These show up in `.ralph/suggested-signs.txt` first.

**When to add a sign:** whenever you find yourself correcting the same mistake twice.

---

## Custom PRD checks — your own validation rules

Ralph validates every PRD before it starts working. The built-in checks catch common problems (missing test steps, no API contract, prose instead of commands). But you can add your own.

### How it works

Drop an executable script into `.ralph/checks/prd/` and Ralph will run it against every story during validation.

Your script receives:
- **stdin** — the story as JSON
- **$1** — the story ID
- **$2** — the path to the PRD file

If something's wrong, print the issue to stdout (one line per issue). If everything's fine, print nothing.

### Example

Create `.ralph/checks/prd/check-description.sh`:

```bash
#!/usr/bin/env bash
story_json=$(cat)

has_description=$(echo "$story_json" | jq -r '.description // empty')
if [[ -z "$has_description" ]]; then
  echo "missing description field"
fi
```

Make it executable:

```bash
chmod +x .ralph/checks/prd/check-description.sh
```

That's it. Next time Ralph validates a PRD, it'll flag any story without a description.

### More examples

**Require a specific field for backend stories:**

```bash
#!/usr/bin/env bash
story_json=$(cat)
story_type=$(echo "$story_json" | jq -r '.type // "unknown"')

if [[ "$story_type" == "backend" ]]; then
  has_rate_limit=$(echo "$story_json" | jq -r '.acceptanceCriteria // [] | join(" ")')
  if ! echo "$has_rate_limit" | grep -qi "rate.limit"; then
    echo "backend story missing rate limiting criteria"
  fi
fi
```

**Enforce a naming convention:**

```bash
#!/usr/bin/env bash
story_json=$(cat)
story_id="$1"

if ! echo "$story_id" | grep -qE '^TASK-[0-9]+$'; then
  echo "story ID must match TASK-NNN format"
fi
```

### Tips

- Scripts must be named `check-*` (e.g., `check-security.sh`, `check-naming.sh`)
- Put project-specific checks in `.ralph/checks/prd/`
- Put personal checks you want everywhere in `~/.config/ralph/checks/prd/`
- Disable a check without deleting it by adding to `.ralph/config.json`:
  ```json
  {"checks": {"custom": {"check-description": false}}}
  ```
- Custom check issues are reported but not auto-fixed — they're for rules only you understand

---

## Quick reference

| What | When to use | What it produces |
|------|------------|-----------------|
| `/idea` | Brainstorming a new feature | `docs/ideas/feature.md` |
| `/prd` | Ready to generate executable stories | `.ralph/prd.json` |
| `ralph sign` | Ralph keeps making the same mistake | `.ralph/signs.json` entry |
| Custom checks | Your project has rules Ralph doesn't know about | Validation warnings in PRD check |
