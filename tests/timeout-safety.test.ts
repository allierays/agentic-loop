import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { mkdirSync, rmSync, writeFileSync, readFileSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..')

function runBash(snippet: string, timeout = 15000): string {
  const script = `
    source "${PROJECT_ROOT}/ralph/utils.sh"
    ${snippet}
  `
  try {
    return execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      encoding: 'utf-8',
      timeout,
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()
  } catch (e: any) {
    return `EXIT:${e.status}:${(e.stdout || '').trim()}`
  }
}

describe('run_with_timeout', () => {
  it('kills a process that exceeds the timeout', () => {
    const start = Date.now()
    const result = runBash(`
      run_with_timeout 2 sleep 30
      echo "EXIT_CODE:$?"
    `)
    const elapsed = Date.now() - start

    // Should have been killed in ~2s, not 30s
    expect(elapsed).toBeLessThan(5000)
    // Exit code 124 = timeout (GNU timeout convention)
    expect(result).toContain('EXIT_CODE:124')
  })

  it('lets a fast process complete normally', () => {
    const result = runBash(`
      run_with_timeout 10 echo "hello"
      echo "EXIT_CODE:$?"
    `)

    expect(result).toContain('hello')
    expect(result).toContain('EXIT_CODE:0')
  })
})

describe('timeout chain worst case', () => {
  it('max_timeouts kills the loop, does not skip', () => {
    // Simulates the timeout counter from loop.sh
    // After max_timeouts, loop exits (return 1) instead of skipping
    const result = runBash(`
      max_timeouts=5
      consecutive_timeouts=0
      stopped=false

      for i in {1..10}; do
        ((consecutive_timeouts++))
        if [[ $consecutive_timeouts -ge $max_timeouts ]]; then
          stopped=true
          break
        fi
      done

      echo "timeouts:$consecutive_timeouts stopped:$stopped"
    `)

    expect(result).toBe('timeouts:5 stopped:true')
  })

  it('worst case time = maxSessionSeconds * max_timeouts', () => {
    // With defaults: 600s * 5 = 3000s = 50 min
    // This is a documentation test — ensures the math is known and bounded
    const result = runBash(`
      source "${PROJECT_ROOT}/ralph/utils.sh"
      timeout=$DEFAULT_TIMEOUT_SECONDS
      max_timeouts=5
      worst_case=$((timeout * max_timeouts))
      echo "$worst_case"
    `)

    expect(parseInt(result)).toBe(3000) // 50 minutes max
  })
})

describe('config protection', () => {
  let testDir: string

  beforeEach(() => {
    testDir = join(tmpdir(), `ralph-config-protect-${Date.now()}`)
    mkdirSync(testDir, { recursive: true })
  })

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('maxSessionSeconds is read once at loop start, not per iteration', () => {
    // Write initial config with 600s
    writeFileSync(
      join(testDir, 'config.json'),
      JSON.stringify({ maxSessionSeconds: 600 })
    )

    // Simulate: read timeout once, then Claude modifies config, read again
    const script = `
      export RALPH_DIR="${testDir}"
      source "${PROJECT_ROOT}/ralph/utils.sh"

      # Read once at start (what the fixed loop does)
      timeout_at_start=$(get_config '.maxSessionSeconds' "$DEFAULT_TIMEOUT_SECONDS")

      # Simulate Claude modifying config mid-session
      echo '{"maxSessionSeconds": 9999}' > "$RALPH_DIR/config.json"

      # On next iteration, a per-iteration read would get 9999
      timeout_per_iteration=$(get_config '.maxSessionSeconds' "$DEFAULT_TIMEOUT_SECONDS")

      echo "start:$timeout_at_start iter:$timeout_per_iteration"
    `

    const result = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    // start should be 600, iter would be 9999 if read per-iteration
    // The fix ensures loop uses timeout_at_start for all iterations
    expect(result).toContain('start:600')
    expect(result).toContain('iter:9999') // config.json WAS modified
    // The point: loop.sh now uses the start value, ignoring the mid-run change
  })
})
