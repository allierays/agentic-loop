#!/usr/bin/env tsx
import { Telegraf } from 'telegraf';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import type { BrainstormConfig, ProjectConfig } from './types.js';
import {
  handleMessage,
  handleSaveCommand,
  handleClearCommand,
  handleProjectsCommand,
  handleStatusCommand,
  setConversationContext,
} from './conversation.js';
import { parseProgressFile, formatLoopStatus } from './loop-monitor.js';
import { getTopicContext } from './context-search.js';

// Load configuration
function loadConfig(): BrainstormConfig {
  const configPath = join(
    process.env.HOME || '',
    '.config/ralph/loopgram.json'
  );

  if (!existsSync(configPath)) {
    console.error(`Config file not found: ${configPath}`);
    console.error('Create it with your Telegram user ID and project mappings.');
    console.error('See setup instructions in the README.');
    process.exit(1);
  }

  try {
    const content = readFileSync(configPath, 'utf-8');
    return JSON.parse(content) as BrainstormConfig;
  } catch (error) {
    console.error(`Error reading config: ${error}`);
    process.exit(1);
  }
}

// Get project config for a chat ID
function getProject(
  chatId: string,
  config: BrainstormConfig
): ProjectConfig | null {
  return config.projects[chatId] || null;
}

// Get project path for a chat ID
function getProjectPath(
  chatId: string,
  config: BrainstormConfig
): string | null {
  const project = config.projects[chatId];
  return project?.path || null;
}

// Main entry point
async function main(): Promise<void> {
  // Check for bot token
  const token = process.env.TELEGRAM_BOT_TOKEN;
  if (!token) {
    console.error('TELEGRAM_BOT_TOKEN environment variable is required');
    console.error('Set it in ~/.config/ralph/secrets and source the file');
    process.exit(1);
  }

  // Check for Anthropic API key
  if (!process.env.ANTHROPIC_API_KEY) {
    console.error('ANTHROPIC_API_KEY environment variable is required');
    console.error('Set it in ~/.config/ralph/secrets and source the file');
    process.exit(1);
  }

  const config = loadConfig();
  const bot = new Telegraf(token);

  // Security middleware: only respond to allowed users
  bot.use((ctx, next) => {
    const userId = ctx.from?.id.toString();
    if (!userId || !config.telegram.allowedUserIds.includes(userId)) {
      // Silently ignore messages from unauthorized users
      return;
    }
    return next();
  });

  // Logging middleware: log unknown group IDs for easy config setup
  bot.use((ctx, next) => {
    const chatId = ctx.chat?.id.toString();
    if (chatId && !config.projects[chatId]) {
      console.log(`Unknown chat ID: ${chatId} - add to config to enable`);
    }
    return next();
  });

  // Command handlers
  bot.command('save', (ctx) => {
    const chatId = ctx.chat?.id.toString();
    const projectPath = chatId ? getProjectPath(chatId, config) : null;
    return handleSaveCommand(ctx, projectPath, config);
  });

  bot.command('clear', handleClearCommand);

  bot.command('projects', (ctx) => handleProjectsCommand(ctx, config));

  bot.command('status', (ctx) => {
    const chatId = ctx.chat?.id.toString();
    const projectPath = chatId ? getProjectPath(chatId, config) : null;
    return handleStatusCommand(ctx, projectPath, config);
  });

  bot.command('help', (ctx) => {
    ctx.reply(
      `📱 **Loopgram**\n\n` +
        `Your mobile connection to agentic-loop.\n\n` +
        `**Commands:**\n` +
        `/context <topic> - Load context about a topic from codebase\n` +
        `/loop - Check Ralph loop progress\n` +
        `/save - Save the conversation as an idea\n` +
        `/clear - Clear conversation history\n` +
        `/status - Show current session info\n` +
        `/projects - List configured projects\n` +
        `/help - Show this message`
    );
  });

  // /loop command - check Ralph loop status
  bot.command('loop', (ctx) => {
    const chatId = ctx.chat?.id.toString();
    const project = chatId ? getProject(chatId, config) : null;

    if (!project) {
      ctx.reply('This chat is not configured for a project.');
      return;
    }

    const status = parseProgressFile(project.path);
    if (!status) {
      ctx.reply(`No Ralph loop running in ${project.name}. Start one with: ralph loop`);
      return;
    }

    ctx.reply(formatLoopStatus(status, project.name));
  });

  // /context command - search codebase for a topic
  bot.command('context', async (ctx) => {
    const chatId = ctx.chat?.id.toString();
    const project = chatId ? getProject(chatId, config) : null;

    if (!project) {
      ctx.reply('This chat is not configured for a project.');
      return;
    }

    // Extract topic from command
    const text = ctx.message?.text || '';
    const topic = text.replace(/^\/context\s*/i, '').trim();

    if (!topic) {
      ctx.reply('Usage: /context <topic>\nExample: /context authentication');
      return;
    }

    await ctx.reply(`🔍 Searching ${project.name} for "${topic}"...`);

    try {
      const { summary, filesFound, searchTerms } = await getTopicContext(
        project.path,
        project.name,
        topic,
        config.anthropic.model
      );

      // Store this context for the conversation
      if (chatId) {
        setConversationContext(parseInt(chatId), summary);
      }

      let response = `🔍 Searched for: ${searchTerms.join(', ')}\n\n`;
      response += `📁 Found ${filesFound.length} files:\n`;
      response += filesFound.slice(0, 5).map(f => `• ${f}`).join('\n');
      if (filesFound.length > 5) {
        response += `\n...and ${filesFound.length - 5} more`;
      }
      response += `\n\n${summary}`;
      response += `\n\n💡 Context loaded! Now brainstorm away.`;

      await ctx.reply(response);
    } catch (error) {
      console.error('Context search error:', error);
      await ctx.reply('Error searching codebase. Check the logs.');
    }
  });

  // Handle regular text messages
  bot.on('text', (ctx) => {
    const chatId = ctx.chat?.id.toString();
    const project = chatId ? getProject(chatId, config) : null;
    return handleMessage(ctx, config, project);
  });

  // Start the bot
  console.log('📱 Loopgram starting...');
  console.log(`Model: ${config.anthropic.model}`);
  console.log(
    `Configured projects: ${Object.values(config.projects)
      .map((p) => p.name)
      .join(', ') || 'none'}`
  );
  console.log(
    `Allowed users: ${config.telegram.allowedUserIds.length} configured`
  );

  await bot.launch();
  console.log('✅ Loopgram running! Send messages in Telegram.');

  // Graceful shutdown
  process.once('SIGINT', () => {
    console.log('\nShutting down...');
    bot.stop('SIGINT');
  });
  process.once('SIGTERM', () => {
    console.log('\nShutting down...');
    bot.stop('SIGTERM');
  });
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
