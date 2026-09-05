# Auth (Authentication & Authorization)

## What is it?

Authentication (**AuthN**) is **who you are** — proving identity (email + password, session cookie, JWT, OAuth). Authorization (**AuthZ**) is **what you can do** — whether that identity may read/write a resource (owner check `WHERE user_id=?`, roles `admin/member`, CSRF gate). Go implements both with stdlib `net/http` + `database/sql` + `golang.org/x/crypto/bcrypt` — no framework needed.

---

## Why use it?

| Strength                       | Detail                                                                                                                                  |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| Sessions are revocable         | DB row `sessions(token PK, user_id FK, expires_at)` — logout = `DELETE` + `MaxAge:-1`, unlike JWT which lives until `exp`               |
| Cookie `HttpOnly` + `SameSite` | Browser enforces XSS/CSRF defenses automatically — no JS can read `HttpOnly` `19 - net:http.md:490`                                     |
| Middleware is composition      | `RequireAuth(next http.Handler) http.Handler` `19 - net:http.md:333` wraps any handler — onion `next.ServeHTTP` chain, zero duplication |
| Bcrypt is adaptive             | Cost factor grows with hardware — `GenerateFromPassword` cost 12 today, still safe in 2030                                              |
| Single `user_id` guard         | One `AND user_id=?` on every query gives per-user isolation — same pattern for `expenses` and `notes`                                   |
| Stdlib only                    | No `gin/echo` — `http.Cookie`, `context.WithValue`, `crypto/rand`, `html/template` auto-escape cover the whole flow                     |

---

## Where it's used

- Web login flows — `GET /login` form → `POST /login` → `Set-Cookie` → `RequireAuth` → `GET /expenses` or `GET /notes`
- API + mobile — `Authorization: Bearer <jwt>` `19 - net:http.md:525` `http.NewRequest` header, same `RequireAuth` checks cookie *or* bearer
- OAuth — `Sign in with Google` → authorization code + PKCE → `ID token`
- Per-resource guards — `DELETE FROM notes WHERE id=? AND user_id=?` — row-level AuthZ

**Real-world examples:** Every `expense-tracker` `POST /expenses/*` will be wrapped; `quicknotes` lab will be built on this stack; `Gemini` `GEMINI_API_KEY` `.env` pattern `gemini.go:14` is the same secret handling.

---

## Weaknesses

- Session DB is a hotspot — every request reads `sessions` (needs `INDEX` + `expires_at` cleanup)
- Cookie theft via XSS if `HttpOnly` forgotten — `document.cookie` leaks
- CSRF without `SameSite` or hidden token — attacker site `POST`s as you `03 - Lessons Learned.md:18`
- Bcrypt is slow by design — login ~100ms, needs rate limiting or brute force wins
- JWT revocation is hard — logout must be blocklist, not `DELETE`
- `context.WithValue` with string keys collides — must use own `type ctxKey string` `19 - net:http.md:649`

---

## Key Concepts

