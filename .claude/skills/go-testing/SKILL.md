---
name: go-testing
description: Go testing patterns — table-driven tests with t.Run subtests, t.Helper, t.Cleanup, stubs via interfaces, testing error conditions with errors.Is/As, httptest for HTTP handlers, t.Parallel gotchas. Load whenever Go test code is written or reviewed.
---

# Skill: Go Testing Patterns

> Claude reads this skill automatically whenever test code is written, reviewed,
> or discussed. Follow these patterns exactly.

---

## Core Rule

**Every test tells a story: given THIS input, when THIS happens, expect THIS result.**

Tests are the team's safety net AND documentation. They should be readable by
someone who has never seen the implementation.

---

## Pattern 1: Table-Driven Tests (Default for Everything)

This is the team's standard test format. Use it for every unit test.

```go
func TestParseAmount(t *testing.T) {
    tests := []struct {
        name    string    // describes the scenario
        input   string    // what we're testing
        want    float64   // expected result
        wantErr bool      // do we expect an error?
    }{
        {
            name:    "valid whole number",
            input:   "42",
            want:    42.0,
            wantErr: false,
        },
        {
            name:    "valid decimal",
            input:   "19.99",
            want:    19.99,
            wantErr: false,
        },
        {
            name:    "empty string returns error",
            input:   "",
            want:    0,
            wantErr: true,
        },
        {
            name:    "negative number returns error",
            input:   "-5",
            want:    0,
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParseAmount(tt.input)

            if (err != nil) != tt.wantErr {
                t.Fatalf("ParseAmount(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
            }
            if got != tt.want {
                t.Errorf("ParseAmount(%q) = %v, want %v", tt.input, got, tt.want)
            }
        })
    }
}
```

**Teaching points when writing table-driven tests**:
- `t.Run` creates a named subtest — you can run one case at a time with
  `go test -run TestParseAmount/empty_string_returns_error`
- `t.Fatalf` stops the current subtest immediately (use for errors that make
  further checks meaningless)
- `t.Errorf` records a failure but continues (use when you want to see all failures)
- Name the struct fields clearly — `input`, `want`, `wantErr` is the convention
- Add test cases ONE AT A TIME during TDD

---

## Pattern 2: Test Helpers

Use helpers for repeated setup. Mark them with `t.Helper()`.

```go
// t.Helper() makes error messages point to the caller, not the helper
func createTestUser(t *testing.T) User {
    t.Helper()
    return User{
        ID:    "test-123",
        Email: "test@example.com",
        Name:  "Test User",
    }
}

// For setup that can fail, return an error or use t.Fatal
func setupTestDB(t *testing.T) *sql.DB {
    t.Helper()
    db, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        t.Fatalf("opening test db: %v", err)
    }
    t.Cleanup(func() {
        db.Close()
    })
    return db
}
```

**Teaching point**: `t.Cleanup` registers a function that runs when the test
finishes (like `defer` but for the test lifecycle). Use it for closing connections,
removing temp files, and rolling back state.

---

## Pattern 3: Testing with Interfaces (Dependency Injection)

This is how the team tests code that depends on external systems.

```go
// Step 1: Define the interface where it's USED (not where it's implemented)
// This lives in the package that needs the dependency.
type UserStore interface {
    GetUser(ctx context.Context, id string) (User, error)
    CreateUser(ctx context.Context, user User) error
}

// Step 2: The real implementation satisfies the interface
type PostgresUserStore struct { db *sql.DB }

func (s *PostgresUserStore) GetUser(ctx context.Context, id string) (User, error) {
    // real database call
}

// Step 3: The test double also satisfies the interface
type StubUserStore struct {
    users    map[string]User
    createFn func(User) error  // optional: control behavior per test
}

func (s *StubUserStore) GetUser(_ context.Context, id string) (User, error) {
    u, ok := s.users[id]
    if !ok {
        return User{}, ErrNotFound
    }
    return u, nil
}

func (s *StubUserStore) CreateUser(_ context.Context, user User) error {
    if s.createFn != nil {
        return s.createFn(user)
    }
    s.users[user.ID] = user
    return nil
}

// Step 4: Use the stub in tests
func TestUserService_GetProfile(t *testing.T) {
    store := &StubUserStore{
        users: map[string]User{
            "user-1": {ID: "user-1", Name: "Alice", Email: "alice@test.com"},
        },
    }
    svc := NewUserService(store)

    profile, err := svc.GetProfile(context.Background(), "user-1")
    if err != nil {
        t.Fatalf("unexpected error: %v", err)
    }
    if profile.Name != "Alice" {
        t.Errorf("got name %q, want %q", profile.Name, "Alice")
    }
}
```

**Teaching point**: Go interfaces are satisfied implicitly — no `implements` keyword.
If your stub has the right methods, it satisfies the interface automatically.
Define interfaces where they're consumed, not where they're implemented.

