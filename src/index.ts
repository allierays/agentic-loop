/**
 * vibe-and-thrive
 *
 * Catch common AI-generated code issues before they hit your codebase.
 */

// Export types
export type {
  Hook,
  HookResult,
  FileContext,
  CheckOptions,
  CheckResult,
  SummaryResult,
  Severity,
} from './utils/types.js';

// Export hooks
export {
  hooks,
  getHook,
  getHooksForFile,
  getHookIds,
} from './checks/index.js';

// Export main check function
export { vibeCheck } from './cli.js';
