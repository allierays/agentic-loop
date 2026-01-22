/**
 * Check for commented-out code blocks
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

// Patterns that indicate commented-out code vs regular comments
const JS_CODE_PATTERNS = [
  /^\s*\/\/\s*(?:const|let|var|function|class|import|export|return|if|else|for|while|try|catch|switch)\b/,
  /^\s*\/\/\s*\w+\s*\([^)]*\)\s*[;{]?\s*$/,  // function calls
  /^\s*\/\/\s*\w+\s*=\s*.+[;,]?\s*$/,        // assignments
  /^\s*\/\/\s*}\s*(?:else|catch|finally)?\s*{?\s*$/,  // closing braces
  /^\s*\/\/\s*\w+\.\w+\s*\(/,                 // method calls
  /^\s*\/\*\s*(?:const|let|var|function|class|import|export)\b/,
];

const PY_CODE_PATTERNS = [
  /^\s*#\s*(?:def|class|import|from|return|if|elif|else|for|while|try|except|with|async)\b/,
  /^\s*#\s*\w+\s*=\s*.+$/,                    // assignments
  /^\s*#\s*\w+\s*\([^)]*\)\s*$/,              // function calls
  /^\s*#\s*\w+\.\w+\s*\(/,                    // method calls
];

// Minimum consecutive commented lines to report
const MIN_CONSECUTIVE_LINES = 3;

export const checkCommentedCode: Hook = {
  id: 'commented-code',
  name: 'Check Commented Code',
  description: 'Detect commented-out code blocks that should be removed',
  severity: 'info',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');
    const language = getLanguage(context.extension);
    const patterns = language === 'python' ? PY_CODE_PATTERNS : JS_CODE_PATTERNS;

    let consecutiveCodeComments = 0;
    let blockStartLine = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Check if this line looks like commented-out code
      const looksLikeCode = patterns.some((pattern) => pattern.test(line));

      if (looksLikeCode) {
        if (consecutiveCodeComments === 0) {
          blockStartLine = lineNum;
        }
        consecutiveCodeComments++;
      } else {
        // End of potential block
        if (consecutiveCodeComments >= MIN_CONSECUTIVE_LINES) {
          results.push({
            line: blockStartLine,
            column: 0,
            message: `${consecutiveCodeComments} lines of commented-out code - consider removing`,
            severity: 'info',
            ruleId: 'commented-code/block',
          });
        }
        consecutiveCodeComments = 0;
      }
    }

    // Check for block at end of file
    if (consecutiveCodeComments >= MIN_CONSECUTIVE_LINES) {
      results.push({
        line: blockStartLine,
        column: 0,
        message: `${consecutiveCodeComments} lines of commented-out code - consider removing`,
        severity: 'info',
        ruleId: 'commented-code/block',
      });
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
