# Lessons Learned

One line per lesson, grown during the project. The bug-party record.

- ⬜ float64 money drifts; integer so'm is exact (see Overview decision #3)
- ⬜ mutations must end in a redirect, or F5 double-submits
- ⬜ SQL lives only in internal/store/
- ⬜ ~~QR never auto-saves — prefill only~~ superseded 2026-08-19: cheque parsing validates via the sum-vs-total golden check, *then* auto-adds (Overview #9)
- ⬜ many small regexes + a line-walk beat one giant pattern; `MatchString` guards `FindStringSubmatch` (`nil[1]` panics)
- ⬜ `^`/`$` anchors make patterns strict: "bare money line" and "money inside a line" are different questions
- ⬜ `break` inside a switch exits the SWITCH, not the loop — label the loop (`loop:` / `break loop`) when you mean the loop
- ⬜ golden checks must reject emptiness: `0 == 0` "validates" a parse that caught nothing
- ⬜ `log.Fatal` belongs in main() only — in library/handler code it kills the whole server
- ⬜ `time.Parse` layouts are the reference time (Mon Jan 2 … 2006): `"02/01/2006"` reads day-first
- ⬜ TrimSpace shaves string edges; ReplaceAll hits every occurrence — different jobs, pick deliberately
- ⬜ interfaces promise capabilities, not facts: `io.Reader` gives bytes but has no `Len()` — measure a stream via `Seek(0, SeekEnd)` (return value = size), then rewind home
- ⬜ file uploads travel as `multipart/form-data` — the enctype belongs on the `<form>` tag, and `r.FormFile` only unpacks what that header announces
- ⬜ forms are sealed envelopes: each button submits its OWN form; a form without a submit button makes users click the wrong one and ship garbage to another route
- ⬜ type mismatches die at compile time — a runtime `ParseInt` error means the wrong handler got hit, not a conversion bug. Grep the error string to find who printed it
- ⬜ `TrimLeftFunc(s, func(r) bool { return !unicode.IsLetter(r) })` strips any leading junk (spaces, `¡`, emoji, BOM) without maintaining a character blacklist
- ⬜ OCR noise is random per run — the same document makes different mistakes at different settings; validate at the boundary and reject loudly, never tune extraction into false trust
- ⬜ golden check + defensive parser = the OCR contract: garbage can only bounce, never store