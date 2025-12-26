/**
 * lint-staged configuration for vibe-and-thrive
 *
 * Usage in package.json:
 *   "lint-staged": {
 *     "*.{js,ts,jsx,tsx}": "vibe-check --fail-on error"
 *   }
 *
 * Or import this config:
 *   import lintStagedConfig from 'vibe-and-thrive/lint-staged';
 */

export interface LintStagedConfig {
  [pattern: string]: string | string[];
}

/**
 * Default lint-staged configuration
 */
export const config: LintStagedConfig = {
  '*.{js,ts,jsx,tsx}': [
    'vibe-check --only secrets,urls,debug,any-types,snake-case --fail-on error',
  ],
  '*.py': [
    'vibe-check --only secrets,urls,debug,magic-numbers --fail-on error',
  ],
  '*.{json,yaml,yml}': [
    'vibe-check --only secrets --fail-on error',
  ],
};

export default config;
