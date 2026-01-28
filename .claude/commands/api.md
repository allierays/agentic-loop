---
description: API design patterns for REST and GraphQL. Use when designing endpoints, handling errors, authentication, pagination, or versioning.
---

# API Patterns

Best practices for designing and implementing APIs. Use these patterns when building REST or GraphQL endpoints.

## REST Design

### Resource Naming

```
# ✅ Nouns, plural, hierarchical
GET    /users              # List users
POST   /users              # Create user
GET    /users/:id          # Get user
PATCH  /users/:id          # Update user
DELETE /users/:id          # Delete user
GET    /users/:id/orders   # User's orders

# ❌ Avoid verbs, actions in URL
GET    /getUsers
POST   /createUser
POST   /users/:id/activate  # Use PATCH with status field instead
```

### HTTP Methods

| Method | Purpose | Idempotent | Request Body |
|--------|---------|------------|--------------|
| GET | Read | Yes | No |
| POST | Create | No | Yes |
| PUT | Replace | Yes | Yes |
| PATCH | Partial update | Yes | Yes |
| DELETE | Remove | Yes | No |

### Status Codes

```typescript
// ✅ Use appropriate status codes
return res.status(200).json(data);        // OK - successful GET/PATCH
return res.status(201).json(created);     // Created - successful POST
return res.status(204).send();            // No Content - successful DELETE
return res.status(400).json({ error });   // Bad Request - validation failed
return res.status(401).json({ error });   // Unauthorized - not authenticated
return res.status(403).json({ error });   // Forbidden - not authorized
return res.status(404).json({ error });   // Not Found
return res.status(409).json({ error });   // Conflict - duplicate, race condition
return res.status(422).json({ error });   // Unprocessable - semantic error
return res.status(429).json({ error });   // Too Many Requests - rate limited
return res.status(500).json({ error });   // Internal Error - unexpected
```

## Error Responses

### Consistent Format

```typescript
// ✅ Standard error shape
interface ApiError {
  error: {
    code: string;           // Machine-readable: "VALIDATION_ERROR"
    message: string;        // Human-readable: "Invalid email format"
    details?: unknown;      // Optional field-level errors
    requestId?: string;     // For debugging
  };
}

// Example response
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "details": {
      "email": "Invalid email format",
      "age": "Must be a positive number"
    },
    "requestId": "req_abc123"
  }
}
```

### Error Handler

```typescript
// ✅ Centralized error handling
class AppError extends Error {
  constructor(
    public code: string,
    public message: string,
    public statusCode: number,
    public details?: unknown
  ) {
    super(message);
  }
}

// Common errors
const NotFoundError = (resource: string) =>
  new AppError('NOT_FOUND', `${resource} not found`, 404);

const ValidationError = (details: Record<string, string>) =>
  new AppError('VALIDATION_ERROR', 'Validation failed', 400, details);

const UnauthorizedError = () =>
  new AppError('UNAUTHORIZED', 'Authentication required', 401);

// Express error middleware
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  const requestId = req.headers['x-request-id'] || crypto.randomUUID();

  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: {
        code: err.code,
        message: err.message,
        details: err.details,
        requestId
      }
    });
  }

  // Unexpected error - log full details, return generic message
  console.error('Unhandled error:', { requestId, error: err });
  return res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
      requestId
    }
  });
});
```

## Pagination

### Cursor-Based (Recommended)

```typescript
// ✅ For large/real-time datasets
interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    hasMore: boolean;
    nextCursor?: string;  // Opaque token
  };
}

// Request
GET /users?limit=20&cursor=eyJpZCI6MTIzfQ

// Implementation
async function listUsers(limit: number, cursor?: string) {
  const decoded = cursor ? JSON.parse(atob(cursor)) : null;

  const users = await db.query({
    where: decoded ? { id: { gt: decoded.id } } : undefined,
    orderBy: { id: 'asc' },
    take: limit + 1  // Fetch one extra to check hasMore
  });

  const hasMore = users.length > limit;
  const data = hasMore ? users.slice(0, -1) : users;
  const nextCursor = hasMore
    ? btoa(JSON.stringify({ id: data[data.length - 1].id }))
    : undefined;

  return { data, pagination: { hasMore, nextCursor } };
}
```

### Offset-Based (Simple)

```typescript
// ✅ For small, static datasets
interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    total: number;
    page: number;
    pageSize: number;
    totalPages: number;
  };
}

// Request
GET /users?page=2&pageSize=20

// Implementation
async function listUsers(page: number, pageSize: number) {
  const [data, total] = await Promise.all([
    db.users.findMany({ skip: (page - 1) * pageSize, take: pageSize }),
    db.users.count()
  ]);

  return {
    data,
    pagination: {
      total,
      page,
      pageSize,
      totalPages: Math.ceil(total / pageSize)
    }
  };
}
```

## Filtering & Sorting

```typescript
// ✅ Consistent query parameters
GET /orders?status=pending&status=processing  // Multiple values
GET /orders?createdAt[gte]=2024-01-01        // Range filters
GET /orders?sort=-createdAt,+amount          // Sort: - desc, + asc
GET /orders?fields=id,status,total           // Sparse fieldsets

// Implementation
function parseFilters(query: Record<string, unknown>) {
  const where: Record<string, unknown> = {};

  if (query.status) {
    where.status = Array.isArray(query.status)
      ? { in: query.status }
      : query.status;
  }

  if (query['createdAt[gte]']) {
    where.createdAt = { gte: new Date(query['createdAt[gte]'] as string) };
  }

  return where;
}

function parseSort(sort?: string) {
  if (!sort) return { createdAt: 'desc' };

  return sort.split(',').reduce((acc, field) => {
    const order = field.startsWith('-') ? 'desc' : 'asc';
    const name = field.replace(/^[-+]/, '');
    return { ...acc, [name]: order };
  }, {});
}
```

