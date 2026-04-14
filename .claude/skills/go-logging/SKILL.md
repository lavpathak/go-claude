---
name: go-logging
description: Go structured logging with log/slog — key-value pairs not sprintf, log levels Debug/Info/Warn/Error, logger injection via constructor (no globals), log-or-return rule, PII/secret redaction, correlation via context, child loggers with slog.With. Load whenever logging is added or events/errors are recorded.
---

# Skill: Go Logging

> Claude reads this skill whenever logs are written, logger dependencies are
> wired, or log output is discussed. Follow these patterns exactly.

---

## Core Rule

**Logs are structured key-value events, not human sentences. Loggers are
injected dependencies, not package globals. You either log an error OR return
it — never both.**

Use `log/slog` (stdlib, Go 1.21+). Do not use `log`, `fmt.Println`, or third-party
loggers unless explicitly approved.

---

## Pattern 1: Structured Key-Value Pairs

```go
// ❌ BAD — string formatting hides fields from log aggregators
log.Printf("user %s placed order %s worth %d cents", userID, orderID, amount)

// ❌ BAD — sprintf-style inside slog
logger.Info(fmt.Sprintf("user %s placed order %s", userID, orderID))

// ✅ GOOD — message is static, values are attributes
logger.Info("order placed",
    "user_id", userID,
    "order_id", orderID,
    "amount_cents", amount,
)
```

**Teaching point**: Log aggregators (Datadog, Loki, CloudWatch) index by field.
`"user_id=alice"` is searchable; `"user alice placed..."` is a string blob. Use
snake_case for keys so they match typical log schema conventions.

---

## Pattern 2: Log Levels

| Level | Use for | Example |
|---|---|---|
| `Debug` | Developer diagnostics, off in production | query SQL, feature-flag decisions |
| `Info`  | Normal operations worth recording | request received, job completed |
| `Warn`  | Something unexpected but recoverable | retry triggered, fallback used |
| `Error` | A failure that needs human attention | DB unreachable, dependency down |

```go
logger.Debug("cache miss", "key", key)
logger.Info("request completed", "method", r.Method, "status", status, "duration", d)
logger.Warn("retrying after failure", "attempt", n, "error", err)
logger.Error("failed to deliver notification", "user_id", userID, "error", err)
```

**Teaching point**: `Info` is the default. Reach for `Warn` only when a human
might want to know. Reach for `Error` only when a human must know. If you're
logging `Error` for things that happen 1,000x/sec, it's not an error — it's a metric.

---

## Pattern 3: Inject the Logger — No Globals

```go
// ✅ GOOD — logger is an explicit dependency
type Service struct {
    store  UserStore
    logger *slog.Logger
}

func NewService(store UserStore, logger *slog.Logger) *Service {
    return &Service{store: store, logger: logger}
}

// ❌ BAD — slog.Default() hides the dependency, breaks tests
func (s *Service) GetUser(ctx context.Context, id string) (User, error) {
    slog.Default().Info("fetching user", "id", id)  // no way to inject a test logger
    return s.store.GetUser(ctx, id)
}
```

**Teaching point**: A logger is a dependency like any other. Tests should be
able to substitute a discard logger (`slog.New(slog.NewTextHandler(io.Discard, nil))`)
to keep test output clean. You cannot do that if the service calls `slog.Default()` directly.

---

## Pattern 4: Log OR Return — Never Both

```go
// ❌ BAD — this error will be logged at every layer of the stack
func (s *Service) Charge(ctx context.Context, orderID string) error {
    if err := s.payments.Charge(ctx, orderID); err != nil {
        s.logger.Error("charge failed", "order_id", orderID, "error", err)
        return fmt.Errorf("charging order: %w", err)  // caller will log it again
    }
    return nil
}

// ✅ GOOD — return the error with context, let the top of the stack log it once
func (s *Service) Charge(ctx context.Context, orderID string) error {
    if err := s.payments.Charge(ctx, orderID); err != nil {
        return fmt.Errorf("charging order %s: %w", orderID, err)
    }
    return nil
}

// The HTTP handler (top of the stack) is where logging happens
func (h *Handler) handleCharge(w http.ResponseWriter, r *http.Request) {
    if err := h.service.Charge(r.Context(), orderID); err != nil {
        h.logger.Error("charge request failed",
            "order_id", orderID,
            "error", err,  // full wrapped chain included
        )
        h.respondError(w, "charge failed", http.StatusInternalServerError)
        return
    }
}
```

**Teaching point**: Duplicate log lines in production are worse than missing
logs — they confuse incident debugging and inflate log bills. Pick one place
to log: the boundary where the error leaves your process (HTTP handler,
CLI main, worker loop). Every other layer wraps with context and returns.

---

## Pattern 5: Child Loggers with slog.With

Attach persistent fields to a logger so every subsequent call carries them.

