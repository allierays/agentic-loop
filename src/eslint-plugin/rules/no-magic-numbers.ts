/**
 * ESLint rule: no-magic-numbers
 * Disallow magic numbers that should be named constants
 */

import type { Rule } from 'eslint';

const ACCEPTABLE_NUMBERS = new Set([-1, 0, 1, 2, 10, 100, 1000]);

const rule: Rule.RuleModule = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Disallow magic numbers that should be named constants',
      recommended: false,
    },
    messages: {
      magicNumber: 'Magic number {{ value }} - consider using a named constant',
    },
    schema: [
      {
        type: 'object',
        properties: {
          ignore: {
            type: 'array',
            items: { type: 'number' },
          },
        },
        additionalProperties: false,
      },
    ],
  },

  create(context) {
    const options = context.options[0] || {};
    const ignore = new Set([...ACCEPTABLE_NUMBERS, ...(options.ignore || [])]);

    return {
      Literal(node: Rule.Node & { value?: unknown; parent?: { type?: string } }) {
        if (typeof node.value !== 'number') return;
        if (ignore.has(node.value)) return;

        // Skip array indices
        if (node.parent?.type === 'MemberExpression') return;

        // Skip variable declarations with UPPER_CASE names
        if (
          node.parent?.type === 'VariableDeclarator' &&
          (node.parent as { id?: { name?: string } }).id?.name?.match(/^[A-Z][A-Z0-9_]*$/)
        ) {
          return;
        }

        context.report({
          node,
          messageId: 'magicNumber',
          data: {
            value: String(node.value),
          },
        });
      },
    };
  },
};

export default rule;
