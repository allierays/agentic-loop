# Project Instructions for AI Coding Agents

## Naming Conventions

### Frontend (React/TypeScript)
- **Files**: `PascalCase.tsx` for components, `camelCase.ts` for utilities
- **Components**: `PascalCase` — e.g., `UserProfile`, `AuthProvider`
- **Hooks**: `useCamelCase` — e.g., `useAuth`, `useUserData`
- **Functions/Variables**: `camelCase` — e.g., `handleSubmit`, `isLoading`

### Backend (Django/Python)
- **Files**: `snake_case.py` — e.g., `user_views.py`
- **Functions/Variables**: `snake_case` — e.g., `get_user_by_id`
- **Classes**: `PascalCase` — e.g., `UserViewSet`, `UserSerializer`

### Shared
- **API endpoints**: `kebab-case` — e.g., `/api/user-profile/`
- **Database tables**: `snake_case` — e.g., `user_sessions`
- **Constants**: `SCREAMING_SNAKE` — e.g., `MAX_RETRIES`

## Tech Stack
- **Frontend**: React 18, TypeScript, Vite, TailwindCSS
- **Backend**: Django 5, Django REST Framework
- **Database**: PostgreSQL
- **Cache/Queue**: Redis, Celery
- **Testing**: pytest (backend), Vitest (frontend), Playwright (E2E)

## Architecture Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   React     │────▶│   Django    │────▶│  PostgreSQL │
│   Frontend  │     │   REST API  │     │   Database  │
└─────────────┘     └─────────────┘     └─────────────┘
                          │
                          ▼
                    ┌─────────────┐
                    │   Redis     │
                    │   + Celery  │
                    └─────────────┘
```

## Code Quality Standards

### API Contract
- Frontend and backend share type definitions
- Use consistent naming (camelCase in TS, snake_case in Python)
- API transforms snake_case responses to camelCase
- Document API changes before implementing

```typescript
// Frontend: types/api.ts
interface User {
  id: number;
  email: string;
  firstName: string;  // Transformed from first_name
  lastName: string;
  createdAt: string;
}
```

```python
# Backend: serializers.py
class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'email', 'first_name', 'last_name', 'created_at']
```

### Frontend Standards

**Components**
- Use functional components with TypeScript
- Keep components under 100 lines
- Extract logic to custom hooks
- Handle loading/error/empty states

**State Management**
- React Query for server state
- Zustand for UI state only
- Don't duplicate server state

**API Calls**
```typescript
// services/api.ts
const api = {
  users: {
    getAll: () => fetch<User[]>('/api/users/'),
    getById: (id: number) => fetch<User>(`/api/users/${id}/`),
    create: (data: CreateUserInput) => post<User>('/api/users/', data),
  },
};
```

### Backend Standards

**Views**
- Use DRF ViewSets for CRUD
- Apply proper permissions
- Return appropriate status codes
- Filter querysets by user ownership

**Models**
- Add explicit `related_name`
- Include `__str__` method
- Index frequently queried fields
- Use model managers for complex queries

**Queries**
- Avoid N+1 with select_related/prefetch_related
- Use pagination for list endpoints
- Add database indexes

### Shared Patterns

**Authentication**
- JWT tokens in httpOnly cookies
- CSRF protection for state-changing requests
- Refresh tokens for long sessions

**Error Handling**
```typescript
// Frontend
try {
  await api.users.create(data);
} catch (error) {
  if (error instanceof ApiError) {
    showToast(error.message);
  } else {
    showToast('Something went wrong');
    logger.error(error);
  }
}
```

```python
# Backend
try:
    user = create_user(data)
except ValidationError as e:
    raise DRFValidationError(e.messages)
except IntegrityError:
    raise DRFValidationError({'email': 'Email already exists'})
```

### Testing Strategy

**Unit Tests**
- Frontend: Test hooks, utilities, complex components
- Backend: Test services, serializers, model methods

**Integration Tests**
- Backend: Test API endpoints with pytest
- Frontend: Test API integration with MSW

**E2E Tests (Playwright)**
- Test critical user flows
- Use TDD workflow (test first, then implement)
- Include SCENARIO/EXPECTED/FAILURE documentation

```typescript
test('user can complete checkout', async ({ page }) => {
  /**
   * SCENARIO: Logged-in user adds item and completes checkout
   * EXPECTED: Order confirmation shown, order in database
   * FAILURE: Stuck at any step, error shown
   */
  await loginAsTestUser(page);
  await page.goto('/products/1');
  await page.click('[data-testid="add-to-cart"]');
  await page.click('[data-testid="checkout"]');
  await page.fill('[name="address"]', '123 Main St');
  await page.click('[data-testid="place-order"]');

  await expect(page.getByText('Order Confirmed')).toBeVisible();
});
```

## File Structure

```
project/
├── frontend/
│   ├── src/
│   │   ├── components/
│   │   ├── hooks/
│   │   ├── pages/
│   │   ├── services/
│   │   ├── stores/
│   │   └── types/
│   └── e2e/              # Playwright tests
├── backend/
│   ├── config/           # Django settings
│   ├── apps/
│   │   ├── users/
│   │   └── orders/
│   └── tests/
├── docker-compose.yml
└── Makefile
```

## Environment Variables

```bash
# .env.example

# Database
DATABASE_URL=postgresql://user:pass@localhost:5432/dbname

# Django
SECRET_KEY=your-secret-key
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1

# Frontend
VITE_API_URL=http://localhost:8000/api

# Redis
REDIS_URL=redis://localhost:6379
```

## Pre-commit Hooks
This project uses vibe-and-thrive hooks. Run `/vibe-check` before committing.

## Common Commands

```bash
# Development
make up              # Start all services (Docker)
make frontend        # Run frontend dev server
make logs            # View backend logs

# Database
make migrate         # Run migrations
make makemigrations  # Create migrations

# Testing
make test            # Run all tests
make test-backend    # Run backend tests
make test-frontend   # Run frontend tests
make test-e2e        # Run Playwright E2E tests

# Code Quality
make lint            # Run all linters
make format          # Format all code
make typecheck       # Check TypeScript types
```

## Workflow

1. **Idea** - Run `/idea "feature description"` to brainstorm
2. **Approve** - Review the idea file, then approve
3. **PRD** - Review generated stories in `.ralph/prd.json`
4. **Run** - Execute `ralph run` for autonomous coding
5. **Audit** - Run `/vibe-check` before shipping
6. **Commit** - Pre-commit hooks catch remaining issues
