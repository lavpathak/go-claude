# Skill: Go HTTP Handlers

> Claude reads this skill whenever HTTP endpoints, middleware, routing, or
> request/response handling is involved. Follow these patterns exactly.

---

## Core Rule

**Handlers translate HTTP into domain calls and domain results back into HTTP.
They contain zero business logic.**

A handler's job: parse request → call service → write response. Nothing else.

---

## Pattern 1: Handler Struct with Dependency Injection

```go
type Handler struct {
    service *user.Service
    logger  *slog.Logger
}

func NewHandler(service *user.Service, logger *slog.Logger) *Handler {
    return &Handler{service: service, logger: logger}
}

// Register routes on a mux — keeps routing in one place
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
    mux.HandleFunc("GET /users/{id}", h.handleGetUser)
    mux.HandleFunc("POST /users", h.handleCreateUser)
    mux.HandleFunc("PUT /users/{id}", h.handleUpdateUser)
    mux.HandleFunc("DELETE /users/{id}", h.handleDeleteUser)
}
```

**Teaching point**: Go 1.22+ supports method and path patterns directly in
`http.ServeMux`. No external router needed for most APIs. The `{id}` syntax
extracts path parameters via `r.PathValue("id")`.

---

## Pattern 2: Standard Handler Structure

Every handler follows this 4-step structure:

```go
func (h *Handler) handleCreateUser(w http.ResponseWriter, r *http.Request) {
    // Step 1: PARSE — extract and decode input
    var input CreateUserRequest
    if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
        h.respondError(w, "invalid request body", http.StatusBadRequest)
        return
    }

    // Step 2: VALIDATE — check input before passing to service
    if err := input.Validate(); err != nil {
        h.respondError(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Step 3: EXECUTE — call the service (the only line with business logic)
    user, err := h.service.CreateUser(r.Context(), input.toServiceInput())
    if err != nil {
        h.handleServiceError(w, err)
        return
    }

    // Step 4: RESPOND — encode the result
    h.respondJSON(w, http.StatusCreated, user)
}
```

---

## Pattern 3: Response Helpers

Consistent response helpers prevent duplicate code across handlers.

```go
func (h *Handler) respondJSON(w http.ResponseWriter, status int, data any) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(status)
    if err := json.NewEncoder(w).Encode(data); err != nil {
        h.logger.Error("encoding response", "error", err)
    }
}

func (h *Handler) respondError(w http.ResponseWriter, message string, status int) {
    h.respondJSON(w, status, map[string]string{"error": message})
}

// Map domain errors to HTTP status codes — centralized, consistent
func (h *Handler) handleServiceError(w http.ResponseWriter, err error) {
    switch {
    case errors.Is(err, domain.ErrNotFound):
        h.respondError(w, "resource not found", http.StatusNotFound)
    case errors.Is(err, domain.ErrConflict):
        h.respondError(w, "resource already exists", http.StatusConflict)
    case errors.Is(err, domain.ErrUnauthorized):
        h.respondError(w, "unauthorized", http.StatusUnauthorized)
    default:
        // Unknown error — log details, don't expose to client
        h.logger.Error("internal error", "error", err)
        h.respondError(w, "internal server error", http.StatusInternalServerError)
    }
}
```

---

## Pattern 4: Request/Response Types

Define explicit types for HTTP requests and responses. Keep them separate from
domain types.

```go
// Request type — what the client sends (may include fields you don't store)
type CreateUserRequest struct {
    Name     string `json:"name"`
    Email    string `json:"email"`
    Password string `json:"password"`
}

func (r CreateUserRequest) Validate() error {
    var errs []error
    if r.Name == "" {
        errs = append(errs, errors.New("name is required"))
    }
    if r.Email == "" {
        errs = append(errs, errors.New("email is required"))
    }
    if len(r.Password) < 8 {
        errs = append(errs, errors.New("password must be at least 8 characters"))
    }
    return errors.Join(errs...)
}

// Convert to service-layer input (separates HTTP from domain)
func (r CreateUserRequest) toServiceInput() user.CreateInput {
    return user.CreateInput{
        Name:     r.Name,
        Email:    r.Email,
        Password: r.Password,
    }
}

// Response type — what the client receives (may omit sensitive fields)
type UserResponse struct {
    ID    string `json:"id"`
    Name  string `json:"name"`
    Email string `json:"email"`
    // Note: no password field in response
}

func toUserResponse(u user.User) UserResponse {
    return UserResponse{
        ID:    u.ID,
        Name:  u.Name,
        Email: u.Email,
    }
}
```

---

## Pattern 5: Middleware

