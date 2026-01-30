import Anthropic from '@anthropic-ai/sdk';
import type { Message } from './types.js';

const anthropic = new Anthropic();

const BASE_SYSTEM_PROMPT = `You are a thoughtful brainstorming partner helping develop software ideas.

Your role:
- Ask clarifying questions to deeply understand the idea
- Explore edge cases and trade-offs
- Challenge assumptions constructively
- Help refine vague concepts into concrete plans
- Keep responses concise but insightful (2-4 sentences usually)

When the user says "save this" or similar:
- Summarize the key decisions made
- Format as a structured idea document
- Confirm what you're saving

Don't:
- Write code unless asked
- Be overly agreeable - push back on weak ideas
- Give long lectures - keep it conversational`;

/**
 * Build system prompt with optional project context
 */
export function buildSystemPrompt(projectContext?: string): string {
  if (!projectContext) {
    return BASE_SYSTEM_PROMPT;
  }

  return `${BASE_SYSTEM_PROMPT}

## Project Context
You are brainstorming for a specific project. Here's context about it:

${projectContext}`
}

const SUMMARY_PROMPT = `Summarize this brainstorming conversation into a structured idea document with:
- Title (short, descriptive)
- Summary (2-3 sentences)
- Key Decisions (bullet points)
- Open Questions (if any)
- Next Steps

Format as clean markdown.`;

/**
 * Send a message to Claude and get a response
 */
export async function chat(
  history: Message[],
  model: string,
  projectContext?: string
): Promise<string> {
  const response = await anthropic.messages.create({
    model,
    max_tokens: 500,
    system: buildSystemPrompt(projectContext),
    messages: history,
  });

  const content = response.content[0];
  return content.type === 'text' ? content.text : '';
}

/**
 * Generate a summary of the conversation for saving
 */
export async function summarize(
  history: Message[],
  model: string
): Promise<string> {
  const conversationText = history
    .map((m) => `${m.role.toUpperCase()}: ${m.content}`)
    .join('\n\n');

  const response = await anthropic.messages.create({
    model,
    max_tokens: 1000,
    system: SUMMARY_PROMPT,
    messages: [{ role: 'user', content: conversationText }],
  });

  const content = response.content[0];
  return content.type === 'text' ? content.text : '';
}

/**
 * Extract a title from a summary document
 */
export function extractTitle(summary: string): string {
  // Try to find a markdown heading
  const headingMatch = summary.match(/^#\s*(.+)/m);
  if (headingMatch) {
    return headingMatch[1].replace(/^Title:?\s*/i, '').trim();
  }

  // Try to find "Title:" line
  const titleMatch = summary.match(/^Title:?\s*(.+)/im);
  if (titleMatch) {
    return titleMatch[1].trim();
  }

  // Fallback to timestamp
  return `brainstorm-${Date.now()}`;
}
