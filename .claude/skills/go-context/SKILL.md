---
name: go-context
description: Go context.Context patterns — first-param convention, propagation through call chains, WithTimeout/WithDeadline/WithCancel with deferred cancel, WithValue with typed keys, Background vs TODO, respecting cancellation in long operations. Load whenever context.Context is created, derived, or passed.
---

# Skill: Go Context

> Claude reads this skill whenever `context.Context` is created, derived,
> propagated, or used for cancellation/deadlines/values. Follow these patterns exactly.

---

## Core Rule

**Context is a cancellation signal and deadline carrier that flows through every
I/O-bound call. Pass it — never store it.**

A `context.Context` tells a function: "here's how long you have, and how to know
if the caller gave up." Every function that does I/O, or calls one that does,
must accept a context as its first parameter.

---

## Pattern 1: First Parameter, Always Named `ctx`

```go
// ✅ GOOD — ctx is first, named ctx, not stored
func (s *Service) GetUser(ctx context.Context, id string) (User, error) {
    return s.store.GetUser(ctx, id)  // propagate, don't swallow
}

// ❌ BAD — ctx not first
func (s *Service) GetUser(id string, ctx context.Context) (User, error) { ... }

// ❌ BAD — ctx stored in struct
type Service struct {
    ctx context.Context  // DON'T. A struct survives multiple calls; ctx belongs to one call.
    store UserStore
}

// ❌ BAD — context dropped
func (s *Service) GetUser(ctx context.Context, id string) (User, error) {
    return s.store.GetUser(context.Background(), id)  // caller's cancellation is ignored
}
```

**Teaching point**: `ctx` is per-call, not per-object. If the caller cancels
their request, everything they started should stop. Storing `ctx` in a struct
breaks that chain because the struct outlives the call.

**Exception**: long-running background workers (e.g. a consumer goroutine)
may hold a context derived from `main`'s context. Document why.

---

## Pattern 2: Background vs TODO vs Derived

```go
// context.Background() — the root. Use ONLY in:
//   - main()
//   - test setup
//   - long-running background tasks started at startup
func main() {
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
    defer stop()
    runServer(ctx)
}

// context.TODO() — placeholder when you don't have a ctx yet but will soon.
// Use when refactoring code to accept ctx, as a temporary marker.
func legacyCode() {
    result, err := someNewAPI(context.TODO(), input)  // FIXME: thread real ctx
    _ = result; _ = err
}

// Derived context — everything else. Pass the caller's ctx, derive from it if needed.
func (s *Service) FetchAll(ctx context.Context) error {
    ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()
    return s.doFetch(ctx)
}
```

**Teaching point**: Seeing `context.Background()` or `context.TODO()` outside
`main`/tests is a red flag — it means a cancellation chain got cut. During review,
grep for these and ask "why isn't this derived from a caller's ctx?"

---

## Pattern 3: WithTimeout / WithDeadline / WithCancel — Always defer cancel()

```go
// WithTimeout — "give up after 5 seconds"
func (s *Service) CallExternalAPI(ctx context.Context) (Response, error) {
    ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
    defer cancel()  // ALWAYS defer cancel, even on the timeout path

    return s.http.Do(ctx, req)
}

// WithDeadline — "give up at this exact time"
func (s *Service) ProcessBefore(ctx context.Context, deadline time.Time) error {
    ctx, cancel := context.WithDeadline(ctx, deadline)
    defer cancel()
    return s.doWork(ctx)
}

// WithCancel — manual cancellation trigger
func (s *Service) StreamUntilError(ctx context.Context) error {
    ctx, cancel := context.WithCancel(ctx)
    defer cancel()

    go func() {
        if err := s.watcher.Watch(ctx); err != nil {
            cancel()  // trigger cancellation on watcher failure
        }
    }()

    return s.consume(ctx)
}
```

**Teaching point**: `cancel` releases resources associated with the derived context.
Not calling it leaks memory and, more importantly, leaks the goroutine tracking the
deadline. `go vet` warns on missing `cancel` — take the warning seriously.

---

## Pattern 4: Respect ctx.Done() in Long Operations

```go
// ❌ BAD — tight loop that ignores cancellation
func processAll(ctx context.Context, items []Item) error {
    for _, item := range items {
        if err := process(item); err != nil {  // never checks ctx
            return err
        }
    }
    return nil
}

// ✅ GOOD — check ctx.Done() between units of work
func processAll(ctx context.Context, items []Item) error {
    for _, item := range items {
        select {
        case <-ctx.Done():
            return ctx.Err()  // returns context.Canceled or context.DeadlineExceeded
        default:
        }
        if err := process(ctx, item); err != nil {
            return err
        }
    }
    return nil
}
```

