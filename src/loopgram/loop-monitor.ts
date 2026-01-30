import { readFileSync, existsSync, watchFile, unwatchFile } from 'fs';
import { join } from 'path';
import type { LoopStatus } from './types.js';

// Track last known state per project to detect changes
const lastState = new Map<string, string>();

/**
 * Parse the Ralph progress file to get loop status
 * Format: [ISO-timestamp] STATUS story_id message
 * Statuses: COMPLETED, FAILED, CLI_CRASH, TIMEOUT, BLOCKED
 */
export function parseProgressFile(projectPath: string): LoopStatus | null {
  const progressPath = join(projectPath, '.ralph/progress.txt');

  if (!existsSync(progressPath)) {
    return null;
  }

  try {
    const content = readFileSync(progressPath, 'utf-8');
    const lines = content.split('\n').filter(Boolean);

    // Only look at recent lines (last 50)
    const recentLines = lines.slice(-50);

    const errors: string[] = [];
    const completedStoryIds = new Set<string>();
    let currentStory: string | null = null;
    let lastUpdate = '';
    let isRunning = false;
    let hasRalphActivity = false;

    // Ralph log format: [timestamp] STATUS story_id message
    const logPattern = /^\[([^\]]+)\]\s+(COMPLETED|FAILED|CLI_CRASH|TIMEOUT|BLOCKED)\s+(\S+)(.*)$/;

    for (const line of recentLines) {
      const match = line.match(logPattern);

      if (match) {
        hasRalphActivity = true;
        const [, timestamp, status, storyId, message] = match;
        lastUpdate = timestamp;

        if (status === 'COMPLETED') {
          completedStoryIds.add(storyId);
          if (currentStory === storyId) {
            currentStory = null;
          }
        } else if (status === 'FAILED' || status === 'CLI_CRASH' || status === 'TIMEOUT') {
          errors.push(`${status} ${storyId}${message}`.trim());
          currentStory = storyId; // Still working on this story
          isRunning = true;
        }
      }

      // Check for loop start/end markers
      if (line.includes('Loop starting') || line.includes('Starting loop')) {
        isRunning = true;
        hasRalphActivity = true;
      }
      if (line.includes('Loop complete') || line.includes('All stories done')) {
        isRunning = false;
      }

      // Try to get total stories
      const totalMatch = line.match(/(\d+)\s*(?:stories|story)/i);
      if (totalMatch) {
        // Don't overwrite with smaller numbers
      }
    }

    // If no Ralph activity found, return null
    if (!hasRalphActivity) {
      return null;
    }

    return {
      isRunning,
      currentStory,
      completedStories: completedStoryIds.size,
      totalStories: 0, // Would need to read PRD to know this
      lastUpdate,
      errors: errors.slice(-3),
    };
  } catch (error) {
    console.error('Error parsing progress file:', error);
    return null;
  }
}

/**
 * Format loop status for Telegram message
 */
export function formatLoopStatus(status: LoopStatus, projectName: string): string {
  const statusEmoji = status.isRunning ? '🔄' : '✅';
  const progress = status.totalStories > 0
    ? `${status.completedStories}/${status.totalStories}`
    : `${status.completedStories} done`;

  let message = `${statusEmoji} **${projectName}**\n`;
  message += `Progress: ${progress}\n`;

  if (status.currentStory) {
    message += `Current: ${status.currentStory}\n`;
  }

  if (status.lastUpdate) {
    message += `Updated: ${status.lastUpdate}\n`;
  }

  if (status.errors.length > 0) {
    message += `\n⚠️ Recent errors:\n`;
    for (const err of status.errors) {
      message += `• ${err.substring(0, 100)}...\n`;
    }
  }

  return message;
}

/**
 * Watch a project's progress file for changes
 */
export function watchProgress(
  projectPath: string,
  _projectName: string,
  onUpdate: (status: LoopStatus, changeType: 'started' | 'completed' | 'error' | 'update') => void
): () => void {
  const progressPath = join(projectPath, '.ralph/progress.txt');

  if (!existsSync(progressPath)) {
    return () => {}; // No-op cleanup
  }

  // Store initial state
  const initialContent = readFileSync(progressPath, 'utf-8');
  lastState.set(projectPath, initialContent);

  const checkForChanges = () => {
    try {
      const currentContent = readFileSync(progressPath, 'utf-8');
      const previousContent = lastState.get(projectPath) || '';

      if (currentContent !== previousContent) {
        lastState.set(projectPath, currentContent);

        const status = parseProgressFile(projectPath);
        if (!status) return;

        // Determine change type
        let changeType: 'started' | 'completed' | 'error' | 'update' = 'update';

        const newLines = currentContent.substring(previousContent.length);
        if (newLines.includes('✓') || newLines.includes('completed')) {
          changeType = 'completed';
        } else if (newLines.includes('✗') || newLines.includes('ERROR')) {
          changeType = 'error';
        } else if (newLines.includes('Starting') || newLines.includes('▶')) {
          changeType = 'started';
        }

        onUpdate(status, changeType);
      }
    } catch (error) {
      // File might be temporarily unavailable during write
    }
  };

  // Watch for changes
  watchFile(progressPath, { interval: 5000 }, checkForChanges);

  // Return cleanup function
  return () => {
    unwatchFile(progressPath);
    lastState.delete(projectPath);
  };
}
