---
name: go-database
description: Go database patterns — store interface at consumer, Postgres QueryRowContext/QueryContext, defer rows.Close and rows.Err check, transactions with deferred rollback, connection pool tuning, parameterized queries, integration tests. Load for database access, queries, or repositories.
---

# Skill: Go Database Patterns

> Claude reads this skill whenever database access, queries, repositories,
> transactions, or data persistence is involved. Follow these patterns exactly.

---

## Core Rule

**SQL lives in the store layer. Business logic never sees a database connection.**

The service layer calls interface methods. The store layer translates those
calls into SQL. This separation makes testing trivial and database migrations
safe.

---

## Pattern 1: Repository / Store Interface

```go
// Defined in the domain package (where it's consumed)
// internal/user/store.go

type UserStore interface {
    GetUser(ctx context.Context, id string) (User, error)
    GetUserByEmail(ctx context.Context, email string) (User, error)
    CreateUser(ctx context.Context, user User) error
    UpdateUser(ctx context.Context, user User) error
    DeleteUser(ctx context.Context, id string) error
    ListUsers(ctx context.Context, offset, limit int) ([]User, error)
}
```

---

## Pattern 2: Postgres Implementation

```go
// internal/user/postgres_store.go

type PostgresStore struct {
    db *sql.DB
}

func NewPostgresStore(db *sql.DB) *PostgresStore {
    return &PostgresStore{db: db}
}

// Compile-time interface check
var _ UserStore = (*PostgresStore)(nil)

func (s *PostgresStore) GetUser(ctx context.Context, id string) (User, error) {
    var u User
    err := s.db.QueryRowContext(ctx,
        `SELECT id, name, email, created_at FROM users WHERE id = $1`,
        id,
    ).Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt)

    if err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return User{}, ErrNotFound  // translate to domain error
        }
        return User{}, fmt.Errorf("querying user by id: %w", err)
    }
    return u, nil
}

func (s *PostgresStore) CreateUser(ctx context.Context, user User) error {
    _, err := s.db.ExecContext(ctx,
        `INSERT INTO users (id, name, email, password_hash, created_at)
         VALUES ($1, $2, $3, $4, $5)`,
        user.ID, user.Name, user.Email, user.PasswordHash, user.CreatedAt,
    )
    if err != nil {
        // Check for unique constraint violation
        var pgErr *pq.Error
        if errors.As(err, &pgErr) && pgErr.Code == "23505" {
            return ErrConflict
        }
        return fmt.Errorf("inserting user: %w", err)
    }
    return nil
}

func (s *PostgresStore) ListUsers(ctx context.Context, offset, limit int) ([]User, error) {
    rows, err := s.db.QueryContext(ctx,
        `SELECT id, name, email, created_at FROM users
         ORDER BY created_at DESC
         LIMIT $1 OFFSET $2`,
        limit, offset,
    )
    if err != nil {
        return nil, fmt.Errorf("querying users: %w", err)
    }
    defer rows.Close()  // ALWAYS close rows

    var users []User
    for rows.Next() {
        var u User
        if err := rows.Scan(&u.ID, &u.Name, &u.Email, &u.CreatedAt); err != nil {
            return nil, fmt.Errorf("scanning user row: %w", err)
        }
        users = append(users, u)
    }

    // ALWAYS check rows.Err() after the loop
    if err := rows.Err(); err != nil {
        return nil, fmt.Errorf("iterating user rows: %w", err)
    }

    return users, nil
}
```

**Teaching points**:
- `QueryRowContext` for single row, `QueryContext` for multiple rows
- Always use `Context` variants (not `Query`, `Exec`) to support cancellation
- Always `defer rows.Close()` immediately after `QueryContext`
- Always check `rows.Err()` after the loop — it catches errors during iteration
- Use `$1, $2` placeholders (Postgres) not string concatenation (SQL injection)
- Translate database errors to domain errors at the store boundary

---

## Pattern 3: Transactions

```go
// Option A: Transaction within a single store method
func (s *PostgresStore) TransferBalance(ctx context.Context, fromID, toID string, amount int) error {
    tx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return fmt.Errorf("beginning transaction: %w", err)
    }
    // Defer rollback — no-op if already committed
    defer tx.Rollback()

    // Debit
    result, err := tx.ExecContext(ctx,
        `UPDATE accounts SET balance = balance - $1 WHERE id = $2 AND balance >= $1`,
        amount, fromID,
    )
    if err != nil {
        return fmt.Errorf("debiting account: %w", err)
    }
    rows, _ := result.RowsAffected()
    if rows == 0 {
        return errors.New("insufficient balance")
    }

    // Credit
    _, err = tx.ExecContext(ctx,
        `UPDATE accounts SET balance = balance + $1 WHERE id = $2`,
        amount, toID,
    )
    if err != nil {
        return fmt.Errorf("crediting account: %w", err)
    }

    // Commit — if this succeeds, the deferred Rollback is a no-op
    if err := tx.Commit(); err != nil {
        return fmt.Errorf("committing transaction: %w", err)
    }
    return nil
}
```

