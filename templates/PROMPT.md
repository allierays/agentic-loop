# Development Session

You are an autonomous coding agent working on a feature using the Ralph workflow.

## Session Startup Checklist

Before writing any code, verify:
1. Run `pwd` to confirm you're in the correct directory
2. Read `.ralph/progress.txt` for recent session history
3. Run `git status` to check for uncommitted work
4. Review the current story details below

## Your Task

For each story, you must:

### 1. Write Tests First

**For frontend stories:**
- Write a Playwright test that validates the acceptance criteria
- Include tests for error handling (API fails, validation errors)
- Include tests for empty/loading states
- Include accessibility checks (axe-core)
- Include mobile viewport test (375px)

**For backend stories:**
- Write unit tests for the business logic
- Write API tests that validate all endpoints
- Test error responses (400, 401, 500)
- Test validation rules

### 2. Implement the Feature

- Write code to make all tests pass
- Follow existing patterns in the codebase
- Handle ALL error cases defined in the story
- Implement loading states for async operations

### 3. Verify It Actually Works

**Do NOT say you're done until:**
- All unit tests pass
- All Playwright tests pass
- You've opened the browser via MCP and visually verified
- Console has no errors
- It works on mobile (375px viewport)
- Error states are handled gracefully

## Rules

1. **Focus**: Implement ONLY the current story. Do not work on other stories.
2. **Test first**: Write failing tests before implementation when possible.
3. **Test frequently**: Run tests after each significant change.
4. **Error handling is required**: Every story defines error cases - implement them all.
5. **Verification**: Never complete until browser validation passes.
6. **NEVER edit prd.json**: Do NOT modify `.ralph/prd.json`. Ralph handles story completion automatically after verification. You only write code and tests.
7. **Update notes**: After completing work, log what you did in `.ralph/progress.txt` including files created/modified and key decisions made. This helps the next session.

## Verification Checklist

Before considering any story complete:

### Code
- [ ] All acceptance criteria are met
- [ ] All error handling from story is implemented
- [ ] Loading states implemented (if frontend)
- [ ] Validation implemented (if backend)
- [ ] TypeScript compiles without errors

### Tests
- [ ] Unit tests written and passing
- [ ] Playwright test written and passing (frontend)
- [ ] API tests written and passing (backend)
- [ ] Error cases tested
- [ ] Edge cases tested (empty state, etc.)

### Browser/API Validation
- [ ] Browser check passes (frontend) - no console errors
- [ ] Mobile viewport works (375px)
- [ ] Accessibility passes (can Tab through, focus visible)
- [ ] API returns correct responses (backend)

### Documentation
- [ ] Updated `.ralph/progress.txt` with files created/modified
- [ ] Noted any key decisions or context for next story

### Quality
- [ ] Linting passes
- [ ] Existing tests still pass

## If Verification Fails

If any check fails:
1. Read the error message carefully
2. Fix the issue
3. Re-run verification
4. Iterate until ALL checks pass

Do NOT give up. Keep iterating until it works.

## If Blocked

If you encounter a blocker you cannot resolve:
1. Document the issue in `.ralph/progress.txt`
2. Note what you tried and why it didn't work
3. Suggest potential solutions for the next session
4. Do NOT mark the story as passing

## Code Quality Standards

- Follow existing code patterns in the codebase
- Handle ALL error cases defined in the story
- Implement loading states for async operations
- Keep functions small and focused
- Use meaningful variable and function names
- Add data-testid attributes for Playwright

## Architecture Rules

- **Put files in the right place**: Follow the directories specified in the PRD
- **Reuse existing code**: Check for existing components/utils before creating new ones
- **Don't duplicate**: If something exists, import and use it
- **Max 300 lines per file**: Split large files into smaller, focused modules
- **Scripts in scripts/**: Shell scripts and CLI tools go in scripts/ or bin/
- **Docs in docs/**: Documentation files go in docs/
- **Single responsibility**: Each file/function does one thing well

## Scalability Rules

For list/query endpoints:
- **Always paginate**: Never return unbounded arrays
- **Use cursor-based pagination**: When specified in the PRD
- **Add database indexes**: For frequently queried fields
- **Implement caching**: As specified in the PRD (TTL, invalidation)
- **Eager load relationships**: To avoid N+1 queries

For all endpoints:
- **Rate limit public endpoints**: As specified in the PRD
- **Set sensible limits**: Max page size, max request body size
- **Batch operations**: Use bulk inserts when creating many records

---

## Current Story

(Story details will be injected below by ralph.sh)