---

## Pattern 4: Testing Error Conditions

```go
func TestUserService_GetProfile_NotFound(t *testing.T) {
    store := &StubUserStore{
        users: map[string]User{},  // empty — nothing to find
    }
    svc := NewUserService(store)

    _, err := svc.GetProfile(context.Background(), "nonexistent")
    if err == nil {
        t.Fatal("expected error, got nil")
    }
    if !errors.Is(err, ErrNotFound) {
        t.Errorf("expected ErrNotFound, got: %v", err)
    }
}

// Testing that a specific error type is returned
func TestValidateUser_MissingEmail(t *testing.T) {
    user := User{Name: "Alice"}  // no email

    err := ValidateUser(user)

    var valErr *ValidationError
    if !errors.As(err, &valErr) {
        t.Fatalf("expected ValidationError, got %T: %v", err, err)
    }
    if valErr.Field != "email" {
        t.Errorf("expected field 'email', got %q", valErr.Field)
    }
}
```

---

## Pattern 5: Test File Organization

```
internal/user/
    service.go              ← implementation
    service_test.go         ← unit tests (same package)
    store.go                ← interface + real implementation
    stub_test.go            ← test doubles (only compiled during tests)

test/integration/
    user_test.go            ← integration tests (separate package)
```

**Rules**:
- Unit tests live next to the code they test, same package
- Test doubles (stubs, fakes) go in `*_test.go` files (not compiled into production binary)
- Integration tests go in `test/integration/` with build tags if needed
- Each test file maps to one source file: `service.go` → `service_test.go`

---

## Pattern 6: Testing HTTP Handlers

```go
func TestHandler_CreateUser(t *testing.T) {
    // Arrange: set up dependencies and request
    store := &StubUserStore{users: map[string]User{}}
    handler := NewHandler(store)

    body := strings.NewReader(`{"name":"Alice","email":"alice@test.com"}`)
    req := httptest.NewRequest(http.MethodPost, "/users", body)
    req.Header.Set("Content-Type", "application/json")
    rec := httptest.NewRecorder()

    // Act: call the handler
    handler.CreateUser(rec, req)

    // Assert: check response
    if rec.Code != http.StatusCreated {
        t.Errorf("status = %d, want %d", rec.Code, http.StatusCreated)
    }

    var got User
    if err := json.NewDecoder(rec.Body).Decode(&got); err != nil {
        t.Fatalf("decoding response: %v", err)
    }
    if got.Name != "Alice" {
        t.Errorf("name = %q, want %q", got.Name, "Alice")
    }
}
```

---

## Pattern 7: Parallel Tests (Advanced — Introduce Later)

```go
// Only use t.Parallel when the test has NO shared mutable state
func TestCalculateDiscount(t *testing.T) {
    tests := []struct {
        name     string
        quantity int
        want     float64
    }{
        {"no discount under 10", 5, 0.0},
        {"10 percent over 10", 15, 0.10},
        {"20 percent over 100", 150, 0.20},
    }

    for _, tt := range tests {
        tt := tt  // capture range variable (required before Go 1.22)
        t.Run(tt.name, func(t *testing.T) {
            t.Parallel()  // this subtest can run concurrently with others
            got := CalculateDiscount(tt.quantity)
            if got != tt.want {
                t.Errorf("CalculateDiscount(%d) = %v, want %v", tt.quantity, got, tt.want)
            }
        })
    }
}
```

**Teaching point**: Don't introduce `t.Parallel()` until the developer understands
why the range variable capture (`tt := tt`) is necessary. This is a common Go gotcha.
In Go 1.22+, the loop variable is scoped per iteration so the capture is unnecessary.

---

## Anti-Patterns to Flag

```go
// ❌ Testing implementation details instead of behavior
if len(service.cache) == 1 { ... }  // couples test to internal state

// ❌ Giant test functions with no subtests
func TestEverything(t *testing.T) {
    // 200 lines of sequential assertions
}

// ❌ Assertions without context
if got != want {
    t.Error("mismatch")  // WHAT mismatched?
}
// ✅ Always include got/want in error messages
if got != want {
    t.Errorf("GetUser(%q).Name = %q, want %q", id, got, want)
}

// ❌ Using time.Sleep in tests
time.Sleep(100 * time.Millisecond)  // flaky, slow
// ✅ Use channels, sync primitives, or polling with timeout

// ❌ Test files without the _test.go suffix
// These get compiled into the production binary
```

---

## TDD Cadence Reminder

When working with a developer on tests:
1. Write ONE test case → RED (fails)
2. Write minimum implementation → GREEN (passes)
3. Refactor → still GREEN
4. Add next test case → repeat

Never pre-populate more than 3 test cases at once. Build incrementally.
