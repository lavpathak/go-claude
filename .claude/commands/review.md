# /review — Educational Code Review

Review code with a focus on teaching. Reference ALL relevant skills in `.claude/skills/`.

## Process:

1. **Read the code.** Check which skills apply (error handling, testing, interfaces, etc.)

2. **Categorize into three tiers (max 5 findings total):**
   - 🔴 **Must Fix** — bugs, unhandled errors, security issues, failing tests
   - 🟡 **Should Fix** — Go anti-patterns, naming issues, missing tests, SOLID violations
   - 🟢 **Consider** — style improvements, performance, alternative approaches

3. **For each finding, TEACH:**
   - Show the current code
   - Explain WHY it matters (reference the specific skill and pattern)
   - Show the improved version
   - If it's a Go idiom, explain the idiomatic approach

4. **End with positives.** At least 1 thing done well. Learners need encouragement.

## Checklist to apply:
- Error handling: `.claude/skills/go-error-handling/SKILL.md` anti-patterns
- Testing: `.claude/skills/go-testing/SKILL.md` patterns present?
- Interfaces: `.claude/skills/go-interfaces/SKILL.md` — segregated? consumer-defined?
- SOLID: `.claude/skills/go-solid-patterns/SKILL.md` code smells table
- HTTP: `.claude/skills/go-http-handlers/SKILL.md` — 4-step handler structure?
- Database: `.claude/skills/go-database/SKILL.md` — rows closed? context used?
- Context: `.claude/skills/go-context/SKILL.md` — ctx propagated, not stored?
- Logging: `.claude/skills/go-logging/SKILL.md` — structured, no PII, injected not global?
- Config: `.claude/skills/go-configuration/SKILL.md` — loaded once in main, validated, no env reads in packages?

## Rules:
- Maximum 5 findings. Don't overwhelm.
- Always include at least 1 positive.
- Never rewrite their entire function. Show the minimal change.
- Focus on patterns they'll see repeatedly.

$ARGUMENTS: File path or description of code to review
