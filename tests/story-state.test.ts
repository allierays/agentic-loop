import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { mkdirSync, rmSync, writeFileSync, readFileSync, existsSync } from 'fs'
import { join } from 'path'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..')

function readPrd(ralphDir: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(ralphDir, 'prd.json'), 'utf-8'))
}

function writePrd(ralphDir: string, prd: Record<string, unknown>): void {
  writeFileSync(join(ralphDir, 'prd.json'), JSON.stringify(prd, null, 2))
}

/**
 * Helper: source utils.sh and run a bash snippet with RALPH_DIR set
 */
function runBash(ralphDir: string, snippet: string): string {
  const script = `
    export RALPH_DIR="${ralphDir}"
    source "${PROJECT_ROOT}/ralph/utils.sh"
    ${snippet}
  `
  try {
    return execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()
  } catch (e: any) {
    return (e.stdout || '') + (e.stderr || '')
  }
}

describe('passes state reset', () => {
  let testDir: string

  const basePrd = {
    feature: { name: 'test' },
    stories: [
      { id: 'TASK-001', title: 'First', passes: false, retryCount: 0 },
      { id: 'TASK-002', title: 'Second', passes: false, retryCount: 0 },
      { id: 'TASK-003', title: 'Third', passes: true, retryCount: 0 }
    ]
  }

  beforeEach(() => {
    testDir = join(tmpdir(), `ralph-state-test-${Date.now()}`)
    mkdirSync(testDir, { recursive: true })
    writeFileSync(join(testDir, 'config.json'), JSON.stringify({}))
    writeFileSync(join(testDir, 'progress.txt'), '')
  })

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('reverts passes when Claude flips a story to true', () => {
    writePrd(testDir, basePrd)

    // Snapshot before using jq (matching what loop.sh does)
    const passesBefore = runBash(testDir, `
      jq '[.stories[] | {id, passes}]' "$RALPH_DIR/prd.json"
    `)

    // Simulate Claude flipping TASK-001 to passes: true
    const tampered = JSON.parse(JSON.stringify(basePrd))
    tampered.stories[0].passes = true
    writePrd(testDir, tampered)

    // Run the same jq reset logic from loop.sh
    const result = runBash(testDir, `
      passes_before='${passesBefore.replace(/'/g, "'\\''")}'
      passes_after=$(jq '[.stories[] | {id, passes}]' "$RALPH_DIR/prd.json" 2>/dev/null)
      if [[ "$passes_before" != "$passes_after" ]]; then
        restored=$(jq --argjson before "$passes_before" '
          .stories |= [.[] | . as $s | ($before[] | select(.id == $s.id)) as $orig |
            if $orig then $s + {passes: $orig.passes} else $s end]
        ' "$RALPH_DIR/prd.json") && echo "$restored" > "$RALPH_DIR/prd.json"
        echo "RESET"
      else
        echo "NO_CHANGE"
      fi
    `)

    expect(result).toBe('RESET')
    const prd = readPrd(testDir)
    const stories = prd.stories as Array<{ id: string; passes: boolean }>
    expect(stories[0].passes).toBe(false)  // reverted
    expect(stories[1].passes).toBe(false)  // unchanged
    expect(stories[2].passes).toBe(true)   // was already true, stays true
  })

  it('does nothing when passes state is unchanged', () => {
    writePrd(testDir, basePrd)

    // Use jq for both sides (matching what loop.sh does)
    const result = runBash(testDir, `
      passes_before=$(jq '[.stories[] | {id, passes}]' "$RALPH_DIR/prd.json" 2>/dev/null)
      passes_after=$(jq '[.stories[] | {id, passes}]' "$RALPH_DIR/prd.json" 2>/dev/null)
      if [[ "$passes_before" != "$passes_after" ]]; then
        echo "RESET"
      else
        echo "NO_CHANGE"
      fi
    `)

    expect(result).toBe('NO_CHANGE')
  })
})

describe('.blocked signal', () => {
  let testDir: string

  beforeEach(() => {
    testDir = join(tmpdir(), `ralph-blocked-test-${Date.now()}`)
    mkdirSync(testDir, { recursive: true })
    writeFileSync(join(testDir, 'config.json'), JSON.stringify({}))
  })

  afterEach(() => {
    rmSync(testDir, { recursive: true, force: true })
  })

  it('reads reason from .blocked file and cleans up', () => {
    writeFileSync(join(testDir, '.blocked'), 'BLOCKED: python not found on PATH')

    const result = runBash(testDir, `
      if [[ -f "$RALPH_DIR/.blocked" ]]; then
        block_reason=$(cat "$RALPH_DIR/.blocked" 2>/dev/null | head -1)
        rm -f "$RALPH_DIR/.blocked"
        echo "$block_reason"
      fi
    `)

    expect(result).toBe('BLOCKED: python not found on PATH')
    expect(existsSync(join(testDir, '.blocked'))).toBe(false)
  })

  it('saves block reason to failures directory', () => {
    const prd = {
      feature: { name: 'test' },
      stories: [
        { id: 'TASK-001', title: 'First', passes: false }
      ]
    }
    writePrd(testDir, prd)
    writeFileSync(join(testDir, '.blocked'), 'BLOCKED: missing dependency')

    runBash(testDir, `
      block_reason=$(cat "$RALPH_DIR/.blocked" 2>/dev/null | head -1)
      rm -f "$RALPH_DIR/.blocked"
      mkdir -p "$RALPH_DIR/failures"
      echo "$block_reason" > "$RALPH_DIR/failures/TASK-001.txt"
    `)

    const failureFile = readFileSync(join(testDir, 'failures', 'TASK-001.txt'), 'utf-8').trim()
    expect(failureFile).toBe('BLOCKED: missing dependency')

    // Story stays as-is (not skipped) — loop stops instead
    const updated = readPrd(testDir)
    const story = (updated.stories as Array<Record<string, unknown>>)[0]
    expect(story.passes).toBe(false)
    expect(story.skipped).toBeUndefined()
  })

  it('handles missing .blocked file gracefully', () => {
    // No .blocked file — should not throw
    const result = runBash(testDir, `
      if [[ -f "$RALPH_DIR/.blocked" ]]; then
        echo "FOUND"
      else
        echo "NOT_FOUND"
      fi
    `)

    expect(result).toBe('NOT_FOUND')
  })
})
