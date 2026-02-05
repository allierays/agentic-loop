import { describe, it, expect, beforeEach, afterAll } from 'vitest'
import { execSync } from 'child_process'
import { mkdirSync, rmSync, writeFileSync, readFileSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..')

/**
 * Helper: run _migrate_config against a temp .ralph directory
 */
function runMigration(ralphDir: string): void {
  const script = `
    export RALPH_DIR="${ralphDir}"
    source "${PROJECT_ROOT}/ralph/utils.sh"
    _migrate_config
  `
  execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
    encoding: 'utf-8',
    env: { ...process.env, NO_COLOR: '1' }
  })
}

function readConfig(ralphDir: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(ralphDir, 'config.json'), 'utf-8'))
}

describe('_migrate_config', () => {
  let testDir: string

  beforeEach(() => {
    testDir = join(tmpdir(), `ralph-migrate-test-${Date.now()}`)
    mkdirSync(testDir, { recursive: true })
  })

  afterAll(() => {
    // Clean up any lingering test dirs
    rmSync(testDir, { recursive: true, force: true })
  })

  it('migrates testUrlBase to urls.frontend', () => {
    writeFileSync(
      join(testDir, 'config.json'),
      JSON.stringify({ testUrlBase: 'http://localhost:8000' })
    )

    runMigration(testDir)
    const config = readConfig(testDir)

    expect((config.urls as Record<string, string>).frontend).toBe('http://localhost:8000')
    expect(config.testUrlBase).toBeUndefined()
  })

  it('does not overwrite existing urls.frontend', () => {
    writeFileSync(
      join(testDir, 'config.json'),
      JSON.stringify({
        testUrlBase: 'http://localhost:3000',
        urls: { frontend: 'http://localhost:5173' }
      })
    )

    runMigration(testDir)
    const config = readConfig(testDir)

    expect((config.urls as Record<string, string>).frontend).toBe('http://localhost:5173')
    expect(config.testUrlBase).toBeUndefined()
  })

  it('is idempotent — safe to run multiple times', () => {
    writeFileSync(
      join(testDir, 'config.json'),
      JSON.stringify({ testUrlBase: 'http://localhost:8000' })
    )

    runMigration(testDir)
    runMigration(testDir)
    const config = readConfig(testDir)

    expect((config.urls as Record<string, string>).frontend).toBe('http://localhost:8000')
    expect(config.testUrlBase).toBeUndefined()
  })

  it('does nothing when no testUrlBase exists', () => {
    writeFileSync(
      join(testDir, 'config.json'),
      JSON.stringify({ urls: { frontend: 'http://localhost:3000' }, checks: { lint: 'npm run lint' } })
    )

    runMigration(testDir)
    const config = readConfig(testDir)

    expect((config.urls as Record<string, string>).frontend).toBe('http://localhost:3000')
    expect(config.checks).toEqual({ lint: 'npm run lint' })
  })

  it('does nothing when config file is missing', () => {
    // No config.json created — should not throw
    expect(() => runMigration(testDir)).not.toThrow()
  })
})