## Authentication

### JWT Pattern

```typescript
// ✅ Middleware
async function authenticate(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    throw UnauthorizedError();
  }

  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET!) as JwtPayload;
    req.user = { id: payload.sub, roles: payload.roles };
    next();
  } catch {
    throw UnauthorizedError();
  }
}

// ✅ Apply to routes
app.use('/api', authenticate);  // All /api routes require auth

// Or per-route
app.get('/users/:id', authenticate, getUser);
```

### API Keys

```typescript
// ✅ For service-to-service or public APIs
async function authenticateApiKey(req: Request, res: Response, next: NextFunction) {
  const apiKey = req.headers['x-api-key'];
  if (!apiKey) {
    throw UnauthorizedError();
  }

  // Hash the key to compare (never store plain keys)
  const hashedKey = crypto.createHash('sha256').update(apiKey).digest('hex');
  const keyRecord = await db.apiKeys.findUnique({ where: { hash: hashedKey } });

  if (!keyRecord || keyRecord.revokedAt) {
    throw UnauthorizedError();
  }

  req.apiKey = keyRecord;
  next();
}
```

## Rate Limiting

```typescript
// ✅ Return rate limit headers
import rateLimit from 'express-rate-limit';

const limiter = rateLimit({
  windowMs: 60 * 1000,  // 1 minute
  max: 100,             // 100 requests per window
  standardHeaders: true, // Return RateLimit-* headers
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.id || req.ip,  // Per-user if authenticated
  handler: (req, res) => {
    res.status(429).json({
      error: {
        code: 'RATE_LIMITED',
        message: 'Too many requests',
        retryAfter: res.getHeader('Retry-After')
      }
    });
  }
});

// Different limits for different endpoints
app.use('/api/', limiter);
app.use('/api/auth/', rateLimit({ windowMs: 60000, max: 5 }));  // Stricter
```

## Versioning

```typescript
// ✅ URL versioning (most explicit)
app.use('/v1', v1Router);
app.use('/v2', v2Router);

// Or header versioning
app.use((req, res, next) => {
  req.apiVersion = req.headers['api-version'] || 'v1';
  next();
});

// ✅ Deprecation headers
app.use('/v1', (req, res, next) => {
  res.setHeader('Deprecation', 'true');
  res.setHeader('Sunset', 'Sat, 01 Jan 2025 00:00:00 GMT');
  res.setHeader('Link', '</v2>; rel="successor-version"');
  next();
});
```

## Request Validation

```typescript
// ✅ Use zod for runtime validation
import { z } from 'zod';

const CreateUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(100),
  role: z.enum(['user', 'admin']).default('user')
});

const QuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
  sort: z.string().optional()
});

// Middleware
function validate<T>(schema: z.Schema<T>, source: 'body' | 'query' | 'params') {
  return (req: Request, res: Response, next: NextFunction) => {
    const result = schema.safeParse(req[source]);
    if (!result.success) {
      throw ValidationError(
        result.error.errors.reduce((acc, err) => ({
          ...acc,
          [err.path.join('.')]: err.message
        }), {})
      );
    }
    req[source] = result.data;
    next();
  };
}

// Usage
app.post('/users', validate(CreateUserSchema, 'body'), createUser);
app.get('/users', validate(QuerySchema, 'query'), listUsers);
```

## Response Formatting

```typescript
// ✅ Consistent envelope (optional but helpful)
interface ApiResponse<T> {
  data: T;
  meta?: {
    requestId: string;
    timestamp: string;
  };
}

// Middleware to wrap responses
app.use((req, res, next) => {
  const originalJson = res.json.bind(res);
  res.json = (body) => {
    if (body?.error) return originalJson(body);  // Don't wrap errors
    return originalJson({
      data: body,
      meta: {
        requestId: req.headers['x-request-id'] || crypto.randomUUID(),
        timestamp: new Date().toISOString()
      }
    });
  };
  next();
});
```

## CORS

```typescript
// ✅ Configure explicitly
import cors from 'cors';

app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || false,
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-ID'],
  credentials: true,
  maxAge: 86400  // Cache preflight for 24h
}));
```

## Documentation

```typescript
// ✅ OpenAPI with zod-to-openapi
import { OpenAPIRegistry } from '@asteasolutions/zod-to-openapi';

const registry = new OpenAPIRegistry();

registry.registerPath({
  method: 'post',
  path: '/users',
  summary: 'Create a user',
  request: { body: { content: { 'application/json': { schema: CreateUserSchema } } } },
  responses: {
    201: { description: 'User created', content: { 'application/json': { schema: UserSchema } } },
    400: { description: 'Validation error' },
    409: { description: 'Email already exists' }
  }
});
```

## Idempotency

```typescript
// ✅ For POST/PATCH that shouldn't be retried blindly
app.post('/payments', async (req, res) => {
  const idempotencyKey = req.headers['idempotency-key'];
  if (!idempotencyKey) {
    throw ValidationError({ 'Idempotency-Key': 'Required header' });
  }

  // Check if we've seen this key
  const existing = await redis.get(`idempotency:${idempotencyKey}`);
  if (existing) {
    return res.status(200).json(JSON.parse(existing));
  }

  // Process payment
  const result = await processPayment(req.body);

  // Store result for 24h
  await redis.setex(`idempotency:${idempotencyKey}`, 86400, JSON.stringify(result));

  return res.status(201).json(result);
});
```

## Health Checks

```typescript
// ✅ Separate liveness and readiness
app.get('/health/live', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/health/ready', async (req, res) => {
  try {
    await db.$queryRaw`SELECT 1`;  // Check DB
    await redis.ping();             // Check Redis
    res.status(200).json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});
```
