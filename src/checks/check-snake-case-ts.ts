/**
 * Check for snake_case property names in TypeScript interfaces/types
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

export const checkSnakeCaseTs: Hook = {
  id: 'snake-case',
  name: 'Check Snake Case',
  description: 'Detect snake_case properties in TypeScript that should be camelCase',
  severity: 'warning',
  fileTypes: ['ts', 'tsx', 'mts', 'cts'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    // Track if we're inside an interface or type definition
    let inInterfaceOrType = false;
    let braceDepth = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comments
      if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
        continue;
      }

      // Detect interface or type start
      if (/^\s*(?:export\s+)?(?:interface|type)\s+\w+/.test(line)) {
        inInterfaceOrType = true;
        braceDepth = 0;
      }

      // Track brace depth
      const openBraces = (line.match(/\{/g) || []).length;
      const closeBraces = (line.match(/\}/g) || []).length;

      if (inInterfaceOrType) {
        braceDepth += openBraces - closeBraces;

        // Check for snake_case properties
        // Match property names in interface/type definitions
        const propertyMatch = line.match(/^\s*['"]?([a-z][a-z0-9]*(?:_[a-z0-9]+)+)['"]?\s*[?]?\s*:/);

        if (propertyMatch) {
          const propertyName = propertyMatch[1];
          const suggestedName = toCamelCase(propertyName);

          results.push({
            line: lineNum,
            column: line.indexOf(propertyName),
            message: `Property "${propertyName}" uses snake_case - consider using camelCase "${suggestedName}"`,
            severity: 'warning',
            ruleId: 'snake-case/property',
            fix: suggestedName,
          });
        }

        // End of interface/type
        if (braceDepth <= 0 && closeBraces > 0) {
          inInterfaceOrType = false;
        }
      }

      // Also check for snake_case in object destructuring from API responses
      // This is a common issue when copying from API response types
      const destructMatch = line.match(/const\s*\{\s*([^}]+)\s*\}\s*=/);
      if (destructMatch) {
        const props = destructMatch[1].split(',');
        for (const prop of props) {
          const propName = prop.trim().split(':')[0].trim();
          if (/^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/.test(propName)) {
            results.push({
              line: lineNum,
              column: line.indexOf(propName),
              message: `Destructured property "${propName}" uses snake_case - API response may need transformation`,
              severity: 'info',
              ruleId: 'snake-case/destructure',
            });
          }
        }
      }

      // Check for snake_case property access (e.g., data.user_name, response.created_at)
      // This catches direct usage of snake_case from API responses without transformation
      const propertyAccessRegex = /\.([a-z][a-z0-9]*(?:_[a-z0-9]+)+)(?:\s*[,;)\]}]|\s*$|\s*\.|\s*\?\.|\s*!\.|\s*&&|\s*\|\||\s*\?|\s*:|\s*===|\s*!==|\s*==|\s*!=)/g;
      let accessMatch;
      while ((accessMatch = propertyAccessRegex.exec(line)) !== null) {
        const propName = accessMatch[1];
        const suggestedName = toCamelCase(propName);

        // Skip if it's in a comment
        const beforeMatch = line.substring(0, accessMatch.index);
        if (beforeMatch.includes('//') || beforeMatch.includes('/*')) {
          continue;
        }

        // Skip common exceptions (CSS properties, external library patterns)
        if (['line_number', 'column_number', 'stack_trace'].includes(propName)) {
          continue;
        }

        results.push({
          line: lineNum,
          column: accessMatch.index + 1,
          message: `Property access ".${propName}" uses snake_case - transform API response to camelCase ".${suggestedName}"`,
          severity: 'warning',
          ruleId: 'snake-case/access',
          fix: suggestedName,
        });
      }
    }

    return results;
  },
};

function toCamelCase(snakeCase: string): string {
  return snakeCase.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
}
