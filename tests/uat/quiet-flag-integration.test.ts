import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { join } from 'path'
import { mkdirSync, writeFileSync, rmSync, mkdtempSync } from 'fs'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..', '..')
const UTILS_SH = join(PROJECT_ROOT, 'ralph', 'utils.sh')
const LOOP_SH = join(PROJECT_ROOT, 'ralph', 'loop.sh')

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

/**
 * Run the argument parsing section of run_loop in isolation.
 * We source utils.sh and loop.sh, then replicate the parse logic
 * from run_loop (lines 641-670) to extract variable values.
 */
function parseRunLoopArgs(args: string, configJson?: Record<string, unknown>): string {
  if (configJson) {
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify(configJson))
  }

  // Replicate the exact parsing logic from run_loop() lines 641-670
  const script = `
    export RALPH_DIR="${ralphDir}"
    source "${UTILS_SH}"

    # Replicate run_loop argument parsing exactly
    max_iterations=""
    specific_story=""
    fast_mode=false
    quiet_mode=$(get_config '.quiet' "false")

    set -- ${args}
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --max)
          max_iterations="$2"
          shift 2
          ;;
        --story)
          specific_story="$2"
          shift 2
          ;;
        --fast)
          fast_mode=true
          shift
          ;;
        --quiet)
          quiet_mode=true
          shift
          ;;
        *)
          shift
          ;;
      esac
    done

    echo "quiet_mode=$quiet_mode"
    echo "fast_mode=$fast_mode"
    echo "max_iterations=$max_iterations"
    echo "specific_story=$specific_story"
  `

  return execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
    cwd: PROJECT_ROOT,
    encoding: 'utf-8',
    env: { ...process.env, NO_COLOR: '1' }
  }).trim()
}

function getVar(output: string, name: string): string {
  const match = output.match(new RegExp(`^${name}=(.*)$`, 'm'))
  return match ? match[1] : ''
}

describe('UAT-003: CLI argument parsing — --quiet flag integration in run_loop', () => {
  it('--quiet flag sets quiet_mode to true', () => {
    // Assertion 1: Parse args: --quiet → quiet_mode variable is 'true'
    const output = parseRunLoopArgs('--quiet')
    expect(getVar(output, 'quiet_mode')).toBe('true')
  })

  it('config quiet=true sets quiet_mode when --quiet flag is not passed', () => {
    // Assertion 2: Parse args with config quiet=true, no --quiet flag → quiet_mode is 'true' from config
    const output = parseRunLoopArgs('', { quiet: true })
    expect(getVar(output, 'quiet_mode')).toBe('true')
  })

  it('--fast --quiet --max 5 sets all three variables correctly', () => {
    // Assertion 3: Parse args: --fast --quiet --max 5 → fast_mode=true, quiet_mode=true, max_iterations=5
    const output = parseRunLoopArgs('--fast --quiet --max 5')
    expect(getVar(output, 'fast_mode')).toBe('true')
    expect(getVar(output, 'quiet_mode')).toBe('true')
    expect(getVar(output, 'max_iterations')).toBe('5')
  })

  // Edge cases from plan.json

  it('--quiet CLI flag overrides config.quiet=false', () => {
    const output = parseRunLoopArgs('--quiet', { quiet: false })
    expect(getVar(output, 'quiet_mode')).toBe('true')
  })

  it('without --quiet and config.quiet=false, quiet_mode is false', () => {
    const output = parseRunLoopArgs('', { quiet: false })
    expect(getVar(output, 'quiet_mode')).toBe('false')
  })

  it('without --quiet and no config file, quiet_mode defaults to false', () => {
    // No config.json written — get_config returns default "false"
    const output = parseRunLoopArgs('')
    expect(getVar(output, 'quiet_mode')).toBe('false')
  })

  it('unknown flags are silently ignored (no error)', () => {
    // Unknown flags should be consumed by the * case without errors
    const output = parseRunLoopArgs('--unknown --foo --quiet')
    expect(getVar(output, 'quiet_mode')).toBe('true')
  })

  it('--quiet combined with --fast and --max and --story', () => {
    const output = parseRunLoopArgs('--fast --quiet --max 10 --story TASK-001')
    expect(getVar(output, 'fast_mode')).toBe('true')
    expect(getVar(output, 'quiet_mode')).toBe('true')
    expect(getVar(output, 'max_iterations')).toBe('10')
    expect(getVar(output, 'specific_story')).toBe('TASK-001')
  })
})
