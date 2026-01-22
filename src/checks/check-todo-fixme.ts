/**
 * Check for TODO/FIXME comments that indicate incomplete work
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

// Patterns to match TODO/FIXME comments
const TODO_PATTERN = /\b(TODO|FIXME|XXX|HACK|BUG|OPTIMIZE)\b[:\s]*(.*)/i;

export const checkTodoFixme: Hook = {
  id: 'todo',
  name: 'Check TODO/FIXME',
  description: 'Detect TODO, FIXME, and other incomplete work markers',
  severity: 'info',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py', 'html', 'css'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      const match = line.match(TODO_PATTERN);
      if (match) {
        const type = match[1].toUpperCase();
        const description = match[2]?.trim() || '';

        // Determine severity based on type
        let severity: 'warning' | 'info' = 'info';
        if (type === 'FIXME' || type === 'BUG') {
          severity = 'warning';
        }

        results.push({
          line: lineNum,
          column: line.indexOf(match[0]),
          message: description
            ? `${type}: ${description}`
            : `${type} marker without description`,
          severity,
          ruleId: `todo/${type.toLowerCase()}`,
        });
      }
    }

    return results;
  },
};
