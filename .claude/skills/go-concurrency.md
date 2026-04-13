# Skill: Go Concurrency

> Claude reads this skill whenever goroutines, channels, mutexes, WaitGroups,
> or async patterns appear. Follow these patterns exactly.
>
> **CRITICAL**: This team is new to Go. Do NOT introduce concurrency unless
> there is a clear, justified need. Always ask: "Do you actually need concurrency
> here, or would sequential code be simpler and sufficient?"

---

## Core Rule

**Don't use goroutines until you can explain WHY sequential code is insufficient.**

Concurrency is not free. It introduces race conditions, deadlocks, and debugging
complexity. The team should exhaust sequential approaches first.

---

## When Concurrency IS Justified

- An HTTP server handling multiple requests (already handled by `net/http`)
- Waiting on multiple independent I/O operations (API calls, DB queries)
- Background tasks with a clear lifecycle (periodic cleanup, health checks)
- Fan-out/fan-in patterns where parallelism has measurable benefit

## When Concurrency is NOT Justified

- "It might be faster" without measurement
- Processing a slice of items sequentially is fast enough
- The function is CPU-bound and runs in milliseconds
- You're adding goroutines to a function that doesn't need to be async

---

## Pattern 1: errgroup for Parallel Tasks (Preferred)

This is the team's default pattern for running tasks concurrently.

```go
import "golang.org/x/sync/errgroup"

func (s *Service) EnrichOrder(ctx context.Context, order *Order) error {
    g, ctx := errgroup.WithContext(ctx)

    // Task 1: fetch user details
    var user User
    g.Go(func() error {
        var err error
        user, err = s.users.GetUser(ctx, order.UserID)
        if err != nil {
            return fmt.Errorf("getting user: %w", err)
        }
        return nil
    })

    // Task 2: fetch product details
    var product Product
    g.Go(func() error {
        var err error
        product, err = s.products.GetProduct(ctx, order.ProductID)
        if err != nil {
            return fmt.Errorf("getting product: %w", err)
        }
        return nil
    })

    // Wait for both. If either fails, ctx is cancelled and the error is returned.
    if err := g.Wait(); err != nil {
        return fmt.Errorf("enriching order: %w", err)
    }

    order.UserName = user.Name
    order.ProductName = product.Name
    return nil
}
```

**Teaching point**: `errgroup.WithContext` creates a derived context that's
cancelled when any goroutine returns an error. This means the other goroutine's
context is cancelled automatically — no manual cleanup. Always use this over
raw `sync.WaitGroup` when goroutines can fail.

---

## Pattern 2: sync.WaitGroup (When Errors Aren't Returned)

```go
func (s *Service) NotifyAll(ctx context.Context, userIDs []string, msg Message) {
    var wg sync.WaitGroup

    for _, id := range userIDs {
        wg.Add(1)
        go func(userID string) {
            defer wg.Done()
            if err := s.notifier.Send(ctx, userID, msg); err != nil {
                s.logger.Error("notification failed",
                    "user_id", userID,
                    "error", err,
                )
                // Log but don't fail — best-effort notifications
            }
        }(id)  // Pass id as argument to avoid closure capture bug
    }

    wg.Wait()
}
```

**Teaching point**: Note the `go func(userID string)` pattern — we pass `id`
as an argument instead of capturing it from the loop. Before Go 1.22, the loop
variable is shared across iterations, so all goroutines would see the last value.
In Go 1.22+, each iteration gets its own variable, but the explicit argument pattern
is still clearer and safer.

---

## Pattern 3: Worker Pool (Bounded Concurrency)

```go
func (s *Service) ProcessBatch(ctx context.Context, items []Item) error {
    g, ctx := errgroup.WithContext(ctx)
    g.SetLimit(5)  // maximum 5 concurrent workers

    for _, item := range items {
        item := item  // capture for goroutine (pre-Go 1.22)
        g.Go(func() error {
            return s.processItem(ctx, item)
        })
    }

    return g.Wait()
}
```

