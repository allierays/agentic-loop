#!/usr/bin/env node

/**
 * vibe-check CLI
 *
 * Usage:
 *   npx vibe-check .
 *   npx vibe-check src/app.ts
 *   npx vibe-check . --only secrets,urls
 *   npx vibe-check . --skip any-types
 *   npx vibe-check . --format json
 */

import { main } from '../dist/cli.js';

main(process.argv.slice(2)).catch((error) => {
  console.error('Fatal error:', error.message);
  process.exit(2);
});
