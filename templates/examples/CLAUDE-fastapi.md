# CLAUDE.md - FastAPI Project

## Project Overview

This is a FastAPI backend application with async SQLAlchemy and Pydantic.

## Tech Stack

- **Framework**: FastAPI
- **ORM**: SQLAlchemy 2.0 (async)
- **Validation**: Pydantic v2
- **Database**: PostgreSQL
- **Migrations**: Alembic
- **Testing**: pytest + httpx
- **Task Queue**: Celery + Redis (if applicable)

## Project Structure

```
app/
├── main.py              # FastAPI app entry point
├── config.py            # Settings via pydantic-settings
├── database.py          # Async SQLAlchemy setup
├── models/              # SQLAlchemy models
├── schemas/             # Pydantic schemas
├── routers/             # API route handlers
├── services/            # Business logic
├── dependencies.py      # FastAPI dependencies
└── exceptions.py        # Custom exceptions
tests/
├── conftest.py          # Fixtures
├── test_api/            # API tests
└── test_services/       # Unit tests
```

## Commands

```bash
# Development
uvicorn app.main:app --reload --port 8000

# Database
alembic upgrade head                    # Run migrations
alembic revision --autogenerate -m ""   # Create migration

# Testing
pytest                                  # Run all tests
pytest -x                               # Stop on first failure
pytest --cov=app                        # With coverage

# Linting
ruff check app/
ruff format app/
```

## Code Standards

### API Endpoints

```python
# Good - explicit status codes, response model, dependencies
@router.post("/users", status_code=status.HTTP_201_CREATED, response_model=UserResponse)
async def create_user(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserResponse:
    """Create a new user."""
    return await user_service.create(db, user_in)

# Bad - implicit everything
@router.post("/users")
async def create_user(user_in: UserCreate, db = Depends(get_db)):
    return await create(db, user_in)
```

### Pydantic Schemas

```python
# Good - explicit validation, examples, field descriptions
class UserCreate(BaseModel):
    email: EmailStr = Field(..., description="User's email address")
    password: str = Field(..., min_length=8, description="Password (min 8 chars)")
    name: str = Field(..., min_length=1, max_length=100)

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "email": "user@example.com",
                "password": "securepass123",
                "name": "John Doe"
            }
        }
    )

# Bad - no validation
class UserCreate(BaseModel):
    email: str
    password: str
    name: str
```

### SQLAlchemy Models

```python
# Good - explicit types, relationships, indexes
class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(default=func.now())

    # Relationships
    posts: Mapped[list["Post"]] = relationship(back_populates="author")

# Bad - old style, no types
class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    email = Column(String)
    password = Column(String)
```

### Async Database Sessions

```python
# Good - async context manager
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

# Bad - no cleanup
async def get_db():
    return async_session()
```

### Error Handling

```python
# Good - custom exceptions with proper HTTP codes
class NotFoundError(Exception):
    def __init__(self, resource: str, id: int):
        self.resource = resource
        self.id = id

@app.exception_handler(NotFoundError)
async def not_found_handler(request: Request, exc: NotFoundError):
    return JSONResponse(
        status_code=404,
        content={"detail": f"{exc.resource} with id {exc.id} not found"}
    )

# Bad - generic exceptions
raise Exception("User not found")
```

### Service Layer

```python
# Good - service handles business logic
class UserService:
    async def create(self, db: AsyncSession, user_in: UserCreate) -> User:
        # Check if exists
        existing = await self.get_by_email(db, user_in.email)
        if existing:
            raise ConflictError("User", "email", user_in.email)

        # Hash password
        hashed = hash_password(user_in.password)

        # Create user
        user = User(email=user_in.email, hashed_password=hashed, name=user_in.name)
        db.add(user)
        await db.flush()
        return user

# Bad - logic in router
@router.post("/users")
async def create_user(user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    existing = await db.execute(select(User).where(User.email == user_in.email))
    if existing.scalar():
        raise HTTPException(409, "Email exists")
    hashed = bcrypt.hash(user_in.password)
    user = User(email=user_in.email, hashed_password=hashed)
    db.add(user)
    # ... more logic
```

## Do NOT

- Use `Any` type - create proper Pydantic models
- Put business logic in routers - use service layer
- Use synchronous database calls in async endpoints
- Hardcode secrets - use `pydantic-settings` with env vars
- Skip input validation - use Pydantic Field validators
- Return SQLAlchemy models directly - use response schemas
- Use `*` imports - explicit imports only
- Catch generic `Exception` - catch specific exceptions

## Do

- Use async/await consistently
- Add OpenAPI descriptions to all endpoints
- Use dependency injection for services
- Write tests for all endpoints
- Use Alembic for all schema changes
- Add proper logging with structlog
- Use HTTPException for API errors
- Validate all inputs with Pydantic

## Environment Variables

```bash
DATABASE_URL=postgresql+asyncpg://user:pass@localhost:5432/dbname
SECRET_KEY=your-secret-key
REDIS_URL=redis://localhost:6379/0
DEBUG=false
```

Always use `pydantic-settings`:

```python
class Settings(BaseSettings):
    database_url: PostgresDsn
    secret_key: str
    debug: bool = False

    model_config = SettingsConfigDict(env_file=".env")

settings = Settings()
```

## Testing

```python
# Good - async test with fixtures
@pytest.mark.asyncio
async def test_create_user(client: AsyncClient, db: AsyncSession):
    response = await client.post(
        "/api/users",
        json={"email": "test@example.com", "password": "testpass123", "name": "Test"}
    )
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "test@example.com"
    assert "password" not in data  # Never return password

# conftest.py
@pytest.fixture
async def client(app: FastAPI) -> AsyncGenerator[AsyncClient, None]:
    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client
```
