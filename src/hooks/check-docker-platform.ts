/**
 * Check for missing platform specification in Dockerfiles
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

export const checkDockerPlatform: Hook = {
  id: 'docker-platform',
  name: 'Check Docker Platform',
  description: 'Detect missing --platform flag in Dockerfile FROM instructions',
  severity: 'info',
  fileTypes: ['dockerfile'],

  check(context: FileContext): HookResult[] {
    const results: HookResult[] = [];
    const lines = context.content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNum = i + 1;

      // Skip comments
      if (line.trim().startsWith('#')) {
        continue;
      }

      // Check for FROM instruction
      if (/^\s*FROM\s+/i.test(line)) {
        // Check if --platform is specified
        if (!line.includes('--platform')) {
          // Skip if using ARG for platform (dynamic platform)
          if (/\$\{?TARGETPLATFORM\}?|\$\{?BUILDPLATFORM\}?/i.test(line)) {
            continue;
          }

          results.push({
            line: lineNum,
            column: 0,
            message: 'Consider adding --platform flag for reproducible builds (e.g., --platform=linux/amd64)',
            severity: 'info',
            ruleId: 'docker-platform/missing',
            fix: 'Add --platform=linux/amd64 or --platform=$TARGETPLATFORM',
          });
        }
      }
    }

    return results;
  },
};
