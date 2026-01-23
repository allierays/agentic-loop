#!/usr/bin/env python3
"""
Check that FastAPI endpoints have Pydantic response models defined.
Ensures Swagger/OpenAPI docs show proper response schemas.

Usage: python check-fastapi-responses.py [directory]

Exit codes:
  0 - All endpoints have response models
  1 - Some endpoints missing response models
"""

import ast
import sys
from pathlib import Path
from typing import NamedTuple


class EndpointIssue(NamedTuple):
    file: str
    line: int
    method: str
    path: str
    issue: str


def check_file(filepath: Path) -> list[EndpointIssue]:
    """Check a single Python file for FastAPI endpoints without response models."""
    issues = []

    try:
        content = filepath.read_text()
        tree = ast.parse(content)
    except (SyntaxError, UnicodeDecodeError):
        return issues

    # HTTP methods that should have response models
    http_methods = {'get', 'post', 'put', 'patch', 'delete'}

    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue

        # Check decorators for FastAPI route decorators
        for decorator in node.decorator_list:
            # Handle @router.get("/path") or @app.get("/path")
            if isinstance(decorator, ast.Call):
                if isinstance(decorator.func, ast.Attribute):
                    method = decorator.func.attr
                    if method not in http_methods:
                        continue

                    # Get the path from first argument
                    path = "unknown"
                    if decorator.args and isinstance(decorator.args[0], ast.Constant):
                        path = decorator.args[0].value

                    # Check for response_model in keyword arguments
                    has_response_model = any(
                        kw.arg == 'response_model'
                        for kw in decorator.keywords
                    )

                    # Check for return type annotation
                    has_return_annotation = node.returns is not None

                    # Check if return annotation is None or missing
                    is_none_return = (
                        isinstance(node.returns, ast.Constant) and
                        node.returns.value is None
                    )

                    if not has_response_model and (not has_return_annotation or is_none_return):
                        # Skip certain common patterns that don't need response models
                        if method == 'delete' and path.endswith('}'):
                            continue  # DELETE /items/{id} often returns nothing

                        issues.append(EndpointIssue(
                            file=str(filepath),
                            line=node.lineno,
                            method=method.upper(),
                            path=path,
                            issue="Missing response_model or return type annotation"
                        ))

    return issues


def check_directory(directory: Path) -> list[EndpointIssue]:
    """Check all Python files in directory for FastAPI response model issues."""
    all_issues = []

    # Common patterns for API files
    patterns = [
        '**/router*.py',
        '**/routes*.py',
        '**/api*.py',
        '**/endpoints*.py',
        '**/views*.py',
    ]

    checked_files = set()

    for pattern in patterns:
        for filepath in directory.glob(pattern):
            if filepath in checked_files:
                continue
            checked_files.add(filepath)
            all_issues.extend(check_file(filepath))

    # Also check any file with FastAPI imports
    for filepath in directory.rglob('*.py'):
        if filepath in checked_files:
            continue
        try:
            content = filepath.read_text()
            if 'from fastapi' in content or 'import fastapi' in content:
                if 'APIRouter' in content or '@app.' in content or '@router.' in content:
                    all_issues.extend(check_file(filepath))
                    checked_files.add(filepath)
        except (UnicodeDecodeError, PermissionError):
            continue

    return all_issues


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')

    if not directory.exists():
        print(f"Error: Directory not found: {directory}")
        sys.exit(1)

    issues = check_directory(directory)

    if not issues:
        print("✓ All FastAPI endpoints have response models defined")
        sys.exit(0)

    print(f"Found {len(issues)} endpoint(s) without response models:\n")

    for issue in sorted(issues, key=lambda x: (x.file, x.line)):
        print(f"  {issue.file}:{issue.line}")
        print(f"    {issue.method} {issue.path}")
        print(f"    → {issue.issue}\n")

    print("Fix: Add response_model parameter or return type annotation:")
    print('  @router.get("/items", response_model=list[ItemSchema])')
    print("  async def get_items() -> list[ItemSchema]:")

    sys.exit(1)


if __name__ == '__main__':
    main()
