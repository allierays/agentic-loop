/**
 * Check for deeply nested code blocks
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

const MAX_NESTING_DEPTH = 4;

export const checkDeepNesting: Hook = {
  id: 'deep-nesting',
  name: 'Check Deep Nesting',
  description: 'Detect deeply nested code blocks that should be refactored',
  severity: 'warning',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const language = getLanguage(context.extension);

    if (language === 'javascript' || language === 'typescript') {
      results.push(...checkJavaScriptNesting(context.content));
    } else if (language === 'python') {
      results.push(...checkPythonNesting(context.content));
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

function checkJavaScriptNesting(content: string): HookResult[] {
  const results: HookResult[] = [];
  const lines = content.split('\n');
  const reportedLines = new Set<number>();

  let nestingDepth = 0;
  let inString = false;
  let stringChar = '';

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Skip comment-only lines
    if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
      continue;
    }

    // Track nesting by counting braces (simplified - doesn't handle all edge cases)
    for (let j = 0; j < line.length; j++) {
      const char = line[j];
      const prevChar = j > 0 ? line[j - 1] : '';

      // Handle strings
      if ((char === '"' || char === "'" || char === '`') && prevChar !== '\\') {
        if (!inString) {
          inString = true;
          stringChar = char;
        } else if (char === stringChar) {
          inString = false;
        }
        continue;
      }

      if (inString) continue;

      // Track braces
      if (char === '{') {
        nestingDepth++;

        if (nestingDepth > MAX_NESTING_DEPTH && !reportedLines.has(lineNum)) {
          reportedLines.add(lineNum);
          results.push({
            line: lineNum,
            column: j,
            message: `Nesting depth ${nestingDepth} exceeds maximum of ${MAX_NESTING_DEPTH} - consider refactoring`,
            severity: 'warning',
            ruleId: 'deep-nesting/too-deep',
          });
        }
      } else if (char === '}') {
        nestingDepth = Math.max(0, nestingDepth - 1);
      }
    }
  }

  return results;
}

function checkPythonNesting(content: string): HookResult[] {
  const results: HookResult[] = [];
  const lines = content.split('\n');
  const reportedLines = new Set<number>();

  // In Python, we track indentation-based nesting
  // Each 4 spaces or 1 tab = 1 level of nesting (approximately)
  const INDENT_SIZE = 4;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Skip empty lines and comments
    if (!line.trim() || line.trim().startsWith('#')) {
      continue;
    }

    // Count leading whitespace
    const leadingSpaces = line.match(/^(\s*)/)?.[1] || '';
    // Convert tabs to spaces for consistent counting
    const normalizedSpaces = leadingSpaces.replace(/\t/g, '    ');
    const indentLevel = Math.floor(normalizedSpaces.length / INDENT_SIZE);

    if (indentLevel > MAX_NESTING_DEPTH && !reportedLines.has(lineNum)) {
      reportedLines.add(lineNum);
      results.push({
        line: lineNum,
        column: 0,
        message: `Indentation level ${indentLevel} exceeds maximum of ${MAX_NESTING_DEPTH} - consider refactoring`,
        severity: 'warning',
        ruleId: 'deep-nesting/too-deep',
      });
    }
  }

  return results;
}
