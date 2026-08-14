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