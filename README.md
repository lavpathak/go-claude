# Claude AI Developer Guide

> Everything you need to know about using Claude Code for Go.

---

## Table of Contents

1. [How This Setup Works](#how-this-setup-works)
2. [Quick Start](#quick-start)
3. [Skills vs Commands — The Two Systems](#skills-vs-commands)
4. [The Commands](#the-commands)
5. [The Skills](#the-skills)
6. [Guardrails Explained](#guardrails-explained)
7. [Workflow Examples](#workflow-examples)
8. [What Claude Will and Won't Do](#what-claude-will-and-wont-do)
9. [Troubleshooting](#troubleshooting)
10. [Growing With the System](#growing-with-the-system)

---

## How This Setup Works

This repo ships with a configured Claude Code environment. Here's the full file map:

```
CLAUDE.md                                ← Master rules. Claude reads this first.

.claude/
  settings.json                          ← Tool permissions (what Claude can/cannot run)
  hooks.json                             ← Automated checks during Claude sessions

  skills/                                ← PASSIVE: Claude reads these automatically
    go-error-handling.md                   Error patterns, wrapping, sentinel errors
    go-testing.md                          Table-driven tests, helpers, mocking
    go-interfaces.md                       Interface design, composition, naming
    go-project-structure.md                Package layout, naming, file organization
    go-concurrency.md                      Goroutines, channels, sync, errgroup
    go-solid-patterns.md                   SOLID principles applied to Go
    go-http-handlers.md                    Handler structure, middleware, routing
    go-database.md                         Repository pattern, queries, transactions

  commands/                              ← ACTIVE: You trigger these with /command
    pair.md                                /pair — Pair programming session
    tdd.md                                 /tdd — Test-driven development cycle
    review.md                              /review — Educational code review
    teach.md                               /teach — Learn a Go concept
    scope.md                               /scope — Break down a large task
    debug.md                               /debug — Guided debugging

  hooks/                                 ← Git hooks (installed by setup script)
    pre-commit.sh                          Blocks >5 files, runs vet, checks tests
    commit-msg.sh                          Enforces conventional commit format

.golangci.yml                            ← Linter config
Makefile                                 ← make test, make lint, make check
scripts/setup-claude-guardrails.sh       ← One-time setup
```

---

## Quick Start

```bash
# 1. Install tools
npm install -g @anthropic-ai/claude-code
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
go install mvdan.cc/gofumpt@latest

# 2. Set up the repo
git clone <your-repo>
cd <your-repo>
./scripts/setup-claude-guardrails.sh

# 3. Start Claude
claude

# 4. Your first session
/pair I need to build a health check endpoint
```

---

## Skills vs Commands

This is the most important concept to understand.

### Commands = You Drive

Commands are workflows **you** trigger explicitly by typing a slash command.
Claude follows a specific protocol when you invoke one.

```
You type:   /pair I need to add email validation
Claude:     Follows the pair programming protocol step by step
```

**You're in control.** The command doesn't activate unless you type it.

### Skills = Claude Knows Automatically

Skills are reference documents Claude reads **on its own** whenever it recognizes
a relevant situation. You never invoke them. Claude just applies them.

```
You say:    "Let's write the error handling for this function"
Claude:     (internally reads go-error-handling.md)
Claude:     "Let's use error wrapping with fmt.Errorf and the %w verb.
             Here's our team's pattern for this..."
```

**Claude is automatically consistent.** Every time it writes error handling, it
follows the same patterns from `go-error-handling.md`. Every test uses the
table-driven format from `go-testing.md`. You don't have to remind it.

### Why Both?

| Situation | What Fires | Example |
|---|---|---|
| You want to start a structured workflow | **Command** | `/pair`, `/tdd`, `/scope` |
| Claude writes or reviews Go code | **Skill** (automatic) | Error handling, testing patterns |
| You want to learn something | **Command** triggers, **Skill** provides content | `/teach interfaces` reads `go-interfaces.md` |
| Claude reviews your code | **Command** triggers, **Skills** provide checklists | `/review` checks all skill anti-patterns |

---

## The Commands

### `/pair [what you're building]`

Start a collaborative coding session.

```
You:     /pair Add a user registration endpoint

Claude:  Let's build this together. First, tell me:
         1. What fields does registration need?
         2. Should we validate email format?
         3. What happens if the email already exists?

You:     Name, email, password. Yes validate. Return conflict error.

Claude:  Good. Let's scope this — I see 4 files:
         - internal/user/model.go (add validation)
         - internal/user/model_test.go
         - internal/user/handler.go (add registration handler)
         - internal/user/handler_test.go

         That's 4 files, within our limit. Let's start with the test.
         What's the simplest successful registration look like?
```

### `/tdd [function or behavior]`

Strict Red → Green → Refactor, one test at a time.

```
You:     /tdd email validation function

Claude:  What's a valid email we should accept?

You:     user@example.com

Claude:  Here's our first test case:

         func TestValidateEmail(t *testing.T) {
             tests := []struct {
                 name    string
                 email   string
                 wantErr bool
             }{
                 {
                     name:    "valid simple email",
                     email:   "user@example.com",
                     wantErr: false,
                 },
             }
             // ...
         }

         Running: go test -v -run TestValidateEmail
         ❌ FAIL — ValidateEmail doesn't exist yet. That's RED.

         Now: what's the minimum code to make this pass?
```

### `/review [file or path]`

Educational code review with max 5 findings.

```
You:     /review internal/user/handler.go

Claude:  🔴 Must Fix: Unhandled error on line 34
           json.NewEncoder(w).Encode(user)
         The Encode call can fail but the error is discarded...

         🟡 Should Fix: Business logic in handler (line 48)
         Password hashing belongs in the service layer...

         🟢 Nice work: Great use of r.Context() throughout.
         Every database call properly uses the request context.
```

### `/teach [concept]`

Interactive concept explainer.

```
You:     /teach interfaces

Claude:  Let me explain interfaces by starting with a problem you'll hit.

         Imagine you write a function that saves a user to Postgres:
             func SaveUser(db *sql.DB, user User) error { ... }

         Now you want to test it. Problem: you need a real database.

         Interfaces solve this. Instead of accepting *sql.DB, you accept
         a behavior:
             type UserSaver interface {
                 SaveUser(ctx context.Context, user User) error
             }

         Now in tests, you pass a stub. In production, you pass the real store.
         The function doesn't know or care which one it gets.

         Quick question: where in our codebase do you think this pattern
         would be most useful right now?
```

### `/scope [feature]`

Break a big feature into safe-sized phases.

```
You:     /scope Build a REST API for user management

Claude:  📋 Feature: User CRUD API
         Total phases: 4

         Phase 1: Domain Model (2 files)
           internal/user/model.go, model_test.go
           Deliverable: User struct with validated fields

         Phase 2: Store Layer (3 files)
           internal/user/store.go, postgres_store.go, stub_test.go
           Deliverable: Can create and fetch users

         Phase 3: HTTP Handlers — Create + Get (3 files)
           internal/user/handler.go, handler_test.go, cmd/api/routes.go
           Deliverable: POST /users and GET /users/:id work

         Phase 4: Update + Delete (2 files, extending existing)
           Deliverable: Full CRUD operational

         Start Phase 1?
```

### `/debug [issue]`

Guided debugging — teaches the process, not just the fix.

```
You:     /debug TestCreateUser panics with nil pointer

Claude:  Let's find it together. Running:
         go test -v -run TestCreateUser ./internal/user/...

         [reads output]

         The panic is on handler.go:28. Before I look at that line —
         based on "nil pointer dereference," what do you think could be nil?

You:     Maybe the service?

Claude:  Good instinct. Let's check: how is the handler created in the test?
         Can you look at the test setup and tell me what you see?
```

---

## The Skills

Skills fire automatically. You don't need to invoke them. But understanding what
they contain helps you know what to expect from Claude.

### go-error-handling.md
Covers error wrapping with `%w`, sentinel errors (`ErrNotFound`), custom error
types (`ValidationError`), the `errors.Is`/`errors.As` patterns, and the rule
about logging OR returning an error — never both.

### go-testing.md
Covers table-driven tests (the team standard), test helpers with `t.Helper()`,
stub/fake patterns for dependency injection, testing HTTP handlers with
`httptest`, and the rule about building test cases incrementally.

### go-interfaces.md
Covers consumer-side interface definition, keeping interfaces small (1-3 methods),
composition, the compile-time check trick (`var _ Interface = (*Type)(nil)`),
and naming conventions.

### go-project-structure.md
Covers the standard layout (`cmd/`, `internal/`, `pkg/`), package naming rules,
the `internal/` visibility boundary, and the composition root pattern in `main.go`.

### go-concurrency.md
Covers `errgroup` (preferred), `sync.WaitGroup`, `sync.Mutex`, worker pools,
graceful shutdown, and — critically — when NOT to use concurrency. This skill
gates concurrency introduction behind demonstrated need.

### go-solid-patterns.md
Covers Single Responsibility, Open/Closed, Liskov Substitution, Interface
Segregation, and Dependency Inversion as they apply specifically to Go. Also
covers constructor injection, guard clauses, and avoiding package-level state.

### go-http-handlers.md
Covers the 4-step handler structure (Parse → Validate → Execute → Respond),
response helpers, request/response type separation, middleware patterns, and
the rule that handlers contain zero business logic.

### go-database.md
Covers the repository/store pattern, parameterized queries, transaction handling
with `defer tx.Rollback()`, connection pool configuration, and the rule that SQL
never appears in the service layer.

---

## Guardrails Explained

### What's Enforced and How

| Guardrail | Mechanism | Can Be Overridden? |
|---|---|---|
| Max 5 files per task | CLAUDE.md + pre-commit hook + Claude hooks.json | `git commit --no-verify` |
| Max 200 lines new code | CLAUDE.md + pre-commit hook (warning) | Warning only |
| Tests before implementation | CLAUDE.md + hooks.json TDD reminder | Behavioral |
| Conventional commits | commit-msg hook | Cannot override |
| Co-authored-by trailer | CLAUDE.md (behavioral) | Manual discipline |
| No dependency installs | settings.json deny list | Edit settings.json |
| No git push/commit by Claude | settings.json deny list | Edit settings.json |
| Go idioms explained | Skills (automatic) | Behavioral |

### What Claude Can Run Without Asking

```
go test, go vet, golangci-lint, go build, go mod tidy, go fmt,
gofumpt, git diff, git status, git log, make targets,
cat, head, tail, grep, find, wc
```

### What Claude Cannot Run

```
go install, go get, git push, git commit, git merge, git rebase,
curl, wget, sudo, docker, kubectl
```

---

## Workflow Examples

### Example 1: "I need to add a new API endpoint"

```
You:     /scope Add a product search endpoint with filtering

Claude:  [Breaks into 3 phases, each ≤5 files]

You:     Let's start Phase 1

Claude:  /tdd product search model

         [Walks through TDD cycle for Product struct and filter types]

You:     /pair Let's build the handler now

Claude:  [Pair programs through Phase 2, handler + tests]
         [Automatically applies go-http-handlers.md patterns]
         [Automatically applies go-error-handling.md patterns]
         [Runs make check at the end]
```

### Example 2: "This test is failing and I don't know why"

```
You:     /debug TestProductSearch returns wrong results

Claude:  [Guides you through reproducing, hypothesizing, narrowing]
         [Uses go-testing.md patterns to add a regression test]
         [Teaches you the debugging technique, not just the fix]
```

### Example 3: "What does this code do?"

```
You:     /teach What is this interface composition pattern I see in store.go?

Claude:  [Reads go-interfaces.md, teaches composition]
         [Shows example from your actual codebase]
         [Asks comprehension question]
```

---

## What Claude Will and Won't Do

### Will Do
- Explain every Go pattern before using it
- Write tests before implementation
- Ask you to try first, then help when stuck
- Break large tasks into ≤5-file phases
- Run tests and linters after every change
- Follow the exact patterns in the skills files

### Won't Do
- Write more than 5 files at once
- Generate entire packages in one shot
- Skip tests
- Add dependencies without discussion
- Push code or create commits
- Write clever code that's hard to understand
- Introduce concurrency without demonstrated need

---

## Troubleshooting

**"Claude won't write the whole function"**
By design. Say: "I tried X but I'm stuck on Y. Can you show me how to handle Y?"

**"Pre-commit hook blocking me"**
Check which check failed. Run `make check` to see all issues. Emergency: `git commit --no-verify`

**"I need to change more than 5 files"**
Use `/scope` to break it down. This is a feature — small changes are safer.

**"Claude keeps explaining things I already know"**
Tell it: "I understand error handling. Skip the explanation and let's write code."
Claude will adapt.

**"Commit message rejected"**
Format: `type(scope): description` with 10+ char description.
Example: `feat(user): add email validation with regex pattern`

---

## Growing With the System

### Phase 1: Learning (Now)
- 5 files max, 200 lines max
- Claude teaches everything
- Strict TDD, all skills active
- All dependencies discussed

### Phase 2: Comfortable (~2-3 months)
- Raise to 8 files
- Allow direct function writing for familiar patterns
- Pre-approve common deps (testify, chi, sqlx)
- Start using Claude for refactoring

### Phase 3: Proficient (~6 months)
- Raise to 12 files or remove limit
- Allow package scaffolding
- Use Claude for architecture discussions
- TDD requirement stays forever

### How to Relax a Guardrail
1. Team discussion in retro
2. Update the file (CLAUDE.md, settings.json, skills, or hooks)
3. Commit: `chore(guardrails): relax [rule] — [reason]`

---

## Quick Reference

```
┌──────────────────────────────────────────────────┐
│  COMMANDS (you trigger)                          │
│  /pair [task]     Pair programming               │
│  /tdd [func]      Test-driven development        │
│  /review [file]   Educational code review        │
│  /teach [topic]   Learn a Go concept             │
│  /scope [feat]    Break down a big task          │
│  /debug [issue]   Guided debugging               │
├──────────────────────────────────────────────────┤
│  SKILLS (automatic)                              │
│  go-error-handling    go-interfaces              │
│  go-testing           go-project-structure       │
│  go-concurrency       go-solid-patterns          │
│  go-http-handlers     go-database                │
├──────────────────────────────────────────────────┤
│  LIMITS                                          │
│  5 files / task    200 lines / task              │
│  Tests first       No deps without discussion    │
├──────────────────────────────────────────────────┤
│  COMMIT FORMAT                                   │
│  type(scope): description (10+ chars)            │
│  Co-authored-by: Claude <claude@anthropic.com>   │
└──────────────────────────────────────────────────┘
```
