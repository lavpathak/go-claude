# Example Sessions

> Three full session transcripts — one per engineer mode — showing what
> a real working session in this repo actually feels like.

These are not scripts. They are representative of how a session unfolds
when the rules in this repo are honored. Treat them as a calibration
target for what Claude should sound like at each mode.

---

## How to Read These

Each session below is a transcript: the developer's input (`You:`) and
Claude's response (`Claude:`), turn by turn.

**Identical across all three modes:**
- The Three Laws (match the mode, announce scope, tests first).
- The same Go skills under `.claude/skills/go-*` are consulted.
- The same guardrails apply (5-file cap, conventional commits, hooks).
- The pre-commit self-check runs before code is handed back.

**Different across modes:**
- **Pacing** — how often Claude checks in mid-task.
- **Idiom narration** — how much Go is explained inline.
- **Scope per task** — small phases vs. one reviewable sitting vs.
  multi-phase plan.
- **Where the conversation opens** — teaching vs. plan vs. design.

---

## Session 1 — `beginner`

**Scenario:** Add an email-validation function to the existing
`internal/user` package. The developer is new to Go.

```
You:     /pair Add email validation to the user package.

Claude:  Mode: beginner. Before we open any file, two design choices
         worth making up front:

         1. Regex vs. net/mail.ParseAddress.
            Regex looks tempting, but RFC 5322 is famously gnarly —
            our team uses net/mail.ParseAddress from stdlib because
            it follows the actual spec. Less surface area for bugs.

         2. What should the function return on failure?
            Two options: a bool, or an error. Errors are richer —
            callers can wrap them and log them with context. Our
            go-error-handling/SKILL.md prefers errors for anything
            that can fail in more than one way.

         Sound good with net/mail + error return?

You:     Yeah that works.

Claude:  Good. Scope I'm proposing (2 files, well under the 5-file cap):

         - internal/user/validation.go         (new — ValidateEmail)
         - internal/user/validation_test.go    (new — its tests)

         We'll run /tdd here. First a failing test, then the smallest
         code that makes it pass. Ready?

You:     Go.

Claude:  Here's our first test case. I'm using a table-driven test
         because that's the team standard (go-testing/SKILL.md) — even
         with one case today, the structure is ready for more tomorrow.

         // internal/user/validation_test.go
         package user

         import "testing"

         func TestValidateEmail(t *testing.T) {
             tests := []struct {
                 name    string
                 email   string
                 wantErr bool
             }{
                 {
                     name:    "valid simple address",
                     email:   "alice@example.com",
                     wantErr: false,
                 },
             }

             for _, tc := range tests {
                 t.Run(tc.name, func(t *testing.T) {
                     err := ValidateEmail(tc.email)
                     if (err != nil) != tc.wantErr {
                         t.Errorf("ValidateEmail(%q) error = %v, wantErr %v",
                             tc.email, err, tc.wantErr)
                     }
                 })
             }
         }

         Running: go test -v -run TestValidateEmail ./internal/user/...
         ❌ FAIL — undefined: ValidateEmail.

         That's RED. What's the smallest code that makes this pass?
         Hint: it doesn't need to actually validate anything yet.

You:     A function that just returns nil?

Claude:  Exactly. The simplest possible thing:

         // internal/user/validation.go
         package user

         // ValidateEmail returns nil if email is a valid RFC 5322
         // address, or a non-nil error describing why it isn't.
         func ValidateEmail(email string) error {
             return nil
         }

         go test -v -run TestValidateEmail ./internal/user/...
         ✅ PASS

         GREEN. Now we add a failing case to force a real implementation.

         Add this to the tests slice:

         {
             name:    "missing @ sign",
             email:   "alice.example.com",
             wantErr: true,
         },

         Re-run. ❌ FAIL — our function returns nil for an invalid email.
         Back to RED. Now we implement for real:

         import (
             "errors"
             "fmt"
             "net/mail"
         )

         var ErrInvalidEmail = errors.New("invalid email")

         func ValidateEmail(email string) error {
             if _, err := mail.ParseAddress(email); err != nil {
                 return fmt.Errorf("%w: %v", ErrInvalidEmail, err)
             }
             return nil
         }

         Two Go idioms worth pausing on, because you'll see them
         everywhere in this codebase:

         - `var ErrInvalidEmail = errors.New(...)` is a *sentinel
           error*. Callers can check `errors.Is(err, ErrInvalidEmail)`
           without pattern-matching the message string. That's the
           pattern from go-error-handling/SKILL.md.

         - `fmt.Errorf("%w: %v", ...)` — the `%w` verb wraps the
           original error so it stays in the chain. `%v` is plain
           formatting. Wrapping with `%w` is what makes `errors.Is`
           work across boundaries.

         ✅ Both cases pass. Let's add one more — an empty string —
         to make sure we handle the zero value:

         {name: "empty string", email: "", wantErr: true},

         ✅ PASS. Pre-commit self-check before I hand this back:

         - [x] Scope announced (2 files, matches what we agreed)
         - [x] New function has a test
         - [x] Errors handled with sentinel + wrap pattern
         - [x] Exported identifiers have doc comments
         - [x] go vet clean, golangci-lint clean
         - [x] You can explain what the code does

         Quick check on that last one — what does `errors.Is(err,
         ErrInvalidEmail)` return for the "missing @ sign" case,
         and why?

You:     True, because of the %w wrap?

Claude:  Exactly right. The %w keeps ErrInvalidEmail in the chain,
         and errors.Is walks the chain looking for a match. Ship it
         when you're ready — suggested commit message:

         feat(user): add ValidateEmail with sentinel-error reporting
```

