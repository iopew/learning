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

`net/http` is a complete HTTP toolkit in one package: the **server** (what your expense-tracker runs) and the **client** (what `curl`, browsers, and other programs use to talk to it). Both halves share the same model of the protocol.

```
client (browser, curl)                    server (your app)
   │   GET /expenses?from=...&to=...            │
   │ ──────────────────────────────────────────► │  handle → run SQL → build HTML
   │   HTTP/1.1 200 OK                          │
   │ ◄────────────────────────────────────────── │
```

The transaction is always one shape: the client sends a **request** (method, path, headers, optional body); the server sends a **response** (status code, headers, optional body). Forms, JSON, file uploads — all variations of those two envelopes.

**A request line, decoded** (what the browser writes on the wire):

```
GET /expenses?from=2026-08-01&to=2026-08-31 HTTP/1.1
Host: localhost:8080

method    path          query string               version
```

Go hides the wire from you — you read/write the *decoded* pieces through `*http.Request` and `http.ResponseWriter`.

> [!note] HTTP is a **text** protocol — everything that travels is text. That's why handlers always receive strings (`"20000"`) and must `strconv.ParseInt` them ([[18 - Standard Library]] §6): the wire has no `int` type.

> [!note] Each incoming request runs in **its own goroutine** ([[12 - Goroutines]] §net/http). Two visitors never block each other — the server is concurrent by default, and that's also why shared state between handlers needs [[15 - Sync Primitives]] discipline.

---

## 2. The Server — ListenAndServe, ServeMux, Handle

**The one line that starts everything:**

```go
log.Fatal(http.ListenAndServe(":8080", mux))
```

Two arguments, two jobs:

- `":8080"` — the **address**: `host:port`. Empty host = all interfaces; `":0"` = a random free port.
- `mux` — the **handler**: the object that decides what happens to every request. (Your project passes a `*http.ServeMux` — the router.)

It **blocks forever**: accept connection → read request → hand to `mux` → write response → repeat. It returns only when the server dies — which is why it's wrapped in `log.Fatal` ([[18 - Standard Library]] §10): the only way out is a fatal error.

**The two registration methods on a mux:**

```go
mux := http.NewServeMux()

mux.Handle("/expenses", h)        // Handle: takes a Handler (interface)
mux.HandleFunc("/hello", func(w, r){...})  // HandleFunc: takes a function
```

`HandleFunc` is `Handle` with the function-to-interface adapter applied for you (§3). Both store a pattern → handler pair in the router.

**The modern server struct** — for control (timeouts, TLS, per-server settings):

```go
srv := &http.Server{
    Addr:         ":8080",
    Handler:      mux,
    ReadTimeout:  10 * time.Second,
    WriteTimeout: 10 * time.Second,
}
log.Fatal(srv.ListenAndServe())        // or srv.ListenAndServeTLS(cert, key)
```

`ListenAndServe`'s two arguments are just the zero-cost defaults of `http.Server`. The struct is the same server with knobs.

> [!tip] `http.ListenAndServeTLS(":443", cert, key, mux)` does HTTPS with the one-liner. Local dev stays plain HTTP because you need certificates first (§13).

---

## 3. Handlers — The Interface & HandlerFunc

Everything in net/http funnels through **one interface:**

```go
type Handler interface {
    ServeHTTP(w http.ResponseWriter, r *http.Request)
}
```

One method, two parameters. Any type with a `ServeHTTP` method is a Handler — including `*http.ServeMux`, which is why `ListenAndServe(":8080", mux)` works.

**The function adapter** — the bridge from "function" to "interface":

```go
type HandlerFunc func(w http.ResponseWriter, r *http.Request)

// HandlerFunc implements ServeHTTP — it just calls itself:
func (f HandlerFunc) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    f(w, r)
}
```

A function type *with a method*. This is why a plain function can stand anywhere a Handler is expected — `mux.HandleFunc` is precisely this conversion.

**The factory pattern** — your milestone-2 shape ([[04 - Functions]] §closures): a function that *builds* a handler with captured state:

```go
func AddExpense(st *store.Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        // st is captured in the closure — the handler carries its store
        st.Add(...)
        http.Redirect(w, r, "/expenses", http.StatusSeeOther)
    }
}
```

