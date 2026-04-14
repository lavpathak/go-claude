# /teach — Go Concept Explainer

Teach a Go concept interactively. Always reference the matching skill file for
canonical patterns.

## Process:

1. **Check which skill covers this topic.** Read the relevant `.claude/skills/go-*/SKILL.md`
   file FIRST. The skill defines the team's canonical patterns.

2. **Explain in plain language.** Start with WHY this concept exists. What problem
   does it solve? No jargon dump.

3. **Show a minimal example** (<20 lines). Use the team's domain when possible, not
   foo/bar. Pull the example directly from the relevant skill file.

4. **Show the counter-example.** What does the BAD version look like? Why is it bad?
   Use the anti-patterns section from the skill file.

5. **Connect to our code.** If this pattern appears (or should appear) in our codebase,
   point to it. "You'll see this in internal/user/store.go where we..."

6. **Check understanding.** Ask one of:
   - "What would happen if we removed X here?"
   - "Can you think of where in our code this pattern would help?"
   - "Try modifying this to handle [edge case]. What changes?"

7. **Give a cheat sheet.** 3-5 line reference they can come back to.

## Skill-to-concept mapping:
- "error handling" / "errors" → `go-error-handling/SKILL.md`
- "testing" / "tests" / "TDD" → `go-testing/SKILL.md`
- "interfaces" / "dependency injection" → `go-interfaces/SKILL.md`
- "project structure" / "packages" → `go-project-structure/SKILL.md`
- "goroutines" / "concurrency" / "channels" → `go-concurrency/SKILL.md`
- "SOLID" / "design patterns" / "clean code" → `go-solid-patterns/SKILL.md`
- "handlers" / "HTTP" / "middleware" / "API" → `go-http-handlers/SKILL.md`
- "database" / "SQL" / "queries" / "transactions" → `go-database/SKILL.md`
- "context" / "cancellation" / "deadlines" → `go-context/SKILL.md`
- "logging" / "slog" / "structured logs" → `go-logging/SKILL.md`
- "config" / "env vars" / "secrets" → `go-configuration/SKILL.md`

## Rules:
- Keep code examples under 20 lines.
- Always end with a check-for-understanding question.
- Never just link to docs. Teach in YOUR words with OUR examples.
- Adapt to their level. If confused, re-explain from a different angle.

$ARGUMENTS: The Go concept to learn
