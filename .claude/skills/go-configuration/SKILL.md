---
name: go-configuration
description: Go configuration patterns — single Config struct loaded once in main, env-var loading with validation and fail-fast on startup, no os.Getenv in internal packages, secrets never committed or logged, default values, test-friendly config construction. Load whenever env vars, config, secrets, or startup validation are involved.
---

# Skill: Go Configuration

> Claude reads this skill whenever configuration, environment variables,
> secrets, or startup wiring is involved. Follow these patterns exactly.

---

## Core Rule

**Load and validate configuration once in `main`. Pass values (or typed config
sub-structs) through constructor injection. Internal packages never read
environment variables.**

Configuration is an input like any other — it belongs to the composition root,
not scattered across `os.Getenv` calls throughout the codebase.

---

## Pattern 1: Single Config Struct at the Root

```go
// internal/platform/config/config.go

type Config struct {
    Env         string        // "local" | "staging" | "production"
    ListenAddr  string
    DatabaseURL string
    LogLevel    slog.Level
    HTTPTimeout time.Duration
    Stripe      StripeConfig  // sub-structs for related settings
}

type StripeConfig struct {
    APIKey        string
    WebhookSecret string
}

// Load reads env vars and returns a validated Config or an error.
func Load() (Config, error) {
    cfg := Config{
        Env:         getEnv("APP_ENV", "local"),
        ListenAddr:  getEnv("LISTEN_ADDR", ":8080"),
        DatabaseURL: os.Getenv("DATABASE_URL"),
        HTTPTimeout: 30 * time.Second,
        Stripe: StripeConfig{
            APIKey:        os.Getenv("STRIPE_API_KEY"),
            WebhookSecret: os.Getenv("STRIPE_WEBHOOK_SECRET"),
        },
    }

    level, err := parseLogLevel(getEnv("LOG_LEVEL", "info"))
    if err != nil {
        return Config{}, fmt.Errorf("parsing LOG_LEVEL: %w", err)
    }
    cfg.LogLevel = level

    if err := cfg.Validate(); err != nil {
        return Config{}, fmt.Errorf("invalid config: %w", err)
    }
    return cfg, nil
}

func getEnv(key, def string) string {
    if v := os.Getenv(key); v != "" {
        return v
    }
    return def
}
```

