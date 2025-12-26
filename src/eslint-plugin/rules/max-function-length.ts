/**
 * ESLint rule: max-function-length
 * Enforce a maximum function length
 */

import type { Rule } from 'eslint';

const DEFAULT_MAX_LINES = 50;

const rule: Rule.RuleModule = {
  meta: {
    type: 'suggestion',
    docs: {
      description: 'Enforce a maximum function length',
      recommended: true,
    },
    messages: {
      tooLong: 'Function "{{ name }}" is {{ lines }} lines (max: {{ max }}) - consider refactoring',
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
    const maxLines = options.max || DEFAULT_MAX_LINES;

    function checkFunction(node: Rule.Node) {
      const loc = node.loc;
      if (!loc) return;

      const lines = loc.end.line - loc.start.line + 1;
      if (lines <= maxLines) return;

      // Get function name
      let name = 'anonymous';
      const nodeAny = node as { id?: { name?: string }; parent?: { type?: string; id?: { name?: string }; key?: { name?: string } } };

      if (nodeAny.id?.name) {
        name = nodeAny.id.name;
      } else if (nodeAny.parent?.type === 'VariableDeclarator' && nodeAny.parent.id?.name) {
        name = nodeAny.parent.id.name;
      } else if (nodeAny.parent?.type === 'MethodDefinition' && nodeAny.parent.key?.name) {
        name = nodeAny.parent.key.name;
      }

      context.report({
        node,
        messageId: 'tooLong',
        data: {
          name,
          lines: String(lines),
          max: String(maxLines),
        },
      });
    }

    return {
      FunctionDeclaration: checkFunction,
      FunctionExpression: checkFunction,
      ArrowFunctionExpression: checkFunction,
    };
  },
};

export default rule;
