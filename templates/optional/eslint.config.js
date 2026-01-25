/**
 * Example ESLint configuration using agentic-loop plugin
 *
 * Copy this file to your project root and customize as needed.
 */

import vibe from "agentic-loop/eslint-plugin";

export default [
  // Use the recommended config (balanced defaults)
  vibe.configs.recommended,

  // Or use strict config for stricter rules
  // vibe.configs.strict,

  // Custom configuration
  {
    files: ["**/*.ts", "**/*.tsx"],
    rules: {
      // Override specific rules if needed
      // "vibe/no-any-type": "error",
      // "vibe/max-function-length": ["warn", { max: 40 }],
    },
  },

  // Disable rules for test files
  {
    files: ["**/*.test.ts", "**/*.test.tsx", "**/*.spec.ts", "**/*.spec.tsx"],
    rules: {
      "vibe/no-magic-numbers": "off",
      "vibe/max-function-length": "off",
    },
  },
];
