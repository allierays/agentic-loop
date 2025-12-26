/**
 * Check for DRY (Don't Repeat Yourself) violations - duplicated code blocks
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

// Minimum number of similar lines to consider a duplicate
const MIN_DUPLICATE_LINES = 5;

// Minimum similarity threshold (0-1)
const SIMILARITY_THRESHOLD = 0.85;

// Paths that indicate frontend component files (skip these - too many false positives)
const FRONTEND_PATH_PATTERNS = [
  /\/components\//i,
  /\/pages\//i,
  /\/views\//i,
  /\/layouts\//i,
  /\/ui\//i,
  /\.styled\./i,
  /\.styles\./i,
  /styleguide/i,
];

export const checkDryViolations: Hook = {
  id: 'dry',
  name: 'Check DRY Violations',
  description: 'Detect duplicated code blocks that should be extracted',
  severity: 'warning',
  // Skip JSX/TSX - too many false positives with similar component patterns
  fileTypes: ['js', 'ts', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];

    // Skip frontend component files
    if (FRONTEND_PATH_PATTERNS.some((pattern) => pattern.test(context.filePath))) {
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
      (l) => l.normalized.length > 10 && !isTrivialLine(l.normalized)
    );

    // Find duplicate blocks using a sliding window approach
    const reportedBlocks = new Set<string>();

    for (let i = 0; i < significantLines.length - MIN_DUPLICATE_LINES; i++) {
      // Create a "fingerprint" of the next N lines
      const block1 = significantLines.slice(i, i + MIN_DUPLICATE_LINES);
      const fingerprint1 = block1.map((l) => l.normalized).join('\n');

      // Look for similar blocks later in the file
      for (let j = i + MIN_DUPLICATE_LINES; j < significantLines.length - MIN_DUPLICATE_LINES; j++) {
        const block2 = significantLines.slice(j, j + MIN_DUPLICATE_LINES);
        const fingerprint2 = block2.map((l) => l.normalized).join('\n');

        // Check similarity
        const similarity = calculateSimilarity(fingerprint1, fingerprint2);

        if (similarity >= SIMILARITY_THRESHOLD) {
          // Create a unique key for this duplicate pair
          const blockKey = `${block1[0].lineNum}-${block2[0].lineNum}`;

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

  // Replace variable names with placeholders (simplified)
  // This helps match similar code with different variable names
  normalized = normalized
    .replace(/\b[a-z][a-zA-Z0-9]*\b/g, 'VAR')
    .replace(/"[^"]*"/g, 'STR')
    .replace(/'[^']*'/g, 'STR')
    .replace(/\d+/g, 'NUM');

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
