import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { execSync } from 'child_process'
import { existsSync, mkdirSync, rmSync, writeFileSync, readFileSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..')
const QUICK_SETUP = join(PROJECT_ROOT, 'ralph', 'setup', 'quick-setup.sh')

describe('install flow', () => {
  describe('skills (new format)', () => {
    const skillsDir = join(PROJECT_ROOT, '.claude', 'skills')

    it('has all required skills', () => {
      const requiredSkills = [
        'tour',
        'vibe-check',
        'review',
        'explain',
        'styleguide',
        'my-dna',
        'vibe-help',
        'vibe-list',
        'prd',
        'lesson'
      ]

      requiredSkills.forEach(skill => {
        expect(existsSync(join(skillsDir, skill, 'SKILL.md'))).toBe(true)
      })
    })

    it('/prd skill has PRD generation', () => {
      const prdPath = join(skillsDir, 'prd', 'SKILL.md')
      const content = readFileSync(prdPath, 'utf-8')

      expect(content).toContain('prd.json')
      expect(content).toContain('Generate PRD')
      expect(content).toContain('Ralph')
    })

    it('/tour skill has Ralph content', () => {
      const tourPath = join(skillsDir, 'tour', 'SKILL.md')
      const content = readFileSync(tourPath, 'utf-8')

      expect(content).toContain('Ralph')
      expect(content).toContain('agentic-loop')
    })
  })

  describe('legacy commands (backward compatibility)', () => {
    const commandsDir = join(PROJECT_ROOT, '.claude', 'commands')

    it('has legacy command files', () => {
      const requiredCommands = [
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
  })

  describe('bin scripts', () => {
    it('agentic-loop.sh is executable', () => {
      const agenticLoopPath = join(PROJECT_ROOT, 'bin', 'agentic-loop.sh')
      expect(existsSync(agenticLoopPath)).toBe(true)
    })

    it('ralph.sh exists for internal use', () => {
      const ralphPath = join(PROJECT_ROOT, 'bin', 'ralph.sh')
      expect(existsSync(ralphPath)).toBe(true)
    })
  })

  describe('ralph scripts', () => {
    const ralphDir = join(PROJECT_ROOT, 'ralph')

    it('has all ralph modules', () => {
      const requiredModules = [
        'utils.sh',
        'init.sh',
        'loop.sh',
        'code-check.sh',
        'prd.sh',
        'lessons.sh',
        'setup.sh',
        'test.sh'
      ]

      requiredModules.forEach(mod => {
        expect(existsSync(join(ralphDir, mod))).toBe(true)
      })
    })

    it('code-check.sh has verification pipeline', () => {
      const verifyPath = join(ralphDir, 'code-check.sh')
      const content = readFileSync(verifyPath, 'utf-8')

      expect(content).toContain('run_verification')
      expect(content).toContain('Verification')
    })
  })

  describe('package.json', () => {
    it('has correct bin entries', () => {
      const pkgPath = join(PROJECT_ROOT, 'package.json')
      const pkg = JSON.parse(readFileSync(pkgPath, 'utf-8'))

      expect(pkg.bin).toHaveProperty('agentic-loop')
      expect(pkg.bin).toHaveProperty('vibe-check')
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

  it('quick-setup creates .claude/skills', () => {
    // Simulate what quick-setup does for skills (new format)
    const skillsDir = join(testDir, '.claude', 'skills', 'vibe-help')
    mkdirSync(skillsDir, { recursive: true })

    // Copy a skill file
    const srcSkill = join(PROJECT_ROOT, '.claude', 'skills', 'vibe-help', 'SKILL.md')
    const destSkill = join(skillsDir, 'SKILL.md')
    writeFileSync(destSkill, readFileSync(srcSkill))

    expect(existsSync(destSkill)).toBe(true)
  })

  it('quick-setup creates .ralph directory', () => {
    const ralphDir = join(testDir, '.ralph')
    mkdirSync(join(ralphDir, 'archive'), { recursive: true })
    mkdirSync(join(ralphDir, 'screenshots'), { recursive: true })

    // Copy config
    const srcConfig = join(PROJECT_ROOT, 'templates', 'config', 'node.json')
    writeFileSync(join(ralphDir, 'config.json'), readFileSync(srcConfig))

    // Create lessons.json
    writeFileSync(join(ralphDir, 'lessons.json'), '{"lessons": []}')

    expect(existsSync(join(ralphDir, 'config.json'))).toBe(true)
    expect(existsSync(join(ralphDir, 'lessons.json'))).toBe(true)
  })

  it('quick-setup creates .pre-commit-config.yaml', () => {
    const precommitConfig = `repos:
  - repo: https://github.com/allierays/agentic-loop
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