```go
// Middleware signature: takes a handler, returns a handler
type Middleware func(http.Handler) http.Handler

// Logging middleware
func LoggingMiddleware(logger *slog.Logger) Middleware {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            start := time.Now()

            // Wrap ResponseWriter to capture status code
            wrapped := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
            next.ServeHTTP(wrapped, r)

            logger.Info("request",
                "method", r.Method,
                "path", r.URL.Path,
                "status", wrapped.status,
                "duration", time.Since(start),
            )
        })
    }
}

type statusRecorder struct {
    http.ResponseWriter
    status int
}

func (r *statusRecorder) WriteHeader(status int) {
    r.status = status
    r.ResponseWriter.WriteHeader(status)
}

// Request ID middleware
func RequestIDMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        id := r.Header.Get("X-Request-ID")
        if id == "" {
            id = uuid.New().String()
        }
        ctx := context.WithValue(r.Context(), requestIDKey, id)
        w.Header().Set("X-Request-ID", id)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}

// Chain middleware (applied inside out — last added runs first)
func Chain(handler http.Handler, middlewares ...Middleware) http.Handler {
    for i := len(middlewares) - 1; i >= 0; i-- {
        handler = middlewares[i](handler)
    }
    return handler
}

// Usage in main.go
mux := http.NewServeMux()
userHandler.RegisterRoutes(mux)

handler := Chain(mux,
    RequestIDMiddleware,
    LoggingMiddleware(logger),
)

srv := &http.Server{Addr: ":8080", Handler: handler}
```

---

## Pattern 6: Path Parameters and Query Params

```go
func (h *Handler) handleGetUser(w http.ResponseWriter, r *http.Request) {
    // Path parameter (Go 1.22+)
    id := r.PathValue("id")
    if id == "" {
        h.respondError(w, "missing user id", http.StatusBadRequest)
        return
    }

    user, err := h.service.GetUser(r.Context(), id)
    if err != nil {
        h.handleServiceError(w, err)
        return
    }

    h.respondJSON(w, http.StatusOK, toUserResponse(user))
}

func (h *Handler) handleListUsers(w http.ResponseWriter, r *http.Request) {
    // Query parameters
    page, _ := strconv.Atoi(r.URL.Query().Get("page"))
    if page < 1 {
        page = 1
    }
    limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
    if limit < 1 || limit > 100 {
        limit = 20  // sensible default
    }

    users, err := h.service.ListUsers(r.Context(), page, limit)
    if err != nil {
        h.handleServiceError(w, err)
        return
    }

    h.respondJSON(w, http.StatusOK, users)
}
```

---

## Testing HTTP Handlers

```go
func TestHandler_CreateUser(t *testing.T) {
    tests := []struct {
        name       string
        body       string
        wantStatus int
    }{
        {
            name:       "valid user returns 201",
            body:       `{"name":"Alice","email":"alice@test.com","password":"secret123"}`,
            wantStatus: http.StatusCreated,
        },
        {
            name:       "missing email returns 400",
            body:       `{"name":"Alice","password":"secret123"}`,
            wantStatus: http.StatusBadRequest,
        },
        {
            name:       "invalid json returns 400",
            body:       `not json`,
            wantStatus: http.StatusBadRequest,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // Arrange
            store := &StubUserStore{users: map[string]user.User{}}
            svc := user.NewService(store)
            handler := NewHandler(svc, slog.Default())

            req := httptest.NewRequest(http.MethodPost, "/users", strings.NewReader(tt.body))
            req.Header.Set("Content-Type", "application/json")
            rec := httptest.NewRecorder()

            // Act
            handler.handleCreateUser(rec, req)

            // Assert
            if rec.Code != tt.wantStatus {
                t.Errorf("status = %d, want %d", rec.Code, tt.wantStatus)
            }
        })
    }
}
```

---

## Anti-Patterns to Flag

```go
// ❌ Business logic in handler
func (h *Handler) handleCreateUser(w http.ResponseWriter, r *http.Request) {
    // ... parsing ...
    hash, _ := bcrypt.GenerateFromPassword(...)  // this belongs in service layer
    db.Exec("INSERT INTO users ...")              // this belongs in store layer
}

// ❌ Not using r.Context()
user, err := h.service.GetUser(context.Background(), id)
// ✅ Always propagate the request context
user, err := h.service.GetUser(r.Context(), id)

// ❌ Writing response after an error response
http.Error(w, "bad request", 400)
// missing return — the code below still runs!
json.NewEncoder(w).Encode(result)
// ✅ Always return after writing an error

// ❌ Not setting Content-Type
w.WriteHeader(200)
json.NewEncoder(w).Encode(data)  // client doesn't know it's JSON
```
