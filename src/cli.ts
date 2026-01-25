/**
 * CLI entry point for vibe-check
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { resolveFiles, readFile, getExtension } from './utils/file-reader.js';
import { formatResults } from './utils/reporters.js';
import type {
  CheckOptions,
  CheckResult,
  SummaryResult,
  FileContext,
  Severity,
  HookResult,
} from './utils/types.js';
import { hooks, getHooksForFile } from './checks/index.js';

/**
 * Parse command line arguments
 */
function parseArgs(args: string[]): { files: string[]; options: CheckOptions } {
  const files: string[] = [];
  const options: CheckOptions = {
    format: 'pretty',
    failOn: 'error',
  };

  let i = 0;
  while (i < args.length) {
    const arg = args[i];

    if (arg === '--only' && args[i + 1]) {
      options.only = args[i + 1].split(',').map((s) => s.trim());
      i += 2;
    } else if (arg === '--skip' && args[i + 1]) {
      options.skip = args[i + 1].split(',').map((s) => s.trim());
      i += 2;
    } else if (arg === '--exclude' && args[i + 1]) {
      options.exclude = args[i + 1].split(',').map((s) => s.trim());
      i += 2;
    } else if (arg === '--format' && args[i + 1]) {
      const format = args[i + 1] as 'pretty' | 'json' | 'compact';
      if (['pretty', 'json', 'compact'].includes(format)) {
        options.format = format;
      }
      i += 2;
    } else if (arg === '--fail-on' && args[i + 1]) {
      const failOn = args[i + 1] as Severity | 'none';
      if (['error', 'warning', 'info', 'none'].includes(failOn)) {
        options.failOn = failOn === 'none' ? undefined : failOn;
      }
      i += 2;
    } else if (arg === '--fix') {
      options.fix = true;
      i += 1;
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else if (arg === '--version' || arg === '-v') {
      const pkg = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf-8'));
      console.log(`vibe-check ${pkg.version}`);
      process.exit(0);
    } else if (!arg.startsWith('-')) {
      files.push(arg);
      i += 1;
    } else {
      console.error(`Unknown option: ${arg}`);
      process.exit(2);
    }
  }

  return { files, options };
}

/**
 * Print help message
 */
function printHelp(): void {
  console.log(`
vibe-check - Catch common AI-generated code issues

Usage:
  vibe-check [options] <files...>

Options:
  --only <hooks>      Only run specified hooks (comma-separated)
  --skip <hooks>      Skip specified hooks (comma-separated)
  --exclude <globs>   Exclude file patterns (comma-separated globs)
  --format <format>   Output format: pretty, json, compact (default: pretty)
  --fail-on <level>   Fail on severity level: error, warning, info, none (default: error)
  --fix               Auto-fix issues where possible
  -h, --help          Show this help message
  -v, --version       Show version

Inline suppression:
  // noqa           Suppress all warnings on this line
  // noqa: debug    Suppress only debug warnings on this line
  # noqa: urls      Python-style suppression

Examples:
  vibe-check .
  vibe-check src/
  vibe-check --only secrets,urls .
  vibe-check --skip any-types,snake-case .
  vibe-check --exclude 'src/checks/**,tests/**' .
  vibe-check --format json .

Available hooks:
${hooks.map((h) => `  ${h.id.padEnd(20)} ${h.description}`).join('\n')}
`);
}

/**
 * Check a single file with applicable hooks
 */
function checkFile(filePath: string, options: CheckOptions): CheckResult {
  const extension = getExtension(filePath);
  const content = readFile(filePath);

  const context: FileContext = {
    filePath,
    content,
    extension,
  };

  // Get hooks for this file type
  let applicableHooks = getHooksForFile(extension);

  // Filter by --only
  if (options.only && options.only.length > 0) {
    applicableHooks = applicableHooks.filter((h) => options.only!.includes(h.id));
  }

  // Filter by --skip
  if (options.skip && options.skip.length > 0) {
    applicableHooks = applicableHooks.filter((h) => !options.skip!.includes(h.id));
  }

  // Run all applicable hooks
  const issues: HookResult[] = [];
  for (const hook of applicableHooks) {
    try {
      const hookIssues = hook.check(context);
      issues.push(...hookIssues);
    } catch (error) {
      // Skip hooks that fail - don't crash the whole check
      console.error(`Warning: Hook "${hook.id}" failed on ${filePath}: ${error}`);
    }
  }

  // Sort issues by line number
  issues.sort((a, b) => a.line - b.line);

  return {
    filePath: path.relative(process.cwd(), filePath),
    issues,
  };
}

/**
 * Main vibe-check function
 */
export function vibeCheck(files: string[], options: CheckOptions = {}): SummaryResult {
  const resolvedFiles = resolveFiles(files, options.exclude);
  const results: CheckResult[] = [];

  for (const file of resolvedFiles) {
    const result = checkFile(file, options);
    results.push(result);
  }

  // Calculate summary
  let errorCount = 0;
  let warningCount = 0;
  let infoCount = 0;
  let filesWithIssues = 0;

  for (const result of results) {
    if (result.issues.length > 0) {
      filesWithIssues++;
    }
    for (const issue of result.issues) {
      switch (issue.severity) {
        case 'error':
          errorCount++;
          break;
        case 'warning':
          warningCount++;
          break;
        case 'info':
          infoCount++;
          break;
      }
    }
  }

  return {
    filesChecked: resolvedFiles.length,
    filesWithIssues,
    errorCount,
    warningCount,
    infoCount,
    results,
  };
}

/**
 * CLI main function
 */
export async function main(args: string[]): Promise<void> {
  const { files, options } = parseArgs(args);

  if (files.length === 0) {
    console.error('Error: No files specified. Use "vibe-check ." to check current directory.');
    process.exit(2);
  }

  const summary = vibeCheck(files, options);
  const output = formatResults(summary, options.format || 'pretty');

  console.log(output);

  // Determine exit code based on --fail-on
  // 'error' (0) = only fail on errors
  // 'warning' (1) = fail on errors or warnings
  // 'info' (2) = fail on errors, warnings, or info
  if (options.failOn) {
    const severityOrder: Severity[] = ['error', 'warning', 'info'];
    const failIndex = severityOrder.indexOf(options.failOn);

    let shouldFail = false;
    if (failIndex >= 0 && summary.errorCount > 0) shouldFail = true;
    if (failIndex >= 1 && summary.warningCount > 0) shouldFail = true;
    if (failIndex >= 2 && summary.infoCount > 0) shouldFail = true;

    if (shouldFail) {
      process.exit(1);
    }
  }

  process.exit(0);
}