```text
Auth/
├── 00 - Overview.md
│     What Auth is, AuthN vs AuthZ vs Session vs Identity,
│     stateless HTTP `19 - net:http.md:40`, cookies as memory,
│     where Auth lives (web/API/mobile), threat model (OWASP top 10)
│
├── 01 - Passwords & Hashing.md           ← Phase 1 Core
│     bcrypt (GenerateFromPassword/CompareHashAndPassword, cost, salt, adaptive),
│     Argon2id vs bcrypt vs scrypt, pepper, timing attacks, password validation
│     (length, TrimSpace, common-password blocklist), never log plain
│
├── 02 - Sessions & Cookies.md            ← Phase 1 Core
│     Set-Cookie/Cookie `19 - net:http.md:469`, attributes
│     (Name, Value, Path, Domain, HttpOnly, Secure, SameSite Lax/Strict/None,
│     MaxAge, Expires), session table (token PK, user_id FK, expires_at),
│     crypto/rand 32B hex, session expiry + cleanup, cookie vs localStorage
│
├── 03 - JWT.md                          ← Phase 3 Advanced (after lab works)
│     header.payload.signature, HS256 vs RS256, base64url, claims (sub, exp, iat, iss),
│     encoding/json `20 - encoding/json` + base64, JWT vs sessions tradeoffs,
│     revocation (blocklist), refresh tokens, `Authorization: Bearer`
│
├── 04 - OAuth 2.0.md                    ← Phase 3 Advanced
│     Roles (resource owner, client, auth server, resource server),
│     grant types (authorization code + PKCE S256, client credentials, refresh),
│     scopes, authorization code flow diagram, state param, redirect_uri validation
│
├── 05 - OpenID Connect.md               ← Phase 3 Advanced
│     ID token vs access token, openid scope, /userinfo, nonce, OIDC vs OAuth,
│     claims (email, email_verified), discovery /.well-known/openid-configuration
│
├── 06 - Middleware & Context.md         ← Phase 1 Core
│     RequireAuth(next http.Handler) `19 - net:http.md:333`, Handler interface
│     `19 - net:http.md:103`, HandlerFunc adapter `19 - net:http.md:117`, closure factory
│     `04 - Functions.md:617`, r.Cookie `19 - net:http.md:479`, r.WithContext
│     `19 - net:http.md:650`, type ctxKey string collision, onion chaining
│
├── 07 - CSRF.md                        ← Phase 2 Hardening
│     SameSite `19 - net:http.md:492`, hidden csrf_token (uuid/crypto/rand),
│     double-submit, state for OAuth, synchronizer token, SameSite Lax vs Strict,
│     why POST for mutations `01 - Milestones.md:13`
│
├── 08 - XSS & Injection.md             ← Phase 2 Hardening
│     html/template auto-escape `19 - net:http.md:229`, database/sql ? placeholders
│     `store.go:33` vs concat, TrimSpace validation `18 - Standard Library.md:218`,
│     Content-Security-Policy, HttpOnly as XSS mitigation
│
├── 09 - RBAC & ABAC.md                 ← Phase 2 Hardening
│     Roles table (role CHECK admin,member), user_roles JOIN, row-level
│     WHERE user_id=? isolation (quicknotes/expenses), RequireRole middleware,
│     ABAC attributes (owner, status), policy decision point
│
├── 10 - Email Verification & Password Reset.md  ← Phase 3 Advanced
│     verification_tokens(token PK, user_id, type, expires_at), crypto/rand hex,
│     one-time use, MaxAge:-1 delete, Send via net/smtp or Resend, timing
│
├── 11 - Rate Limiting & Brute Force.md ← Phase 2 Hardening
│     sync.Mutex `15 - Sync Primitives.md:90` counter per IP/email, 429
│     `19 - net:http.md:274`, time.After `14 - Select.md:131`, golang.org/x/time/rate,
│     exponential backoff, account lockout
│
├── 12 - HTTPS & Transport.md            ← Phase 3 Production
│     TLS ListenAndServeTLS `19 - net:http.md:96`, Secure cookie, HSTS,
│     ReadTimeout/WriteTimeout `19 - net:http.md:592`, cert (Let's Encrypt),
│     Secure flag in prod, HSTS preload
│
├── 13 - Storage & DB.md                ← Phase 1 Core
│     users UNIQUE `06 - Maps.md:48` index, FK ON DELETE CASCADE, migrations,
│     sql.ErrNoRows `11 - Error Handling.md:259` + errors.Is `11 - Error Handling.md:289`,
│     Null handling `store.go:74`, transactions `sql.Tx`, INDEX idx_notes_user_status
│
├── 14 - Validation & Errors.md         ← Phase 1 Core
│     strings.TrimSpace `18 - Standard Library.md:218`, net/url.ParseRequestURI,
│     11 - Error Handling.md:34 error interface + wrapping %w, flash cookie one-time
│     `19 - net:http.md:465`, 400 vs 401 vs 403 `19 - net:http.md:274`
│
├── 15 - Testing Auth.md                ← Phase 2 Hardening
│     httptest.NewRequest/NewRecorder/NewServer `19 - net:http.md:669`,
│     go test -race `15 - Sync Primitives.md:90`, table-driven tests
│     `22 - Testing.md`, helper t.Helper, cookie jar, -cover
│
├── 16 - Frontend Auth.md               ← Phase 2 Hardening
│     GET /login form enctype `03 - Lessons Learned.md:17`, POST FormValue
│     `19 - net:http.md:155`, flash {{if .Flash}} `list.html:11`, autofocus,
│     preserving input on error, password type="password"
│
├── 17 - Mobile & API Auth.md           ← Phase 3 Advanced
│     Authorization: Bearer <jwt> `19 - net:http.md:525` NewRequest header,
│     GET /api/notes JSON `20 - encoding/json`, cookie vs token for app,
│     refresh flow, http.Client{Timeout} `19 - net:http.md:545`
│
├── 18 - OAuth Providers.md             ← Phase 3 Advanced
│     Google/GitHub provider, state + PKCE S256, http.Client{Timeout},
│     GEMINI_API_KEY .env pattern `gemini.go:14`, token exchange, /userinfo fetch
│
├── 19 - Security Headers & Hardening.md ← Phase 3 Production
│     Content-Security-Policy, X-Frame-Options, X-Content-Type-Options,
│     Secure+HttpOnly audit, log/slog `18 - Standard Library.md:460`, audits
│
└── 20 - Patterns & Idioms.md           ← Phase 3 Production
      Factory Auth(st) `04 - Functions.md:617`, functional options
      `17 - Packages & Modules.md`, sync.Once for pepper load `15 - Sync Primitives.md:163`,
      worker pool for email send `12 - Goroutines.md:869`, embed for static
```

