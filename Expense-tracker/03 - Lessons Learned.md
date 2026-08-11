# Lessons Learned

One line per lesson, grown during the project. The bug-party record.

- ⬜ float64 money drifts; integer so'm is exact (see Overview decision #3)
- ⬜ mutations must end in a redirect, or F5 double-submits
- ⬜ SQL lives only in internal/store/
- ⬜ QR never auto-saves — prefill only