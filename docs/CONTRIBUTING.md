# Contributing to Vibe and Thrive

Found a pattern that AI agents commonly introduce? We'd love to add it!

## Adding a New Hook

### 1. Fork the repo

```bash
git clone https://github.com/allierays/agentic-loop.git
cd agentic-loop
npm install
```

### 2. Create your hook

Create a new file in `src/checks/`:

```typescript
// src/checks/check-your-pattern.ts
import type { CheckResult, Finding } from '../utils/types';

const PATTERNS = [
  // Your regex patterns here
  { regex: /problematic_pattern/, message: 'Description of issue' },
];

export function checkYourPattern(
  filePath: string,
  content: string
): CheckResult {
  const findings: Finding[] = [];
  const lines = content.split('\n');

  lines.forEach((line, index) => {
    for (const { regex, message } of PATTERNS) {
      if (regex.test(line)) {
        findings.push({
          line: index + 1,
          column: 0,
          message,
          severity: 'warning', // or 'error' for blocking issues
        });
      }
    }
  });

  return {
    filePath,
    findings,
    hookId: 'your-pattern',
  };
}
```

### 3. Register it in `src/checks/index.ts`

```typescript
import { checkYourPattern } from './check-your-pattern';

export const hooks = {
  // ... existing hooks
  'your-pattern': checkYourPattern,
};
```

### 4. Add to `.pre-commit-hooks.yaml`

```yaml
- id: check-your-pattern
  name: Check Your Pattern
  entry: npx vibe-check --only your-pattern --fail-on warning
  language: node
  types_or: [python, javascript, ts]
  pass_filenames: true
```

### 5. Add tests

Create `src/checks/__tests__/check-your-pattern.test.ts`:

```typescript
import { describe, it, expect } from 'vitest';
import { checkYourPattern } from '../check-your-pattern';

describe('checkYourPattern', () => {
  it('detects problematic code', () => {
    const result = checkYourPattern('test.ts', 'problematic_pattern here');
    expect(result.findings).toHaveLength(1);
  });

  it('ignores valid code', () => {
    const result = checkYourPattern('test.ts', 'valid code here');
    expect(result.findings).toHaveLength(0);
  });
});
```

### 6. Update documentation

- Add to `docs/HOOKS.md`
- Update the hook count in `README.md`

### 7. Submit a PR

```bash
git checkout -b add-check-your-pattern
npm run build
npm test
git add .
git commit -m "Add check-your-pattern hook"
git push origin add-check-your-pattern
```

## Hook Guidelines

- **Warn by default** - Use `severity: 'warning'` unless it's a security issue
- **Be specific** - Catch real problems, not style preferences
- **Allow suppression** - Check for `// noqa:` comments
- **Skip tests** - Don't flag test files unless relevant
- **Clear messages** - Tell users what's wrong and how to fix it

## Ideas for New Hooks

Have an idea? We'd love contributions:

- `check-unused-imports` - Imports that aren't used
- `check-async-await` - Missing `await` on async calls
- `check-react-keys` - Missing keys in React lists
- `check-sql-injection` - SQL string concatenation
- `check-circular-imports` - Circular import detection
- `check-type-ignore` - Excessive `// type: ignore` comments

## Running Tests

```bash
npm install
npm test           # Run all tests
npm run test:run   # Run tests once (no watch)
npm run build      # Build TypeScript
npm run typecheck  # Type check only
```

## Code Style

We use:
- **TypeScript** for all hooks
- **ESLint** for linting
- **Vitest** for testing

Run before committing:

```bash
npm run lint
npm run typecheck
npm run build
```
