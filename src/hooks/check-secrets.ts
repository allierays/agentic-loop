/**
 * Check for hardcoded secrets, API keys, and tokens
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';
import { SECRET_PATTERNS, isPlaceholder } from '../utils/patterns.js';

export const checkSecrets: Hook = {
  id: 'secrets',
  name: 'Check Secrets',
  description: 'Detect hardcoded API keys, passwords, and tokens',
  severity: 'error',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py', 'json', 'yaml', 'yml', 'toml', 'env'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comments
      if (isCommentLine(line, context.extension)) {
        continue;
      }

      // AWS Access Key
      const awsMatch = line.match(SECRET_PATTERNS.awsAccessKey);
      if (awsMatch && !isPlaceholder(awsMatch[0])) {
        results.push({
          line: lineNum,
          column: line.indexOf(awsMatch[0]),
          message: 'Possible AWS Access Key detected',
          severity: 'error',
          ruleId: 'secrets/aws-key',
        });
      }

      // Stripe Key
      const stripeMatch = line.match(SECRET_PATTERNS.stripeKey);
      if (stripeMatch && !isPlaceholder(stripeMatch[0])) {
        results.push({
          line: lineNum,
          column: line.indexOf(stripeMatch[0]),
          message: 'Stripe API key detected',
          severity: 'error',
          ruleId: 'secrets/stripe-key',
        });
      }

      // GitHub Token
      const githubMatch = line.match(SECRET_PATTERNS.githubToken);
      if (githubMatch && !isPlaceholder(githubMatch[0])) {
        results.push({
          line: lineNum,
          column: line.indexOf(githubMatch[0]),
          message: 'GitHub token detected',
          severity: 'error',
          ruleId: 'secrets/github-token',
        });
      }

      // Slack Token
      const slackMatch = line.match(SECRET_PATTERNS.slackToken);
      if (slackMatch && !isPlaceholder(slackMatch[0])) {
        results.push({
          line: lineNum,
          column: line.indexOf(slackMatch[0]),
          message: 'Slack token detected',
          severity: 'error',
          ruleId: 'secrets/slack-token',
        });
      }

      // SendGrid Key
      const sendgridMatch = line.match(SECRET_PATTERNS.sendgridKey);
      if (sendgridMatch && !isPlaceholder(sendgridMatch[0])) {
        results.push({
          line: lineNum,
          column: line.indexOf(sendgridMatch[0]),
          message: 'SendGrid API key detected',
          severity: 'error',
          ruleId: 'secrets/sendgrid-key',
        });
      }

      // Private Key
      if (SECRET_PATTERNS.privateKey.test(line)) {
        results.push({
          line: lineNum,
          column: 0,
          message: 'Private key detected - never commit private keys',
          severity: 'error',
          ruleId: 'secrets/private-key',
        });
      }

      // Generic API key patterns
      const genericApiMatch = line.match(SECRET_PATTERNS.genericApiKey);
      if (genericApiMatch && !isPlaceholder(genericApiMatch[0])) {
        // Only flag if it looks like a real key (long enough, not a placeholder)
        const value = genericApiMatch[0];
        if (value.length > 30) {
          results.push({
            line: lineNum,
            column: line.indexOf(value),
            message: 'Possible hardcoded API key - use environment variables',
            severity: 'error',
            ruleId: 'secrets/generic-api-key',
          });
        }
      }

      // Generic secrets (password, token, etc.)
      const secretMatch = line.match(SECRET_PATTERNS.genericSecret);
      if (secretMatch && !isPlaceholder(secretMatch[0])) {
        // Skip obvious non-secrets
        const value = secretMatch[0].toLowerCase();
        if (
          !value.includes('password:') && // Not a type annotation
          !value.includes('password =') && // Assignment with placeholder
          value.length > 20
        ) {
          results.push({
            line: lineNum,
            column: line.indexOf(secretMatch[0]),
            message: 'Possible hardcoded secret - use environment variables',
            severity: 'warning',
            ruleId: 'secrets/generic-secret',
          });
        }
      }
    }

    return results;
  },
};

function isCommentLine(line: string, extension: string): boolean {
  const trimmed = line.trim();

  // JavaScript/TypeScript style comments
  if (['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs'].includes(extension)) {
    return trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*');
  }

  // Python style comments
  if (['py', 'pyw'].includes(extension)) {
    return trimmed.startsWith('#');
  }

  // YAML style comments
  if (['yaml', 'yml'].includes(extension)) {
    return trimmed.startsWith('#');
  }

  return false;
}
