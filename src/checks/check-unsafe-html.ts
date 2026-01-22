/**
 * Check for unsafe HTML/DOM manipulation that could lead to XSS
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

export const checkUnsafeHtml: Hook = {
  id: 'unsafe-html',
  name: 'Check Unsafe HTML',
  description: 'Detect unsafe innerHTML/DOM manipulation that could lead to XSS',
  severity: 'error',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'html'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comments
      if (line.trim().startsWith('//') || line.trim().startsWith('*')) {
        continue;
      }

      // Check for innerHTML assignment
      if (/\.innerHTML\s*=/.test(line)) {
        // Check if it's a static string (less dangerous)
        const isStaticString = /\.innerHTML\s*=\s*['"`][^'"`]*['"`]\s*;?\s*$/.test(line);

        if (!isStaticString) {
          results.push({
            line: lineNum,
            column: line.indexOf('innerHTML'),
            message: 'Unsafe innerHTML assignment - use textContent or sanitize input',
            severity: 'error',
            ruleId: 'unsafe-html/innerHTML',
          });
        }
      }

      // Check for outerHTML assignment
      if (/\.outerHTML\s*=/.test(line)) {
        results.push({
          line: lineNum,
          column: line.indexOf('outerHTML'),
          message: 'Unsafe outerHTML assignment - consider safer alternatives',
          severity: 'error',
          ruleId: 'unsafe-html/outerHTML',
        });
      }

      // Check for document.write
      if (/document\.write\s*\(/.test(line)) {
        results.push({
          line: lineNum,
          column: line.indexOf('document.write'),
          message: 'document.write() is unsafe - use DOM manipulation instead',
          severity: 'error',
          ruleId: 'unsafe-html/document-write',
        });
      }

      // Check for insertAdjacentHTML with non-static content
      if (/\.insertAdjacentHTML\s*\([^,]+,/.test(line)) {
        const isStaticString = /\.insertAdjacentHTML\s*\([^,]+,\s*['"`][^'"`]*['"`]\s*\)/.test(line);

        if (!isStaticString) {
          results.push({
            line: lineNum,
            column: line.indexOf('insertAdjacentHTML'),
            message: 'Unsafe insertAdjacentHTML - sanitize input before insertion',
            severity: 'warning',
            ruleId: 'unsafe-html/insertAdjacentHTML',
          });
        }
      }

      // Check for dangerouslySetInnerHTML in React
      if (/dangerouslySetInnerHTML\s*=/.test(line)) {
        results.push({
          line: lineNum,
          column: line.indexOf('dangerouslySetInnerHTML'),
          message: 'dangerouslySetInnerHTML requires careful sanitization',
          severity: 'warning',
          ruleId: 'unsafe-html/react-dangerously',
        });
      }

      // Check for eval
      if (/\beval\s*\(/.test(line)) {
        results.push({
          line: lineNum,
          column: line.indexOf('eval'),
          message: 'eval() is unsafe - avoid using eval with dynamic content',
          severity: 'error',
          ruleId: 'unsafe-html/eval',
        });
      }

      // Check for Function constructor with dynamic content
      if (/new\s+Function\s*\(/.test(line)) {
        results.push({
          line: lineNum,
          column: line.indexOf('Function'),
          message: 'new Function() with dynamic content is similar to eval()',
          severity: 'warning',
          ruleId: 'unsafe-html/function-constructor',
        });
      }
    }

    return results;
  },
};
