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

### 1. Implement the Feature

- Follow existing patterns in the codebase
- Handle ALL error cases defined in the story
- Implement loading states for async operations

### 2. Write Tests

- Write unit tests for the business logic
- Write tests that validate acceptance criteria
- Test error cases and edge cases

### 3. Verify It Actually Works

**You have browser tools - USE THEM to verify your work:**

**Playwright MCP** (testing & automation):
- `browser_navigate` - Go to a URL and get page content
- `browser_screenshot` - Take a screenshot to verify UI
- `browser_click` - Click elements to test interactions
- `browser_type` - Fill in forms to test inputs
- `browser_snapshot` - Get accessibility tree for a11y testing

**Chrome DevTools MCP** (debugging & inspection):
- Inspect DOM, check console for errors
- Debug network requests
- Check element styles and computed properties

**Do NOT say you're done until:**
- All unit tests pass
- You've opened the browser and visually verified the feature works
- Console has no errors
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

- [ ] All acceptance criteria are met
- [ ] All error handling from story is implemented
- [ ] TypeScript/code compiles without errors
- [ ] Unit tests written and passing
- [ ] **Browser verified** - used Playwright MCP to visually confirm it works
- [ ] No console errors
- [ ] Linting passes
- [ ] Updated `.ralph/progress.txt` with files created/modified

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

### Core Principles
- **Readability First**: Code is read more than written. Prioritize clarity.
- **KISS**: Keep it simple. Avoid over-engineering.
- **DRY**: Don't repeat yourself. Extract reusable logic.
- **YAGNI**: Don't build features you don't need yet.

### Naming Conventions
- Variables: descriptive camelCase (`userProfile`, `isLoading`, `marketSearchQuery`)
- Functions: verb-noun pattern (`fetchUserData`, `validateInput`, `handleSubmit`)
- Components: PascalCase (`UserProfile`, `MarketCard`)
- Constants: SCREAMING_SNAKE_CASE (`MAX_RETRIES`, `API_BASE_URL`)

### Immutability (CRITICAL)
Always use spread operators. Never mutate directly:
```typescript
// ❌ Bad - mutation
user.name = 'new name';
items.push(newItem);

// ✅ Good - immutable
const updatedUser = { ...user, name: 'new name' };
const updatedItems = [...items, newItem];
```

### Error Handling
Every async operation needs proper error handling:
```typescript
// ✅ Good
try {
  const data = await fetchData();
  return { success: true, data };
} catch (error) {
  console.error('Failed to fetch data:', error);
  return { success: false, error: error.message };
}
```

### Type Safety
- Use TypeScript interfaces for all data shapes
- Never use `any` - use `unknown` if type is truly unknown
- Define return types for functions

### Functions
- Max 50 lines per function (split if longer)
- Single responsibility - one function does one thing
- Early returns for guard clauses

### React Specific
- Functional components with typed props
- Custom hooks for reusable stateful logic
- Use `prev =>` for state updates that depend on previous state
- Avoid excessive ternaries - extract to variables or early returns

### General
- Follow existing code patterns in the codebase
- Handle ALL error cases defined in the story
- Implement loading states for async operations
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

## AI/LLM Configuration

**NEVER hardcode AI model names, API keys, or endpoints.** Always use environment variables or settings.

```python
# ❌ Bad - hardcoded model
model = "gpt-4"
client = OpenAI(api_key="sk-...")

# ✅ Good - from environment/settings
model = os.environ.get("OPENAI_MODEL", "gpt-4")
client = OpenAI()  # Uses OPENAI_API_KEY env var
```

```python
# ❌ Bad - hardcoded in code
response = openai.chat.completions.create(
    model="gpt-4-turbo",
    max_tokens=4096,
)

# ✅ Good - from settings/config
from django.conf import settings
response = openai.chat.completions.create(
    model=settings.AI_MODEL,
    max_tokens=settings.AI_MAX_TOKENS,
)
```

If the project has an AI gateway or wrapper, use it:
```python
# ✅ Best - use project's AI abstraction
from myapp.ai import get_completion
response = get_completion(prompt)
```

---

## Current Story

(Story details will be injected below by ralph.sh)
