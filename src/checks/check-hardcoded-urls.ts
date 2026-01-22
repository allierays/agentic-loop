/**
 * Check for hardcoded URLs that should use environment variables
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

// Common CDN and safe domains to ignore
const SAFE_DOMAINS = new Set([
  'cdn.jsdelivr.net',
  'cdnjs.cloudflare.com',
  'unpkg.com',
  'fonts.googleapis.com',
  'fonts.gstatic.com',
  'fonts.bunny.net',
  'api.github.com',
  'raw.githubusercontent.com',
  'registry.npmjs.org',
  'pypi.org',
  'schema.org',
  'www.w3.org',
  'example.com',
  'example.org',
]);

// Patterns that indicate this is likely test/example code
const TEST_PATTERNS = [
  /\.test\./,
  /\.spec\./,
  /\/__tests__\//,
  /\/test\//,
  /\/fixtures?\//,
  /\.mock\./,
];

export const checkHardcodedUrls: Hook = {
  id: 'urls',
  name: 'Check Hardcoded URLs',
  description: 'Detect hardcoded URLs that should use environment variables',
  severity: 'error',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    // Skip test files
    if (TEST_PATTERNS.some((p) => p.test(context.filePath))) {
      return results;
    }

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comments
      if (isCommentLine(line, context.extension)) {
        continue;
      }

      // Check for localhost URLs
      const localhostMatches = line.matchAll(/https?:\/\/localhost(?::\d+)?(?:\/[^\s'")\]]*)?/g);
      for (const match of localhostMatches) {
        // Skip if in a fallback/default pattern
        if (isFallbackPattern(line, match.index || 0)) {
          continue;
        }

        results.push({
          line: lineNum,
          column: match.index || 0,
          message: 'Hardcoded localhost URL - use environment variable',
          severity: 'warning',
          ruleId: 'urls/localhost',
          fix: 'Use process.env.API_URL or similar',
        });
      }

      // Check for 127.0.0.1 URLs
      const ipMatches = line.matchAll(/https?:\/\/127\.0\.0\.1(?::\d+)?(?:\/[^\s'")\]]*)?/g);
      for (const match of ipMatches) {
        if (isFallbackPattern(line, match.index || 0)) {
          continue;
        }

        results.push({
          line: lineNum,
          column: match.index || 0,
          message: 'Hardcoded localhost IP - use environment variable',
          severity: 'warning',
          ruleId: 'urls/localhost-ip',
        });
      }

      // Check for production URLs
      const urlMatches = line.matchAll(/https?:\/\/([a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,}(?:\.[a-zA-Z]{2,})?)(?::\d+)?(?:\/[^\s'")\]]*)?/g);
      for (const match of urlMatches) {
        const domain = match[1].toLowerCase();

        // Skip safe domains
        if (SAFE_DOMAINS.has(domain)) {
          continue;
        }

        // Skip if in a fallback pattern
        if (isFallbackPattern(line, match.index || 0)) {
          continue;
        }

        // Skip common documentation/example patterns
        if (domain.includes('example') || domain.includes('placeholder')) {
          continue;
        }

        // Flag as potential hardcoded production URL
        results.push({
          line: lineNum,
          column: match.index || 0,
          message: `Hardcoded URL (${domain}) - consider using environment variable`,
          severity: 'warning',
          ruleId: 'urls/hardcoded',
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

function isFallbackPattern(line: string, urlIndex: number): boolean {
  // Check if URL appears after || or ?? or as a default value
  const before = line.substring(0, urlIndex);
  return /(\|\||\?\?|:\s*$|,\s*$|=\s*$|default[:\s]*$)/i.test(before.trim());
}