```go
// Create a logger scoped to a request or operation
func (h *Handler) handleCreateOrder(w http.ResponseWriter, r *http.Request) {
    reqID, _ := RequestIDFrom(r.Context())
    logger := h.logger.With(
        "request_id", reqID,
        "method", r.Method,
        "path", r.URL.Path,
    )

    // Every log below automatically includes those fields
    logger.Info("creating order")
    // ... work ...
    logger.Info("order created", "order_id", order.ID)
}
```

**Teaching point**: `With` returns a NEW logger; the parent is unchanged. Use
this at the start of a request or long-running operation to avoid repeating
the same fields on every `Info` call.

---

## Pattern 6: Correlation IDs via Context

```go
// Middleware attaches a request ID to the context
func RequestIDMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        id := r.Header.Get("X-Request-ID")
        if id == "" {
            id = uuid.New().String()
        }
        ctx := WithRequestID(r.Context(), id)
        w.Header().Set("X-Request-ID", id)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

// A helper to build a request-scoped logger from ctx
func loggerFrom(ctx context.Context, base *slog.Logger) *slog.Logger {
    if id, ok := RequestIDFrom(ctx); ok {
        return base.With("request_id", id)
    }
    return base
}
```

See `go-context/SKILL.md` for the typed-key pattern used by `WithRequestID`.

---

## Pattern 7: What NOT to Log

```go
// ❌ NEVER log these, even at Debug
logger.Info("login attempt", "password", input.Password)       // credential
logger.Info("token issued",  "jwt", token)                     // auth token
logger.Info("payment",       "card_number", card.Number)       // PAN
logger.Info("user",          "ssn", user.SSN)                  // PII
logger.Info("headers",       "headers", r.Header)              // may contain Authorization

// ✅ Log the SHAPE, not the value
logger.Info("login attempt", "user_id", userID, "ip", r.RemoteAddr)
logger.Info("token issued",  "user_id", userID, "token_prefix", token[:8])
logger.Info("payment",       "user_id", userID, "card_last4", card.Last4)
```

**Teaching point**: Logs are often replicated across storage tiers, sent to
third-party aggregators, and visible to more people than you think. Treat log
output as effectively public. A redaction bug costs a SOC-2 finding at minimum.

---

## Pattern 8: Handler Setup in main

```go
func main() {
    cfg := loadConfig()

    // Text handler for local dev (readable), JSON for production (parseable)
    var handler slog.Handler
    if cfg.Env == "local" {
        handler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
            Level: slog.LevelDebug,
        })
    } else {
        handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
            Level: cfg.LogLevel,  // parsed from env: info | warn | error
        })
    }

    logger := slog.New(handler).With(
        "service", "myservice",
        "version", buildVersion,
    )

    // Pass logger to every constructor that needs it
    userStore := user.NewPostgresStore(db)
    userService := user.NewService(userStore, logger)
    // ...
}
```

---

## Anti-Patterns to Flag

```go
// ❌ fmt.Println anywhere outside a CLI tool's stdout contract
fmt.Println("got here")

// ❌ log.Printf (stdlib log package) — not structured
log.Printf("user=%s action=%s", userID, action)

// ❌ Using slog.Default() in library code
slog.Info("something happened")  // can't be replaced in tests

// ❌ Logging inside tight loops without a reason
for _, item := range millionItems {
    logger.Info("processing", "id", item.ID)  // floods logs, tanks performance
}

// ❌ Logging the same error at multiple layers
// (see Pattern 4)

// ❌ Using message for variable data
logger.Info(fmt.Sprintf("processed %d items", count))
// ✅ logger.Info("processing complete", "count", count)

// ❌ Logging errors without context about what failed
logger.Error("error", "error", err)
// ✅ logger.Error("charging order failed", "order_id", id, "error", err)
```

---

## Testing with a Logger

```go
// Discard logger for unit tests — keeps test output clean
func newTestLogger() *slog.Logger {
    return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestService_GetUser(t *testing.T) {
    store := &StubUserStore{...}
    svc := NewService(store, newTestLogger())
    // ...
}

// If a test NEEDS to assert on log output, capture it:
func TestService_LogsOnFailure(t *testing.T) {
    var buf bytes.Buffer
    logger := slog.New(slog.NewJSONHandler(&buf, nil))
    svc := NewService(&FailingStub{}, logger)

    _ = svc.DoWork(context.Background())

    if !strings.Contains(buf.String(), `"level":"ERROR"`) {
        t.Errorf("expected an ERROR log, got: %s", buf.String())
    }
}
```

---

## Teaching Progression

1. **Week 1**: `logger.Info("thing happened", "key", value)` — nothing else. Ban
   `fmt.Println`. Show how fields appear in the handler output.
2. **Week 2**: Inject the logger in constructors; stop using `slog.Default()`.
3. **Month 2**: Log levels and the "log OR return" rule for error paths.
4. **Month 3**: `slog.With` for per-request child loggers; correlation IDs via ctx.
5. **Later**: Custom handlers, log sampling, what to test about logs.
