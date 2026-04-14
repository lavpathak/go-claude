---
name: go-interfaces
description: Go interface design — accept interfaces/return structs, define interfaces at the consumer, small segregated interfaces, composition, compile-time satisfaction checks, -er naming convention, functional options. Load when designing, implementing, or refactoring Go interfaces.
---

# Skill: Go Interfaces

> Claude reads this skill automatically whenever interfaces are designed,
> implemented, composed, or refactored. Follow these patterns exactly.

---

## Core Rule

**Accept interfaces, return structs. Define interfaces where they are consumed.**

Go interfaces are small, implicit, and powerful. The team's standard is to keep
them focused (1-3 methods) and define them in the package that USES the behavior,
not the package that implements it.

---

## Pattern 1: Define Interfaces at the Consumer

```go
// ❌ BAD — defining the interface in the implementation package
// package store
type UserStore interface {
    Get(ctx context.Context, id string) (User, error)
    Create(ctx context.Context, user User) error
}
type PostgresUserStore struct { ... }

// ✅ GOOD — define the interface where it's needed
// package service (the consumer)
type UserReader interface {
    GetUser(ctx context.Context, id string) (User, error)
}

type UserWriter interface {
    CreateUser(ctx context.Context, user User) error
}

// package store (the implementation) — no interface here
type PostgresStore struct { db *sql.DB }
func (s *PostgresStore) GetUser(ctx context.Context, id string) (User, error) { ... }
func (s *PostgresStore) CreateUser(ctx context.Context, user User) error { ... }
```

**Teaching point**: This is inverted from Java/C# where you define the interface
with the implementation. In Go, the consumer defines what it needs. This means
the store package doesn't even know the interface exists — it just has methods.
The Go compiler checks satisfaction automatically.

---

## Pattern 2: Keep Interfaces Small

```go
// ❌ BAD — fat interface forces implementors to provide everything
type Repository interface {
    Get(ctx context.Context, id string) (Entity, error)
    List(ctx context.Context, filter Filter) ([]Entity, error)
    Create(ctx context.Context, entity Entity) error
    Update(ctx context.Context, entity Entity) error
    Delete(ctx context.Context, id string) error
    Count(ctx context.Context) (int, error)
    Export(ctx context.Context, format string) ([]byte, error)
}

// ✅ GOOD — segregated by use case
type EntityGetter interface {
    Get(ctx context.Context, id string) (Entity, error)
}

type EntityLister interface {
    List(ctx context.Context, filter Filter) ([]Entity, error)
}

type EntityCreator interface {
    Create(ctx context.Context, entity Entity) error
}
```

**Teaching point**: If a function only needs to READ an entity, it should accept
`EntityGetter`, not the full `Repository`. This makes the function easier to test
(smaller stub), documents exactly what it needs, and follows Interface Segregation
(the I in SOLID).

---

## Pattern 3: Compose Interfaces When Needed

```go
// Combine small interfaces for functions that need multiple capabilities
type EntityReadWriter interface {
    EntityGetter
    EntityCreator
}

// The service constructor can accept the composed interface
func NewOrderService(store EntityReadWriter, notifier Notifier) *OrderService {
    return &OrderService{store: store, notifier: notifier}
}
```

---

## Pattern 4: Standard Library Interfaces to Know

Teach these as the team encounters them:

```go
// io.Reader — anything you can read bytes from
type Reader interface {
    Read(p []byte) (n int, err error)
}
// Implemented by: *os.File, *bytes.Buffer, *strings.Reader, http.Response.Body

// io.Writer — anything you can write bytes to
type Writer interface {
    Write(p []byte) (n int, err error)
}
// Implemented by: *os.File, *bytes.Buffer, http.ResponseWriter

// io.Closer — anything that needs cleanup
type Closer interface {
    Close() error
}

// fmt.Stringer — custom string representation
type Stringer interface {
    String() string
}

// error — the most important interface in Go
type error interface {
    Error() string
}

// sort.Interface — for custom sorting
type Interface interface {
    Len() int
    Less(i, j int) bool
    Swap(i, j int)
}

// http.Handler — HTTP request handler
type Handler interface {
    ServeHTTP(ResponseWriter, *Request)
}
```

---

## Pattern 5: The Interface Check Trick

```go
// Compile-time check that PostgresStore implements UserReader
var _ UserReader = (*PostgresStore)(nil)

// This produces a compile error if PostgresStore is missing any methods.
// Place it in the implementation file, not the test file.
```

**Teaching point**: This is a zero-cost assertion that runs at compile time.
It catches interface mismatches before any tests run. Use it whenever you
create a new implementation of a team-defined interface.

---

## Pattern 6: Naming Conventions

```go
// Single-method interfaces: name by the verb + "er"
type Reader interface { Read(p []byte) (int, error) }
type Writer interface { Write(p []byte) (int, error) }
type Closer interface { Close() error }
type Stringer interface { String() string }
type Notifier interface { Notify(ctx context.Context, msg Message) error }
type Validator interface { Validate() error }

// Multi-method interfaces: name by the role or capability
type UserStore interface { ... }
type OrderProcessor interface { ... }
type AuthProvider interface { ... }

// NEVER use "I" prefix
// ❌ IUserStore, INotifier
// ✅ UserStore, Notifier

// Implementation names should be concrete
// ✅ PostgresUserStore, SMTPNotifier, InMemoryCache
// ❌ UserStoreImpl, NotifierImpl
```

---

## Pattern 7: Functional Options (Advanced)

Introduce this pattern when a constructor has many optional parameters:

```go
// Option type
type Option func(*Server)

// Option constructors
func WithPort(port int) Option {
    return func(s *Server) {
        s.port = port
    }
}

func WithTimeout(d time.Duration) Option {
    return func(s *Server) {
        s.timeout = d
    }
}

// Constructor accepts variadic options
func NewServer(handler http.Handler, opts ...Option) *Server {
    s := &Server{
        handler: handler,
        port:    8080,           // sensible default
        timeout: 30 * time.Second, // sensible default
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage is clean and self-documenting
srv := NewServer(handler,
    WithPort(9090),
    WithTimeout(60 * time.Second),
)
```

**Teaching point**: Don't introduce this until the developer has written at least
a few constructors with 3+ parameters and felt the pain of positional arguments.

---

## Anti-Patterns to Flag

```go
// ❌ Interface defined in same package as only implementation
// (premature abstraction — you don't need an interface with one implementation)

// ❌ Empty interface used as "accept anything"
func Process(data interface{}) { ... }  // what does this accept? who knows

// ❌ Returning an interface instead of a concrete type
func NewStore() Store { ... }      // ❌ hides the real type
func NewStore() *PostgresStore { ... }  // ✅ caller knows what they get

// ❌ Interface with 10+ methods (almost certainly a struct in disguise)

// ❌ Checking interface satisfaction at runtime only
// Use compile-time check: var _ Interface = (*Type)(nil)
```

---

## When to Introduce Interfaces

Guide for when to teach/use interfaces with this team:

1. **Week 1-2**: Show `error` interface, `io.Reader`, `io.Writer`
2. **Week 3-4**: Create first custom interface for testing (UserStore pattern)
3. **Month 2**: Interface composition, segregation
4. **Month 3**: Functional options, the interface check trick
5. **Never in month 1**: Don't create interfaces "just in case." Wait until
   there's a real second implementation or a testing need.