**Teaching point**: `g.SetLimit(5)` prevents spawning 10,000 goroutines for
10,000 items. Always bound concurrency when processing collections. Even though
goroutines are cheap, the work they do (DB queries, HTTP calls) has limits.

---

## Pattern 4: Protecting Shared State with Mutex

```go
type Cache struct {
    mu    sync.RWMutex  // RWMutex allows concurrent reads
    items map[string]Item
}

func NewCache() *Cache {
    return &Cache{items: make(map[string]Item)}
}

// Read: multiple goroutines can read simultaneously
func (c *Cache) Get(key string) (Item, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    item, ok := c.items[key]
    return item, ok
}

// Write: exclusive access, blocks all readers and writers
func (c *Cache) Set(key string, item Item) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.items[key] = item
}
```

**Teaching point**: Always use `defer` for unlocking. Without it, a panic or
early return leaves the mutex locked forever (deadlock). `sync.RWMutex` is
preferred over `sync.Mutex` when reads are much more frequent than writes.

---

## Pattern 5: Graceful Shutdown

```go
func main() {
    srv := &http.Server{Addr: ":8080", Handler: mux}

    // Start server in a goroutine
    go func() {
        if err := srv.ListenAndServe(); err != http.ErrServerClosed {
            log.Fatalf("server error: %v", err)
        }
    }()

    // Wait for interrupt signal
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, os.Interrupt, syscall.SIGTERM)
    <-quit  // blocks until signal received

    // Give in-flight requests 10 seconds to finish
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    if err := srv.Shutdown(ctx); err != nil {
        log.Fatalf("shutdown error: %v", err)
    }
    log.Println("server stopped cleanly")
}
```

---

## Anti-Patterns to Flag

```go
// ❌ Fire-and-forget goroutine (no way to know if it fails or finishes)
go processItem(item)

// ❌ Goroutine leak (no shutdown path)
go func() {
    for {
        doWork()
        time.Sleep(time.Second)
    }
}()

// ❌ Sharing state without synchronization
var count int
go func() { count++ }()  // RACE CONDITION
go func() { count++ }()

// ❌ Using channels AND mutexes for the same data
// Pick one. Channels for communication, mutexes for state protection.

// ❌ Unbounded goroutine creation
for _, item := range thousandItems {
    go process(item)  // spawns 1000 goroutines at once
}
// ✅ Use errgroup.SetLimit or a worker pool

// ❌ context.Background() inside a goroutine that should be cancellable
go func() {
    s.doWork(context.Background())  // won't respond to cancellation
}()
// ✅ Pass the parent context or a derived one
```

---

## Testing Concurrent Code

```go
// Use -race flag to detect race conditions
// go test -race ./...

// Use channels for synchronization in tests (not time.Sleep)
func TestConcurrentAccess(t *testing.T) {
    cache := NewCache()
    done := make(chan struct{})

    // Start writers
    go func() {
        defer close(done)
        for i := 0; i < 100; i++ {
            cache.Set(fmt.Sprintf("key-%d", i), Item{Value: i})
        }
    }()

    // Start readers (concurrent with writers)
    for i := 0; i < 10; i++ {
        go func() {
            for j := 0; j < 100; j++ {
                cache.Get(fmt.Sprintf("key-%d", j))
            }
        }()
    }

    <-done  // wait for writers to finish
    // If this test passes with -race, the Cache is safe
}
```

---

## Teaching Progression

1. **Month 1**: No concurrency. Sequential code only. Mention that `net/http`
   handles concurrency for you in handlers.
2. **Month 2**: Introduce `errgroup` for 2-3 parallel I/O operations.
3. **Month 3**: `sync.Mutex` for shared state, worker pools with `SetLimit`.
4. **Month 4+**: Channels for communication, graceful shutdown patterns.
5. **Never early**: Don't teach `select`, `context.WithCancel`, or channels
   until the developer has a concrete problem that needs them.
