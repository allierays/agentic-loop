/**
 * Check signs.json for credentials (emails, passwords, tokens, API keys)
 *
 * Signs are learned patterns saved to .ralph/signs.json and committed to git.
 * They should never contain credentials — use environment variables instead.
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

const EMAIL_PATTERN = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/;
const PASSWORD_PATTERN = /password\s*[:=]/i;
const TOKEN_PATTERN = /\b[A-Za-z0-9_]*_?(pass|pwd|token|secret|key|api[_.]?key)\s*[:=]/i;
const AWS_KEY_PATTERN = /AKIA[0-9A-Z]{16}/;
const OPENAI_KEY_PATTERN = /sk-[a-zA-Z0-9]{20,}/;
const GITHUB_TOKEN_PATTERN = /ghp_[a-zA-Z0-9]{36}/;
const STRIPE_KEY_PATTERN = /sk_(live|test)_[0-9a-zA-Z]{24,}/;

const CREDENTIAL_CHECKS: { pattern: RegExp; message: string; ruleId: string }[] = [
  { pattern: EMAIL_PATTERN, message: 'Email address in sign — use environment variables', ruleId: 'signs-secrets/email' },
  { pattern: PASSWORD_PATTERN, message: 'Password reference in sign — use environment variables', ruleId: 'signs-secrets/password' },
  { pattern: TOKEN_PATTERN, message: 'Token/secret/key reference in sign — use environment variables', ruleId: 'signs-secrets/token' },
  { pattern: AWS_KEY_PATTERN, message: 'AWS access key in sign — use environment variables', ruleId: 'signs-secrets/aws-key' },
  { pattern: OPENAI_KEY_PATTERN, message: 'OpenAI API key in sign — use environment variables', ruleId: 'signs-secrets/openai-key' },
  { pattern: GITHUB_TOKEN_PATTERN, message: 'GitHub token in sign — use environment variables', ruleId: 'signs-secrets/github-token' },
  { pattern: STRIPE_KEY_PATTERN, message: 'Stripe key in sign — use environment variables', ruleId: 'signs-secrets/stripe-key' },
];

export const checkSignsSecrets: Hook = {
  id: 'signs-secrets',
  name: 'Check Signs for Credentials',
  description: 'Detect credentials (emails, passwords, tokens) in signs.json',
  severity: 'error',
  fileTypes: ['json'],

  check(context: FileContext): HookResult[] {
    // Only check signs.json files
    if (!context.filePath.endsWith('signs.json')) {
      return [];
    }

    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Only check lines that contain pattern values (the actual sign text)
      if (!/"pattern"/.test(line)) {
        continue;
      }

      for (const { pattern, message, ruleId } of CREDENTIAL_CHECKS) {
        if (pattern.test(line)) {
          results.push({
            line: lineNum,
            message,
            severity: 'error',
            ruleId,
          });
        }
      }
    }

    return results;
  },
};
