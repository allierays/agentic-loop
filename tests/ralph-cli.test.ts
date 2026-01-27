import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { execSync, exec } from 'child_process'
import { existsSync, mkdirSync, rmSync, readFileSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const RALPH_BIN = join(__dirname, '..', 'bin', 'ralph.sh')
const TEMPLATES_DIR = join(__dirname, '..', 'templates')

// Helper to run ralph commands
function ralph(args: string, cwd?: string): string {
  try {
    return execSync(`${RALPH_BIN} ${args}`, {
      cwd: cwd || process.cwd(),
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    })
  } catch (e: any) {
    return e.stdout || e.stderr || e.message
  }
}

describe('ralph CLI', () => {
  describe('help command', () => {
    it('shows help text', () => {
      const output = ralph('help')
      expect(output).toContain('agentic-loop - Tools to thrive with agentic coding')
      expect(output).toContain('Commands:')
      expect(output).toContain('init')
      expect(output).toContain('run')
      expect(output).toContain('status')
    })

    it('shows help with --help flag', () => {
      const output = ralph('--help')
      expect(output).toContain('agentic-loop - Tools to thrive with agentic coding')
    })
  })

  describe('init command', () => {
    let testDir: string

    beforeAll(() => {
      testDir = join(tmpdir(), `ralph-test-${Date.now()}`)
      mkdirSync(testDir, { recursive: true })
    })

    afterAll(() => {
      rmSync(testDir, { recursive: true, force: true })
    })

    it('creates .ralph directory', () => {
      ralph('init', testDir)
      expect(existsSync(join(testDir, '.ralph'))).toBe(true)
    })

    it('creates config.json', () => {
      expect(existsSync(join(testDir, '.ralph', 'config.json'))).toBe(true)
    })

    it('creates signs.json', () => {
      expect(existsSync(join(testDir, '.ralph', 'signs.json'))).toBe(true)
      const signs = JSON.parse(readFileSync(join(testDir, '.ralph', 'signs.json'), 'utf-8'))
      expect(signs).toHaveProperty('signs')
      expect(Array.isArray(signs.signs)).toBe(true)
    })

    it('creates progress.txt', () => {
      expect(existsSync(join(testDir, '.ralph', 'progress.txt'))).toBe(true)
    })

    it('creates PROMPT.md', () => {
      expect(existsSync(join(testDir, 'PROMPT.md'))).toBe(true)
    })

    it('detects node project type', () => {
      const nodeTestDir = join(tmpdir(), `ralph-node-test-${Date.now()}`)
      mkdirSync(nodeTestDir, { recursive: true })
      execSync('echo \'{"name":"test"}\' > package.json', { cwd: nodeTestDir })

      const output = ralph('init', nodeTestDir)
      expect(output).toContain('node')

      rmSync(nodeTestDir, { recursive: true, force: true })
    })

    it('is idempotent (safe to run twice)', () => {
      const output = ralph('init', testDir)
      expect(output).toContain('already initialized')
    })
  })

  describe('status command', () => {
    let testDir: string

    beforeAll(() => {
      testDir = join(tmpdir(), `ralph-status-test-${Date.now()}`)
      mkdirSync(testDir, { recursive: true })
      ralph('init', testDir)
    })

    afterAll(() => {
      rmSync(testDir, { recursive: true, force: true })
    })

    it('shows status without PRD', () => {
      const output = ralph('status', testDir)
      expect(output).toContain('No active PRD')
    })
  })

  describe('check command', () => {
    let testDir: string

    beforeAll(() => {
      testDir = join(tmpdir(), `ralph-check-test-${Date.now()}`)
      mkdirSync(testDir, { recursive: true })
      ralph('init', testDir)
    })

    afterAll(() => {
      rmSync(testDir, { recursive: true, force: true })
    })

    it('runs auto-fix and checks successfully', () => {
      const output = ralph('check', testDir)
      expect(output).toContain('Auto-fixing lint issues')
      expect(output).toContain('All checks passed')
    })
  })
})

describe('config templates', () => {
  const templates = ['node', 'python', 'go', 'rust', 'minimal', 'fullstack']

  templates.forEach(template => {
    it(`${template}.json is valid JSON`, () => {
      const configPath = join(TEMPLATES_DIR, 'config', `${template}.json`)
      expect(existsSync(configPath)).toBe(true)

      const content = readFileSync(configPath, 'utf-8')
      const config = JSON.parse(content)

      expect(config).toHaveProperty('checks')
      expect(config).toHaveProperty('maxIterations')
      expect(config).toHaveProperty('verification')
    })

    it(`${template}.json has required verification options`, () => {
      const configPath = join(TEMPLATES_DIR, 'config', `${template}.json`)
      const config = JSON.parse(readFileSync(configPath, 'utf-8'))

      expect(config.verification).toHaveProperty('codeReviewEnabled')
    })
  })
})

describe('PROMPT.md template', () => {
  it('exists', () => {
    const promptPath = join(TEMPLATES_DIR, 'PROMPT.md')
    expect(existsSync(promptPath)).toBe(true)
  })

  it('contains TDD instructions', () => {
    const promptPath = join(TEMPLATES_DIR, 'PROMPT.md')
    const content = readFileSync(promptPath, 'utf-8')

    expect(content).toContain('TDD Workflow')
    expect(content).toContain('Run Test Steps')
  })
})
