import { describe, it, expect } from 'vitest'
import { execSync } from 'child_process'
import { join } from 'path'

const PROJECT_ROOT = join(__dirname, '..', '..')
const UTILS_SH = join(PROJECT_ROOT, 'ralph', 'utils.sh')

function runBash(script: string): string {
  return execSync(`bash -c '${script}'`, {
    cwd: PROJECT_ROOT,
    encoding: 'utf-8',
    env: { ...process.env, NO_COLOR: '1' }
  }).trim()
}

function runBashWithStderr(script: string): { stdout: string; stderr: string } {
  try {
    const stdout = execSync(`bash -c '${script}'`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()
    return { stdout, stderr: '' }
  } catch (e: any) {
    return {
      stdout: (e.stdout || '').trim(),
      stderr: (e.stderr || '').trim()
    }
  }
}

describe('UAT-001: RALPH_LOOP_VERSION constant', () => {
  it('has value exactly "2"', () => {
    const result = runBash(`source "${UTILS_SH}" && echo "$RALPH_LOOP_VERSION"`)
    expect(result).toBe('2')
  })

  it('is a string, not an integer', () => {
    // Verify it's the string '2' by checking bash string comparison
    const result = runBash(
      `source "${UTILS_SH}" && [[ "$RALPH_LOOP_VERSION" == "2" ]] && echo "string_match"`
    )
    expect(result).toBe('string_match')
  })

  it('is readonly and cannot be reassigned', () => {
    const { stderr } = runBashWithStderr(
      `source "${UTILS_SH}" && RALPH_LOOP_VERSION=99 2>&1`
    )
    expect(stderr).toContain('readonly variable')
  })

  it('is defined within 5 lines of RALPH_VERSION', () => {
    const grepOutput = runBash(
      `grep -n -E "RALPH_LOOP_VERSION|RALPH_VERSION" "${UTILS_SH}" | head -10`
    )
    // Extract line numbers for first definition of each
    const lines = grepOutput.split('\n')
    let versionLine: number | null = null
    let loopVersionLine: number | null = null

    for (const line of lines) {
      const match = line.match(/^(\d+):/)
      if (!match) continue
      const lineNum = parseInt(match[1], 10)

      if (!versionLine && line.includes('RALPH_VERSION=') && !line.includes('RALPH_LOOP_VERSION')) {
        versionLine = lineNum
      }
      if (!loopVersionLine && line.includes('RALPH_LOOP_VERSION=')) {
        loopVersionLine = lineNum
      }
    }

    expect(versionLine).not.toBeNull()
    expect(loopVersionLine).not.toBeNull()
    const distance = Math.abs(loopVersionLine! - versionLine!)
    expect(distance).toBeLessThanOrEqual(5)
  })
})
