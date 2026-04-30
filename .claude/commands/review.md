# /review — Code Review

Review code. Tone, depth, and what Claude focuses on depend on the current
engineer mode in `CLAUDE.md`. Read that mode first, then follow the
matching section below. The Skills System applies in every mode — what
changes is how findings are *framed* and how *deep* the review goes.

---

## Mode: `beginner` — Educational Review

Teach through the review. Help the developer build pattern recognition.

### Process:

1. **Read the code.** Identify which skills apply.
2. **Categorize findings into three tiers:**
   - 🔴 **Must Fix** — bugs, unhandled errors, security issues, failing tests
   - 🟡 **Should Fix** — Go anti-patterns, naming issues, missing tests,
     SOLID violations
   - 🟢 **Consider** — style improvements, performance, alternative
     approaches
3. **For each finding, TEACH:**
   - Show the current code
   - Explain WHY it matters (reference the specific skill and pattern)
   - Show the improved version
   - If it's a Go idiom, explain the idiomatic approach
4. **End with positives.** At least 1 thing done well — learners need
   encouragement.

### Rules:
- Cap findings at what the developer can absorb (typically 5-7). Pick the
  highest-leverage ones — don't overwhelm.
- Always include at least 1 positive.
- Never rewrite their entire function. Show the minimal change.
- Focus on patterns they'll see repeatedly.

---

## Mode: `senior` — Peer Review

Talk to a peer who knows Go. Be direct.

### Process:

1. **Read the code in context.** Pull in the surrounding files where it
   matters.
2. **Lead with the highest-impact issues.** Bugs, races, leaking
   resources, broken error semantics, missing tests on tricky paths.
3. **Call out over-engineering** — speculative interfaces, premature
   abstractions, defensive code for impossible states.
4. **Be terse.** State the issue and the fix. Skip the WHY unless it's
   non-obvious; assume Go fluency.
5. **No mandatory positives.** Mention something done well only if it's
   worth pointing out.

### Style:
- Findings are direct: "this handler swallows the cancel — use
  `context.Cause`" rather than "you might want to consider…"
- Group findings by file or by concern, whichever is clearer.
- No tier emojis required; severity is implied by ordering.
- If the diff is clean, say so in one line.

---

## Mode: `staff` — Architectural Review

Review the *shape* of the change, not just the lines.

### Process:

1. **Re-establish the design intent** in one sentence. What is this change
   trying to enable?
2. **Check architectural fit:**
   - Does this belong in this package? Is the boundary right?
   - Is dependency direction respected? (domain ← application ← interface
     adapter)
   - Are interfaces defined at the consumer? Right size?
   - Is the abstraction earning its keep?
3. **Check operational fit:**
   - Blast radius on rollback?
   - Behavior under partial failure, retries, concurrent writes?
   - Is the change feature-flagged or otherwise reversible if it
     misbehaves in prod?
   - Telemetry — can on-call diagnose this from logs/metrics alone?
4. **Check forward fit:**
   - What does this make harder later? What does it lock in?
   - Where will the next person extend this, and is the seam in the right
     place?
5. **Stylistic and pattern-level findings are out of scope.** Trust the
   author and the skill files. Surface only what affects design,
   correctness, or operability.

### Output:
- A short narrative review (not a finding list) framed around design,
  operational, and forward fit.
- Concrete recommendations with the trade-off named, not just the verdict.

---

## Common rules (all modes)

- Reference skill files when the issue maps to one — by name, not by
  paraphrase.
- Never rewrite code the author didn't ask you to touch. Suggest, don't
  refactor.
- If you find something genuinely surprising or clever, say so — in any
  mode.

$ARGUMENTS: File path or description of code to review
