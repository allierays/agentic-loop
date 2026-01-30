# Loopgram

**Your mobile connection to agentic-loop.** Brainstorm ideas, monitor Ralph loops, and search your codebase - all from Telegram.

## Features

- **Smart Context Search**: `/context <topic>` searches your codebase and summarizes what exists
- **Loop Monitoring**: `/loop` checks the status of running Ralph loops
- **Idea Capture**: `/save` summarizes conversations and saves to `docs/ideas/`
- **Multi-Project Support**: One bot, multiple Telegram groups - each maps to a different project

## Setup

### 1. Create Telegram Bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram
2. Send `/newbot` and follow prompts
3. Copy the bot token

### 2. Get Your User ID

1. Message [@userinfobot](https://t.me/userinfobot) on Telegram
2. Copy your user ID number

### 3. Configure Secrets

```bash
mkdir -p ~/.config/ralph

cat > ~/.config/ralph/secrets << 'EOF'
export TELEGRAM_BOT_TOKEN="your-bot-token"
export ANTHROPIC_API_KEY="your-anthropic-key"
EOF

chmod 600 ~/.config/ralph/secrets
```

### 4. Configure Projects

Create `~/.config/ralph/loopgram.json`:

```json
{
  "telegram": {
    "allowedUserIds": ["YOUR_USER_ID"]
  },
  "anthropic": {
    "model": "claude-opus-4-20250514"
  },
  "projects": {}
}
```

### 5. Start Loopgram

```bash
source ~/.config/ralph/secrets
npm run loopgram
```

### 6. Add Projects

1. Create a Telegram group for each project (e.g., "My Project Ideas")
2. Add your bot to the group
3. Send a message - the bot logs the group ID
4. Add the group to your config:

```json
{
  "projects": {
    "-1001234567890": {
      "name": "my-project",
      "path": "/path/to/my-project",
      "description": "Brief description of what this project does"
    }
  }
}
```

5. Restart the bot

## Commands

| Command | Description |
|---------|-------------|
| `/context <topic>` | Search codebase for topic, load context for brainstorming |
| `/loop` | Check Ralph loop progress for this project |
| `/save` | Summarize conversation and save to `docs/ideas/` |
| `/clear` | Clear conversation history |
| `/status` | Show current session info |
| `/projects` | List configured projects |
| `/help` | Show help message |

## Workflow

```
Telegram                    Your Mac                     Claude Code
────────────────────────────────────────────────────────────────────

/context authentication
    │
    ▼
Loopgram searches ────────► Found: auth.py, login.ts...
    │
    ▼
"I want to add OAuth"
    │
    ▼
Loopgram brainstorms
with codebase context
    │
    ▼
/save
    │
    ▼
Saved to docs/ideas/oauth.md ──────────────────────────► /prd docs/ideas/oauth.md
                                                              │
                                                              ▼
                                                         Ralph executes
```

## Cost

- **Telegram**: Free
- **Claude Opus**: ~$0.25 per deep conversation
- **Hosting**: Free (runs on your Mac)

Estimated: ~$7.50/month for daily use.

## Running in Background

```bash
# Start in background
npm run loopgram:bg

# Check logs
tail -f .ralph/loopgram.log

# Stop
pkill -f "loopgram/index.ts"
```

## Tips

- Use single keywords for `/context` searches (e.g., `/context auth` not `/context authentication system`)
- The bot generates smart search terms automatically
- Context is preserved until you `/clear` or `/save`
- Ideas saved to `docs/ideas/` can be converted to PRDs with `/prd`
