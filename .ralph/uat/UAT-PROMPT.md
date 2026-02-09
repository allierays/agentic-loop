# UAT Guide — agentic-loop (Ralph CLI)

## App Overview
- **What it does**: Ralph is an autonomous AI development loop CLI tool written in Bash. It orchestrates Claude CLI to build features from PRDs, running code generation, verification, and testing loops.
- **Tech stack**: Bash (primary), Node.js/TypeScript (tests, build tooling), Vitest (test framework)
- **No web frontend**: This is a CLI tool. All testing is integration-level (shell commands, file I/O, config parsing). No Playwright E2E browser tests needed for the core CLI.

## Project Structure
```
bin/
  ralph.sh          # Main CLI entry point, routes commands
  agentic-loop.sh   # Symlink wrapper, passes through to ralph.sh
ralph/
  utils.sh          # Shared constants, utilities (get_config, log_progress, etc.)
  init.sh           # ralph init + ralph_help()
  setup.sh          # ralph setup
  loop.sh           # Main autonomous loop (run_loop), arg parsing, story execution
  code-check.sh     # Post-Claude verification pipeline (lint, tests, API smoke)
  prd-check.sh      # PRD validation
  prd.sh            # PRD generation
  signs.sh          # Learned patterns
  backup.sh         # Database backup/restore
  ci.sh             # CI integration
  test.sh           # Test execution
  uat.sh            # UAT loop
  verify/            # Verification submodules
    lint.sh
    tests.sh
    api.sh
tests/              # Vitest test files (.test.ts)
templates/          # Config templates per project type
```

## Test Infrastructure
- **Framework**: Vitest (`npm test` or `vitest run`)
- **Pattern**: Tests source Bash scripts via `execSync` with `bash -c '...'`
- **Temp directories**: Tests create isolated temp dirs in `os.tmpdir()` with `beforeEach`/`afterEach` cleanup
- **Helper pattern**: Each test file has a `runBash()` helper that sets `RALPH_DIR` and sources the needed `.sh` files
- **Environment**: `NO_COLOR=1` to strip ANSI codes from output
- **Test file location**: `tests/*.test.ts`

## Key Functions & How to Test Them

### get_config (utils.sh)
```bash
export RALPH_DIR="$testDir"
source ralph/utils.sh
result=$(get_config '.key.path' 'default_value')
```
- Reads from `$RALPH_DIR/config.json`
- Returns default if key missing, file missing, or value is null

### log_progress (utils.sh)
```bash
export RALPH_DIR="$testDir"
source ralph/utils.sh
log_progress "STORY-ID" "STATUS" "optional message"
# Appends to $RALPH_DIR/progress.txt
# Auto-rotates at MAX_PROGRESS_FILE_LINES (1000)
```

### _migrate_config (utils.sh)
```bash
export RALPH_DIR="$testDir"
source ralph/utils.sh
_migrate_config
# Migrates testUrlBase -> urls.frontend in config.json
```

### run_loop argument parsing (loop.sh)
- `--quiet` sets `quiet_mode=true`
- `--fast` sets `fast_mode=true`
- `--max N` sets `max_iterations=N`
- `--story ID` sets `specific_story=ID`
- Config fallback: `quiet_mode` reads from `.quiet` in config.json

### ralph init (init.sh)
- Creates `.ralph/` directory structure
- Copies config template based on detected project type
- Creates `signs.json`, `progress.txt`, `PROMPT.md`
- Idempotent: second call says "already initialized"

## CLI Commands & Expected Behavior
| Command | Expected Output | Exit Code |
|---------|----------------|-----------|
| `ralph` (no args) | Help text | 0 |
| `ralph help` | Help text | 0 |
| `ralph --help` | Help text | 0 |
| `ralph -h` | Help text | 0 |
| `ralph version` | `ralph X.Y.Z (agentic-loop)` | 0 |
| `ralph --version` | Same as version | 0 |
| `ralph -v` | Same as version | 0 |
| `ralph status` | Feature status + story progress | 0 |
| `ralph check` | Run verification pipeline | 0 |
| `ralph signs` | List signs or "No signs" | 0 |
| `ralph progress` | Last 50 lines of progress.txt | 0 |
| `ralph stop` | Creates `.ralph/.stop` signal file | 0 |
| `ralph skip` | Creates `.ralph/.skip` signal file | 0 |
| `ralph nonexistent` | Error + help text | 1 |
| `ralph verify` (no ID) | Usage error | 1 |

## Constants (utils.sh)
```bash
RALPH_VERSION       # from package.json (e.g., "3.20.0")
RALPH_LOOP_VERSION  # "2" (readonly)
MAX_LOG_LINES       # 30
MAX_PROGRESS_FILE_LINES  # 1000
DEFAULT_TIMEOUT_SECONDS  # 600
```

## Config File Format (.ralph/config.json)
```json
{
  "checks": { "lint": true, "typecheck": true, "build": "final", "test": true },
  "commands": { "test": "uv run pytest", "dev": "", "install": "" },
  "urls": { "frontend": "http://localhost:3000" },
  "api": { "baseUrl": "http://localhost:3000" },
  "quiet": false,
  "maxIterations": 20,
  "maxSessionSeconds": 600
}
```

## Signal Files
- `.ralph/.stop` — Created by `ralph stop`, consumed by loop (removed before `run_loop`)
- `.ralph/.skip` — Created by `ralph skip`, consumed mid-loop
- `.ralph/.blocked` — Created by Claude when stuck, read + deleted by loop, reason saved to `.ralph/failures/{story-id}.txt`
- `.ralph/.lock` — Lock file for concurrent execution prevention

## Project Type Detection Priority
In `bin/ralph.sh` (lines 43-62):
1. `pyproject.toml` with `fastmcp` → `fastmcp`
2. `pyproject.toml` with `fastapi` → `fastapi`
3. `pyproject.toml` with `django` or `manage.py` → `django`
4. `pyproject.toml` (other) → `python`
5. `go.mod` → `go`
6. `Cargo.toml` → `rust`
7. `frontend/` + (`backend/` | `core/` | `apps/`) → `fullstack`
8. `package.json` → `node`
9. None → `minimal`

## Observations from Exploration

### Side Effects
- `ralph stop` and `ralph skip` trigger the full startup sequence (config auto-detection, file creation) even in directories without prior `ralph init`. This creates `.ralph/config.json`, `PROMPT.md`, `signs.json` as a side effect. Whether this is intended behavior or a bug depends on design intent.

### Help Text Consistency
- `bin/agentic-loop.sh` header comments document run flags (lines 8-12)
- `ralph_help()` in `ralph/init.sh` has the full help text (lines 666-749)
- Both locations include `--quiet` consistently

### Test Patterns to Follow
When writing new tests:
1. Import from `vitest`: `{ describe, it, expect, beforeEach, afterEach }`
2. Create temp dir: `join(tmpdir(), 'ralph-test-${Date.now()}')`
3. Set `RALPH_DIR` to temp dir's `.ralph` subdirectory
4. Source scripts: `source "${PROJECT_ROOT}/ralph/utils.sh"`
5. Strip colors: `env: { ...process.env, NO_COLOR: '1' }`
6. Clean up in `afterEach`: `rmSync(testDir, { recursive: true, force: true })`
