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
  /** File patterns to exclude (glob patterns) */
  exclude?: string[];
  /** Minimum severity to fail on */
  failOn?: Severity;
  /** Output format */
  format?: 'pretty' | 'json' | 'compact';
  /** Auto-fix issues where possible */
  fix?: boolean;
}

/**
 * Check if a line should be ignored due to noqa comment
 * Supports: // noqa, // noqa: rule, # noqa, # noqa: rule
 */
export function shouldIgnoreLine(line: string, ruleId?: string): boolean {
  // Match // noqa or # noqa with optional rule specification
  const noqaMatch = line.match(/(?:\/\/|#)\s*noqa(?::\s*([a-z0-9_,-]+))?/i);
  if (!noqaMatch) return false;

  // If no specific rule in comment, ignore all rules
  if (!noqaMatch[1]) return true;

  // If rule specified, check if current rule matches
  if (ruleId) {
    const rules = noqaMatch[1].split(',').map((r) => r.trim().toLowerCase());
    const ruleBase = ruleId.split('/')[0].toLowerCase(); // e.g., 'debug' from 'debug/console'
    return rules.includes(ruleBase) || rules.includes(ruleId.toLowerCase());
  }

  return true;
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
