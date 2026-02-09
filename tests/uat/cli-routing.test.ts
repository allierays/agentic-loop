import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { join } from 'path'
import { mkdirSync, writeFileSync, rmSync, mkdtempSync, readFileSync } from 'fs'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..', '..')
const RALPH_SH = join(PROJECT_ROOT, 'bin', 'ralph.sh')

let testDir: string

beforeEach(() => {
  testDir = mkdtempSync(join(tmpdir(), 'ralph-test-'))
  // Create minimal .ralph structure so the script doesn't try to auto-detect
  mkdirSync(join(testDir, '.ralph', 'archive'), { recursive: true })
  mkdirSync(join(testDir, '.ralph', 'screenshots'), { recursive: true })
  writeFileSync(join(testDir, '.ralph', 'config.json'), JSON.stringify({ checks: {} }))
  writeFileSync(join(testDir, '.ralph', 'signs.json'), '{"signs": []}')
  writeFileSync(join(testDir, 'PROMPT.md'), '# Test')
  // Create package.json so version command works
  writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test', version: '0.0.0' }))
})

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true })
})

function runRalph(args: string, opts?: { expectFail?: boolean }): { stdout: string; stderr: string; exitCode: number } {
  try {
    const stdout = execSync(`bash "${RALPH_SH}" ${args}`, {
      cwd: testDir,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1', RALPH_DIR: join(testDir, '.ralph') }
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

describe('UAT-004: CLI command routing — unknown commands, no args, error handling', () => {
  // Assertion 1: bin/ralph.sh (no args) → Shows help text starting with 'agentic-loop - Tools to thrive'
  it('no arguments defaults to help text', () => {
    const { stdout, exitCode } = runRalph('')
    // Help text should contain the project tagline
    expect(stdout).toContain('agentic-loop')
    expect(stdout).toContain('Tools to thrive')
    expect(exitCode).toBe(0)
  })

  // Assertion 2: bin/ralph.sh nonexistent → Shows 'Error: Unknown command: nonexistent' and exits with code 1
  it('unknown command shows error message and exits with code 1', () => {
    const { stdout, stderr, exitCode } = runRalph('nonexistent')
    const combined = stdout + '\n' + stderr
    expect(combined).toContain('Unknown command: nonexistent')
    expect(exitCode).toBe(1)
  })

  // Assertion 3: bin/ralph.sh verify (no story-id) → Shows 'Usage: ralph verify <story-id>' and exits with code 1
  it('verify without story-id shows usage error and exits with code 1', () => {
    const { stdout, stderr, exitCode } = runRalph('verify')
    const combined = stdout + '\n' + stderr
    expect(combined).toContain('Usage: ralph verify <story-id>')
    expect(exitCode).toBe(1)
  })

  // Assertion 4: bin/ralph.sh --version → Output matches 'ralph X.Y.Z (agentic-loop)' format with valid semver
  it('--version outputs ralph X.Y.Z (agentic-loop) format with valid semver', () => {
    // Run from PROJECT_ROOT so it can find the real package.json
    const stdout = execSync(`bash "${RALPH_SH}" --version`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    // Should match format: ralph X.Y.Z (agentic-loop)
    expect(stdout).toMatch(/^ralph \d+\.\d+\.\d+ \(agentic-loop\)$/)
  })

  // Edge case: --help shows help
  it('--help shows help text', () => {
    const { stdout, exitCode } = runRalph('--help')
    expect(stdout).toContain('agentic-loop')
    expect(exitCode).toBe(0)
  })

  // Edge case: -h shows help
  it('-h shows help text', () => {
    const { stdout, exitCode } = runRalph('-h')
    expect(stdout).toContain('agentic-loop')
    expect(exitCode).toBe(0)
  })

  // Edge case: --version and -v both show version
  it('--version and -v produce the same output', () => {
    // Run both from PROJECT_ROOT to find real package.json
    const versionLong = execSync(`bash "${RALPH_SH}" --version`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    const versionShort = execSync(`bash "${RALPH_SH}" -v`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(versionLong).toBe(versionShort)
  })

  // Edge case: version (word) also works
  it('version command produces same output as --version', () => {
    const versionCmd = execSync(`bash "${RALPH_SH}" version`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(versionCmd).toMatch(/^ralph \d+\.\d+\.\d+ \(agentic-loop\)$/)
  })

  // Edge case: unknown command still shows help text after error
  it('unknown command shows help text along with the error', () => {
    const { stdout, stderr } = runRalph('nonexistent')
    const combined = stdout + '\n' + stderr
    // Should show error AND help text
    expect(combined).toContain('Unknown command: nonexistent')
    // Help text should follow the error
    expect(combined).toContain('agentic-loop')
  })

  // Edge case: special characters in command name
  it('special characters in command name are handled safely', () => {
    const { exitCode } = runRalph('"foo bar"')
    expect(exitCode).toBe(1)
  })

  // Edge case: help command (word) works
  it('help command shows help text', () => {
    const { stdout, exitCode } = runRalph('help')
    expect(stdout).toContain('agentic-loop')
    expect(stdout).toContain('Tools to thrive')
    expect(exitCode).toBe(0)
  })

  // Edge case: version output matches package.json exactly
  it('version matches package.json version', () => {
    const pkgJson = JSON.parse(readFileSync(join(PROJECT_ROOT, 'package.json'), 'utf-8'))
    const expectedVersion = pkgJson.version

    const stdout = execSync(`bash "${RALPH_SH}" version`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(stdout).toBe(`ralph ${expectedVersion} (agentic-loop)`)
  })
})