**Why the pattern:** a handler that needs dependencies (a store, a logger, a config) has nowhere to get them — `ServeHTTP` only receives `w` and `r`. The factory closes over them. Handlers that need nothing can be plain functions — your milestone-4 scan handler was the first such case.

> [!info] You met the interface + adapter without the names in milestone 2. `http.HandlerFunc` and `http.Handler` are the single most repeated shape in Go web code — every framework (echo, gin, chi) is built on handlers shaped exactly like these.

---

## 4. The Request — Method, URL, Header, Body, Form

`*http.Request` is the decoded envelope. The fields you'll use daily:

```go
r.Method                      // "GET", "POST", "PUT", ...
r.URL.Path                    // "/expenses" — no query
r.URL.RawQuery                // "from=2026-08-01&to=..." — the raw query text
r.URL.Query()                 // url.Values — parsed query params
r.PathValue("id")             // wildcard capture (Go 1.22+)
r.Header.Get("Content-Type")  // one header (Header is a map)
r.Body                        // io.ReadCloser — the raw request body stream
r.FormValue("amount")         // form field from query OR body — the workhorse
r.FormFile("qr")              // uploaded file → (multipart.File, *FileHeader, err)
r.Context()                   // the request's context (§14) — cancelled when the client disconnects
r.RemoteAddr                  // "127.0.0.1:52341" — who's calling
```

**The four ways data arrives:**

| Source | Example | How to read |
|---|---|---|
| URL query | `/expenses?from=2026-08-01&to=2026-08-31` | `r.URL.Query().Get("from")` |
| URL wildcard | `/expenses/7` | `r.PathValue("id")` |
| Form body | `POST` + `description=bread&amount=10000` | `r.FormValue("description")` |
| File upload | multipart body (the cheque PDF) | `r.FormFile("qr")` |

**Form parsing — the two layers:**

- **`r.FormValue`** — the shortcut: parses both query and body, merges them, returns the first hit. One call for either source. (`r.PostFormValue` reads only the body — useful when a query param and a form field share a name.)
- **`r.ParseForm()`** — the explicit version: parses into `r.Form` / `r.PostForm` (the `url.Values` maps) so you can inspect *all* fields at once. `FormValue` calls this internally.

**The Body is a stream, read once:**

```go
data, err := io.ReadAll(r.Body)   // whole body → []byte ([[18]] §3)
defer r.Body.Close()
```

Read `r.Body` *or* `FormValue` — not both. Once the stream is consumed, `FormValue` finds nothing. For JSON bodies you read `r.Body` directly (§10); for forms you use `FormValue`; the server decides the format by `Content-Type`.

> [!warning] `FormValue` on a file-upload form returns an empty string — files don't live in `r.Form`; they come through `r.FormFile`. The two channels are separate.

> [!tip] `r.Header` is a map — `r.Header["Content-Type"]` gives the whole slice of values; `r.Header.Get` gives the first. Both are case-insensitive: HTTP header names are case-insensitive by spec.

---

## 5. The ResponseWriter — Header, WriteHeader, Write

```go
type ResponseWriter interface {
    Header() http.Header        // the response's headers — set BEFORE writing
    Write([]byte) (int, error)  // the body — also satisfies io.Writer
    WriteHeader(int)            // the status code — implicit if never called
}
```

**The three rules:**

1. **`Write` is the body.** And because it's an `io.Writer`, `fmt.Fprintln(w, ...)`, `tmpl.Execute(w, data)`, and `io.Copy(w, file)` all work with zero adapters ([[18 - Standard Library]] §3). That one interface is why your template render is a single line.
2. **`Header().Set` before `Write`.** After the first `Write`, the header set is frozen — the status line has already left the server.
3. **`WriteHeader` — or the implicit 200.** Not calling it = Go writes `200 OK` at the first `Write`. Call it *first* when the status isn't 200.

```go
w.Header().Set("Content-Type", "text/html; charset=utf-8")
w.WriteHeader(http.StatusNotFound)        // MUST come before Write
fmt.Fprintln(w, "not found")
```

