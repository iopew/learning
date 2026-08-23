# Milestones — Plan & Status

| # | Milestone | Status |
|---|---|---|
| 1 | DB days: go.mod ✓, schema, `store.Add/List/Summary`, throwaway proof main | ✅ DONE + committed |
| 2 | Server skeleton: list page renders, add form round-trips | ✅ DONE + committed |
| 3 | Date-range filters (`from`/`to` query params), summary block inline, delete button per row | ✅ DONE + committed (Aug 18) |
| 4 | Cheque PDF upload → parse items → auto-add each (`source="cheque"`) | ✅ DONE (Aug 23, commit pending) |
| 5 | Polish: CSS via `http.FileServer` (`web/static/`), flash errors, formatting, README, visible errors for rejected cheques | ⬜ |
| 6 | Auth: users table, bcrypt, session cookie, middleware, CSRF | ⬜ |
| 7 | Scanned cheques: image upload → tesseract OCR → hardened parser (`source="cheque"`) | ⬜ **NEXT** |

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

## Milestone 2 checklist (server skeleton)

- [x] `web/templates/list.html` — table + add form (my first HTML)
- [x] `internal/web/handlers.go` — ListPage + AddExpense factories (closure handing `st` to handlers)
- [x] `cmd/expense/main.go` wiring — `store.Open` + guard, both routes, `log.Fatal(ListenAndServe)`
- [x] round-trip proven in browser: added bread + eggs, rows land in `expense.db`
- [x] 303 redirect + F5-protection verified (refresh re-GETs, no duplicates)
- [x] deferred to milestone 5: CSS + static files (`FileServer` + `web/static/`)
- [x] commit milestone 2 (includes the staged `prove.db`/`.DS_Store` untracking)

## Milestone 3 checklist (filters, summary, delete)

- [x] date-range filters via query params — `GET /expenses?from=...&to=...`, defaults `0001-01-01`/`9999-12-31` keep the bare page working
- [x] summary rendered inline on the list page (`st.Summary` next to `st.List`) — no separate `/summary` route, the planned two pages became one
- [x] `store.Delete(id)` — third DML verb: `DELETE FROM expenses WHERE id = ?`
- [x] per-row delete forms with hidden `<input name="id">`, read back with `r.FormValue`
- [x] route `POST /expenses/delete` + third 303 redirect
- [x] committed (Aug 18)

## Milestone 4 checklist (cheque PDF → parse → auto-add)

- [x] QR approach scrapped after seeing a real Korzinka cheque: it arrives as a **PDF**, not an image
- [x] redesign: upload PDF → extract text → walk lines with regexes → one expense per item (`source="cheque"`), all stamped with the cheque's date
- [x] dependency `github.com/ledongthuc/pdf` (`GetPlainText` per page)
- [x] sample at `testdata/cheque-sample.pdf`
- [x] proving bench `cmd/pdfprove/main.go`: numbered text dump → date bite → full parser proven (`date + 4 items + total: 195238 sum == total: OK`)
- [x] labeled `break loop` — a plain break inside the switch only exits the switch; the promo section below the total kept overwriting it and injecting 2027 dates
- [x] parser moved into `internal/web/cheque.go`: prints became returns; guards added (empty items, `sum != total`); first-date-only; patterns compiled once at package level
- [x] `ChequeExpense` handler in handlers.go (`r.FormFile` → `Seek` size trick → `pdf.NewReader` → `parseCheque` → `st.Add` × N)
- [x] route `POST /expenses/cheque` in cmd/expense/main.go
- [x] upload form in list.html (`enctype="multipart/form-data"` on the `<form>` tag, file input `name="cheque"`, own submit button)
- [x] browser round trip with the real PDF → 4 rows stamped with the cheque's date, source `"cheque"`
- [x] polish: `cleanDesc` — leading `¡`/emoji junk trimmed via `TrimLeftFunc(!unicode.IsLetter)` (the bite-1 deferral finally paid)
- [ ] commit milestone 4

## Milestone 7 checklist (scanned cheques via OCR)

Bench findings from 2026-08-23 (`sips` renders sample PDF → PNG with ground truth, `tesseract -l eng` reads it back):

- [x] bench proven: tesseract reads the rendered cheque; amounts survive perfectly, structure mostly survives
- [x] damage report (noise differs run-to-run — resolution tuning is NOT reliability): date destroyed every run (`W387 LAMP 026`), item opener `1.` ↔ `1,`, `= ` separator once became `- `, `TO'LOV` case wobbles, total gets glued onto the marker line
- [ ] bite 1 — date guard: walk ends with `date == ""` → return error (no dateless rows ever stored)
- [ ] bite 2 — tolerant opener: `^\d+[.,] ` (comma happens)
- [ ] bite 3 — tolerant separator: `[-=] ([\d ]+,\d{2})`
- [ ] bite 4 — case-proof flag: compare lowercased `"to'lov uchun"`
- [ ] bite 5 — total on the marker line: when flag flips, hunt trailing money on the same line; else keep waiting for a bare line
- [ ] handler sniffs upload magic bytes: `%PDF` → ledongthuc path, PNG/JPEG → new OCR path (temp file → exec tesseract → read text) → both feed `parseCheque`
- [ ] form accepts images too
- [ ] round trip with a scan → commit milestone 7

Engine note: tesseract stays behind one small bytes→text seam so a future swap (cloud API / on-device ML if this becomes a mobile app) changes nothing downstream.