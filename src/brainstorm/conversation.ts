import type { Context } from 'telegraf';
import type { Message, BrainstormConfig, ProjectConfig } from './types.js';
import { chat, summarize, extractTitle } from './claude.js';
import { saveIdea, slugify } from './saver.js';

// Store conversation history per chat (group or DM)
const conversations = new Map<number, Message[]>();

// Store loaded context per chat (from /context command)
const conversationContexts = new Map<number, string>();

// Max history length (20 exchanges = 40 messages)
const MAX_HISTORY_LENGTH = 40;

/**
 * Set context for a conversation (from /context command)
 */
export function setConversationContext(chatId: number, context: string): void {
  conversationContexts.set(chatId, context);
}

/**
 * Get context for a conversation
 */
function getConversationContext(chatId: number): string | undefined {
  return conversationContexts.get(chatId);
}

/**
 * Get conversation history for a chat, creating if needed
 */
function getHistory(chatId: number): Message[] {
  if (!conversations.has(chatId)) {
    conversations.set(chatId, []);
  }
  return conversations.get(chatId)!;
}

/**
 * Clear conversation history for a chat
 */
export function clearConversation(chatId: number): void {
  conversations.delete(chatId);
  conversationContexts.delete(chatId);
}

/**
 * Handle incoming text messages
 */
export async function handleMessage(
  ctx: Context,
  config: BrainstormConfig,
  project: ProjectConfig | null
): Promise<void> {
  const chatId = ctx.chat?.id;
  const message = ctx.message;

  if (!chatId || !message || !('text' in message)) {
    return;
  }

  const userMessage = message.text;
  const history = getHistory(chatId);

  // Add user message to history
  history.push({ role: 'user', content: userMessage });

  // Build project context if available
  let projectContext = project
    ? `**Project:** ${project.name}\n**Description:** ${project.description || 'No description'}\n**Path:** ${project.path}`
    : undefined;

  // Add loaded context from /context command if available
  const loadedContext = getConversationContext(chatId);
  if (loadedContext && projectContext) {
    projectContext += `\n\n## Codebase Context\n${loadedContext}`;
  } else if (loadedContext) {
    projectContext = `## Codebase Context\n${loadedContext}`;
  }

  try {
    // Get response from Claude with project context
    const response = await chat(history, config.anthropic.model, projectContext);

    // Add assistant response to history
    history.push({ role: 'assistant', content: response });

    // Trim history if too long
    if (history.length > MAX_HISTORY_LENGTH) {
      history.splice(0, 2);
    }

    await ctx.reply(response);
  } catch (error) {
    console.error('Error calling Claude:', error);
    await ctx.reply('Sorry, I had trouble processing that. Please try again.');
  }
}

/**
 * Handle /save command - summarize and save the conversation
 */
export async function handleSaveCommand(
  ctx: Context,
  projectPath: string | null,
  config: BrainstormConfig
): Promise<void> {
  const chatId = ctx.chat?.id;

  if (!chatId) {
    return;
  }

  if (!projectPath) {
    await ctx.reply(
      'This group is not configured for a project. ' +
        'Add this group ID to ~/.config/ralph/brainstorm.json'
    );
    return;
  }

  const history = getHistory(chatId);

  if (history.length < 2) {
    await ctx.reply('Nothing to save yet. Start a conversation first!');
    return;
  }

  try {
    await ctx.reply('Summarizing conversation...');

    // Generate summary
    const summary = await summarize(history, config.anthropic.model);

    // Extract title and create filename
    const title = extractTitle(summary);
    const filename = slugify(title);

    // Save to project
    const filepath = saveIdea(projectPath, filename, summary);

    // Report success
    const shortSummary = summary.length > 500 ? summary.slice(0, 500) + '...' : summary;
    await ctx.reply(`✅ Saved to ${filepath}\n\n${shortSummary}`);

    // Clear conversation after saving
    clearConversation(chatId);
  } catch (error) {
    console.error('Error saving idea:', error);
    await ctx.reply('Sorry, I had trouble saving that. Please try again.');
  }
}

/**
 * Handle /clear command - clear conversation history
 */
export function handleClearCommand(ctx: Context): void {
  const chatId = ctx.chat?.id;
  if (chatId) {
    clearConversation(chatId);
    ctx.reply('Conversation cleared. Start fresh!');
  }
}

/**
 * Handle /projects command - list configured projects
 */
export function handleProjectsCommand(
  ctx: Context,
  config: BrainstormConfig
): void {
  const projects = Object.values(config.projects);

  if (projects.length === 0) {
    ctx.reply('No projects configured yet. Add them to ~/.config/ralph/brainstorm.json');
    return;
  }

  const list = projects.map((p) => `• ${p.name}: ${p.path}`).join('\n');
  ctx.reply(`Configured projects:\n${list}`);
}

/**
 * Handle /status command - show current conversation status
 */
export function handleStatusCommand(
  ctx: Context,
  projectPath: string | null,
  config: BrainstormConfig
): void {
  const chatId = ctx.chat?.id;

  if (!chatId) {
    return;
  }

  const history = getHistory(chatId);
  const project = projectPath
    ? Object.values(config.projects).find((p) => p.path === projectPath)
    : null;

  const lines = [
    `📊 **Status**`,
    `Messages: ${history.length}`,
    `Project: ${project?.name || 'Not configured'}`,
    `Model: ${config.anthropic.model}`,
  ];

  ctx.reply(lines.join('\n'));
}
