/**
 * Shared types for agentic-loop
 */

export type Severity = 'error' | 'warning' | 'info';

export interface FileContext {
  /** Absolute path to the file */
  filePath: string;
  /** File content as string */
  content: string;
  /** File extension without dot (e.g., 'ts', 'py') */
  extension: string;
}

export interface HookResult {
  /** 1-based line number */
  line: number;
  /** 0-based column number */
  column?: number;
  /** Human-readable message */
  message: string;
  /** Severity level */
  severity: Severity;
  /** Rule identifier (e.g., 'secrets/aws-key') */
  ruleId: string;
  /** Optional fix suggestion */
  fix?: string;
}

export interface Hook {
  /** Unique identifier (e.g., 'secrets', 'debug-statements') */
  id: string;
  /** Human-readable name */
  name: string;
  /** Description of what this hook checks */
  description: string;
  /** Default severity level */
  severity: Severity;
  /** File extensions this hook applies to (without dots) */
  fileTypes: string[];
  /** Check function that returns issues found */
  check: (context: FileContext) => HookResult[];
}

export interface CheckOptions {
  /** Only run these hooks (by id) */
  only?: string[];
  /** Skip these hooks (by id) */
  skip?: string[];
  /** Minimum severity to fail on */
  failOn?: Severity;
  /** Output format */
  format?: 'pretty' | 'json' | 'compact';
  /** Auto-fix issues where possible */
  fix?: boolean;
}

export interface CheckResult {
  /** File path */
  filePath: string;
  /** All issues found in this file */
  issues: HookResult[];
}

export interface SummaryResult {
  /** Total files checked */
  filesChecked: number;
  /** Files with issues */
  filesWithIssues: number;
  /** Total issues by severity */
  errorCount: number;
  warningCount: number;
  infoCount: number;
  /** All results */
  results: CheckResult[];
}