**Content-Type auto-detection:** if you never set it, Go sniffs the body (`http.DetectContentType`) — fine for HTML, but for JSON it may guess `text/plain; charset=utf-8`; set `application/json` explicitly (§10).

> [!warning] The double-write trap: calling `Write` before `WriteHeader(500)` means the 200 status has already been sent — the 500 is silently ignored (and logged as "superfluous WriteHeader"). **Decide the status first, then write.** Your handlers dodge this because the mutation path writes nothing at all — it redirects (§7).

---

## 6. Routing — stdlib mux vs gorilla/mux vs chi

### The stdlib mux (Go 1.22+ patterns)

Modern `ServeMux` matches method + path and hands off to the handler:

```go
mux := http.NewServeMux()

mux.HandleFunc("GET /expenses", web.ListPage(st))        // method + space + path
mux.HandleFunc("POST /expenses/add", web.AddExpense(st))
mux.HandleFunc("GET /expenses/scan", web.ScanExpense)    // plain func, no st
```

- **Method + path:** a POST to `/expenses` does not match the GET pattern — it gets `405 Method Not Allowed` instead of silently running the GET handler.
- **Wildcards:**

```go
mux.HandleFunc("GET /expenses/{id}", handler)
id := r.PathValue("id")        // "7" — the capture, always a string
```

- **Precedence is automatic:** the most specific pattern wins — `/expenses/7` beats `/expenses/{id}` beats `/expenses/` (the tree catch-all). No ordering bugs.
- **Trailing slash:** `/expenses/` matches everything under `/expenses/`; `/expenses` matches only the exact path.
- Pre-1.22, `"/expenses"` matched *any* method — the exact bug you hit in milestone 2 (`GET /expense/add` vs `POST /expenses/add`).

### Third-party routers

When the stdlib mux's rules get limiting (regex routes, grouped middleware, subrouters), the ecosystem has mature options — same `http.Handler` interface, so they drop into `ListenAndServe` unchanged:

| Router | Style | Why you'd pick it |
|---|---|---|
| stdlib `ServeMux` | method + path patterns (1.22+) | nothing to add; most apps never outgrow it |
| **gorilla/mux** | `r.Path("/a/{id}").Methods("GET")`, subrouters, regex `{id:[0-9]+}` | the classic; route-level middleware chaining |
| **chi** | method-first, middleware `r.Use(...)`, context value access `chi.URLParam(r, "id")` | idiomatic stdlib-style composition; a popular modern default |

```go
// gorilla/mux
r := mux.NewRouter()
r.HandleFunc("/expenses/{id:[0-9]+}", handler).Methods("GET")

// chi
r := chi.NewRouter()
r.Use(middleware.Logger)                       // middleware at the router level
r.Get("/expenses/{id}", handler)               // 1.22-style method-first syntax
id := chi.URLParam(r, "id")
```

> [!note] All three share the same core: they satisfy `http.Handler` and match against method + path. The stdlib mux gained method matching + wildcards in Go 1.22, which closed most of the gap that created gorilla/mux. Start with the stdlib; reach for a library when the route table grows subrouters and per-group middleware.

---

## 7. Status Codes & the Redirect

The status code is the response's *headline* — a three-digit verdict read before any content.

| Code | Name | Meaning |
|---|---|---|
| 200 | OK | everything worked |
| 201 | Created | a POST that added a resource |
| 204 | No Content | success, nothing to return |
| 301 | Moved Permanently | the URL changed forever (browsers cache it) |
| 303 | See Other | "the result is elsewhere — GET it" — the redirect |
| 400 | Bad Request | the client sent nonsense (bad amount) |
| 401 | Unauthorized | not authenticated |
| 403 | Forbidden | authenticated but not allowed |
| 404 | Not Found | no such route |
| 405 | Method Not Allowed | route exists, wrong method |
| 500 | Internal Server Error | the server broke (SQL failed) |

**The sacred redirect — every mutation in your app ends this way:**

```go
http.Redirect(w, r, "/expenses", http.StatusSeeOther)
```

Three arguments: writer, request, target, code. It writes a `Location` header + the 303; the **browser then issues a fresh GET to `/expenses`**. That's the whole **POST/Redirect/GET** pattern:

