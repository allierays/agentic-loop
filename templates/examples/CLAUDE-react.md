# Project Instructions for AI Coding Agents

## Tech Stack
- **Frontend**: React 18, TypeScript, Vite
- **Styling**: TailwindCSS
- **State**: React Query for server state, Zustand for client state
- **Testing**: Vitest, React Testing Library, Playwright

## Code Quality Standards

### TypeScript
- **Never use `any`** - Create proper interfaces for all data
- Use strict mode (`"strict": true` in tsconfig)
- Prefer `interface` for object shapes, `type` for unions/intersections
- Use `unknown` instead of `any` when type is truly unknown

```typescript
// Bad
const data: any = await fetchUser();

// Good
interface User {
  id: string;
  email: string;
  name: string;
}
const data: User = await fetchUser();
```

### React Components
- Use functional components with hooks
- Keep components small and focused (< 100 lines)
- Extract logic into custom hooks
- Use proper TypeScript types for props

```typescript
// Good component structure
interface UserCardProps {
  user: User;
  onEdit: (user: User) => void;
}

export function UserCard({ user, onEdit }: UserCardProps) {
  return (/* ... */);
}
```

### State Management
- Use React Query for server state (caching, refetching)
- Use Zustand for UI state only
- Keep state as close to usage as possible
- Don't duplicate server state in client state

### Error Handling
- Always handle loading, error, and empty states
- Use Error Boundaries for unexpected errors
- Show user-friendly error messages
- Log errors with context for debugging

```typescript
// Always handle all states
const { data, isLoading, error } = useQuery(['user'], fetchUser);

if (isLoading) return <Skeleton />;
if (error) return <ErrorMessage error={error} />;
if (!data) return <EmptyState />;

return <UserProfile user={data} />;
```

### Styling with TailwindCSS
- Use Tailwind utility classes
- Extract repeated patterns to components, not @apply
- Use design system tokens (colors, spacing)
- Keep className strings readable

### Testing
- Write tests for business logic and user interactions
- Use React Testing Library (test behavior, not implementation)
- Mock external dependencies
- Use Playwright for critical user flows

```typescript
// Test user behavior, not implementation
test('user can submit form', async () => {
  render(<ContactForm />);

  await userEvent.type(screen.getByLabelText(/email/i), 'test@example.com');
  await userEvent.click(screen.getByRole('button', { name: /submit/i }));

  expect(screen.getByText(/thanks/i)).toBeInTheDocument();
});
```

## File Structure
```
src/
├── components/     # Reusable UI components
│   ├── ui/         # Design system primitives
│   └── features/   # Feature-specific components
├── hooks/          # Custom React hooks
├── pages/          # Page components (routes)
├── services/       # API calls and external services
├── stores/         # Zustand stores
├── types/          # TypeScript types/interfaces
└── utils/          # Helper functions
```

## Environment Variables
- Use `import.meta.env.VITE_*` for client-side env vars
- Never commit real secrets
- Provide defaults for local development

```typescript
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000/api';
```

## Pre-commit Hooks
This project uses vibe-and-thrive hooks. Run `/vibe-check` before committing.

## Common Commands
```bash
npm run dev          # Start dev server
npm run build        # Build for production
npm test             # Run unit tests
npm run test:e2e     # Run E2E tests
npm run lint         # Run linter
npm run typecheck    # Check types
```