## Hybrid Learning Path — Most Useful + Practical + Theoretical Profit (Recommended Execution Order)

**Why hybrid:** `§§ - About Golang.md` pure theory-first worked for Golang 01-19 because each note had its own bench. Auth’s 21 notes converge on *one* bench (`quicknotes` `notes` + `url/tags` + `status`). Reading all 21 before code = 4 weeks, 30% retention. Building cold = cargo-cult. Hybrid pairs *immediately useful* theory with same-day code — 70% retention, shippable in 12 days.

**Execution order (file numbers stay stable for links; follow this path, not numeric order):**

**Phase 1 — Core Lab (Days 1-6, 5 notes → shippable auth):**
`00 Overview` → `01 Passwords` → `02 Sessions & Cookies` → `13 Storage & DB` → `06 Middleware & Context` → `14 Validation & Errors`
*Bench after Phase 1:* `POST /signup`/`POST /login`/`RequireAuth`/`WHERE user_id=?` works. You can already retrofit `expense-tracker` M7.

**Phase 2 — Hardening While Building CRUD (Days 7-12, 6 notes):**
`07 CSRF` → `08 XSS` → `09 RBAC` → `11 Rate Limiting` → `15 Testing` → `16 Frontend Auth`
*Bench:* `POST /notes/add` + `status/tags/url` CRUD with `AND user_id=?` guard, `SameSite` + token, `html/template` escape, `RequireRole`, `429` + `httptest`.

**Phase 3 — Advanced Theory (Days 13+, after lab is green):**
`03 JWT` (needs `20 - encoding/json` `← NEXT`) → `04 OAuth 2.0` → `05 OIDC` → `17 Mobile & API` → `18 OAuth Providers` → `10 Email Verification` → `12 HTTPS` → `19 Headers` → `20 Patterns`
*Bench:* `Bearer` API for future Android/iPhone, `Sign in with Google`.

> **File numbers never change — only this path changes.** If you prefer sequential numeric order, ignore this section. Hybrid is the profit path for your 2-3 week `quicknotes` goal.

# Prompts

I’d like to learn about Auth — Passwords & Hashing in Go comprehensively with detailed examples. Include all the data, so that I have no questions left. Just Everything. Make it copyable for Obsidian. Include all the nuances, problems, limitations and advantages. Make very clear and engaging. Use a lot of examples with detailed explanation

---

Make questions for anki until the end of 06 - Middleware section. Avoid Yes\No questions. Make them contemplative and complex. Include coding. Make a lot of questions, do not limit yourself to a few questions for the section, make a lot of them, so that YOU COVER EVERYTHING, do not miss anything. I expect a MINIMUM of 50 questions

---

---

## Context for Claude

I am learning **Auth (Authentication & Authorization)** from scratch, building a comprehensive Obsidian note vault as I go. Here is everything you need to know to continue helping me effectively.

---

### My Setup

- **Editor:** Obsidian (notes use wikilinks `[[#Section]]`, callout blocks `> [!warning]`, `> [!tip]`, `> [!info]`)
- **Platform:** Mac
- **Location:** Tashkent, Uzbekistan
- **Learning tools:** Anki (flashcards with spaced repetition), YouTube videos
- **Go knowledge level:** Beginner → Intermediate (01-19 ✅ DONE per `§§ - About Golang.md`), Auth is greenfield but reuses `net/http` + `database/sql`
- **Project tie-in:** `go-auth-crud-lab` / `quicknotes` lab (`~/Documents/Developer/quicknotes`) will be the hands-on bench for every Auth note; `expense-tracker` `feature/gemini 9113d57` is the target to retrofit after lab

