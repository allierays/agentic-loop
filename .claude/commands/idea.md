---
description: Brainstorm a feature idea in plan mode, then generate PRDs for Ralph autonomous execution.
---

# /idea - From Brainstorm to PRD

You are helping the user go from a rough idea to executable PRDs for Ralph.

## User Input

```text
$ARGUMENTS
```

## Workflow

### Step 1: Enter Plan Mode

First, enter plan mode to explore this idea thoroughly. Use the EnterPlanMode tool.

Say: "Let's explore this idea. Entering plan mode to brainstorm..."

### Step 2: Brainstorm

In plan mode, help the user flesh out the idea:

1. **Understand the goal** - What problem does this solve? Who benefits?
2. **Explore the codebase** - What exists? What patterns should we follow?
3. **Ask clarifying questions** - Up to 5 questions about:
   - Scope boundaries (what's in/out)
   - User experience (what does the user see/do)
   - Edge cases (what could go wrong)
   - Dependencies (what does this touch)
   - Security/permissions (who can do what)
   - Scale (how many users/items/requests? what happens at 10x?)
4. **Map the architecture** - Where should code live? What patterns to follow?
5. **Design the approach** - How should this be built?

Take your time. This is the creative phase.

### Step 2b: Architecture Discovery

Before designing, explore the codebase to understand:

1. **Directory structure** - Run `ls -la` and `find . -type d -name "src" -o -name "lib" -o -name "app"` to map the project
2. **Existing patterns** - Look for similar features and note how they're organized
3. **Naming conventions** - Check existing files for PascalCase, camelCase, kebab-case usage
4. **Reusable components** - Identify existing utilities, components, hooks to reuse

Document findings in your plan before proceeding.

### Step 3: Write the Idea File

When the brainstorm feels complete, write a markdown file:

1. Create the directory if needed:
   ```bash
   mkdir -p docs/ideas
   ```

2. Write to `docs/ideas/{feature-name}.md` with this structure:
   ```markdown
   # {Feature Name}

   ## Problem
   What problem does this solve?

   ## Solution
   High-level description of the solution.

   ## User Stories
   - As a [user], I want to [action] so that [benefit]
   - ...

   ## Scope
   ### In Scope
   - ...

   ### Out of Scope
   - ...

   ## Architecture
   ### Directory Structure
   - Where new files should go (be specific: `src/components/forms/`, not just `src/`)
   - Scripts go in `scripts/` or `bin/`
   - Docs go in `docs/`
   - Tests mirror source structure

   ### Patterns to Follow
   - Existing components/utilities to reuse (don't reinvent)
   - Naming conventions (PascalCase, camelCase, etc.)
   - File size guidance (split if > 300 lines)

   ### Do NOT Create
   - List things that already exist (avoid duplication)

   ## Scalability
   - Expected scale (users, items, requests per second)
   - Pagination strategy (offset, cursor, keyset)
   - Caching strategy (what to cache, TTL, invalidation)
   - Rate limiting (if applicable)
   - Database considerations (indexes, query optimization)

   ## Technical Notes
   - Dependencies
   - Security considerations

   ## Open Questions
   - Any unresolved decisions
   ```

3. Open the file for review:
   ```bash
   open -a TextEdit docs/ideas/{feature-name}.md
   ```

4. Say: "I've written the idea to `docs/ideas/{feature-name}.md` and opened it in TextEdit. Review it and let me know:
   - **'approved'** - Ready to split into PRDs
   - **'edit'** - Tell me what to change
   - Or just make edits in the file and say 'done'"

### Step 4: Wait for Approval

Wait for the user to approve or request changes. If they request changes, make them and re-open the file.

### Step 5: Split into PRDs

Once the idea is approved, break it into small, executable PRDs:

1. Each PRD should be completable in one Claude session (~10-15 min of work)
2. Each PRD needs:
   - Clear acceptance criteria
   - Specific test steps (curl commands, UI checks, etc.)
   - Dependencies on other PRDs (if any)

Generate the PRD JSON structure. **Each story must define error handling and edge cases to prevent bugs.**

```json
{
  "feature": {
    "name": "Feature Name",
    "ideaFile": "docs/ideas/{feature-name}.md",
    "branch": "feature/{feature-name}",
    "status": "pending"
  },
  "metadata": {
    "createdAt": "ISO timestamp",
    "estimatedStories": 5,
    "complexity": "low|medium|high"
  },
  "scalability": {
    "expectedScale": {
      "users": "100s | 1000s | 10000s+",
      "itemsPerList": 100,
      "requestsPerMinute": 1000
    },
    "pagination": {
      "strategy": "cursor | offset | none",
      "pageSize": 20,
      "maxPageSize": 100
    },
    "caching": {
      "strategy": "none | in-memory | redis | cdn",
      "ttlSeconds": 300,
      "invalidateOn": ["create", "update", "delete"]
    },
    "rateLimiting": {
      "enabled": false,
      "requestsPerMinute": 60,
      "scope": "user | ip | global"
    },
    "database": {
      "indexes": ["fields that need indexes"],
      "avoidNPlusOne": ["relationships to eager load"],
      "batchOperations": ["operations that should batch"]
    }
  },
  "architecture": {
    "directories": {
      "components": "src/components/{feature}/",
      "api": "src/api/",
      "types": "src/types/",
      "utils": "src/utils/",
      "tests": "tests/{feature}/",
      "scripts": "scripts/",
      "docs": "docs/"
    },
    "patterns": {
      "reuse": [
        "Use existing Button from src/components/ui",
        "Use existing validation utils from src/utils/validation"
      ],
      "follow": [
        "Match existing form patterns in src/components/forms/",
        "Follow API route structure in src/api/"
      ]
    },
    "naming": {
      "components": "PascalCase (e.g., ContactForm.tsx)",
      "utilities": "camelCase (e.g., validateEmail.ts)",
      "constants": "SCREAMING_SNAKE_CASE",
      "files": "kebab-case for non-component files"
    },
    "principles": {
      "maxFileLines": 300,
      "singleResponsibility": true,
      "domainDrivenDirs": true
    },
    "doNotCreate": [
      "New button component (use existing)",
      "Custom fetch wrapper (use existing apiClient)"
    ]
  },
  "stories": [
    // FRONTEND STORY EXAMPLE
    {
      "id": "US-001",
      "type": "frontend",
      "title": "User can submit contact form",
      "passes": false,
      "testUrl": "http://localhost:3000/contact",

      "files": {
        "create": [
          "src/components/contact/ContactForm.tsx",
          "src/components/contact/ContactForm.test.tsx"
        ],
        "modify": [
          "src/pages/contact.tsx"
        ],
        "reuse": [
          "src/components/ui/Button.tsx",
          "src/utils/validation.ts"
        ]
      },

      "acceptanceCriteria": [
        "Form has name, email, message fields",
        "Submit button sends data to API",
        "Success message shown after submit"
      ],

      "errorHandling": [
        "Show validation errors for empty fields",
        "Show error message if API fails",
        "Disable submit while loading"
      ],

      "emptyState": null,
      "loadingState": "Submit button shows spinner, is disabled",

      "a11y": [
        "All inputs have labels",
        "Errors announced to screen readers"
      ],

      "mobile": "Form stacks vertically",

      "testSteps": [
        "Navigate to /contact",
        "Fill form and submit",
        "Verify success message"
      ],

      "dependsOn": []
    },

    // BACKEND STORY EXAMPLE (CREATE - no pagination needed)
    {
      "id": "US-002",
      "type": "backend",
      "title": "Contact form API endpoint",
      "passes": false,
      "apiEndpoints": ["POST /api/contact"],

      "files": {
        "create": [
          "src/api/contact/route.ts",
          "src/api/contact/route.test.ts",
          "src/types/contact.ts"
        ],
        "modify": [],
        "reuse": [
          "src/lib/db.ts",
          "src/utils/validation.ts"
        ]
      },

      "acceptanceCriteria": [
        "Accepts name, email, message",
        "Saves to database",
        "Returns 201 on success"
      ],

      "errorHandling": [
        "Returns 400 if required fields missing",
        "Returns 400 if email format invalid",
        "Returns 500 with message if DB fails"
      ],

      "validation": {
        "name": "required, max 100 chars",
        "email": "required, valid email format",
        "message": "required, max 1000 chars"
      },

      "auth": "None (public endpoint)",

      "scale": {
        "rateLimit": "60 req/min per IP"
      },

      "testSteps": [
        "curl -X POST /api/contact with valid data → 201",
        "curl -X POST /api/contact with missing email → 400",
        "curl -X POST /api/contact with invalid email → 400"
      ],

      "dependsOn": []
    },

    // BACKEND STORY EXAMPLE (LIST - needs pagination, caching, indexes)
    {
      "id": "US-003",
      "type": "backend",
      "title": "List contacts API endpoint",
      "passes": false,
      "apiEndpoints": ["GET /api/contacts"],

      "files": {
        "create": [
          "src/api/contacts/route.ts",
          "src/api/contacts/route.test.ts"
        ],
        "modify": [],
        "reuse": [
          "src/lib/db.ts",
          "src/utils/pagination.ts"
        ]
      },

      "acceptanceCriteria": [
        "Returns paginated list of contacts",
        "Supports cursor-based pagination",
        "Returns 200 with items and nextCursor"
      ],

      "errorHandling": [
        "Returns 400 if invalid cursor",
        "Returns 401 if not authenticated",
        "Returns 500 with message if DB fails"
      ],

      "validation": {
        "cursor": "optional, valid base64 string",
        "limit": "optional, 1-100, default 20"
      },

      "auth": "Required (admin only)",

      "scale": {
        "pagination": "cursor-based, 20 per page, max 100",
        "caching": "cache list for 5 min, invalidate on create/update/delete",
        "indexes": ["created_at", "email"],
        "eagerLoad": [],
        "rateLimit": "100 req/min per user"
      },

      "testSteps": [
        "curl -X GET /api/contacts → 200 with items[]",
        "curl -X GET /api/contacts?limit=5 → 200 with 5 items",
        "curl -X GET /api/contacts without auth → 401"
      ],

      "dependsOn": ["US-002"]
    }
  ]
}
```

### Required Fields by Story Type

**All stories MUST have:**
- `files` - Explicit file paths (create, modify, reuse)
- `acceptanceCriteria` - What it should do
- `errorHandling` - What happens when things fail

**Frontend stories MUST also have:**
- `testUrl` - URL to test
- `loadingState` - What shows during async operations
- `a11y` - Accessibility requirements
- `mobile` - How it works on mobile

**Backend stories MUST also have:**
- `apiEndpoints` - Endpoints to test
- `validation` - Input validation rules
- `auth` - Authentication requirements
- `scale` - Always include:
  - `rateLimit` - For all public endpoints
  - `pagination`, `caching`, `indexes`, `eagerLoad` - For GET list/query endpoints only

### Step 6: Write PRD and Review

1. Ensure .ralph directory exists:
   ```bash
   mkdir -p .ralph
   ```

2. Write to `.ralph/prd.json`

3. Open both files for review:
   ```bash
   open -a TextEdit docs/ideas/{feature-name}.md .ralph/prd.json
   ```

4. Say: "I've created the PRD with {N} stories. Both files are open in TextEdit:
   - `docs/ideas/{feature-name}.md` - The full idea (source of truth)
   - `.ralph/prd.json` - The executable stories for Ralph

   Review the PRD and let me know:
   - **'approved'** - Ready for `ralph run`
   - **'edit'** - Tell me what to change
   - Or edit the JSON directly and say 'done'"

### Step 7: Final Approval

Wait for the user to approve the PRD. If they request changes, update the JSON and re-open.

Once approved, say:

"Your idea is ready for execution!

**Idea:** `docs/ideas/{feature-name}.md`
**PRD:** `.ralph/prd.json` ({N} stories)

To start autonomous development:
```bash
ralph run
```

Ralph will work through each story, running tests and committing as it goes. You can check progress anytime with `ralph status`."

## Guidelines

### Story Guidelines
- **Keep stories small** - If a story has more than 3-4 acceptance criteria, split it
- **Make test steps concrete** - "User can see X" is vague; "curl /api/x returns 200 with {field}" is testable
- **Order by dependency** - Stories that depend on others should come later
- **Max 10 stories** - If more, suggest splitting into phases
- **Stay in plan mode** - Don't write code during brainstorming
- **Define error handling** - Every story must specify what happens when things fail
- **Think about edge cases** - Empty states, loading states, validation errors
- **Consider accessibility** - Frontend stories need a11y requirements
- **Consider mobile** - Frontend stories need mobile behavior defined

### Architecture Guidelines
- **Domain-driven directories** - Group by feature, not by type (e.g., `src/contact/` not `src/components/`)
- **Scripts in scripts/** - Shell scripts, build scripts, CLI tools
- **Docs in docs/** - Documentation, ADRs, guides
- **Tests mirror source** - `src/foo/bar.ts` → `src/foo/bar.test.ts` or `tests/foo/bar.test.ts`
- **Max 300 lines per file** - Split large files into smaller, focused modules
- **Single responsibility** - Each file/function does one thing well
- **Reuse over recreate** - Always check for existing utilities before creating new ones
- **Explicit file paths** - Every story must specify exactly which files to create/modify
- **No orphan files** - Every new file must be imported/used somewhere
- **Consistent naming** - Follow project's existing conventions

### Scalability Guidelines
- **Always paginate lists** - Never return unbounded arrays; use cursor or offset pagination
- **Think about N+1** - Specify relationships to eager load, avoid loops with DB calls
- **Cache read-heavy endpoints** - Specify TTL and invalidation strategy
- **Add indexes early** - Specify indexes for frequently queried fields
- **Rate limit public endpoints** - Prevent abuse on unauthenticated routes
- **Batch where possible** - Bulk inserts, batch API calls, queue heavy operations
- **Set sensible limits** - Max page size, max request body, max file upload
- **Plan for 10x** - If you expect 100 users, design for 1000

## Error Handling

- If user provides no arguments, ask: "What feature or idea would you like to brainstorm?"
- If .ralph/prd.json already exists, warn: "A PRD already exists. Archive it first: `mv .ralph/prd.json .ralph/archive/`"
- If user abandons mid-flow, the idea file is still saved for later
