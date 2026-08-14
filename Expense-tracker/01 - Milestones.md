# Milestones — Plan & Status

| # | Milestone | Status |
|---|---|---|
| 1 | DB days: go.mod ✓, schema, `store.Add/List/Summary`, throwaway proof main | ✅ DONE + committed |
| 2 | Server skeleton: list page renders, add form round-trips | **IN PROGRESS** (hello server ✓, template/handlers/wiring next) |
| 3 | Filters (range on both pages) + summary page | ⬜ |
| 4 | QR upload → prefill | ⬜ |
| 5 | Polish: flash errors, formatting, README, sample QR in testdata | ⬜ |
| 6 | Auth: users table, bcrypt, session cookie, middleware, CSRF | ⬜ |

Each milestone = one git commit (at least). Rules: SQL lives only in `internal/store/`; every mutation ends in a redirect; auth is milestone 6.

## Milestone 1 checklist (DB days)

- [x] `git init` own repo in `~/Documents/Developer/expense-tracker/`
- [x] Notes folder created alongside Golang vault
- [x] `go get modernc.org/sqlite`
- [x] `internal/model/model.go` — Expense struct + Summary struct (Total/Count/Max)
- [x] `internal/store/store.go` — Open, Add, List, Summary (the only SQL) ✓ all four proven
- [x] throwaway `cmd/prove/main.go` — inserts 3 groceries, lists chronologically, prints summary
- [x] first `git commit` of milestone 1
- [ ] (cleanup) prove main may be kept until milestone 2 replaces it
- [ ] `go run` proves it → commit