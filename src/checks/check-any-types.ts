/**
 * Check for 'any' type usage in TypeScript
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

export const checkAnyTypes: Hook = {
  id: 'any-types',
  name: 'Check Any Types',
  description: 'Detect usage of "any" type in TypeScript',
  severity: 'warning',
  fileTypes: ['ts', 'tsx', 'mts', 'cts'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    // Track if we're in a block comment
    let inBlockComment = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Handle block comments
      if (line.includes('/*')) {
        inBlockComment = true;
      }
      if (line.includes('*/')) {
        inBlockComment = false;
        continue;
      }
      if (inBlockComment) {
        continue;
      }

      // Skip single-line comments
      if (line.trim().startsWith('//')) {
        continue;
      }

      // Remove string literals to avoid false positives
      const lineWithoutStrings = line
        .replace(/"[^"]*"/g, '""')
        .replace(/'[^']*'/g, "''")
        .replace(/`[^`]*`/g, '``');

      // Look for 'any' type annotations
      // Matches: : any, : any[], <any>, as any, etc.
      const anyPatterns = [
        /:\s*any\b/,                    // : any
        /:\s*any\s*\[/,                 // : any[]
        /:\s*any\s*\|/,                 // : any |
        /\|\s*any\b/,                   // | any
        /<\s*any\s*>/,                  // <any>
        /<\s*any\s*,/,                  // <any,
        /,\s*any\s*>/,                  // , any>
        /as\s+any\b/,                   // as any
        /:\s*Array\s*<\s*any\s*>/,      // : Array<any>
        /:\s*Record\s*<\s*[^,]+,\s*any\s*>/, // : Record<..., any>
      ];

      for (const pattern of anyPatterns) {
        const match = lineWithoutStrings.match(pattern);
        if (match) {
          // Check if it's disabled via eslint comment
          if (line.includes('eslint-disable') || line.includes('@ts-ignore')) {
            continue;
          }

          results.push({
            line: lineNum,
            column: match.index || 0,
            message: 'Avoid using "any" type - use "unknown" or a specific type instead',
            severity: 'warning',
            ruleId: 'any-types/no-any',
          });
          break; // Only report once per line
        }
      }
    }

    return results;
  },
};
