# Claude Code Beginner's Guide

A complete guide for developers new to Claude Code - the AI coding assistant that lives in your terminal.

---

## Getting Started

### Installation

```bash
# macOS / Linux / WSL
curl -fsSL https://claude.ai/install.sh | bash

# Windows PowerShell
irm https://claude.ai/install.ps1 | iex
```

### Your First Session

```bash
# Start interactive mode
claude

# Start with a question
claude "explain this codebase"

# Run a single command and exit
claude -p "what does this function do?"
```

---

## Essential Commands

### Starting Sessions

| Command | What it does |
|---------|--------------|
| `claude` | Start interactive session |
| `claude "question"` | Start with initial prompt |
| `claude -p "query"` | Run once and exit (non-interactive) |
| `claude -c` | Resume most recent session |
| `claude -r "name"` | Resume specific session by name |
| `claude update` | Update to latest version |

### Inside Claude Code

| Command | What it does |
|---------|--------------|
| `/help` | Show built-in help |
| `/compact` | Toggle compact output mode |
| `/rename` | Rename current session |
| `/mcp` | Check MCP server status |

### Keyboard Shortcuts

| Shortcut | What it does |
|----------|--------------|
| `Ctrl+C` | Cancel current operation |
| `Ctrl+L` | Clear terminal |
| `Ctrl+R` | Search command history |
| `Ctrl+B` | Run task in background |
| `Alt+T` / `Option+T` | Toggle extended thinking |
| `Shift+Enter` | Multi-line input |

---

## The Permission System

Claude Code asks before doing anything potentially risky. Understanding permissions is key to working efficiently.

### Three Permission Types

1. **Allow** - Claude can do this without asking
2. **Ask** - Claude will prompt you before doing this
3. **Deny** - Claude cannot do this at all

### How Permissions Are Evaluated

```
1. Deny rules checked first (always win)
2. Ask rules checked second
3. Allow rules checked last
```

**Important**: A deny rule blocks an action even if an allow rule also matches.

### Permission Patterns

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Bash(git:*)",
      "Read(src/**/*.ts)"
    ],
    "ask": [
      "Write(*.env)"
    ],
    "deny": [
      "Read(./.env)",
      "Bash(rm -rf *)"
    ]
  }
}
```

**Pattern syntax:**
- `Bash` - All bash commands
- `Bash(npm run:*)` - Commands starting with "npm run"
- `Read(src/**/*.ts)` - TypeScript files in src/
- `Write(*.env)` - Any .env file

### "Dangerously Allow" Explained

When you see warnings about "dangerously allowing" something, it means you're granting broad permissions. For example:

```json
// Broad (potentially risky)
"allow": ["Bash"]

// Scoped (safer)
"allow": ["Bash(npm run:*)", "Bash(git:*)"]
```

**Best practice**: Start restrictive and expand only as needed.

---

## Plan Mode

Plan mode lets Claude analyze your codebase without making changes - perfect for understanding complex code or planning refactors.

### When to Use Plan Mode

- Exploring unfamiliar codebases
- Planning complex refactors
- Code review without risk of changes
- Understanding architecture before making decisions

### How to Use It

```bash
# Start in plan mode
claude --permission-mode plan "analyze this codebase"
```

In plan mode, Claude can:
- Read all files
- Analyze code structure
- Propose changes (but not execute them)
- Answer questions about the code

Claude cannot:
- Write or edit files
- Run shell commands
- Make any permanent changes

### Typical Workflow

1. Start in plan mode to analyze
2. Claude explores and proposes a plan
3. You review and ask questions
4. Exit plan mode when ready to implement
5. Claude executes changes with your approval

---

## CLAUDE.md - Your Project's Instructions

CLAUDE.md is a special file that tells Claude about your project. It's like onboarding documentation specifically for AI.

### Where to Put It

Place `CLAUDE.md` in your project root. Claude automatically reads it when starting a session.

### What to Include

```markdown
# Project Guide for Claude

## Overview
Brief description of what this project does.

## Tech Stack
- Runtime: Node.js 18+
- Framework: Next.js 14
- Database: PostgreSQL
- Testing: Jest + Playwright

## Conventions
- Use camelCase for variables
- Components use PascalCase
- API routes in /app/api/

## Directory Structure
- /src - Source code
- /tests - Test files
- /docs - Documentation

## Important Patterns
Describe any unique patterns in your codebase.

## Git Workflow
- Branch naming: feature/description
- Commit format: type: description
- Always run tests before committing

