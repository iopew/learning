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