import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { mkdirSync, rmSync, writeFileSync, readFileSync, existsSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..')

/**
 * Helper: source utils.sh + loop.sh and run a bash snippet with RALPH_DIR set.
 * Runs inside a temp project directory so detect_project_type sees the right files.
 */
function runBash(
  ralphDir: string,
  snippet: string,
  opts: { cwd?: string; env?: Record<string, string>; timeout?: number } = {}
): string {
  const script = `
    export RALPH_DIR="${ralphDir}"
    source "${PROJECT_ROOT}/ralph/utils.sh"
    source "${PROJECT_ROOT}/ralph/loop.sh"
    ${snippet}
  `
  try {
    return execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      encoding: 'utf-8',
      timeout: opts.timeout ?? 15000,
      cwd: opts.cwd,
      env: { ...process.env, NO_COLOR: '1', ...opts.env }
    }).trim()
  } catch (e: any) {
    return `EXIT:${e.status}:${(e.stdout || '').trim()}:${(e.stderr || '').trim()}`
  }
}

// ─────────────────────────────────────────────────────────────────────
// _docker_safety_warning — skip conditions
// ─────────────────────────────────────────────────────────────────────

describe('_docker_safety_warning skip conditions', () => {
  let testDir: string
  let ralphDir: string

  beforeEach(() => {
    testDir = join(tmpdir(), `ralph-docker-test-${Date.now()}`)
    ralphDir = join(testDir, '.ralph')
    mkdirSync(ralphDir, { recursive: true })
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({}))
    // Create a package.json so detect_project_type returns "node" (not "minimal")
    writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test' }))
  })

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('skips when RALPH_SKIP_DOCKER_WARNING=1', () => {
    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir, env: { RALPH_SKIP_DOCKER_WARNING: '1' } }
    )
    // Should return immediately, printing only REACHED (no banner)
    expect(result).toBe('REACHED')
  })

  it('skips when docker.enabled is true in config', () => {
    writeFileSync(
      join(ralphDir, 'config.json'),
      JSON.stringify({ docker: { enabled: true } })
    )

    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toBe('REACHED')
  })

  it('skips when project type is minimal', () => {
    // Remove package.json so detect_project_type returns "minimal"
    rmSync(join(testDir, 'package.json'))

    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toBe('REACHED')
  })

  it('skips when project type is hugo', () => {
    // Remove package.json, add hugo markers
    rmSync(join(testDir, 'package.json'))
    writeFileSync(join(testDir, 'hugo.toml'), '')
    mkdirSync(join(testDir, 'content'), { recursive: true })

    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toBe('REACHED')
  })

  it('skips when docker-compose.yml exists', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), 'services: {}')

    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toBe('REACHED')
  })

  it('skips when compose.yml exists', () => {
    writeFileSync(join(testDir, 'compose.yml'), 'services: {}')

    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toBe('REACHED')
  })

  it('skips when docker-compose.yaml exists', () => {
    writeFileSync(join(testDir, 'docker-compose.yaml'), 'services: {}')

    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toBe('REACHED')
  })

  it('skips when compose.yaml exists', () => {
    writeFileSync(join(testDir, 'compose.yaml'), 'services: {}')

    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toBe('REACHED')
  })

  it('shows warning when no compose file and non-minimal project', () => {
    // Feed "C" to stdin so read doesn't hang
    const result = runBash(
      ralphDir,
      `
      echo "C" | _docker_safety_warning
      echo "REACHED"
    `,
      { cwd: testDir }
    )
    expect(result).toContain('YOUR PROJECT IS NOT USING DOCKER')
    expect(result).toContain('REACHED')
  })
})

// ─────────────────────────────────────────────────────────────────────
// _generate_docker_compose — output per project type
// ─────────────────────────────────────────────────────────────────────

