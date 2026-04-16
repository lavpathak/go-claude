---
name: go-solid-patterns
description: SOLID principles applied to Go — SRP at function and package level, OCP via interfaces, LSP substitutability, ISP, DIP via constructor injection, guard clauses, avoiding package-level state and init(). Load when making structure or design decisions.
---

# Skill: Go SOLID Patterns

> Claude reads this skill whenever code structure or design decisions are being
> made. Apply these principles in every review and implementation.

---

## Core Rule

**Good Go code is boring code. It reads top to bottom, does one thing per function,
and makes dependencies explicit.**

---

## Single Responsibility Principle

Every struct, function, and package has ONE reason to change.

### At the Function Level

```go
// ❌ BAD — this function does three things
func CreateUser(db *sql.DB, input UserInput) (User, error) {
    // 1. Validates
    if input.Email == "" {
        return User{}, errors.New("email required")
    }
    // 2. Hashes password
    hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
    if err != nil {
        return User{}, err
    }
    // 3. Persists
    _, err = db.Exec("INSERT INTO users ...", input.Email, hash)
    return User{}, err
}

// ✅ GOOD — each function has one job
func (v *UserValidator) Validate(input UserInput) error {
    if input.Email == "" {
        return &ValidationError{Field: "email", Message: "is required"}
    }
    return nil
}

func HashPassword(plain string) (string, error) {
    hash, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
    if err != nil {
        return "", fmt.Errorf("hashing password: %w", err)
    }
    return string(hash), nil
}

func (s *UserStore) Create(ctx context.Context, user User) error {
    _, err := s.db.ExecContext(ctx, "INSERT INTO users ...", user.Email, user.PasswordHash)
    if err != nil {
        return fmt.Errorf("inserting user: %w", err)
    }
    return nil
}
```

### At the Package Level

```
// ❌ BAD — package does too many unrelated things
package app
    user.go       // user logic
    order.go      // order logic
    email.go      // email sending
    database.go   // db connection

// ✅ GOOD — each package has a focused purpose
internal/user/      // user domain
internal/order/     // order domain
internal/email/     // email sending
internal/platform/postgres/  // database infrastructure
```

---

## Open/Closed Principle

Open for extension, closed for modification. In Go, this means interfaces.

```go
// Define behavior as an interface
type PaymentProcessor interface {
    Process(ctx context.Context, amount Money) (Receipt, error)
}

// Extend by adding NEW implementations, not modifying existing ones
type StripeProcessor struct { client *stripe.Client }
type PayPalProcessor struct { client *paypal.Client }
type MockProcessor struct { err error }  // for testing

// The service doesn't know or care which processor it uses
type OrderService struct {
    payments PaymentProcessor  // accepts any implementation
}

func (s *OrderService) Checkout(ctx context.Context, order Order) error {
    receipt, err := s.payments.Process(ctx, order.Total)
    // ...
}

// Adding a new payment method (e.g., Bitcoin) = new struct, zero changes to OrderService
type BitcoinProcessor struct { ... }
```

---

## Liskov Substitution Principle

Any implementation must be a safe drop-in replacement.

```go
// If your interface says it returns an error for invalid input:
type Validator interface {
    Validate(input Input) error
}

// Then EVERY implementation must handle invalid input by returning an error.
// An implementation that panics on invalid input violates Liskov.

// ❌ Violates Liskov
type StrictValidator struct{}
func (v *StrictValidator) Validate(input Input) error {
    if input.Name == "" {
        panic("name required")  // callers expect an error, not a panic
    }
    return nil
}

// ✅ Satisfies Liskov
type StrictValidator struct{}
func (v *StrictValidator) Validate(input Input) error {
    if input.Name == "" {
        return &ValidationError{Field: "name", Message: "is required"}
    }
    return nil
}
```

---

## Interface Segregation Principle

Don't force consumers to depend on methods they don't use.
(See `go-interfaces/SKILL.md` skill for detailed patterns.)

```go
// ❌ A function that only reads users shouldn't require write capability
func GetUserProfile(store FullUserRepository) (Profile, error) { ... }

// ✅ Accept only what you need
func GetUserProfile(reader UserReader) (Profile, error) { ... }
```

