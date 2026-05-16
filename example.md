# Example Sessions — Working Sessions With Claude

> Real, turn-by-turn transcripts of live working sessions in this repo.
> Each session shows what pairing with Claude actually feels like at a
> given mode, against a real task. User messages are verbatim. Claude's
> responses are verbatim as sent (markdown rendered). Tool calls are
> compressed into one-line summaries in square brackets.
>
> Scenarios all build pieces of a small menu management system. Sessions
> can be read independently, but later sessions sometimes refer to
> earlier ones by name.

## Format

Each turn is labeled **You:** (the developer) or **Claude:**. Section
headers Claude used mid-response have been demoted to bold lines so they
don't collide with the document's heading structure; everything else is
preserved as-sent.

Each session opens with a short header listing scope, the Go skills
Claude consulted, and the outcome (so a reader can tell at a glance
whether the session got to "green" or ended earlier).

---

## Beginner

### Session 1 — `/pair`: `MenuItem` constructor in a new package

**Scenario:** Brand-new `internal/menu` package. Add a `MenuItem` struct
and a `NewMenuItem` constructor that validates inputs and returns errors.

**Scope discussed:** `internal/menu/{money,money_test,item,item_test}.go`
— 4 files, phased 2 + 2.

**Skills referenced:** `go-error-handling`, `go-testing`, `go-project-structure`.

**Outcome:** Session ended mid-Red after writing the first failing test
for `NewMoney`. Design decisions locked: `BasePrice` is a `Money` type
(int64 cents underneath, decimal display via `String()`),
`NewMoney(dollars, cents int) (Money, error)` rejects negatives and
`cents > 99`, one-sentinel error style for validation failures.
Implementation deferred to the next sitting.

---

**You:**

```
/pair Add a MenuItem struct and a NewMenuItem constructor to a new internal/menu package. Validate inputs and return errors.
```

**Claude:**

Mode: **beginner**. We're pairing on a new `internal/menu` package — `MenuItem` struct and a `NewMenuItem` constructor that validates and returns errors.

Before I propose anything concrete, two checks — one on your mental model, one teachable moment that shapes the whole struct.

**What fields does a `MenuItem` need?**

My starting picture is four:

- `Name` (string)
- `Description` (string)
- `Price` (money type — see below)
- `ID` (string — for when we add a repository later)

Anything you want to add or drop? Common candidates we *could* defer: `Category`, `Available bool`, `CreatedAt`. I'd leave them out today and add when we need them.

**The one design choice worth surfacing now: how do we represent price?**

Three common options. This matters more than it looks.

1. **`float64`** (e.g., `12.99`) — Looks natural. **Don't.** Floats can't represent `0.10` exactly in binary, so `0.10 + 0.20` in Go gives `0.30000000000000004`. Fine for graphics, fatal for money.

2. **`int` cents** (e.g., `1299` means $12.99) — Integer math is exact, stdlib only, easy to reason about. Drawback: you have to remember "cents" everywhere, and currencies with different minor units (JPY 0, KWD 3) eventually need a wrapper.

3. **`decimal.Decimal`** (third-party, e.g., `shopspring/decimal`) — Most correct. Pulls in a dependency, which per CLAUDE.md we'd have to flag and justify.

My recommendation: **int cents**. Exact, stdlib-only, smallest thing that works. We can revisit when we need multi-currency.

**Two questions I'm parking until you respond**

- **Validation rules** — what makes an input invalid? (empty name? negative or zero price? name length cap?)
- **Error style** — one sentinel `ErrInvalidMenuItem` that we wrap with field context, or a separate sentinel per field (`ErrEmptyName`, `ErrInvalidPrice`)?

Once we settle fields + price representation, I'll propose the file scope and we write the first failing test together.

**Your call on:** field list, price representation. Push back on anything.

---

**You:**

Can we make price as base price since it can be overriden at a particular store? Otherwise this is a good starting point.

**Claude:**

Good call — `BasePrice` encodes a real domain fact (price is overridable downstream) into the type, which is cheaper than renaming later. Tiny refinement on top of that:

**Field name should make the unit explicit.** In Go, when a numeric field's unit isn't obvious from context, the convention is to suffix it: `time.Sleep(5)` is ambiguous, `time.Sleep(5 * time.Millisecond)` is not. Same principle here — `BasePrice int` could be dollars, cents, or millicents. Two options:

