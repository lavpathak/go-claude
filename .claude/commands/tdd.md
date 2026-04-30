# /tdd — Test-Driven Development Cycle

Run a Red → Green → Refactor cycle. Pacing and how many tests Claude
writes at once depend on the current engineer mode in `CLAUDE.md`. Read
that mode first. The cycle itself is mandatory in every mode — no
implementation code without a failing test.

Reference `.claude/skills/go-testing/SKILL.md` for canonical test patterns.

---

## Mode: `beginner` — Strict, One Case at a Time

### RED — Write a Failing Test
1. Ask: "What's the simplest behavior we need to test?"
2. Write ONE test case using the table-driven format from the testing skill.
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
2. Suggest options: empty input, invalid input, boundary values, error
   conditions.
3. Add ONE test case. Back to RED.

### Rules:
- NEVER skip RED. Every test must fail before implementation exists.
- ONE test case at a time. Build incrementally.
- ALWAYS run tests between phases.
- Hints, not answers.

---

## Mode: `senior` — Cycle Stays, Pacing Loosens

### Test list first
1. Name the behaviors you'll cover in 4-8 bullets — happy path, validation,
   boundaries, error semantics.
2. Confirm or adjust the list with the developer in one round.

### RED
- When the table is obvious (validation rules, boundary inputs), write the
  initial table with 3-5 cases up front.
- For trickier behaviors (error mapping, concurrency), stay one case at a
  time.
- Run: `go test ./... -run TestName -v`. Show failures.

### GREEN
- Implement the minimum needed to pass the current red set.
- Skip the "what's the minimum?" Socratic prompt — just write it.
- Run tests.

### REFACTOR
- Apply skill patterns silently. Call out only deliberate deviations.
- Run tests after refactor.

### NEXT
- Move to the next item on the test list. Repeat.

### Rules:
- RED still mandatory — failing test before code, every time.
- The whole feature ends with the test list fully covered. Don't skip
  cases to ship faster.

---

## Mode: `staff` — Test List Up Front, Spike-Then-Test Permitted

### Open with the contract
1. Specify the behavior under test as a contract: invariants, pre/post
   conditions, error semantics, concurrency expectations.
2. Propose the full test list — unit, integration, and (where it earns
   its keep) property-based or fuzz tests.
3. Decide what's covered at which level. Confirm.

### Cycle
- Drive Red → Green → Refactor across the test list. Group related cases
  into one red step where it makes sense.
- For genuinely exploratory work where the design isn't clear yet, a
  short spike is allowed — write throwaway code to learn the shape, then
  *delete it* and start over from RED. Spike code never merges without
  passing through the cycle.
- Apply skill patterns silently. Narrate only at design seams.

### Close with the gate
- Before declaring done: every behavior on the test list has a test.
- Run with `-race` and `-count=1`.
- Note any properties that *should* be tested but aren't (e.g. requires
  staging env, requires real DB) and explain why.

### Rules:
- The "now we test it" gate before merge is non-negotiable, even after a
  spike.
- If a property can't be unit-tested, say so explicitly and propose where
  it *is* tested (integration, e2e, observability).

---

## Common rules (all modes)

- A failing test must precede any implementation code, in every mode.
- Tests use the patterns in `.claude/skills/go-testing/SKILL.md`. Mode
  controls pacing, not test quality.
- Run `-race` for any code touching goroutines.

$ARGUMENTS: The function or behavior to TDD