**Rule of thumb**: If an interface has more than 3 methods, consider splitting it.

---

## Dependency Inversion Principle

High-level modules should not depend on low-level modules. Both should depend
on abstractions.

```go
// ❌ BAD — service depends directly on concrete database type
type UserService struct {
    db *sql.DB  // concrete dependency
}

func (s *UserService) GetUser(ctx context.Context, id string) (User, error) {
    row := s.db.QueryRowContext(ctx, "SELECT ...", id)  // SQL is in business logic
    // ...
}

// ✅ GOOD — service depends on abstraction
type UserReader interface {
    GetUser(ctx context.Context, id string) (User, error)
}

type UserService struct {
    users UserReader  // abstraction — could be Postgres, Redis, mock, etc.
}

func (s *UserService) GetProfile(ctx context.Context, id string) (Profile, error) {
    user, err := s.users.GetUser(ctx, id)  // no SQL here
    if err != nil {
        return Profile{}, fmt.Errorf("getting user: %w", err)
    }
    return user.ToProfile(), nil
}

// Constructor makes the dependency explicit
func NewUserService(users UserReader) *UserService {
    return &UserService{users: users}
}
```

---

## Additional Go Design Patterns

### Constructor Injection (Team Standard)

```go
// Every service uses constructor injection — no global state, no init()
type OrderService struct {
    orders  OrderStore
    users   UserReader
    notify  Notifier
    logger  *slog.Logger
}

func NewOrderService(
    orders OrderStore,
    users UserReader,
    notify Notifier,
    logger *slog.Logger,
) *OrderService {
    return &OrderService{
        orders: orders,
        users:  users,
        notify: notify,
        logger: logger,
    }
}
```

### Guard Clauses (Fail Early)

```go
// ❌ BAD — deep nesting
func ProcessOrder(ctx context.Context, order Order) error {
    if order.ID != "" {
        if order.Total > 0 {
            if len(order.Items) > 0 {
                // actual logic buried here
            } else {
                return errors.New("no items")
            }
        } else {
            return errors.New("invalid total")
        }
    } else {
        return errors.New("missing id")
    }
}

// ✅ GOOD — guard clauses, flat structure
func ProcessOrder(ctx context.Context, order Order) error {
    if order.ID == "" {
        return errors.New("missing order id")
    }
    if order.Total <= 0 {
        return errors.New("order total must be positive")
    }
    if len(order.Items) == 0 {
        return errors.New("order must have at least one item")
    }

    // Happy path — clear and unindented
    return s.store.Save(ctx, order)
}
```

### Avoid Package-Level State

```go
// ❌ BAD — global mutable state
var db *sql.DB

func init() {
    var err error
    db, err = sql.Open("postgres", os.Getenv("DATABASE_URL"))
    if err != nil {
        panic(err)
    }
}

func GetUser(id string) (User, error) {
    return queryUser(db, id)  // hidden dependency
}

// ✅ GOOD — explicit dependencies, no globals
type Store struct {
    db *sql.DB
}

func NewStore(db *sql.DB) *Store {
    return &Store{db: db}
}

func (s *Store) GetUser(ctx context.Context, id string) (User, error) {
    return s.queryUser(ctx, id)
}
```

**Teaching point**: `init()` functions run before `main()` and create hidden
dependencies. They make testing harder because you can't control initialization
order. Avoid them except for registering database drivers (`_ "github.com/lib/pq"`).

---

## Code Smells to Watch For

| Smell | Likely Violation | Fix |
|---|---|---|
| Function >40 lines | Single Responsibility | Extract smaller functions |
| Struct with 8+ fields | Single Responsibility | Split into smaller structs |
| `switch` on type | Open/Closed | Use interface + implementations |
| Passing `*sql.DB` everywhere | Dependency Inversion | Define a store interface |
| Package imports 10+ others | Single Responsibility | Package is too big, split it |
| `if err != nil` with no context | Error handling | Wrap with `fmt.Errorf("...: %w", err)` |
| Global variables | Dependency Inversion | Constructor injection |
| `interface{}` / `any` parameter | Interface Segregation | Define specific interface |