**Teaching point**: Always `defer tx.Rollback()` right after `BeginTx`. If the
function returns early due to an error, the transaction is rolled back automatically.
If `tx.Commit()` is called first, the deferred `Rollback()` is a harmless no-op.

```go
// Option B: Transaction helper for cross-store operations
func WithTransaction(ctx context.Context, db *sql.DB, fn func(tx *sql.Tx) error) error {
    tx, err := db.BeginTx(ctx, nil)
    if err != nil {
        return fmt.Errorf("beginning transaction: %w", err)
    }
    defer tx.Rollback()

    if err := fn(tx); err != nil {
        return err
    }

    if err := tx.Commit(); err != nil {
        return fmt.Errorf("committing transaction: %w", err)
    }
    return nil
}

// Usage
err := WithTransaction(ctx, db, func(tx *sql.Tx) error {
    if err := userStore.CreateWithTx(ctx, tx, user); err != nil {
        return err
    }
    if err := auditStore.LogWithTx(ctx, tx, "user_created", user.ID); err != nil {
        return err
    }
    return nil
})
```

---

## Pattern 4: Database Connection Setup

```go
// internal/platform/postgres/client.go

func Connect(databaseURL string) (*sql.DB, error) {
    db, err := sql.Open("postgres", databaseURL)
    if err != nil {
        return nil, fmt.Errorf("opening database: %w", err)
    }

    // Configure connection pool
    db.SetMaxOpenConns(25)                  // max concurrent connections
    db.SetMaxIdleConns(5)                   // keep some connections warm
    db.SetConnMaxLifetime(5 * time.Minute)  // recycle connections periodically

    // Verify connectivity
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := db.PingContext(ctx); err != nil {
        db.Close()
        return nil, fmt.Errorf("pinging database: %w", err)
    }

    return db, nil
}
```

---

## Pattern 5: Testing Database Code

### Unit Tests (with stubs — no real database)

```go
// stub_test.go
type StubUserStore struct {
    users map[string]User
}

func (s *StubUserStore) GetUser(_ context.Context, id string) (User, error) {
    u, ok := s.users[id]
    if !ok {
        return User{}, ErrNotFound
    }
    return u, nil
}
```

### Integration Tests (with real database)

```go
// test/integration/user_store_test.go
// +build integration

func TestPostgresStore_CreateAndGet(t *testing.T) {
    db := setupTestDB(t)  // connects to test database
    store := user.NewPostgresStore(db)

    // Create
    u := user.User{
        ID:    "test-1",
        Name:  "Alice",
        Email: "alice@test.com",
    }
    err := store.CreateUser(context.Background(), u)
    if err != nil {
        t.Fatalf("CreateUser: %v", err)
    }

    // Get
    got, err := store.GetUser(context.Background(), "test-1")
    if err != nil {
        t.Fatalf("GetUser: %v", err)
    }
    if got.Email != "alice@test.com" {
        t.Errorf("email = %q, want %q", got.Email, "alice@test.com")
    }
}

func setupTestDB(t *testing.T) *sql.DB {
    t.Helper()
    url := os.Getenv("TEST_DATABASE_URL")
    if url == "" {
        t.Skip("TEST_DATABASE_URL not set")
    }
    db, err := sql.Open("postgres", url)
    if err != nil {
        t.Fatalf("connecting: %v", err)
    }
    t.Cleanup(func() { db.Close() })

    // Run in a transaction that rolls back — clean test isolation
    tx, err := db.Begin()
    if err != nil {
        t.Fatalf("beginning tx: %v", err)
    }
    t.Cleanup(func() { tx.Rollback() })

    return db
}
```

---

## Anti-Patterns to Flag

```go
// ❌ SQL in business logic layer
func (s *Service) GetUser(ctx context.Context, id string) (User, error) {
    row := s.db.QueryRow("SELECT * FROM users WHERE id = $1", id)
    // Service should call store.GetUser(ctx, id) instead
}

// ❌ String concatenation in queries (SQL injection)
query := "SELECT * FROM users WHERE name = '" + name + "'"
// ✅ Always use parameterized queries
query := "SELECT * FROM users WHERE name = $1"

// ❌ Not closing rows
rows, _ := db.QueryContext(ctx, "SELECT ...")
for rows.Next() { ... }
// Missing rows.Close() — connection leak!

// ❌ Ignoring rows.Err()
for rows.Next() { ... }
// Missing rows.Err() check — silent iteration errors

// ❌ Using context.Background() instead of request context
row := db.QueryRowContext(context.Background(), ...)
// ✅ Use the request context for automatic cancellation
row := db.QueryRowContext(ctx, ...)

// ❌ SELECT * (fragile, breaks when columns change)
db.QueryContext(ctx, "SELECT * FROM users")
// ✅ Always list columns explicitly
db.QueryContext(ctx, "SELECT id, name, email, created_at FROM users")
```

---

## Migration Pattern

```
migrations/
    001_create_users.up.sql
    001_create_users.down.sql
    002_add_user_email_index.up.sql
    002_add_user_email_index.down.sql
```

Use a migration tool (golang-migrate, goose, or atlas). Never modify
the database schema by hand or in application code.
