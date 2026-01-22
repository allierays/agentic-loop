# CLAUDE.md - FastMCP Server

## Project Overview

This is an MCP (Model Context Protocol) server built with FastMCP. It exposes tools, resources, and prompts to LLM clients.

## Tech Stack

- **Framework**: FastMCP 2.0
- **Protocol**: Model Context Protocol (MCP)
- **Validation**: Pydantic v2
- **Async**: anyio

## Project Structure

```
server/
├── main.py              # FastMCP app entry point
├── tools/               # Tool implementations
│   ├── __init__.py
│   └── search.py
├── resources/           # Resource handlers
│   ├── __init__.py
│   └── data.py
├── prompts/             # Prompt templates
│   ├── __init__.py
│   └── analysis.py
├── dependencies.py      # Dependency injection
└── config.py            # Settings
tests/
├── conftest.py
└── test_tools.py
```

## Commands

```bash
# Development
fastmcp dev server/main.py

# Run server
python server/main.py

# Testing
pytest

# Install to Claude Desktop
fastmcp install server/main.py --name "My Server"
```

## Code Standards

### Basic Server Setup

```python
# Good - clear name, proper structure
from fastmcp import FastMCP

mcp = FastMCP("My Server")

@mcp.tool
def search(query: str) -> list[dict]:
    """Search for items matching the query."""
    return [{"id": 1, "name": "Result"}]

if __name__ == "__main__":
    mcp.run()

# Bad - no name, no types
from fastmcp import FastMCP
mcp = FastMCP()

@mcp.tool
def search(query):
    return [{"id": 1}]
```

### Tools

```python
from typing import Annotated
from pydantic import Field
from fastmcp import FastMCP
from fastmcp.exceptions import ToolError

mcp = FastMCP("My Server")

# Good - typed parameters, validation, docstring, error handling
@mcp.tool
async def search_products(
    query: Annotated[str, Field(min_length=1, description="Search query")],
    max_results: Annotated[int, Field(ge=1, le=100, description="Max results")] = 10,
    category: str | None = None,
) -> list[dict]:
    """Search the product catalog.

    Returns matching products with id, name, and price.
    """
    if not query.strip():
        raise ToolError("Query cannot be empty")

    results = await fetch_products(query, max_results, category)
    return results

# Bad - no types, no validation, no docstring
@mcp.tool
def search_products(query, max_results=10, **kwargs):
    return fetch_products(query, max_results)
```

### Resources

```python
from fastmcp import FastMCP
from fastmcp.resources import TextResource, FileResource
from fastmcp.exceptions import ResourceError
from pathlib import Path

mcp = FastMCP("My Server")

# Good - static resource with proper URI and MIME type
config_resource = TextResource(
    uri="config://app/settings",
    name="App Settings",
    text='{"theme": "dark", "version": "1.0"}',
    mime_type="application/json"
)
mcp.add_resource(config_resource)

# Good - dynamic resource with template
@mcp.resource("users://{user_id}/profile")
async def get_user_profile(user_id: str) -> dict:
    """Get user profile by ID."""
    user = await fetch_user(user_id)
    if not user:
        raise ResourceError(f"User {user_id} not found")
    return user

# Bad - no URI scheme, no error handling
@mcp.resource("user")
def get_user(id):
    return fetch_user(id)
```

### Prompts

```python
from fastmcp import FastMCP
from fastmcp.prompts import PromptMessage

mcp = FastMCP("My Server")

# Good - typed parameters, clear docstring, structured return
@mcp.prompt
def analyze_code(
    code: str,
    language: str = "python",
    focus: str = "security"
) -> list[PromptMessage]:
    """Analyze code for issues.

    Args:
        code: The code to analyze
        language: Programming language
        focus: Analysis focus (security, performance, style)
    """
    return [
        PromptMessage(
            role="user",
            content=f"Analyze this {language} code for {focus} issues:\n\n```{language}\n{code}\n```"
        )
    ]

# Bad - no types, returns plain string
@mcp.prompt
def analyze(code):
    return f"Analyze: {code}"
```

### Dependency Injection