---

## Session 2 — `senior`

**Scenario:** Add retry-with-backoff to an outbound webhook client.
The developer ships features end-to-end.

```
You:     Add retry-with-backoff to the webhook client.

Claude:  Plan:
         - Up to 5 attempts. Exponential backoff: 100ms base, ×2 each.
           Full jitter on every sleep, ctx-aware.
         - Retry on 5xx responses and net.Error timeouts.
         - 4xx fails fast (non-retryable).
         - Wrap the exhausted-retries error with the last underlying
           error so callers can errors.Is/As against it.
         - 3 files: internal/webhook/retry.go (new), retry_test.go
           (new), client.go (call sites).

         Push back if you want jittered-equal instead of full jitter,
         or different retry-eligibility rules.

You:     Looks good. Go.

Claude:  Failing test first.

         // internal/webhook/retry_test.go
         func TestDoWithRetry(t *testing.T) {
             tests := []struct {
                 name      string
                 statuses  []int // status returned on each attempt
                 wantCalls int
                 wantErrIs error
             }{
                 {
                     name:      "succeeds on first try",
                     statuses:  []int{200},
                     wantCalls: 1,
                 },
                 {
                     name:      "retries 5xx then succeeds",
                     statuses:  []int{503, 503, 200},
                     wantCalls: 3,
                 },
                 {
                     name:      "fails fast on 4xx",
                     statuses:  []int{404},
                     wantCalls: 1,
                     wantErrIs: ErrNonRetryable,
                 },
                 {
                     name:      "exhausts retries",
                     statuses:  []int{500, 500, 500, 500, 500},
                     wantCalls: 5,
                     wantErrIs: ErrRetriesExhausted,
                 },
             }
             // ... t.Run loop with a stub RoundTripper that returns
             //     the canned statuses in order ...
         }

         go test -race ./internal/webhook/...
         ❌ FAIL — undefined: DoWithRetry, ErrNonRetryable,
         ErrRetriesExhausted.

         Implementation:

         var (
             ErrNonRetryable     = errors.New("non-retryable response")
             ErrRetriesExhausted = errors.New("retries exhausted")
         )

         const (
             maxAttempts = 5
             baseDelay   = 100 * time.Millisecond
         )

         func DoWithRetry(
             ctx context.Context,
             do func(context.Context) (*http.Response, error),
         ) (*http.Response, error) {
             var lastErr error
             for attempt := 0; attempt < maxAttempts; attempt++ {
                 resp, err := do(ctx)
                 switch {
                 case err == nil && resp.StatusCode < 500:
                     if resp.StatusCode >= 400 {
                         return resp, fmt.Errorf("%w: %d",
                             ErrNonRetryable, resp.StatusCode)
                     }
                     return resp, nil
                 case err == nil:
                     lastErr = fmt.Errorf("status %d", resp.StatusCode)
                     resp.Body.Close()
                 default:
                     lastErr = err
                 }
                 if attempt == maxAttempts-1 {
                     break
                 }
                 if err := sleepWithJitter(ctx, attempt); err != nil {
                     return nil, err
                 }
             }
             return nil, fmt.Errorf("%w: %v", ErrRetriesExhausted, lastErr)
         }

         func sleepWithJitter(ctx context.Context, attempt int) error {
             max := baseDelay * (1 << attempt)
             d := time.Duration(rand.Int63n(int64(max)))
             t := time.NewTimer(d)
             defer t.Stop()
             select {
             case <-ctx.Done():
                 return ctx.Err()
             case <-t.C:
                 return nil
             }
         }

         ✅ All four cases pass, -race clean.

         One non-obvious choice worth flagging: full jitter (random
         0..backoff) rather than equal jitter (backoff/2 + random
         0..backoff/2). At our outbound volume the difference is
         imperceptible, but full jitter is strictly better for
         thundering-herd behavior the moment this runs in more than
         one pod. No downside today, future-proof.

         client.go wired up. make check passes.

         /review on the diff —

         🟡 Should fix: when ctx is cancelled mid-sleep, we return
            ctx.Err() raw. Callers using errors.Is(err,
            ErrRetriesExhausted) won't catch that path. That's
            probably intentional (cancellation is its own concept)
            but worth a doc note on DoWithRetry so the boundary is
            explicit.
         🟢 Nice: jitter math is correct and ctx-aware.

         Want me to add the doc note?

You:     Yes.

Claude:  Done. DoWithRetry's doc comment now reads:

         // DoWithRetry calls do with exponential-backoff retries on
         // 5xx and transport errors, up to maxAttempts. Returns
         // ErrNonRetryable for 4xx responses and ErrRetriesExhausted
         // after the final failure. If ctx is cancelled during a
         // backoff sleep, the cancellation error is returned directly
         // (it does not wrap ErrRetriesExhausted).

         Pre-commit self-check:
         - [x] Scope held to 3 files as announced
         - [x] go vet, golangci-lint, go test -race all clean
         - [x] Every error wrapped or returned; no `_ =` on errors
         - [x] Reviewable in one sitting

         Suggested commit:

         feat(webhook): add ctx-aware retry with full-jitter backoff
```