- User POSTs an expense → you add the row → **303** → browser GETs the list → they see the new row.
- **F5 protection:** responding with 200 + the form HTML instead would make refresh re-POST — re-inserting the row (your duplicate-bread bug from milestone 1). After a 303, refresh re-GETs — harmless.

**Status constants:** every code has a named constant (`http.StatusOK`, `http.StatusSeeOther`, `http.StatusInternalServerError`) — always use the name, never the bare number.

> [!warning] The redirect **writes nothing else**. Any `w.Write` before it has already started the response, and the redirect then fails silently ("superfluous WriteHeader"). In your handlers: guard → mutate → redirect, nothing in between.

---

## 8. Errors in Handlers

A handler can't "return an error" — `ServeHTTP` returns nothing. So what happens when SQL fails? The pattern you've drilled since milestone 2:

```go
if err != nil {
    fmt.Println("failed to list:", err)                    // ① the log — with the ACTUAL err
    http.Error(w, "oops", http.StatusInternalServerError)  // ② the client — generic message
    return                                                // ③ stop. early return, always
}
```

**`http.Error(w, message, code)`** — the one-line error responder: sets the status, writes the message as the body. It's `WriteHeader + Write` combined.

The division of honesty:
- The **client** gets a generic message — your SQL internals are a security leak (that's how people learn your table names).
- The **log** gets the real error — that's where debugging happens.

> [!tip] A handler that fails must still produce a *valid HTTP response* — never return having written nothing (the client hangs or gets an empty 200 — your delete-guard bug taught you this). The three-step shape — log, `http.Error`, `return` — guarantees a verdict every time. The `log` calls here are the debugging friend; milestone-6 middleware replaces them with structured logging (§9).

---

## 9. Middleware — Wrapping Handlers

A Handler is an interface — and an interface can *wrap* another. **Middleware** is a function that takes a Handler and returns a Handler, adding behavior around it:

```go
func logRequests(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)                        // ① let the real handler run
        fmt.Printf("%s %s in %v\n", r.Method, r.URL.Path, time.Since(start))
    })
}
```

**Chaining** — middleware wrapping middleware:

```go
mux.Handle("GET /expenses",
    logRequests(
        requireAuth(
            http.HandlerFunc(web.ListPage(st)))))
```

The flow is an onion: request → `logRequests` → `requireAuth` → handler → back out. Each layer runs before *and* after the next. The inner handler never knows it's wrapped.

**The four classic middlewares:**

```go
// logging — method, path, status, duration per request
func logging(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        slog.Info("request", "method", r.Method, "path", r.URL.Path,
            "dur", time.Since(start))                    // structured — [[18]] §10
    })
}

// auth — reject before the handler runs (milestone 7!)
func requireAuth(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if !isLoggedIn(r) {                              // check the session cookie §11
            http.Redirect(w, r, "/login", http.StatusSeeOther)
            return                                       // never call next
        }
        next.ServeHTTP(w, r)
    })
}

// CORS — tell browsers which origins may call you
func cors(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        if r.Method == http.MethodOptions {              // preflight request
            w.WriteHeader(http.StatusNoContent)
            return
        }
        next.ServeHTTP(w, r)
    })
}

// rate limiting — one counter per IP, refuse past the limit
func rateLimit(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if tooMany(r.RemoteAddr) {
            http.Error(w, "slow down", http.StatusTooManyRequests)  // 429
            return
        }
        next.ServeHTTP(w, r)
    })
}
```

**The two shapes of middleware:**

- **Around** — behavior before and after the handler (logging, timing, recovery).
- **Gate** — decide whether the handler runs at all (auth, CORS preflight, rate limit). The gate **returns without calling `next`** — that's how a request is refused.

> [!tip] The factory pattern and middleware are the same trick from two sides: `AddExpense(st)` *creates* a handler with captured state; `logRequests(h)` *modifies* one by wrapping. Both are functions producing handlers — the core idiom of Go web code.

---

## 10. JSON APIs — Encoding & Decoding Bodies

Your app renders HTML, but APIs (and the milestone-6 future) speak JSON. Two directions, two patterns. (Full JSON reference: [[20 - encoding/json]])

**Decoding — reading a JSON request body:**

```go
type AddReq struct {
    Description string `json:"description"`
    Amount      int64  `json:"amount"`
}

func handleJSON(w http.ResponseWriter, r *http.Request) {
    var req AddReq
    dec := json.NewDecoder(r.Body)        // stream from the request body
    if err := dec.Decode(&req); err != nil {
        http.Error(w, "bad json", http.StatusBadRequest)
        return
    }
    // req is now populated — the tags mapped the JSON keys to fields
}
```

`json.Decoder` reads from the `io.Reader` — and `r.Body` is one, so decoding is one line. The struct tags map wire names (`description`) to Go fields (`Description`) — unexported fields are silently ignored (the classic silent-bug source; [[20 - encoding/json]]).

**Encoding — writing a JSON response:**

```go
w.Header().Set("Content-Type", "application/json")
w.WriteHeader(http.StatusCreated)
json.NewEncoder(w).Encode(result)         // stream out — writes to an io.Writer
```

`json.Encoder.Encode` writes the marshaled JSON plus a trailing newline. Setting `Content-Type` *before* `Encode` beats the sniffing (§5).

**The equivalents without the stream** — `json.Marshal` / `json.Unmarshal` work on whole `[]byte` in memory:

```go
data, _ := json.Marshal(result)      // struct → []byte
w.Write(data)                        // then write it yourself

var req AddReq
body, _ := io.ReadAll(r.Body)
json.Unmarshal(body, &req)           // []byte → struct
```

> [!note] `Marshal`/`Unmarshal` are the pure functions; `Encoder`/`Decoder` are the streaming wrappers that plug into `r.Body` and `w` directly. Your choose: small bodies — either works; large streams — Decoder/Encoder (no whole-body copy in memory).

> [!warning] Struct field names are **case-sensitive** in both directions: a JSON key `"Amount"` does not fill a tag `json:"amount"` field. And unexported fields never marshal — you get `{}` with no error. Check with the "two wrongs" habit from the Summary bug: verify against the wire, not the struct.

---

## 11. Cookies

HTTP is stateless — every request is independent. **Cookies** are how the server persists identity across requests: the response tells the browser to store a token, and the browser sends it back with every subsequent request.

```go
// SET — on a successful login
http.SetCookie(w, &http.Cookie{
    Name:     "session",
    Value:    "abc123",
    Path:     "/",                    // which routes the cookie applies to
    HttpOnly: true,                   // JS can't read it — XSS protection
    SameSite: http.SameSiteLaxMode,   // CSRF protection
    MaxAge:   3600,                   // seconds; or Expires
})

// READ — on every protected request
c, err := r.Cookie("session")         // *http.Cookie or error
if err == http.ErrNoCookie {          // no such cookie — treat as not logged in
    http.Redirect(w, r, "/login", http.StatusSeeOther)
    return
}
fmt.Println(c.Value)                  // "abc123"
```

**The security flags are not optional:**

- **`HttpOnly`** — a malicious script injected into your page cannot read the cookie via `document.cookie`. You'll set this on every auth cookie.
- **`Secure`** — only send over HTTPS (your milestone-6 session cookie wants this in production).
- **`SameSite`** — stops the browser sending the cookie on cross-site requests: the core CSRF defense, *in addition to* your POST-for-mutations rule (§7).

**Why you need it (milestone 7):** your auth middleware (§9) will check `r.Cookie("session")` → look up the user in the DB → attach the user to `r.Context()` (§14) → `next.ServeHTTP`. The cookie is just the browser's half of the handshake; the server keeps the real session data.

> [!tip] Cookies are also where the "flash message" polish idea lives: set a cookie on a failed action, read-and-delete it on the next page render, show it once. That's the milestone-5 flash-errors plan in one line.

---

## 12. The HTTP Client

Same package, opposite direction. The server side you know; the client is one line:

```go
resp, err := http.Get("https://example.com")
if err != nil { ... }
defer resp.Body.Close()                        // ← THE leak rule

fmt.Println(resp.StatusCode)                   // 200
body, err := io.ReadAll(resp.Body)             // the response body → []byte
```

**The four verbs:**

```go
http.Get(url)                     // GET
http.Post(url, "application/json", body)   // POST — body is io.Reader
http.PostForm(url, url.Values{"a": {"b"}}) // POST form-encoded
http.Head(url)                    // GET with no response body (headers only)
```

**The full control path — `http.NewRequest` + `client.Do`:**

```go
// ① build the request: method, URL, body (as an io.Reader)
req, err := http.NewRequest("POST", "http://localhost:8080/expenses/add",
    strings.NewReader("description=bread&amount=10000"))
req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
req.Header.Set("User-Agent", "expense-sync/1.0")

// ② do it with a custom client — ALWAYS set a timeout
client := &http.Client{Timeout: 5 * time.Second}
resp, err := client.Do(req)
```

`NewRequest` separates *building* the request from *sending* it — the step where headers and context attach.

**The custom client's settings:**

```go
client := &http.Client{
    Timeout: 5 * time.Second,          // overall deadline — the one you must set
    Transport: &http.Transport{        // the low-level connection pool
        MaxIdleConns:        10,
        IdleConnTimeout:     30 * time.Second,
        TLSClientConfig:    &tls.Config{InsecureSkipVerify: false},
    },
}
```

The package-level `http.Get`/`http.Post` use a default client **with no timeout** — a dead server can hang your program forever. For anything real, build a client with a `Timeout`.

**One rule to own: `resp.Body` is a stream — always `defer resp.Body.Close()`.** An unclosed body leaks the connection. This is the client twin of `defer rows.Close()` from milestone 1 — same idea, same muscle.

> [!note] Your verification ritual already uses the client: `curl localhost:8080/expenses` is `http.Get` in disguise; `curl -d "amount=10000" -X POST ...` is `client.Do` with a body. When a third-party API arrives (QR/prefill), this section is your door to it.

---

## 13. TLS/HTTPS & Timeouts

### TLS

HTTPS is HTTP inside a TLS-encrypted tunnel. Go makes the switch trivial — the hard part is the certificate:

```go
// one-liner form
log.Fatal(http.ListenAndServeTLS(":443", "server.crt", "server.key", mux))

// server-struct form
srv := &http.Server{Addr: ":443", Handler: mux}
log.Fatal(srv.ListenAndServeTLS("server.crt", "server.key"))
```

- **Certificate files** — `server.crt` (public cert) + `server.key` (private key), usually from Let's Encrypt, a CA, or a self-signed pair for dev.
- **HTTP/2** — automatic when TLS is on; `http.Server` enables it by default, no config.
- **Testing locally** — generate a self-signed cert (`openssl req -x509 -newkey rsa:2048 ...`), serve HTTPS, and your browser will warn "untrusted" — expected for a self-signed cert. `InsecureSkipVerify` on the *client* side is a dev-only escape hatch, never production.

**Forcing HTTPS from an HTTP server** (redirect all traffic):

```go
// run the HTTP listener on :80, redirect everything to :443
http.ListenAndServe(":80", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
    http.Redirect(w, r, "https://"+r.Host+r.URL.RequestURI(), http.StatusMovedPermanently)
}))
```

### Timeouts — the four knobs

| Knob | What it protects against | Typical value |
|---|---|---|
| `Server.ReadTimeout` | slow/broken clients holding the connection open while "reading" | 5–10s |
| `Server.ReadHeaderTimeout` | header-only floods (cheaper than ReadTimeout) | 5s |
| `Server.WriteTimeout` | a handler that hangs forever | 10–30s |
| `Server.IdleTimeout` | idle keep-alive connections squatting on resources | 60–120s |
| `Client.Timeout` | your *outgoing* calls hanging on a dead peer | 5–10s |

```go
srv := &http.Server{
    Addr: ":8080",
    Handler: mux,
    ReadHeaderTimeout: 5 * time.Second,
    ReadTimeout:       10 * time.Second,
    WriteTimeout:      15 * time.Second,
    IdleTimeout:       60 * time.Second,
}
```

> [!warning] Without timeouts, a single client that connects and never sends anything holds a goroutine forever — and each connection is cheap, so a thousand of them still only cost memory... but every hung *handler* also blocks its goroutine. `WriteTimeout` is what stops a deadlocked handler from hanging the server's resources indefinitely.

---

## 14. Context & Cancellation

HTTP requests die all the time — the client closes the tab, the connection drops. The server must *know* and stop working on the dead request. That's `context.Context` (full deep dive: [[24 - Context]]).

**Every request carries one:**

```go
ctx := r.Context()        // cancelled when: the client disconnects,
                          // the timeout fires, or the server shuts down
```

**The two things context does for handlers:**

1. **Cancellation-aware work.** Long operations check `ctx.Done()` — they learn the client is gone and abandon the work:

```go
func slowHandler(w http.ResponseWriter, r *http.Request) {
    select {
    case <-time.After(3 * time.Second):
        fmt.Fprintln(w, "done after 3s")
    case <-r.Context().Done():          // client left early — give up
        return                          // no response needed, nobody's listening
    }
}
```

2. **Propagating into the stack.** Database calls accept a context and stop when it's cancelled — your store's `Query`/`Exec` could take `ctx` and pass it to the SQL driver, so a dropped client cancels the query:

```go
rows, err := s.db.QueryContext(ctx, `SELECT ...`, from, to)   // vs plain Query
```

**Storing values (milestone 7's auth hook):** middleware attaches the authenticated user to the request's context, handlers read it back:

```go
type ctxKey string
const userKey ctxKey = "user"

// middleware (after auth check):
ctx := context.WithValue(r.Context(), userKey, user)
next.ServeHTTP(w, r.WithContext(ctx))        // r.WithContext returns a NEW request

// handler:
user, ok := r.Context().Value(userKey).(User)  // typed back out
```

> [!warning] The value key must be your own **type** (`ctxKey`), never a plain string or a built-in — two packages using `"user"` silently collide. And never store context in a struct field — it belongs in the request, flowing downward.

> [!note] The one context rule from [[24 - Context]] applies here twice over: **context flows, it does not live.** Every place a request's work passes (handler → store → driver), the context passes with it.

---

## 15. Testing HTTP Handlers — httptest

You've been testing with `curl` by hand. `httptest` automates it — same `net/http`, no real port needed ([[22 - Testing]]).

**`httptest.NewRecorder`** — a fake `ResponseWriter` that captures everything:

```go
func TestListPage(t *testing.T) {
    st, _ := store.Open(":memory:")               // in-memory DB — no file
    h := web.ListPage(st)

    req := httptest.NewRequest("GET", "/expenses?from=2026-08-01&to=2026-08-31", nil)
    rec := httptest.NewRecorder()                  // collects what the handler writes

    h.ServeHTTP(rec, req)                          // call the handler directly

    if rec.Code != http.StatusOK {
        t.Fatalf("got %d, want %d", rec.Code, http.StatusOK)
    }
    if !strings.Contains(rec.Body.String(), "bread") {
        t.Errorf("list page missing bread: %s", rec.Body.String())
    }
}
```

`NewRecorder` implements `ResponseWriter` — status into `rec.Code`, headers into `rec.Header()`, body into `rec.Body`. You assert against those.

**`httptest.NewServer`** — a *real* running server on a random port, for full integration tests (your client code against your server code):

```go
srv := httptest.NewServer(mux)          // starts on 127.0.0.1:random
defer srv.Close()

resp, err := http.Get(srv.URL + "/expenses")   // the REAL client, the REAL server
```

**The request builder** — `httptest.NewRequest(method, target, body)` where body is an `io.Reader`:

```go
body := strings.NewReader("description=bread&amount=10000")
req := httptest.NewRequest("POST", "/expenses/add", body)
req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
```

> [!tip] This is the milestone-6-era payoff: every handler gets a `_test.go`, and the hand-curl ritual (restart server, click browser) becomes `go test`. Note how the whole test uses only what this note taught — the handler is just an interface you call directly. That's the design working: handlers are testable because they're plain values.

---

## 16. Quick Reference Cheatsheet

```go
# server
http.ListenAndServe(":8080", mux)      # blocks forever; return = dead server
log.Fatal(http.ListenAndServe(...))    # the canonical wrap
srv := &http.Server{Addr, Handler, ReadTimeout, WriteTimeout, IdleTimeout}
srv.ListenAndServeTLS("server.crt", "server.key")   # HTTPS + HTTP/2

# handler interface
type Handler interface { ServeHTTP(w http.ResponseWriter, r *http.Request) }
mux.HandleFunc(pattern, func(w, r))    # function → Handler via HandlerFunc
mux.Handle(pattern, handler)           # Handler directly
factories: func Name(st) http.HandlerFunc { return func(w, r) {...} }

# routing (Go 1.22+)
mux.HandleFunc("GET /expenses", h)         # method + space + path
mux.HandleFunc("POST /expenses/add", h)
mux.HandleFunc("GET /expenses/{id}", h)    # wildcard; r.PathValue("id")
# specific beats wildcard beats "/" tree; wrong method → 405
# alternatives: gorilla/mux, chi — same http.Handler interface

# request
r.Method  r.URL.Path  r.URL.Query().Get("from")
r.PathValue("id")        # wildcard capture
r.FormValue("amount")    # query + body, always a string
r.PostFormValue("x")     # body only
r.ParseForm()            # explicit → r.Form / r.PostForm
r.FormFile("qr")         # → (multipart.File, *FileHeader, err)
r.Header.Get("Content-Type")
r.Body (io.ReadCloser) — read once, io.ReadAll(r.Body)
r.Context()              # cancelled on disconnect/timeout/shutdown

# response
w.Write(body)            # the body; w IS an io.Writer
w.Header().Set("K", "v") # BEFORE Write
w.WriteHeader(500)       # before Write; else implicit 200
http.Redirect(w, r, "/x", http.StatusSeeOther)  # 303 → browser re-GETs
http.Error(w, "oops", 500)  # body + code in one call

# status codes
200 OK  201 Created  204 No Content  301 Moved Permanently  303 See Other
400 Bad Request  401 Unauthorized  403 Forbidden  404 Not Found
405 Method Not Allowed  429 Too Many Requests  500 Internal Server Error

# middleware
func wrap(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w, r) { /* before */; next.ServeHTTP(w, r); /* after */ })
}
# gate middleware returns WITHOUT calling next (auth, CORS, rate limit)

# JSON
dec := json.NewDecoder(r.Body); dec.Decode(&req)       # in
w.Header().Set("Content-Type", "application/json")
json.NewEncoder(w).Encode(result)                      # out
# tags: json:"name" — unexported fields are silently skipped

# cookies
http.SetCookie(w, &http.Cookie{Name, Value, Path, HttpOnly, Secure, SameSite, MaxAge})
c, err := r.Cookie("session")    # err == http.ErrNoCookie when absent

# client
resp, err := http.Get(url)          # defer resp.Body.Close() ALWAYS
http.Post(url, ct, body)  http.PostForm(url, url.Values{...})
req, _ := http.NewRequest(method, url, body)   # headers attach here
client := &http.Client{Timeout: 5 * time.Second}
resp, err := client.Do(req)
io.ReadAll(resp.Body)              # the response body

# context
ctx := r.Context()                 # Done() when client leaves
r.WithContext(ctx)                 # returns a NEW request
r.Context().Value(key)             # key = your own type, never a string
db.QueryContext(ctx, ...)          # cancel-aware SQL

# testing
rec := httptest.NewRecorder(); h.ServeHTTP(rec, req)
rec.Code  rec.Header()  rec.Body.String()
httptest.NewRequest(method, target, body)
srv := httptest.NewServer(mux); defer srv.Close(); http.Get(srv.URL + "/x")
```

> [!practice] **Project laser.** Look at `cmd/expense/main.go` + `internal/web/handlers.go` and answer, from this note only: (1) why does `tmpl.Execute(w, data)` work without any adapter, given `w` is a `http.ResponseWriter`? (2) why does the list page's filter form use `method="get"` while the add/delete forms use `method="post"`? (3) trace `POST /expenses/delete` with a garbage id through the three-step error shape — what status would the client receive, and what would change if the missing `return` came back? (4) the delete redirect uses `http.StatusSeeOther` — what would change if the handler responded with `http.StatusOK` and printed the page instead? (5) which handler is a *gate* candidate for milestone-6 auth middleware, and where would the session cookie be read?

---

_Previous: [[18 - Standard Library]] · Next: [[20 - encoding/json]]_