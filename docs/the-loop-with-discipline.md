# Discipline Your Loop. Verify Every Step.

Autonomous AI coding isn't the risk. Undisciplined autonomous AI coding is.

Here's the loop:

```bash
while true; do
  cat PROMPT.md | claude
done
```

Here's the loop with discipline:

```bash
ralph run
```

Same concept. Different engineering.

---

## The CI/CD Parallel

**Before CI/CD:**
```
Write code → FTP to production → Hope it works → Fix at 3am
```

**After CI/CD:**
```
Write code → Build → Test → Stage → Deploy
     ↓         ↓       ↓       ↓        ↓
   commit    gate    gate    gate     gate
```

Every stage has verification. Nothing advances without passing. You can see exactly where it failed and why.

**Before agentic-loop:**
```
Prompt → AI codes → Loop → Hope it works → Wake up to chaos
```

**After agentic-loop:**
```
PRD → Story → Code → Verify → Commit → Next Story → Done
 ↓      ↓       ↓       ↓        ↓          ↓         ↓
spec  scope  execute  gate   atomic    progress    exit
```

Same transformation. Chaos becomes pipeline.

---

## What Discipline Looks Like

| Without | With |
|---------|------|
| "Keep coding until it works" | Stories with acceptance criteria |
| Hope it compiles | Lint → Typecheck → Test → API → Browser |
| One massive diff | One commit per story |
| Loop forever | Exit when PRD complete |
| Same mistakes repeated | Learned patterns prevent regression |

---

## Verification at Every Step

The loop without:
- A defined spec
- Verification gates
- Observable progress
- Exit conditions

...is just prompting on repeat.

**Terraform brought these principles to infrastructure.**

**CI/CD brought them to deployment.**

**agentic-loop brings them to AI coding.**

---

Discipline your loop. Verify every step.
