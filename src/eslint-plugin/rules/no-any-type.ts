/**
 * ESLint rule: no-any-type
 * Disallow usage of 'any' type in TypeScript
 */

import type { Rule } from 'eslint';

const rule: Rule.RuleModule = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Disallow usage of "any" type',
      recommended: true,
    },
    messages: {
      noAny: 'Avoid using "any" type - use "unknown" or a specific type instead',
    },
    schema: [],
  },

  create(context) {
    return {
      TSAnyKeyword(node: Rule.Node) {
        context.report({
          node,
          messageId: 'noAny',
        });
      },
    };
  },
};

export default rule;
