# Project Instructions for AI Coding Agents

## Tech Stack
- **Runtime**: Node.js 20+
- **Framework**: Express.js / Fastify
- **Language**: TypeScript
- **Database**: PostgreSQL with Prisma
- **Testing**: Jest, Supertest

## Code Quality Standards

### TypeScript
- Enable strict mode in tsconfig
- Never use `any` - define proper types
- Use `unknown` for truly dynamic data
- Export types from dedicated files

```typescript
// types/user.ts
export interface User {
  id: string;
  email: string;
  name: string;
  createdAt: Date;
}

export interface CreateUserInput {
  email: string;
  name: string;
  password: string;
}
```

### API Endpoints
- Use consistent response format
- Return appropriate HTTP status codes
- Validate all input with Zod or Joi
- Handle errors with middleware

```typescript
// Consistent response format
interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
  };
}

// Controller
export async function createUser(req: Request, res: Response) {
  const input = createUserSchema.parse(req.body);

  const user = await userService.create(input);

  res.status(201).json({
    success: true,
    data: user,
  });
}
```

### Error Handling
- Use custom error classes
- Centralize error handling in middleware
- Log errors with context
- Never expose stack traces to clients

```typescript
// errors.ts
export class AppError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string
  ) {
    super(message);
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string) {
    super(404, 'NOT_FOUND', `${resource} not found`);
  }
}

// middleware/errorHandler.ts
export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction
) {
  logger.error('Request error', { error: err, path: req.path });

  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      success: false,
      error: { code: err.code, message: err.message },
    });
  }

  // Don't expose internal errors
  res.status(500).json({
    success: false,
    error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' },
  });
}
```

### Database (Prisma)
- Use transactions for multi-step operations
- Select only needed fields
- Use pagination for list endpoints
- Add indexes in schema

```typescript
// Good - select only needed fields
const users = await prisma.user.findMany({
  select: {
    id: true,
    email: true,
    name: true,
  },
  take: 20,
  skip: page * 20,
});

// Transaction
await prisma.$transaction(async (tx) => {
  const order = await tx.order.create({ data: orderData });
  await tx.inventory.decrement({ where: { productId }, data: { quantity } });
  return order;
});
```

### Async/Await
- Always use try/catch or error middleware
- Use Promise.all for parallel operations
- Handle promise rejections
- Avoid callback-style code

```typescript
// Parallel operations
const [user, orders, notifications] = await Promise.all([
  userService.getById(userId),
  orderService.getByUser(userId),
  notificationService.getUnread(userId),
]);
```

### Security
- Validate all input
- Use parameterized queries (Prisma does this)
- Set security headers (helmet)
- Rate limit sensitive endpoints
- Never log sensitive data

### Logging
- Use structured logging (pino, winston)
- Include request ID for tracing
- Log appropriate levels
- Never log passwords or tokens

```typescript
logger.info('User created', {
  userId: user.id,
  email: user.email,
  // Never log: password, token, etc.
});
```

### Testing
- Unit test business logic
- Integration test API endpoints
- Mock external services
- Use test database

```typescript
describe('POST /api/users', () => {
  it('creates a user with valid input', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ email: 'test@example.com', name: 'Test', password: 'secure123' });

    expect(response.status).toBe(201);
    expect(response.body.success).toBe(true);
    expect(response.body.data.email).toBe('test@example.com');
  });

  it('returns 400 for invalid email', async () => {
    const response = await request(app)
      .post('/api/users')
      .send({ email: 'invalid', name: 'Test', password: 'secure123' });

    expect(response.status).toBe(400);
    expect(response.body.error.code).toBe('VALIDATION_ERROR');
  });
});
```

## File Structure
```
src/
├── controllers/      # Route handlers
├── services/         # Business logic
├── repositories/     # Database access
├── middleware/       # Express middleware
├── types/            # TypeScript types
├── utils/            # Helper functions
├── routes/           # Route definitions
└── index.ts          # App entry point
```

## Environment Variables
```typescript
// config.ts
export const config = {
  port: process.env.PORT || 3000,
  databaseUrl: process.env.DATABASE_URL!,
  jwtSecret: process.env.JWT_SECRET!,
  nodeEnv: process.env.NODE_ENV || 'development',
};
```

## Pre-commit Hooks
This project uses vibe-and-thrive hooks. Run `/vibe-check` before committing.

## Common Commands
```bash
npm run dev          # Start dev server with hot reload
npm run build        # Build TypeScript
npm start            # Start production server
npm test             # Run tests
npm run lint         # Run linter
npm run db:migrate   # Run Prisma migrations
```