---

### Note Style & Preferences

Every Obsidian note follows this structure:

- File name: `NN - Topic.md` (zero-padded number, e.g. `01 - Passwords & Hashing.md`)
- `# Auth — Topic` H1 (NOT frontmatter-YAML; the metadata is a blockquote on line 3: `> **Series:** Auth **Tags:** #auth #security ... **Level:** Beginner → Intermediate`)
- `## Table of Contents` with `[[#Section]]` wikilinks
- Sections numbered `## 1.`, `## 2.`, ... (subsections `### 1.1`)
- Obsidian callout blocks: `> [!note]`, `> [!warning]`, `> [!tip]`, `> [!info]`, `> [!practice]` — practice callouts end each meaningful section
- Code blocks with `go` syntax highlighting — examples are complete/runnable when relevant (func main included)
- Cross-reference other notes as wikilinks with link text: `[[06 - Middleware & Context]] §3`
- Cheatsheet is the SECOND-TO-LAST section (`## N. Quick Reference Cheatsheet`)
- Last line: navigation `_Previous: [[x]] · Next: [[y]]_`
- Follow-ups/gotchas are mirrored in About.md (descriptor + tree entry), and marked `✅ DONE` / `← NEXT` in the tree above

---

### How the Assistant Works in This Project

When a new session starts, the user pastes a session summary. The assistant should:

1. Read this file (`Auth/§§ - About Auth.md`) — it is the source of truth for conventions, curriculum, and state. No questions about note style or topic order; follow conventions directly.
2. **Answer questions in chat FIRST.** Explanations happen in the chat conversation, teaching style:
   - Examples before theory, minimal jargon, short blocks matching the vault notes
   - Mental models/analogies (bouncer at door vs badge check inside, coat-check ticket vs self-carried ID, etc.)
   - When the user says "I don't understand" — re-explain from zero with a concrete tiny example, then ask WHERE it breaks (which step)
3. **Write to the vault ONLY when asked** (“create the topic”, “update the note”).
4. When creating a topic note: follow the descriptor in “What Each Note Should Cover” below, the style above, and the existing `Golang/NN - Topic.md` notes as templates (same callouts, depth, structure). After creating: update the tree marker (`✅ DONE`/`← NEXT`) and note any new facts in “Current State” below.
5. Code demos live as `.go` files next to the notes (`auth_lab/` demo folder). Run `go run -race` to verify before presenting. Small one-off snippets go in chat only, unless the user asks for a demo file.
6. Verify cross-links after creating a note (Previous/Next navigation both directions).
7. **Session exports live in `~/Documents/Learning/session-exports/`** — one level ABOVE `Golang/` + `Auth/`, shared across learning projects. Write new exports there — never loose in `Golang/` or `Auth/` or anywhere else. Naming: `session-YYYY-MM-DD.md`, where the date is the day the session **ended** (its last Updated timestamp).

### Current State

- Topics **00 Overview planned**, **01 Passwords & Hashing ✅ DONE (2026-08-28)** — hybrid Phase 1 started. Next: **02 - Sessions & Cookies.md** (Set-Cookie + sessions table bench).
- Vault location: `~/Documents/Learning/Golang/Auth/` — companion to `~/Documents/Learning/Golang/` (01-19 DONE). Auth vault is `00-20` (21 notes inc Overview).
- Pending lab: `~/Documents/Developer/quicknotes` separate project (DB + detailed auth + CRUD, `notes` + `url/tags` + `status draft/active/archived`) will be the proving bench for every Auth note (mirrors `expense-tracker` shape `internal/store` + `internal/web` + `web/templates` + `web/static`). Lab is **separate project**, not lab copy.
- Naming: `NN - Topic.md` zero-padded, `§§ - About Auth.md` is the index — same as `§§ - About Golang.md`.
- **2026-08-28 Restructure — Hybrid Path chosen:** user wants maximum *useful + practical + theoretical* profit. Pure theory-first (21 notes before code) loses retention. Pure build-first loses security depth. **Hybrid interleaving adopted** — see `## Hybrid Learning Path` below. File numbers stay stable (`01` is still `Passwords`), but **execution order** is now phased (Core → Build → Harden → Advanced). This file is the restructured index.
- Pending follow-ups, confirmed with user:
  - Vault location Option A inside `Golang/Auth/` ✅ chosen
  - Depth: very deep, vault examples, 22 notes fully — only `§§ - About Auth.md` for now, user will go one-by-one later (now via hybrid path)
  - Project decision: `QuickNotes+` separate project ✅ chosen — `tags TEXT` single column recommended vs normalized JOIN trade-off still open (user to confirm)
  - Hybrid profit discussion 2026-08-28: core → build → deepen yields higher realized profit than all-theory-first for 2-3 week goal
  - 2026-08-28: `01 - Passwords & Hashing.md` created — 14 sections, bcrypt deep dive, cost/pepper/validation, project tie-in to quicknotes + expense-tracker retrofit

