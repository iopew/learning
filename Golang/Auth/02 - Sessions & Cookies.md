# Auth — Sessions & Cookies

> **Series:** Auth **Tags:** #auth #session #cookies #golang #security #net-http #cryptography **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. Why Sessions — HTTP Has No Memory]]
- [[#2. http.Cookie Struct — Every Field]]
- [[#3. Set-Cookie vs Cookie — Server Sets, Browser Sends]]
- [[#4. Sessions Table — token PK, user_id FK, expires_at]]
- [[#5. Generating Tokens — crypto/rand 32B Hex]]
- [[#6. Setting Cookies — http.SetCookie]]
- [[#7. Reading Cookies — r.Cookie and Errors]]
- [[#8. Validating Sessions — SELECT WHERE token AND expires_at]]
- [[#9. Expiry & Cleanup — DELETE WHERE expires_at < now()]]
- [[#10. Logout — MaxAge -1 and DELETE]]
- [[#11. Cookie vs localStorage vs sessionStorage]]
- [[#12. SameSite — Lax vs Strict vs None + Secure]]
- [[#13. Common Pitfalls — The Bug Party]]
- [[#14. Project Tie-In — quicknotes + expense-tracker]]
- [[#15. Quick Reference Cheatsheet]]

---

## 1. Why Sessions — HTTP Has No Memory

HTTP is stateless `19 - net:http.md:40` — `GET /notes` knows nothing about `POST /login` that happened 2 seconds ago. Sessions add **memory** via cookies `Golang/Auth/§§ - About Auth.md:50`.

Flow `01 - Passwords & Hashing` → `02`:
```
POST /login  email=a@b.com password=secret
  → bcrypt.CompareHashAndPassword == nil 01:2
  → generate token 32B hex 02:5
  → INSERT INTO sessions (token, user_id, expires_at) 02:4
  → Set-Cookie: session=abc; HttpOnly; SameSite=Lax; Path=/ 02:6
Browser stores cookie → every GET /notes sends Cookie: session=abc 02:7
  → r.Cookie("session") → SELECT WHERE token=? AND expires_at>now() 02:8
  → RequireAuth 06 loads user_id into context
```

> [!note] Session = server memory `sessions(token PK)` `02:4` — revocable via `DELETE` `02:9`. JWT `03` is client-carried — not revocable without blocklist.

---

## 2. http.Cookie Struct — Every Field

From `net/http` `19 - net:http.md:469`:

```go
import "net/http"

type Cookie struct {
    Name     string // "session" — what JS/server calls it
    Value    string // "4f9d...a3c" — 64 hex chars (32B)
    Path     string // "/" — cookie sent to every path; "/notes" = only /notes
    Domain   string // "" = current host only; ".example.com" = subdomains
    Expires  time.Time // absolute expiry — browser deletes after
    MaxAge   int       // seconds until expiry — 0 = session cookie (browser close), -1 = delete now 19:492
    Secure   bool      // true = only over https — set in prod 12 - HTTPS
    HttpOnly bool      // true = JS document.cookie cannot read — XSS mitigation 08
    SameSite http.SameSite // Lax/Strict/None — CSRF mitigation 07
    RawExpires string  // rarely set directly
    Unparsed []string  // rarely used
}
```

> [!warning] `Value` must be URL-safe — `32B hex` `02:5` is `0-9a-f` only, no `;` or ` `. Never put `user_id` or `email` in `Value` — token is opaque, `user_id` lives in `sessions` table.

```go
cookie := &http.Cookie{
    Name:     "session",
    Value:    token, // 64 hex
    Path:     "/",
    MaxAge:   7 * 24 * 3600, // 7 days in seconds — or Expires: time.Now().Add(7*24*time.Hour)
    HttpOnly: true,
    Secure:   false, // true in prod with TLS 12 - HTTPS
    SameSite: http.SameSiteLaxMode, // default CSRF defense 07
}
```

---

## 3. Set-Cookie vs Cookie — Server Sets, Browser Sends

* **Server → Browser:** `Set-Cookie` response header `19:469` — `http.SetCookie(w, cookie)` adds it. Browser stores `Name=Value` + attributes.
* **Browser → Server:** `Cookie` request header `19:479` — browser automatically sends `Cookie: session=abc; theme=dark` on every request to matching `Path/Domain`. Read via `r.Cookie("session")` or `r.Header.Get("Cookie")`.

```go
// Server sets
http.SetCookie(w, &http.Cookie{Name: "session", Value: token, Path: "/", HttpOnly: true, SameSite: http.SameSiteLaxMode})

// Browser sends next request
// GET /notes
// Cookie: session=4f9d...a3c

// Server reads
c, err := r.Cookie("session") // 19:479
if err != nil { /* http.ErrNoCookie — not logged in */ }
token := c.Value
```

> [!note] `http.SetCookie` writes a *header*, not a body. Must be called **before** `w.WriteHeader`/`w.Write` `19:5` — same order as `Header() → WriteHeader → Write`.

---

## 4. Sessions Table — token PK, user_id FK, expires_at

Single table for `quicknotes` and `expense-tracker` retrofit `Golang/Auth/§§ - About Auth.md:184`:

```sql
import "modernc.org/sqlite" // same as expense-tracker internal/store/store.go:14

CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY, -- 64 hex chars
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL -- ISO8601 "2006-01-02 15:04:05" or RFC3339
);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
```

> [!tip] `TEXT PRIMARY KEY` for `token` — never `INTEGER`. `user_id FK` gives `ON DELETE CASCADE` — deleting user auto-deletes sessions. `expires_at TEXT` with ISO8601 sorts chronologically like `expense-tracker` `store.go:30`.

---

## 5. Generating Tokens — crypto/rand 32B Hex

Never `math/rand` — predictable. Use `crypto/rand` `19 - net:http.md:469` footnote:

```go
import (
    "crypto/rand"
    "encoding/hex"
    "fmt"
)

func generateToken() (string, error) {
    b := make([]byte, 32) // 32 bytes = 256 bits — 64 hex chars
    if _, err := rand.Read(b); err != nil {
        return "", fmt.Errorf("generate token: %w", err)
    }
    return hex.EncodeToString(b), nil // 64 chars [0-9a-f]
}
```

> [!warning] `32B = 64 hex` is minimum for session tokens. `16B` (32 hex) is okay for `csrf_token` `07` but not sessions. Never `uuid.NewString()` alone — 122 bits, less than 256.

---

## 6. Setting Cookies — http.SetCookie

After `01` login success `01:2` → create session row → set cookie:

```go
import (
    "net/http"
    "time"
)

func Login(st *store.Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        email := r.FormValue("email")
        password := r.FormValue("password")
        hash, err := st.FindHashByEmail(email)
        if err != nil || bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
            http.Redirect(w, r, "/login?err="+url.QueryEscape("invalid credentials"), http.StatusSeeOther)
            return
        }
        userID, _ := st.FindUserIDByEmail(email)
        token, _ := generateToken()
        expiresAt := time.Now().Add(7 * 24 * time.Hour)
        if err := st.CreateSession(token, userID, expiresAt.Format(time.RFC3339)); err != nil {
            http.Error(w, "session create failed", http.StatusInternalServerError)
            return
        }
        http.SetCookie(w, &http.Cookie{
            Name:     "session",
            Value:    token,
            Path:     "/",
            Expires:  expiresAt,
            MaxAge:   int(7 * 24 * time.Hour.Seconds()), // or just Expires, both is okay
            HttpOnly: true,
            Secure:   false, // true in prod 12
            SameSite: http.SameSiteLaxMode,
        })
        http.Redirect(w, r, "/notes", http.StatusSeeOther)
    }
}
```

> [!note] `SetCookie` before `Redirect` — `Redirect` calls `WriteHeader(303)` `19:7`, headers must be staged before.

Store helpers:

```go
func (s *Store) CreateSession(token string, userID int64, expiresAt string) error {
    _, err := s.db.Exec("INSERT INTO sessions (token, user_id, expires_at) VALUES (?, ?, ?)", token, userID, expiresAt)
    return err
}
```

---

## 7. Reading Cookies — r.Cookie and Errors

```go
import "net/http"

c, err := r.Cookie("session")
if err == http.ErrNoCookie {
    // not logged in — redirect to /login
    http.Redirect(w, r, "/login", http.StatusSeeOther)
    return
}
if err != nil {
    http.Error(w, "bad cookie", http.StatusBadRequest)
    return
}
token := c.Value
if token == "" {
    http.Redirect(w, r, "/login", http.StatusSeeOther)
    return
}
```

> [!info] `r.Cookie` parses `Cookie` header `19:479`. If browser sends no `Cookie: session=`, you get `http.ErrNoCookie` — not `sql.ErrNoRows`. Check cookie error *before* DB lookup.

---

## 8. Validating Sessions — SELECT WHERE token AND expires_at

Never `SELECT WHERE token=?` alone — must also check expiry in SQL (DB is source of truth, not cookie `Expires` which browser can ignore):

```go
func (s *Store) FindSession(token string) (userID int64, ok bool, err error) {
    var uid int64
    var exp string
    err = s.db.QueryRow("SELECT user_id, expires_at FROM sessions WHERE token = ?", token).Scan(&uid, &exp)
    if err != nil {
        return 0, false, err // sql.ErrNoRows → invalid token
    }
    t, _ := time.Parse(time.RFC3339, exp)
    if time.Now().After(t) {
        return 0, false, nil // expired — caller will delete and redirect
    }
    return uid, true, nil
}

// atomic version — expiry in SQL, no Go Parse needed
func (s *Store) FindValidSession(token string) (int64, error) {
    var uid int64
    err := s.db.QueryRow("SELECT user_id FROM sessions WHERE token = ? AND expires_at > datetime('now')", token).Scan(&uid)
    return uid, err // ErrNoRows = invalid or expired
}
```

> [!tip] Use `AND expires_at > datetime('now')` `store.go:48` pattern — filtering in DB `store.go:74` like `expense-tracker` `List` `WHERE date BETWEEN`. Never trust cookie `Expires` alone.

---

## 9. Expiry & Cleanup — DELETE WHERE expires_at < now()

Sessions accumulate — clean expired rows periodically:

```go
func (s *Store) DeleteExpiredSessions() (int64, error) {
    res, err := s.db.Exec("DELETE FROM sessions WHERE expires_at < datetime('now')")
    if err != nil { return 0, err }
    return res.RowsAffected()
}
```

Call on startup and via `time.Ticker` `14 - Select.md:131` or on every `RequireAuth` (cheap with `idx_sessions_expires`):

```go
go func() {
    ticker := time.NewTicker(1 * time.Hour)
    defer ticker.Stop()
    for range ticker.C {
        if n, err := st.DeleteExpiredSessions(); err == nil && n > 0 {
            log.Printf("cleaned %d expired sessions", n) // 18:87
        }
    }
}()
```

> [!note] `datetime('now')` is UTC in SQLite `modernc.org/sqlite` — store `expires_at` as `time.Now().UTC().Format(time.RFC3339)` to avoid Tashkent vs UTC drift.

---

## 10. Logout — MaxAge -1 and DELETE

Logout = delete server row **and** tell browser to delete cookie `19:492`:

```go
func Logout(st *store.Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        if c, err := r.Cookie("session"); err == nil {
            st.DeleteSession(c.Value) // DELETE FROM sessions WHERE token=?
        }
        // MaxAge:-1 + Expires in past = browser deletes cookie
        http.SetCookie(w, &http.Cookie{
            Name:     "session",
            Value:    "",
            Path:     "/",
            MaxAge:   -1, // delete now 19:492
            Expires:  time.Unix(0, 0),
            HttpOnly: true,
            SameSite: http.SameSiteLaxMode,
        })
        http.Redirect(w, r, "/login", http.StatusSeeOther)
    }
}

func (s *Store) DeleteSession(token string) error {
    _, err := s.db.Exec("DELETE FROM sessions WHERE token = ?", token)
    return err
}
```

> [!warning] Must do **both** — `DELETE` without `MaxAge:-1` leaves browser cookie pointing to dead token (next request does DB miss but still sends cookie). `MaxAge:-1` without `DELETE` leaves DB row forever.

---

## 11. Cookie vs localStorage vs sessionStorage

| Storage | Where | Sent to server? | JS readable? | Use for session? |
|---|---|---|---|---|
| **Cookie** `http.Cookie` `19:469` | Browser, per `Path/Domain` | Yes — `Cookie:` header every request `02:3` | No if `HttpOnly` `02:2` | **Yes** — server reads `r.Cookie` |
| **localStorage** | Browser, per origin | No — only JS `localStorage.getItem` | Yes — `document.localStorage` | No — JS can steal via XSS `08` |
| **sessionStorage** | Browser, per tab | No | Yes | No — lost on tab close, still XSS-stealable |

> [!warning] Never store `session` token in `localStorage` — `XSS` `08` `document.localStorage.getItem` leaks it. `HttpOnly` cookie `02:2` is the only store JS cannot read.

---

## 12. SameSite — Lax vs Strict vs None + Secure

`SameSite` `19:492` controls **CSRF** `07`: attacker site `evil.com` auto-submitting `<form action="https://yourapp.com/notes/delete">` as you.

| SameSite | Browser sends cookie on `evil.com → yourapp.com` POST? | UX |
|---|---|---|
| `Lax` (recommended) | No for cross-site POST (CSRF blocked), Yes for top-level GET (link to yourapp still logged in) | Best balance `07` |
| `Strict` | No for *all* cross-site (even GET link) | User clicks link from email → appears logged out → annoying |
| `None` | Yes always — **requires** `Secure: true` (https) or browser rejects | Only for `iframe` / cross-site API |

```go
// CSRF defense in depth 07: SameSite Lax + synchronizer token
http.SetCookie(w, &http.Cookie{Name: "session", Value: token, Path: "/", HttpOnly: true, Secure: true, SameSite: http.SameSiteLaxMode})
```

> [!tip] `quicknotes` lab uses `Lax` `02:6` + hidden `csrf_token` `07` for POSTs — two layers. `Secure: true` only in prod with `TLS` `12 - HTTPS`, `false` on `localhost:8080`.

---

## 13. Common Pitfalls — The Bug Party

| Pitfall | What happens | Fix |
|---|---|---|
| `SetCookie` after `WriteHeader` | `Header()` already flushed `19:5` → `Set-Cookie` never sent, browser never stores session → always redirect to login | `SetCookie` before `Redirect`/`WriteHeader` |
| `Value` with `;` or space | Cookie parsing breaks — `Value` truncated at `;` | Use `hex.EncodeToString` (only `0-9a-f`) `02:5` |
| `Path: "/notes"` vs `"/"` | Cookie only sent to `/notes`, not `/logout` → `r.Cookie` miss on logout | `Path: "/"` for session `02:2` |
| `SELECT WHERE token=?` without expiry | Expired token still valid until manual cleanup → session never expires | `AND expires_at > datetime('now')` `02:8` |
| `MaxAge: 0` vs `-1` confusion | `0` = session cookie (dies on browser close), not delete. Delete is `-1` `19:492` | `Logout` uses `-1` `02:10` |
| `r.Cookie` without `http.ErrNoCookie` check | `token == ""` treated as DB lookup → `SELECT WHERE token=''` → `sql.ErrNoRows` logged as error | Check `err == http.ErrNoCookie` first `02:7` |
| Storing `user_id` in cookie `Value` | Client tampers `session=3` → `user_id=3` → IDOR `30` | `Value` is random token, `user_id` only in `sessions` table `02:4` |
| Not deleting expired rows | `sessions` table grows forever | `DELETE WHERE expires_at < now()` with `idx` `02:9` |

---

## 14. Project Tie-In — quicknotes + expense-tracker

**Lab `quicknotes` (separate project you chose) `Golang/Auth/§§ - About Auth.md:184`:**
- After `01` hash → `02` token → `sessions` table → `Set-Cookie` `02:6`
- Next `06 Middleware` → `RequireAuth(next http.Handler) http.Handler` `19:333` reads `r.Cookie` `02:7` → `FindValidSession` `02:8` → `r.WithContext` `19:650` with `user_id`
- `13 Storage` → every `SELECT ... WHERE user_id=?` `Golang/Auth/§§ - About Auth.md:184` uses `user_id` from context, not cookie
- `POST /notes/add` → `INSERT INTO notes (user_id, title, body) VALUES (?, ?, ?)` with `user_id` from session

**Retrofit `expense-tracker` `feature/gemini 9113d57` `Golang/Auth/§§ - About Auth.md:184`:**
- `ALTER TABLE expenses ADD COLUMN user_id INTEGER REFERENCES users(id)` + `UPDATE expenses SET user_id=1`
- Wrap `mux.HandleFunc("GET /expenses", RequireAuth(web.ListPage(st)))` `cmd/expense/main.go:21`
- Add `users` + `sessions` tables `internal/store/store.go:20`

> [!note] `quicknotes` and `expense-tracker` share identical `02` code — copy `internal/store/sessions.go` + `SetCookie`/`r.Cookie` between repos. That's hybrid profit: one bench, two products.

---

## 15. Quick Reference Cheatsheet

```go
import (
    "crypto/rand"
    "encoding/hex"
    "fmt"
    "log"
    "net/http"
    "time"
)

// Generate 32B hex token
func generateToken() (string, error) {
    b := make([]byte, 32)
    if _, err := rand.Read(b); err != nil { return "", fmt.Errorf("rand: %w", err) }
    return hex.EncodeToString(b), nil // 64 hex
}

// Create session row
_, err = db.Exec("INSERT INTO sessions (token, user_id, expires_at) VALUES (?, ?, ?)", token, userID, time.Now().Add(7*24*time.Hour).Format(time.RFC3339))
// Find valid session
var uid int64
err = db.QueryRow("SELECT user_id FROM sessions WHERE token=? AND expires_at > datetime('now')", token).Scan(&uid)
// Delete expired
db.Exec("DELETE FROM sessions WHERE expires_at < datetime('now')")
// Logout
http.SetCookie(w, &http.Cookie{Name: "session", Value: "", Path: "/", MaxAge: -1, Expires: time.Unix(0,0), HttpOnly: true, SameSite: http.SameSiteLaxMode})
db.Exec("DELETE FROM sessions WHERE token=?", token)

// Set cookie (must be before WriteHeader)
http.SetCookie(w, &http.Cookie{
    Name: token, Value: token, Path: "/", Expires: time.Now().Add(7*24*time.Hour),
    MaxAge: 7*24*3600, HttpOnly: true, Secure: false, SameSite: http.SameSiteLaxMode,
})
// Read cookie
c, err := r.Cookie("session")
if err == http.ErrNoCookie { /* redirect /login */ }
token := c.Value

// Cookie fields 19:469
// Name, Value, Path="/", Domain="", Expires, MaxAge (0 session, -1 delete 19:492), HttpOnly true, Secure true in prod, SameSite Lax
```

> [!practice] Bench + prove: `curl -c jar.txt -d "email=a@b.com&password=secret123" http://localhost:8080/login` → `Set-Cookie: session=...` → `curl -b jar.txt http://localhost:8080/notes` → 200, `curl -b jar.txt http://localhost:8080/logout` → `Set-Cookie: session=; Max-Age=0` + DB row gone. Prove `r.Cookie` miss after `MaxAge:-1` via `sqlite3 expense.db "SELECT COUNT(*) FROM sessions"`.
---

_Previous: [[01 - Passwords & Hashing]] · Next: [[06 - Middleware & Context]]_ // Hybrid Phase 1: 00→01→02→13→06→14 — numeric Next is 03 JWT but Phase 1 Next is 06 per §§ - About Auth.md:183
