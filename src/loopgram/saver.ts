import { writeFileSync, mkdirSync, existsSync } from 'fs';
import { join } from 'path';

/**
 * Save a brainstorming idea to docs/ideas/ in the specified project
 */
export function saveIdea(
  projectPath: string,
  filename: string,
  content: string
): string {
  const ideasDir = join(projectPath, 'docs/ideas');

  // Ensure directory exists
  if (!existsSync(ideasDir)) {
    mkdirSync(ideasDir, { recursive: true });
  }

  const filepath = join(ideasDir, `${filename}.md`);

  // Add metadata header
  const fullContent = `---
created: ${new Date().toISOString()}
source: telegram-brainstorm
status: idea
---

${content}
`;

  writeFileSync(filepath, fullContent);
  return filepath;
}

/**
 * Generate a filename-safe slug from a title
 */
export function slugify(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 50);
}
