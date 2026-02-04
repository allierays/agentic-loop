import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { execSync } from 'child_process'
import { mkdirSync, rmSync, writeFileSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..')

/**
 * Helper: run a bash snippet that sources utils.sh + verify/tests.sh,
 * sets RALPH_DIR to our temp fixture, and prints the result.
 */
function expandConfigVars(input: string, ralphDir: string): string {
  const script = `
    export RALPH_DIR="${ralphDir}"
    source "${PROJECT_ROOT}/ralph/utils.sh"
    source "${PROJECT_ROOT}/ralph/verify/tests.sh"
    _expand_config_vars "${input}"
  `
  return execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
    encoding: 'utf-8',
    env: { ...process.env, NO_COLOR: '1' }
  }).trim()
}

describe('_expand_config_vars', () => {
  let testDir: string

  beforeAll(() => {
    testDir = join(tmpdir(), `ralph-expand-test-${Date.now()}`)
    mkdirSync(testDir, { recursive: true })
    writeFileSync(
      join(testDir, 'config.json'),
      JSON.stringify({
        urls: {
          backend: 'http://localhost:8000',
          frontend: 'http://localhost:3000'
        },
        api: {
          baseUrl: 'http://fallback:9000'
        }
      })
    )
  })

  afterAll(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('expands {config.urls.frontend} in a testUrl', () => {
    const result = expandConfigVars('{config.urls.frontend}/dashboard', testDir)
    expect(result).toBe('http://localhost:3000/dashboard')
  })

  it('expands {config.urls.backend} in a testStep', () => {
    const result = expandConfigVars(
      'curl -s {config.urls.backend}/api/users | jq -e .id',
      testDir
    )
    expect(result).toBe('curl -s http://localhost:8000/api/users | jq -e .id')
  })

  it('expands a bare placeholder with no path suffix', () => {
    const result = expandConfigVars('{config.urls.frontend}', testDir)
    expect(result).toBe('http://localhost:3000')
  })

  it('returns input unchanged when no placeholders present', () => {
    const result = expandConfigVars('/login', testDir)
    expect(result).toBe('/login')
  })

  it('returns input unchanged when config file is missing', () => {
    const emptyDir = join(tmpdir(), `ralph-no-config-${Date.now()}`)
    mkdirSync(emptyDir, { recursive: true })
    try {
      const result = expandConfigVars('{config.urls.frontend}/page', emptyDir)
      expect(result).toBe('{config.urls.frontend}/page')
    } finally {
      rmSync(emptyDir, { recursive: true, force: true })
    }
  })

  it('expands multiple placeholders in one string', () => {
    const result = expandConfigVars(
      'curl {config.urls.backend}/api && open {config.urls.frontend}/status',
      testDir
    )
    expect(result).toBe(
      'curl http://localhost:8000/api && open http://localhost:3000/status'
    )
  })
})

describe('testUrl expansion in api.sh', () => {
  let testDir: string

  beforeAll(() => {
    testDir = join(tmpdir(), `ralph-testurl-test-${Date.now()}`)
    mkdirSync(testDir, { recursive: true })
    writeFileSync(
      join(testDir, 'config.json'),
      JSON.stringify({
        urls: {
          frontend: 'http://localhost:5173'
        }
      })
    )
    writeFileSync(
      join(testDir, 'prd.json'),
      JSON.stringify({
        feature: { name: 'test' },
        stories: [
          {
            id: 'FE-1',
            title: 'Login page',
            type: 'frontend',
            testUrl: '{config.urls.frontend}/login',
            passes: false
          },
          {
            id: 'FE-2',
            title: 'Dashboard',
            type: 'frontend',
            testUrl: '/dashboard',
            passes: false
          }
        ]
      })
    )
  })

  afterAll(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('expands {config.urls.frontend} in testUrl read from PRD', () => {
    // Simulate exactly what api.sh does: jq extraction then _expand_config_vars
    const script = `
      export RALPH_DIR="${testDir}"
      source "${PROJECT_ROOT}/ralph/utils.sh"
      source "${PROJECT_ROOT}/ralph/verify/tests.sh"

      test_url=$(jq -r --arg id "FE-1" \
        '.stories[] | select(.id==$id) | .testUrl // empty' \
        "${testDir}/prd.json" 2>/dev/null)
      test_url=$(_expand_config_vars "$test_url")
      echo "$test_url"
    `
    const result = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(result).toBe('http://localhost:5173/login')
  })

  it('leaves plain path testUrl unchanged', () => {
    const script = `
      export RALPH_DIR="${testDir}"
      source "${PROJECT_ROOT}/ralph/utils.sh"
      source "${PROJECT_ROOT}/ralph/verify/tests.sh"

      test_url=$(jq -r --arg id "FE-2" \
        '.stories[] | select(.id==$id) | .testUrl // empty' \
        "${testDir}/prd.json" 2>/dev/null)
      test_url=$(_expand_config_vars "$test_url")
      echo "$test_url"
    `
    const result = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(result).toBe('/dashboard')
  })
})
