import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { join } from 'path'
import { mkdirSync, writeFileSync, readFileSync, rmSync, mkdtempSync } from 'fs'
import { tmpdir } from 'os'
import { execSync } from 'child_process'

const PROJECT_ROOT = join(__dirname, '..', '..')

let testDir: string
let ralphDir: string
let prdFile: string

beforeEach(() => {
  testDir = mkdtempSync(join(tmpdir(), 'ralph-test-'))
  ralphDir = join(testDir, '.ralph')
  mkdirSync(ralphDir, { recursive: true })
  prdFile = join(ralphDir, 'prd.json')
})

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true })
})

/**
 * Build a minimal PRD with the given passes array.
 * Each entry in passes becomes a story with id STORY-001, STORY-002, etc.
 */
function buildPrd(passes: boolean[]): object {
  return {
    feature: { name: 'test-feature', status: 'in-progress' },
    stories: passes.map((p, i) => ({
      id: `STORY-${String(i + 1).padStart(3, '0')}`,
      title: `Story ${i + 1}`,
      type: 'general',
      passes: p,
      retryCount: 0
    }))
  }
}

/**
 * Simulate the snapshot-then-restore logic from loop.sh lines 957-1249.
 *
 * 1. Take a snapshot of [.stories[] | {id, passes}] (passes_before)
 * 2. Write a tampered PRD (simulating Claude modifying passes)
 * 3. Run the restore jq command from loop.sh
 * 4. Return the restored PRD
 */
function runStateProtection(
  snapshotPrd: object,
  tamperedPrd: object
): { stories: Array<{ id: string; passes: boolean }> } {
  // Write the snapshot PRD first to capture passes_before
  writeFileSync(prdFile, JSON.stringify(snapshotPrd, null, 2))

  // The script mirrors loop.sh lines 958-1249:
  //   passes_before=$(jq '[.stories[] | {id, passes}]' prd.json)
  //   ... Claude runs and potentially tampers ...
  //   passes_after=$(jq '[.stories[] | {id, passes}]' prd.json)
  //   if [[ "$passes_before" != "$passes_after" ]]; then
  //     restored=$(jq --argjson before "$passes_before" '...' prd.json)
  //     echo "$restored" > prd.json
  //   fi
  const script = `
    set -euo pipefail
    PRD_FILE="${prdFile}"

    # Step 1: Snapshot passes state (like loop.sh line 958-959)
    passes_before=$(jq '[.stories[] | {id, passes}]' "$PRD_FILE")

    # Step 2: Write tampered PRD (simulating Claude modification)
    cat > "$PRD_FILE" <<'TAMPERED_EOF'
${JSON.stringify(tamperedPrd, null, 2)}
TAMPERED_EOF

    # Step 3: Check and restore (like loop.sh lines 1239-1249)
    passes_after=$(jq '[.stories[] | {id, passes}]' "$PRD_FILE")
    if [[ "$passes_before" != "$passes_after" ]]; then
      restored=$(jq --argjson before "$passes_before" '
        .stories |= [.[] | . as $s | ($before[] | select(.id == $s.id)) as $orig |
          if $orig then $s + {passes: $orig.passes} else $s end]
      ' "$PRD_FILE")
      echo "$restored" > "$PRD_FILE"
    fi

    # Output the final state
    cat "$PRD_FILE"
  `

  const output = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
    cwd: PROJECT_ROOT,
    encoding: 'utf-8',
    env: { ...process.env, NO_COLOR: '1' }
  }).trim()

  return JSON.parse(output)
}

/** Helper to extract passes array from a PRD result */
function getPassesArray(result: { stories: Array<{ passes: boolean }> }): boolean[] {
  return result.stories.map((s) => s.passes)
}

