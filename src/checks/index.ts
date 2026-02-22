/**
 * Hook registry - exports all available hooks
 */

import type { Hook } from '../utils/types.js';

// Import all hooks
import { checkSecrets } from './check-secrets.js';
import { checkHardcodedUrls } from './check-hardcoded-urls.js';
import { checkDebugStatements } from './check-debug-statements.js';
import { checkTodoFixme } from './check-todo-fixme.js';
import { checkEmptyCatch } from './check-empty-catch.js';
import { checkDryViolations } from './check-dry-violations.js';
import { checkMagicNumbers } from './check-magic-numbers.js';
import { checkFunctionLength } from './check-function-length.js';
import { checkCommentedCode } from './check-commented-code.js';
import { checkDeepNesting } from './check-deep-nesting.js';
import { checkConsoleError } from './check-console-error.js';
import { checkAnyTypes } from './check-any-types.js';
import { checkSnakeCaseTs } from './check-snake-case-ts.js';
import { checkUnsafeHtml } from './check-unsafe-html.js';
import { checkDockerPlatform } from './check-docker-platform.js';
import { checkHardcodedAiModels } from './check-hardcoded-ai-models.js';
import { checkLessonsSecrets } from './check-lessons-secrets.js';

/** All available hooks */
export const hooks: Hook[] = [
  // Security (blocking)
  checkSecrets,
  checkHardcodedUrls,
  checkUnsafeHtml,

  // Code quality (warnings)
  checkDebugStatements,
  checkTodoFixme,
  checkEmptyCatch,
  checkDryViolations,
  checkMagicNumbers,
  checkFunctionLength,
  checkCommentedCode,
  checkDeepNesting,
  checkConsoleError,
  checkAnyTypes,
  checkSnakeCaseTs,

  // Infrastructure
  checkDockerPlatform,

  // AI/LLM
  checkHardcodedAiModels,

  // Lessons
  checkLessonsSecrets,
];

/** Get hooks filtered by file extension */
export function getHooksForFile(extension: string): Hook[] {
  return hooks.filter((hook) => hook.fileTypes.includes(extension));
}

export {
  checkSecrets,
  checkHardcodedUrls,
  checkDebugStatements,
  checkTodoFixme,
  checkEmptyCatch,
  checkDryViolations,
  checkMagicNumbers,
  checkFunctionLength,
  checkCommentedCode,
  checkDeepNesting,
  checkConsoleError,
  checkAnyTypes,
  checkSnakeCaseTs,
  checkUnsafeHtml,
  checkDockerPlatform,
  checkHardcodedAiModels,
  checkLessonsSecrets,
};
