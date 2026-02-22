import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { execSync } from 'child_process'
import { join } from 'path'
import {
  mkdirSync, writeFileSync, readFileSync, rmSync,
  mkdtempSync, existsSync
} from 'fs'
import { tmpdir } from 'os'

const PROJECT_ROOT = join(__dirname, '..', '..')
const RALPH_SH = join(PROJECT_ROOT, 'bin', 'ralph.sh')

let testDir: string
let ralphDir: string

beforeEach(() => {
  testDir = mkdtempSync(join(tmpdir(), 'ralph-uat-test-'))
  ralphDir = join(testDir, '.ralph')

  // Create minimal .ralph structure
  mkdirSync(join(ralphDir, 'archive'), { recursive: true })
  mkdirSync(join(ralphDir, 'screenshots'), { recursive: true })
  mkdirSync(join(ralphDir, 'uat', 'screenshots'), { recursive: true })
  mkdirSync(join(ralphDir, 'chaos', 'screenshots'), { recursive: true })
  writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({ checks: {} }))
  writeFileSync(join(ralphDir, 'lessons.json'), '{"lessons": []}')
  writeFileSync(join(testDir, 'PROMPT.md'), '# Test')
  writeFileSync(join(testDir, 'package.json'), JSON.stringify({ name: 'test', version: '0.0.0' }))

  // Initialize git repo (many uat.sh functions depend on git)
  execSync('git init && git add -A && git commit -m "init" --no-verify', {
    cwd: testDir,
    encoding: 'utf-8',
    env: { ...process.env, GIT_AUTHOR_NAME: 'test', GIT_AUTHOR_EMAIL: 'test@test.com', GIT_COMMITTER_NAME: 'test', GIT_COMMITTER_EMAIL: 'test@test.com' }
  })
})

afterEach(() => {
  rmSync(testDir, { recursive: true, force: true })
})

const GIT_ENV = {
  GIT_AUTHOR_NAME: 'test',
  GIT_AUTHOR_EMAIL: 'test@test.com',
  GIT_COMMITTER_NAME: 'test',
  GIT_COMMITTER_EMAIL: 'test@test.com'
}

/**
 * Run a bash script that sources utils.sh, loop.sh (for _inject_lessons), and uat.sh
 * then executes the given code. Sets up RALPH_DIR and RALPH_TEMPLATES.
 */
function runUatBash(script: string, opts?: { expectFail?: boolean }): { stdout: string; stderr: string; exitCode: number } {
  const fullScript = `
    set -euo pipefail
    export RALPH_DIR="${ralphDir}"
    export RALPH_LIB="${join(PROJECT_ROOT, 'ralph')}"
    export RALPH_TEMPLATES="${join(PROJECT_ROOT, 'templates')}"
    source "$RALPH_LIB/utils.sh"
    source "$RALPH_LIB/lessons.sh"
    source "$RALPH_LIB/loop.sh"
    source "$RALPH_LIB/uat.sh"
    ${script}
  `
  try {
    const stdout = execSync(`bash -c '${fullScript.replace(/'/g, "'\\''")}'`, {
      cwd: testDir,
      encoding: 'utf-8',
      timeout: 10000,
      env: { ...process.env, NO_COLOR: '1', ...GIT_ENV }
    }).trim()
    return { stdout, stderr: '', exitCode: 0 }
  } catch (e: any) {
    return {
      stdout: (e.stdout || '').trim(),
      stderr: (e.stderr || '').trim(),
      exitCode: e.status ?? 1
    }
  }
}

/**
 * Run ralph CLI command
 */
function runRalph(args: string): { stdout: string; stderr: string; exitCode: number } {
  try {
    const stdout = execSync(`bash "${RALPH_SH}" ${args}`, {
      cwd: testDir,
      encoding: 'utf-8',
      timeout: 10000,
      env: { ...process.env, NO_COLOR: '1', RALPH_DIR: ralphDir, ...GIT_ENV }
    }).trim()
    return { stdout, stderr: '', exitCode: 0 }
  } catch (e: any) {
    return {
      stdout: (e.stdout || '').trim(),
      stderr: (e.stderr || '').trim(),
      exitCode: e.status ?? 1
    }
  }
}

function writePlan(dir: string, plan: object): void {
  writeFileSync(join(ralphDir, dir, 'plan.json'), JSON.stringify(plan, null, 2))
}

function readPlan(dir: string): any {
  return JSON.parse(readFileSync(join(ralphDir, dir, 'plan.json'), 'utf-8'))
}

function validPlan(overrides?: Partial<{ discoveryMethod: string; testCases: any[] }>): object {
  return {
    testSuite: {
      name: 'Test',
      generatedAt: new Date().toISOString(),
      status: 'pending',
      discoveryMethod: overrides?.discoveryMethod ?? 'uat-team'
    },
    testCases: overrides?.testCases ?? [
      {
        id: 'UAT-001',
        title: 'Login works',
        category: 'auth',
        type: 'e2e',
        testFile: 'tests/e2e/login.spec.ts',
        targetFiles: ['src/pages/login.tsx'],
        edgeCases: ['Empty password'],
        assertions: [
          { input: 'Fill email, submit', expected: 'Redirect to dashboard', strategy: 'keyword' },
          { input: 'Empty password', expected: 'Shows error', strategy: 'keyword' },
          { input: 'XSS in email', expected: 'Escaped', strategy: 'security' }
        ],
        passes: false,
        retryCount: 0,
        source: 'uat-team:happy-path'
      }
    ]
  }
}

