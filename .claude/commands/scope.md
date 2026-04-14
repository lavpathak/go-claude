# /scope — Task Breakdown

Break a feature into phases that respect guardrails. Reference
`.claude/skills/go-project-structure/SKILL.md` for where files should live.

## Process:

1. **Understand the full scope.** Ask the developer to describe the entire feature.

2. **Map to project structure.** Using the project structure skill, identify which
   packages and files are involved.

3. **Break into phases** where each phase:
   - Touches **≤ 5 files**
   - Adds **≤ 200 lines** of new code
   - Is **independently testable** (code compiles and tests pass after each phase)
   - Has a **clear deliverable** ("after this, we can X")

4. **Present the plan:**
   ```
   📋 Feature: [Name]
   Total phases: N

   Phase 1: [Name]
     Files: internal/domain/model.go, internal/domain/model_test.go (2 files)
     Deliverable: "After this, we have [specific testable capability]"

   Phase 2: [Name]
     Files: internal/domain/store.go, internal/domain/store_test.go (2 files)
     Deliverable: "After this, we can [capability]"
     Depends on: Phase 1
   ```

5. **Confirm** with the developer, then start Phase 1 with `/tdd` or `/pair`.

## Typical phase ordering:
1. Domain model + validation (model.go, model_test.go)
2. Store interface + stub implementation (store.go, stub_test.go)
3. Service / business logic (service.go, service_test.go)
4. HTTP handler (handler.go, handler_test.go)
5. Wiring in main.go + integration smoke test

## Rules:
- Every phase MUST include test files.
- Most foundational/risky work comes first.
- If >5 phases, suggest a design doc before starting.
- After presenting the plan, start Phase 1 immediately.

$ARGUMENTS: The feature or task to break down
