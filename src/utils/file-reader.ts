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
 * Simple glob pattern matching
 * Supports: * (any chars), ** (any path), ? (single char)
 */
function matchesGlob(filePath: string, pattern: string): boolean {
  // Normalize path separators
  const normalizedPath = filePath.replace(/\\/g, '/');
  const normalizedPattern = pattern.replace(/\\/g, '/');

  // Convert glob to regex
  const regexPattern = normalizedPattern
    .replace(/[.+^${}()|[\]\\]/g, '\\$&') // Escape special regex chars
    .replace(/\*\*/g, '<<<GLOBSTAR>>>') // Temp placeholder for **
    .replace(/\*/g, '[^/]*') // * = any chars except /
    .replace(/\?/g, '.') // ? = single char
    .replace(/<<<GLOBSTAR>>>/g, '.*'); // ** = any chars including /

  const regex = new RegExp(`^${regexPattern}$|/${regexPattern}$|^${regexPattern}/|/${regexPattern}/`);
  return regex.test(normalizedPath);
}

/**
 * Check if file matches any exclude pattern
 */
function isExcluded(filePath: string, excludePatterns: string[]): boolean {
  const relativePath = path.relative(process.cwd(), filePath);
  return excludePatterns.some((pattern) => matchesGlob(relativePath, pattern));
}

/**
 * Resolve input paths to a list of files
 */
export function resolveFiles(inputs: string[], excludePatterns: string[] = []): string[] {
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

  // Apply exclude patterns
  const filtered = excludePatterns.length > 0 ? files.filter((f) => !isExcluded(f, excludePatterns)) : files;

  return [...new Set(filtered)]; // Deduplicate
}

// Max file size to read (10MB) - prevents OOM on huge files
const MAX_FILE_SIZE = 10 * 1024 * 1024;

/**
 * Read file content (with size limit to prevent OOM)
 */
export function readFile(filePath: string): string {
  const stats = fs.statSync(filePath);
  if (stats.size > MAX_FILE_SIZE) {
    throw new Error(`File too large (${Math.round(stats.size / 1024 / 1024)}MB > 10MB limit): ${filePath}`);
  }
  return fs.readFileSync(filePath, 'utf-8');
}