describe('UAT-007: Story state protection — passes field cannot be flipped by Claude', () => {
  // Assertion 1: Snapshot passes=[false,false,true], Claude changes to [true,false,true]
  // → Reset to [false,false,true] — first story reverted
  it('reverts a single story flipped from false to true', () => {
    const snapshot = buildPrd([false, false, true])
    const tampered = buildPrd([true, false, true])

    const result = runStateProtection(snapshot, tampered)

    expect(getPassesArray(result)).toEqual([false, false, true])
  })

  // Assertion 2: Snapshot passes=[false,false], Claude changes to [true,true]
  // → Reset to [false,false] — both reverted
  it('reverts all stories when Claude flips ALL to true', () => {
    const snapshot = buildPrd([false, false])
    const tampered = buildPrd([true, true])

    const result = runStateProtection(snapshot, tampered)

    expect(getPassesArray(result)).toEqual([false, false])
  })

  // Assertion 3: Passes unchanged between snapshot and post-Claude
  // → No reset performed, PRD untouched
  it('does not modify PRD when passes are unchanged', () => {
    const prd = buildPrd([false, true, false])

    // Write original and capture it
    writeFileSync(prdFile, JSON.stringify(prd, null, 2))

    const script = `
      set -euo pipefail
      PRD_FILE="${prdFile}"

      passes_before=$(jq '[.stories[] | {id, passes}]' "$PRD_FILE")

      # Claude runs but doesn't change passes
      passes_after=$(jq '[.stories[] | {id, passes}]' "$PRD_FILE")

      if [[ "$passes_before" != "$passes_after" ]]; then
        echo "RESET_TRIGGERED"
      else
        echo "NO_RESET"
      fi
    `

    const output = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(output).toBe('NO_RESET')

    // Verify PRD is untouched
    const finalPrd = JSON.parse(readFileSync(prdFile, 'utf-8'))
    expect(getPassesArray(finalPrd)).toEqual([false, true, false])
  })

  // Edge case: Claude flips one story from false to true (middle story)
  it('reverts middle story flipped from false to true', () => {
    const snapshot = buildPrd([true, false, true])
    const tampered = buildPrd([true, true, true])

    const result = runStateProtection(snapshot, tampered)

    expect(getPassesArray(result)).toEqual([true, false, true])
  })

  // Edge case: Claude flips a story from true to false (shouldn't happen but test it)
  it('reverts story flipped from true to false', () => {
    const snapshot = buildPrd([true, true, false])
    const tampered = buildPrd([false, true, false])

    const result = runStateProtection(snapshot, tampered)

    expect(getPassesArray(result)).toEqual([true, true, false])
  })

  // Edge case: Claude adds a new story (not in snapshot)
  // The jq restore logic uses `($before[] | select(.id == $s.id)) as $orig` which
  // produces zero outputs when no match is found, effectively dropping the new story.
  it('drops new story added by Claude that was not in snapshot', () => {
    const snapshot = buildPrd([false, false])
    const tampered = {
      feature: { name: 'test-feature', status: 'in-progress' },
      stories: [
        { id: 'STORY-001', title: 'Story 1', type: 'general', passes: true, retryCount: 0 },
        { id: 'STORY-002', title: 'Story 2', type: 'general', passes: false, retryCount: 0 },
        { id: 'STORY-NEW', title: 'New Story', type: 'general', passes: true, retryCount: 0 }
      ]
    }

    const result = runStateProtection(snapshot, tampered)

    // STORY-001 should be reverted (false in snapshot, true in tampered)
    expect(result.stories[0].passes).toBe(false)
    // STORY-002 unchanged
    expect(result.stories[1].passes).toBe(false)
    // STORY-NEW has no snapshot match — jq's `as $orig` produces zero outputs,
    // so the new story is dropped from the array entirely
    expect(result.stories).toHaveLength(2)
  })

  // Edge case: Claude removes a story from the array
  it('handles Claude removing a story (restore only affects remaining stories)', () => {
    const snapshot = buildPrd([false, false, true])
    const tampered = {
      feature: { name: 'test-feature', status: 'in-progress' },
      stories: [
        { id: 'STORY-001', title: 'Story 1', type: 'general', passes: true, retryCount: 0 },
        { id: 'STORY-003', title: 'Story 3', type: 'general', passes: true, retryCount: 0 }
      ]
    }

    const result = runStateProtection(snapshot, tampered)

    // STORY-001 should be reverted to false (was false in snapshot)
    expect(result.stories[0].id).toBe('STORY-001')
    expect(result.stories[0].passes).toBe(false)
    // STORY-003 should be reverted to true (was true in snapshot)
    expect(result.stories[1].id).toBe('STORY-003')
    expect(result.stories[1].passes).toBe(true)
    // STORY-002 was removed — only 2 stories remain
    expect(result.stories).toHaveLength(2)
  })

  // Edge case: jq failure on malformed JSON
  it('fails gracefully on malformed JSON', () => {
    writeFileSync(prdFile, '{ invalid json }}}')

    const script = `
      set -euo pipefail
      PRD_FILE="${prdFile}"
      passes_before=$(jq '[.stories[] | {id, passes}]' "$PRD_FILE" 2>/dev/null) || {
        echo "JQ_FAILED"
        exit 0
      }
      echo "JQ_SUCCEEDED"
    `

    const output = execSync(`bash -c '${script.replace(/'/g, "'\\''")}'`, {
      cwd: PROJECT_ROOT,
      encoding: 'utf-8',
      env: { ...process.env, NO_COLOR: '1' }
    }).trim()

    expect(output).toBe('JQ_FAILED')
  })

  // Edge case: Other story fields (title, retryCount, etc.) preserved after reset
  it('preserves non-passes fields when restoring state', () => {
    const snapshot = {
      feature: { name: 'test-feature', status: 'in-progress' },
      stories: [
        { id: 'STORY-001', title: 'Original Title', type: 'general', passes: false, retryCount: 0 }
      ]
    }
    const tampered = {
      feature: { name: 'test-feature', status: 'in-progress' },
      stories: [
        { id: 'STORY-001', title: 'Claude Changed Title', type: 'backend', passes: true, retryCount: 3 }
      ]
    }

    const result = runStateProtection(snapshot, tampered)

    // passes should be reverted
    expect(result.stories[0].passes).toBe(false)
    // Other fields should retain Claude's changes (only passes is protected)
    expect(result.stories[0].title).toBe('Claude Changed Title')
    expect((result.stories[0] as any).retryCount).toBe(3)
  })
})
