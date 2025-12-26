/**
 * vibe-and-thrive ESLint plugin
 *
 * Usage:
 *   import vibe from 'vibe-and-thrive/eslint-plugin';
 *   export default [vibe.configs.recommended];
 */

import noAnyType from './rules/no-any-type.js';
import noSnakeCaseProps from './rules/no-snake-case-props.js';
import noDebugStatements from './rules/no-debug-statements.js';
import noEmptyCatch from './rules/no-empty-catch.js';
import noMagicNumbers from './rules/no-magic-numbers.js';
import noDeepNesting from './rules/no-deep-nesting.js';
import maxFunctionLength from './rules/max-function-length.js';

const rules = {
  'no-any-type': noAnyType,
  'no-snake-case-props': noSnakeCaseProps,
  'no-debug-statements': noDebugStatements,
  'no-empty-catch': noEmptyCatch,
  'no-magic-numbers': noMagicNumbers,
  'no-deep-nesting': noDeepNesting,
  'max-function-length': maxFunctionLength,
};

const plugin = {
  meta: {
    name: 'vibe-and-thrive',
    version: '1.0.0',
  },
  rules,
  configs: {
    recommended: {
      plugins: {
        get vibe() {
          return plugin;
        },
      },
      rules: {
        'vibe/no-any-type': 'warn',
        'vibe/no-snake-case-props': 'warn',
        'vibe/no-debug-statements': 'warn',
        'vibe/no-empty-catch': 'warn',
        'vibe/no-magic-numbers': 'off', // Often noisy
        'vibe/no-deep-nesting': 'warn',
        'vibe/max-function-length': 'warn',
      },
    },
    strict: {
      plugins: {
        get vibe() {
          return plugin;
        },
      },
      rules: {
        'vibe/no-any-type': 'error',
        'vibe/no-snake-case-props': 'error',
        'vibe/no-debug-statements': 'error',
        'vibe/no-empty-catch': 'error',
        'vibe/no-magic-numbers': 'warn',
        'vibe/no-deep-nesting': 'error',
        'vibe/max-function-length': ['error', { max: 40 }],
      },
    },
  },
};

export default plugin;
export { rules };
