/**
 * Output formatters for CLI results
 */

import type { SummaryResult, Severity } from './types.js';

// ANSI color codes
const colors = {
  reset: '\x1b[0m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  gray: '\x1b[90m',
};

function severityColor(severity: Severity): string {
  switch (severity) {
    case 'error':
      return colors.red;
    case 'warning':
      return colors.yellow;
    case 'info':
      return colors.blue;
  }
}

function severityIcon(severity: Severity): string {
  switch (severity) {
    case 'error':
      return '✖';
    case 'warning':
      return '⚠';
    case 'info':
      return 'ℹ';
  }
}

/**
 * Pretty format - colored terminal output
 */
export function formatPretty(summary: SummaryResult): string {
  const lines: string[] = [];

  // Header
  lines.push('');
  lines.push(`${colors.bold}vibe-check${colors.reset}`);
  lines.push('');

  // Results by file
  for (const result of summary.results) {
    if (result.issues.length === 0) continue;

    lines.push(`${colors.cyan}${result.filePath}${colors.reset}`);

    for (const issue of result.issues) {
      const color = severityColor(issue.severity);
      const icon = severityIcon(issue.severity);
      const location = issue.column
        ? `${issue.line}:${issue.column}`
        : `${issue.line}`;

      lines.push(
        `  ${colors.gray}${location.padEnd(8)}${colors.reset}` +
          `${color}${icon}${colors.reset} ` +
          `${issue.message}  ${colors.dim}${issue.ruleId}${colors.reset}`
      );
    }

    lines.push('');
  }

  // Summary
  const problems: string[] = [];
  if (summary.errorCount > 0) {
    problems.push(`${colors.red}${summary.errorCount} error${summary.errorCount === 1 ? '' : 's'}${colors.reset}`);
  }
  if (summary.warningCount > 0) {
    problems.push(`${colors.yellow}${summary.warningCount} warning${summary.warningCount === 1 ? '' : 's'}${colors.reset}`);
  }
  if (summary.infoCount > 0) {
    problems.push(`${colors.blue}${summary.infoCount} info${colors.reset}`);
  }

  if (problems.length > 0) {
    lines.push(`${problems.join(', ')} in ${summary.filesWithIssues} file${summary.filesWithIssues === 1 ? '' : 's'}`);
  } else {
    lines.push(`${colors.bold}✓${colors.reset} ${summary.filesChecked} file${summary.filesChecked === 1 ? '' : 's'} checked - no issues found`);
  }

  lines.push('');

  return lines.join('\n');
}

/**
 * JSON format - machine-readable output
 */
export function formatJson(summary: SummaryResult): string {
  return JSON.stringify(summary, null, 2);
}

/**
 * Compact format - one line per issue
 */
export function formatCompact(summary: SummaryResult): string {
  const lines: string[] = [];

  for (const result of summary.results) {
    for (const issue of result.issues) {
      const location = issue.column
        ? `${issue.line}:${issue.column}`
        : `${issue.line}`;

      lines.push(
        `${result.filePath}:${location}: ${issue.severity}: ${issue.message} [${issue.ruleId}]`
      );
    }
  }

  return lines.join('\n');
}

/**
 * Format results based on output format option
 */
export function formatResults(
  summary: SummaryResult,
  format: 'pretty' | 'json' | 'compact'
): string {
  switch (format) {
    case 'pretty':
      return formatPretty(summary);
    case 'json':
      return formatJson(summary);
    case 'compact':
      return formatCompact(summary);
  }
}
