import { readFileSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';
import Anthropic from '@anthropic-ai/sdk';
import type { Message } from './types.js';

const anthropic = new Anthropic();

interface Story {
  id: string;
  title: string;
  description: string;
  acceptanceCriteria: string[];
  testSteps: string[];
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
}

interface PRD {
  feature: {
    name: string;
    description: string;
  };
  stories: Story[];
}

const PRD_PROMPT = `You are generating stories for a PRD (Product Requirements Document) that will be executed by an autonomous coding agent called Ralph.

Based on the conversation, generate 1-3 small, focused stories. Each story should be completable in a single coding session.

Output ONLY valid JSON in this exact format:
{
  "featureName": "Brief feature name",
  "featureDescription": "One sentence description",
  "stories": [
    {
      "id": "kebab-case-id",
      "title": "Short title",
      "description": "What needs to be built",
      "acceptanceCriteria": ["Criterion 1", "Criterion 2"],
      "testSteps": ["npm test", "npm run lint"]
    }
  ]
}

Rules:
- Story IDs must be unique kebab-case (e.g., "add-oauth-config")
- Keep stories small and focused
- Include realistic test commands in testSteps
- Output ONLY the JSON, no markdown or explanation`;

/**
 * Generate PRD stories from a conversation
 */
export async function generateStories(
  conversation: Message[],
  context: string | undefined,
  model: string
): Promise<{ featureName: string; featureDescription: string; stories: Story[] }> {
  let prompt = 'Generate PRD stories from this conversation:\n\n';

  if (context) {
    prompt += `## Codebase Context\n${context}\n\n`;
  }

  prompt += '## Conversation\n';
  for (const msg of conversation) {
    prompt += `${msg.role.toUpperCase()}: ${msg.content}\n\n`;
  }

  const response = await anthropic.messages.create({
    model,
    max_tokens: 2000,
    system: PRD_PROMPT,
    messages: [{ role: 'user', content: prompt }],
  });

  const text = response.content[0];
  if (text.type !== 'text') {
    throw new Error('Unexpected response type');
  }

  // Parse JSON from response (handle markdown code blocks)
  let jsonStr = text.text.trim();
  if (jsonStr.startsWith('```')) {
    jsonStr = jsonStr.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
  }

  const result = JSON.parse(jsonStr);

  return {
    featureName: result.featureName,
    featureDescription: result.featureDescription,
    stories: result.stories.map((s: any) => ({
      ...s,
      status: 'pending',
    })),
  };
}

/**
 * Append stories to existing PRD or create new one
 */
export function appendToPRD(
  projectPath: string,
  featureName: string,
  featureDescription: string,
  newStories: Story[]
): { added: number; total: number; prdPath: string } {
  const prdPath = join(projectPath, '.ralph/prd.json');

  let prd: PRD;

  if (existsSync(prdPath)) {
    // Load existing PRD
    const content = readFileSync(prdPath, 'utf-8');
    prd = JSON.parse(content);

    // Check for duplicate story IDs and make unique
    const existingIds = new Set(prd.stories.map((s) => s.id));
    for (const story of newStories) {
      let id = story.id;
      let counter = 1;
      while (existingIds.has(id)) {
        id = `${story.id}-${counter}`;
        counter++;
      }
      story.id = id;
      existingIds.add(id);
    }

    // Append new stories
    prd.stories.push(...newStories);
  } else {
    // Create new PRD
    prd = {
      feature: {
        name: featureName,
        description: featureDescription,
      },
      stories: newStories,
    };
  }

  // Write PRD
  writeFileSync(prdPath, JSON.stringify(prd, null, 2));

  return {
    added: newStories.length,
    total: prd.stories.length,
    prdPath,
  };
}

/**
 * Get current PRD status
 */
export function getPRDStatus(projectPath: string): {
  exists: boolean;
  featureName?: string;
  total: number;
  pending: number;
  completed: number;
} | null {
  const prdPath = join(projectPath, '.ralph/prd.json');

  if (!existsSync(prdPath)) {
    return { exists: false, total: 0, pending: 0, completed: 0 };
  }

  try {
    const content = readFileSync(prdPath, 'utf-8');
    const prd: PRD = JSON.parse(content);

    const pending = prd.stories.filter((s) => s.status === 'pending').length;
    const completed = prd.stories.filter((s) => s.status === 'completed').length;

    return {
      exists: true,
      featureName: prd.feature.name,
      total: prd.stories.length,
      pending,
      completed,
    };
  } catch {
    return null;
  }
}
