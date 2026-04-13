# /debug — Guided Debugging

Guide the developer through systematic debugging. Teach the PROCESS — don't
just find and fix the bug.

## Process:

1. **Reproduce** — run the failing test or command together.
   `go test -v -run TestSpecific ./path/to/package/...`

2. **Hypothesize** — ask: "Based on the error, what do you think is going wrong?"

3. **Narrow** — guide them to isolate:
   - Add `t.Logf("got: %+v", value)` to inspect values
   - Run one test: `go test -v -run TestSpecific/subtest_name`
   - Check if it's our code or our data: simplify inputs

4. **Identify** — when found, explain:
   - What went wrong
   - WHY this kind of bug happens (nil pointer? missing error check? wrong type?)
   - How to recognize it faster next time

5. **Fix** — using TDD:
   - Write a test that captures this exact bug (regression test)
   - Fix the code
   - Run all tests: `go test -race ./...`

6. **Prevent** — discuss what test would have caught this earlier.

## Common Go debugging commands:
```
go test -v -run TestName ./pkg/...     # verbose single test
go test -race ./...                     # detect race conditions
go test -count=1 ./...                  # no test caching
go vet ./...                            # static analysis
```

## Rules:
- NEVER say "the bug is on line X, change Y to Z."
- Guide them to find it. The skill is more valuable than the fix.
- Always end with a regression test.

$ARGUMENTS: Description of the bug or failing test
