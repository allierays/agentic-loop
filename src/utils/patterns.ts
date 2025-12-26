/**
 * Common regex patterns used across hooks
 */

// Secret patterns
export const SECRET_PATTERNS = {
  // AWS
  awsAccessKey: /AKIA[0-9A-Z]{16}/,
  awsSecretKey: /(?<![A-Za-z0-9/+=])[A-Za-z0-9/+=]{40}(?![A-Za-z0-9/+=])/,

  // API keys (generic)
  genericApiKey: /(?:api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*['"][a-zA-Z0-9_\-]{20,}['"]/i,
  genericSecret: /(?:secret|password|passwd|pwd|token|auth)\s*[:=]\s*['"][^'"]{8,}['"]/i,

  // Specific services
  stripeKey: /sk_(?:live|test)_[0-9a-zA-Z]{24,}/,
  githubToken: /gh[pousr]_[A-Za-z0-9_]{36,}/,
  slackToken: /xox[baprs]-[0-9]{10,}-[0-9a-zA-Z]{24,}/,
  twilioKey: /SK[0-9a-fA-F]{32}/,
  sendgridKey: /SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}/,

  // Private keys
  privateKey: /-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/,

  // JWT (only if it looks like a real token, not a placeholder)
  jwt: /eyJ[a-zA-Z0-9_-]{10,}\.eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}/,
};

// URL patterns
export const URL_PATTERNS = {
  // Localhost URLs
  localhost: /https?:\/\/localhost(?::\d+)?(?:\/[^\s'"]*)?/g,
  localIp: /https?:\/\/127\.0\.0\.1(?::\d+)?(?:\/[^\s'"]*)?/g,

  // Hardcoded production URLs (excluding common CDNs)
  hardcodedUrl: /https?:\/\/(?!(?:cdn|fonts|unpkg|cdnjs|jsdelivr)\.)[a-zA-Z0-9][a-zA-Z0-9-]*\.[a-zA-Z]{2,}(?::\d+)?(?:\/[^\s'"]*)?/g,
};

// Debug statement patterns by language
export const DEBUG_PATTERNS: Record<string, RegExp[]> = {
  javascript: [
    /console\.(log|debug|info|warn|error|trace|dir|table)\s*\(/,
    /debugger\s*;?/,
    /alert\s*\(/,
  ],
  typescript: [
    /console\.(log|debug|info|warn|error|trace|dir|table)\s*\(/,
    /debugger\s*;?/,
  ],
  python: [
    /\bprint\s*\(/,
    /\bbreakpoint\s*\(\s*\)/,
    /\bpdb\.set_trace\s*\(\s*\)/,
    /\bipdb\.set_trace\s*\(\s*\)/,
  ],
};

// File extensions by language type
export const LANGUAGE_EXTENSIONS: Record<string, string[]> = {
  javascript: ['js', 'jsx', 'mjs', 'cjs'],
  typescript: ['ts', 'tsx', 'mts', 'cts'],
  python: ['py', 'pyw'],
  json: ['json', 'jsonc'],
  yaml: ['yaml', 'yml'],
  docker: ['dockerfile'],
  html: ['html', 'htm'],
};

// Get language from file extension
export function getLanguage(extension: string): string | undefined {
  for (const [lang, exts] of Object.entries(LANGUAGE_EXTENSIONS)) {
    if (exts.includes(extension.toLowerCase())) {
      return lang;
    }
  }
  return undefined;
}

// Common placeholder patterns (to ignore in secret detection)
export const PLACEHOLDER_PATTERNS = [
  /example/i,
  /placeholder/i,
  /your[_-]?(?:api[_-]?)?key/i,
  /xxx+/i,
  /test/i,
  /dummy/i,
  /fake/i,
  /sample/i,
  /demo/i,
];

// Check if a string looks like a placeholder
export function isPlaceholder(value: string): boolean {
  return PLACEHOLDER_PATTERNS.some((pattern) => pattern.test(value));
}
