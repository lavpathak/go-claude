# Claude AI Developer Guide

> Everything you need to know about using Claude Code.

---

## Table of Contents

1. [How This Setup Works](#how-this-setup-works)
2. [Quick Start](#quick-start)
3. [Operating Philosophy](#operating-philosophy)
4. [Engineer Modes](#engineer-modes)
5. [Skills vs Commands — The Two Systems](#skills-vs-commands)
6. [The Commands](#the-commands)
7. [The Skills](#the-skills)
8. [Guardrails Explained](#guardrails-explained)
9. [Workflow Examples](#workflow-examples)
10. [What Claude Will and Won't Do](#what-claude-will-and-wont-do)
11. [Troubleshooting](#troubleshooting)
12. [Growing With the System](#growing-with-the-system)

---

## How This Setup Works

This repo ships with a configured Claude Code environment. Here's the full file map:

```
CLAUDE.md                                ← Master rules. Claude reads this first.

.claude/
  settings.json                          ← Tool permissions (what Claude can/cannot run)
  hooks.json                             ← Automated checks during Claude sessions

  skills/                                ← PASSIVE: Claude reads these automatically
    go-error-handling/SKILL.md             Error patterns, wrapping, sentinel errors
    go-testing/SKILL.md                    Table-driven tests, helpers, mocking
    go-interfaces/SKILL.md                 Interface design, composition, naming
    go-project-structure/SKILL.md          Package layout, naming, file organization
    go-concurrency/SKILL.md                Goroutines, channels, sync, errgroup
    go-solid-patterns/SKILL.md             SOLID principles applied to Go
    go-http-handlers/SKILL.md              Handler structure, middleware, routing
    go-database/SKILL.md                   Repository pattern, queries, transactions
    go-context/SKILL.md                    context.Context propagation and cancellation
    go-logging/SKILL.md                    Structured logging with log/slog
    go-configuration/SKILL.md              Env vars, config loading, startup validation

  commands/                              ← ACTIVE: You trigger these with /command
    mode.md                                /mode — Switch engineer mode (beginner|senior|staff)
    pair.md                                /pair — Pair programming session
    tdd.md                                 /tdd — Test-driven development cycle
    review.md                              /review — Code review (tone follows mode)
    teach.md                               /teach — Learn a Go concept
    scope.md                               /scope — Break down a large task
    debug.md                               /debug — Guided debugging

  hooks/                                 ← Git hooks (installed by setup script)
    pre-commit.sh                          Blocks commits with >5 staged files,
                                            runs vet + tests, warns on unhandled
                                            errors and missing test files.
                                            Bypassable with `git commit --no-verify`.
    commit-msg.sh                          Enforces conventional commit format

.golangci.yml                            ← Linter config (errcheck, govet, staticcheck,
                                            gosec, revive, gocritic, more)
Makefile                                 ← make setup, test, lint, vet, fmt, check, diff
scripts/setup-claude-guardrails.sh       ← One-time setup (also runnable via `make setup`)
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
make setup                       # or: ./scripts/setup-claude-guardrails.sh

# 3. Start Claude
claude

# 4. (Optional) Pick a mode — defaults to beginner
/mode senior

# 5. Your first session
/pair I need to build a health check endpoint
```

`make setup` installs the git hooks, verifies that `go`, `golangci-lint`,
`gofumpt`, and `claude` are on your PATH, and confirms every required file
is in place.

---

## Operating Philosophy

Claude in this repo is a **collaborator**, not an autonomous coder. Every
interaction should leave you in a stronger position to own, extend, and
review the code than before.

### The Three Laws

These apply in every mode and override every other instruction.

1. **Match the mode.** In `beginner`, teach before doing. In `senior`,
   state the approach in a few bullets, get a quick agree-or-push-back,
   then execute. In `staff`, open with the design conversation —
   interfaces, failure modes, blast radius — before any code.
2. **Announce scope before acting.** Before edits, Claude lists the files
   it intends to touch and the rough shape of the change. If the work
   isn't reviewable in one sitting, it proposes a phase split via `/scope`
   instead of charging ahead.
3. **Tests come first.** No implementation code without a failing test.
   Red → Green → Refactor is mandatory in every mode. `staff` may
   spike-then-test for genuinely exploratory work, but a test gate must
   precede merge.

### Behavioral Rules

These hold regardless of mode:

- **Never refactor code you didn't ask Claude to touch**, even nearby and
  tempting. Out-of-scope changes belong in a separate task.
- **Never introduce a dependency without flagging it** — what it does, why
  stdlib isn't enough, the maintenance cost.
- **Always prefer readability over cleverness.**
- **Always include `Co-authored-by: Claude <claude@anthropic.com>`** in
  commit messages.
- **Never use `fmt.Println` for logging** — use the structured logger from
  `go-logging`.
- **Never leave a TODO without a linked issue.**
- **Never write code in files you didn't ask about.** Claude surfaces it
  and asks first.

### Pre-Commit Self-Check

Before presenting code, Claude verifies:

- [ ] Scope was announced before editing — files touched match what was
      proposed (or a deviation was called out)
- [ ] Every new function has a test
- [ ] Every error is handled (no `_ =` for errors)
- [ ] All exported identifiers have doc comments
- [ ] `go vet` and `golangci-lint` pass
- [ ] `beginner` mode: developer was walked through the approach
- [ ] `senior` / `staff` mode: change is reviewable in one sitting, or a
      phase plan exists

---

## Engineer Modes

The current mode lives in `CLAUDE.md` under the `## Engineer Mode` section
(`**Current mode: \`<value>\`**`). Default for new repos is `beginner`.
Switch with `/mode <beginner|senior|staff>`.

Mode never changes *what* Claude does — skills still apply, TDD is still
mandatory, scope is still announced. What changes is *how Claude paces,
explains, and scopes* its work.

| Mode | Default audience | Tone | Idiom explanations | Scope per task |
|---|---|---|---|---|
| `beginner` | New to Go, learning the codebase | Socratic, teaching-first | Always inline | Small, phased, frequent check-ins |
| `senior` | Comfortable in Go, owns features end-to-end | Peer, decisions-first | Only when non-obvious or risky | Whatever ships in one reviewable sitting |
| `staff` | Sets architecture and standards | Design-first, challenges assumptions | Skipped entirely | Phase plans + rollout/rollback considerations |

Today, three commands have explicit mode-specific sections in their
prompt files: `/pair`, `/tdd`, and `/review`. The other commands
(`/teach`, `/scope`, `/debug`) ship with a single protocol that does
not branch on mode — they will not, for example, become more terse in
`senior` mode automatically. If you want different pacing from those
commands, say so when invoking them.

---

## Skills vs Commands

The setup has two kinds of guidance for Claude. They behave differently
and exist for different reasons.

### Commands = You Drive

Commands are workflows **you** trigger explicitly by typing a slash command.
Claude follows a specific protocol when you invoke one.

```
You type:   /pair I need to add email validation
Claude:     Follows the pair programming protocol step by step
```

**You're in control.** The command doesn't activate unless you type it.

### Skills = Reference Material Claude Should Consult

Skills are markdown reference files in `.claude/skills/`. Claude Code
loads them into its context at session start, and CLAUDE.md tells Claude
to consult the matching skill whenever a relevant situation comes up
(error handling, testing, HTTP handlers, etc.). You don't invoke them
with a slash command.

```
You say:    "Let's write the error handling for this function"
Claude:     (consults go-error-handling/SKILL.md)
Claude:     "Let's use error wrapping with fmt.Errorf and the %w verb —
             that's our team's pattern. Here's how it looks for this case..."
```

**This is a behavioral expectation, not a hard guarantee.** Claude is
*directed* to apply the skill patterns every time, and in practice it
does so reliably — but it is not a runtime check. If Claude deviates
from a skill, point at the file (`go-error-handling/SKILL.md` says X)
and it will correct.

### Why Both?

| Situation | What Fires | Example |
|---|---|---|
| You want to start a structured workflow | **Command** | `/pair`, `/tdd`, `/scope` |
| Claude writes or reviews Go code | **Skill** (consulted in context) | Error handling, testing patterns |
| You want to learn something | **Command** triggers, **Skill** provides content | `/teach interfaces` references `go-interfaces/SKILL.md` |
| Claude reviews your code | **Command** triggers, **Skills** provide the rubric | `/review` checks against the patterns documented in the skills |

---

## The Commands

### `/mode [beginner|senior|staff]`

Switch how Claude paces, explains, and scopes its work. The Three Laws and
Skills System apply identically in every mode — only the *delivery* changes.

```
You:     /mode senior

Claude:  Mode set: senior.
         I'll skip Go idiom explanations, lead with the approach in one
         line, and expect a quick agree-or-push-back before I execute.
         Scope per task is whatever ships in one reviewable sitting.
```

| Mode | Tone | Idiom explanations | Scope per task |
|---|---|---|---|
| `beginner` | Socratic, teaching-first | Always inline | Small, phased, frequent check-ins |
| `senior` | Peer, decisions-first | Only when non-obvious | One reviewable sitting |
| `staff` | Design-first, challenges assumptions | Skipped entirely | Phase plans + rollout/rollback |

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

Skills are reference files Claude consults on its own as it works. You
don't need to invoke them. Understanding what each one contains helps
you predict what Claude will do — and lets you point at a specific file
when you want Claude to follow (or stop ignoring) a pattern.

### go-error-handling/SKILL.md
Covers error wrapping with `%w`, sentinel errors (`ErrNotFound`), custom error
types (`ValidationError`), the `errors.Is`/`errors.As` patterns, and the rule
about logging OR returning an error — never both.

### go-testing/SKILL.md
Covers table-driven tests (the team standard), test helpers with `t.Helper()`,
stub/fake patterns for dependency injection, testing HTTP handlers with
`httptest`, and the rule about building test cases incrementally.

### go-interfaces/SKILL.md
Covers consumer-side interface definition, keeping interfaces small (1-3 methods),
composition, the compile-time check trick (`var _ Interface = (*Type)(nil)`),
and naming conventions.

### go-project-structure/SKILL.md
Covers the standard layout (`cmd/`, `internal/`, `pkg/`), package naming rules,
the `internal/` visibility boundary, and the composition root pattern in `main.go`.

### go-concurrency/SKILL.md
Covers `errgroup` (preferred), `sync.WaitGroup`, `sync.Mutex`, worker pools,
graceful shutdown, and — critically — when NOT to use concurrency. This skill
gates concurrency introduction behind demonstrated need.

### go-solid-patterns/SKILL.md
Covers Single Responsibility, Open/Closed, Liskov Substitution, Interface
Segregation, and Dependency Inversion as they apply specifically to Go. Also
covers constructor injection, guard clauses, and avoiding package-level state.

### go-http-handlers/SKILL.md
Covers the 4-step handler structure (Parse → Validate → Execute → Respond),
response helpers, request/response type separation, middleware patterns, and
the rule that handlers contain zero business logic.

### go-database/SKILL.md
Covers the repository/store pattern, parameterized queries, transaction handling
with `defer tx.Rollback()`, connection pool configuration, and the rule that SQL
never appears in the service layer.

### go-context/SKILL.md
Covers the `context.Context` first-param convention, propagation through call
chains, `WithTimeout`/`WithDeadline`/`WithCancel` with deferred cancel,
`WithValue` with typed keys, and respecting cancellation in long operations.

### go-logging/SKILL.md
Covers structured logging with `log/slog`, key-value pairs over sprintf, log
levels, logger injection via constructor (no globals), PII/secret redaction,
correlation via context, and the log-OR-return rule.

### go-configuration/SKILL.md
Covers a single `Config` struct loaded once in `main`, env-var loading with
validation and fail-fast on startup, no `os.Getenv` in internal packages,
secrets never committed or logged, and test-friendly config construction.

---

## Guardrails Explained

### What's Enforced and How

| Guardrail | Mechanism | Can Be Overridden? |
|---|---|---|
| 5-file soft cap during a Claude session | `hooks.json` PostToolUse (warning only) | Warning only — Claude keeps going |
| 5-file hard cap at commit time | pre-commit hook (blocks if hooks installed) | `git commit --no-verify` |
| Max 200 lines new code | pre-commit hook (warning only) | Warning only |
| `go vet` clean before commit | pre-commit hook | `--no-verify` |
| All tests pass before commit | pre-commit hook (`go test ./... -count=1 -short`) | `--no-verify` |
| Auto `go vet` after Claude edits Go files | `hooks.json` PostToolUse | Edit `hooks.json` |
| TDD reminder when Go files change w/o tests | `hooks.json` PostResponse | Behavioral |
| Warn on possible unhandled errors | pre-commit hook (heuristic) | Warning only |
| Warn on new Go files missing `_test.go` | pre-commit hook | Warning only |
| Conventional commit format | commit-msg hook | `--no-verify` |
| `Co-authored-by: Claude` trailer | CLAUDE.md (behavioral) | Manual discipline |
| No dependency installs / network egress | `settings.json` deny list | Edit `settings.json` |
| No git push/commit/merge/rebase by Claude | `settings.json` deny list | Edit `settings.json` |
| Go idioms applied consistently | Skills (automatic) | Behavioral |

**About the 5-file rule.** It is a *soft* limit, not a hard one:

- During a session, Claude sees a warning each time more than 5 files
  are touched, but is not stopped from continuing.
- The pre-commit hook blocks commits with >5 *staged* files — but only
  if `make setup` has installed the hook into `.git/hooks/`, and only
  until someone runs `git commit --no-verify`.
- The hook counts staged files per-commit. Splitting a 12-file change
  into three commits of four files each will pass without complaint.

Treat it as a nudge toward smaller, reviewable changes — not a guarantee.

### What Claude Can Run Without Asking

Drawn from `.claude/settings.json` `permissions.allow`:

```
Read                                    (any file read)

go test ./...                           go fmt ./...
go test -race ./...                     gofumpt -w .
go test -v -run *                       git diff *
go vet ./...                            git status
golangci-lint run ./...                 git log *
go build ./...                          wc -l *
go mod tidy                             cat *, head *, tail *
                                        grep *, find *

make check    make test    make lint    make vet    make fmt
```

Anything outside that list triggers a permission prompt.

### What Claude Cannot Run

Drawn from `.claude/settings.json` `permissions.deny`:

```
go install *      git push *           curl *
go get *          git commit *         wget *
rm -rf *          git merge *          sudo *
                  git rebase *         docker *
                  git checkout -b *    kubectl *
```

You always commit, push, and create branches yourself.

### Conventional Commit Format

The `commit-msg` hook enforces this regex: the first line must match

```
^(feat|fix|test|refactor|docs|chore|build|ci|perf|style)\(.+\): .{10,}
```

Allowed types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`,
`build`, `ci`, `perf`, `style`. Description must be at least 10
characters. The `Co-authored-by: Claude <claude@anthropic.com>` trailer
is a behavioral rule from CLAUDE.md, not enforced by the hook.

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
         [Follows go-http-handlers/SKILL.md for handler structure]
         [Follows go-error-handling/SKILL.md for error wrapping]
         [Runs `make check` at the end]
```

### Example 2: "This test is failing and I don't know why"

```
You:     /debug TestProductSearch returns wrong results

Claude:  [Guides you through reproducing, hypothesizing, narrowing]
         [Uses go-testing/SKILL.md patterns to add a regression test]
         [Teaches you the debugging technique, not just the fix]
```

### Example 3: "What does this code do?"

```
You:     /teach What is this interface composition pattern I see in store.go?

Claude:  [References go-interfaces/SKILL.md, teaches composition]
         [Shows an example from your actual codebase]
         [Ends with a comprehension question]
```

---

## Same Task, Three Modes

The clearest way to feel the difference between modes is to see the same
request handled three ways. Mode never changes *what* Claude does — it
changes *how Claude narrates and paces* the work.

### Request: "Add a rate limiter to the login endpoint"

#### `beginner` mode

```
You:     Add a rate limiter to the login endpoint.

Claude:  Before we touch code, let me check you're set up for this. Rate
         limiting in Go is usually one of three things:
           1. A token bucket (golang.org/x/time/rate)
           2. A fixed window counter in Redis
           3. A leaky bucket via middleware

         Which one is right depends on whether you want per-IP or
         per-user limiting, and whether you have Redis available.

         Quick questions:
         - Per-IP or per-user?
         - Single instance or behind a load balancer?

You:     Per-IP, single instance for now.

Claude:  Good — that means option 1 (token bucket, in-memory) is the
         right call. It's stdlib-adjacent (golang.org/x/time/rate is the
         official extended stdlib) so no real dependency cost.

         Scope I'm proposing (3 files):
         - internal/middleware/ratelimit.go        (new)
         - internal/middleware/ratelimit_test.go   (new)
         - cmd/api/routes.go                       (wire it up)

         Before we start: rate.Limiter is concurrency-safe but the *map*
         of limiters per IP is not — we'll need a sync.RWMutex. I'll
         walk through that when we get there.

         Shall we start with the failing test?
```

#### `senior` mode

```
You:     Add a rate limiter to the login endpoint.

Claude:  Plan: token-bucket middleware via golang.org/x/time/rate, keyed
         by IP, sync.Map for the limiter cache, 5 req/min burst 10.
         Three files: middleware/ratelimit.go + test + routes.go wiring.

         Push back if you want per-user instead, or Redis-backed for
         multi-instance.

You:     Go.

Claude:  [Writes failing test → passes → wires it up → runs make check]
         [Calls out one non-obvious choice: "Used sync.Map over RWMutex
          + map because read-heavy access pattern."]
```

#### `staff` mode

```
You:     Add a rate limiter to the login endpoint.

Claude:  Before code, the design questions worth pinning down:

         1. Blast radius: in-memory limiter is fine for one instance,
            but the moment we add a second pod, an attacker gets
            N× the budget. If multi-instance is on the 6-month
            roadmap, build it Redis-backed now — the migration cost
            later is higher than the upfront complexity.

         2. Failure mode: what happens when the limiter store is
            unavailable? Fail-open (allow all) leaks the protection;
            fail-closed (deny all) turns a Redis blip into a full
            login outage. I'd default fail-open with a loud metric.

         3. Observability: this needs a counter (rejections by IP)
            and an alert. Without it, we won't know if the limiter
            is doing anything or if it's blocking real users.

         4. Bypass policy: do we exempt internal IPs / health checks?
            If yes, that exemption list is a config concern.

         My recommendation: in-memory token bucket *now*, behind an
         interface so the Redis swap is a one-file change later.
         Decide on fail-open vs fail-closed before I write a line.

         Which of those four do you want to nail down first?
```

Notice what's identical across modes: skills still apply, TDD is still
mandatory, scope is still announced, the same files get touched. What
changes is the *conversation*.

---

## More Examples by Mode

### `beginner` — Learning a concept while shipping

```
You:     /teach context cancellation

Claude:  Let me ground this in something you'll actually hit. Imagine a
         user opens your /search endpoint, then closes their browser tab
         halfway through. Without context, your handler keeps running:
         querying the DB, calling downstream services, burning CPU for
         a response no one will read.

         context.Context is Go's answer. Every blocking call (DB query,
         HTTP request, channel receive) takes a ctx, and when the
         request is cancelled, the ctx fires Done() and those calls
         return early.

         Three rules our team follows (from go-context/SKILL.md):
           1. ctx is always the first parameter.
           2. Never store ctx on a struct.
           3. Always defer cancel() when you create one with WithTimeout.

         Want to try it? Pick a function in our codebase that does a DB
         call and doesn't take ctx — we'll add it together as a real
         change.
```

### `senior` — Triaging a flaky test

```
You:     /debug TestProcessOrders is flaky in CI, passes locally.

Claude:  Three usual suspects for "passes local, flakes CI": time
         dependence, goroutine leak between tests, or shared state in
         a test container.

         Fastest signal: run it locally with -race -count=50.
         If it fails, it's a data race. If it passes, it's environmental.

         Want me to run that and report?

You:     Do it.

Claude:  [Runs go test -race -count=50 -run TestProcessOrders ./...]
         Hit it on iteration 17. DATA RACE on orderQueue.items —
         processor goroutine reads, test goroutine appends. Fix is a
         sync.Mutex on orderQueue or a channel-based handoff.

         Recommend the channel — it removes the shared state entirely
         instead of guarding it. Two files. Want me to write it?
```

### `staff` — Architecture review before code

```
You:     We need to add async job processing. Email sending, report
         generation, that kind of thing.

Claude:  Before a single line — the decisions worth making explicit:

         Delivery semantics: at-least-once is the only sane default
         for email/reports. That means idempotency is the consumer's
         job. Worth deciding now whether each job type carries a
         dedupe key or whether handlers must be naturally idempotent.

         Backing store: three real options.
           - Postgres + SELECT FOR UPDATE SKIP LOCKED. Zero new infra,
             fine to ~100 jobs/sec, dies past that.
           - Redis + Streams. Fast, but no durability guarantees
             unless you configure AOF, and ops cost goes up.
           - SQS / Cloud Tasks. Operationally cheapest, vendor lock-in,
             ~50ms latency floor.

         Given this team's current scale (single Postgres, no Redis in
         prod), Postgres-backed is the right call until it's not. The
         migration to a real queue later is bounded — one interface,
         one handler runtime.

         Failure mode I want to flag: if the worker crashes mid-job,
         at-least-once means the next worker re-runs it. That's
         catastrophic for "send email" without a dedupe key. Either
         we add an outbox table with a (job_id, handler) unique
         constraint, or we accept that users sometimes get two emails.

         Three things I need from you before designing the interface:
           1. Postgres-backed acceptable for v1?
           2. Idempotency: dedupe key per job, or handler-enforced?
           3. Acceptable latency floor — sub-second, or minutes okay?
```

---

## What Claude Will and Won't Do

These are the directives in `CLAUDE.md` and the command/skill files.
They describe what Claude is *instructed* to do — not hard-enforced
runtime behavior, except where a hook or permission is named.

### Will Do
- Announce scope (files it'll touch) before editing
- Write a failing test before any implementation code
- Follow the patterns in `.claude/skills/` when working in a relevant
  area (consults the file; not a runtime check — point at the file if
  you see a deviation)
- Break large tasks into ≤5-file phases via `/scope`
- Run `go vet`, `go test`, and `make check` after meaningful changes
- Adapt tone, idiom commentary, and pacing to the current `/mode`
  (in `/pair`, `/tdd`, and `/review`; other commands have a single
  protocol)
- Flag any new dependency with what it does, why stdlib isn't enough,
  and the maintenance cost
- Use `log/slog` for any logging (never `fmt.Println`)

### Won't Do
- Stage more than 5 files in one commit, *if* the pre-commit hook is
  installed (it blocks; bypassable with `--no-verify`)
- Generate entire packages in one shot
- Skip tests or write implementation before a failing test exists
- Refactor code outside the announced scope
- Add a dependency without flagging it first
- `git push`, `git commit`, `git merge`, `git rebase`, or
  `git checkout -b` (denied in `settings.json`)
- Run `go install`, `go get`, `curl`, `wget`, `sudo`, `docker`, or
  `kubectl` (denied)
- Leave a TODO without a linked issue
- Introduce concurrency without demonstrated need

---

## Troubleshooting

**"Claude won't write the whole function"**
By design. Say: "I tried X but I'm stuck on Y. Can you show me how to handle Y?"

**"Pre-commit hook blocking me"**
The hook can fail for four reasons: more than 5 staged files,
`go vet` errors, failing tests, or an invalid commit message format.
Run `make check` to reproduce the vet/test failures locally. Emergency
override: `git commit --no-verify` (skips both pre-commit and
commit-msg hooks).

**"I need to change more than 5 files"**
Use `/scope` to break it down. This is a feature — small changes are safer.

**"Claude keeps explaining things I already know"**
Tell it: "I understand error handling. Skip the explanation and let's write code."
Claude will adapt.

**"Commit message rejected"**
Format: `type(scope): description` with 10+ char description.
Allowed types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`,
`build`, `ci`, `perf`, `style`.
Example: `feat(user): add email validation with regex pattern`

**"Claude won't run a command I'd expect"**
Check `.claude/settings.json`. The allow list is exact-match with
specific arg patterns (e.g., `Bash(go test ./...)` allows that exact
form, not arbitrary `go test` invocations). Add the pattern you need.

---

## Growing With the System

The defaults shipped today are tuned for a team learning Go together.
Two real levers exist already:

1. **Engineer mode** (`/mode beginner|senior|staff`) — adjusts pacing,
   idiom explanations, and scope-per-task without changing any
   guardrails.
2. **Per-repo overrides** — change `.claude/settings.json` (allow/deny),
   `.claude/hooks/pre-commit.sh` (file/line limits), or
   `.claude/hooks.json` (Claude-session hooks) to fit your team.

### Suggested progression (not enforced)

These are recommendations, not phases the tooling tracks. Tune the files
above when the team is ready.

**Learning** (default today)
- 5 staged files / commit (pre-commit blocks), 200 lines / commit
  (pre-commit warns)
- Default mode `beginner`; skills are loaded for every session
- All dependencies discussed before adding

**Comfortable**
- Raise the file limit in `pre-commit.sh` and `hooks.json`
- Default mode `senior`
- Pre-approve common deps (e.g., `testify`, `chi`, `sqlx`) in CLAUDE.md
- Use Claude for targeted refactoring

**Proficient**
- Raise or remove the file limit
- Default mode `staff` for design-heavy work
- Use Claude for architecture discussions and `/scope` planning
- TDD requirement stays — it's the floor, not a phase

### How to relax a guardrail

1. Team discussion in retro.
2. Update the relevant file:
   - File/line limits → `.claude/hooks/pre-commit.sh` and the warning in
     `.claude/hooks.json`
   - Allowed/denied commands → `.claude/settings.json`
   - Behavioral rules → `CLAUDE.md`
   - Skill patterns → `.claude/skills/<skill>/SKILL.md`
3. Commit: `chore(guardrails): relax [rule] — [reason]`

---

## Quick Reference

```
┌──────────────────────────────────────────────────┐
│  COMMANDS (you trigger)                          │
│  /mode [b|s|st]   Switch engineer mode           │
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
│  go-context           go-logging                 │
│  go-configuration                                │
├──────────────────────────────────────────────────┤
│  LIMITS                                          │
│  5 files / task    200 lines / task              │
│  Tests first       No deps without discussion    │
├──────────────────────────────────────────────────┤
│  COMMIT FORMAT                                   │
│  type(scope): description (10+ chars)            │
│  Types: feat fix test refactor docs chore        │
│         build ci perf style                      │
│  Co-authored-by: Claude <claude@anthropic.com>   │
└──────────────────────────────────────────────────┘
```
