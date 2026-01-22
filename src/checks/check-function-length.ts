/**
 * Check for functions that are too long
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

const MAX_FUNCTION_LENGTH = 150; // lines

export const checkFunctionLength: Hook = {
  id: 'function-length',
  name: 'Check Function Length',
  description: 'Detect functions that are too long and should be refactored',
  severity: 'warning',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const language = getLanguage(context.extension);

    if (language === 'javascript' || language === 'typescript') {
      results.push(...checkJavaScriptFunctions(context.content));
    } else if (language === 'python') {
      results.push(...checkPythonFunctions(context.content));
    }

    return results;
  },
};

function getLanguage(ext: string): string {
  if (['js', 'jsx', 'mjs', 'cjs'].includes(ext)) return 'javascript';
  if (['ts', 'tsx', 'mts', 'cts'].includes(ext)) return 'typescript';
  if (['py', 'pyw'].includes(ext)) return 'python';
  return 'unknown';
}

function checkJavaScriptFunctions(content: string): HookResult[] {
  const results: HookResult[] = [];
  const lines = content.split('\n');

  // Track function declarations
  const functionStarts: Array<{ line: number; name: string; braceCount: number }> = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Detect function starts
    // - function name()
    // - const name = function
    // - const name = () =>
    // - async function name()
    // - method() { or method = () =>
    const funcMatch = line.match(
      /(?:(?:async\s+)?function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\(?|(\w+)\s*(?:=\s*(?:async\s*)?\(|[:(]\s*\)\s*(?:=>|{)))/
    );

    if (funcMatch) {
      const name = funcMatch[1] || funcMatch[2] || funcMatch[3] || 'anonymous';

      // Count opening braces on this line
      const openBraces = (line.match(/\{/g) || []).length;
      const closeBraces = (line.match(/\}/g) || []).length;

      if (openBraces > 0) {
        functionStarts.push({
          line: lineNum,
          name,
          braceCount: openBraces - closeBraces,
        });
      }
    } else {
      // Update brace counts for tracked functions
      const openBraces = (line.match(/\{/g) || []).length;
      const closeBraces = (line.match(/\}/g) || []).length;

      for (let j = functionStarts.length - 1; j >= 0; j--) {
        functionStarts[j].braceCount += openBraces - closeBraces;

        // Function ended
        if (functionStarts[j].braceCount <= 0) {
          const func = functionStarts[j];
          const length = lineNum - func.line + 1;

          if (length > MAX_FUNCTION_LENGTH) {
            results.push({
              line: func.line,
              column: 0,
              message: `Function "${func.name}" is ${length} lines (max: ${MAX_FUNCTION_LENGTH}) - consider refactoring`,
              severity: 'warning',
              ruleId: 'function-length/too-long',
            });
          }

          functionStarts.splice(j, 1);
        }
      }
    }
  }

  return results;
}

function checkPythonFunctions(content: string): HookResult[] {
  const results: HookResult[] = [];
  const lines = content.split('\n');

  // Track function definitions by indentation
  const functionStarts: Array<{ line: number; name: string; indent: number }> = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Detect function definition
    const funcMatch = line.match(/^(\s*)(?:async\s+)?def\s+(\w+)\s*\(/);

    if (funcMatch) {
      const indent = funcMatch[1].length;
      const name = funcMatch[2];

      // Close any functions with same or greater indentation
      while (
        functionStarts.length > 0 &&
        functionStarts[functionStarts.length - 1].indent >= indent
      ) {
        const func = functionStarts.pop()!;
        const length = lineNum - func.line;

        if (length > MAX_FUNCTION_LENGTH) {
          results.push({
            line: func.line,
            column: 0,
            message: `Function "${func.name}" is ${length} lines (max: ${MAX_FUNCTION_LENGTH}) - consider refactoring`,
            severity: 'warning',
            ruleId: 'function-length/too-long',
          });
        }
      }

      functionStarts.push({ line: lineNum, name, indent });
    } else if (line.trim() && !line.trim().startsWith('#')) {
      // Non-empty, non-comment line - check indentation to close functions
      const indent = line.match(/^(\s*)/)?.[1].length || 0;

      while (
        functionStarts.length > 0 &&
        indent <= functionStarts[functionStarts.length - 1].indent &&
        !line.trim().startsWith('@') // decorators don't close functions
      ) {
        const func = functionStarts.pop()!;
        const length = i - func.line; // Previous line was the end

        if (length > MAX_FUNCTION_LENGTH) {
          results.push({
            line: func.line,
            column: 0,
            message: `Function "${func.name}" is ${length} lines (max: ${MAX_FUNCTION_LENGTH}) - consider refactoring`,
            severity: 'warning',
            ruleId: 'function-length/too-long',
          });
        }
      }
    }
  }

  // Close remaining functions at EOF
  for (const func of functionStarts) {
    const length = lines.length - func.line + 1;

    if (length > MAX_FUNCTION_LENGTH) {
      results.push({
        line: func.line,
        column: 0,
        message: `Function "${func.name}" is ${length} lines (max: ${MAX_FUNCTION_LENGTH}) - consider refactoring`,
        severity: 'warning',
        ruleId: 'function-length/too-long',
      });
    }
  }

  return results;
}