**Teaching point**: Most stdlib I/O already respects `ctx` (HTTP, SQL, file ops
with context variants). You only need to check `ctx.Done()` yourself inside
pure-CPU loops or when integrating with non-context-aware libraries.

---

## Pattern 5: context.WithValue — Request-Scoped, Typed Keys

```go
// ✅ GOOD — typed key prevents collisions across packages
type ctxKey int

const (
    requestIDKey ctxKey = iota
    userIDKey
)

func WithRequestID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, requestIDKey, id)
}

func RequestIDFrom(ctx context.Context) (string, bool) {
    id, ok := ctx.Value(requestIDKey).(string)
    return id, ok
}

// ❌ BAD — string key (collides across packages, shows up in linters)
ctx = context.WithValue(ctx, "request_id", id)
```

**Teaching point**: `context.WithValue` is for **request-scoped** data that
crosses API boundaries and doesn't fit in an explicit parameter — request IDs,
auth subjects, trace spans. It is NOT for:
- Optional function parameters (use function args)
- Dependencies (use constructor injection)
- Configuration (use config struct)

If you can pass it explicitly, pass it explicitly. `WithValue` should feel like
a last resort.

---

## Pattern 6: Don't Pass nil Context

```go
// ❌ BAD — nil ctx will panic when anything derives from it
s.store.GetUser(nil, id)

// ✅ GOOD — use context.TODO() if you truly don't have one
s.store.GetUser(context.TODO(), id)

// ✅ BETTER — thread a real context through
s.store.GetUser(ctx, id)
```

---

## Anti-Patterns to Flag

```go
// ❌ Storing ctx in a struct
type Worker struct { ctx context.Context }

// ❌ Dropping ctx when calling downstream
func (s *Service) Run(ctx context.Context) error {
    return s.worker.Do(context.Background())  // breaks cancellation chain
}

// ❌ Missing defer cancel()
ctx, _ := context.WithTimeout(ctx, 5*time.Second)  // timer leaks

// ❌ String keys for WithValue
ctx = context.WithValue(ctx, "user", u)

// ❌ WithValue for things that should be explicit parameters
ctx = context.WithValue(ctx, "pageSize", 20)  // pass pageSize as an argument

// ❌ Checking ctx.Err() instead of using select for cancellation
for {
    if ctx.Err() != nil { return ctx.Err() }  // busy-loops
    // ... work ...
}
// ✅ Use select with ctx.Done() to block properly
```

---

## Testing with Context

```go
// Most tests can use context.Background()
func TestService_GetUser(t *testing.T) {
    ctx := context.Background()
    svc := NewService(&StubUserStore{...})

    _, err := svc.GetUser(ctx, "user-1")
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
}

// Testing cancellation behavior
func TestService_GetUser_Cancelled(t *testing.T) {
    ctx, cancel := context.WithCancel(context.Background())
    cancel()  // cancel immediately

    svc := NewService(&SlowStub{})
    _, err := svc.GetUser(ctx, "user-1")
    if !errors.Is(err, context.Canceled) {
        t.Errorf("expected context.Canceled, got %v", err)
    }
}

// Testing timeout behavior — use very short timeouts, not sleeps
func TestService_GetUser_Timeout(t *testing.T) {
    ctx, cancel := context.WithTimeout(context.Background(), 1*time.Millisecond)
    defer cancel()

    svc := NewService(&SlowStub{delay: 100 * time.Millisecond})
    _, err := svc.GetUser(ctx, "user-1")
    if !errors.Is(err, context.DeadlineExceeded) {
        t.Errorf("expected context.DeadlineExceeded, got %v", err)
    }
}
```

---

## Teaching Progression

1. **Week 1**: "Every method takes `ctx context.Context` as the first parameter.
   Pass it through. Don't think about it beyond that."
2. **Week 2**: `context.Background()` in `main` and tests; `r.Context()` in handlers.
3. **Month 2**: `context.WithTimeout` for external calls; `defer cancel()` every time.
4. **Month 3**: `context.WithValue` for request IDs (read the typed-key pattern first).
5. **Later**: `context.WithCancel`, graceful shutdown, `select` on `ctx.Done()`.

Don't teach `WithValue` before the team is comfortable passing `ctx` everywhere —
it's the most misused part of the API.