---

### Curriculum Structure

The full Auth learning path I am following (files stay `NN` stable; **execution follows Hybrid Path below**):

```
Auth/  — file numbers (stable for Obsidian links)
├── 00 - Overview.md                 ← NEXT (after this file)
├── 01 - Passwords & Hashing.md
├── 02 - Sessions & Cookies.md
├── 03 - JWT.md
├── 04 - OAuth 2.0.md
├── 05 - OpenID Connect.md
├── 06 - Middleware & Context.md
├── 07 - CSRF.md
├── 08 - XSS & Injection.md
├── 09 - RBAC & ABAC.md
├── 10 - Email Verification & Password Reset.md
├── 11 - Rate Limiting & Brute Force.md
├── 12 - HTTPS & Transport.md
├── 13 - Storage & DB.md
├── 14 - Validation & Errors.md
├── 15 - Testing Auth.md
├── 16 - Frontend Auth.md
├── 17 - Mobile & API Auth.md
├── 18 - OAuth Providers.md
├── 19 - Security Headers & Hardening.md
└── 20 - Patterns & Idioms.md

Hybrid execution order (most useful + practical + theoretical profit):
Phase 1 — Core Lab (days 1-6) → Phase 2 — Hardening (days 7-12) → Phase 3 — Advanced Theory (days 13+)
See ## Hybrid Learning Path for the phased sequence.
```

---

### What Each Note Should Cover

When I say “let’s explore topic X”, create a **full, detailed Obsidian note** covering everything listed below for that topic.

**00 - Overview.md** What Auth is, AuthN (who you are) vs AuthZ (what you can do) vs Session (memory) vs Identity (claims), stateless HTTP `19 - net:http.md:40`, cookies as memory, tokens, where Auth lives (web/API/mobile), threat model (OWASP Top 10: injection, broken auth, XSS, CSRF, etc.), the lab shape (`go-auth-crud-lab` mirroring `expense-tracker`)

**01 - Passwords & Hashing.md** bcrypt (`golang.org/x/crypto/bcrypt` `GenerateFromPassword` with cost 10-14, `CompareHashAndPassword`), how bcrypt stores salt+cost in hash string, constant-time compare, Argon2id vs bcrypt vs scrypt (memory-hard), pepper (HMAC with pepper from env), timing attacks, password validation (length 8+, `strings.TrimSpace`, common-password blocklist 10k), never log plain, cost tuning `go test -bench`

**02 - Sessions & Cookies.md** `http.Cookie` struct (Name, Value, Path, Domain, HttpOnly, Secure, SameSite `Lax/Strict/None`, MaxAge, Expires) `19 - net:http.md:469`, `http.SetCookie` vs `r.Cookie`, session table `token TEXT PRIMARY KEY, user_id FK, expires_at TEXT`, `crypto/rand` 32B hex generation, `INSERT` + `SELECT WHERE token=? AND expires_at>now()`, expiry cleanup `DELETE WHERE expires_at<now()`, cookie vs localStorage/sessionStorage, `Secure` in prod, `SameSite` CSRF value, `MaxAge:-1` delete `19 - net:http.md:492`

**03 - JWT.md** Structure `header.payload.signature` + `base64.RawURLEncoding` + `json.Marshal`, `encoding/json` `20 - encoding/json` + `encoding/base64`, claims (`sub`, `exp`, `iat`, `iss`, `aud`), HS256 (shared secret) vs RS256 (public/private), `exp` validation, `jwt-go`/`golang-jwt` library, JWT vs sessions tradeoffs (revocation, size, stateless), refresh tokens (short `access` + long `refresh`), `Authorization: Bearer` `19 - net:http.md:525`