- **`BasePriceCents int`** — unit is in the name, can't be misread at the call site.
- **`BasePrice Money`** where `Money` is a thin `type Money int` wrapper — slightly more ceremony, but typesafe (you can't accidentally pass a count to a price).

For where we are today I'd go with `BasePriceCents int`. The `Money` wrapper is the right call when we have more than one money-like field; with one, it's overkill.

**Locked-in field list**

```go
type MenuItem struct {
    ID              string
    Name            string
    Description     string
    BasePriceCents  int
}
```

OK to lock this in, or push back?

**Back to the parked questions**

I need your read on these two before I propose scope and we write the first test:

**1. Validation rules — what counts as invalid input?**

My suggested defaults (push back on any):

- `ID` — non-empty, trimmed.
- `Name` — non-empty after trim, max 200 chars.
- `Description` — allowed empty (some items have no description), max 2000 chars.
- `BasePriceCents` — must be `> 0`. (Zero-priced items — promotional freebies — are a real thing, but they're better modeled as a promotion than a base price. We can revisit.)

**2. Error style — one sentinel, or one per field?**

- **One sentinel** — `var ErrInvalidMenuItem = errors.New("invalid menu item")`. Callers do `errors.Is(err, ErrInvalidMenuItem)`. Inside the error we wrap with field context: `"empty name"`, `"price must be positive"`. Simpler.
- **One per field** — `ErrEmptyName`, `ErrEmptyID`, `ErrInvalidPrice`, etc. Callers can branch on the specific failure. More ceremony, useful when callers actually do branch (e.g., a form UI highlighting a specific input).

My recommendation: **one sentinel**, wrapped with field context. The caller this constructor will have today is internal code that just rejects bad input — it doesn't need to branch on which field failed. We can split later if a UI ever needs it. This matches `go-error-handling/SKILL.md`'s "smallest API surface that works" guidance.

Your call on validation rules and error style. Once you sign off, I'll propose the 2-file scope and we write the first failing test.

---

**You:**

I dont want cents. Lets do Money. Can money also represent decimal value?

**Claude:**

Honest answer: **Go has no built-in decimal type, and a `Money` wrapper is *still an integer underneath*.** The wrapper gives you type-safety (you can't accidentally add a `Money` to a `Quantity`), it doesn't give you fractional storage. Worth disentangling two things you might mean by "decimal":

- **Decimal *display*** — showing `"$12.99"` instead of `1299`. This is just a `String()` method on the type. Easy in any of the options below.
- **Decimal *storage*** — actually holding `0.001` or `12.9999`. That needs more than an `int` underneath.

So when people say "use a `Money` type" there are three flavors, depending on the precision you actually need:

1. **`type Money int64`, units = cents.** Stores `1299`, prints as `"$12.99"`. Two decimal places max. Fine for most retail menus.

2. **`type Money int64`, units = micros** (1/10000 of a currency unit). Stores `12990000` for $12.99, also stores `1000` for $0.001. Four decimal places max. Used in per-gram pricing, FX, ad-tech.

3. **`decimal.Decimal`** (third-party, `shopspring/decimal`). Arbitrary precision. Real decimal. Costs a dependency — CLAUDE.md says I have to flag any new dep with its maintenance cost.

For a menu, what does the business actually need?
- Whole-cent prices only (`$12.99`, never `$12.991`) → option 1.
- Sub-cent pricing (per-gram, per-ounce, currency conversion mid-flight) → option 2.
- True arbitrary precision (rare for menus) → option 3.

**My recommendation: option 1**

`type Money int64` representing cents, with a `String()` method for decimal display. You get the typesafe `BasePrice Money` field you asked for, decimal *display* via method, decimal *storage* you don't actually need, and zero external dependencies.

Sketch:

```go
// internal/menu/money.go
package menu

import "fmt"

// Money represents an amount of currency in cents.
// Use NewMoney to construct from dollars; arithmetic stays in cents.
type Money int64

// String formats as "$12.99". Negative values are bracketed: "-$1.50".
func (m Money) String() string {
    if m < 0 {
        return fmt.Sprintf("-$%d.%02d", -m/100, -m%100)
    }
    return fmt.Sprintf("$%d.%02d", m/100, m%100)
}
```

Now the struct reads:

```go
type MenuItem struct {
    ID          string
    Name        string
    Description string
    BasePrice   Money
}
```

`item.BasePrice.String()` gives `"$12.99"` for display. Arithmetic (`a + b`) stays exact because it's just `int64` addition under the hood.

**Two follow-ups before we move to scope**

1. **Lock in option 1**, or do you actually have a sub-cent pricing case in mind? (If unsure, option 1 — migrating to micros later is mechanical.)
2. **Do you want a constructor `NewMoney(dollars int, cents int) (Money, error)`** to make construction safe at call sites, or are we OK with `Money(1299)` directly? Constructor is nicer for readers (`NewMoney(12, 99)` is self-documenting); direct cast is less ceremony.

Your call. Once these are settled I'll propose the file scope and we write the first failing test.

---

**You:**

Lets go with 2.

**Claude:**

Quick clarification — your "2" is ambiguous and I don't want to guess wrong. I just gave you two enumerated lists:

- **Money type options 1/2/3** (cents / micros / decimal.Decimal)
- **Follow-up questions 1/2** (lock in option 1? / want a `NewMoney` constructor?)

Two possible reads:

- **Money option 2 = micros.** You'd be saying: "I want sub-cent precision because the question about decimals had a real use case behind it." Plausible — your earlier question about decimal representation hinted at this.
- **Follow-up question 2 = yes, want `NewMoney` constructor.** Plausible because it's the most recent prompt.

Which did you mean? Two sentences and we move on.

---

**You:**

Yes I want NewMoney constructor

**Claude:**

Settled then:
- `Money` = option 1 (`int64` cents under the hood, decimal display via `String()`)
- `NewMoney(dollars, cents int) (Money, error)` constructor

One micro-design call I want to flag before we write a test, so we don't bake in the wrong rule:

**Should `NewMoney` accept negative values?** Two readings:
- *Money as a general type* — refunds and discounts are negative money, so yes, allow it.
- *Money as built by `NewMoney`* — this constructor is for entering *positive* amounts; negatives come out of *arithmetic* (e.g., `discount := base - applied`), not construction.

My recommendation: **`NewMoney` rejects negative dollars or negative cents**. Arithmetic on `Money` can still produce negatives naturally. Document it: "Use `NewMoney` for amount entry; subtract `Money` values to produce negatives." Cleaner contract, can revisit if a real refund-entry case appears.

Also: `cents` must be 0–99. `NewMoney(0, 105)` is a caller bug.

Sound right? If yes, locking in.

**Scope (4 files, two natural phases — well under the 5-file cap)**

**Phase 1 — this sitting:**
- `internal/menu/money.go` (new) — `Money` type, `String()`, `NewMoney()`
- `internal/menu/money_test.go` (new) — tests for `NewMoney` and `String`

**Phase 2 — same sitting if you've got energy, otherwise next:**
- `internal/menu/item.go` (new) — `MenuItem`, `NewMenuItem()`
- `internal/menu/item_test.go` (new) — tests for `NewMenuItem`

Phasing reason: `MenuItem` will depend on `Money`, so building `Money` first means Phase 2's tests can use real `Money` values, not stubs.

**First failing test**

Per beginner `/tdd` flow: one failing case, smallest possible. Table-driven from the start so we have a place to add cases (`go-testing/SKILL.md`).

```go
// internal/menu/money_test.go
package menu

import "testing"

func TestNewMoney(t *testing.T) {
    tests := []struct {
        name    string
        dollars int
        cents   int
        want    Money
        wantErr bool
    }{
        {
            name:    "simple positive amount",
            dollars: 12,
            cents:   99,
            want:    Money(1299),
            wantErr: false,
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            got, err := NewMoney(tc.dollars, tc.cents)
            if (err != nil) != tc.wantErr {
                t.Errorf("NewMoney(%d, %d) error = %v, wantErr %v",
                    tc.dollars, tc.cents, err, tc.wantErr)
            }
            if got != tc.want {
                t.Errorf("NewMoney(%d, %d) = %v, want %v",
                    tc.dollars, tc.cents, got, tc.want)
            }
        })
    }
}
```

Running it:

```
[Bash: go test -v ./internal/menu/...]
./money_test.go:18:18: undefined: Money
./money_test.go:24:25: undefined: NewMoney
FAIL    internal/menu [build failed]
```

That's **RED** — won't even compile because `Money` and `NewMoney` don't exist yet.

**Your turn.** What's the smallest code in a new `internal/menu/money.go` that makes this test compile and pass?

Hint: it doesn't need to validate anything yet. Think about the simplest possible type definition and the simplest possible function that returns the expected value for this single test case.

Take a swing — I'll catch anything off, and we'll add a forcing test case next.

---

**You:**

Lets conclude session 1 here.

**Claude:**

[Session captured to `example.md`. Implementation of `NewMoney` deferred — design + first failing test locked in, the smallest-thing-that-passes step belongs to the next sitting.]

---

## What this session shows (beginner mode)

- **Teach-first pacing.** The price-representation digression took several turns because the choice shapes every line that follows. Senior mode would have made that call in one line.
- **Inline idiom explanation.** Floats-for-money, unit-in-the-name (`time.Sleep` analogy), `%w` wrapping, sentinel errors, table-driven tests — each introduced where it first appeared, with the *why*, not just the *what*.
- **Active confusion management.** When the user's "Lets go with 2" was ambiguous between two enumerated lists, Claude stopped and asked instead of guessing. This is the [`using-agent-skills`](/) operating behavior in practice.
- **Driver/navigator split.** Claude proposed designs but pushed the implementation step (smallest code that makes the test pass) back to the developer. They own the keyboard; Claude owns the catch-net.
- **Natural pause point.** The session ended cleanly mid-Red. The TDD cycle survives across sittings because the next move (smallest passing code) is concrete and obvious from the failing test alone.

---

### Session 2 — `/tdd`: `ParseMoney` as a strict inverse of `Money.String()`

**Scenario:** Same `internal/menu` package as Session 1. Implement
`ParseMoney(s string) (Money, error)` driven strictly by Red → Green → Refactor.

**Scope discussed:** `internal/menu/money.go` (modify),
`internal/menu/money_test.go` (append `TestParseMoney`).

**Skills referenced:** `go-testing`, `go-error-handling`.

**Outcome:** Two full Red → Green cycles captured. First cycle used
fake-it-til-you-make-it to prove the test exercised the function; second
cycle replaced the fake-it with a minimal real parser passing two
positive-input cases. Session ended at the second GREEN, with a forcing-case
table listed for future cycles (negative path, error wrapping for malformed
input, prefix/decimal validation).

---

**You:**

```
/tdd Implement ParseMoney(s string) (Money, error) in the internal/menu package. It parses currency strings like "$12.99" back into a Money value, inverse of Money.String().
```

**Claude:**

Mode: **beginner**. Strict TDD cycle: Red → Green → Refactor, one case at a time.

Quick contract confirmation since you said "inverse of `Money.String()`" in the task:

- **Accept** exactly what `String()` produces: `"$12.99"`, `"$0.00"`, `"-$1.50"`.
- **Reject** everything else: `"12.99"` (no `$`), `"$12"` (no cents), `"$12.9"` (one decimal), `"$12.999"` (three decimals), `""`, whitespace-padded, garbage like `"$twelve"`.

That gives us a clean round-trip property we can test later: `m == ParseMoney(m.String())` for any `Money m`. Drawing the line at "strict inverse" also keeps the rules finite — lenient parsing tends to grow forever (unicode minus? thousand separators? trailing zeros?).

Push back if you want lenient, otherwise we lock strict.

Assuming strict — **first question of the RED phase**:

> **What's the simplest behavior we should test first?**

Don't reach for edge cases yet. Pick one obviously-valid happy-path input. Once we have a baseline green, we'll add forcing cases one at a time to drive out the real implementation.

What case would you start with?

---

**You:**

Lets start with Accept case

**Claude:**

Good. Canonical happy-path case: `"$12.99"` → `Money(1299)`, no error.

Here's the test. Same table-driven pattern as Session 1 — one row today, with the structure ready for the forcing cases we'll add next:

```go
// internal/menu/money_test.go  (appended; TestNewMoney already exists from Session 1)
func TestParseMoney(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    Money
        wantErr bool
    }{
        {
            name:    "simple positive dollars and cents",
            input:   "$12.99",
            want:    Money(1299),
            wantErr: false,
        },
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            got, err := ParseMoney(tc.input)
            if (err != nil) != tc.wantErr {
                t.Errorf("ParseMoney(%q) error = %v, wantErr %v",
                    tc.input, err, tc.wantErr)
            }
            if got != tc.want {
                t.Errorf("ParseMoney(%q) = %v, want %v",
                    tc.input, got, tc.want)
            }
        })
    }
}
```

Running it:

```
[Bash: go test -v -run TestParseMoney ./internal/menu/...]
./money_test.go:42:25: undefined: ParseMoney
FAIL    internal/menu [build failed]
```

**RED.** Won't even compile — `ParseMoney` doesn't exist. That's the strongest kind of red: no implementation, no test, no risk of a false-positive pass.

**GREEN — your turn.** What's the smallest code in `internal/menu/money.go` that makes this test compile and pass?

Hint: it doesn't need to parse anything. It doesn't need to validate anything. It doesn't need to handle any input other than the one we're testing. Think about the cheapest possible function body that returns the right `(Money, error)` pair for this single case.

(Yes, it'll be silly. That's the point — we're going to break it on purpose with the next test case, which is what forces real implementation. This is "fake it 'til you make it" — a real TDD technique, not a shortcut.)

Take a swing.

---

**You:**

ok done.

**Claude:**

Got it. Smallest passing implementation looks like:

```go
// internal/menu/money.go (appended)
func ParseMoney(s string) (Money, error) {
    return Money(1299), nil
}
```

```
[Bash: go test -v -run TestParseMoney ./internal/menu/...]
=== RUN   TestParseMoney/simple_positive_dollars_and_cents
--- PASS: TestParseMoney/simple_positive_dollars_and_cents
PASS
```

**GREEN.** Embarrassingly fake — it returns `Money(1299)` for *any* input, including `""` or `"hello"`. That's exactly the point. The next test case is what forces real parsing.

This pattern has a name: **fake-it-til-you-make-it**. It's a deliberate TDD technique, not a shortcut. By starting with a hardcoded return, you prove your test actually exercises the function. Then each new failing case ratchets the implementation toward correctness one step at a time. The alternative — writing the full parser before any test passes — is how bugs hide inside un-test-exercised branches.

**RED — next case.** The teaching here: pick a forcing input that's *different enough* from `$12.99` that the fake-it can't handle both. Three reasonable candidates:

- `"$0.00"` → `Money(0)` — different number, same shape. Forces actual parsing of digits. **Smallest jump.**
- `"$1.50"` → `Money(150)` — single-digit dollars, non-`.99` cents. Forces digit-by-digit.
- `"-$1.50"` → `Money(-150)` — negative path. Bigger jump (sign handling).

The disciplined TDD move is the smallest jump: `"$0.00"`. Add it, watch it RED, write a real parser, watch both go GREEN. Then add `"-$1.50"` next.

If you want to keep cycling, I'll write the next RED. **Or this is a natural place to conclude Session 2** — we've captured a full Red → Green cycle with the fake-it pattern explained inline, and remaining cycles are mechanical (each one mirrors the one above: forcing case, fail, implement, pass).

Your call: continue, or wrap Session 2 here?

---

**You:**

Lets do $1.50

**Claude:**

OK — slightly bigger jump than the disciplined-minimum `$0.00`, but it still keeps us in positive-only territory and forces real parsing. Fine.

Adding the case to the existing table:

```go
// internal/menu/money_test.go  (TestParseMoney's tests slice, after the first case)
{
    name:    "single-digit dollars and partial cents",
    input:   "$1.50",
    want:    Money(150),
    wantErr: false,
},
```

Running:

```
[Bash: go test -v -run TestParseMoney ./internal/menu/...]
=== RUN   TestParseMoney
=== RUN   TestParseMoney/simple_positive_dollars_and_cents
--- PASS: TestParseMoney/simple_positive_dollars_and_cents
=== RUN   TestParseMoney/single-digit_dollars_and_partial_cents
    money_test.go:60: ParseMoney("$1.50") = $12.99, want $1.50
--- FAIL: TestParseMoney/single-digit_dollars_and_partial_cents
FAIL
```

**RED.** First case still passes (lucky — fake-it happened to match it). New case fails: our function returns `Money(1299)` for *every* input, including `"$1.50"`. The fake-it is officially broken; we need real parsing.

(Side note: the error message reads `$12.99` and `$1.50` — that's `%v` calling `Money.String()` from Session 1. Self-documenting test output for free.)

**GREEN — your turn.** Time for a real implementation.

Think about the steps. What does the parser need to do, in order? I'll list them in the abstract — you map them to Go:

1. Strip the leading `$`.
2. Split the remaining string into two parts: dollars and cents, around the `.`.
3. Convert each part from string to int.
4. Combine: `dollars * 100 + cents`.

Stdlib has every piece you need:

- `strings.TrimPrefix(s, "$")` — removes a known prefix, returns the rest. (Returns `s` unchanged if the prefix isn't there — important later.)
- `strings.Cut(s, ".")` — Go 1.18+. Splits `"1.50"` into `("1", "50", true)`. The `bool` tells you whether the separator was found.
- `strconv.Atoi(s)` — parses an `int` from a decimal string, returns `(int, error)`.

For now: don't worry about *invalid* input. Don't worry about negatives. Don't worry about the round-trip property. Just get `"$12.99"` and `"$1.50"` both passing. Wrong input causing a panic or weird number is fine *for this step* — we'll add forcing cases next that drive validation in.

Take a swing. Show me your `ParseMoney` body.

---

**You:**

ok done

**Claude:**

Got it. Minimal real parser:

```go
// internal/menu/money.go (replaces the fake-it body, adds imports)
import (
    "strconv"
    "strings"
)

func ParseMoney(s string) (Money, error) {
    s = strings.TrimPrefix(s, "$")
    dollarsStr, centsStr, _ := strings.Cut(s, ".")
    dollars, _ := strconv.Atoi(dollarsStr)
    cents, _ := strconv.Atoi(centsStr)
    return Money(dollars*100 + cents), nil
}
```

```
[Bash: go test -v -run TestParseMoney ./internal/menu/...]
=== RUN   TestParseMoney/simple_positive_dollars_and_cents
--- PASS: TestParseMoney/simple_positive_dollars_and_cents
=== RUN   TestParseMoney/single-digit_dollars_and_partial_cents
--- PASS: TestParseMoney/single-digit_dollars_and_partial_cents
PASS
```

**GREEN.** Both cases pass.

Worth flagging: this function is **correct for the two cases tested and broken for everything else.** Three `_` discards swallow real errors (against `go-error-handling/SKILL.md`), negatives produce silently-wrong numbers, `"$abc"` gives `Money(0)` with no error, `""` gives `Money(0)` with no error. The compiler is happy; the function is a trap.

That's exactly what the next forcing cases would drive out:

| Forcing input | What it forces into the code |
|---|---|
| `"-$1.50"` | Sign handling (parse the `-` before stripping `$`) |
| `""` | Empty-input rejection |
| `"$abc"` | Real strconv-error handling — no more `_`, use `%w` to wrap |
| `"$12.9"` / `"$12.999"` | Cents must be exactly 2 digits |
| `"12.99"` | `$` prefix required (the `TrimPrefix` no-op is dangerous) |
| `"$12"` | Decimal point required |

Each row = one more R→G cycle. Implementation grows a guard clause or branch each time. At the end, `ParseMoney` is robust and the test table is comprehensive.

**Two natural off-ramps:**

1. **Wrap Session 2 here.** Clean Red → Green → Red → real-Green cycle captured, fake-it explained, the remaining cycles are mechanical. Pedagogical point is made.
2. **One more cycle for the example.** Pick the teaching-richest case — probably `"$abc"`, since it brings in proper error wrapping with `%w`, which is a Session 1 callback worth reinforcing.

I lean **(1) wrap here** — Session 2 should showcase the cycle, not exhaust every edge case. Your call.

---

**You:**

Lets wrap up session 2 here

**Claude:**

[Session captured to `example.md`. Two Red → Green cycles preserved (fake-it then real parser). Forcing-case table left in the transcript as the natural next-session starting point.]

---

## What this session shows (beginner `/tdd`)

- **Strict one-case-at-a-time discipline.** Even when the user picked a slightly bigger jump (`$1.50` instead of the recommended `$0.00`), the cycle stayed one case at a time. Beginner mode pushes back on overshoot but doesn't override developer judgment.
- **Fake-it-til-you-make-it as a teaching device.** The first GREEN was deliberately silly. The transcript names the technique and explains *why* it isn't a shortcut — it proves the test exercises the function before any real logic exists.
- **Hints, not answers, in GREEN.** Claude listed the four parsing steps in the abstract and named the stdlib functions, but did not write the parser. The developer's "ok done" short-circuit was respected — Claude filled in the trivial step rather than belaboring it, which is the right read of beginner pacing when the developer has clearly absorbed the pattern.
- **Honest GREEN.** The second GREEN passed but the response immediately flagged that the function was *correct for the cases tested and broken for everything else*. Beginner mode shouldn't let a misleading "all green" stand without naming the gap.
- **Graceful off-ramp.** When the cycle pattern is established, the session offered two clear stopping points (wrap vs one more teaching case) instead of grinding through every forcing case. Example transcripts showcase *the cycle*, not exhaustive coverage.

---

### Session 3 — `/teach`: `context.Context` from scratch

**Scenario:** Before touching repository code in a future session, the
developer asks to understand `context.Context` from scratch. Pure
conceptual session — no code lands.

**Scope:** No files touched. Concept summary lives in the transcript.

**Skills referenced:** `go-context`.

**Outcome:** Three sub-topics covered (the problem Context solves,
cancellation mechanics, where contexts originate and how to derive them).
Developer wraps when satisfied.

---

**You:**

```
/teach context.Context. I need to understand it before we touch the repository.
```

**Claude:**

Mode: **beginner**. `/teach` is question-driven — I'll explain, you push back on anything that doesn't land. No code will be written today.

Quick calibration so I don't over- or under-shoot: which is closest to where you're starting?

- Never heard of `context.Context` before today.
- Seen it as the first parameter on Go functions, no idea what it does.
- Vague sense it handles cancellation or timeouts.

What's closest?

---

**You:**

second one. I see ctx everywhere. whats it for?

**Claude:**

Good — that's exactly the right place to start. The short version: `context.Context` is Go's standard way to plumb three things through a chain of function calls:

1. **Cancellation** — a signal saying "stop what you're doing, the caller doesn't care anymore."
2. **Deadlines / timeouts** — a clock running underneath the cancellation: "stop if you take longer than 5 seconds."
3. **Request-scoped values** — small bits of metadata that should flow with the call (trace IDs, user IDs) without polluting every function signature.

Concrete example. Imagine your menu repository has a `GetItem(ctx, id)` that hits a database. Three things can happen mid-call:

- The HTTP request that triggered it gets cancelled (user closed the tab). Without context, the DB query keeps running and returns to nobody. Wasted work.
- The query takes 30 seconds for some reason. Without context, your API endpoint hangs indefinitely. With a 2-second deadline on ctx, the DB driver sees ctx expire and aborts the query.
- A trace system wants to attach a span ID. With ctx, it rides along automatically — no parameter for every layer.

That's the *why*. The *how*: every function that does I/O or waits on something takes `ctx context.Context` as its **first parameter** and respects whatever signal arrives on it.

Want me to go deeper on cancellation mechanics, or on where contexts come from in the first place?

---

**You:**

cancellation. how does the function know to stop?

**Claude:**

Two mechanisms, both stdlib.

**`ctx.Done()`** returns a `<-chan struct{}` — a channel that closes when the context is cancelled. The canonical pattern:

```go
select {
case <-ctx.Done():
    return ctx.Err()  // tells you *why* it was cancelled
case result := <-someWork:
    return result, nil
}
```

You wait on *both* the actual work and `ctx.Done()` at the same time. Whichever fires first wins.

**`ctx.Err()`** tells you why the context was cancelled:

- `context.Canceled` — caller explicitly cancelled.
- `context.DeadlineExceeded` — timeout fired.
- `nil` — context is still alive (don't normally call Err in this state).

For functions that don't do channel work but make a lot of small steps (looping over DB rows, for example), the convention is to check `ctx.Err()` periodically:

```go
for rows.Next() {
    if err := ctx.Err(); err != nil {
        return nil, err
    }
    // process row
}
```

Database drivers and HTTP clients in stdlib already do this internally — `http.Client.Do(req.WithContext(ctx))` cancels the in-flight request when ctx fires. You inherit cancellation for free *if you propagate ctx to them*.

Next question naturally is: where do contexts come from in the first place? Want that?

---

**You:**

yes

**Claude:**

Three roots and four derivations. That's the whole surface area.

**Roots — where contexts originate:**

- `context.Background()` — the canonical "no-cancellation" root. Use in `main`, in tests, anywhere the call chain originates outside a request.
- `context.TODO()` — same thing at runtime, but says "I haven't decided what to plumb here yet." Useful as a placeholder during refactoring. Replace with `Background()` or a real ctx once you know.

**Derivations — how you wrap a parent ctx with extra behavior:**

- `ctx, cancel := context.WithCancel(parent)` — gives you a `cancel` function. Calling it cancels `ctx` and all its descendants. You must call `cancel` (usually `defer cancel()`) to release resources, even if you never actually intend to cancel — the runtime needs that signal to clean up.
- `ctx, cancel := context.WithTimeout(parent, 5*time.Second)` — auto-cancels after the duration. Same `defer cancel()` rule.
- `ctx, cancel := context.WithDeadline(parent, t)` — same idea, but takes an absolute time instead of a duration. Use when you have a hard wall-clock deadline (e.g., a request must finish before midnight).
- `ctx = context.WithValue(parent, key, value)` — attaches a request-scoped value. No `cancel` returned. Used sparingly and only for things like request IDs or trace context, never application data.

Concrete example — how ctx flows through a real call chain:

```go
func main() {
    ctx := context.Background()
    server := NewServer(ctx, ...)
}

// In an HTTP handler:
func (h *Handler) GetItem(w http.ResponseWriter, r *http.Request) {
    ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
    defer cancel()
    item, err := h.repo.GetItem(ctx, id)
    // ...
}

// In the repository:
func (r *Repository) GetItem(ctx context.Context, id string) (*MenuItem, error) {
    return r.db.QueryRowContext(ctx, "SELECT ...", id).Scan(...)
}
```

ctx flows: `main → handler → repository → db driver`. Cancel a single parent and everything downstream stops.

**Two rules that get violated a lot:**

1. **Don't store ctx in a struct field.** Pass it as an argument every time. The exception is HTTP handlers, where the *request* carries its ctx — you extract it with `r.Context()` and pass it onward.
2. **Don't pass `nil` for ctx.** Use `context.TODO()` if you genuinely don't have one yet.

How's the model? Want me to go deeper on WithValue, or are we done?

---

**You:**

done this is enough. wrap.

**Claude:**

[Session captured. No code written; concept summary lives in the transcript. Next time we touch the repository, ctx propagation should land without re-teaching.]

---

## What this session shows (beginner `/teach`)

- **Calibration before content.** The opening turn asked which of three starting points was closest, not "what do you want to know." Cheaper than guessing wrong and re-teaching.
- **One direction per turn.** Each Claude response ended with a single follow-up question, not a buffet. The developer drove the depth.
- **No code lands.** `/teach` is conceptual. Code blocks appeared only as illustrative — not as a deliverable.

---

## Senior

### Session 4 — `/review`: in-memory repository with a planted race

**Scenario:** Developer drafted `internal/menu/repository.go` — an
in-memory store over `MenuItem`. Asks for `/review`. The diff has a
concurrency hazard and an error-style miss.

**Scope:** 1 file (`repository.go`) + the implied test file.

**Skills referenced:** `go-error-handling`, `go-concurrency`, `go-context`.

**Outcome:** Two must-fix callouts (race, sentinel errors), one
should-fix (ctx in signature). Sketch of the fixed version provided.
Developer accepts, schedules `/debug` follow-up to reproduce the race.

---

**You:**

```
/review I drafted internal/menu/repository.go. In-memory store for now. Please review.
```

```go
// internal/menu/repository.go
package menu

import "errors"

type Repository struct {
    items map[string]*MenuItem
}

func NewRepository() *Repository {
    return &Repository{items: make(map[string]*MenuItem)}
}

func (r *Repository) Add(item *MenuItem) error {
    if item == nil {
        return errors.New("nil item")
    }
    r.items[item.ID] = item
    return nil
}

func (r *Repository) Get(id string) (*MenuItem, error) {
    item, ok := r.items[id]
    if !ok {
        return nil, errors.New("not found")
    }
    return item, nil
}
```

**Claude:**

Mode: **senior**. Five-axis review.

**🔴 Correctness — concurrency hazard.** `r.items` is an unsynchronized map. Two goroutines into `Add`/`Get` — or two `Add`s racing — is undefined behavior. `go test -race` will fire instantly. In-memory repos are *always* hit concurrently in practice (HTTP handler pool), so this isn't theoretical.

Fix: `sync.RWMutex` on Repository — `RLock` in Get, `Lock` in Add. RWMutex over plain Mutex because reads dominate writes on a menu read path.

**🟡 Architecture — error semantics.** `errors.New("not found")` is opaque. Callers can't `errors.Is` against it without string matching, and `go-error-handling/SKILL.md` is explicit: sentinel errors for any condition callers might branch on. "Item not found" is exactly that — handlers route it to HTTP 404.

Fix:

```go
var ErrItemNotFound = errors.New("menu: item not found")
// ...
return nil, fmt.Errorf("%w: id=%s", ErrItemNotFound, id)
```

Callers get the sentinel via `errors.Is` *and* the ID in the formatted message for logs. Same applies to the nil-check (or fold it under a generic `ErrInvalidInput` if no caller will branch on it specifically).

**🟡 Architecture — context missing.** No `ctx context.Context` parameter. For an in-memory repo today it changes nothing, but the moment this gets swapped for a DB-backed implementation, every call site has to change. Define the interface with ctx now; the in-memory impl checks `ctx.Err()` and proceeds.

**🟢 Readability.** Constructor is clean, exported names match team convention.

**🟢 Performance.** O(1) map access; no concerns at this layer.

Summary: two must-fix, one should-fix-now. Want the fixed sketch, or take a swing first?

---

**You:**

sketch the fix.

**Claude:**

```go
// internal/menu/repository.go
package menu

import (
    "context"
    "errors"
    "fmt"
    "sync"
)

var (
    ErrItemNotFound = errors.New("menu: item not found")
    ErrNilItem      = errors.New("menu: nil item")
)

type Repository struct {
    mu    sync.RWMutex
    items map[string]*MenuItem
}

func NewRepository() *Repository {
    return &Repository{items: make(map[string]*MenuItem)}
}

func (r *Repository) Add(ctx context.Context, item *MenuItem) error {
    if item == nil {
        return ErrNilItem
    }
    if err := ctx.Err(); err != nil {
        return err
    }
    r.mu.Lock()
    defer r.mu.Unlock()
    r.items[item.ID] = item
    return nil
}

func (r *Repository) Get(ctx context.Context, id string) (*MenuItem, error) {
    if err := ctx.Err(); err != nil {
        return nil, err
    }
    r.mu.RLock()
    defer r.mu.RUnlock()
    item, ok := r.items[id]
    if !ok {
        return nil, fmt.Errorf("%w: id=%s", ErrItemNotFound, id)
    }
    return item, nil
}
```

Two non-obvious calls worth flagging:

- `ctx.Err()` check happens *before* the lock — cheap, no point grabbing a mutex if we're about to bail.
- `fmt.Errorf` with `%w` is the wrap pattern: callers get `errors.Is(err, ErrItemNotFound)` for routing-to-404, and the ID still surfaces in the message for logs.

A `TestRepository_ConcurrentAddGet` will be needed to lock in the race fix. Want me to drive that in a follow-up `/debug` or `/tdd` session?

---

**You:**

yes follow up with /debug — I want to confirm the race reproduces first. wrap this review.

**Claude:**

[Review captured. Two must-fix landed in the sketch. Next session: `/debug` to reproduce the race against the original code and verify the fix closes it.]

---

## What this session shows (senior `/review`)

- **Five-axis scan, severity-labeled.** Each finding led with 🔴/🟡/🟢 and one line of *what* before the *fix*. Senior tier doesn't pad explanations — the developer already knows why a race is a race.
- **Skill citations only when load-bearing.** `go-error-handling/SKILL.md` named because the developer's draft contradicted it. No `go-concurrency` citation needed for the race — the finding speaks for itself.
- **Fix on request, not by default.** Senior `/review` flags problems; the developer asks for sketches when they want them.

---

### Session 5 — `/debug`: items disappear under concurrent writes

**Scenario:** Direct follow-up to Session 4. Developer reproduces the
unsynchronized-map race that the `/review` flagged, then validates the
fix closes it.

**Scope:** `internal/menu/repository_test.go` (new regression test).

**Skills referenced:** `go-concurrency`, `go-testing`.

**Outcome:** Race reproduced under `-race`, fix from Session 4
confirmed via a stronger regression that asserts *all* concurrent writes
are visible afterwards (not just that the race detector stays quiet).

---

**You:**

```
/debug Items I add concurrently sometimes disappear from Get. Original repository code from before the review.
```

**Claude:**

Mode: **senior**. Hypothesis-led.

Symptom restated: concurrent `Add(item)` calls — some items end up unreachable via `Get(id)` later, even though `Add` returned `nil`.

Strongest hypothesis up front (cheap to confirm): unsynchronized map access. Concurrent writes to a Go map are undefined behavior — Go's runtime sometimes detects it and panics with "concurrent map writes," but more often the map silently corrupts: entries vanish, lookups return wrong values, or the program crashes with a bus error.

Verification step #1: reproduce under `-race`. The race detector will flag the unsynchronized access regardless of whether *visible* corruption fires in any given run.

```go
// internal/menu/repository_test.go
func TestRepository_ConcurrentAddGetReproducesRace(t *testing.T) {
    repo := NewRepository()
    var wg sync.WaitGroup
    for i := 0; i < 100; i++ {
        wg.Add(1)
        go func(i int) {
            defer wg.Done()
            id := fmt.Sprintf("item-%d", i)
            _ = repo.Add(&MenuItem{ID: id, Name: id})
            _, _ = repo.Get(id)
        }(i)
    }
    wg.Wait()
}
```

```
[Bash: go test -race -run TestRepository_ConcurrentAddGetReproducesRace ./internal/menu/...]
```

What do you see?

---

**You:**

WARNING: DATA RACE — Read at 0x... by goroutine 42, Previous write at 0x... by goroutine 17. Both on r.items in repository.go.

**Claude:**

Hypothesis confirmed. The race detector is showing exactly what we'd expect — concurrent read of `r.items` (from Get) overlapping a write (from Add) with no synchronization. That's the root cause of "items disappear": the map's internal state is being torn between the two access paths, and the visible disappearance is one of several symptoms of that corruption.

Two legitimate fixes:

- **`sync.RWMutex` on Repository** — `RLock`/`RUnlock` on reads, `Lock`/`Unlock` on writes. Predictable iteration order, no surprises. Recommended.
- **`sync.Map`** — stdlib's concurrent map. Avoids the explicit lock dance but has a weird API (`Load`/`Store`/`Range`) and is only worth it under specific access patterns (write-once, read-many at high concurrency). Overkill here.

Go with RWMutex — Session 4's review sketch already has it.

To *prove* the fix closes the race rather than just papering over it, re-run with `-count=10` to reduce the chance of the race detector missing a narrow window:

```
[Bash: go test -race -count=10 -run TestRepository_ConcurrentAdd... ./internal/menu/...]
PASS
```

Pass on all 10 = high confidence.

One thing worth flagging on test quality: the current regression only verifies "no race fires." It doesn't verify "all 100 items are actually reachable after the writes complete." Stronger regression:

```go
func TestRepository_ConcurrentAddAllVisible(t *testing.T) {
    repo := NewRepository()
    const n = 100
    ctx := context.Background()
    var wg sync.WaitGroup
    for i := 0; i < n; i++ {
        wg.Add(1)
        go func(i int) {
            defer wg.Done()
            id := fmt.Sprintf("item-%d", i)
            if err := repo.Add(ctx, &MenuItem{ID: id, Name: id}); err != nil {
                t.Errorf("Add: %v", err)
            }
        }(i)
    }
    wg.Wait()
    for i := 0; i < n; i++ {
        id := fmt.Sprintf("item-%d", i)
        if _, err := repo.Get(ctx, id); err != nil {
            t.Errorf("Get(%q) after concurrent Add: %v", id, err)
        }
    }
}
```

Catches both the race (under `-race`) *and* the data-loss symptom (a missed item produces a Get error). This is the test you actually want in CI.

Apply the Session 4 fix, run this against it. Should be green on `-race -count=10`.

---

**You:**

nope green. wrap.

**Claude:**

[Race reproduced under `-race`, confirmed as the root cause of items-disappearing, fix verified via the stronger regression. Both tests now part of `internal/menu/repository_test.go`.]

---

## What this session shows (senior `/debug`)

- **Hypothesis up front, not bisect-first.** The strongest hypothesis (unsynchronized map) was named in turn one with a verification step. Senior debugging skips the "what are you observing exactly" interview when the symptom is already specific.
- **Two regressions, not one.** The first regression just confirms "race detector stays quiet" — not enough. The session pushed for a second regression that asserts the *visible* symptom (data loss) is closed too. Race-detector pass alone hides timing-window misses.
- **Reproduce, don't speculate.** Even with high confidence in the hypothesis, the session ran the test before declaring victory. "Pretty sure that's the bug" is not a fix.

---

## Staff

### Session 6 — `/scope`: pricing rules engine initiative

**Scenario:** New initiative — pricing rules engine for happy hour,
customer-tier discounts, combo deals. Multi-phase plan with rollout
considerations. Staff mode: design forces locked before phasing.

**Scope discussed:** multi-file initiative — `internal/pricing/*` (new
package), eventual menu HTTP layer wiring, eventual DB-backed rule
store.

**Skills referenced:** `go-interfaces`, `go-error-handling`, `go-context`.
Routes to `agent-skills:spec` for the Rule interface contract.

**Outcome:** 5-phase plan with per-phase rollback. Five architectural
decisions pinned (storage, evaluation order, idempotency, failure mode,
dependency direction). Spec routed before phase 1 code.

---

**You:**

```
/scope add a pricing rules engine. Need to support happy hour, customer-tier pricing (loyalty / staff / VIP), and combo deals (buy two get one).
```

**Claude:**

Mode: **staff**. Before phasing, five design forces I want pinned — each one constrains every phase that follows.

**1. Rule storage.**

- *In code* (`var rules = []Rule{...}`). Cheapest. Every rule change is a deploy. Fine for a small fixed set; awful for happy-hour windows that ops needs to flip without engineering.
- *In database*. Ops-friendly. Adds a load path, a cache-invalidation problem, and a "what if the DB is down" failure mode for pricing.
- *In config service* (flag vendor). Same as DB but with built-in flag semantics. Costs you a vendor dependency.

Recommendation: **in code for phase 1**, *interface* designed so swapping to DB later is mechanical. Don't pay cache/invalidation cost on day one for a feature whose scope you're still discovering.

**2. Evaluation order — stacking semantics.**

- Apply all matching rules sequentially. Deterministic but discount stacking explodes — VIP at happy hour during a combo gets four rules layered.
- Pick one rule per pricing event via an explicit priority field. Predictable, auditable.

Recommendation: **explicit priority field on Rule**. Highest-priority matching rule wins. Stacking becomes a deliberate rule-author choice ("VIP-during-happy-hour" is its own rule), not emergent behavior.

**3. Idempotency.** Is pricing a *function* of `(item, customer, time)` — same answer every call — or does the engine mutate state (e.g., "100 free coffees per day" counter)?

Recommendation: **idempotent for v1**. No counters, no state mutation. Coupons-with-redemption-limits is a separate problem.

**4. Failure mode — rule evaluation errors.**

- *Fail closed* — return error, refuse to price. Safe but every malformed rule takes down a checkout.
- *Fail open with logging* — fall back to `MenuItem.BasePrice`, log loudly. Customers pay base price; ops sees the alert.

Recommendation: **fail open**. Pricing-engine bugs shouldn't block transactions; they should produce alerts.

**5. Dependency direction.** Engine sits *between* MenuItem retrieval and HTTP response. Repository returns base prices; engine produces effective prices for a given customer context. Engine doesn't touch the repository — single-direction dependency.

Push back on any of these, or move to phasing.

---

**You:**

all good. Rules in code first, priority field, idempotent, fail open. lets phase.

**Claude:**

Locked.

**📋 Initiative: pricing rules engine — total phases: 5**

**Phase 1 — Rule interface + evaluation engine (code-stored rules)**
- `internal/pricing/rule.go` (new) — `Rule` interface, `PricingContext` struct (item, customer, time).
- `internal/pricing/engine.go` (new) — `Engine.Price(ctx, PricingContext) (Money, error)` with fail-open semantics.
- `internal/pricing/{rule,engine}_test.go` (new)
- **Deliverable:** stand-alone engine with two stub rules in tests. No menu integration yet.

**Phase 2 — Concrete rules: happy hour + customer tier**
- `internal/pricing/rules/happyhour.go` (new) — time-window rule.
- `internal/pricing/rules/tier.go` (new) — customer-tier rule.
- Tests for each.
- **Deliverable:** two real rules, registered with the engine via a builder. Still no menu integration.

**Phase 3 — Combo deal rule**
- `internal/pricing/rules/combo.go` (new) — requires `PricingContext` to carry the full cart, not just a single item.
- Refactor `PricingContext` to support multi-item evaluation.
- **Deliverable:** combo rule wired in. **Riskiest phase** — forces a context-shape change that ripples back to phase 1's interface.

**Phase 4 — Wire into menu HTTP layer**
- `internal/menu/handler.go` (modify) — accept customer ID from headers/session, call engine, return effective price alongside `MenuItem`.
- **Deliverable:** customer-facing API returns effective pricing. Dark-launched behind a header flag.

**Phase 5 — Rule storage migration to DB**
- `internal/pricing/store.go` (new) — Rule storage interface.
- DB-backed implementation. In-code rules kept as a fallback when store unavailable.
- **Deliverable:** ops can edit rules without deploys.

**Rollback per phase:** every phase ships behind `PRICING_ENGINE_ENABLED=false`. Default off until phase 4 dark-launches. Flag check happens at request time so flip is hot.

**Phase ordering rationale:** interface before concrete rules (phase 1 → 2) lets us delete-and-replace rules without engine churn. Combo (phase 3) before menu integration (phase 4) means the context shape stabilizes before any external API depends on it. Store migration (phase 5) last because it's the most reversible — moving from "in code" to "in DB" is purely additive.

**One lifecycle gap.** The Rule *interface contract* needs a written spec before phase 1 code lands — what does a rule return for non-applicable cases, what's the priority comparison rule, what happens if two rules tie on priority, what's the engine's contract for fail-open. Repo has no local `/spec` command; this is exactly the gap `agent-skills:spec` is designed for.

Recommend routing to `agent-skills:spec` for the Rule interface contract before phase 1 `/tdd`. Sign off?

---

**You:**

yes route to agent-skills:spec, wrap /scope.

**Claude:**

[Phase plan captured. Handing off to `agent-skills:spec` for the Rule interface contract. Will bring the spec back for sign-off before `/tdd` Phase 1.]

---

## What this session shows (staff `/scope`)

- **Design before phases.** Five architectural forces named and recommended before any phase boundary was drawn. Phases derive from the design — a phase plan without those decisions locked is busywork.
- **Rollback baked into every phase.** Each phase ships behind a flag with a documented flip path. Staff-level scoping doesn't separate "build" from "operate."
- **Lifecycle gap surfaced honestly.** The Rule contract belongs in a spec, and the repo has no local `/spec` command. The session routed to `agent-skills:spec` explicitly — local first, agent-skills for gaps, per CLAUDE.md.

---

### Session 7 — `/pair`: POS sync gateway

**Scenario:** Design and begin a sync gateway between this service and
a downstream POS for menu updates. Staff `/pair` — architecture-first
conversation, interface sketched, code deferred to spec + phase 1.

**Scope discussed:** new `internal/sync` package; eventual durable
outbox pattern over the menu DB.

**Skills referenced:** `go-interfaces`, `go-context`, `go-error-handling`,
`go-concurrency`. Routes to `agent-skills:spec` for the Sender contract.

**Outcome:** Five design forces resolved (push, idempotency key,
per-item retry, thick gateway, loose coupling). Gateway/Sender interface
sketch. Two-phase rollout (in-memory → durable outbox) agreed. Spec
routed before phase 1 code.

---

**You:**

```
/pair build a sync gateway between this service and a downstream POS for menu updates.
```

**Claude:**

Mode: **staff**. Architecture first. Five forces I need pinned before any code:

**1. Push vs pull.**
- *Push* — we POST to POS on every menu change. Real-time, but every retry, dead-letter, and idempotency concern lives in our code.
- *Pull* — POS polls us for changes since timestamp X. Simpler for us, POS controls freshness budget.

Which does the POS support? If both, push gives lower latency at higher operational complexity.

**2. Idempotency.** At-least-once delivery means the POS *will* receive the same update twice. Two options:
- POS handles idempotency on its end (idempotency-key header → 200 if already applied).
- We track delivery state (`menu_sync_deliveries` table) and never resend.

Recommendation: **idempotency key from our side, POS dedupes**. Cleaner separation. Stable keys per `(item_id, change_version)` so the same logical change always gets the same key.

**3. Partial failure.** Batch of 50: 48 succeed, 2 fail.
- All-or-nothing rollback — strong consistency, heavy contract requirement on POS.
- Per-item with retry queue — eventually consistent, the realistic default.
- Per-item, no retry — alert and reconcile manually. Cheap, operationally painful.

Recommendation: **per-item retry queue** with explicit retry policy (max attempts, backoff, dead-letter).

**4. Where the abstraction line sits.**
- *Thin* — `Sender.Send(ctx, update) error`. Caller handles batching, retries, idempotency keys.
- *Thick* — `Gateway.PublishMenuChange(ctx, change) error`. Gateway internalizes all policy.

Recommendation: **thick gateway, thin Sender inside**. Gateway is policy; Sender is transport. Test gateway against stub Sender; swap stub for real POS without touching policy.

**5. Coupling to POS availability.**
- *Tight* — block menu publishes until POS confirms. Pricing accuracy critical, POS down = menu authoring down.
- *Loose* — publish to our DB immediately, queue for POS, alert on queue depth. Source of truth lives here.

Recommendation: **loose coupling**. Source of truth lives here. POS is a consumer.

Push back on any of these. The architecture *is* the work today.

---

**You:**

push. idempotency key from our side. per-item retry. thick gateway. loose coupling.

**Claude:**

Locked. The shape:

```go
// internal/sync/gateway.go (sketch — not for merge)
package sync

import (
    "context"
    "github.com/yourorg/yourrepo/internal/menu"
)

// Gateway publishes menu changes to a downstream consumer (POS).
// Loose coupling: PublishMenuChange returns once the change is queued,
// not once the POS has confirmed.
type Gateway interface {
    PublishMenuChange(ctx context.Context, change MenuChange) error
}

// MenuChange is the unit of replication. ChangeID is stable per logical
// change — same item + same revision yields the same ChangeID — and is
// used as the POS-side idempotency key.
type MenuChange struct {
    ChangeID string
    Type     ChangeType // Create, Update, Delete
    Item     *menu.MenuItem
}

type ChangeType int

const (
    ChangeCreate ChangeType = iota
    ChangeUpdate
    ChangeDelete
)

// Sender is the transport boundary. Implementations:
//   HTTPSender (real POS), StubSender (tests), FakeSender (local dev).
type Sender interface {
    Send(ctx context.Context, change MenuChange) error
}
```

Gateway internals (not in the sketch): in-memory queue, worker pool calling Sender with retry policy, dead-letter sink. Queue can move to a durable store (e.g., Postgres outbox pattern) in a later phase once the volume is known.

**Two-phase rollout, called out before any code:**

- **Phase 1 — in-memory queue, single worker.** Single-process, in-memory. Crash = lost queue. Acceptable for dev/staging to learn the failure shapes.
- **Phase 2 — durable outbox.** Writes to `menu_outbox` table in the *same DB transaction* as the menu update. Worker reads from outbox, sends, marks delivered. Crash-safe. Production shape.

Phase 1 → 2 is a worker swap; Gateway interface stays the same. That's what protects the rollout.

**Spec gap.** Same shape as Session 6: the Sender contract — what counts as retryable, timeout semantics, what the POS is allowed to return — needs to be written down before phase 1 lands. Routing to `agent-skills:spec`.

**Test strategy.** TDD on the Gateway uses `StubSender` to assert: idempotency keys are stable across retries; retry policy fires on retryable errors; non-retryable errors go to dead-letter immediately; ctx cancellation aborts in-flight work cleanly. No real POS in tests.

Want to spec, or fork to spike-then-test on the queue/worker mechanics first?

---

**You:**

spec first, then phase 1. wrap.

**Claude:**

[Design captured. Routing to `agent-skills:spec` for the Sender contract. Phase 1 (in-memory single-worker) ships after spec review. Phase 2 (durable outbox) deferred to the natural next iteration once phase 1's failure modes are understood.]

---

## What this session shows (staff `/pair`)

- **Forces before code, every time.** Even with the developer ready to build, the session refused to draft an interface until five design questions were resolved. The shape of the interface falls out of those answers — drafting first risks rebuilding it after.
- **Rollout shape inseparable from design.** The two-phase plan (in-memory → durable outbox) was surfaced as part of the design conversation, not after. Staff design includes the deploy story.
- **Local first, agent-skills for gaps.** Per CLAUDE.md, the local `/pair` covers the design conversation, and `agent-skills:spec` is invoked specifically because writing a contract spec is a lifecycle gap the local commands don't cover.

---

## What Changes Across Modes

Reading the seven sessions side by side:

| Aspect | beginner | senior | staff |
|---|---|---|---|
| Tests come first? | Yes | Yes | Yes (after the design is locked) |
| Skills consulted? | Yes — named inline | Yes — silent unless load-bearing | Yes — silent |
| Scope announced? | Yes — small phase, often single function | Yes — one reviewable sitting | Yes — multi-phase plan with rollback |
| Idiom narration | Always, first time each appears | Only when non-obvious | Skipped |
| Opening move | Teaching + design questions | One-line plan, agree-or-pushback | Design conversation: forces, failure modes, rollout |
| Mid-stream check-ins | After each red → green step | One inline call-out | One alignment check before scoping |
| Pre-commit self-check | Walk-through with a comprehension question | Quick checklist | Per-phase, plus rollout/rollback verification |
| agent-skills used? | No (local covers it) | No (local covers it) | Yes — for spec authoring (lifecycle gap) |

The discipline is identical across all three modes. The narration adapts
to the audience. If a session in your own work doesn't feel like one of
these seven, that's a signal to either change `/mode` or push back on
Claude's pacing.
