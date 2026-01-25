/**
 * Check for DRY (Don't Repeat Yourself) violations - duplicated code blocks
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

// Minimum number of similar lines to consider a duplicate
const MIN_DUPLICATE_LINES = 8;

// Minimum similarity threshold (0-1)
const SIMILARITY_THRESHOLD = 0.90;

// Max duplicates to report per file (prevent noise)
const MAX_DUPLICATES_PER_FILE = 5;

// Paths to skip (too many false positives)
const SKIP_PATH_PATTERNS = [
  /\/components\//i,
  /\/pages\//i,
  /\/views\//i,
  /\/layouts\//i,
  /\/ui\//i,
  /\.styled\./i,
  /\.styles\./i,
  /styleguide/i,
  /\.test\./i,
  /\.spec\./i,
  /\/__tests__\//i,
  /\/test\//i,
  /\/tests\//i,
  /\/fixtures?\//i,
];

// Keywords that should NOT be normalized (keep them distinct)
const KEYWORDS = new Set([
  // JS/TS
  'const', 'let', 'var', 'function', 'class', 'return', 'if', 'else', 'for', 'while',
  'switch', 'case', 'break', 'continue', 'try', 'catch', 'finally', 'throw', 'new',
  'this', 'super', 'import', 'export', 'default', 'from', 'as', 'async', 'await',
  'typeof', 'instanceof', 'in', 'of', 'true', 'false', 'null', 'undefined',
  'interface', 'type', 'enum', 'extends', 'implements', 'public', 'private', 'protected',
  // Python
  'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'try', 'except',
  'finally', 'raise', 'import', 'from', 'as', 'with', 'lambda', 'pass', 'True', 'False', 'None',
  // Common test functions
  'describe', 'it', 'test', 'expect', 'beforeAll', 'afterAll', 'beforeEach', 'afterEach',
]);

export const checkDryViolations: Hook = {
  id: 'dry',
  name: 'Check DRY Violations',
  description: 'Detect duplicated code blocks that should be extracted',
  severity: 'warning',
  // Skip JSX/TSX - too many false positives with similar component patterns
  fileTypes: ['js', 'ts', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];

    // Skip files that tend to have false positives
    if (SKIP_PATH_PATTERNS.some((pattern) => pattern.test(context.filePath))) {
      return results;
    }

    const lines = context.content.split('\n');

    // Normalize lines for comparison (remove whitespace, comments)
    const normalizedLines = lines.map((line, index) => ({
      original: line,
      normalized: normalizeLine(line, context.extension),
      lineNum: index + 1,
    }));

    // Filter out empty/trivial lines
    const significantLines = normalizedLines.filter(
      (l) => l.normalized.length > 15 && !isTrivialLine(l.normalized)
    );

    // Need enough significant lines to compare
    if (significantLines.length < MIN_DUPLICATE_LINES * 2) {
      return results;
    }

    // Find duplicate blocks using a sliding window approach
    const reportedBlocks = new Set<string>();

    for (let i = 0; i < significantLines.length - MIN_DUPLICATE_LINES; i++) {
      // Stop if we've reported enough
      if (results.length >= MAX_DUPLICATES_PER_FILE) break;

      // Create a "fingerprint" of the next N lines
      const block1 = significantLines.slice(i, i + MIN_DUPLICATE_LINES);
      const fingerprint1 = block1.map((l) => l.normalized).join('\n');

      // Look for similar blocks later in the file
      for (let j = i + MIN_DUPLICATE_LINES; j < significantLines.length - MIN_DUPLICATE_LINES; j++) {
        if (results.length >= MAX_DUPLICATES_PER_FILE) break;

        const block2 = significantLines.slice(j, j + MIN_DUPLICATE_LINES);
        const fingerprint2 = block2.map((l) => l.normalized).join('\n');

        // Check similarity
        const similarity = calculateSimilarity(fingerprint1, fingerprint2);

        if (similarity >= SIMILARITY_THRESHOLD) {
          // Create a unique key for this duplicate pair (sorted to avoid A-B and B-A)
          const key1 = Math.min(block1[0].lineNum, block2[0].lineNum);
          const key2 = Math.max(block1[0].lineNum, block2[0].lineNum);
          const blockKey = `${key1}-${key2}`;

          if (!reportedBlocks.has(blockKey)) {
            reportedBlocks.add(blockKey);

            results.push({
              line: block1[0].lineNum,
              column: 0,
              message: `Similar code block found at line ${block2[0].lineNum} - consider extracting to a function`,
              severity: 'warning',
              ruleId: 'dry/duplicate-block',
            });
          }
        }
      }
    }

    return results;
  },
};

function normalizeLine(line: string, extension: string): string {
  let normalized = line;

  // Remove comments
  if (['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs'].includes(extension)) {
    normalized = normalized.replace(/\/\/.*$/, '').replace(/\/\*.*?\*\//g, '');
  } else if (['py', 'pyw'].includes(extension)) {
    normalized = normalized.replace(/#.*$/, '');
  }

  // Normalize whitespace
  normalized = normalized.replace(/\s+/g, ' ').trim();

  // Replace strings and numbers first
  normalized = normalized
    .replace(/"[^"]*"/g, 'STR')
    .replace(/'[^']*'/g, 'STR')
    .replace(/`[^`]*`/g, 'STR')
    .replace(/\b\d+\.?\d*\b/g, 'NUM');

  // Replace variable/function names with placeholders, but preserve keywords
  // Only replace identifiers that look like user-defined names (camelCase, snake_case)
  normalized = normalized.replace(/\b([a-z][a-zA-Z0-9_]*)\b/g, (match) => {
    // Keep keywords as-is
    if (KEYWORDS.has(match)) {
      return match;
    }
    // Replace user-defined identifiers
    return 'VAR';
  });

  return normalized;
}

function isTrivialLine(normalized: string): boolean {
  // Lines that are too generic to be meaningful duplicates
  const trivialPatterns = [
    /^[{}()\[\];,]+$/,                     // Just brackets/punctuation
    /^(?:return|break|continue|pass);?$/,  // Single keywords
    /^VAR\s*=\s*(?:VAR|STR|NUM);?$/,       // Simple assignments
    /^}\s*(?:else|catch|finally)\s*{?$/,   // Control flow brackets
    /^import\s/,                            // Import statements (often similar)
    /^export\s/,                            // Export statements
  ];

  return trivialPatterns.some((pattern) => pattern.test(normalized));
}

function calculateSimilarity(str1: string, str2: string): number {
  // Simple Jaccard similarity based on character n-grams
  const ngram = (s: string, n: number): Set<string> => {
    const grams = new Set<string>();
    for (let i = 0; i <= s.length - n; i++) {
      grams.add(s.slice(i, i + n));
    }
    return grams;
  };

  const grams1 = ngram(str1, 3);
  const grams2 = ngram(str2, 3);

  let intersection = 0;
  for (const gram of grams1) {
    if (grams2.has(gram)) {
      intersection++;
    }
  }

  const union = grams1.size + grams2.size - intersection;
  return union > 0 ? intersection / union : 0;
}
