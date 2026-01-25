/**
 * Ready-to-use lint-staged configuration for agentic-loop
 *
 * Copy this file to your project root, or reference the config:
 *
 *   // package.json
 *   {
 *     "lint-staged": {
 *       "*.{js,ts,jsx,tsx}": "vibe-check --fail-on error"
 *     }
 *   }
 */

export default {
  // JavaScript/TypeScript files - full security and quality checks
  '*.{js,jsx,ts,tsx,mjs,cjs}': [
    'vibe-check --only secrets,urls,debug,unsafe-html,any-types,snake-case,empty-catch --fail-on error',
  ],

  // Python files
  '*.py': [
    'vibe-check --only secrets,urls,debug,empty-catch,magic-numbers --fail-on error',
  ],

  // Config files - secrets check only
  '*.{json,yaml,yml,toml}': [
    'vibe-check --only secrets --fail-on error',
  ],

  // Dockerfiles
  'Dockerfile*': [
    'vibe-check --only docker-platform --fail-on warning',
  ],
};
