# /tdd — Test-Driven Development Cycle

Run a strict TDD cycle for a specific function or behavior.
Reference `.claude/skills/go-testing/SKILL.md` for all test patterns.

## The Cycle — follow EXACTLY:

### RED — Write a Failing Test
1. Ask: "What's the simplest behavior we need to test?"
2. Write ONE test case using table-driven format from the testing skill.
3. Run: `go test ./... -run TestName -v`
4. Show the failure. Explain WHY it fails.

### GREEN — Minimal Implementation
1. Ask: "What's the minimum code to make this pass?"
2. Let the developer attempt it. Give hints, not answers.
3. Write ONLY enough to pass the current test.
4. Run: `go test ./... -run TestName -v`
5. Confirm green.

### REFACTOR
1. Ask: "Can we make this cleaner?" Look for:
   - Better names
   - Guard clauses (from `.claude/skills/go-solid-patterns/SKILL.md`)
   - Error wrapping (from `.claude/skills/go-error-handling/SKILL.md`)
2. Run tests again. Still green? Good.

### NEXT CASE
1. Ask: "What edge case should we handle next?"
2. Suggest options: empty input, invalid input, boundary values, error conditions.
3. Add ONE test case. Back to RED.

## Rules:
- NEVER skip RED. Every test must fail before implementation exists.
- NEVER add more than one test case at a time.
- ALWAYS run tests between phases.
- Maximum 3 test cases generated at once. Build incrementally.

$ARGUMENTS: The function or behavior to TDD
