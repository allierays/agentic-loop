/**
 * ESLint rule: no-debug-statements
 * Disallow console.log, debugger, and other debug statements
 */

import type { Rule } from 'eslint';

const rule: Rule.RuleModule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Disallow debug statements (console.log, debugger)',
      recommended: true,
    },
    fixable: 'code',
    messages: {
      consoleLog: 'Unexpected console.log statement - remove before commit',
      consoleDebug: 'Unexpected console.debug statement - remove before commit',
      debugger: 'Unexpected debugger statement - remove before commit',
      alert: 'Unexpected alert statement - remove before commit',
    },
    schema: [],
  },

  create(context) {
    return {
      CallExpression(node: Rule.Node & {
        callee?: {
          type?: string;
          object?: { name?: string };
          property?: { name?: string };
          name?: string;
        };
      }) {
        // Check for console.log, console.debug
        if (
          node.callee?.type === 'MemberExpression' &&
          node.callee.object?.name === 'console'
        ) {
          const method = node.callee.property?.name;
          if (method === 'log') {
            context.report({
              node,
              messageId: 'consoleLog',
            });
          } else if (method === 'debug') {
            context.report({
              node,
              messageId: 'consoleDebug',
            });
          }
        }

        // Check for alert()
        if (node.callee?.type === 'Identifier' && node.callee.name === 'alert') {
          context.report({
            node,
            messageId: 'alert',
          });
        }
      },

      DebuggerStatement(node: Rule.Node) {
        context.report({
          node,
          messageId: 'debugger',
        });
      },
    };
  },
};

export default rule;