## Common Gotchas
Things that trip people up in this codebase.
```

### Why It Matters

Without CLAUDE.md, Claude makes generic assumptions. With it, Claude:
- Follows your team's conventions
- Understands your architecture
- Avoids patterns you don't use
- Writes code that fits your codebase

---

## Settings & Configuration

### Settings Locations (in order of precedence)

| Location | Purpose | Shared? |
|----------|---------|---------|
| `.claude/settings.local.json` | Personal project overrides | No |
| `.claude/settings.json` | Team project settings | Yes |
| `~/.claude/settings.json` | Personal global settings | No |

### Common Settings

```json
{
  "permissions": {
    "allow": ["Bash(npm:*)", "Bash(git:*)"],
    "deny": ["Read(.env)"]
  },
  "env": {
    "NODE_ENV": "development"
  },
  "model": "claude-sonnet-4-5-20250929",
  "includeCoAuthoredBy": false
}
```

### Key Settings Explained

| Setting | What it does |
|---------|--------------|
| `permissions` | Control what Claude can do |
| `env` | Environment variables for sessions |
| `model` | Which Claude model to use |
| `includeCoAuthoredBy` | Add Claude as git co-author |
| `hooks` | Automation scripts (see Hooks section) |

---

## Hooks - Automation & Guardrails

Hooks are scripts that run automatically at specific points during your session.

### Hook Events

| Event | When it fires |
|-------|---------------|
| `SessionStart` | When you start Claude |
| `PreToolUse` | Before Claude runs a tool |
| `PostToolUse` | After a tool completes |
| `UserPromptSubmit` | When you send a message |
| `Stop` | When Claude finishes responding |

### Example: Block Dangerous Commands

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/validator.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Common Hook Uses

- **Validation** - Block dangerous commands
- **Logging** - Track all tool usage
- **Context injection** - Add project info at session start
- **Quality gates** - Warn about code issues in real-time

---

## MCP Servers - External Integrations

MCP (Model Context Protocol) connects Claude to external tools and services.

### Adding an MCP Server

```bash
# HTTP server (remote services)
claude mcp add --transport http notion https://mcp.notion.com/mcp

# Stdio server (local tools)
claude mcp add --transport stdio mydb -- npx database-mcp-server
```

### Managing Servers

```bash
claude mcp list              # List all servers
claude mcp get notion        # Get server details
claude mcp remove notion     # Remove a server
```

### Check Status Inside Claude

```
/mcp
```

### Common Integrations

- **GitHub** - Access repos, issues, PRs
- **Linear/Jira** - Track work items
- **Notion** - Query documentation
- **Databases** - Query production data

---

## Working with Sessions

### Sessions Are Persistent

Claude remembers your conversation history. You can resume where you left off.

```bash
# Resume most recent session in this directory
claude -c

# Resume by session name
claude -r "auth-refactor"

# Rename current session for easy retrieval
/rename auth-refactor
```

### Session Tips

- Use `/rename` to give meaningful names to important sessions
- Sessions are stored locally
- Each directory can have its own session history

---

## Extended Thinking

Extended thinking gives Claude more "reasoning space" for complex problems.

### Toggle During Session

Press `Alt+T` (or `Option+T` on Mac) to toggle extended thinking.

### When to Use It

- Complex architectural decisions
- Multi-file refactors
- Debugging tricky issues
- Planning large features

### Enable by Default

```json
{
  "alwaysThinkingEnabled": true
}
```

---

## Tips for Beginners

### 1. Start Small

Don't ask Claude to "build an entire app." Start with specific, focused requests:

```
// Too broad
"Build me a todo app"

// Better
"Create a TodoItem component with checkbox, title, and delete button"
```

### 2. Provide Context

The more context you give, the better the results:

```
"Refactor the auth module to use OAuth.
Follow the pattern in src/services/api.ts.
Use the existing Button component for UI."
```

### 3. Iterate

Claude works best in a conversation. Ask follow-up questions, request changes, and refine.

### 4. Use Plan Mode First

For complex changes, start in plan mode to understand the scope before making changes.

### 5. Review Changes

Always review what Claude writes. Use git diff to see changes before committing.

### 6. Set Up CLAUDE.md Early

The sooner you create a good CLAUDE.md, the better Claude will understand your project.

---

## Quick Reference

### CLI Flags

| Flag | What it does |
|------|--------------|
| `-p` | Print mode (non-interactive) |
| `-c` | Continue last session |
| `-r "name"` | Resume specific session |
| `--model` | Specify model |
| `--permission-mode plan` | Read-only plan mode |
| `--debug` | Show debug output |
| `--output-format json` | JSON output for scripts |

### File Locations

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project instructions |
| `.claude/settings.json` | Project settings (shared) |
| `.claude/settings.local.json` | Personal project settings |
| `~/.claude/settings.json` | Global user settings |
| `.mcp.json` | MCP server config (shared) |
| `~/.claude.json` | Personal MCP config |

### Getting Help

- `/help` inside Claude Code
- `claude --help` in terminal
- [Official docs](https://docs.anthropic.com/en/docs/claude-code)

---

## Example Workflow

```bash
# 1. Start a session
cd my-project
claude

# 2. Explore the codebase
> "Explain the architecture of this project"

# 3. Make a change
> "Add input validation to the signup form"

# 4. Review and iterate
> "Also add email format validation"

# 5. Commit when ready
> "Create a commit for these changes"

# 6. Resume later
claude -c
```

---

## Common Issues

### "Permission denied"

Check your settings. You may need to add the tool to `allow`:

```json
{
  "permissions": {
    "allow": ["Bash(npm run:*)"]
  }
}
```

### Claude doesn't follow project conventions

Create or update your `CLAUDE.md` with clear conventions.

### Session won't resume

Make sure you're in the same directory where you started the session.

### MCP server not connecting

Run `/mcp` inside Claude to check status and authenticate.

---

## Next Steps

1. Create a `CLAUDE.md` for your project
2. Set up project-level permissions in `.claude/settings.json`
3. Try plan mode for exploring new codebases
4. Install vibe-and-thrive for enhanced workflows: `npm install vibe-and-thrive`
