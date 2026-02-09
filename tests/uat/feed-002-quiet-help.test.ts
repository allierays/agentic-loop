import { describe, it, expect, beforeAll } from 'vitest'
import { execSync } from 'child_process'
import { readFileSync } from 'fs'
import { join } from 'path'

const PROJECT_ROOT = join(__dirname, '..', '..')
const RALPH_SH = join(PROJECT_ROOT, 'bin', 'ralph.sh')
const AGENTIC_LOOP_SH = join(PROJECT_ROOT, 'bin', 'agentic-loop.sh')

function runBash(script: string): string {
  return execSync(`bash -c '${script}'`, {
    cwd: PROJECT_ROOT,
    encoding: 'utf-8',
    env: { ...process.env, NO_COLOR: '1' }
  }).trim()
}

describe('UAT-002: CLI help text — --quiet flag documentation', () => {
  let helpOutput: string

  // Get help output once for all assertions
  beforeAll(() => {
    helpOutput = runBash(`"${RALPH_SH}" help`)
  })

  it('help output contains "run --quiet" with description mentioning activity feed suppression', () => {
    // Assertion 1: Output contains 'run --quiet' with description mentioning activity feed suppression
    const quietLine = helpOutput.split('\n').find(line => line.includes('--quiet'))
    expect(quietLine).toBeDefined()
    expect(quietLine).toContain('run --quiet')
    // Description should mention suppressing the activity feed
    expect(quietLine!.toLowerCase()).toMatch(/suppress.*activity|activity.*suppress/)
  })

  it('bin/agentic-loop.sh header contains --quiet with correct description', () => {
    // Assertion 2: Header comments contain '--quiet' with description 'Suppress the live activity feed'
    const header = readFileSync(AGENTIC_LOOP_SH, 'utf-8')
      .split('\n')
      .slice(0, 15)
      .join('\n')
    expect(header).toContain('--quiet')
    expect(header).toContain('Suppress the live activity feed')
  })

  it('--quiet appears in the run command group near --fast and --max', () => {
    // Assertion 3: --quiet appears in the run command group, near --fast and --max
    const lines = helpOutput.split('\n')

    // Use findIndex to get the FIRST occurrence of each flag
    const quietLineNum = lines.findIndex(line => line.includes('--quiet'))
    const fastLineNum = lines.findIndex(line => line.includes('--fast'))
    const maxLineNum = lines.findIndex(line => line.includes('--max'))

    expect(quietLineNum).toBeGreaterThan(-1)
    expect(fastLineNum).toBeGreaterThan(-1)
    expect(maxLineNum).toBeGreaterThan(-1)

    // All three should be within 5 lines of each other (same command group)
    const spread = Math.max(quietLineNum, fastLineNum, maxLineNum) -
                   Math.min(quietLineNum, fastLineNum, maxLineNum)
    expect(spread).toBeLessThanOrEqual(5)
  })

  it('--quiet appears in both bin/agentic-loop.sh header AND ralph_help() output', () => {
    // Edge case: --quiet documented in both locations
    const header = readFileSync(AGENTIC_LOOP_SH, 'utf-8')
      .split('\n')
      .slice(0, 15)
      .join('\n')
    expect(header).toContain('--quiet')
    expect(helpOutput).toContain('--quiet')
  })

  it('description mentions "activity" or "suppress"', () => {
    // Edge case: description uses expected terminology
    const quietLine = helpOutput.split('\n').find(line => line.includes('--quiet'))
    expect(quietLine).toBeDefined()
    const lower = quietLine!.toLowerCase()
    expect(lower).toSatisfy(
      (l: string) => l.includes('activity') || l.includes('suppress')
    )
  })

  it('--quiet appears near --fast and --max flags within the same command group', () => {
    // Edge case: verify they are in the "run" section, not scattered elsewhere
    const lines = helpOutput.split('\n')

    // Find the "run" command line (the base "run" entry, not a flag line)
    const runLineIdx = lines.findIndex(line =>
      /^\s+run\s/.test(line) && !line.includes('--')
    )
    expect(runLineIdx).toBeGreaterThan(-1)

    // --fast, --quiet, --max should all appear after the base "run" line
    // and before the next non-run command
    const fastIdx = lines.findIndex((line, i) => i > runLineIdx && line.includes('--fast'))
    const quietIdx = lines.findIndex((line, i) => i > runLineIdx && line.includes('--quiet'))
    const maxIdx = lines.findIndex((line, i) => i > runLineIdx && line.includes('--max'))

    expect(fastIdx).toBeGreaterThan(runLineIdx)
    expect(quietIdx).toBeGreaterThan(runLineIdx)
    expect(maxIdx).toBeGreaterThan(runLineIdx)

    // They should be consecutive or near-consecutive (within 4 lines of "run")
    expect(fastIdx - runLineIdx).toBeLessThanOrEqual(4)
    expect(quietIdx - runLineIdx).toBeLessThanOrEqual(4)
    expect(maxIdx - runLineIdx).toBeLessThanOrEqual(4)
  })
})
