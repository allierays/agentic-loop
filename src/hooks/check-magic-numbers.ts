/**
 * Check for magic numbers that should be named constants
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

// Numbers that are commonly acceptable and don't need constants
const ACCEPTABLE_NUMBERS = new Set([
  -1, 0, 1, 2, 10, 100, 1000,
  // Common time values
  60, 1000, 3600, 86400,
  // Array/string indices
  0, 1, 2,
]);

// Contexts where magic numbers are acceptable
const ACCEPTABLE_CONTEXTS = [
  /\.length\s*[<>=!]/,           // array length comparisons
  /\[\s*\d+\s*\]/,               // array indexing
  /slice\s*\(\s*\d+/,            // slice operations
  /substring\s*\(\s*\d+/,        // substring operations
  /repeat\s*\(\s*\d+/,           // repeat operations
  /^\s*(?:return|throw)\s+\d+/,  // return/throw numeric values
  /port\s*[:=]/i,                // port numbers
  /\.toFixed\s*\(\s*\d+/,        // decimal places
  /Math\./,                      // Math operations
  /parseInt|parseFloat/,         // parsing functions
  /0x[0-9a-fA-F]+/,             // hex numbers (color codes, etc.)
  /rgba?\s*\(/,                  // CSS colors
  /version/i,                    // version numbers
  /new Date\(/,                  // date constructors
  /setTimeout|setInterval/,      // timer functions (often have inline ms)
  /padding|margin|width|height/i, // CSS-related
];

// Paths that indicate frontend component files (skip these)
const FRONTEND_PATH_PATTERNS = [
  /\/components\//i,
  /\/pages\//i,
  /\/views\//i,
  /\/layouts\//i,
  /\/ui\//i,
  /\.styled\./i,
  /\.styles\./i,
];

export const checkMagicNumbers: Hook = {
  id: 'magic-numbers',
  name: 'Check Magic Numbers',
  description: 'Detect magic numbers that should be named constants',
  severity: 'warning',
  // Skip JSX/TSX - too many false positives with CSS values
  fileTypes: ['js', 'ts', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];

    // Skip frontend component files even if they're .js/.ts
    if (FRONTEND_PATH_PATTERNS.some((pattern) => pattern.test(context.filePath))) {
      return results;
    }

    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comments
      if (isCommentLine(line, context.extension)) {
        continue;
      }

      // Skip constant/variable declarations with descriptive names
      if (isConstantDeclaration(line)) {
        continue;
      }

      // Find all numbers in the line
      const numberMatches = line.matchAll(/(?<![a-zA-Z_])(-?\d+(?:\.\d+)?)\b/g);

      for (const match of numberMatches) {
        const numStr = match[1];
        const num = parseFloat(numStr);

        // Skip acceptable numbers
        if (ACCEPTABLE_NUMBERS.has(num)) {
          continue;
        }

        // Skip if in acceptable context
        if (ACCEPTABLE_CONTEXTS.some((pattern) => pattern.test(line))) {
          continue;
        }

        // Skip very small numbers (likely not magic)
        if (num >= -10 && num <= 10 && Number.isInteger(num)) {
          continue;
        }

        results.push({
          line: lineNum,
          column: match.index || 0,
          message: `Magic number ${numStr} - consider using a named constant`,
          severity: 'warning',
          ruleId: 'magic-numbers/unnamed',
        });
      }
    }

    return results;
  },
};

function isCommentLine(line: string, extension: string): boolean {
  const trimmed = line.trim();

  if (['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs'].includes(extension)) {
    return trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*');
  }

  if (['py', 'pyw'].includes(extension)) {
    return trimmed.startsWith('#');
  }

  return false;
}

function isConstantDeclaration(line: string): boolean {
  // JavaScript/TypeScript const with UPPER_CASE name
  if (/const\s+[A-Z][A-Z0-9_]+\s*=/.test(line)) {
    return true;
  }

  // Python uppercase variable (convention for constants)
  if (/^[A-Z][A-Z0-9_]+\s*=/.test(line.trim())) {
    return true;
  }

  return false;
}
