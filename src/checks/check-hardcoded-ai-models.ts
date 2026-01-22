/**
 * Check for hardcoded AI model names and configurations
 *
 * AI models should be configured via environment variables or settings,
 * not hardcoded in the source code. This allows for easy model switching
 * and proper configuration management.
 */

import type { Hook, HookResult, FileContext } from '../utils/types.js';

// Common AI model name patterns
const AI_MODEL_PATTERNS = [
  // OpenAI models
  /["']gpt-4(?:-turbo|-vision|-\d+)?["']/gi,
  /["']gpt-3\.5-turbo(?:-\d+)?["']/gi,
  /["']text-davinci-\d+["']/gi,
  /["']text-embedding-(?:ada-\d+|3-\w+)["']/gi,
  /["']dall-e-\d+["']/gi,
  /["']whisper-\d+["']/gi,
  /["']tts-\d+(?:-hd)?["']/gi,
  /["']o1(?:-preview|-mini)?["']/gi,

  // Anthropic models
  /["']claude-(?:3|2|instant)(?:-\d+)?(?:-sonnet|-opus|-haiku)?(?:-\d+)?["']/gi,

  // Google models
  /["']gemini-(?:pro|ultra|nano)(?:-vision)?(?:-\d+)?["']/gi,
  /["']palm-\d+["']/gi,

  // Cohere models
  /["']command(?:-light|-nightly|-r)?(?:-\d+)?["']/gi,

  // Mistral models
  /["']mistral-(?:tiny|small|medium|large)(?:-\d+)?["']/gi,
  /["']mixtral-\d+x\d+b(?:-\d+)?["']/gi,

  // Llama models
  /["']llama-?\d+(?:-\d+b)?(?:-chat)?["']/gi,
  /["']codellama-\d+b["']/gi,
];

// Patterns that indicate it's in a config/env context (OK)
const ALLOWED_CONTEXTS = [
  /process\.env\./,
  /os\.environ/,
  /settings\./,
  /config\./,
  /getenv/,
  /ENV\[/,
  /default[=:]/i,  // Default value in env lookup
  /fallback/i,
  /\.env/,
  /# noqa/,
  /\/\/ noqa/,
  /eslint-disable/,
];

export const checkHardcodedAiModels: Hook = {
  id: 'ai-models',
  name: 'Check Hardcoded AI Models',
  description: 'Detect hardcoded AI model names - use environment variables or settings instead',
  severity: 'warning',
  fileTypes: ['js', 'jsx', 'ts', 'tsx', 'mjs', 'cjs', 'py'],

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

      // Skip if line has noqa directive
      if (line.includes('noqa') || line.includes('eslint-disable')) {
        continue;
      }

      // Check if line is in an allowed context (env lookup, config, etc.)
      if (ALLOWED_CONTEXTS.some(pattern => pattern.test(line))) {
        continue;
      }

      // Check for hardcoded model names
      for (const pattern of AI_MODEL_PATTERNS) {
        const match = line.match(pattern);
        if (match) {
          results.push({
            line: lineNum,
            column: line.indexOf(match[0]),
            message: `Hardcoded AI model "${match[0].replace(/["']/g, '')}" - use environment variable or settings`,
            severity: 'warning',
            ruleId: 'ai-models/hardcoded-model',
            fix: 'Use os.environ.get("AI_MODEL") or settings.AI_MODEL instead',
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

  return false;
}
