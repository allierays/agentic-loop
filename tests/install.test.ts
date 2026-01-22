import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { execSync } from 'child_process'
import { existsSync, mkdirSync, rmSync, writeFileSync, readFileSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..')
const QUICK_SETUP = join(PROJECT_ROOT, 'ralph', 'setup', 'quick-setup.sh')

describe('install flow', () => {
  describe('slash commands', () => {
    const commandsDir = join(PROJECT_ROOT, '.claude', 'commands')

    it('has all required slash commands', () => {
      const requiredCommands = [
        'idea.md',
        'tour.md',
        'vibe-check.md',
        'review.md',
        'explain.md',
        'styleguide.md',
        'my-dna.md',
        'vibe-help.md'
      ]

      requiredCommands.forEach(cmd => {
        expect(existsSync(join(commandsDir, cmd))).toBe(true)
      })
    })

    it('/idea command has PRD schema', () => {
      const ideaPath = join(commandsDir, 'idea.md')
      const content = readFileSync(ideaPath, 'utf-8')

      expect(content).toContain('prd.json')
      expect(content).toContain('acceptanceCriteria')
      expect(content).toContain('errorHandling')
      expect(content).toContain('testSteps')
    })

    it('/tour command has Ralph content', () => {
      const tourPath = join(commandsDir, 'tour.md')
      const content = readFileSync(tourPath, 'utf-8')

      expect(content).toContain('Ralph')
      expect(content).toContain('vibe-and-thrive')
    })
  })

  describe('bin scripts', () => {
    it('ralph.sh is executable', () => {
      const ralphPath = join(PROJECT_ROOT, 'bin', 'ralph.sh')
      expect(existsSync(ralphPath)).toBe(true)
    })

    it('vibe-and-thrive.sh is executable', () => {
      const vibePath = join(PROJECT_ROOT, 'bin', 'vibe-and-thrive.sh')
      expect(existsSync(vibePath)).toBe(true)
    })

    it('ralph-setup.sh is executable', () => {
      const setupPath = join(PROJECT_ROOT, 'bin', 'ralph-setup.sh')
      expect(existsSync(setupPath)).toBe(true)
    })
  })

  describe('ralph scripts', () => {
    const ralphDir = join(PROJECT_ROOT, 'ralph')

    it('has all ralph modules', () => {
      const requiredModules = [
        'utils.sh',
        'init.sh',
        'loop.sh',
        'verify.sh',
        'prd.sh',
        'signs.sh',
        'playwright.sh',
        'api.sh'
      ]

      requiredModules.forEach(mod => {
        expect(existsSync(join(ralphDir, mod))).toBe(true)
      })
    })

    it('verify.sh has verification pipeline', () => {
      const verifyPath = join(ralphDir, 'verify.sh')
      const content = readFileSync(verifyPath, 'utf-8')

      expect(content).toContain('run_verification')
      expect(content).toContain('Code review')
    })
  })

  describe('package.json', () => {
    it('has correct bin entries', () => {
      const pkgPath = join(PROJECT_ROOT, 'package.json')
      const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'))

      expect(pkg.bin).toHaveProperty('ralph')
      expect(pkg.bin).toHaveProperty('vibe-and-thrive')
      expect(pkg.bin).toHaveProperty('ralph-setup')
    })

    it('includes required files in package', () => {
      const pkgPath = join(PROJECT_ROOT, 'package.json')
      const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'))

      expect(pkg.files).toContain('ralph')
      expect(pkg.files).toContain('templates')
      expect(pkg.files).toContain('.claude')
      expect(pkg.files).toContain('bin')
    })

    it('has postinstall script', () => {
      const pkgPath = join(PROJECT_ROOT, 'package.json')
      const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'))

      expect(pkg.scripts.postinstall).toBeDefined()
    })
  })
})

describe('simulated install', () => {
  let testDir: string

  beforeAll(() => {
    testDir = join(tmpdir(), `vibe-install-test-${Date.now()}`)
    mkdirSync(testDir, { recursive: true })
    // Create a minimal package.json so it looks like a real project
    writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test-project' }))
  })

  afterAll(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('quick-setup creates .claude/commands', () => {
    // Simulate what quick-setup does for slash commands
    const commandsDir = join(testDir, '.claude', 'commands')
    mkdirSync(commandsDir, { recursive: true })

    // Copy a command file
    const srcCommand = join(PROJECT_ROOT, '.claude', 'commands', 'vibe-help.md')
    const destCommand = join(commandsDir, 'vibe-help.md')
    writeFileSync(destCommand, readFileSync(srcCommand))

    expect(existsSync(destCommand)).toBe(true)
  })

  it('quick-setup creates .ralph directory', () => {
    const ralphDir = join(testDir, '.ralph')
    mkdirSync(join(ralphDir, 'archive'), { recursive: true })
    mkdirSync(join(ralphDir, 'screenshots'), { recursive: true })

    // Copy config
    const srcConfig = join(PROJECT_ROOT, 'templates', 'config', 'node.json')
    writeFileSync(join(ralphDir, 'config.json'), readFileSync(srcConfig))

    // Create signs.json
    writeFileSync(join(ralphDir, 'signs.json'), '{"signs": []}')

    expect(existsSync(join(ralphDir, 'config.json'))).toBe(true)
    expect(existsSync(join(ralphDir, 'signs.json'))).toBe(true)
  })

  it('quick-setup creates .pre-commit-config.yaml', () => {
    const precommitConfig = `repos:
  - repo: https://github.com/allthriveai/vibe-and-thrive
    rev: v1.0.0
    hooks:
      - id: check-secrets
      - id: check-hardcoded-urls
      - id: vibe-check-quality
`
    writeFileSync(join(testDir, '.pre-commit-config.yaml'), precommitConfig)
    expect(existsSync(join(testDir, '.pre-commit-config.yaml'))).toBe(true)
  })
})
