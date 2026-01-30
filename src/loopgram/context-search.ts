import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';
import { join, relative } from 'path';
import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic();

interface SearchResult {
  file: string;
  matches: string[];
}

/**
 * Use AI to generate smart search terms for a topic
 */
async function generateSearchTerms(topic: string, model: string): Promise<string[]> {
  const response = await anthropic.messages.create({
    model,
    max_tokens: 200,
    system: `You generate search terms for code search. Given a topic, output 5-8 relevant keywords/patterns to search for in a codebase. Output ONLY the terms, one per line, no explanations. Include variations (e.g., "auth", "authenticate", "authentication").`,
    messages: [
      { role: 'user', content: `Topic: ${topic}` },
    ],
  });

  const text = response.content[0];
  if (text.type !== 'text') return [topic];

  const terms = text.text
    .split('\n')
    .map(t => t.trim().toLowerCase())
    .filter(t => t.length > 0 && t.length < 30);

  // Always include the original topic
  if (!terms.includes(topic.toLowerCase())) {
    terms.unshift(topic.toLowerCase());
  }

  return terms.slice(0, 8);
}

/**
 * Search a project for files related to a topic using ripgrep
 */
export function searchProject(projectPath: string, topic: string): SearchResult[] {
  const results: SearchResult[] = [];

  try {
    // Use ripgrep to find matching files (case insensitive)
    // Escape special regex characters in topic
    const escapedTopic = topic.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    // Use grep instead of rg for compatibility
    const cmd = `grep -r -i -l "${escapedTopic}" "${projectPath}" --include="*.py" --include="*.ts" --include="*.js" --include="*.md" --include="*.json" --include="*.sh" 2>/dev/null | grep -v node_modules | grep -v __pycache__ | grep -v ".git" | head -20 || true`;
    console.log(`[search] Running: ${cmd}`);

    const rgOutput = execSync(cmd, {
      encoding: 'utf-8',
      maxBuffer: 1024 * 1024,
      shell: '/bin/zsh'
    }).trim();
    console.log(`[search] Found ${rgOutput ? rgOutput.split('\n').length : 0} files for "${topic}"`);

    if (!rgOutput) {
      return results;
    }

    const files = rgOutput.split('\n').filter(Boolean);

    for (const file of files.slice(0, 10)) { // Limit to 10 files
      try {
        // Get matching lines with context
        const matchOutput = execSync(
          `rg -i -C 2 "${topic}" "${file}" 2>/dev/null | head -30`,
          { encoding: 'utf-8', maxBuffer: 1024 * 1024 }
        ).trim();

        results.push({
          file: relative(projectPath, file),
          matches: matchOutput ? [matchOutput] : [],
        });
      } catch {
        // File might not have readable matches
        results.push({ file: relative(projectPath, file), matches: [] });
      }
    }
  } catch (error) {
    // ripgrep not found or no matches
    console.error('Search error:', error);
  }

  return results;
}

/**
 * Read key project files for additional context
 */
export function readProjectFiles(projectPath: string): string {
  const contextFiles = [
    'CLAUDE.md',
    'README.md',
    'package.json',
    'pyproject.toml',
  ];

  let context = '';

  for (const file of contextFiles) {
    const filePath = join(projectPath, file);
    if (existsSync(filePath)) {
      try {
        const content = readFileSync(filePath, 'utf-8');
        // Truncate large files
        const truncated = content.length > 2000
          ? content.substring(0, 2000) + '\n...[truncated]'
          : content;
        context += `\n### ${file}\n${truncated}\n`;
      } catch {
        // Skip unreadable files
      }
    }
  }

  return context;
}

/**
 * Generate a summary of search results using Claude
 */
export async function generateContextSummary(
  projectName: string,
  topic: string,
  searchResults: SearchResult[],
  projectContext: string,
  model: string
): Promise<string> {
  if (searchResults.length === 0) {
    return `No code found related to "${topic}" in ${projectName}. This might be a new area to build.`;
  }

  // Build the content to summarize
  let content = `Project: ${projectName}\nTopic: ${topic}\n\n`;
  content += `## Project Context\n${projectContext}\n\n`;
  content += `## Search Results\n`;

  for (const result of searchResults) {
    content += `\n### ${result.file}\n`;
    if (result.matches.length > 0) {
      content += '```\n' + result.matches.join('\n---\n') + '\n```\n';
    }
  }

  const response = await anthropic.messages.create({
    model,
    max_tokens: 800,
    system: `You are summarizing code search results to provide context for brainstorming.
Be concise but thorough. Focus on:
- What exists related to this topic
- Key patterns and approaches used
- Important files/functions
- Potential extension points

Keep the summary under 500 words.`,
    messages: [
      {
        role: 'user',
        content: `Summarize what exists in this codebase related to "${topic}":\n\n${content}`,
      },
    ],
  });

  const text = response.content[0];
  return text.type === 'text' ? text.text : 'Unable to generate summary.';
}

/**
 * Search project and generate context for brainstorming
 */
export async function getTopicContext(
  projectPath: string,
  projectName: string,
  topic: string,
  model: string
): Promise<{ summary: string; filesFound: string[]; searchTerms: string[] }> {
  // Use AI to generate smart search terms
  console.log(`[context] Generating search terms for: ${topic}`);
  const searchTerms = await generateSearchTerms(topic, model);
  console.log(`[context] Search terms: ${searchTerms.join(', ')}`);

  // Search for each term and combine results
  const allResults = new Map<string, SearchResult>();

  for (const term of searchTerms) {
    const results = searchProject(projectPath, term);
    for (const result of results) {
      // Dedupe by file path, merge matches
      if (allResults.has(result.file)) {
        const existing = allResults.get(result.file)!;
        existing.matches.push(...result.matches);
      } else {
        allResults.set(result.file, result);
      }
    }
  }

  const searchResults = Array.from(allResults.values()).slice(0, 15);

  // Get basic project context
  const projectContext = readProjectFiles(projectPath);

  // Generate summary
  const summary = await generateContextSummary(
    projectName,
    topic,
    searchResults,
    projectContext,
    model
  );

  return {
    summary,
    filesFound: searchResults.map((r) => r.file),
    searchTerms,
  };
}
