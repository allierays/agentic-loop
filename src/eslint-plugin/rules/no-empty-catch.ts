/**
 * ESLint rule: no-empty-catch
 * Disallow empty catch blocks
 */

import type { Rule } from 'eslint';

const rule: Rule.RuleModule = {
  meta: {
    type: 'problem',
    docs: {
      description: 'Disallow empty catch blocks that silently swallow errors',
      recommended: true,
    },
    messages: {
      emptyCatch: 'Empty catch block - handle or rethrow the error',
    },
    schema: [],
  },

  create(context) {
    return {
      CatchClause(node: Rule.Node & { body?: { body?: unknown[] } }) {
        if (node.body?.body?.length === 0) {
          context.report({
            node,
            messageId: 'emptyCatch',
          });
        }
      },
    };
  },
};

export default rule;
