/**
 * Check for empty catch blocks that silently swallow errors
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

export const checkEmptyCatch: Hook = {
  id: 'empty-catch',
  name: 'Check Empty Catch',
  description: 'Detect empty catch blocks that silently swallow errors',
  severity: 'warning',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');
    const language = getLanguage(context.extension);

    if (language === 'javascript' || language === 'typescript') {
      results.push(...checkJavaScriptCatch(lines));
    } else if (language === 'python') {
      results.push(...checkPythonCatch(lines));
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

function checkJavaScriptCatch(lines: string[]): HookResult[] {
  const results: HookResult[] = [];
  const content = lines.join('\n');

  // Pattern: catch block with empty body or just whitespace/comments
  // Matches: catch (e) { } or catch { } or catch(error) { /* comment */ }
  const catchPattern = /catch\s*\([^)]*\)\s*\{\s*(?:\/\/[^\n]*\n?\s*|\/\*[\s\S]*?\*\/\s*)?\}/g;

  let match;
  while ((match = catchPattern.exec(content)) !== null) {
    // Find line number
    const beforeMatch = content.substring(0, match.index);
    const lineNum = beforeMatch.split('\n').length;

    results.push({
      line: lineNum,
      column: 0,
      message: 'Empty catch block - handle or rethrow the error',
      severity: 'warning',
      ruleId: 'empty-catch/js',
    });
  }

  // Also check for catch without body content (single line)
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Pattern: catch (e) {} on single line
    if (/catch\s*\([^)]*\)\s*\{\s*\}/.test(line)) {
      // Avoid duplicates from the multi-line check
      if (!results.some((r) => r.line === i + 1)) {
        results.push({
          line: i + 1,
          column: line.indexOf('catch'),
          message: 'Empty catch block - handle or rethrow the error',
          severity: 'warning',
          ruleId: 'empty-catch/js',
        });
      }
    }
  }

  return results;
}

function checkPythonCatch(lines: string[]): HookResult[] {
  const results: HookResult[] = [];

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    // Look for except: or except Exception: etc.
    if (/^\s*except\s*(?:\w+(?:\s+as\s+\w+)?)?:\s*$/.test(line)) {
      // Check next non-empty line
      let nextLineIndex = i + 1;
      while (nextLineIndex < lines.length) {
        const nextLine = lines[nextLineIndex].trim();

        if (nextLine === '') {
          nextLineIndex++;
          continue;
        }

        // Check if it's just 'pass' or a comment
        if (nextLine === 'pass' || nextLine.startsWith('#')) {
          results.push({
            line: lineNum,
            column: 0,
            message: 'Empty except block - handle or reraise the exception',
            severity: 'warning',
            ruleId: 'empty-catch/py',
          });
        }

        break;
      }
    }

    // Also catch bare except: pass on same or adjacent line
    if (/except.*:\s*pass\s*$/.test(line)) {
      results.push({
        line: lineNum,
        column: line.indexOf('except'),
        message: 'Empty except block - handle or reraise the exception',
        severity: 'warning',
        ruleId: 'empty-catch/py',
      });
    }
  }

  return results;
}
