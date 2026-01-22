# Project Instructions for AI Coding Agents

## Tech Stack
- **Backend**: Django 5, Django REST Framework
- **Database**: PostgreSQL
- **Cache/Queue**: Redis, Celery
- **Testing**: pytest, pytest-django

## Code Quality Standards

### Python Style
- Follow PEP 8
- Use type hints for function signatures
- Maximum line length: 88 (Black default)
- Use f-strings for string formatting

```python
# Good
def get_user_by_email(email: str) -> User | None:
    """Fetch a user by their email address."""
    return User.objects.filter(email=email).first()
```

### Django Models
- Use explicit `related_name` on ForeignKey/M2M
- Add `__str__` method to all models
- Use model managers for complex queries
- Add indexes for frequently queried fields

```python
class Order(models.Model):
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='orders'
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"Order {self.id} by {self.user.email}"
```

### Django REST Framework
- Use serializers for all input/output
- Use ViewSets for CRUD operations
- Use proper permission classes
- Return appropriate HTTP status codes

```python
class OrderViewSet(viewsets.ModelViewSet):
    serializer_class = OrderSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # Only return user's own orders
        return Order.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)
```

### Error Handling
- Use DRF exceptions for API errors
- Log errors with context
- Never expose internal errors to users
- Handle specific exceptions, not bare except

```python
# Bad
try:
    process_order(order)
except Exception:
    pass

# Good
try:
    process_order(order)
except PaymentError as e:
    logger.error(f"Payment failed for order {order.id}: {e}")
    raise ValidationError({"payment": "Payment processing failed"})
except InventoryError as e:
    logger.warning(f"Inventory issue for order {order.id}: {e}")
    raise ValidationError({"inventory": str(e)})
```

### Database Queries
- Avoid N+1 queries (use select_related/prefetch_related)
- Use .only() or .defer() for large models
- Use database transactions for multi-step operations
- Add indexes for filter/order fields

```python
# Bad - N+1 query
orders = Order.objects.all()
for order in orders:
    print(order.user.email)  # Hits DB for each order

# Good
orders = Order.objects.select_related('user').all()
for order in orders:
    print(order.user.email)  # No additional queries
```

### Security
- Use Django's CSRF protection
- Validate all user input with serializers
- Use parameterized queries (Django ORM does this)
- Never trust user input for file paths or shell commands

### Testing
- Use pytest and pytest-django
- Use fixtures for test data
- Test API endpoints with APIClient
- Mock external services

```python
@pytest.mark.django_db
class TestOrderAPI:
    def test_create_order(self, authenticated_client, product):
        response = authenticated_client.post('/api/orders/', {
            'product_id': product.id,
            'quantity': 2,
        })
        assert response.status_code == 201
        assert Order.objects.count() == 1

    def test_cannot_create_order_unauthenticated(self, client):
        response = client.post('/api/orders/', {})
        assert response.status_code == 401
```

## File Structure
```
project/
├── config/           # Django settings, URLs, WSGI
├── apps/
│   ├── users/        # User-related models, views
│   ├── orders/       # Order-related models, views
│   └── common/       # Shared utilities
├── tests/            # Test files
└── manage.py
```

## Environment Variables
```python
# settings.py
DATABASE_URL = os.getenv('DATABASE_URL')
SECRET_KEY = os.getenv('SECRET_KEY')
DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'
```

## Pre-commit Hooks
This project uses vibe-and-thrive hooks. Run `/vibe-check` before committing.

## Common Commands
```bash
make up              # Start Docker services
make migrate         # Run migrations
make test            # Run tests
make shell           # Django shell
make logs            # View logs
```
