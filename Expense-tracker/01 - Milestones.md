# Milestones — Plan & Status

| # | Milestone | Status |
|---|---|---|
| 1 | DB days: go.mod ✓, schema, `store.Add/List/Summary`, throwaway proof main | **IN PROGRESS** |
| 2 | Server skeleton: list page renders, add form round-trips | ⬜ |
| 3 | Filters (range on both pages) + summary page | ⬜ |
| 4 | QR upload → prefill | ⬜ |
| 5 | Polish: flash errors, formatting, README, sample QR in testdata | ⬜ |
| 6 | Auth: users table, bcrypt, session cookie, middleware, CSRF | ⬜ |

Each milestone = one git commit (at least). Rules: SQL lives only in `internal/store/`; every mutation ends in a redirect; auth is milestone 6.

## Milestone 1 checklist (DB days)

- [x] `git init` own repo in `~/Documents/Developer/expense-tracker/`
- [x] Notes folder created alongside Golang vault
- [ ] `go get modernc.org/sqlite`
- [ ] `internal/model/model.go` — Expense struct (id, amount int64, description, date, source)
- [ ] `internal/store/store.go` — Open/Add/List/Summary (the only SQL)
- [ ] throwaway `cmd/prove/main.go` — calls Add, List, prints; delete after
- [ ] `go run` proves it → commit