// ============================================================================
// 1. CLI ROUTING — chaos-agent routes, old name rejected
// ============================================================================

describe('CLI routing for uat and chaos-agent', () => {
  it('chaos-agent is a recognized command (not "Unknown command")', () => {
    // Run help to check command is listed, since --plan-only would invoke claude
    const { stdout } = runRalph('help')
    expect(stdout).toContain('chaos-agent')
  })

  it('uat is a recognized command', () => {
    const { stdout } = runRalph('help')
    expect(stdout).toContain('uat')
  })

  it('old command name "chaos" is rejected as unknown', () => {
    const { stdout, stderr, exitCode } = runRalph('chaos')
    const combined = stdout + '\n' + stderr
    expect(combined).toContain('Unknown command: chaos')
    expect(exitCode).toBe(1)
  })

  it('help text shows chaos-agent, not bare chaos', () => {
    const { stdout } = runRalph('help')
    expect(stdout).toContain('chaos-agent')
    // Should not have "chaos " as a standalone command (allow "chaos-agent")
    const lines = stdout.split('\n')
    const chaosLines = lines.filter(l => /^\s+chaos\s/.test(l) && !l.includes('chaos-agent'))
    expect(chaosLines).toHaveLength(0)
  })
})

// ============================================================================
// 2. PLAN VALIDATION — reject bad plans, accept good ones
// ============================================================================

describe('plan validation (_validate_plan)', () => {
  it('accepts a valid plan', () => {
    writePlan('uat', validPlan())
    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_plan
    `)
    expect(exitCode).toBe(0)
  })

  it('rejects invalid JSON', () => {
    writeFileSync(join(ralphDir, 'uat', 'plan.json'), '{ broken json }}}')
    const { exitCode, stderr } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_plan
    `)
    expect(exitCode).not.toBe(0)
  })

  it('rejects plan missing testSuite', () => {
    writePlan('uat', { testCases: [] })
    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_plan
    `)
    expect(exitCode).not.toBe(0)
  })

  it('rejects plan missing testCases', () => {
    writePlan('uat', { testSuite: { name: 'Test' } })
    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_plan
    `)
    expect(exitCode).not.toBe(0)
  })

  it('rejects test case missing id', () => {
    writePlan('uat', validPlan({
      testCases: [{
        title: 'No ID',
        testFile: 'tests/x.spec.ts',
        assertions: [{ input: 'x', expected: 'y', strategy: 'keyword' }],
        passes: false
      }]
    }))
    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_plan
    `)
    expect(exitCode).not.toBe(0)
  })

  it('warns but accepts test case with no assertions', () => {
    writePlan('uat', validPlan({
      testCases: [{
        id: 'UAT-001',
        title: 'Shallow',
        testFile: 'tests/x.spec.ts',
        passes: false
      }]
    }))
    const { exitCode, stdout, stderr } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_plan
    `)
    // Warning, not failure
    expect(exitCode).toBe(0)
    const combined = stdout + '\n' + stderr
    expect(combined).toContain('no expected results defined')
  })
})

// ============================================================================
// 3. CONFIG NAMESPACE ISOLATION — chaos reads .chaos.*, uat reads .uat.*
// ============================================================================

describe('config namespace isolation', () => {
  it('uat reads from .uat config namespace', () => {
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      uat: { maxIterations: 42 },
      chaos: { maxIterations: 99 }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      echo $(get_config ".$UAT_CONFIG_NS.maxIterations" "20")
    `)
    expect(stdout).toBe('42')
  })

  it('chaos reads from .chaos config namespace', () => {
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      uat: { maxIterations: 42 },
      chaos: { maxIterations: 99 }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      echo $(get_config ".$UAT_CONFIG_NS.maxIterations" "20")
    `)
    expect(stdout).toBe('99')
  })

  it('falls back to default when namespace key missing', () => {
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({ checks: {} }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      echo $(get_config ".$UAT_CONFIG_NS.maxIterations" "20")
    `)
    expect(stdout).toBe('20')
  })

  it('UAT_CMD_NAME is chaos-agent for chaos mode', () => {
    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      echo "$UAT_CMD_NAME"
    `)
    expect(stdout).toBe('chaos-agent')
  })

  it('UAT_CMD_NAME defaults to subdir for uat mode', () => {
    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      echo "$UAT_CMD_NAME"
    `)
    expect(stdout).toBe('uat')
  })

  it('uat and chaos use separate directories', () => {
    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      uat_dir="$UAT_MODE_DIR"
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      chaos_dir="$UAT_MODE_DIR"
      [[ "$uat_dir" != "$chaos_dir" ]] && echo "SEPARATE" || echo "SAME"
    `)
    expect(stdout).toBe('SEPARATE')
  })
})

// ============================================================================
// 4. GIT SNAPSHOT + ROLLBACK — verify files actually restore
// ============================================================================