**04 - OAuth 2.0.md** Roles (resource owner, client, auth server, resource server), grant types (authorization code + PKCE `S256` `code_challenge`, implicit deprecated, client credentials, refresh token), scopes, full authorization code flow diagram (redirect → code → token exchange → access), `state` param CSRF `07 - CSRF`, `redirect_uri` validation, `authorization_code` vs `implicit` why deprecated

**05 - OpenID Connect.md** OIDC layer atop OAuth 2.0, ID token (JWT with `sub`, `email`, `email_verified`) vs access token, `scope=openid email profile`, `nonce`, `/userinfo` endpoint, discovery `/.well-known/openid-configuration`, OIDC vs OAuth (auth vs delegation), claims mapping

**06 - Middleware & Context.md** `type Handler interface {ServeHTTP}` `19 - net:http.md:103`, `type HandlerFunc func` adapter `19 - net:http.md:117`, `RequireAuth` factory `func RequireAuth(next http.Handler) http.Handler` `19 - net:http.md:333` onion `next.ServeHTTP`, `r.Cookie("session")` `19 - net:http.md:479`, `context.WithValue` `19 - net:http.md:650` with `type ctxKey string` never string key, `r.WithContext` returns NEW request `19 - net:http.md:651`, `RequireRole` variant `09 - RBAC`, chaining `RequireAuth(RequireRole("admin", handler))`

**07 - CSRF.md** What CSRF is (attacker site POSTs as you), `SameSite=Lax` `19 - net:http.md:492` vs `Strict` vs `None+Secure`, synchronizer token (`uuid`/`crypto/rand` per session, hidden `<input name="csrf">`, validate on every POST), double-submit cookie, `state` for OAuth, why POST for mutations `01 - Milestones.md:13`, `Origin`/`Referer` checks, `SameSite` alone vs token defense-in-depth

**08 - XSS & Injection.md** XSS types (stored, reflected, DOM), `html/template` auto-escape `19 - net:http.md:229` vs `template.HTML` danger, `database/sql` `?` placeholders `store.go:33` vs concat injection, `strings.TrimSpace` `18 - Standard Library.md:218` validation, `net/url` `ParseRequestURI`, `Content-Security-Policy` `19 - Security Headers`

**09 - RBAC & ABAC.md** RBAC tables `roles(id, name UNIQUE)` + `user_roles(user_id, role_id)` JOIN, `CHECK` enum, `RequireRole("admin")` middleware, ABAC attributes (owner `user_id`, `status`, `created_at`), row-level `WHERE user_id=?` isolation (`quicknotes` + `expenses` `store.go:48`), policy decision point, `SELECT ... WHERE id=? AND user_id=?` as AuthZ

**10 - Email Verification & Password Reset.md** `verification_tokens(token PK, user_id, type CHECK verify/reset, expires_at TEXT, used BOOLEAN)` table, `crypto/rand` 32B hex, `http://host/verify?token=`, `Expires` 15min-24h, one-time use `used=true`, `net/smtp` or `Resend` API `http.Client{Timeout}` `19 - net:http.md:545`, timing attacks on token compare

**11 - Rate Limiting & Brute Force.md** `sync.Mutex` `15 - Sync Primitives.md:90` `map[ip]int` + `map[email]int` counters, `429 Too Many Requests` `19 - net:http.md:274`, `time.After` `14 - Select.md:131`/`time.Since` window, `golang.org/x/time/rate` `Limiter`, exponential backoff, account lockout `locked_until`, `Retry-After` header, per-IP vs per-account

**12 - HTTPS & Transport.md** `ListenAndServeTLS(":443", cert, key, mux)` `19 - net:http.md:96`, `Secure` cookie flag in prod, HSTS `Strict-Transport-Security`, `ReadTimeout`/`WriteTimeout`/`IdleTimeout` `19 - net:http.md:592`, cert via `Let's Encrypt`/`openssl req -x509`, HTTP → HTTPS redirect `301` `19 - net:http.md:581`, `TLSClientConfig` `19 - net:http.md:545`

**13 - Storage & DB.md** `CREATE TABLE users` `email UNIQUE` `06 - Maps.md:48` index, `FOREIGN KEY ... ON DELETE CASCADE`, migrations `goose` or plain `Exec` version table, `sql.ErrNoRows` `11 - Error Handling.md:259` + `errors.Is` `11 - Error Handling.md:289`, `sql.NullString`, transactions `sql.Tx` `Begin/Commit/Rollback`, `INDEX` `idx_notes_user_status`, `goose` vs `modernc.org/sqlite` `store.go:14`

