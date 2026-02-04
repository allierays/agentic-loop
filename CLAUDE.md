# Claude Code Instructions for agentic-loop

## Project Overview
Ralph is an autonomous AI development loop written in Bash. It orchestrates Claude CLI for automated development workflows including code generation, verification, and testing.

## Naming Conventions

### Bash (ralph/*.sh)
- **Functions**: `snake_case` — e.g., `run_verification`, `parse_endpoint`, `get_config`
- **Local variables**: `snake_case` — e.g., `story_id`, `base_url`, `failed`
- **Constants**: `SCREAMING_SNAKE` — e.g., `MAX_LOG_LINES`, `DEFAULT_TIMEOUT_SECONDS`
- **Global state variables**: `SCREAMING_SNAKE` — e.g., `RALPH_DIR`, `BACKUP_QUIET`
- **Private/helper functions**: `_prefixed_snake_case` — e.g., `_inject_story_context`

### TypeScript/JavaScript (src/*, tests/*)
- **Functions/methods**: `camelCase` — e.g., `runCheck`, `parseFile`
- **Variables**: `camelCase` — e.g., `fileName`, `isValid`
- **Constants**: `SCREAMING_SNAKE` or `camelCase` — follow existing file patterns
- **Classes/Types**: `PascalCase` — e.g., `CheckResult`, `FileReader`

### File Names
- Bash scripts: `kebab-case.sh` or `snake_case.sh` (match existing pattern in directory)
- TypeScript: `kebab-case.ts` — e.g., `check-secrets.ts`
- Test files: `*.test.ts`

## Code Style

### Bash
- Always use `shellcheck` directive: `# shellcheck shell=bash`
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `local` for function variables
- Prefer `$(command)` over backticks
- Use constants from `utils.sh` instead of magic numbers

### Error Handling
- Bash: Check return values, use `|| return 1` pattern
- Always clean up temp files on error paths
- Log failures to progress file for debugging

## Architecture

### Ralph Module Structure
```
ralph/
  utils.sh      # Shared constants and utilities (source first)
  loop.sh       # Main autonomous loop
  prd-check.sh  # PRD validation before loop starts
  code-check.sh # Code verification after Claude writes
  verify/       # Verification submodules for code-check.sh
    lint.sh     # Linting/auto-fix
    tests.sh    # Unit tests
    api.sh      # API/frontend smoke tests
  backup.sh     # Database backup/restore
  init.sh       # Project initialization
  prd.sh        # PRD generation
  signs.sh      # Learned patterns
```

### Key Patterns
- Use `get_config` for reading config values with defaults
- Use `create_temp_file` for temp files (auto-cleanup)
- Use `safe_exec` for running external commands
- Use `log_progress` for audit trail
- Use centralized constants from `utils.sh` for timeouts, limits, etc.

## Security
- Never store credentials in plain text if avoidable — prefer env vars
- Use `validate_command()` for any user-provided commands
- Escape strings before embedding in AppleScript/SQL/etc.
