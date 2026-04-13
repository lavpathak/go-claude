# Skill: Go Project Structure

> Claude reads this skill automatically whenever new files or packages are
> created, or when code organization is discussed. Follow these patterns exactly.

---

## Core Rule

**Organize by domain, not by layer. Keep packages small and focused.**

---

## Standard Layout

```
myservice/
├── cmd/
│   └── myservice/
│       └── main.go              ← Entry point. Wires dependencies. Minimal logic.
│
├── internal/                    ← Private to this module. Cannot be imported externally.
│   ├── user/
│   │   ├── model.go             ← User struct, validation, domain logic
│   │   ├── model_test.go
│   │   ├── service.go           ← Business logic (UserService)
│   │   ├── service_test.go
│   │   ├── handler.go           ← HTTP handlers
│   │   ├── handler_test.go
│   │   ├── store.go             ← Interface + real implementation
│   │   └── stub_test.go         ← Test doubles
│   │
│   ├── order/                   ← Another domain
│   │   ├── model.go
│   │   ├── ...
│   │
│   └── platform/                ← Shared infrastructure
│       ├── postgres/
│       │   └── client.go        ← Database connection setup
│       ├── httpserver/
│       │   └── server.go        ← HTTP server configuration
│       └── logger/
│           └── logger.go        ← Logging setup
│
├── api/                         ← API definitions (OpenAPI, protobuf)
│   └── openapi.yaml
│
├── configs/                     ← Configuration templates
│   └── config.yaml
│
├── scripts/                     ← Build and setup scripts
│   └── setup-claude-guardrails.sh
│
├── docs/                        ← Documentation
│   └── claude-developer-guide.md
│
├── test/                        ← Integration and e2e tests
│   └── integration/
│       └── user_api_test.go
│
├── go.mod
├── go.sum
├── Makefile
├── CLAUDE.md
├── .golangci.yml
└── .claude/                     ← Claude Code configuration
```

---

## Package Rules

### Naming
```go
// ✅ GOOD — short, lowercase, single word
package user
package order
package auth
package store
package config

// ❌ BAD — multi-word, underscores, mixedCaps
package userService     // mixedCaps
package user_handler    // underscore
package models          // plural (avoid)
package utils           // vague grab-bag
package helpers         // same problem
package common          // same problem
```

**Teaching point**: If you can't name a package with one clear word, it's probably
doing too much. Split it. The exception is compound domain terms like `orderitem`
when there's no good single word.

### What Goes Where

| Content | Location | Reasoning |
|---------|----------|-----------|
| Domain types (User, Order) | `internal/<domain>/model.go` | Types live with their domain |
| Business logic | `internal/<domain>/service.go` | Orchestrates domain operations |
| HTTP handlers | `internal/<domain>/handler.go` | Translates HTTP ↔ domain |
| Storage interfaces | `internal/<domain>/store.go` | Defined where consumed |
| Storage implementations | `internal/<domain>/store.go` or `internal/platform/postgres/` | Depends on reusability |
| Shared infrastructure | `internal/platform/<thing>/` | Database, logging, config |
| CLI entry point | `cmd/<binary>/main.go` | One per binary |
| Integration tests | `test/integration/` | Separate from unit tests |

### The `internal/` Rule

Everything under `internal/` is invisible to outside modules. Use it aggressively.
If in doubt, put it in `internal/`. You can always move it to `pkg/` later
(but almost never need to).

```
// ✅ Can import:
// cmd/myservice/main.go → internal/user
// internal/order         → internal/user (sibling packages can import each other)

// ❌ Cannot import (enforced by Go compiler):
// some-other-module      → internal/user
```

---

## Package Dependency Rules

```
cmd/          → imports internal/*
internal/user → imports internal/platform/* (infrastructure)
internal/user → NEVER imports internal/order (avoid circular domain deps)
```

If two domain packages need to communicate:
1. **Define an interface** in the consuming package
2. **Wire it in `cmd/main.go`** through dependency injection
3. Never have domain packages import each other directly

