# Go — net/http

> **Series:** Go Language Fundamentals **Tags:** #go #golang #net-http #http #server #routing #middleware #cookies #json #tls #context #httptest #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. HTTP in One Picture]]
- [[#2. The Server — ListenAndServe, ServeMux, Handle]]
- [[#3. Handlers — The Interface & HandlerFunc]]
- [[#4. The Request — Method, URL, Header, Body, Form]]
- [[#5. The ResponseWriter — Header, WriteHeader, Write]]
- [[#6. Routing — stdlib mux vs gorilla/mux vs chi]]
- [[#7. Status Codes & the Redirect]]
- [[#8. Errors in Handlers]]
- [[#9. Middleware — Wrapping Handlers]]
- [[#10. JSON APIs — Encoding & Decoding Bodies]]
- [[#11. Cookies]]
- [[#12. The HTTP Client]]
- [[#13. TLS/HTTPS & Timeouts]]
- [[#14. Context & Cancellation]]
- [[#15. Testing HTTP Handlers — httptest]]
- [[#16. Quick Reference Cheatsheet]]

---

## 1. HTTP in One Picture

`net/http` is server + client in one package — `ListenAndServe` runs your app, `Get/Post` talks to others. Both share the same request/response model.

```
browser/curl                         server (your app)
  │  GET /expenses?from=2026-08-01     │
  │ ─────────────────────────────────► │ handle → SQL → HTML
  │  HTTP/1.1 200 OK                   │
  │ ◄───────────────────────────────── │
```

Request = method + path + headers + body. Response = status + headers + body. Go exposes decoded `*http.Request` and `http.ResponseWriter`.

> [!note] HTTP is text — handlers receive strings `"20000"` → `strconv.ParseInt` [[18 - Standard Library]] §6. Each request runs in its own goroutine [[12 - Goroutines]] §net/http → protect shared state with [[15 - Sync Primitives]].

---

## 2. The Server — ListenAndServe, ServeMux, Handle

```go
log.Fatal(http.ListenAndServe(":8080", mux)) // blocks forever; return = dead server
```

- `":8080"` = `host:port` (`":0"` = random port, `""` = all interfaces)
- `mux` = router implementing `Handler`

```go
mux := http.NewServeMux()
mux.Handle("/expenses", h)                                    // Handler interface
mux.HandleFunc("/hello", func(w http.ResponseWriter, r *http.Request) {...}) // function
```

`HandleFunc` is `Handle` plus `HandlerFunc` conversion (§3).

```go
srv := &http.Server{
    Addr: ":8080",
    Handler: mux,
    ReadTimeout: 10 * time.Second,
    WriteTimeout: 10 * time.Second,
}
log.Fatal(srv.ListenAndServe()) // same as ListenAndServe, with timeout knobs (§13)
```

---

## 3. Handlers — The Interface & HandlerFunc

Single interface for the whole package:

```go
type Handler interface { ServeHTTP(w http.ResponseWriter, r *http.Request) }
```

`*http.ServeMux` implements it — why `ListenAndServe(":8080", mux)` compiles.

**Function adapter:**

```go
type HandlerFunc func(w http.ResponseWriter, r *http.Request)
func (f HandlerFunc) ServeHTTP(w http.ResponseWriter, r *http.Request) { f(w, r) }
```

Any `func(w, r)` becomes a `Handler` via cast. `mux.HandleFunc` does this cast for you.

**Factory — handler with dependencies (your `store` shape):**

```go
func AddExpense(st *store.Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        st.Add(...) // st closed over
        http.Redirect(w, r, "/expenses", http.StatusSeeOther)
    }
}
```

`ServeHTTP` only gives `w,r` — factory closes over `st`, `cfg`, logger. Handlers with no deps are plain functions.

> [!tip] `http.HandlerFunc` and `http.Handler` are the most repeated types in Go web code — `echo/gin/chi` all implement the same `ServeHTTP`.

---

## 4. The Request — Method, URL, Header, Body, Form

```go
r.Method                    // "GET", "POST", "PUT", "DELETE"
r.URL.Path                  // "/expenses"
r.URL.RawQuery              // "from=2026-08-01&to=2026-08-31"
r.URL.Query().Get("from")   // "2026-08-01" — parsed
r.PathValue("id")           // wildcard Go 1.22+ — always string
r.Header.Get("Content-Type")
r.Body                      // io.ReadCloser — stream, read once
r.FormValue("amount")       // query OR body — workhorse, always string
r.PostFormValue("amount")   // body only — when query and body share name
r.FormFile("cheque")        // uploaded file → (File, *FileHeader, err)
r.Context()                 // cancelled on disconnect (§14)
r.RemoteAddr                // "127.0.0.1:52341"
```

| Source    | Example                          | Read                         |
| --------- | -------------------------------- | ---------------------------- |
| URL query | `/expenses?from=2026-08-01`      | `r.URL.Query().Get("from")`  |
| Wildcard  | `/expenses/7`                    | `r.PathValue("id")`          |
| Form body | `description=bread&amount=10000` | `r.FormValue("description")` |
| File      | multipart cheque PDF             | `r.FormFile("cheque")`       |

- `r.FormValue` calls `r.ParseForm()` internally, merges `r.Form` + `r.PostForm`, returns first hit.
- `r.Body` vs `FormValue` — read one, not both. Once `Body` consumed, `FormValue` sees `""`. JSON uses `r.Body` (§10), forms use `FormValue`.

> [!warning] `FormValue` on file-upload returns `""` — files come via `FormFile` only. `r.Header` is case-insensitive — `r.Header.Get("content-type")` works.

---

## 5. The ResponseWriter — Header, WriteHeader, Write

```go
type ResponseWriter interface {
    Header() http.Header        // response headers — set BEFORE Write
    Write([]byte) (int, error)  // body — also io.Writer
    WriteHeader(int)            // status — implicit 200 if never called
}
```

1. `Write` = body. Because it’s `io.Writer`, `fmt.Fprintln(w, ...)`, `tmpl.Execute(w, data)`, `io.Copy(w, file)` all work with no adapter [[18 - Standard Library]] §3.
2. `Header().Set` before `Write` — after first `Write` headers frozen.
3. No `WriteHeader` = `200 OK` at first `Write`. Call `WriteHeader(404)` *before* `Write`.

```go
w.Header().Set("Content-Type", "text/html; charset=utf-8")
w.WriteHeader(http.StatusNotFound)
fmt.Fprintln(w, "not found")
```

Go sniffs `Content-Type` via `http.DetectContentType` if you don’t set it — ok for HTML, but for JSON set `application/json` explicitly (§10).

> [!warning] `Write` before `WriteHeader(500)` keeps `200` and logs `superfluous WriteHeader`. Your mutation handlers avoid this by redirecting — they never `Write` (§7).

---

## 6. Routing — stdlib mux vs gorilla/mux vs chi

**Stdlib `ServeMux` (Go 1.22+):**

```go
mux.HandleFunc("GET /expenses", web.ListPage(st))
mux.HandleFunc("POST /expenses/add", web.AddExpense(st))
mux.HandleFunc("GET /expenses/{id}", handler)
id := r.PathValue("id") // "7" — always string, ParseInt yourself
```

- `GET /expenses` ≠ `POST /expenses` → `405 Method Not Allowed`, not `404`
- Precedence: most specific wins — `/expenses/7` > `/expenses/{id}` > `/expenses/` (catch-all)
- `/expenses` exact, `/expenses/` = subtree `"/expenses/*"`
- Pre-1.22 `"/expenses"` matched any method — your `GET /expense/add` vs `POST /expenses/add` bug `02 - Journal.md:40`

**Third-party routers** — same `http.Handler` interface, drop into `ListenAndServe` unchanged:

| Router | Pattern | Wildcard + Middleware | Why pick |
|---|---|---|---|
| **stdlib `ServeMux`** | `"GET /expenses"` | `{id}` + `r.PathValue("id")` | Zero deps — most apps never outgrow |
| `gorilla/mux` | `r.HandleFunc("/a/{id:[0-9]+}").Methods("GET")` | Regex `{id:[0-9]+}`, `r.PathPrefix("/api").Subrouter()` | Classic, route-level chaining, archived now |
| `chi` | `r.Get("/expenses/{id}", h)` + `r.Use(middleware.Logger)` | `chi.URLParam(r, "id")` + `r.Route("/api", fn)` grouping | Idiomatic stdlib-style, popular modern default |

```go
// gorilla/mux
r := mux.NewRouter()
r.HandleFunc("/expenses/{id:[0-9]+}", handler).Methods("GET")
api := r.PathPrefix("/api").Subrouter()
api.Use(authMiddleware)

// chi
r := chi.NewRouter()
r.Use(middleware.Logger)
r.Get("/expenses/{id}", handler)
id := chi.URLParam(r, "id")
r.Route("/notes", func(r chi.Router) {
    r.Use(RequireAuth)
    r.Post("/add", CreateNote)
})
```

> [!tip] Start stdlib. Add `chi` when `r.Route` grouping saves 10+ manual `RequireAuth(handler)` wraps.

---

## 7. Status Codes & the Redirect

| Code | Name | Meaning |
|---|---|---|
| 200 OK | success |
| 201 Created | POST added resource |
| 204 No Content | success, no body |
| 301 Moved Permanently | URL forever (browser caches) |
| 303 See Other | `Redirect` — `GET` the target |
| 400 Bad Request | bad `amount` |
| 401 Unauthorized | not logged in |
| 403 Forbidden | logged in, not allowed |
| 404 Not Found | no route |
| 405 Method Not Allowed | wrong method |
| 500 Internal Server Error | SQL failed |
| 429 Too Many Requests | rate limit (§9) |

**Every mutation ends with 303:**

```go
http.Redirect(w, r, "/expenses", http.StatusSeeOther) // Location + 303 → browser GETs /expenses
```

`POST → 303 → GET` = F5 safe. Without it, refresh re-POSTs and re-inserts (duplicate-bread). 301 is cached forever — wrong for post-action redirect. Always use named constants `http.StatusSeeOther`, not `303`.

> [!warning] `Redirect` writes `Location` + status and nothing else. Any `w.Write` before it has already sent `200` — redirect fails silently.

---

## 8. Errors in Handlers

`ServeHTTP` returns nothing — you must write the error response:

```go
if err != nil {
    fmt.Println("failed to list:", err)                   // log: real err [[11 - Error Handling]] §5
    http.Error(w, "oops", http.StatusInternalServerError) // client: generic — don't leak table names
    return                                                // always return
}
```

`http.Error` = `WriteHeader + Write` in one call. Never return without writing — client hangs on empty `200` (your `Delete` `return` without `http.Error` bug).

---

## 9. Middleware — Wrapping Handlers

Takes a handler, returns a handler with extra behavior:

```go
func logRequests(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        fmt.Printf("%s %s in %v\n", r.Method, r.URL.Path, time.Since(start))
    })
}
mux.Handle("GET /expenses", logRequests(requireAuth(http.HandlerFunc(web.ListPage(st)))))
// request → log → auth → handler → back out (onion)
```

**Around vs Gate:**

```go
// Around — runs before + after
func logging(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        slog.Info("request", "method", r.Method, "path", r.URL.Path, "dur", time.Since(start))
    })
}

// Gate — returns without next (auth, CORS preflight, rate limit)
func requireAuth(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !isLoggedIn(r) { // r.Cookie("session") §11
            http.Redirect(w, r, "/login", http.StatusSeeOther)
            return // never calls next — request refused
        }
        next.ServeHTTP(w, r)
    })
}

func cors(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusNoContent); return
        }
        next.ServeHTTP(w, r)
    })
}

func rateLimit(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if tooMany(r.RemoteAddr) {
            http.Error(w, "slow down", http.StatusTooManyRequests); return
        }
        next.ServeHTTP(w, r)
    })
}
```

> [!tip] Factory `AddExpense(st)` *creates* with state; middleware *wraps* with behavior — both are `func → Handler` `04 - Functions.md:617`.

---

## 10. JSON APIs — Encoding & Decoding Bodies

```go
type AddReq struct { Description string `json:"description"`; Amount int64 `json:"amount"` }

// Decode (read JSON body)
var req AddReq
if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
    http.Error(w, "bad json", http.StatusBadRequest); return
}

// Encode (write JSON body)
w.Header().Set("Content-Type", "application/json")
w.WriteHeader(http.StatusCreated)
json.NewEncoder(w).Encode(result) // adds trailing \n
```

`json.Marshal/Unmarshal` on `[]byte`:

```go
data, _ := json.Marshal(result) // struct → []byte
w.Write(data)
var req AddReq; body, _ := io.ReadAll(r.Body); json.Unmarshal(body, &req)
```

`Encoder/Decoder` stream via `r.Body`/`w` (no extra buffer), `Marshal/Unmarshal` buffer in memory — pick by size. Tags case-sensitive (`json:"amount"` ≠ `Amount`), unexported fields silently `→ {}` — verify on wire.

> [!note] Full JSON reference: `20 - encoding/json` — tags `json:"name,omitempty"`, `json:"-"`, `json.RawMessage`, custom `MarshalJSON`.

---

## 11. Cookies

Stateless HTTP → cookies persist identity across requests.

```go
// SET — on login
http.SetCookie(w, &http.Cookie{
    Name: "session", Value: "abc123", Path: "/", HttpOnly: true,
    SameSite: http.SameSiteLaxMode, MaxAge: 3600, // or Expires
})

// READ — on protected route
c, err := r.Cookie("session") // *http.Cookie or err
if err == http.ErrNoCookie {
    http.Redirect(w, r, "/login", http.StatusSeeOther); return
}
fmt.Println(c.Value) // "abc123"
```

- `HttpOnly` — JS cannot read via `document.cookie` (XSS protection) — set on every auth cookie
- `Secure` — HTTPS only (prod)
- `SameSite` — `Lax` (default, CSRF defense) / `Strict` / `None` (requires `Secure`) — core CSRF defense plus `POST` rule (§7)

Auth middleware `r.Cookie("session") → DB → r.WithContext → next` (§14). Flash: set on failed POST, read+delete (`MaxAge:-1`) on next `GET` — one-time banner.

---

## 12. The HTTP Client

```go
resp, err := http.Get("https://example.com")
if err != nil { ... }
defer resp.Body.Close() // ALWAYS — leaks connection otherwise (twin of defer rows.Close())
fmt.Println(resp.StatusCode) // 200
body, _ := io.ReadAll(resp.Body)
```

One-liners:

```go
http.Get(url)
http.Post(url, "application/json", body) // body io.Reader
http.PostForm(url, url.Values{"a": {"b"}})
http.Head(url) // headers only
```

Full control:

```go
req, _ := http.NewRequest("POST", "http://localhost:8080/expenses/add",
    strings.NewReader("description=bread&amount=10000"))
req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
client := &http.Client{Timeout: 5*time.Second} // default client has NO timeout — hangs forever
resp, _ := client.Do(req)
```

`NewRequest` = build, `Do` = send. Always set `Client{Timeout}` for real code. Transport `MaxIdleConns`, `IdleConnTimeout`, `TLSClientConfig` for tuning.

---

## 13. TLS/HTTPS & Timeouts

**TLS:**

```go
log.Fatal(http.ListenAndServeTLS(":443", "server.crt", "server.key", mux))
srv := &http.Server{Addr: ":443", Handler: mux}
log.Fatal(srv.ListenAndServeTLS("server.crt", "server.key"))
```

`server.crt` (public) + `server.key` (private) from Let’s Encrypt or self-signed `openssl req -x509 -newkey rsa:2048` (browser warns untrusted for self-signed). `http.Server` enables HTTP/2 under TLS automatically.

Redirect HTTP → HTTPS:

```go
http.ListenAndServe(":80", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    http.Redirect(w, r, "https://"+r.Host+r.URL.RequestURI(), http.StatusMovedPermanently)
}))
```

**Timeouts:**

| Timeout | Protects against | Typical |
|---|---|---|
| `ReadTimeout` / `ReadHeaderTimeout` | slow client holding connection | 5-10s |
| `WriteTimeout` | hanging handler | 10-30s |
| `IdleTimeout` | idle keep-alive squatters | 60-120s |
| `Client.Timeout` | dead peer on outgoing call | 5-10s |

```go
srv := &http.Server{
    Addr: ":8080", Handler: mux,
    ReadHeaderTimeout: 5*time.Second, ReadTimeout: 10*time.Second,
    WriteTimeout: 15*time.Second, IdleTimeout: 60*time.Second,
}
```

Without timeouts, one slow client holds a goroutine forever.

---

## 14. Context & Cancellation

Every request has a context cancelled on disconnect/timeout/shutdown:

```go
select {
case <-time.After(3*time.Second):
    fmt.Fprintln(w, "done")
case <-r.Context().Done(): // client left — abandon work
    return
}
rows, _ := s.db.QueryContext(r.Context(), `SELECT ...`, from, to) // DB cancels too
```

Storing auth user:

```go
type ctxKey string; const userKey ctxKey = "user"
ctx := context.WithValue(r.Context(), userKey, user)
next.ServeHTTP(w, r.WithContext(ctx)) // returns NEW request
user, _ := r.Context().Value(userKey).(User)
```

> [!warning] Key must be own `type ctxKey`, not plain string — two packages using `"user"` collide. Never store context in struct — it flows down the call chain `Context` `24 - Context` rule.

---

## 15. Testing HTTP Handlers — httptest

No real port — call handler directly.

```go
func TestListPage(t *testing.T) {
    st, _ := store.Open(":memory:")
    h := web.ListPage(st)
    req := httptest.NewRequest("GET", "/expenses?from=2026-08-01&to=2026-08-31", nil)
    rec := httptest.NewRecorder()
    h.ServeHTTP(rec, req)
    if rec.Code != http.StatusOK { t.Fatalf("got %d", rec.Code) }
    if !strings.Contains(rec.Body.String(), "bread") { t.Error(rec.Body.String()) }
}
```

`rec.Code` = status, `rec.Header()` / `rec.Body.String()` = output.

`httptest.NewServer` for integration:

```go
srv := httptest.NewServer(mux)
defer srv.Close()
resp, _ := http.Get(srv.URL + "/expenses")
```

Request builder:

```go
body := strings.NewReader("description=bread&amount=10000")
req := httptest.NewRequest("POST", "/expenses/add", body)
req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
```

> [!tip] Handlers are plain values — `h.ServeHTTP(rec, req)` is the whole test. That’s why factory `AddExpense(st)` is testable: `store.Open(":memory:")` gives isolated DB per test.

---

## 16. Quick Reference Cheatsheet

```go
# server
http.ListenAndServe(":8080", mux)
log.Fatal(http.ListenAndServe(...))
srv := &http.Server{Addr, Handler, ReadTimeout, WriteTimeout, IdleTimeout}
srv.ListenAndServeTLS("server.crt", "server.key")

# handler
type Handler interface { ServeHTTP(w http.ResponseWriter, r *http.Request) }
mux.HandleFunc(pattern, func(w, r))
mux.Handle(pattern, handler)
func Name(st) http.HandlerFunc { return func(w, r) {...} }

# routing (Go 1.22+)
mux.HandleFunc("GET /expenses", h)
mux.HandleFunc("POST /expenses/add", h)
mux.HandleFunc("GET /expenses/{id}", h) // r.PathValue("id")
# precedence: specific > wildcard > "/" ; 405 vs 404
# gorilla/mux: r.HandleFunc("/a/{id:[0-9]+}").Methods("GET") + Subrouter
# chi: r.Get("/path", h) + r.Use() + r.Route() + chi.URLParam

# request
r.Method; r.URL.Path; r.URL.Query().Get("from")
r.PathValue("id"); r.FormValue("amount"); r.PostFormValue("x"); r.FormFile("cheque")
r.Header.Get("Content-Type"); r.Body; r.Context()

# response
w.Header().Set("K","v") // before Write
w.WriteHeader(500) // before Write else 200
http.Redirect(w,r,"/x",http.StatusSeeOther)
http.Error(w,"oops",500)

# status: 200 201 204 301 303 400 401 403 404 405 429 500
# middleware
func wrap(next http.Handler) http.Handler { return http.HandlerFunc(func(w,r){ next.ServeHTTP(w,r) }) }
# gate returns without next (auth/CORS/rate limit)

# JSON
json.NewDecoder(r.Body).Decode(&req)
w.Header().Set("Content-Type","application/json"); json.NewEncoder(w).Encode(result)
# json.Marshal/Unmarshal on []byte; tags json:"name" — unexported → {}

# cookies
http.SetCookie(w, &http.Cookie{Name,Value,Path,HttpOnly,Secure,SameSite,MaxAge})
c, err := r.Cookie("session") // ErrNoCookie

# client
resp, _ := http.Get(url); defer resp.Body.Close()
req, _ := http.NewRequest(method, url, body); client := &http.Client{Timeout:5*time.Second}; client.Do(req)

# context
ctx := r.Context(); r.WithContext(ctx); r.Context().Value(key); db.QueryContext(ctx, ...)
# key = type ctxKey string, never string

# testing
rec := httptest.NewRecorder(); h.ServeHTTP(rec, req) // rec.Code/Header/Body
httptest.NewRequest(method,target,body)
srv := httptest.NewServer(mux); defer srv.Close()
```

> [!practice] **Project laser.** `cmd/expense/main.go` + `internal/web/handlers.go`: (1) why does `tmpl.Execute(w, data)` work with `http.ResponseWriter`? (2) why does filter form use `GET` while add/delete use `POST`? (3) trace `POST /expenses/delete` with garbage `id` through log→`http.Error`→`return` — what status and what would missing `return` do? (4) `StatusSeeOther` vs `StatusOK` + print page — what does F5 do? (5) which handler is gate for auth middleware and where is `r.Cookie("session")` read? (6) what happens if `r.Body` is read twice — `FormValue` after `io.ReadAll`?

---

_Previous: [[18 - Standard Library]] · Next: [[20 - encoding/json]]_
