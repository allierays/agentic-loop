/**
 * Check lessons.json for credentials (emails, passwords, tokens, API keys)
 *
 * Lessons are learned patterns saved to .ralph/lessons.json and committed to git.
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
  { pattern: EMAIL_PATTERN, message: 'Email address in lesson — use environment variables', ruleId: 'lessons-secrets/email' },
  { pattern: PASSWORD_PATTERN, message: 'Password reference in lesson — use environment variables', ruleId: 'lessons-secrets/password' },
  { pattern: TOKEN_PATTERN, message: 'Token/secret/key reference in lesson — use environment variables', ruleId: 'lessons-secrets/token' },
  { pattern: AWS_KEY_PATTERN, message: 'AWS access key in lesson — use environment variables', ruleId: 'lessons-secrets/aws-key' },
  { pattern: OPENAI_KEY_PATTERN, message: 'OpenAI API key in lesson — use environment variables', ruleId: 'lessons-secrets/openai-key' },
  { pattern: GITHUB_TOKEN_PATTERN, message: 'GitHub token in lesson — use environment variables', ruleId: 'lessons-secrets/github-token' },
  { pattern: STRIPE_KEY_PATTERN, message: 'Stripe key in lesson — use environment variables', ruleId: 'lessons-secrets/stripe-key' },
];

export const checkLessonsSecrets: Hook = {
  id: 'lessons-secrets',
  name: 'Check Lessons for Credentials',
  description: 'Detect credentials (emails, passwords, tokens) in lessons.json',
  severity: 'error',
  fileTypes: ['json'],

  check(context: FileContext): HookResult[] {
    // Only check lessons.json files
    if (!context.filePath.endsWith('lessons.json')) {
      return [];
    }

    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Only check lines that contain pattern values (the actual lesson text)
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