```go
// cmd/myservice/main.go — the wiring point
func main() {
    db := postgres.Connect(cfg.DatabaseURL)

    userStore := &user.PostgresStore{DB: db}
    orderStore := &order.PostgresStore{DB: db}

    userService := user.NewService(userStore)
    orderService := order.NewService(orderStore, userService) // inject user capability

    // ...
}
```

---

## File Organization Within a Package

Each file should have one clear purpose. Keep files under ~200 lines.

```go
// model.go — types, constructors, validation
type User struct { ... }
func NewUser(name, email string) (User, error) { ... }
func (u User) Validate() error { ... }

// service.go — business logic
type Service struct { store UserStore }
func NewService(store UserStore) *Service { ... }
func (s *Service) CreateUser(ctx context.Context, input CreateInput) (User, error) { ... }
func (s *Service) GetProfile(ctx context.Context, id string) (Profile, error) { ... }

// handler.go — HTTP translation
type Handler struct { service *Service }
func NewHandler(service *Service) *Handler { ... }
func (h *Handler) RegisterRoutes(mux *http.ServeMux) { ... }
func (h *Handler) handleCreate(w http.ResponseWriter, r *http.Request) { ... }
func (h *Handler) handleGet(w http.ResponseWriter, r *http.Request) { ... }

// store.go — persistence interface and implementation
type UserStore interface { ... }
type PostgresStore struct { db *sql.DB }
func (s *PostgresStore) GetUser(ctx context.Context, id string) (User, error) { ... }
```

---

## The `cmd/main.go` Pattern

```go
package main

import (
    "context"
    "log/slog"
    "net/http"
    "os"
    "os/signal"

    "myservice/internal/platform/postgres"
    "myservice/internal/user"
)

func main() {
    // 1. Load configuration
    cfg := loadConfig()

    // 2. Set up logger
    logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

    // 3. Connect infrastructure
    db, err := postgres.Connect(cfg.DatabaseURL)
    if err != nil {
        logger.Error("connecting to database", "error", err)
        os.Exit(1)
    }
    defer db.Close()

    // 4. Wire dependencies (this is your composition root)
    userStore := &user.PostgresStore{DB: db}
    userService := user.NewService(userStore)
    userHandler := user.NewHandler(userService)

    // 5. Set up routes
    mux := http.NewServeMux()
    userHandler.RegisterRoutes(mux)

    // 6. Start server with graceful shutdown
    srv := &http.Server{Addr: cfg.ListenAddr, Handler: mux}

    go func() {
        logger.Info("server starting", "addr", cfg.ListenAddr)
        if err := srv.ListenAndServe(); err != http.ErrServerClosed {
            logger.Error("server error", "error", err)
        }
    }()

    // 7. Wait for interrupt
    ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
    defer stop()
    <-ctx.Done()

    logger.Info("shutting down")
    srv.Shutdown(context.Background())
}
```

**Teaching point**: `main.go` is the composition root. It wires everything together
but contains no business logic. If you find yourself writing `if` statements about
business rules in `main.go`, that logic belongs in a service.

---

## Anti-Patterns to Flag

```
// ❌ Layer-based organization (Java-style)
models/
    user.go
    order.go
controllers/
    user_controller.go
    order_controller.go
services/
    user_service.go
    order_service.go

// ❌ "utils" or "helpers" packages
utils/string_helpers.go    // put these in the package that uses them
helpers/date_helpers.go    // or create a specific package like "timeutil"

// ❌ Putting everything in one package
internal/
    user.go
    order.go
    handler.go          // which domain? unclear
    service.go          // which service?

// ❌ Too many tiny packages (1 file each)
internal/user/model/model.go
internal/user/service/service.go
internal/user/handler/handler.go
// Just put these in internal/user/
```

---

## Creating New Packages Checklist

When Claude helps create a new package:

1. Confirm the package name is a single lowercase word
2. Confirm it lives under `internal/` unless there's a reason not to
3. Create `model.go` first with the core types
4. Create `model_test.go` immediately (TDD)
5. Never create more than 3 files in one session (+ their test files)
6. Wire it in `cmd/main.go` through dependency injection
