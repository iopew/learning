# Expense Tracker — Project Overview

> **Goal:** a working web app for tracking grocery expenses. Learn backend fundamentals by building (structurisation, web, DB, security) — the "programmer mindset" project.

## Scope (locked by discussion)

- Web app, server-rendered, stdlib `net/http` + `html/template`, Go 1.22+ routing, no JS, no framework
- Groceries only. No categories (decision: categorisation redundant — it's all food)
- Money = whole integer so'm (`int64`). No tiyin, no floats ever
- Cheque PDF: upload → extract text → parse items → **auto-add each item** (`source="cheque"`), validated by an items-sum vs printed-total check before anything lands
- Storage: SQLite (`modernc.org/sqlite`, pure Go, no cgo) behind a `Store` interface
- Time ranges: Today / This week / This month / Last month / All
- One page: `/expenses` (list + add + cheque upload + summary block inline)

## Explicitly NOT in v1

- auth (milestone 7, after app works), users, multi-currency, categories CRUD, editing, budgets, charts, JS

## Decision log

| # | Decision | Why |
|---|---|---|
| 1 | Web, not CLI | Chose deliberately: learn net/http + templates |
| 2 | SQLite behind `Store` interface | JSON file = escape hatch if DB explodes mid-project |
| 3 | Integer so'm, no subunit | Real-life sums are whole; kills float-dust bugs forever |
| 4 | ~~QR from image file, not camera~~ superseded by #9 — Korzinka cheques arrive as PDFs, not images | was: real decoding without macOS camera plumbing |
| 5 | No categories | All groceries — summary gives total/count/avg/max instead |
| 6 | Auth last | Don't let security block the dependency chain |
| 7 | modernc.org/sqlite | Pure Go — no cgo/compiler toolchain on Mac |
| 8 | One expense = one row (no line items) | Split mixed receipts manually in v1 |
| 9 | Cheque PDF parsed server-side; items **auto-added** (`source="cheque"`) | Reverses the old prefill-never-auto-save rule: the parser's `sum == total` golden check rejects bad cheques *before* anything is stored, making auto-save safe. Also automates #8's manual splitting |

## Folder maps

- App: `~/Documents/Developer/expense-tracker/`
- Notes: `~/Documents/Learning/expense-tracker/` (this folder, alongside Golang vault)