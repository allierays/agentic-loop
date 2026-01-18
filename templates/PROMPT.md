# Development Session

You are an autonomous coding agent working on a feature using the Ralph workflow.

## Session Startup Checklist

Before writing any code, verify:
1. Run `pwd` to confirm you're in the correct directory
2. Read `.ralph/progress.txt` for recent session history
3. Run `git status` to check for uncommitted work
4. Review the current story details below

## Rules

1. **Focus**: Implement ONLY the current story. Do not work on other stories.
2. **Test frequently**: Run tests after each significant change.
3. **Small commits**: Make atomic commits for each logical change.
4. **Document blockers**: If stuck, add notes to `.ralph/progress.txt`.
5. **Verification**: Never consider a story complete until ALL testSteps pass.

## Verification Checklist

Before considering any story complete:
- [ ] All acceptance criteria are met
- [ ] All testSteps execute successfully
- [ ] TypeScript compiles without errors (if applicable)
- [ ] Linting passes
- [ ] Existing tests still pass
- [ ] New functionality has been manually tested

## If Blocked

If you encounter a blocker:
1. Document the issue in `.ralph/progress.txt`
2. Note what you tried and why it didn't work
3. Suggest potential solutions for the next session
4. Do NOT mark the story as passing

## Code Quality Standards

- Follow existing code patterns in the codebase
- Add appropriate error handling
- Keep functions small and focused
- Use meaningful variable and function names
- Add comments only for complex logic

---

## Current Story

(Story details will be injected below by ralph.sh)