**14 - Validation & Errors.md** `strings.TrimSpace` `18 - Standard Library.md:218`, `net/url.ParseRequestURI`, `regexp` `07 - Strings & Runes.md:430` email `^[^@]+@[^@]+\.[^@]+$`, `11 - Error Handling.md:34` `error` interface + `%w` wrapping `11 - Error Handling.md:558`, sentinel `ErrInvalidEmail`, `errors.As` `11 - Error Handling.md:458` for field errors, `400 Bad Request` vs `401 Unauthorized` vs `403 Forbidden` `19 - net:http.md:274`, flash cookie one-time `19 - net:http.md:465`

**15 - Testing Auth.md** `httptest.NewRequest/NewRecorder/NewServer` `19 - net:http.md:669`, `httptest` cookie jar `rec.Result().Cookies()`, table-driven tests `22 - Testing.md`, `t.Helper`, `go test -race -cover` `15 - Sync Primitives.md:90`, setup `store.Open(":memory:")`, `TestRequireAuth_Unauthorized` etc., `httptest.NewRequest` with `AddCookie`

**16 - Frontend Auth.md** `GET /login` form `method="post" action="/login"` `enctype` `03 - Lessons Learned.md:17`, `POST FormValue` `19 - net:http.md:155`, `{{if .Flash}}` `list.html:11`, `type="email"`/`type="password"`/`autocomplete`, `autofocus`, preserving `email` value on error `value="{{.Email}}"`, password `type="password"` never prefill

**17 - Mobile & API Auth.md** `Authorization: Bearer <token>` `19 - net:http.md:525` `http.NewRequest` `Header.Set`, `GET /api/notes` JSON `20 - encoding/json` `json.NewEncoder(w).Encode`, cookie vs token for app (`Secure` + `HttpOnly` vs `localStorage`), refresh flow `POST /api/refresh`, `http.Client{Timeout:5s}` `19 - net:http.md:545`, `Bearer` parsing `strings.TrimPrefix`

**18 - OAuth Providers.md** Google/GitHub provider flow, `state` (`uuid`/`crypto/rand`) + PKCE `S256` `code_challenge = base64url(sha256(verifier))`, `http.Client{Timeout}` exchange `POST /token` + `GET /userinfo`, `GEMINI_API_KEY` `.env` pattern `gemini.go:14` for client secret, `redirect_uri` exact match, `email_verified` check

**19 - Security Headers & Hardening.md** `Content-Security-Policy default-src 'self'`, `X-Frame-Options DENY`, `X-Content-Type-Options nosniff`, `Referrer-Policy strict-origin`, `Permissions-Policy`, `Secure`+`HttpOnly` audit checklist, `log/slog` `18 - Standard Library.md:460` structured `slog.Info("login", "user", email)`, dependency audit `go list -m all`, `govulncheck`

**20 - Patterns & Idioms.md** Factory `Auth(st)` `04 - Functions.md:617` vs functional options `17 - Packages & Modules.md`, `sync.Once` for pepper/config load `15 - Sync Primitives.md:163`, `type ctxKey string` `19 - net:http.md:649` never string key, worker pool for email send `12 - Goroutines.md:869`, `embed` for `web/static` `21 - File I/O.md`, `go:generate` for mocks

---

### Anki Card Style

When making Anki questions:

- **No yes/no questions** — all questions must be contemplative and complex
- **Include coding questions** — predict output, spot the bug, write the fix
- **Cover everything** — aim for minimum 25-30 cards per topic, do not miss sections
- **Format:**
    
    ```
    Q: [question]A: [answer with code if needed]
    ```
    

---

### Teaching Style Preferences

- Explain things **from scratch with examples** when I say I don't understand
- When I ask "explain this" with a screenshot or code snippet — break it down step by step, simply
- When I ask for **more examples** — give different scenarios, not variations of the same one
- Keep explanations **focused** — no unnecessary padding
- When I paste a document and ask to **update it** — only change what was asked, leave everything else untouched
- When I say **"make questions for Anki"** with a pasted document — cover every section, minimum 25 cards
- When I say **"lets explore [topic]"** — create the full Obsidian note outputting it as a downloadable `.md` file

---

### Conversation Patterns Established

