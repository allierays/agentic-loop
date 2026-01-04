# PRD (Product Requirements Document)

Generate a comprehensive PRD by asking the user targeted questions, then output a structured requirements document with implementation tasks.

## Instructions

This skill guides users through defining a feature or project by asking questions in phases, then generates a PRD document they can reference during implementation.

### Phase 1: The Big Picture

Start by asking these questions (wait for answers before proceeding):

**Question 1: What are you building?**
> "What feature or project are you building? Give me a one-sentence description."
>
> Example: "A password reset flow via email" or "An admin dashboard for managing users"

**Question 2: Why does this matter?**
> "What problem does this solve? Who benefits and how?"
>
> Example: "Users forget passwords and currently have to contact support"

**Question 3: What does success look like?**
> "How will you know this feature is working? What can users do that they couldn't before?"
>
> Example: "Users can reset their password within 5 minutes without contacting support"

### Phase 2: Users and Scenarios

After getting the big picture, ask:

**Question 4: Who are the users?**
> "Who will use this feature? List the different types of users."
>
> Example: "Logged-out users who forgot their password, admins who need to force-reset"

**Question 5: Walk me through it**
> "Describe the main user journey step by step. What does the user do, what do they see?"
>
> Example: "User clicks 'Forgot Password', enters email, receives link, clicks link, enters new password, sees success"

**Question 6: What could go wrong?**
> "What edge cases or error scenarios should we handle?"
>
> Example: "Invalid email, expired link, user enters weak password, email not in system"

### Phase 3: Technical Scope

After understanding the user experience, ask:

**Question 7: What already exists?**
> "What existing code, APIs, or infrastructure can we build on? What needs to be created from scratch?"
>
> Example: "We have email sending via SendGrid, need to create the reset token system"

**Question 8: What's out of scope?**
> "What should this feature explicitly NOT do? What's a 'v2' feature?"
>
> Example: "v1 won't support password reset via SMS, just email"

**Question 9: Any constraints?**
> "Are there any technical constraints, security requirements, or dependencies we should know about?"
>
> Example: "Reset links must expire after 1 hour, must work on mobile"

### Phase 4: Generate the PRD

Once you have answers to all questions, generate a PRD document in this format:

```markdown
# PRD: [Feature Name]

## Overview
**One-liner:** [Question 1 answer]
**Problem:** [Question 2 answer]
**Success Metric:** [Question 3 answer]

## Users
[Question 4 answer - formatted as a list]

## User Journey
[Question 5 answer - formatted as numbered steps]

### Happy Path
1. User does X
2. System shows Y
3. User does Z
4. Success state

### Error Scenarios
[Question 6 answer - formatted as a table]

| Scenario | User Action | System Response |
|----------|-------------|-----------------|
| Invalid email | Enters "notanemail" | Shows "Please enter a valid email" |
| ... | ... | ... |

## Technical Requirements

### Dependencies
[Question 7 answer - what exists]

### New Components
[Question 7 answer - what needs building]

### Out of Scope
[Question 8 answer - as a bulleted list]

### Constraints
[Question 9 answer - as a bulleted list]

## Implementation Tasks

Break down into actionable tasks:

### Phase 1: Foundation
- [ ] Task 1
- [ ] Task 2

### Phase 2: Core Feature
- [ ] Task 3
- [ ] Task 4

### Phase 3: Polish
- [ ] Task 5
- [ ] Task 6

## Test Scenarios

Based on the user journey, these E2E tests should be written:

1. **[Happy path test name]** - Verify [success scenario]
2. **[Error case test name]** - Verify [error handling]
3. ...
```

### Phase 5: Offer Next Steps

After generating the PRD, offer:

> "Your PRD is ready! Here's what you can do next:
>
> 1. **Save it** - I can write this to `docs/prd-[feature-name].md`
> 2. **Start TDD** - Use `/tdd-feature` to implement with tests first
> 3. **Refine it** - Tell me what to add or change
>
> What would you like to do?"

## Tips for Gathering Requirements

**If the user gives vague answers:**
- Ask for a specific example
- Ask "Can you walk me through what a user would actually click/see?"
- Ask "What's the simplest version of this that would be useful?"

**If the user wants to skip questions:**
- Mark those sections as "TBD" in the PRD
- Suggest they'll need to answer before implementation

**If the feature is very large:**
- Suggest breaking into multiple PRDs
- Ask "What's the MVP? What's the smallest useful version?"

**If the user already has a PRD:**
- Offer to review and improve it
- Check for missing sections
- Suggest adding test scenarios

## Example Interaction

**User:** `/prd`

**Claude:** "Let's build your PRD! First question: **What feature or project are you building?** Give me a one-sentence description."

**User:** "A comment system for blog posts"

**Claude:** "Got it - a comment system. **Why does this matter?** What problem does this solve, and who benefits?"

**User:** "Readers want to discuss articles but currently can't. It'll increase engagement."

**Claude:** "Makes sense - driving engagement. **What does success look like?** How will you know this is working?"

[...continues through all questions...]

**Claude:** [Generates full PRD document]

"Your PRD is ready! Would you like me to save it to `docs/prd-comment-system.md`, or shall we start implementing with `/tdd-feature`?"

## Integration with Other Skills

After PRD is complete, suggest:
- `/tdd-feature` - Implement features test-first using the PRD as a guide
- `/e2e-scaffold` - Generate E2E test structure from the test scenarios
- `/vibe-check` - Audit existing code before building on it
