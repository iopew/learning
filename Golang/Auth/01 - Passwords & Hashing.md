# Auth — Passwords & Hashing

> **Series:** Auth **Tags:** #auth #security #passwords #hashing #bcrypt #golang #cryptography **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. Why Hashing — Never Store Plain]]
- [[#2. bcrypt in Go — The Two Functions]]
- [[#3. Cost — The Slowness Knob]]
- [[#4. Salt — Built Into the Hash String]]
- [[#5. How the Hash String Looks — Decoding `$2a$12$...`]]
- [[#6. Comparing — Constant-Time and Why]]
- [[#7. Pepper — Environment Secret on Top]]
- [[#8. Validation Before Hashing]]
- [[#9. AuthN vs AuthZ in One Glance (Sessions vs JWT) — Deeper Link to 31]]
- [[#10. Never Log Plain — The Error Handling Shape]]
- [[#11. Argon2id vs bcrypt vs scrypt — When to Switch]]
- [[#12. Cost Tuning — Bench on Your Machine]]
- [[#13. Common Pitfalls — The Bug Party]]
- [[#14. Project Tie-In — quicknotes + expense-tracker]]
- [[#15. Quick Reference Cheatsheet]]

---

## 1. Why Hashing — Never Store Plain

Storing `password = "secret123"` in `users.password_hash` means a single `SELECT` leak (backup, `sqlite3` dump, log) compromises every user forever — and users reuse passwords across sites.

Hashing is **one-way**: `password → hash` is cheap, `hash → password` is infeasible. Go checks by hashing the candidate the same way and comparing hashes, not by decrypting.

```go
// ❌ NEVER
db.Exec("INSERT INTO users (email, password) VALUES (?, ?)", email, password)

// ✅ ALWAYS
hash, _ := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
db.Exec("INSERT INTO users (email, password_hash) VALUES (?, ?)", email, string(hash))
```

> [!warning] Hashing ≠ Encryption
> Encryption is reversible (`encrypt → decrypt` with a key). Hashing is not — there is no `Decrypt(hash)`. If you can decrypt it, it’s not a password hash.

> [!note] Go has no `hash(password)` stdlib for passwords — `crypto/sha256` is *not* a password hash (too fast, no salt). Use `golang.org/x/crypto/bcrypt` or `argon2`.

---

## 2. bcrypt in Go — The Two Functions

Only two you call. Both live in `golang.org/x/crypto/bcrypt`.

```go
import "golang.org/x/crypto/bcrypt"

// 1. Hash on signup — password string → hash string
hash, err := bcrypt.GenerateFromPassword([]byte("secret123"), bcrypt.DefaultCost)
if err != nil { // only if cost out of range or password too long (72 bytes)
    return fmt.Errorf("hash: %w", err)
}
fmt.Println(string(hash)) // $2a$12$...

 // 2. Compare on login — hash string + candidate → nil or error
err = bcrypt.CompareHashAndPassword(hash, []byte("secret123"))
fmt.Println(err == nil) // true  — correct password
err = bcrypt.CompareHashAndPassword(hash, []byte("wrong"))
fmt.Println(err) // crypto/bcrypt: hashedPassword is not the hash of the given password
```

> [!info] Both take `[]byte`, not `string`. Convert with `[]byte(password)` on the way in, `string(hash)` on the way out for DB storage. The hash is ASCII-safe.

### Minimal signup/login handlers (mirrors `quicknotes` lab)

```go
func Signup(st *store.Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        email := strings.TrimSpace(r.FormValue("email"))
        password := r.FormValue("password") // never TrimSpace password — spaces are valid

        if email == "" || password == "" {
            http.Redirect(w, r, "/signup?err="+url.QueryEscape("email and password required"), http.StatusSeeOther)
            return
        }
        if len(password) < 8 {
            http.Redirect(w, r, "/signup?err="+url.QueryEscape("password must be at least 8"), http.StatusSeeOther)
            return
        }

        hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost) // cost 10
        if err != nil {
            http.Error(w, "hash failed", http.StatusInternalServerError)
            return
        }
        _, err = st.CreateUser(email, string(hash)) // INSERT users
        if err != nil {
            // UNIQUE violation → errors.Is(err, sqliteErr) or string check
            http.Redirect(w, r, "/signup?err="+url.QueryEscape("email taken"), http.StatusSeeOther)
            return
        }
        http.Redirect(w, r, "/login", http.StatusSeeOther)
    }
}

func Login(st *store.Store) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        email := strings.TrimSpace(r.FormValue("email"))
        password := r.FormValue("password")

        hash, err := st.FindHashByEmail(email) // SELECT password_hash WHERE email=?
        if err != nil {
            http.Redirect(w, r, "/login?err="+url.QueryEscape("invalid credentials"), http.StatusSeeOther)
            return
        }
        if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)); err != nil {
            http.Redirect(w, r, "/login?err="+url.QueryEscape("invalid credentials"), http.StatusSeeOther)
            return
        }
        // success → create session + Set-Cookie (see [[02 - Sessions & Cookies]] §3)
        http.Redirect(w, r, "/notes", http.StatusSeeOther)
    }
}
```

> [!tip] Always return *identical* error messages for “email not found” and “wrong password” — `invalid credentials`. Different messages leak which emails exist (enumeration).

---

## 3. Cost — The Slowness Knob

`GenerateFromPassword` second arg is `cost` (4–31). It does `2^cost` iterations of Blowfish.

| Cost | Approx time on M1 Mac | Security | Use |
|---|---|---|---|
| 4 | ~0.3ms | Testing only | `go test` — fast |
| 10 | ~75ms | `DefaultCost` — current default | Signup/login in prod |
| 12 | ~300ms | Stronger — recommended 2024+ | Your `quicknotes` lab — good balance |
| 14 | ~1.2s | Very strong | High-value apps |

```go
bcrypt.DefaultCost // 10
bcrypt.MinCost     // 4
bcrypt.MaxCost     // 31

hash, _ := bcrypt.GenerateFromPassword([]byte(pw), 12) // 2^12 iterations
cost, _ := bcrypt.Cost(hash) // 12 — reads cost back from hash string
```

> [!warning] Cost is exponential — `12` is 4× slower than `10`, not 20% slower. Benchmark on *your* machine (see §11) and on *your* host (Fly free tier is slower than M1). Pick the highest cost where login still feels instant (<400ms).

> [!info] Cost is stored *inside* the hash (see §5). Raising cost later does not break old hashes — old logins still `Compare` with cost 10, new signups use cost 12. No migration needed until user logs in next.

### Cost 4 for tests — the speed trick

```go
func TestSignup(t *testing.T) {
    hash, err := bcrypt.GenerateFromPassword([]byte("secret"), 4) // MinCost — fast
    if err != nil { t.Fatal(err) }
    if err := bcrypt.CompareHashAndPassword(hash, []byte("secret")); err != nil {
        t.Error("should match")
    }
}
```

Never use cost 4 in prod — `go test -run TestSignup` should be fast, `POST /login` should be slow.

---

## 4. Salt — Built Into the Hash String

A **salt** is 16 random bytes prepended before hashing. Without salt, two users with `password="123456"` have identical hashes — one crack reveals both, plus rainbow tables (precomputed `hash → password` maps) work.

bcrypt **generates a fresh salt automatically** on every `GenerateFromPassword` call — you never supply it.

```go
h1, _ := bcrypt.GenerateFromPassword([]byte("secret"), 12)
h2, _ := bcrypt.GenerateFromPassword([]byte("secret"), 12)
fmt.Println(string(h1) == string(h2)) // false — different salts, different hashes
fmt.Println(bcrypt.CompareHashAndPassword(h1, []byte("secret")) == nil) // true
fmt.Println(bcrypt.CompareHashAndPassword(h2, []byte("secret")) == nil) // true — both verify
```

> [!note] You don’t store salt separately. It’s encoded inside the hash string (see §5). `CompareHashAndPassword` extracts it internally.

---

## 5. How the Hash String Looks — Decoding `$2a$12$...`

```text
$2a$12$L0eb1p6aGe9G8a2rKg3qOeXyZ9q8aBcDeFgHiJkLmNoPqRsTuVwXy
│  │  │└────────────── 31 chars: salt (22) + hash (31) base64 ──────────────┘
│  │  └ 22 chars base64 salt (16 bytes)
│  └ cost = 12
└ version = 2a (bcrypt variant; 2b is newer Go, both verify each other)
```

Full length is always **60 chars** for bcrypt:

```go
hash, _ := bcrypt.GenerateFromPassword([]byte("secret"), 12)
fmt.Println(len(hash)) // 60
fmt.Println(string(hash[:4])) // $2a$
fmt.Println(string(hash[4:6])) // 12

cost, _ := bcrypt.Cost(hash) // 12
```

> [!tip] Store `password_hash TEXT NOT NULL` — `VARCHAR(60)` is enough for bcrypt, but use `TEXT` so future Argon2 (longer) fits without `ALTER`. Never `VARCHAR(20)` — truncates hash and every login fails.

---

## 6. Comparing — Constant-Time and Why

`CompareHashAndPassword` is **constant-time** — it takes the same time for `wrong` vs `almost-right` candidates. A naive `hash == hash` leaks timing: attacker measures response time to guess how many prefix chars are correct.

```go
// ❌ Naive — leaks timing, plus you must hash candidate yourself
candidateHash, _ := bcrypt.GenerateFromPassword([]byte(candidate), 12)
if string(candidateHash) == string(storedHash) { ... } // wrong — different salts → never equal, plus timing leak

// ✅ Correct — constant-time, handles salt extraction
if err := bcrypt.CompareHashAndPassword(storedHash, []byte(candidate)); err != nil {
    // invalid credentials — same path, same timing for any wrong password
}
```

> [!warning] `CompareHashAndPassword` returns `nil` on match, `error` on mismatch — never `bool`. Check `err == nil`, not `err != nil` for success. The error is always `crypto/bcrypt: hashedPassword is not the hash of the given password` — don’t leak it to client, just `invalid credentials`.

---

## 7. Pepper — Environment Secret on Top

**Salt** is per-password (stored in hash, public). **Pepper** is per-application (one secret for all passwords, *not* stored in DB, lives in env `GEMINI_API_KEY` pattern `gemini.go:14`).

```go
pepper := os.Getenv("PEPPER") // 32 random bytes hex, set via fly secrets / .env gitignored

func hashWithPepper(password, pepper string) ([]byte, error) {
    // HMAC-SHA256 with pepper as key, then bcrypt
    mac := hmac.New(sha256.New, []byte(pepper))
    mac.Write([]byte(password))
    peppered := mac.Sum(nil) // 32 bytes
    return bcrypt.GenerateFromPassword(peppered, 12)
}
func compareWithPepper(hash []byte, password, pepper string) error {
    mac := hmac.New(sha256.New, []byte(pepper))
    mac.Write([]byte(password))
    peppered := mac.Sum(nil)
    return bcrypt.CompareHashAndPassword(hash, peppered)
}
```

| | Stored where | Rotatable | If DB leaks |
|---|---|---|---|
| **Salt** | Inside hash (public) | No — per hash | Still need brute force per password |
| **Pepper** | Env (not DB) | Yes — rotate pepper, re-hash on next login | Attacker has hashes but missing pepper → cannot brute force without also stealing env |

> [!note] Pepper is optional for `quicknotes` lab — add it only after core works. If you add it, keep `PEPPER` out of `go.mod` and out of git — `echo "PEPPER=..." >> .env` ` .gitignore:12 .env` same as `GEMINI_API_KEY`.

---

## 8. Validation Before Hashing

Bcrypt has hard limits — validate *before* calling it.

```go
func validatePassword(pw string) error {
    if len(pw) < 8 {
        return errors.New("password must be at least 8 characters")
    }
    if len(pw) > 72 {
        return errors.New("password must be at most 72 characters") // bcrypt limit
    }
    if strings.TrimSpace(pw) != pw {
        // optional — you may allow leading/trailing spaces (they are valid), but many apps reject to avoid copy-paste traps
    }
    // common-password blocklist (10k most common) — see note below
    if commonPasswords[pw] {
        return errors.New("password too common")
    }
    return nil
}
```

> [!warning] bcrypt **truncates at 72 bytes**, not 72 characters. `strings.Repeat("a", 100)` → only first 72 bytes matter. `Validate` must reject `>72 bytes` before hashing, else `password` and `password+"extra"` hash identically.

> [!info] `strings.TrimSpace` `18 - Standard Library.md:218` on **email**, never on **password** — ` " secret "` with spaces is a valid password; trimming it changes what user typed. For email: `email = strings.ToLower(strings.TrimSpace(email))`.

Common-password blocklist — keep a `map[string]struct{}` `06 - Maps.md:472` set of 10k entries (haveibeenpwned top 10k), loaded once with `sync.Once` `15 - Sync Primitives.md:163` or `embed` `21 - File I/O.md`:

```go
//go:embed common_passwords.txt
var commonRaw string
var commonPasswords map[string]struct{}
var once sync.Once
func isCommon(pw string) bool {
    once.Do(func() {
        commonPasswords = make(map[string]struct{}, 10000)
        for _, line := range strings.Split(commonRaw, "\n") {
            commonPasswords[strings.TrimSpace(line)] = struct{}{}
        }
    })
    _, ok := commonPasswords[strings.ToLower(pw)]
    return ok
}
```

---

## 9. AuthN vs AuthZ in One Glance (Sessions vs JWT) — Deeper Link to [[31 - Authentication vs Authorization (Sessions, JWT, OAuth basics)]]

You are on `01` now — this is the capstone at a glance so `01` is self-contained before `31` (at end) exists. Full `31 - Authentication vs Authorization` is the separate short note at the end.

- **AuthN (Authentication) = who you are:** `email + password` → `bcrypt.CompareHashAndPassword` `01 - Passwords` → `session cookie` `02 - Sessions & Cookies` `19 - net:http.md:469` or `JWT` `03 - JWT` `Authorization: Bearer`. Answers *“Are you Alice?”* — this `01` is AuthN.
- **AuthZ (Authorization) = what you can do:** `WHERE user_id=?` `13 - Storage & DB` `store.go:48`, `roles admin/member` `09 - RBAC`, `CSRF gate` `21 - CSRF`. Answers *“May Alice delete note 5?”* → `WHERE id=? AND user_id=?` `30 - IDOR` vs `WHERE id=?` leak → horizontal vs vertical. `RequireAuth` `06 - Middleware` is AuthN gate, `RequireRole` is AuthZ gate.
- **Session vs JWT:** `session` = server memory `sessions(token PK)` `02` — revocable `DELETE + MaxAge:-1`; `JWT` = self-carried `header.payload.signature` `03` — stateless but needs blocklist. `quicknotes` lab uses `session` first, `Bearer` later for `17 - Mobile & API`.
- **When AuthN vs AuthZ matters for `01`:** `01` validates `len(pw)<8` → `400 Bad Request` `14 - Validation` (not `401` AuthN), and never logs `password` `10 - Never Log Plain` — AuthZ checks `user_id` only after AuthN succeeded.

> [!note] Full `AuthN vs AuthZ` (sessions vs JWT vs OAuth, RBAC vs ABAC, when to use which) lives in `[[31 - Authentication vs Authorization (Sessions, JWT, OAuth basics)]]` — separate short topic at the end, not here. This `§9` is just the one-glance map.

---

## 10. Never Log Plain — The Error Handling Shape

```go
// ❌ Leaks to logs, terminal, and maybe to client via ?err=
fmt.Printf("login failed for %s password %s: %v\n", email, password, err)
http.Redirect(w, r, "/login?err="+url.QueryEscape(password), http.StatusSeeOther)

// ✅ Only log email + error, never password; client gets generic message
fmt.Println("login failed for", email, ":", err) // 11 - Error Handling.md:34
http.Redirect(w, r, "/login?err="+url.QueryEscape("invalid credentials"), http.StatusSeeOther)

// Store: TEXT NOT NULL `password_hash`, never `password`
_, err = db.Exec("INSERT INTO users (email, password_hash) VALUES (?, ?)", email, string(hash))
if err != nil {
    // UNIQUE violation → errors.Is(err, sqliteErr) `11 - Error Handling.md:289`
    return fmt.Errorf("create user %s: %w", email, err) // %w preserves chain `11 - Error Handling.md:558`
}
```

> [!warning] `log.Printf("hash %s", hash)` is also sensitive — hash + pepper still helps offline cracking. Log `user_id` and `email` only.

---

## 11. Argon2id vs bcrypt vs scrypt — When to Switch

| Algorithm | Type | Memory-hard | Go package | Hash length | When to use |
|---|---|---|---|---|---|
| **bcrypt** `golang.org/x/crypto/bcrypt` | Adaptive | No (CPU-hard) | `x/crypto/bcrypt` | 60 | **Default for 99% — what you use in `quicknotes` lab** |
| **Argon2id** `x/crypto/argon2` | Memory-hard | **Yes** | `golang.org/x/crypto/argon2` | ~97+ | High-value (banking, admin) — resists GPU/ASIC cracking |
| **scrypt** `x/crypto/scrypt` | Memory-hard | Yes | `x/crypto/scrypt` | variable | Older memory-hard, Argon2id preferred now |

```go
// Argon2id — for reference, NOT needed for lab (cost tuned differently)
import "golang.org/x/crypto/argon2"
salt := make([]byte, 16)
rand.Read(salt)
hash := argon2.IDKey([]byte(password), salt, 3, 64*1024, 4, 32) // time=3, memory=64MB, threads=4
// must store salt+params alongside hash yourself — bcrypt does this automatically, Argon2 does not
```

> [!tip] Stick with **bcrypt** for the entire `Auth` Phase 1-2. Switch to Argon2id only in `20 - Patterns & Idioms.md` if you need memory-hard for a high-value project. The stdlib `slices` analogy `16 - Generics.md:276` applies — use the stdlib/battle-tested default first.

---

## 12. Cost Tuning — Bench on Your Machine

Bcrypt cost must be tuned to *your* host (M1 vs Fly free tier differ 2×).

```go
func BenchmarkBcrypt(b *testing.B) {
    for _, cost := range []int{10, 12, 14} {
        b.Run(fmt.Sprintf("cost%d", cost), func(b *testing.B) {
            for i := 0; i < b.N; i++ {
                bcrypt.GenerateFromPassword([]byte("bench-password-123"), cost)
            }
        })
    }
}
// go test -bench=BenchmarkBcrypt -benchmem
// BenchmarkBcrypt/cost10-8    12  75ms/op
// BenchmarkBcrypt/cost12-8     3  310ms/op
// BenchmarkBcrypt/cost14-8     1  1250ms/op
```

**Rule:** pick highest cost where `POST /login` still <400ms at p95 on your host. For `quicknotes` on Fly free, cost 10 is often right; on M1, cost 12.

> [!practice] Bench on *both* machines: `go test -bench=.` locally, then `fly ssh console -C "go test -bench=."` on host. Set `const bcryptCost = 12` as a package `const` so tuning is one line.

---

## 13. Common Pitfalls — The Bug Party

| Pitfall | What happens | Fix |
|---|---|---|
| `len(pw) > 72` not checked | `password` and `password+"xxx"` truncate → same hash | Validate `len(pw) <= 72` before hash |
| `cost=4` in prod | `3072×` faster to brute force | `const cost = 12` prod, `cost=4` only in `*_test.go` |
| `string(candidateHash) == string(storedHash)` | Always false (different salts) + timing leak | `CompareHashAndPassword` only |
| `TrimSpace(password)` | Changes user’s password, login with spaces fails | `TrimSpace` on `email` only |
| Log `password` or `hash` | Leak in `expense.db` backup + logs | Log `email` + `err` only |
| `VARCHAR(60)` truncated | New hash doesn’t fit, every login fails | `TEXT` for `password_hash` |
| Two `GenerateFromPassword` with same `password` → expect equal | Not equal — salt random | Compare via `CompareHashAndPassword`, not `==` |
| `err == bcrypt.ErrMismatchedHashAndPassword` vs `errors.Is` | Wrapped `%w` fails with `==` | `errors.Is(err, bcrypt.ErrMismatchedHashAndPassword)` `11 - Error Handling.md:289` |

> [!warning] `bcrypt.CompareHashAndPassword` returns `ErrMismatchedHashAndPassword` on wrong password — always check with `errors.Is`, not `==`, if you ever wrap it `fmt.Errorf("login: %w", err)`.

---

## 14. Project Tie-In — quicknotes + expense-tracker

**Lab `quicknotes` (separate project you chose):**
- `POST /signup` → validate `01 - Passwords & Hashing.md:8` → `GenerateFromPassword(cost 12)` → `INSERT users (email, password_hash)` → `303 /login`
- `POST /login` → `SELECT password_hash WHERE email=?` → `CompareHashAndPassword` → on `nil` create `sessions` row + `Set-Cookie` `02 - Sessions & Cookies.md` → `RequireAuth` `06 - Middleware & Context.md`

**Back to `expense-tracker` `feature/gemini 9113d57`:**
- Add `users` table to `expense.db` `internal/store/store.go:20` `CREATE TABLE IF NOT EXISTS users ...`, add `password_hash TEXT NOT NULL`
- Wrap `mux.HandleFunc("GET /expenses", RequireAuth(web.ListPage(st)))` `cmd/expense/main.go:20` — same `RequireAuth` factory `04 - Functions.md:617` as lab
- Existing 19 rows `SELECT COUNT(*)=19` get `user_id = your ID` via `UPDATE expenses SET user_id=1 WHERE user_id IS NULL` after adding column `ALTER TABLE expenses ADD COLUMN user_id INTEGER REFERENCES users(id)`

> [!note] `quicknotes` and `expense-tracker` share the **identical** password file — copy `internal/web/auth.go` between repos. That’s the hybrid profit: one bench, two products.

---

## 15. Quick Reference Cheatsheet

```go
// Hash on signup
hash, err := bcrypt.GenerateFromPassword([]byte(password), 12) // 60 chars, salt auto
if err != nil { /* cost out of range or pw >72B */ }
db.Exec("INSERT INTO users (email, password_hash) VALUES (?, ?)", email, string(hash))

// Compare on login
storedHash, _ := st.FindHashByEmail(email) // SELECT password_hash
if err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(candidate)); err != nil {
    // err == ErrMismatchedHashAndPassword → invalid credentials
}

// Cost
bcrypt.DefaultCost // 10
bcrypt.Cost(hash) // reads cost from hash string (e.g. 12)
cost4ForTests := 4 // MinCost — tests only

// Validation before hash
if len(pw) < 8 || len(pw) > 72 { /* reject */ }
email = strings.ToLower(strings.TrimSpace(email)) // email yes, password never

// Pepper (optional, after core works)
mac := hmac.New(sha256.New, []byte(os.Getenv("PEPPER")))
mac.Write([]byte(password)); peppered := mac.Sum(nil)
bcrypt.GenerateFromPassword(peppered, 12)

// Never
fmt.Println(password) // leak
string(hash) == string(otherHash) // always false, use Compare
```

> [!practice] Bench + validate: `go test -bench=BenchmarkBcrypt` with costs 10/12/14, then write `validatePassword` that rejects `<8`, `>72`, and `commonPasswords` set `06 - Maps.md:472` via `embed` `21 - File I/O.md`. Prove by `curl -c jar -b jar -X POST -d "email=a@b.com&password=short"` hitting `400` then `invalid credentials`.

---

_Previous: [[00 - Overview]] · Next: [[02 - Sessions & Cookies]]_