describe('git snapshot and rollback', () => {
  it('rollback restores files modified after snapshot', () => {
    // Create a source file and commit
    writeFileSync(join(testDir, 'src.ts'), 'const x = 1;')
    execSync('git add -A && git commit -m "add src" --no-verify', {
      cwd: testDir,
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      # Take snapshot
      _git_snapshot "UAT-001"

      # Modify file (simulating Claude)
      echo 'const x = 999;' > src.ts

      # Verify file is modified
      if grep -q "999" src.ts; then
        echo "MODIFIED"
      fi

      # Rollback
      _rollback_to_snapshot "UAT-001"

      # Verify file is restored
      cat src.ts
    `)
    expect(stdout).toContain('MODIFIED')
    expect(stdout).toContain('const x = 1;')
  })

  it('rollback restores deleted files', () => {
    writeFileSync(join(testDir, 'important.ts'), 'export default 42;')
    execSync('git add -A && git commit -m "add important" --no-verify', {
      cwd: testDir,
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _git_snapshot "UAT-002"
      rm important.ts
      _rollback_to_snapshot "UAT-002"
      [[ -f important.ts ]] && echo "RESTORED" || echo "LOST"
    `)
    expect(stdout).toContain('RESTORED')
  })
})

// ============================================================================
// 5. RED PHASE — _has_app_changes detects app code modifications
// ============================================================================

describe('RED phase constraint: _has_app_changes', () => {
  it('detects app file modification alongside test file', () => {
    // Setup: committed source file
    mkdirSync(join(testDir, 'src'), { recursive: true })
    writeFileSync(join(testDir, 'src', 'app.ts'), 'const app = true;')
    mkdirSync(join(testDir, 'tests'), { recursive: true })
    writeFileSync(join(testDir, 'tests', 'app.spec.ts'), 'test("x", () => {});')
    execSync('git add -A && git commit -m "add src" --no-verify', {
      cwd: testDir,
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      # Modify both test and app file
      echo 'const app = false;' > src/app.ts
      echo 'test("y", () => {});' > tests/app.spec.ts

      if _has_app_changes "tests/app.spec.ts"; then
        echo "DETECTED"
      else
        echo "MISSED"
      fi
    `)
    expect(stdout).toBe('DETECTED')
  })

  it('allows test-only changes (no app modifications)', () => {
    mkdirSync(join(testDir, 'src'), { recursive: true })
    writeFileSync(join(testDir, 'src', 'app.ts'), 'const app = true;')
    mkdirSync(join(testDir, 'tests'), { recursive: true })
    writeFileSync(join(testDir, 'tests', 'app.spec.ts'), 'test("x", () => {});')
    execSync('git add -A && git commit -m "add src" --no-verify', {
      cwd: testDir,
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      # Only modify the test file
      echo 'test("y", () => {});' > tests/app.spec.ts

      if _has_app_changes "tests/app.spec.ts"; then
        echo "DETECTED"
      else
        echo "CLEAN"
      fi
    `)
    expect(stdout).toBe('CLEAN')
  })

  it('ignores .ralph/ directory changes', () => {
    mkdirSync(join(testDir, 'src'), { recursive: true })
    writeFileSync(join(testDir, 'src', 'app.ts'), 'const app = true;')
    execSync('git add -A && git commit -m "add src" --no-verify', {
      cwd: testDir,
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      # Only modify .ralph files (progress, plan, etc.)
      echo "log entry" >> .ralph/uat/progress.txt

      if _has_app_changes "tests/new.spec.ts"; then
        echo "DETECTED"
      else
        echo "CLEAN"
      fi
    `)
    expect(stdout).toBe('CLEAN')
  })
})

// ============================================================================
// 6. GREEN PHASE — _test_file_modified detects test tampering
// ============================================================================

describe('GREEN phase constraint: _test_file_modified', () => {
  it('detects when test file is modified after commit', () => {
    mkdirSync(join(testDir, 'tests'), { recursive: true })
    writeFileSync(join(testDir, 'tests', 'login.spec.ts'), 'test("login", () => { expect(1).toBe(1); });')
    execSync('git add -A && git commit -m "add test" --no-verify', {
      cwd: testDir,
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      # Tamper with the test (simulating Claude weakening assertions)
      echo 'test("login", () => {});' > tests/login.spec.ts

      if _test_file_modified "tests/login.spec.ts"; then
        echo "TAMPERED"
      else
        echo "MISSED"
      fi
    `)
    expect(stdout).toBe('TAMPERED')
  })

  it('allows unmodified test file', () => {
    mkdirSync(join(testDir, 'tests'), { recursive: true })
    writeFileSync(join(testDir, 'tests', 'login.spec.ts'), 'test("login", () => { expect(1).toBe(1); });')
    execSync('git add -A && git commit -m "add test" --no-verify', {
      cwd: testDir,
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      if _test_file_modified "tests/login.spec.ts"; then
        echo "TAMPERED"
      else
        echo "CLEAN"
      fi
    `)
    expect(stdout).toBe('CLEAN')
  })
})

// ============================================================================
// 7. CIRCUIT BREAKER — retries capped, case skipped
// ============================================================================

describe('circuit breaker (retry limits)', () => {
  it('skips test case when combined retries exceed max', () => {
    // Write a plan where a case has hit the retry limit
    const plan = validPlan({
      testCases: [{
        id: 'UAT-001',
        title: 'Flaky test',
        category: 'auth',
        type: 'e2e',
        testFile: 'tests/e2e/flaky.spec.ts',
        targetFiles: [],
        edgeCases: [],
        assertions: [{ input: 'x', expected: 'y', strategy: 'keyword' }],
        passes: false,
        retryCount: 5,
        redRetries: 3,
        greenRetries: 2
      }]
    })
    writePlan('uat', plan)

    // The circuit breaker in _run_uat_loop checks total_retries >= max_case_retries
    // We can test the jq + logic directly
    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"

      case_json=$(jq '.testCases[0]' "$UAT_PLAN_FILE")
      red_retries=$(echo "$case_json" | jq -r '.redRetries // 0')
      green_retries=$(echo "$case_json" | jq -r '.greenRetries // 0')
      total_retries=$((red_retries + green_retries))
      max_case_retries=5

      if [[ $total_retries -ge $max_case_retries ]]; then
        echo "BREAKER_TRIPPED"
      else
        echo "CONTINUE"
      fi
    `)
    expect(stdout).toBe('BREAKER_TRIPPED')
  })

  it('continues when retries are below max', () => {
    const plan = validPlan({
      testCases: [{
        id: 'UAT-001',
        title: 'Recoverable test',
        category: 'auth',
        type: 'e2e',
        testFile: 'tests/e2e/recover.spec.ts',
        targetFiles: [],
        edgeCases: [],
        assertions: [{ input: 'x', expected: 'y', strategy: 'keyword' }],
        passes: false,
        retryCount: 3,
        redRetries: 2,
        greenRetries: 1
      }]
    })
    writePlan('uat', plan)

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"

      case_json=$(jq '.testCases[0]' "$UAT_PLAN_FILE")
      red_retries=$(echo "$case_json" | jq -r '.redRetries // 0')
      green_retries=$(echo "$case_json" | jq -r '.greenRetries // 0')
      total_retries=$((red_retries + green_retries))
      max_case_retries=5

      if [[ $total_retries -ge $max_case_retries ]]; then
        echo "BREAKER_TRIPPED"
      else
        echo "CONTINUE"
      fi
    `)
    expect(stdout).toBe('CONTINUE')
  })

  it('retry increment updates plan.json correctly', () => {
    writePlan('uat', validPlan())

    runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _increment_red_retry "UAT-001"
      _increment_red_retry "UAT-001"
      _increment_green_retry "UAT-001"
    `)

    const plan = readPlan('uat')
    const tc = plan.testCases[0]
    expect(tc.redRetries).toBe(2)
    expect(tc.greenRetries).toBe(1)
    expect(tc.retryCount).toBe(3)
  })
})

// ============================================================================
// 8. STALE LOCK DETECTION
// ============================================================================

describe('lock file handling', () => {
  it('detects stale lock (dead PID) and proceeds', () => {
    // Write a lock with a PID that definitely doesn't exist
    writeFileSync(join(ralphDir, '.lock'), '99999999')

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      # _acquire_uat_lock sets trap, which would exit. Test the stale detection logic directly.
      lockfile="$RALPH_DIR/.lock"
      pid=$(cat "$lockfile")
      if kill -0 "$pid" 2>/dev/null; then
        echo "BLOCKED"
      else
        rm -f "$lockfile"
        echo "STALE_REMOVED"
      fi
    `)
    expect(stdout).toBe('STALE_REMOVED')
    // Lock file should be gone
    expect(existsSync(join(ralphDir, '.lock'))).toBe(false)
  })
})

// ============================================================================
// 9. TEST QUALITY VALIDATION — shallow test rejection
// ============================================================================

describe('test quality validation (_validate_test_quality)', () => {
  beforeEach(() => {
    mkdirSync(join(testDir, 'tests', 'e2e'), { recursive: true })
  })

  it('rejects test with zero assertions', () => {
    writeFileSync(join(testDir, 'tests', 'e2e', 'empty.spec.ts'),
      'import { test } from "@playwright/test";\ntest("empty", async ({ page }) => {\n  await page.goto("/");\n});'
    )

    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_test_quality "tests/e2e/empty.spec.ts" "UAT-001"
    `)
    expect(exitCode).not.toBe(0)
  })

  it('rejects test with only structural assertions (no content)', () => {
    writeFileSync(join(testDir, 'tests', 'e2e', 'structural.spec.ts'),
      `import { test, expect } from "@playwright/test";
test("shallow", async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page).toHaveURL("/dashboard");
  await expect(page.locator("nav")).toBeVisible();
  await expect(page.locator("footer")).toBeVisible();
});`
    )

    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_test_quality "tests/e2e/structural.spec.ts" "UAT-001"
    `)
    expect(exitCode).not.toBe(0)
  })

  it('accepts test with content assertions and input-output pattern', () => {
    writeFileSync(join(testDir, 'tests', 'e2e', 'good.spec.ts'),
      `import { test, expect } from "@playwright/test";
test("login flow", async ({ page }) => {
  await page.goto("/login");
  await page.getByLabel("Email").fill("user@test.com");
  await page.getByLabel("Password").fill("pass123");
  await page.getByRole("button", { name: "Login" }).click();
  await expect(page.getByText("Welcome, User")).toBeVisible();
  await expect(page.getByText("Dashboard")).toContain("Dashboard");
});`
    )

    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_test_quality "tests/e2e/good.spec.ts" "UAT-001"
    `)
    expect(exitCode).toBe(0)
  })

  it('rejects e2e test that checks content but never interacts', () => {
    writeFileSync(join(testDir, 'tests', 'e2e', 'passive.spec.ts'),
      `import { test, expect } from "@playwright/test";
test("passive check", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByText("Welcome")).toBeVisible();
  await expect(page.getByText("Home")).toContain("Home");
});`
    )

    const { exitCode } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _validate_test_quality "tests/e2e/passive.spec.ts" "UAT-001"
    `)
    // e2e with page. references but no fill/click = shallow
    expect(exitCode).not.toBe(0)
  })
})

// ============================================================================
// 10. FAILURE CLASSIFICATION — test bug vs app bug
// ============================================================================

describe('RED failure classification (_classify_red_failure)', () => {
  it('classifies SyntaxError as test_bug', () => {
    writeFileSync(join(ralphDir, 'uat', 'last_test_output.log'),
      'Error: SyntaxError: Unexpected token }\n  at tests/e2e/login.spec.ts:5:1'
    )

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _classify_red_failure "tests/e2e/login.spec.ts" "UAT-001"
    `)
    expect(stdout).toContain('test_bug')
  })

  it('classifies Cannot find module as test_bug', () => {
    writeFileSync(join(ralphDir, 'uat', 'last_test_output.log'),
      "Error: Cannot find module '@playwright/test'\n  Require stack:"
    )

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _classify_red_failure "tests/e2e/login.spec.ts" "UAT-001"
    `)
    expect(stdout).toContain('test_bug')
  })

  it('classifies assertion failure as app_bug', () => {
    writeFileSync(join(ralphDir, 'uat', 'last_test_output.log'),
      'Error: expect(received).toContain(expected)\n  Expected: "Welcome, John"\n  Received: "Error 500"'
    )

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _classify_red_failure "tests/e2e/login.spec.ts" "UAT-001"
    `)
    expect(stdout).toContain('app_bug')
  })

  it('classifies as app_bug when no log file exists', () => {
    // Ensure no log file
    rmSync(join(ralphDir, 'uat', 'last_test_output.log'), { force: true })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _classify_red_failure "tests/e2e/login.spec.ts" "UAT-001"
    `)
    expect(stdout).toContain('app_bug')
  })
})

// ============================================================================
// 11. PHASE STATE TRANSITIONS — mark_phase, mark_passed
// ============================================================================

describe('phase state transitions in plan.json', () => {
  it('mark_phase sets phase to "red" (transitioning to GREEN)', () => {
    writePlan('uat', validPlan())

    runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _mark_phase "UAT-001" "red"
    `)

    const plan = readPlan('uat')
    expect(plan.testCases[0].phase).toBe('red')
  })

  it('mark_passed resets all retry state', () => {
    const plan = validPlan({
      testCases: [{
        id: 'UAT-001',
        title: 'Test',
        category: 'auth',
        type: 'e2e',
        testFile: 'tests/x.spec.ts',
        targetFiles: [],
        edgeCases: [],
        assertions: [{ input: 'x', expected: 'y', strategy: 'keyword' }],
        passes: false,
        retryCount: 4,
        redRetries: 2,
        greenRetries: 2,
        phase: 'red'
      }]
    })
    writePlan('uat', plan)

    runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _mark_passed "UAT-001"
    `)

    const result = readPlan('uat')
    const tc = result.testCases[0]
    expect(tc.passes).toBe(true)
    expect(tc.retryCount).toBe(0)
    expect(tc.redRetries).toBe(0)
    expect(tc.greenRetries).toBe(0)
    expect(tc.phase).toBeNull()
  })
})

// ============================================================================
// 12. ARCHIVE — plan archived after run
// ============================================================================

describe('plan archiving (_archive_plan)', () => {
  it('creates timestamped archive file in archive dir', () => {
    writePlan('uat', validPlan())

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _archive_plan
      ls "$UAT_MODE_DIR/archive/" | grep "plan-"
    `)
    // stdout includes print_info output; extract just the filename line
    const lines = stdout.split('\n')
    const archiveLine = lines.find(l => l.startsWith('plan-'))!
    expect(archiveLine).toMatch(/^plan-\d{8}-\d{6}\.json$/)
  })

  it('archived plan contains gitHash matching current HEAD', () => {
    writePlan('chaos', validPlan({ discoveryMethod: 'chaos-agent' }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      _archive_plan
      # Read the gitHash from the archived plan
      latest=$(ls -1t "$UAT_MODE_DIR/archive/"plan-*.json | head -1)
      jq -r '.testSuite.gitHash' "$latest"
    `)

    // Get current HEAD for comparison
    const head = execSync('git rev-parse HEAD', {
      cwd: testDir,
      encoding: 'utf-8',
      env: { ...process.env, ...GIT_ENV }
    }).trim()

    // stdout includes print_info output; last line is the hash
    const lastLine = stdout.split('\n').pop()!.trim()
    expect(lastLine).toBe(head)
  })

  it('prunes oldest archives when count exceeds MAX_UAT_ARCHIVE_COUNT', () => {
    mkdirSync(join(ralphDir, 'uat', 'archive'), { recursive: true })

    // Create 22 fake archives (exceeds limit of 20)
    for (let i = 0; i < 22; i++) {
      const ts = `20260101-${String(i).padStart(6, '0')}`
      writeFileSync(
        join(ralphDir, 'uat', 'archive', `plan-${ts}.json`),
        JSON.stringify(validPlan())
      )
    }

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _prune_archives
      ls "$UAT_MODE_DIR/archive/"plan-*.json | wc -l | tr -d ' '
    `)
    expect(parseInt(stdout)).toBe(20)
  })

  it('archive is skipped when UAT_TESTS_WRITTEN is 0', () => {
    writePlan('uat', validPlan())

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      UAT_TESTS_WRITTEN=0
      # Simulate the guard from run_uat
      if [[ "$UAT_TESTS_WRITTEN" -gt 0 ]]; then
        _archive_plan
        echo "ARCHIVED"
      else
        echo "SKIPPED"
      fi
    `)
    expect(stdout).toBe('SKIPPED')
  })
})

// ============================================================================
// 13. AUTO-LESSON — chaos-agent learns from fixed vulnerabilities
// ============================================================================

describe('auto-lesson from fixed vulnerabilities (_auto_lesson_from_case)', () => {
  it('adds lesson to lessons.json with category security for chaos mode', () => {
    const plan = validPlan({
      discoveryMethod: 'chaos-agent',
      testCases: [{
        id: 'UAT-001',
        title: 'XSS in search input',
        category: 'security',
        type: 'e2e',
        testFile: 'tests/e2e/xss.spec.ts',
        testApproach: 'Inject script tags and verify escaping',
        targetFiles: ['src/pages/search.tsx'],
        edgeCases: [],
        assertions: [{ input: '<script>alert(1)</script>', expected: 'Escaped output', strategy: 'security' }],
        passes: true,
        retryCount: 0,
        source: 'chaos-agent:security'
      }]
    })
    writePlan('chaos', plan)

    runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      _auto_lesson_from_case "UAT-001"
    `)

    const lessons = JSON.parse(readFileSync(join(ralphDir, 'lessons.json'), 'utf-8'))
    expect(lessons.lessons.length).toBe(1)
    expect(lessons.lessons[0].category).toBe('security')
    expect(lessons.lessons[0].pattern).toContain('XSS in search input')
    expect(lessons.lessons[0].pattern).toContain('Inject script tags')
  })

  it('is a no-op for UAT mode (UAT_CONFIG_NS != chaos)', () => {
    const plan = validPlan({
      testCases: [{
        id: 'UAT-001',
        title: 'Login form validates email',
        category: 'auth',
        type: 'e2e',
        testFile: 'tests/e2e/login.spec.ts',
        testApproach: 'Submit invalid email',
        targetFiles: ['src/pages/login.tsx'],
        edgeCases: [],
        assertions: [{ input: 'invalid', expected: 'Error shown', strategy: 'keyword' }],
        passes: true,
        retryCount: 0,
        source: 'uat-team:happy-path'
      }]
    })
    writePlan('uat', plan)

    runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _auto_lesson_from_case "UAT-001"
    `)

    const lessons = JSON.parse(readFileSync(join(ralphDir, 'lessons.json'), 'utf-8'))
    expect(lessons.lessons.length).toBe(0)
  })

  it('does not add duplicate patterns', () => {
    const plan = validPlan({
      discoveryMethod: 'chaos-agent',
      testCases: [{
        id: 'UAT-001',
        title: 'XSS in search input',
        category: 'security',
        type: 'e2e',
        testFile: 'tests/e2e/xss.spec.ts',
        testApproach: 'Inject script tags and verify escaping',
        targetFiles: ['src/pages/search.tsx'],
        edgeCases: [],
        assertions: [{ input: '<script>', expected: 'Escaped', strategy: 'security' }],
        passes: true,
        retryCount: 0,
        source: 'chaos-agent:security'
      }]
    })
    writePlan('chaos', plan)

    // Run twice
    runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      _auto_lesson_from_case "UAT-001"
      _auto_lesson_from_case "UAT-001"
    `)

    const lessons = JSON.parse(readFileSync(join(ralphDir, 'lessons.json'), 'utf-8'))
    expect(lessons.lessons.length).toBe(1)
  })

  it('builds pattern from title + testApproach', () => {
    const plan = validPlan({
      discoveryMethod: 'chaos-agent',
      testCases: [{
        id: 'UAT-001',
        title: 'SQL injection in login',
        category: 'security',
        type: 'e2e',
        testFile: 'tests/e2e/sqli.spec.ts',
        testApproach: 'Use parameterized queries instead of string concatenation',
        targetFiles: ['src/api/auth.ts'],
        edgeCases: [],
        assertions: [{ input: "'; DROP TABLE users; --", expected: 'Query escaped', strategy: 'security' }],
        passes: true,
        retryCount: 0,
        source: 'chaos-agent:security'
      }]
    })
    writePlan('chaos', plan)

    runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      _auto_lesson_from_case "UAT-001"
    `)

    const lessons = JSON.parse(readFileSync(join(ralphDir, 'lessons.json'), 'utf-8'))
    expect(lessons.lessons[0].pattern).toBe('SQL injection in login -- Use parameterized queries instead of string concatenation')
  })
})

// ============================================================================
// 14. HISTORY INJECTION — archive summary and changed files
// ============================================================================

describe('history injection into discovery prompts', () => {
  it('_build_archive_summary outputs prior run history when archives exist', () => {
    mkdirSync(join(ralphDir, 'uat', 'archive'), { recursive: true })
    writeFileSync(
      join(ralphDir, 'uat', 'archive', 'plan-20260209-120000.json'),
      JSON.stringify(validPlan({
        testCases: [{
          id: 'UAT-001',
          title: 'Login works',
          category: 'auth',
          type: 'e2e',
          testFile: 'tests/e2e/login.spec.ts',
          targetFiles: [],
          edgeCases: [],
          assertions: [{ input: 'x', expected: 'y', strategy: 'keyword' }],
          passes: true,
          retryCount: 0
        }]
      }))
    )

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _build_archive_summary
    `)
    expect(stdout).toContain('Prior Run History')
    expect(stdout).toContain('ALREADY been run')
    expect(stdout).toContain('UAT-001')
    expect(stdout).toContain('PASSED')
  })

  it('_build_archive_summary outputs nothing when no archives exist', () => {
    // No archive dir created
    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _build_archive_summary
      echo "END"
    `)
    expect(stdout).toBe('END')
  })

  it('_build_changed_files_section lists files changed since archived git hash', () => {
    // Create an archive with the current HEAD hash
    mkdirSync(join(ralphDir, 'uat', 'archive'), { recursive: true })
    const head = execSync('git rev-parse HEAD', {
      cwd: testDir,
      encoding: 'utf-8',
      env: { ...process.env, ...GIT_ENV }
    }).trim()

    writeFileSync(
      join(ralphDir, 'uat', 'archive', 'plan-20260209-120000.json'),
      JSON.stringify({ testSuite: { gitHash: head }, testCases: [] })
    )

    // Make a new commit with a changed file
    writeFileSync(join(testDir, 'src-new.ts'), 'const x = 1;')
    execSync('git add -A && git commit -m "add src-new" --no-verify', {
      cwd: testDir,
      encoding: 'utf-8',
      env: { ...process.env, ...GIT_ENV }
    })

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _build_changed_files_section
    `)
    expect(stdout).toContain('Files Changed Since Last Run')
    expect(stdout).toContain('src-new.ts')
  })

  it('_build_changed_files_section outputs nothing on first run (no archive)', () => {
    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      _build_changed_files_section
      echo "END"
    `)
    expect(stdout).toBe('END')
  })
})

// ============================================================================
// 15. PLAN RESET — plan.json deleted after archive
// ============================================================================

describe('plan reset after archive', () => {
  it('plan.json is deleted after archive so next run starts fresh', () => {
    writePlan('uat', validPlan())

    const { stdout } = runUatBash(`
      _init_uat_dirs "uat" "UAT"
      UAT_TESTS_WRITTEN=1
      # Simulate the archive + reset from run_uat
      _archive_plan
      rm -f "$UAT_PLAN_FILE"
      [[ -f "$UAT_PLAN_FILE" ]] && echo "EXISTS" || echo "DELETED"
    `)
    expect(stdout).toContain('DELETED')

    // But archive should exist
    const archiveDir = join(ralphDir, 'uat', 'archive')
    const archives = execSync(`ls ${archiveDir}/plan-*.json 2>/dev/null | wc -l`, {
      encoding: 'utf-8'
    }).trim()
    expect(parseInt(archives)).toBeGreaterThan(0)
  })
})

// ============================================================================
// 16. DOCKER ISOLATION — override generation, isolation decision, prompt injection
// ============================================================================

describe('Docker isolation (_should_use_docker_isolation)', () => {
  it('sets CHAOS_ISOLATION_RESULT="true" when compose file exists and Docker available', () => {
    // Create a compose file
    writeFileSync(join(testDir, 'docker-compose.yml'), `
services:
  web:
    ports:
      - "5173:5173"
  api:
    ports:
      - "8001:8001"
`)

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      # Mock _detect_compose_cmd to return a value (Docker may not be installed in CI)
      _detect_compose_cmd() { echo "docker compose"; }
      _should_use_docker_isolation
      echo "RESULT=$CHAOS_ISOLATION_RESULT"
      echo "CMD=$CHAOS_COMPOSE_CMD"
      echo "FILE=$CHAOS_COMPOSE_FILE"
    `)
    expect(stdout).toContain('RESULT=true')
    // Verify globals are preserved (not lost in subshell)
    expect(stdout).toContain('CMD=docker compose')
    expect(stdout).toContain('FILE=docker-compose.yml')
  })

  it('sets CHAOS_ISOLATION_RESULT="false" when chaos.isolate is false', () => {
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { isolate: false }
    }))
    writeFileSync(join(testDir, 'docker-compose.yml'), 'services:\n  web:\n    ports:\n      - "5173:5173"')

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      _detect_compose_cmd() { echo "docker compose"; }
      _should_use_docker_isolation
      echo "RESULT=$CHAOS_ISOLATION_RESULT"
    `)
    expect(stdout).toContain('RESULT=false')
  })

  it('sets CHAOS_ISOLATION_RESULT="false" when no compose file exists', () => {
    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      _detect_compose_cmd() { echo "docker compose"; }
      _should_use_docker_isolation
      echo "RESULT=$CHAOS_ISOLATION_RESULT"
    `)
    expect(stdout).toContain('RESULT=false')
  })
})

