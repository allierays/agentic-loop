/**
 * TypeScript interfaces for the Telegram Brainstorm Bot
 */

export interface Message {
  role: 'user' | 'assistant';
  content: string;
}

export interface ProjectConfig {
  name: string;
  path: string;
  description?: string;
}

export interface TelegramConfig {
  allowedUserIds: string[];
}

export interface AnthropicConfig {
  model: string;
}

export interface BrainstormConfig {
  telegram: TelegramConfig;
  anthropic: AnthropicConfig;
  projects: Record<string, ProjectConfig>;
}

export interface SaveResult {
  filepath: string;
  summary: string;
  title: string;
}

export interface LoopStatus {
  isRunning: boolean;
  currentStory: string | null;
  completedStories: number;
  totalStories: number;
  lastUpdate: string;
  errors: string[];
}
