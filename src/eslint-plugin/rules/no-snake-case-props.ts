/**
 * ESLint rule: no-snake-case-props
 * Disallow snake_case property names in TypeScript interfaces
 */

import type { Rule } from 'eslint';

const SNAKE_CASE_PATTERN = /^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$/;

function toCamelCase(snakeCase: string): string {
  return snakeCase.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
}

const rule: Rule.RuleModule = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Disallow snake_case property names in TypeScript interfaces',
      recommended: true,
    },
    fixable: 'code',
    messages: {
      snakeCase: 'Property "{{ name }}" uses snake_case - use camelCase "{{ suggested }}" instead',
    },
    schema: [],
  },

  create(context) {
    return {
      TSPropertySignature(node: Rule.Node) {
        const nodeAny = node as { key?: { type?: string; name?: string } };
        if (nodeAny.key?.type === 'Identifier' && nodeAny.key.name) {
          const name = nodeAny.key.name;
          if (SNAKE_CASE_PATTERN.test(name)) {
            const keyNode = nodeAny.key as unknown as Rule.Node;
            context.report({
              node: keyNode,
              messageId: 'snakeCase',
              data: {
                name,
                suggested: toCamelCase(name),
              },
              fix(fixer) {
                return fixer.replaceText(keyNode, toCamelCase(name));
              },
            });
          }
        }
      },
    };
  },
};

export default rule;