describe('Docker override generation (_generate_chaos_override)', () => {
  it('produces override YAML with offset ports', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  web:
    ports:
      - "5173:5173"
  api:
    ports:
      - "8001:8001"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      cat "$CHAOS_OVERRIDE_FILE"
    `)
    expect(stdout).toContain('15173:5173')
    expect(stdout).toContain('18001:8001')
  })

  it('handles multiple port mappings per service', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  api:
    ports:
      - "8001:8001"
      - "8002:8002"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      cat "$CHAOS_OVERRIDE_FILE"
    `)
    expect(stdout).toContain('18001:8001')
    expect(stdout).toContain('18002:8002')
  })

  it('rejects ports that would exceed 65535', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  web:
    ports:
      - "60000:60000"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { exitCode, stdout, stderr } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
    `)
    const combined = stdout + '\n' + stderr
    expect(combined).toContain('exceeds 65535')
    expect(exitCode).not.toBe(0)
  })

  it('handles quoted port formats', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  web:
    ports:
      - "5173:5173"
  api:
    ports:
      - 8001:8001
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      cat "$CHAOS_OVERRIDE_FILE"
    `)
    expect(stdout).toContain('15173:5173')
    expect(stdout).toContain('18001:8001')
  })

  it('handles three-part port format with IP binding', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  api:
    ports:
      - "127.0.0.1:8001:8001"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      cat "$CHAOS_OVERRIDE_FILE"
    `)
    expect(stdout).toContain('127.0.0.1:18001:8001')
  })

  it('rejects network_mode: host', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  api:
    network_mode: host
    ports:
      - "8001:8001"
`)

    const { exitCode, stdout, stderr } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
    `)
    const combined = stdout + '\n' + stderr
    expect(combined).toContain('network_mode: host')
    expect(exitCode).not.toBe(0)
  })

  it('skips services without ports', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  redis:
    image: redis:7
  web:
    ports:
      - "5173:5173"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      cat "$CHAOS_OVERRIDE_FILE"
    `)
    expect(stdout).toContain('15173:5173')
    expect(stdout).not.toContain('redis')
  })

  it('handles service names with digits and dots', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  db.master:
    ports:
      - "5432:5432"
  redis6:
    ports:
      - "6379:6379"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      cat "$CHAOS_OVERRIDE_FILE"
    `)
    expect(stdout).toContain('db.master')
    expect(stdout).toContain('15432:5432')
    expect(stdout).toContain('redis6')
    expect(stdout).toContain('16379:6379')
  })

  it('handles comments between port entries', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  api:
    ports:
      - "4000:4000"
      # Debug port
      - "9229:9229"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      cat "$CHAOS_OVERRIDE_FILE"
    `)
    expect(stdout).toContain('14000:4000')
    expect(stdout).toContain('19229:9229')
  })

  it('sets CHAOS_OVERRIDE_FILE global (not lost in subshell)', () => {
    writeFileSync(join(testDir, 'docker-compose.yml'), `services:
  web:
    ports:
      - "5173:5173"
`)
    writeFileSync(join(ralphDir, 'config.json'), JSON.stringify({
      checks: {},
      chaos: { docker: { portOffset: 10000 } }
    }))

    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_COMPOSE_FILE="docker-compose.yml"
      _generate_chaos_override
      [[ -n "$CHAOS_OVERRIDE_FILE" && -f "$CHAOS_OVERRIDE_FILE" ]] && echo "GLOBAL_SET" || echo "GLOBAL_LOST"
    `)
    expect(stdout).toContain('GLOBAL_SET')
  })
})

describe('chaos prompt Docker injection', () => {
  it('includes "ISOLATED ENVIRONMENT" when CHAOS_FRONTEND_URL is set', () => {
    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_FRONTEND_URL="http://localhost:15173"
      CHAOS_API_URL="http://localhost:18001"
      prompt_file=$(create_temp_file ".chaos-prompt.md")
      _build_chaos_agent_prompt "$prompt_file"
      cat "$prompt_file"
    `)
    expect(stdout).toContain('ISOLATED ENVIRONMENT')
    expect(stdout).toContain('http://localhost:15173')
    expect(stdout).toContain('http://localhost:18001')
    expect(stdout).not.toContain('Non-Destructive Testing')
  })

  it('includes "Non-Destructive Testing" when no Docker isolation', () => {
    const { stdout } = runUatBash(`
      _init_uat_dirs "chaos" "Chaos Agent" "chaos-agent"
      CHAOS_FRONTEND_URL=""
      CHAOS_API_URL=""
      prompt_file=$(create_temp_file ".chaos-prompt.md")
      _build_chaos_agent_prompt "$prompt_file"
      cat "$prompt_file"
    `)
    expect(stdout).toContain('Non-Destructive Testing')
    expect(stdout).not.toContain('ISOLATED ENVIRONMENT')
  })
})