- I paste my Obsidian note → ask for Anki cards → you cover every section
- I paste a screenshot of code from my notes → ask "explain this" → you break it down simply
- I ask "what is X" mid-topic → you explain it clearly with examples, then offer to connect it back to the current topic
- I say "update the document" → you only change what was requested
- I say "add more detail to section X" → you update just that section, leave others untouched
- When I don't understand something → I tell you directly, you start fresh with a simpler explanation
- Notes that are already done do NOT need to be recreated — just reference them
- New Auth notes live in `Golang/Auth/` — same `Previous/Next` navigation as Golang vault

---

### Topics Already Deeply Discussed (Beyond the Notes)

These came up during conversation and were explained in detail — no need to re-explain unless asked:

- Why `defer` captures arguments immediately vs closures seeing current values
- Named return values + defer interaction (the "magic" step order)
- Why `f.Close()` can fail and why the named return pattern catches it
- The full `panic` unwind process with the a→b→c stack example
- `log.Fatal` vs `panic` (output, defers, exit codes, when to use each)
- What handlers, parsers, and middleware are (non-Go general concepts)
- How middleware chains work — `next(w, r)` handoff explained in detail
- Why `recover()` only works inside `defer`
- Closures — what they are, why captured variables survive, shared state
- Why `any` and `interface{}` both exist (backwards compatibility)
- Type assertions — only work on interfaces, why concrete types can't be asserted
- Interfaces — what they are, implicit satisfaction, will be covered in depth in note 10
- `init()` — FIFO not LIFO, blank imports, why to avoid writing your own
- Recursion — base case + recursive case, when to use vs loops, stack growth
- Functional options — what they are, the coffee example, when you need them
- The set pattern — `map[T]struct{}` vs `map[T]bool`, the four operations, use cases
- Struct keys vs pointer keys in maps — value equality vs address identity
- Why map iteration order is actively randomized (not just unspecified)
- Typed nil vs untyped nil — interface `(type,value)` pair, `error` trap `var e *MyError = nil; return e` → `(type:*MyError,value:nil) != nil`
- Cookies — stateless HTTP, `Set-Cookie` vs `Cookie` header, `HttpOnly/Secure/SameSite/MaxAge` vs query-param `?err=` flash one-time via `MaxAge:-1`
- What Auth is — AuthN (who) vs AuthZ (what), sessions vs JWT, RBAC `WHERE user_id=?`

---

## Context for OpenCode

You are teaching me Go (Golang) + Auth. Follow these rules precisely:

### Style
- **No water.** Be concise, precise, concrete. Cut fluff, verbose explanations, analogies, and content that belongs in other topics.
- **Examples first.** Lead with runnable code, then explain.
- **Obsidian format.** Use `[[#Section]]` wikilinks, `> [!note]`/`> [!warning]`/`> [!tip]` callouts, `go` syntax highlighting, frontmatter tags, and navigation links at the bottom.

### How to handle requests
- **"Let's explore [topic]"** — Create a full Obsidian note for that topic covering every listed point. Output as downloadable `.md`.
- **"Explain this"** (code/screenshot) — Break it down step by step from scratch.
- **"Make questions for Anki"** — Cover every section. No yes/no. Include code questions. Minimum 25-30.
- **"Remove water from [topic]"** — Strip fluff, cut verbose explanations, remove off-topic content, keep concrete examples.
- **"Update the document"** — Only change what was asked. Leave everything else untouched.
- User says they don't understand — Explain more simply with fresh examples.

### Curriculum state
Topics `Golang 01-19 ✅ DONE`, `Golang 20 - encoding/json ← NEXT`. Auth `00-20` planned, `§§ - About Auth.md` ✅ DONE as index; `Auth 00 Overview ← NEXT`. Vault is `Golang/Auth/`. Lab benches: `auth_lab/` demo folder per Auth note; project benches: `go-auth-crud-lab` / `quicknotes` for hands-on Auth+DB+CRUD (2-3 week separate project), `expense-tracker` `feature/gemini 9113d57` frozen for later retrofit.

---

## Prompts (Auth)

I’d like to learn about Passwords & Hashing in Go comprehensively with detailed examples. Include all the data, so that I have no questions left. Just Everything. Make it copyable for Obsidian. Include all the nuances, problems, limitations and advantages. Make very clear and engaging. Use a lot of examples with detailed explanation

---

Make questions for anki until the end of 06 - Middleware section. Avoid Yes\No questions. Make them contemplative and complex. Include coding. Make a lot of questions, do not limit yourself to a few questions for the section, make a lot of them, so that YOU COVER EVERYTHING, do not miss anything. I expect a MINIMUM of 50 questions

---
