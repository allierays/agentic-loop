/**
 * ESLint rule: no-deep-nesting
 * Disallow deeply nested code blocks
 */

import type { Rule } from 'eslint';

const DEFAULT_MAX_DEPTH = 4;

const rule: Rule.RuleModule = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Disallow deeply nested code blocks',
      recommended: true,
    },
    messages: {
      tooDeep: 'Nesting depth {{ depth }} exceeds maximum of {{ max }} - consider refactoring',
    },
    schema: [
      {
        type: 'object',
        properties: {
          max: {
            type: 'number',
            minimum: 1,
          },
        },
        additionalProperties: false,
      },
    ],
  },

  create(context) {
    const options = context.options[0] || {};
    const maxDepth = options.max || DEFAULT_MAX_DEPTH;
    let currentDepth = 0;

    function enterBlock(node: Rule.Node) {
      currentDepth++;
      if (currentDepth > maxDepth) {
        context.report({
          node,
          messageId: 'tooDeep',
          data: {
            depth: String(currentDepth),
            max: String(maxDepth),
          },
        });
      }
    }

    function exitBlock() {
      currentDepth--;
    }

    return {
      BlockStatement: enterBlock,
      'BlockStatement:exit': exitBlock,
    };
  },
};

export default rule;
