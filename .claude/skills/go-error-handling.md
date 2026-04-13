# Skill: Go Error Handling

> Claude reads this skill automatically whenever errors are created, returned,
> wrapped, checked, or discussed. Follow these patterns exactly.

---

## Core Rule

**Every error must be handled. Every error must carry context.**

In Go, errors are values. They are returned, not thrown. This is intentional —
it forces you to think about failure at every step. Never suppress an error
with `_` unless you've explicitly documented why.

---

## Pattern 1: Always Wrap Errors With Context

```go
// ❌ BAD — loses all context about what failed
if err != nil {
    return err
}

// ❌ BAD — creates a new error, breaks error chain
if err != nil {
    return fmt.Errorf("failed to get user")
}

// ✅ GOOD — wraps with context AND preserves the original error
if err != nil {
    return fmt.Errorf("getting user by id %s: %w", id, err)
}
```

**Teaching point**: The `%w` verb wraps the original error so callers can unwrap it
with `errors.Is()` or `errors.As()`. Use `%w` when callers might need to check the
underlying error. Use `%v` (rare) when you intentionally want to hide the underlying error.

**Context format**: Use present participle (gerund) without "failed to" prefix.
The error chain reads naturally: `"creating order: validating items: getting product by sku ABC123: sql: no rows"`.

---

## Pattern 2: Sentinel Errors for Expected Conditions

```go
// Define at package level with var, not const
var (
    ErrNotFound     = errors.New("not found")
    ErrUnauthorized = errors.New("unauthorized")
    ErrConflict     = errors.New("conflict: resource already exists")
)

// Return them directly (no wrapping needed at the source)
func (s *Store) GetUser(ctx context.Context, id string) (User, error) {
    row := s.db.QueryRowContext(ctx, "SELECT ...", id)
    if err := row.Scan(&user); err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return User{}, ErrNotFound  // translate db error to domain error
        }
        return User{}, fmt.Errorf("scanning user row: %w", err)
    }
    return user, nil
}

// Check with errors.Is (works through any wrapping chain)
if errors.Is(err, store.ErrNotFound) {
    http.Error(w, "user not found", http.StatusNotFound)
    return
}
```

**Teaching point**: Sentinel errors are named `Err` + condition. They represent
expected, recoverable situations. Don't create sentinels for programming errors
(those should panic or be caught by tests).

---

## Pattern 3: Custom Error Types for Rich Information

```go
// Define as a struct implementing the error interface
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation: %s %s", e.Field, e.Message)
}

// Return as a pointer
func ValidateUser(u User) error {
    if u.Email == "" {
        return &ValidationError{Field: "email", Message: "is required"}
    }
    return nil
}

// Check with errors.As (extracts the typed error through wrapping)
var valErr *ValidationError
if errors.As(err, &valErr) {
    // Access valErr.Field and valErr.Message
    http.Error(w, valErr.Message, http.StatusBadRequest)
    return
}
```

**Teaching point**: Use `errors.As` (not type assertions) because it traverses
the entire wrap chain. A type assertion only checks the outermost error.

---

## Pattern 4: Error Handling in HTTP Handlers

```go
func (h *Handler) CreateUser(w http.ResponseWriter, r *http.Request) {
    // 1. Parse input
    var input CreateUserInput
    if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
        http.Error(w, "invalid request body", http.StatusBadRequest)
        return  // ALWAYS return after writing an error response
    }

    // 2. Validate
    if err := input.Validate(); err != nil {
        var valErr *ValidationError
        if errors.As(err, &valErr) {
            http.Error(w, valErr.Error(), http.StatusBadRequest)
            return
        }
        http.Error(w, "validation failed", http.StatusBadRequest)
        return
    }

    // 3. Execute business logic
    user, err := h.service.CreateUser(r.Context(), input)
    if err != nil {
        if errors.Is(err, ErrConflict) {
            http.Error(w, "user already exists", http.StatusConflict)
            return
        }
        // Unknown error — log it, return 500, don't leak internals
        h.logger.Error("creating user", "error", err)
        http.Error(w, "internal server error", http.StatusInternalServerError)
        return
    }

    // 4. Success response
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(http.StatusCreated)
    json.NewEncoder(w).Encode(user)
}
```

---

## Pattern 5: Multi-Error Collection

```go
// When validating multiple fields, collect all errors
type Errors []error

func (e *Errors) Add(err error) {
    if err != nil {
        *e = append(*e, err)
    }
}

func (e Errors) Err() error {
    if len(e) == 0 {
        return nil
    }
    return fmt.Errorf("multiple errors: %v", e)  // or use errors.Join in Go 1.20+
}

// Go 1.20+ preferred approach:
func ValidateOrder(o Order) error {
    var errs []error
    if o.CustomerID == "" {
        errs = append(errs, &ValidationError{Field: "customer_id", Message: "is required"})
    }
    if o.Total < 0 {
        errs = append(errs, &ValidationError{Field: "total", Message: "must be non-negative"})
    }
    return errors.Join(errs...)  // returns nil if errs is empty
}
```

---

## Anti-Patterns to Flag in Review

```go
// ❌ Ignoring errors
data, _ := json.Marshal(user)

// ❌ Panic on errors in library/application code
data, err := json.Marshal(user)
if err != nil {
    panic(err)  // only acceptable in main() or test setup
}

// ❌ Logging AND returning (leads to duplicate log entries)
if err != nil {
    log.Error("failed", "error", err)
    return err  // caller will also log this
}

// ❌ Returning a non-nil error with a valid value
if err != nil {
    return defaultUser, err  // caller might use defaultUser incorrectly
}

// ✅ Choose ONE: log it OR return it. Never both.
// Exception: at the top of the call stack (HTTP handler, main), you log AND respond.
```

---

## When Teaching Error Handling

1. Start with the simplest case: function returns error, caller checks
2. Then introduce wrapping: show how context accumulates up the call stack
3. Then sentinel errors: show the pattern with `ErrNotFound`
4. Then custom types: show `ValidationError` with `errors.As`
5. Last: `errors.Join` for multi-error collection

Never introduce all five patterns at once. One per TDD session.