---

## Session 3 — `staff`

**Scenario:** Add OpenTelemetry tracing across the HTTP layer. This is a
multi-quarter initiative, not a single change.

```
You:     We need to add OpenTelemetry tracing across the API.

Claude:  Before any code — this is an observability initiative spanning
         multiple phases. The decisions to pin down first, because each
         one constrains everything that follows:

         1. Sampling strategy.
            Head sampling (decide at request entry) is cheap and what
            most teams ship first. Tail sampling (decide after the
            trace is observed) gives much better signal-to-cost
            ratio — you keep 100% of errors and 1% of successes —
            but needs a stateful collector and more infra cost. My
            recommendation: head-sample at 1% globally, with a
            forced-keep on any span that records an error. Migrate
            to tail later if we outgrow it. That decision is
            reversible at the collector layer.

         2. Vendor neutrality.
            Lock-in matters. We depend on the OTel SDK API only and
            route through an exporter interface we own. "Switch
            from Tempo to Honeycomb to Datadog" becomes a config
            change, not a code rewrite. We don't have a local
            command for spec authoring, so this is the right
            lifecycle gap for agent-skills:spec — we want this
            interface contract in writing before we build against it.

         3. Propagation.
            W3C traceparent on every outbound HTTP, extract on every
            inbound. Risk: any handler that forgets to propagate
            becomes a trace black hole. Mitigation: wrap http.Client
            at the composition root so propagation is the default,
            not opt-in per call site.

         4. Failure mode: collector down.
            Tracing MUST fail open. We never block a request on an
            observability concern. SDK defaults are fine here, but I
            want this written into the spec so it can't drift.

         5. Rollout.
            Per-route feature flag, env-driven. Roll out to /health
            first (cheapest span possible), then one real endpoint
            at 1% sampling, watch collector cost for a week, then
            expand. Rollback is "set env var to false." The
            middleware checks at request time, not init time, so
            the flag is hot-swappable.

         6. Where to instrument.
            HTTP mux middleware: yes. Outbound HTTP: yes. DB layer:
            yes but one span per transaction, not per query — span
            explosion is the most common foot-gun. Internal function
            calls: no.

         I need answers on 1, 2, and 4 before drafting anything.
         The rest follow from those three.

You:     1: head sample 1% with error keep, agreed.
         2: vendor-neutral interface. Run agent-skills:spec for it.
         4: fail open, agreed.

Claude:  Phase plan via /scope:

         📋 Initiative: OpenTelemetry tracing
         Total phases: 5

         Phase 1 — SDK init + exporter interface
           internal/observability/tracing.go (new)
           internal/observability/tracing_test.go (new)
           cmd/api/main.go (wire the init at composition root)
           Deliverable: tracer provider set up at startup; no-op
           exporter in tests; OTLP exporter in prod; fail-open if
           collector unreachable.

         Phase 2 — HTTP mux middleware
           internal/middleware/tracing.go (new)
           internal/middleware/tracing_test.go (new)
           cmd/api/routes.go (wrap mux)
           Deliverable: every inbound request produces a root span;
           name follows "{method} {route_pattern}"; error responses
           promote to span error status.

         Phase 3 — Outbound http.Client instrumentation
           internal/http/client.go (modify)
           internal/http/client_test.go (modify)
           Deliverable: trace context injected via traceparent;
           outbound spans nest under inbound spans.

         Phase 4 — DB transaction spans
           internal/db/tracing.go (new)
           internal/db/tracing_test.go (new)
           Deliverable: one span per transaction; query attributes
           recorded with parameter values redacted.

         Phase 5 — Sampling tuning + alerting
           Configuration only — alerts on collector lag and span
           drop rate.

         Rollback plan, every phase: OTEL_TRACING_ENABLED=false.
         Each phase ships independently, dark-launched behind the
         flag, then enabled. Phase N never blocks on phase N+1.

         Before /tdd on Phase 1, the right next move is the spec.
         I'll route to agent-skills:spec — local commands cover
         building and testing well, but spec authoring is the
         lifecycle gap the agent-skills partition is designed for.

         The spec will cover, at minimum:
           - The exporter interface and its contract (Shutdown,
             ForceFlush, ExportSpans semantics).
           - The init function's signature and failure mode
             (fail-open: log + continue with a no-op tracer).
           - The env-config surface (OTEL_TRACING_ENABLED,
             OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME).
           - The contract our future Tempo/Honeycomb/Datadog
             adapters must satisfy.

         Ready for me to route to agent-skills:spec for that draft?

You:     Yes.

Claude:  Handing off to agent-skills:spec. I'll bring the spec back
         here for your review before any code is written. Once it's
         approved, the next step is /tdd on the exporter interface
         in tracing_test.go. The interface comes first; the OTel
         SDK plumbing comes second. That ordering is what protects
         vendor neutrality — if we plumb SDK types into the rest of
         the codebase, the interface becomes ornamental.
```

---

## What's the Same vs. What Changes

Reading the three sessions side by side:

| Aspect | beginner | senior | staff |
|---|---|---|---|
| Tests come first? | Yes | Yes | Yes (after the design is locked) |
| Skills consulted? | Yes — named inline | Yes — silent unless non-obvious | Yes — silent |
| Scope announced? | Yes — small phase | Yes — one sitting | Yes — multi-phase plan |
| Idiom narration | Always, first time each appears | Only when non-obvious | Skipped |
| Opening move | Teaching + design Q's | One-line plan, agree-or-pushback | Design conversation: failure modes, blast radius, rollout |
| Mid-stream check-ins | After each red→green step | One inline call-out | One alignment check before /scope |
| Scope per task | Small, often one function | One reviewable sitting | Phase plan, multi-sitting |
| agent-skills used? | No (local covers it) | No (local covers it) | Yes — for spec authoring (lifecycle gap) |
| Pre-commit self-check | Walk-through with a comprehension question | Quick checklist | Per-phase, plus rollout/rollback verification |

The discipline is identical across all three modes. The narration adapts
to the audience. If a session in your own work doesn't feel like one of
these three, that's a signal to either change `/mode` or push back on
Claude's pacing.
