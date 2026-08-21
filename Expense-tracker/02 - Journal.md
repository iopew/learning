# Journal — Day by Day

**Rules:** one entry per work session. What I built · bugs I hit · what I learned. The "what I know now vs day 1" artifact.

---

## 2026-08-11 — Milestone 1 start

- scaffolded repo (git init), notes folder alongside Golang vault
- planned: Expense model + store package + throwaway main

## 2026-08-12 — Store half alive

- learned: driver = translator between database/sql and SQLite; SQL = text contract sent via Exec/Query; IF NOT EXISTS; ? holes; LastInsertId; unexported fields = private walls; early-return pattern; ISO dates sort chronologically, dd.mm.2026 does NOT
- built: model.Expense, store.Open (handle + CREATE TABLE), store.Add (INSERT with holes, returns id)
- prove program inserts 3 groceries; SELECT proves rows live in prove.db
- still to write: List, Summary → then first commit

## 2026-08-12 — Store complete + first commit

- List: Query returns a cursor (bookmark), 5-move dance learned (Query → guard → defer Close → Next/Scan/append → rows.Err)
- WHERE BETWEEN = the librarian: filtering happens inside the database, never in Go
- typo saga: `descriptionm`, then `descriptio` — same column, three strikes; guards caught it, but the real lesson: ALWAYS print `err` ("failed to get the list: no such column: ...")
- Summary: QueryRow one-shot; sql.NullInt64 boxes (SUM/MAX are NULL on empty months, COUNT never) — the Valid-lid check
- full loop proven: Add 3 → List chronological → Summary {3, 180000, 150000}
- milestone 1 committed (own .gitignore for prove.db)

## 2026-08-12 — Milestone 2 started

- concepts: mux = reception desk (dispatcher, longest-prefix, method patterns "GET /hello"); middleware = on-the-way checks (auth/logging) — milestone 6; handler = func(w, r); factory pattern = closures handing the store to handlers
- bug party: `http.HandleFunc` registers on the DEFAULT mux, not your `mux` → served mux was empty → 404 everywhere. Fix: `mux.HandleFunc("GET /hello", Greet)`
- `/` 404ing is CORRECT: only registered routes exist
- hello server works: curl localhost:8080/hello → "hello from the tracker"
- next: web/templates/list.html + internal/web/handlers.go (ListPage/AddExpense factories) + wire cmd/expense/main.go (expense.db)
- git: prove.db + .DS_Store untracked, staged for removal — commit pending

## 2026-08-16 — Milestone 2 complete

- full round-trip: form → POST /expenses/add → AddExpense → st.Add → 303 redirect → GET /expenses → ListPage → template render → table in browser
- factory pattern made real: ListPage/AddExpense are closures that capture `st`
- bug party: phantom `"structs"` import (autocomplete hallucination — `struct` is a keyword, not a package); route `GET /expense/add` vs form's `POST /expenses/add` (method + spelling mismatch — compiler can't see strings)
- redirect: 303 + Location = "the page you see is always served by a GET" — F5-protection proven live
- `log.Fatal(http.ListenAndServe(...))`: arguments evaluate BEFORE the call → Fatal runs only when the server dies; requests are served inside the argument slot
- AddExpense five-fix round: bit-size 64 (was 4), early returns, `_, err =`, err in prints, the redirect itself
- static files: `file://` browser reads disk itself; `http://` it can only request — handlers are the delivery truck (CSS deferred to milestone 5)
- proven in expense.db: 2 rows (bread 10000, eggs 38000), both `manual`

## 2026-08-18 — Milestone 3 complete

- filters live in the URL: `GET /expenses?from=...&to=...` — filtering stays in SQL (`WHERE BETWEEN`), Go just passes strings through
- summary folded into the list page instead of a separate `/summary` route — one page, one round trip
- delete: third DML verb (`DELETE FROM expenses WHERE id = ?`), id travels as hidden input, `r.FormValue` reads it like any form field
- same factory shape, third 303 redirect — the rhythm holds
- committed

## 2026-08-19 — The pivot: QR dies, cheque PDF born

- shared a real Korzinka cheque expecting a QR image — it's a **PDF**. QR machinery scrapped mid-milestone
- redesign: upload PDF → extract text → walk lines with regexes → each item becomes its own expense row (`source="cheque"`), all stamped with the cheque's date
- `ledongthuc/pdf`: `pdf.Open(path)` → `NumPage()` / `Page(i)` / `GetPlainText(nil)`; numbered dump of testdata as the map of the terrain
- date bite proven: `\d{2}/\d{2}/\d{4}` finds it, `time.Parse("02/01/2006", m)` reads it day-first (the reference layout!), `.Format("2006-01-02")` emits ISO

## 2026-08-21 — Parser complete + regexp bootcamp

- regexp decoded piece by piece against real cheque lines: `\d`, `{n}`, `+`, `[class]`, `^ $`, `( )`; conclusion — many small patterns + a line-walk beat one giant pattern
- `FindStringSubmatch` returns two recordings: `[0]` = whole match, `[1]` = what the parentheses boxed. Parens are boundary markers drawn by the pattern author — nothing is "omitted"
- switch mechanics nailed: top-to-bottom, first true wins, one case per line — the loop re-asks all questions for every iteration
- bug party: case 4 lost its `else` → total counted twice as a ghost fifth item · final check lived *inside* the loop → verdict spam on every line · promo section below the total kept overwriting `total` (20918! 871!) and injecting 2027 dates → labeled `break loop` fixed both
- silent failure of the day: regexes typed with `, ` matched nothing at all, yet `sum == total == 0` passed the golden check → added `len(items) == 0` guard
- inverted guard: `m != "" && date != ""` never sets date (first pass has date empty!) → `==`
- `log.Fatal` banished from library code — fine in a CLI proving bench, kills a web server; regex already guarantees digits-only so `parseAmount` ignores `ParseInt`'s error honestly
- `parseAmount` pipeline: `ReplaceAll(" ", "")` → `Split(",")[0]` → `ParseInt`; tiyin always `,00` on these cheques, whole soms by design
- print became return: `internal/web/cheque.go` exports `parseCheque(text) (date, []ChequeItem, error)`; patterns compiled once at package level; pdfprove stays as the bench
- next session: `ChequeExpense` handler (`r.FormFile`, `io.Seek` size trick, `pdf.NewReader`) + route + multipart form