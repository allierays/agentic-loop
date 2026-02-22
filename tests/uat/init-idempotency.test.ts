import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { join } from 'path'
import { mkdirSync, writeFileSync, rmSync, mkdtempSync, readFileSync, existsSync, statSync } from 'fs'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..', '..')
const RALPH_SH = join(PROJECT_ROOT, 'bin', 'ralph.sh')

let testDir: string

beforeEach(() => {
  testDir = mkdtempSync(join(tmpdir(), 'ralph-test-'))
})

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true })
})

function runRalph(args: string, opts?: { expectFail?: boolean }): { stdout: string; stderr: string; exitCode: number } {
  try {
    const stdout = execSync(`bash "${RALPH_SH}" ${args}`, {
      cwd: testDir,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1', RALPH_DIR: join(testDir, '.ralph') },
      timeout: 30000
    }).trim()
    return { stdout, stderr: '', exitCode: 0 }
  } catch (e: any) {
    return {
      stdout: (e.stdout || '').trim(),
      stderr: (e.stderr || '').trim(),
      exitCode: e.status ?? 1
    }
  }
}

describe('UAT-005: Init idempotency — safe to run twice, file preservation', () => {
  // Assertion 1: ralph init in empty directory creates all expected files
  it('first init creates .ralph/config.json, .ralph/lessons.json, .ralph/progress.txt, PROMPT.md', () => {
    const { exitCode } = runRalph('init')

    expect(existsSync(join(testDir, '.ralph', 'config.json'))).toBe(true)
    expect(existsSync(join(testDir, '.ralph', 'lessons.json'))).toBe(true)
    expect(existsSync(join(testDir, '.ralph', 'progress.txt'))).toBe(true)
    expect(existsSync(join(testDir, 'PROMPT.md'))).toBe(true)
    expect(exitCode).toBe(0)
  })

  // Assertion 1 (structural): config.json should be valid JSON
  it('first init creates valid JSON config.json', () => {
    runRalph('init')

    const configContent = readFileSync(join(testDir, '.ralph', 'config.json'), 'utf-8')
    expect(() => JSON.parse(configContent)).not.toThrow()
  })

  // Assertion 1 (structural): lessons.json should be valid JSON with lessons array
  it('first init creates valid lessons.json with lessons array', () => {
    runRalph('init')

    const lessonsContent = readFileSync(join(testDir, '.ralph', 'lessons.json'), 'utf-8')
    const lessons = JSON.parse(lessonsContent)
    expect(lessons).toHaveProperty('lessons')
    expect(Array.isArray(lessons.lessons)).toBe(true)
  })

  // Assertion 1 (structural): progress.txt should contain INIT entry
  it('first init creates progress.txt with INIT entry', () => {
    runRalph('init')

    const progressContent = readFileSync(join(testDir, '.ralph', 'progress.txt'), 'utf-8')
    expect(progressContent).toContain('INIT')
  })

  // Assertion 2: ralph init in already-initialized directory says "already initialized"
  it('second init says "already initialized" and does not modify files', () => {
    // First init
    runRalph('init')

    // Record file contents after first init
    const configAfterFirst = readFileSync(join(testDir, '.ralph', 'config.json'), 'utf-8')
    const lessonsAfterFirst = readFileSync(join(testDir, '.ralph', 'lessons.json'), 'utf-8')
    const progressAfterFirst = readFileSync(join(testDir, '.ralph', 'progress.txt'), 'utf-8')
    const promptAfterFirst = readFileSync(join(testDir, 'PROMPT.md'), 'utf-8')

    // Second init
    const { stdout, exitCode } = runRalph('init')

    // Should say "already initialized"
    expect(stdout).toContain('already initialized')
    expect(exitCode).toBe(0)

    // Files should not be modified
    const configAfterSecond = readFileSync(join(testDir, '.ralph', 'config.json'), 'utf-8')
    const lessonsAfterSecond = readFileSync(join(testDir, '.ralph', 'lessons.json'), 'utf-8')
    const progressAfterSecond = readFileSync(join(testDir, '.ralph', 'progress.txt'), 'utf-8')
    const promptAfterSecond = readFileSync(join(testDir, 'PROMPT.md'), 'utf-8')

    expect(configAfterSecond).toBe(configAfterFirst)
    expect(lessonsAfterSecond).toBe(lessonsAfterFirst)
    expect(progressAfterSecond).toBe(progressAfterFirst)
    expect(promptAfterSecond).toBe(promptAfterFirst)
  })

  // Assertion 3: Modified lessons.json content is preserved on re-init
  it('modified lessons.json content is preserved after re-init', () => {
    // First init
    runRalph('init')

    // Modify lessons.json with custom content
    const customLessons = {
      lessons: [
        { pattern: 'Always use camelCase', category: 'frontend', addedAt: '2026-01-01' }
      ]
    }
    writeFileSync(join(testDir, '.ralph', 'lessons.json'), JSON.stringify(customLessons, null, 2))

    // Second init
    runRalph('init')

    // Custom lessons.json should be preserved
    const lessonsContent = readFileSync(join(testDir, '.ralph', 'lessons.json'), 'utf-8')
    const lessons = JSON.parse(lessonsContent)
    expect(lessons.lessons).toHaveLength(1)
    expect(lessons.lessons[0].pattern).toBe('Always use camelCase')
    expect(lessons.lessons[0].category).toBe('frontend')
  })

  // Edge case: Existing config.json is not overwritten
  it('existing config.json is not overwritten on re-init', () => {
    // First init
    runRalph('init')

    // Modify config.json with custom values
    const config = JSON.parse(readFileSync(join(testDir, '.ralph', 'config.json'), 'utf-8'))
    config.customKey = 'custom-value'
    config.maxIterations = 42
    writeFileSync(join(testDir, '.ralph', 'config.json'), JSON.stringify(config, null, 2))

    // Second init
    runRalph('init')

    // Custom config should be preserved
    const configAfter = JSON.parse(readFileSync(join(testDir, '.ralph', 'config.json'), 'utf-8'))
    expect(configAfter.customKey).toBe('custom-value')
    expect(configAfter.maxIterations).toBe(42)
  })

  // Edge case: Custom PROMPT.md content is preserved
  it('custom PROMPT.md content is preserved on re-init', () => {
    // First init
    runRalph('init')

    // Write custom content to PROMPT.md
    const customPrompt = '# My Custom Prompt\n\nThis is my custom prompt content.\n'
    writeFileSync(join(testDir, 'PROMPT.md'), customPrompt)

    // Second init
    runRalph('init')

    // Custom PROMPT.md should be preserved
    const promptContent = readFileSync(join(testDir, 'PROMPT.md'), 'utf-8')
    expect(promptContent).toBe(customPrompt)
  })

  // Edge case: progress.txt is not reset on re-init
  it('progress.txt is not reset on re-init', () => {
    // First init
    runRalph('init')

    // Append custom progress entries
    const progressPath = join(testDir, '.ralph', 'progress.txt')
    const originalContent = readFileSync(progressPath, 'utf-8')
    const customEntry = '[2026-01-15T10:00:00] TASK-001 PASS custom test entry\n'
    writeFileSync(progressPath, originalContent + customEntry)

    // Second init
    runRalph('init')

    // progress.txt should retain all entries including custom one
    const progressAfter = readFileSync(progressPath, 'utf-8')
    expect(progressAfter).toContain('INIT')
    expect(progressAfter).toContain('custom test entry')
    expect(progressAfter).toContain('TASK-001')
  })

  // Edge case: directory structure (archive, screenshots) created on first init
  it('creates archive and screenshots subdirectories', () => {
    runRalph('init')

    expect(existsSync(join(testDir, '.ralph', 'archive'))).toBe(true)
    expect(existsSync(join(testDir, '.ralph', 'screenshots'))).toBe(true)
  })
})