```python
from fastmcp import FastMCP
from fastmcp.server.dependencies import get_context

mcp = FastMCP("My Server")

# Good - hide runtime values from LLM
def get_api_key() -> str:
    return os.environ["API_KEY"]

def get_db() -> Database:
    return Database(os.environ["DATABASE_URL"])

@mcp.tool
async def fetch_data(
    query: str,
    api_key: str = Depends(get_api_key),  # Hidden from schema
    db: Database = Depends(get_db),        # Hidden from schema
) -> dict:
    """Fetch data from external API."""
    return await db.query(query)

# Bad - exposing secrets in schema
@mcp.tool
def fetch_data(query: str, api_key: str) -> dict:
    return call_api(query, api_key)
```

### Error Handling

```python
from fastmcp.exceptions import ToolError, ResourceError

# Good - specific errors with helpful messages
@mcp.tool
def divide(a: float, b: float) -> float:
    """Divide two numbers."""
    if b == 0:
        raise ToolError("Cannot divide by zero")
    return a / b

@mcp.resource("data://{id}")
def get_data(id: str) -> dict:
    """Get data by ID."""
    data = fetch_data(id)
    if not data:
        raise ResourceError(f"Data with ID '{id}' not found")
    return data

# Bad - generic exceptions
@mcp.tool
def divide(a, b):
    return a / b  # ZeroDivisionError not handled
```

### Async Best Practices

```python
import anyio

# Good - async for I/O operations
@mcp.tool
async def fetch_url(url: str) -> str:
    """Fetch content from URL."""
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        return response.text

# Good - wrap CPU-bound sync code
@mcp.tool
async def process_image(image_data: bytes) -> bytes:
    """Process image (CPU-intensive)."""
    return await anyio.to_thread.run_sync(
        lambda: heavy_image_processing(image_data)
    )

# Bad - blocking call in async context
@mcp.tool
async def fetch_url(url: str) -> str:
    return requests.get(url).text  # Blocks event loop!
```

## Do NOT

- Use `*args` or `**kwargs` in tools - FastMCP needs complete parameter schemas
- Expose secrets as tool parameters - use `Depends()` for injection
- Use blocking I/O in async functions - wrap with `anyio.to_thread.run_sync()`
- Skip type hints - they generate the JSON schema for clients
- Catch and silence exceptions - use `ToolError`/`ResourceError` with helpful messages
- Use generic names like `data` or `process` - be specific

## Do

- Add docstrings to all tools, resources, and prompts
- Use `Annotated` with `Field` for parameter validation and descriptions
- Use async for all I/O operations
- Use `Depends()` to inject runtime values (API keys, DB connections)
- Use specific error types (`ToolError`, `ResourceError`)
- Add proper MIME types to resources
- Use URI schemes (`data://`, `config://`, `file://`)
- Test tools with `mcp.call_tool()` in pytest

## Testing

```python
import pytest
from server.main import mcp

@pytest.mark.asyncio
async def test_search_tool():
    result = await mcp.call_tool("search_products", {"query": "test"})
    assert isinstance(result, list)

@pytest.mark.asyncio
async def test_search_empty_query():
    with pytest.raises(ToolError, match="cannot be empty"):
        await mcp.call_tool("search_products", {"query": ""})

@pytest.mark.asyncio
async def test_user_resource():
    result = await mcp.read_resource("users://123/profile")
    assert "name" in result
```

## Configuration

```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    api_key: str
    database_url: str
    debug: bool = False

    model_config = {"env_file": ".env"}

settings = Settings()

# Use in server
mcp = FastMCP(
    "My Server",
    debug=settings.debug,
    mask_error_details=not settings.debug,  # Hide errors in production
)
```

## Deployment

```bash
# FastMCP Cloud (free for personal)
fastmcp deploy server/main.py

# Install to Claude Desktop
fastmcp install server/main.py --name "My Server"

# HTTP server
uvicorn server.main:mcp.http_app --host 0.0.0.0 --port 8000
```

## Resources

- [FastMCP Docs](https://gofastmcp.com)
- [MCP Specification](https://modelcontextprotocol.io)
