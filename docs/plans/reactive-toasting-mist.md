# Plan: Rename "signs" to "lessons"

## Context

The "signs" terminology for learned patterns has always been an internal metaphor (from the original Ralph blog post). "Lessons" is clearer and more intuitive — users immediately understand what "learned lessons" means without needing context. This is a terminology rename across the entire codebase: CLI commands, bash functions, file names, JSON keys, documentation, and skills.

**Naming map:**
| Old | New |
|-----|-----|
| `sign` | `lesson` |
| `signs` | `lessons` |
| `unsign` | `forget` |
| `signs.json` | `lessons.json` |
| `suggested-signs.txt` | `suggested-lessons.txt` |
| `/sign` skill | `/lesson` skill |

No backward-compat aliases — clean break.

---

## Changes

### 1. Rename files and directories

| Old path | New path |
|----------|----------|
| `ralph/signs.sh` | `ralph/lessons.sh` |
| `.claude/skills/sign/SKILL.md` | `.claude/skills/lesson/SKILL.md` |
| `.claude/commands/sign.md` | `.claude/commands/lesson.md` |
| `templates/signs.json` | `templates/lessons.json` |
| `src/checks/check-signs-secrets.ts` | `src/checks/check-lessons-secrets.ts` |

Runtime files (`.ralph/signs.json`, `.ralph/suggested-signs.txt`) are renamed via migration logic in setup.sh, not by git rename.

### 2. Core bash — `ralph/lessons.sh` (was signs.sh)

Rename all three exported functions and their internals:
- `ralph_sign()` → `ralph_lesson()`
- `ralph_signs()` → `ralph_lessons()`
- `ralph_unsign()` → `ralph_forget()`
- All internal variables: `sign_count` → `lesson_count`, `sign_id` → `lesson_id`, etc.
- All user-facing strings: "Added sign:" → "Added lesson:", "No signs recorded" → "No lessons recorded", etc.
- JSON key references: `.signs[]` → `.lessons[]`

### 3. CLI router — `bin/ralph.sh`

Update the case statement:
```
sign)  → lesson)   calls ralph_lesson
signs) → lessons)  calls ralph_lessons
unsign) → forget)  calls ralph_forget
```

Update the `source` line from `signs.sh` to `lessons.sh`.

Update the initialization that creates default `signs.json` → creates `lessons.json` with `{"lessons": []}`.

### 4. Loop engine — `ralph/loop.sh`

- `_sign_is_duplicate()` → `_lesson_is_duplicate()`
- `_maybe_promote_sign()` → `_maybe_promote_lesson()`
- `_inject_signs()` → `_inject_lessons()`
- All call sites of these functions
- Variables: `existing_signs` → `existing_lessons`, etc.
- Constants reference: `SIGN_EXTRACTION_TIMEOUT_SECONDS` → `LESSON_EXTRACTION_TIMEOUT_SECONDS`
- All jq references: `.signs[]` → `.lessons[]`
- File path references: `signs.json` → `lessons.json`, `suggested-signs.txt` → `suggested-lessons.txt`
- Log messages and comments

### 5. Constants — `ralph/utils.sh`

- `MAX_SIGN_CONTEXT_LINES` → `MAX_LESSON_CONTEXT_LINES`
- `MAX_SIGN_DEDUP_EXISTING` → `MAX_LESSON_DEDUP_EXISTING`
- `SIGN_EXTRACTION_TIMEOUT_SECONDS` → `LESSON_EXTRACTION_TIMEOUT_SECONDS`

### 6. Setup and init — `ralph/setup.sh`, `ralph/init.sh`

**setup.sh:**
- Merge logic: references to `signs.json` → `lessons.json`
- jq keys: `.signs[]` → `.lessons[]`
- Variables: `new_signs_added` → `new_lessons_added`
- File path: `suggested-signs.txt` → `suggested-lessons.txt`
- Add **migration**: if `.ralph/signs.json` exists and `.ralph/lessons.json` doesn't, rename the file and rewrite the JSON key from `"signs"` to `"lessons"`. Same for `suggested-signs.txt` → `suggested-lessons.txt`.

**init.sh:**
- Help text: `sign <pattern> [cat]` → `lesson <pattern> [cat]`, `signs` → `lessons`, example commands
- Source line: `signs.sh` → `lessons.sh`

### 7. UAT — `ralph/uat.sh`

- `_auto_sign_from_case()` → `_auto_lesson_from_case()`
- `_inject_signs` calls → `_inject_lessons`
- Log messages: `AUTO_SIGN:` → `AUTO_LESSON:`
- All `ralph_sign` calls → `ralph_lesson`

### 8. Hooks — `ralph/hooks/`

