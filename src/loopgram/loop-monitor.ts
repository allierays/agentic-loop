import { readFileSync, existsSync, watchFile, unwatchFile } from 'fs';
import { join } from 'path';
import type { LoopStatus } from './types.js';

// Track last known state per project to detect changes
const lastState = new Map<string, string>();

/**
 * Parse the Ralph progress file to get loop status
 */
export function parseProgressFile(projectPath: string): LoopStatus | null {
  const progressPath = join(projectPath, '.ralph/progress.txt');

  if (!existsSync(progressPath)) {
    return null;
  }

  try {
    const content = readFileSync(progressPath, 'utf-8');
    const lines = content.split('\n').filter(Boolean);

    // Parse the progress file
    // Format: timestamps and status messages
    const errors: string[] = [];
    let currentStory: string | null = null;
    let completedStories = 0;
    let totalStories = 0;
    let lastUpdate = '';
    let isRunning = false;

    for (const line of lines) {
      // Extract timestamp
      const timestampMatch = line.match(/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]/);
      if (timestampMatch) {
        lastUpdate = timestampMatch[1];
      }

      // Check for story start
      if (line.includes('Starting story:') || line.includes('▶')) {
        const storyMatch = line.match(/(?:Starting story:|▶)\s*(\S+)/);
        if (storyMatch) {
          currentStory = storyMatch[1];
          isRunning = true;
        }
      }

      // Check for story completion
      if (line.includes('✓') || line.includes('completed') || line.includes('Story complete')) {
        completedStories++;
        currentStory = null;
      }

      // Check for errors
      if (line.includes('✗') || line.includes('ERROR') || line.includes('Failed')) {
        errors.push(line.substring(0, 200)); // Truncate long errors
      }

      // Check for loop end
      if (line.includes('Loop complete') || line.includes('All stories done')) {
        isRunning = false;
      }

      // Try to get total stories from PRD load message
      const totalMatch = line.match(/(\d+)\s*(?:stories|tasks)/);
      if (totalMatch) {
        totalStories = Math.max(totalStories, parseInt(totalMatch[1]));
      }
    }

    return {
      isRunning,
      currentStory,
      completedStories,
      totalStories,
      lastUpdate,
      errors: errors.slice(-3), // Last 3 errors
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
