import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { join } from 'path'
import { mkdirSync, writeFileSync, readFileSync, rmSync, mkdtempSync } from 'fs'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..', '..')
const UTILS_SH = join(PROJECT_ROOT, 'ralph', 'utils.sh')

let testDir: string
let ralphDir: string

beforeEach(() => {
  testDir = mkdtempSync(join(tmpdir(), 'ralph-test-'))
  ralphDir = join(testDir, '.ralph')
  mkdirSync(ralphDir, { recursive: true })
})

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true })
})

function runMigration(configJson: Record<string, unknown>): Record<string, unknown> {
  writeFileSync(join(ralphDir, 'config.json'), JSON.stringify(configJson))

  const script = `
    export RALPH_DIR="${ralphDir}"
    source "${UTILS_SH}"
    _migrate_config
    cat "$RALPH_DIR/config.json"
  `

  const output = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
    cwd: PROJECT_ROOT,
    encoding: 'utf-8',
    env: { ...process.env, NO_COLOR: '1' }
  }).trim()

  return JSON.parse(output)
}

function readConfig(): Record<string, unknown> {
  return JSON.parse(readFileSync(join(ralphDir, 'config.json'), 'utf-8'))
}

describe('UAT-006: Config migration — testUrlBase to urls.frontend', () => {
  // Assertion 1: Config with testUrlBase='http://localhost:8000/api'
  // → urls.frontend='http://localhost:8000/api', testUrlBase removed
  it('migrates testUrlBase to urls.frontend and removes testUrlBase', () => {
    const result = runMigration({
      testUrlBase: 'http://localhost:8000/api',
      checks: { lint: true }
    })

    expect((result as any).urls.frontend).toBe('http://localhost:8000/api')
    expect(result).not.toHaveProperty('testUrlBase')
  })

  // Assertion 2: Config with both testUrlBase AND urls.frontend
  // → urls.frontend preserved (not overwritten), testUrlBase removed
  it('preserves existing urls.frontend when both fields present', () => {
    const result = runMigration({
      testUrlBase: 'http://host:8000',
      urls: { frontend: 'http://host:5173' }
    })

    expect((result as any).urls.frontend).toBe('http://host:5173')
    expect(result).not.toHaveProperty('testUrlBase')
  })

  // Assertion 3: Run migration twice on same config → same result, no data loss
  it('is idempotent — running twice produces the same result', () => {
    writeFileSync(
      join(ralphDir, 'config.json'),
      JSON.stringify({ testUrlBase: 'http://localhost:3000', checks: { lint: true } })
    )

    const script = `
      export RALPH_DIR="${ralphDir}"
      source "${UTILS_SH}"
      _migrate_config
      _migrate_config
      cat "$RALPH_DIR/config.json"
    `

    const output = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    const result = JSON.parse(output)
    expect((result as any).urls.frontend).toBe('http://localhost:3000')
    expect(result).not.toHaveProperty('testUrlBase')
    expect((result as any).checks.lint).toBe(true)
  })

  // Edge case: testUrlBase with special characters in URL
  it('handles testUrlBase with special characters in URL', () => {
    const result = runMigration({
      testUrlBase: 'http://localhost:8000/api/v2?token=abc&flag=1'
    })

    expect((result as any).urls.frontend).toBe('http://localhost:8000/api/v2?token=abc&flag=1')
    expect(result).not.toHaveProperty('testUrlBase')
  })

  // Edge case: testUrlBase with trailing slash
  it('handles testUrlBase with trailing slash', () => {
    const result = runMigration({
      testUrlBase: 'http://localhost:3000/'
    })

    expect((result as any).urls.frontend).toBe('http://localhost:3000/')
    expect(result).not.toHaveProperty('testUrlBase')
  })

  // Edge case: Config with empty string testUrlBase
  it('does not migrate empty string testUrlBase', () => {
    const result = runMigration({
      testUrlBase: '',
      checks: { lint: true }
    })

    // Empty string means legacy_url is empty, so no migration occurs
    // testUrlBase remains as-is (jq '.testUrlBase // empty' returns empty for "")
    expect(result).not.toHaveProperty('urls')
  })

  // Edge case: No testUrlBase at all — migration is a no-op
  it('is a no-op when no testUrlBase exists', () => {
    const original = {
      checks: { lint: true },
      urls: { frontend: 'http://localhost:5173' }
    }
    const result = runMigration(original)

    expect((result as any).urls.frontend).toBe('http://localhost:5173')
    expect((result as any).checks.lint).toBe(true)
  })

  // Edge case: No config file at all — returns 0 without error
  it('returns cleanly when no config file exists', () => {
    const script = `
      export RALPH_DIR="${ralphDir}"
      rm -f "$RALPH_DIR/config.json"
      source "${UTILS_SH}"
      _migrate_config
      echo "exit_code=$?"
    `

    const output = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(output).toContain('exit_code=0')
  })

  // Edge case: Config with both — verify other fields are preserved
  it('preserves all other config fields during migration', () => {
    const result = runMigration({
      testUrlBase: 'http://localhost:8000',
      checks: { lint: true, typecheck: true, build: 'final' },
      commands: { test: 'npm test' },
      quiet: false,
      maxIterations: 20
    })

    expect((result as any).urls.frontend).toBe('http://localhost:8000')
    expect(result).not.toHaveProperty('testUrlBase')
    expect((result as any).checks.lint).toBe(true)
    expect((result as any).checks.typecheck).toBe(true)
    expect((result as any).checks.build).toBe('final')
    expect((result as any).commands.test).toBe('npm test')
    expect((result as any).quiet).toBe(false)
    expect((result as any).maxIterations).toBe(20)
  })
})