**Teaching point**: Keep `Load()` boring — read strings, parse them, return a
struct. Don't call external services, don't log (the logger doesn't exist yet),
don't retry. Failing here means the process can't start, and that's fine.

---

## Pattern 2: Validate on Startup, Fail Fast

```go
func (c Config) Validate() error {
    var errs []error

    if c.DatabaseURL == "" {
        errs = append(errs, errors.New("DATABASE_URL is required"))
    }
    if c.Stripe.APIKey == "" && c.Env != "local" {
        errs = append(errs, errors.New("STRIPE_API_KEY is required outside local env"))
    }
    if !strings.HasPrefix(c.ListenAddr, ":") {
        errs = append(errs, fmt.Errorf("LISTEN_ADDR must start with :, got %q", c.ListenAddr))
    }
    if c.HTTPTimeout <= 0 {
        errs = append(errs, errors.New("HTTPTimeout must be positive"))
    }

    return errors.Join(errs...)
}
```

**Teaching point**: Validate EVERYTHING at startup so the process either boots
correctly or refuses to boot. A missing env var discovered at 3 a.m. during a
rollout is a much worse outage than a clear error message on startup. Collect
all errors (via `errors.Join`) so an operator sees every problem at once, not
one per redeploy.

---

## Pattern 3: Load Once, Inject Everywhere

```go
// cmd/myservice/main.go

func main() {
    cfg, err := config.Load()
    if err != nil {
        fmt.Fprintf(os.Stderr, "config error: %v\n", err)
        os.Exit(1)
    }

    logger := newLogger(cfg)
    db := mustConnectDB(cfg.DatabaseURL)

    // Pass primitive fields OR a relevant sub-struct — NEVER the whole Config.
    userStore := user.NewPostgresStore(db)
    stripeClient := stripe.NewClient(cfg.Stripe)
    orderService := order.NewService(userStore, stripeClient, logger)

    srv := &http.Server{
        Addr:        cfg.ListenAddr,
        Handler:     router,
        ReadTimeout: cfg.HTTPTimeout,
    }
    // ...
}
```

**Teaching point**: Never pass the whole `Config` into a service. A user service
doesn't need to know about Stripe keys. Pass only what each component needs —
this keeps blast radius small and makes dependencies explicit.

---

## Pattern 4: No os.Getenv Outside main and platform/config

```go
// ❌ BAD — hidden dependency on environment
// internal/user/service.go
func (s *Service) SendWelcome(user User) error {
    from := os.Getenv("SMTP_FROM")  // this service is now untestable
    // ...
}

// ✅ GOOD — configured at construction time
type Service struct {
    store    UserStore
    mailer   Mailer
    fromAddr string
}

func NewService(store UserStore, mailer Mailer, fromAddr string) *Service {
    return &Service{store: store, mailer: mailer, fromAddr: fromAddr}
}
```

**Teaching point**: A `grep -r "os.Getenv" internal/` should return zero hits.
If you find one, that's a refactor: move the read to `config.Load()`, add a field,
thread it through the constructor.

---

## Pattern 5: Secrets Discipline

```go
// ❌ NEVER do any of these

// Checked-in defaults
const defaultAPIKey = "sk_live_abcd1234..."

// Logged at startup
logger.Info("config loaded", "stripe_key", cfg.Stripe.APIKey)

// Stringer/String() methods that expose secrets
func (c Config) String() string {
    return fmt.Sprintf("%+v", c)  // %+v prints every field including secrets
}

// Error messages with secrets
return fmt.Errorf("auth failed with key %s", apiKey)
```

```go
// ✅ DO

// Load from env only
cfg.Stripe.APIKey = os.Getenv("STRIPE_API_KEY")

// Log the shape, never the value
logger.Info("stripe configured", "key_present", cfg.Stripe.APIKey != "")

// Redact when formatting
func (c Config) String() string {
    redacted := c
    redacted.Stripe.APIKey = redact(c.Stripe.APIKey)
    redacted.Stripe.WebhookSecret = redact(c.Stripe.WebhookSecret)
    return fmt.Sprintf("%+v", redacted)
}

func redact(s string) string {
    if len(s) <= 4 {
        return "****"
    }
    return s[:4] + "****"
}
```

**Teaching point**: See also `go-logging/SKILL.md` Pattern 7. Anything labeled
`*_KEY`, `*_SECRET`, `*_TOKEN`, `*_PASSWORD`, `*_URL` (if it contains credentials)
is radioactive. Default to assuming every log ends up in five places.

---

## Pattern 6: Defaults via Explicit Fallback

```go
// ✅ Explicit getEnv helper with defaults (see Pattern 1)
ListenAddr: getEnv("LISTEN_ADDR", ":8080"),

// ✅ Zero-value defaults — let the struct literal state the default
type Config struct {
    HTTPTimeout time.Duration  // set to 30s explicitly in Load, not via env default
}

// ❌ BAD — silent defaults buried in constructors
func NewService(timeout time.Duration) *Service {
    if timeout == 0 {
        timeout = 30 * time.Second  // caller has no idea this fallback exists
    }
    return &Service{timeout: timeout}
}
```

**Teaching point**: Put defaults in ONE place: `config.Load()`. That way an
operator can read `Load()` and see every knob and its default. Hiding defaults
in each constructor makes it impossible to audit what the service will actually do.

---

## Pattern 7: Testable Config Construction

```go
// Tests build a Config directly — they don't parse env vars
func TestService_Charge(t *testing.T) {
    cfg := stripe.Config{
        APIKey:        "sk_test_dummy",
        WebhookSecret: "whsec_test",
    }
    client := stripe.NewClient(cfg)
    // ...
}

// Load() itself is tested with an env fixture
func TestLoad_MissingDatabaseURL(t *testing.T) {
    t.Setenv("APP_ENV", "production")
    t.Setenv("DATABASE_URL", "")  // empty, should fail validation

    _, err := config.Load()
    if err == nil {
        t.Fatal("expected validation error, got nil")
    }
    if !strings.Contains(err.Error(), "DATABASE_URL") {
        t.Errorf("error should mention DATABASE_URL, got: %v", err)
    }
}
```

**Teaching point**: `t.Setenv` (Go 1.17+) sets an env var for the duration of
the test and restores it afterwards. Use it instead of `os.Setenv`, which leaks
state across tests.

---

## Anti-Patterns to Flag

```go
// ❌ Reading env vars outside config package
// internal/user/service.go
retries := os.Getenv("USER_SERVICE_RETRIES")

// ❌ init() that reads env and panics
func init() {
    db, _ = sql.Open("postgres", os.Getenv("DATABASE_URL"))
}

// ❌ Passing the whole Config everywhere
func NewService(cfg Config) *Service  // service now depends on ALL of config

// ❌ Secrets in code, fixtures, test files, or default struct tags
type Config struct {
    APIKey string `default:"sk_live_..."`
}

// ❌ Reading env lazily on first call (hides missing config)
func (s *Service) lazyLoad() {
    if s.apiKey == "" {
        s.apiKey = os.Getenv("API_KEY")  // fails at request time, not startup
    }
}

// ❌ Silent string-to-enum conversion
level := os.Getenv("LOG_LEVEL")  // "INFO" vs "info" vs "Info" all accepted or all rejected?
// ✅ Parse and validate in Load(), return a typed field.
```

---

## Teaching Progression

1. **Week 1**: One `Config` struct in `internal/platform/config`. `Load()` in main.
   No `os.Getenv` anywhere else. Pass fields to constructors.
2. **Week 2**: `Validate()` with `errors.Join`. Fail the process on invalid config.
3. **Month 2**: Sub-structs for related settings (database, Stripe, auth). Pass
   only the relevant sub-struct to each component.
4. **Month 3**: Redacted `String()` methods; secret-shape logging (`key_present`).
5. **Later**: Config reload, feature flags, config from a secrets manager.