**inject-context.sh:**
- File reference: `signs.json` → `lessons.json`
- Variable: `SIGNS` → `LESSONS`
- jq: `.signs[]?` → `.lessons[]?`
- Context label in output string

**save-learnings.sh:**
- File reference: `suggested-signs.txt` → `suggested-lessons.txt`
- Comments

**install.sh:**
- Comment: "Loads signs & progress" → "Loads lessons & progress"

### 9. TypeScript — `src/checks/`

**check-lessons-secrets.ts** (was check-signs-secrets.ts):
- All string references: "signs.json" → "lessons.json", "in sign" → "in lesson"
- Export name: `checkSignsSecrets` → `checkLessonsSecrets`
- Metadata: id, name, description fields

**index.ts:**
- Import path and name update

### 10. PRD check — `ralph/prd-check.sh`

- References to `signs.json` → `lessons.json`
- References to `suggested-signs.txt` → `suggested-lessons.txt`
- String "signs" in user-facing output → "lessons"

### 11. Templates

**templates/lessons.json** (was signs.json):
- JSON key: `"signs"` → `"lessons"`

**templates/PROMPT.md** (and root PROMPT.md):
- "Read `.ralph/signs.json`" → "Read `.ralph/lessons.json`"
- "patterns learned" text stays the same (it's already good)

### 12. Skills

**.claude/skills/lesson/SKILL.md** (was sign/):
- All references: `/sign` → `/lesson`, `ralph sign` → `ralph lesson`, `ralph signs` → `ralph lessons`
- Description frontmatter

**.claude/skills/prd/SKILL.md:**
- Step 7c: `signs.json` → `lessons.json`, `suggested-signs.txt` → `suggested-lessons.txt`, "signs" → "lessons"

**.claude/skills/prd-check/SKILL.md:**
- All "signs" references → "lessons"

**.claude/skills/vibe-help/SKILL.md** and **.claude/skills/vibe-list/SKILL.md:**
- Command references: `ralph signs` → `ralph lessons`, etc.

### 13. Commands (`.claude/commands/`)

**lesson.md** (was sign.md):
- All references updated

**vibe-help.md** and **vibe-list.md:**
- Command tables and examples

### 14. Documentation (docs/)

All `.md` files in `docs/` — update references:
- `README.md` — diagram, descriptions, tips
- `CLAUDE.md` — file structure reference
- `docs/RALPH.md` — data sources table, signs.json section, commands table, file structure
- `docs/GETTING-STARTED.md` — Step 9 "Teach Ralph with Signs" → "Teach Ralph with Lessons", all command examples
- `docs/CHEATSHEET.md` — command tables
- `docs/SKILLS.md` — skill descriptions
- `docs/PRD-CHECK.md` — cross-reference mentions
- `docs/CUSTOMIZATION.md` — signs section
- `docs/customizing-ralph.md` — signs section
- `docs/ARCHITECTURE.md` — diagrams, command tables, template docs
- `docs/HOOKS.md` — hook descriptions
- `docs/WORKFLOW.md` — command references

### 15. UAT prompt — `.ralph/uat/UAT-PROMPT.md`

- References to `signs.sh`, `signs.json`

---

## Execution Order

1. **Rename files/directories** (git mv)
2. **Core bash**: utils.sh constants → lessons.sh functions → bin/ralph.sh router
3. **Loop engine**: loop.sh function renames and call sites
4. **Supporting bash**: setup.sh (+ migration logic), init.sh, prd-check.sh, uat.sh, hooks
5. **TypeScript**: check file rename + import update
6. **Templates**: JSON key + PROMPT.md
7. **Skills**: lesson SKILL.md, prd, prd-check, vibe-help, vibe-list
8. **Commands**: lesson.md, vibe-help.md, vibe-list.md
9. **Documentation**: all docs/*.md files
10. **Migration test**: verify `setup` migrates old signs.json → lessons.json

## Verification

1. `npx agentic-loop lessons` — lists existing lessons (or "No lessons recorded")
2. `npx agentic-loop lesson "Test pattern" general` — adds a lesson
3. `npx agentic-loop lessons` — shows the new lesson
4. `npx agentic-loop forget "Test pattern"` — removes it
5. `cat .ralph/lessons.json` — confirms JSON uses `"lessons"` key
6. `npx agentic-loop setup` — verify migration: create a fake `.ralph/signs.json`, run setup, confirm it becomes `.ralph/lessons.json` with `"lessons"` key
7. `grep -r "signs" ralph/ src/ .claude/ templates/ PROMPT.md CLAUDE.md docs/ --include="*.sh" --include="*.ts" --include="*.md" --include="*.json" | grep -v node_modules | grep -v ".git/"` — verify no stale references remain (excluding plan files and progress.txt)
