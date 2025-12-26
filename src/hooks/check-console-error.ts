/**
 * Check for console.error usage that might need proper error handling
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

export const checkConsoleError: Hook = {
  id: 'console-error',
  name: 'Check Console Error',
  description: 'Detect console.error that might need proper error handling',
  severity: 'info',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comment lines
      if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
        continue;
      }

      // Look for console.error
      const match = line.match(/console\.error\s*\(/);
      if (match) {
        // Check if it's in a catch block (look at nearby lines)
        const nearbyLines = lines.slice(Math.max(0, i - 5), i + 1).join('\n');
        const inCatchBlock = /catch\s*\([^)]*\)\s*\{/.test(nearbyLines);

        if (inCatchBlock) {
          // In a catch block - suggest proper error handling
          results.push({
            line: lineNum,
            column: match.index || 0,
            message: 'console.error in catch block - consider using a logging service or rethrowing',
            severity: 'info',
            ruleId: 'console-error/in-catch',
          });
        }
      }
    }

    return results;
  },
};
