/**
 * Check for debug statements that should be removed before commit
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';
import { DEBUG_PATTERNS } from '../utils/patterns.js';

export const checkDebugStatements: Hook = {
  id: 'debug',
  name: 'Check Debug Statements',
  description: 'Detect console.log, print(), debugger, and other debug statements',
  severity: 'warning',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    // Get patterns for this language
    const language = getLanguageFromExtension(context.extension);
    const patterns = DEBUG_PATTERNS[language] || [];

    if (patterns.length === 0) {
      return results;
    }

    // Track if we're inside a multi-line comment
    let inBlockComment = false;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Handle block comments for JS/TS
      if (['javascript', 'typescript'].includes(language)) {
        if (line.includes('/*') && !line.includes('*/')) {
          inBlockComment = true;
        }
        if (line.includes('*/')) {
          inBlockComment = false;
          continue;
        }
        if (inBlockComment) {
          continue;
        }
      }

      // Skip single-line comments
      if (isCommentLine(line, language)) {
        continue;
      }

      // Check each pattern
      for (const pattern of patterns) {
        const match = line.match(pattern);
        if (match) {
          const patternType = getPatternType(pattern.source, language);

          // Skip console.error and console.warn - these are often intentional
          if (patternType === 'console' && /console\.(error|warn)\s*\(/.test(line)) {
            continue;
          }

          // Skip if explicitly marked to keep
          if (line.includes('// eslint-disable') || line.includes('# noqa')) {
            continue;
          }

          results.push({
            line: lineNum,
            column: match.index || 0,
            message: getDebugMessage(patternType, language),
            severity: 'warning',
            ruleId: `debug/${patternType}`,
          });
        }
      }
    }

    return results;
  },
};

function getLanguageFromExtension(ext: string): string {
  if (['js', 'jsx', 'mjs', 'cjs'].includes(ext)) return 'javascript';
  if (['ts', 'tsx', 'mts', 'cts'].includes(ext)) return 'typescript';
  if (['py', 'pyw'].includes(ext)) return 'python';
  return 'unknown';
}

function isCommentLine(line: string, language: string): boolean {
  const trimmed = line.trim();

  if (['javascript', 'typescript'].includes(language)) {
    return trimmed.startsWith('//') || trimmed.startsWith('*');
  }

  if (language === 'python') {
    return trimmed.startsWith('#');
  }

  return false;
}

function getPatternType(patternSource: string, _language: string): string {
  if (patternSource.includes('console')) return 'console';
  if (patternSource.includes('debugger')) return 'debugger';
  if (patternSource.includes('alert')) return 'alert';
  if (patternSource.includes('print')) return 'print';
  if (patternSource.includes('breakpoint')) return 'breakpoint';
  if (patternSource.includes('pdb') || patternSource.includes('ipdb')) return 'pdb';
  return 'debug';
}

function getDebugMessage(patternType: string, _language: string): string {
  switch (patternType) {
    case 'console':
      return 'console.log() statement - remove before commit';
    case 'debugger':
      return 'debugger statement - remove before commit';
    case 'alert':
      return 'alert() statement - remove before commit';
    case 'print':
      return 'print() statement - use proper logging instead';
    case 'breakpoint':
      return 'breakpoint() - remove before commit';
    case 'pdb':
      return 'pdb debugger - remove before commit';
    default:
      return 'Debug statement - remove before commit';
  }
}
