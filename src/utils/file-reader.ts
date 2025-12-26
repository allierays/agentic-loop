/**
 * File discovery and reading utilities
 */

import * as fs from 'node:fs';
import * as path from 'node:path';

/** Directories to always skip */
const SKIP_DIRS = new Set([
  'node_modules',
  '.git',
  '__pycache__',
  '.venv',
  'venv',
  'env',
  'dist',
  'build',
  '.next',
  '.nuxt',
  'coverage',
  '.pytest_cache',
  '.mypy_cache',
  '.tox',
  'egg-info',
  '.eggs',
]);

/** File extensions to check */
const SUPPORTED_EXTENSIONS = new Set([
  // JavaScript/TypeScript
  'js',
  'jsx',
  'ts',
  'tsx',
  'mjs',
  'cjs',
  'mts',
  'cts',
  // Python
  'py',
  'pyw',
  // Config/Data
  'json',
  'jsonc',
  'yaml',
  'yml',
  'toml',
  // Web
  'html',
  'htm',
  // Docker
  'dockerfile',
  // Other
  'env',
  'env.local',
  'env.development',
  'env.production',
]);

/**
 * Check if a file should be processed based on extension
 */
export function shouldProcessFile(filePath: string): boolean {
  const basename = path.basename(filePath).toLowerCase();

  // Handle Dockerfile (no extension)
  if (basename === 'dockerfile' || basename.startsWith('dockerfile.')) {
    return true;
  }

  // Handle .env files
  if (basename.startsWith('.env')) {
    return true;
  }

  const ext = path.extname(filePath).slice(1).toLowerCase();
  return SUPPORTED_EXTENSIONS.has(ext);
}

/**
 * Get file extension (handles special cases like Dockerfile)
 */
export function getExtension(filePath: string): string {
  const basename = path.basename(filePath).toLowerCase();

  if (basename === 'dockerfile' || basename.startsWith('dockerfile.')) {
    return 'dockerfile';
  }

  if (basename.startsWith('.env')) {
    return 'env';
  }

  return path.extname(filePath).slice(1).toLowerCase();
}

/**
 * Recursively discover files in a directory
 */
export function discoverFiles(dirPath: string): string[] {
  const files: string[] = [];

  function walk(currentPath: string): void {
    const entries = fs.readdirSync(currentPath, { withFileTypes: true });

    for (const entry of entries) {
      const fullPath = path.join(currentPath, entry.name);

      if (entry.isDirectory()) {
        // Skip excluded directories
        if (SKIP_DIRS.has(entry.name) || entry.name.startsWith('.')) {
          continue;
        }
        walk(fullPath);
      } else if (entry.isFile()) {
        if (shouldProcessFile(fullPath)) {
          files.push(fullPath);
        }
      }
    }
  }

  walk(dirPath);
  return files;
}

/**
 * Resolve input paths to a list of files
 */
export function resolveFiles(inputs: string[]): string[] {
  const files: string[] = [];

  for (const input of inputs) {
    const resolvedPath = path.resolve(input);

    if (!fs.existsSync(resolvedPath)) {
      console.error(`Warning: Path does not exist: ${input}`);
      continue;
    }

    const stat = fs.statSync(resolvedPath);

    if (stat.isDirectory()) {
      files.push(...discoverFiles(resolvedPath));
    } else if (stat.isFile()) {
      if (shouldProcessFile(resolvedPath)) {
        files.push(resolvedPath);
      }
    }
  }

  return [...new Set(files)]; // Deduplicate
}

/**
 * Read file content
 */
export function readFile(filePath: string): string {
  return fs.readFileSync(filePath, 'utf-8');
}