describe('_generate_docker_compose', () => {
  let testDir: string
  let ralphDir: string

  beforeEach(() => {
    testDir = join(tmpdir(), `ralph-compose-gen-${Date.now()}`)
    ralphDir = join(testDir, '.ralph')
    mkdirSync(ralphDir, { recursive: true })
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({}))
  })

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('generates postgres + redis for node projects', () => {
    writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test' }))

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).toContain('redis')
    expect(compose).toContain('5432:5432')
    expect(compose).toContain('6379:6379')
    expect(compose).toContain('pgdata')
  })

  it('generates postgres + redis for python projects', () => {
    writeFileSync(join(testDir, 'pyproject.toml'), '[project]\nname = "myapp"')

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).toContain('redis')
  })

  it('generates postgres + redis for fullstack projects', () => {
    mkdirSync(join(testDir, 'frontend'), { recursive: true })
    mkdirSync(join(testDir, 'backend'), { recursive: true })

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).toContain('redis')
  })

  it('generates postgres + redis for fastapi projects', () => {
    writeFileSync(
      join(testDir, 'pyproject.toml'),
      '[project]\nname = "myapp"\ndependencies = ["fastapi"]'
    )

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).toContain('redis')
  })

  it('generates postgres + redis for django projects', () => {
    writeFileSync(
      join(testDir, 'pyproject.toml'),
      '[project]\nname = "myapp"\ndependencies = ["django"]'
    )

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).toContain('redis')
  })

  it('generates postgres only for go projects', () => {
    writeFileSync(join(testDir, 'go.mod'), 'module example.com/app')

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).not.toContain('redis')
  })

  it('generates postgres only for rust projects', () => {
    writeFileSync(join(testDir, 'Cargo.toml'), '[package]\nname = "app"')

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).not.toContain('redis')
  })

  it('generates postgres with elixir-standard credentials for elixir projects', () => {
    writeFileSync(join(testDir, 'mix.exs'), 'defmodule App do end')

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('postgres')
    expect(compose).toContain('POSTGRES_USER: postgres')
    expect(compose).toContain('POSTGRES_PASSWORD: postgres')
    expect(compose).not.toContain('redis')
  })

  it('generates app service for fastmcp projects', () => {
    writeFileSync(
      join(testDir, 'pyproject.toml'),
      '[project]\nname = "myserver"\ndependencies = ["fastmcp"]'
    )

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('app:')
    expect(compose).toContain('build: .')
    expect(compose).toContain('8000:8000')
    expect(compose).not.toContain('postgres')
  })

  it('returns error for minimal project type', () => {
    // No project files → minimal
    const result = runBash(ralphDir, `
      _generate_docker_compose
      echo "EXIT:$?"
    `, { cwd: testDir })

    expect(result).toContain('EXIT:1')
    expect(existsSync(join(testDir, 'docker-compose.yml'))).toBe(false)
  })

  it('includes healthchecks for postgres', () => {
    writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test' }))

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('healthcheck')
    expect(compose).toContain('pg_isready')
  })

  it('includes healthchecks for redis', () => {
    writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test' }))

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('redis-cli')
  })

  it('uses named volume for postgres data', () => {
    writeFileSync(join(testDir, 'go.mod'), 'module example.com/app')

    runBash(ralphDir, '_generate_docker_compose', { cwd: testDir })

    const compose = readFileSync(join(testDir, 'docker-compose.yml'), 'utf-8')
    expect(compose).toContain('volumes:')
    expect(compose).toContain('pgdata:')
    expect(compose).toContain('pgdata:/var/lib/postgresql/data')
  })
})

// ─────────────────────────────────────────────────────────────────────
// _docker_safety_warning — interactive responses
// ─────────────────────────────────────────────────────────────────────

describe('_docker_safety_warning interactive responses', () => {
  let testDir: string
  let ralphDir: string

  beforeEach(() => {
    testDir = join(tmpdir(), `ralph-docker-interactive-${Date.now()}`)
    ralphDir = join(testDir, '.ralph')
    mkdirSync(ralphDir, { recursive: true })
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({}))
    writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test' }))
  })

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('continues loop when user presses C', () => {
    const result = runBash(
      ralphDir,
      `
      echo "C" | _docker_safety_warning
      echo "CONTINUED"
    `,
      { cwd: testDir }
    )
    expect(result).toContain('Continuing without Docker')
    expect(result).toContain('CONTINUED')
  })

  it('continues on any non-S/Q input (default)', () => {
    const result = runBash(
      ralphDir,
      `
      echo "" | _docker_safety_warning
      echo "CONTINUED"
    `,
      { cwd: testDir }
    )
    expect(result).toContain('CONTINUED')
  })

  it('generates docker-compose.yml when user presses S', () => {
    const result = runBash(
      ralphDir,
      `
      echo "S" | _docker_safety_warning
      echo "DONE"
    `,
      { cwd: testDir }
    )
    expect(result).toContain('Generated docker-compose.yml')
    expect(existsSync(join(testDir, 'docker-compose.yml'))).toBe(true)
  })

  it('exits when user presses Q', () => {
    // Use herestring (<<<) instead of pipe to avoid subshell — exit 0 must
    // terminate the script, not just a pipe subshell.
    const result = runBash(
      ralphDir,
      `
      _docker_safety_warning <<< "Q"
      echo "SHOULD_NOT_REACH"
    `,
      { cwd: testDir }
    )
    // exit 0 stops the script, so SHOULD_NOT_REACH is never printed
    expect(result).not.toContain('SHOULD_NOT_REACH')
    expect(result).toContain('Exiting')
  })

  it('shows suppress hint in banner', () => {
    const result = runBash(
      ralphDir,
      `
      echo "C" | _docker_safety_warning
    `,
      { cwd: testDir }
    )
    expect(result).toContain('RALPH_SKIP_DOCKER_WARNING=1')
  })
})
