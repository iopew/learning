# Go — Packages & Modules

> **Series:** Go Language Fundamentals **Tags:** #go #golang #packages #modules #imports #go-mod #programming **Level:** Intermediate

---

## Table of Contents

- [[#1. What Is a Package?]]
- [[#2. The `main` Package and `cmd/`]]
- [[#3. Import Paths — How Go Finds Code]]
- [[#4. Visibility — Exported vs Unexported]]
- [[#5. `init()` — Startup Code]]
- [[#6. `go.mod` — The Module's ID Card]]
- [[#7. `go.sum` — The Integrity Ledger]]
- [[#8. go get, go mod tidy, go mod vendor]]
- [[#9. Semantic Versioning]]
- [[#10. `internal/` Packages — The Privacy Wall]]
- [[#11. Blank Imports]]
- [[#12. Dot Imports (anti-pattern)]]
- [[#13. Package Naming]]
- [[#14. Organizing Code — the cmd/internal Layout]]
- [[#15. Build Constraints]]
- [[#16. Workspaces (brief)]]
- [[#17. Quick Reference Cheatsheet]]

---

## 1. What Is a Package?

A **package** is a folder of `.go` files that form one unit of compiled code. Two rules you've already met in the project:

- **One package per folder.** All files in a folder must start with the same `package` line.
- **Every `.go` file starts with `package X`** — that's how Go knows which unit you belong to.

```go
// internal/model/model.go
package model        // this folder = package "model"

// cmd/prove/main.go
package main         // this folder = package "main" — even though the folder is "prove"!
```

> [!note] **Folder name ≠ package name.** The folder is *where it lives*; the `package` keyword is *what it is*. Convention says they match (clean code does this) — but the exception proves the rule: executables under `cmd/` are always `package main`, whatever their folder is called. Your year-two self will thank you for keeping both lowercase and identical wherever possible.

Inside one folder, files share everything: types, functions, and — importantly — their unexported names (the privacy rule in section 4). `Add` in `store.go` is directly callable from `Open` in the same folder even though it's a different file.

---

## 2. The `main` Package and `cmd/`

A package named `main` is special: it's **compiled into an executable program**, and it needs one `func main()`. Everything else is a *library* package — importable, not runnable on its own.

Go's community convention for a project with several executables: put them each in a folder under `cmd/`, named after the binary:

```
expense-tracker/
├── cmd/
│   ├── prove/       ← the throwaway experiment
│   └── expense/     ← the real app: package main
├── internal/
│   ├── model/       ← library packages
│   ├── store/
│   └── web/
```

- `go run ./cmd/expense` — builds only that command and runs it
- `go build ./...` — builds everything (you met the pain when the stray root `main.go` had no `main` function: `function main is undeclared in the main package`)

> [!tip] A library package that is also `main` is a contradiction. Keep `func main()` exactly one per executable, in `cmd/<name>/`.

---

## 3. Import Paths — How Go Finds Code

The `import` statement is Go's "give me that package" — and it's addressed by an **import path**, not a filesystem path. Anatomy, using your own project:

```go
import "expense-tracker/internal/store"
//        └────┬─────┘ └────┬─────┘
//      module path    folders inside the module
```

The import path = **module path (from go.mod) + the folder walk to reach the package.** With `module expense-tracker` and the package in `internal/store/`, the path is `expense-tracker/internal/store`.

Why paths and not "the file at ~/Documents/...": import paths are **globally unique names**. They identify a package the same way a street address identifies a building — on any machine, `golang.org/x/sys` means the same package. Your own packages borrow your module path as their namespace.

**Resolution order** when you import:

1. **Standard library first** — no dot in the first element (`fmt`, `database/sql`, `net/http`)
2. **Your module's packages** — the module path prefix matches yours
3. **Third-party** (`modernc.org/sqlite`) — Go downloads them into the module cache and records them in go.mod

> [!warning] Import a package you never use and compilation fails; use something without importing it and compilation fails too. Imports are enforced — `goimports`/your editor adds them automatically.

---

## 4. Visibility — Exported vs Unexported

Go has no `public`/`private` keywords. It uses **one rule built into the name**: a **capital first letter = exported** (visible outside its package); **lowercase = unexported** (visible only inside its own package — but that includes every file in the same folder).

```go
// internal/store/store.go
type Store struct {
    db *sql.DB      // lowercase: nobody outside package store can touch it
}
func Open(...)      // capital: exported — the world may call it
```

This is *the* privacy wall. Remember the pain and the lesson: in the prove program you tried to reach `store.db` from `package main` and the compiler refused — `db` is unexported, so it's private to `store`. The compiler **enforces** the wall; nothing slips through.

```go
// cmd/prove/main.go
st.db             // ERROR: st.db undefined (cannot refer to unexported field)
st.Add(...)       // OK — Add is exported
```

> [!practice] **Project check.** Find each capital letter in your `internal/model`, `internal/store`, and `cmd/expense` files and say why it's capital (exported = "used by another package") or lowercase (unexported = "private to this folder"). Then make one yourself: export a helper, unexport it back.
>
> Exported also means **API** — it's the contract others compile against. Unexported = free to change any time; exported = breaking changes now break your callers.

---

## 5. `init()` — Startup Code

Every file may declare one `func init()` — it runs **automatically at package load time**, before `main`. Zero arguments, zero returns, called once.

```go
// somepackage/somepackage.go
var config map[string]string

func init() {
    config = loadConfig()   // runs before anyone uses this package
}
```

**Order across packages:** dependencies first. If `web` imports `store`, then `store`'s `init` runs before `web`'s. Within a file, multiple `init`s run in source order.

> [!warning] init makes behavior **implicit** — a function nobody calls is doing things. Modern Go treats init as a code smell: prefer explicit setup (your `store.Open()` pattern, called from main, is the good kind) over init magic. You'll meet init once in the wild, meaningfully: **blank imports** — see section 11.

---

## 6. `go.mod` — The Module's ID Card

`go mod init <path>` creates the file that makes a folder a **module** — the unit Go builds and versions. Your project's, first lines:

```go
module expense-tracker

go 1.26.3
```

- **`module`** — the module path: the namespace your import paths hang off (section 3)
- **`go 1.26.3`** — minimum Go version for this code (language features gate on it)

As you add dependencies, `go get` appends **requirement lines**:

```go
require modernc.org/sqlite v1.56.0
```

- **`require`** — the dependency manifest with exact versions

**`replace` and `exclude`** sit alongside — the escape hatches:

```go
replace old => new v1.2.3      // use THIS module instead of the published one
exclude bad v1.4.0             // pretend a broken version doesn't exist
```

`replace` is the actor's trick: you can point a dependency at a local folder (`replace foo => ../foo`) for day-to-day dev on both modules simultaneously.

> [!note] `go mod init` is how your project began. Without it, Go refuses to treat the folder as a project — which is why running `go build` first thing in a bare folder fails with a confusing "go.mod not found" or "directory prefix does not contain main module".

---

## 7. `go.sum` — The Integrity Ledger

Every time you `go get` a dependency, Go records its **cryptographic hashes** in `go.sum`:

```go
modernc.org/sqlite v1.56.0 h1:kVGh5Zr0TrKdiA7ignhlF7v...
modernc.org/sqlite v1.56.0/go.mod h1:SWZR0oLk6DnN...
```

Its job: **verification.** On later builds, Go re-hashes what's in the module cache and compares. If bytes changed (an attacker, a corrupt cache, a truncated download), the build fails loudly rather than silently running tampered code.

You never edit `go.sum` by hand — `go mod tidy` and `go get` maintain it. If it ever disagrees with reality, `go mod tidy` reconciles.

> [!tip] The h1:/go.mod entry pair is normal. The second entry records the hash of the module's own go.mod, protecting the whole dependency graph — not just the code.

---

## 8. go get, go mod tidy, go mod vendor

The three commands of daily module life — you've run the first two already:

| Command | Job |
|---|---|
| `go get <module>@<version>` | add/update a dependency + write go.mod/go.sum (your `go get modernc.org/sqlite`) |
| `go mod tidy` | reconcile: add missing requirements, drop unused ones — the "make it consistent" sweep |
| `go mod vendor` | copy all deps into a `vendor/` folder so the build uses local copies |

- **`go mod tidy`** is the hygiene habit: run it after any import change; the build only depends on it when your imports and go.mod disagree.
- **`go mod vendor`** is for hermetic builds (CI, offline). When `vendor/` exists, builds use it exclusively.

> [!practice] **Project ritual.** Go to the project root and run `go mod tidy`, then `git diff go.mod go.sum` — see exactly what the tool changed (probably nothing, if you're clean) and what a tidy commit looks like.

---

## 9. Semantic Versioning

Go modules follow **semantic versioning** — three numbers, each a promise:

```
v1.4.2
│ │ └── patch: bugfixes only, no behavior change
│ └──── minor: new features, still backwards compatible
└────── major: breaking changes
```

Rules Go enforces:

- **You never require a patch — you require a version**: `v1.4.2` means "at least 1.4.2, newer 1.4.x may satisfy"
- **Major versions are separate paths**: `example.com/foo/v2` is a *different module* than `example.com/foo` — because v2 breaks compatibility, it must not collide
- **`v0.x` and pre-1.0** versions make no compatibility promises — this is where most young modules live (no guarantee of stability)

> [!note] The driver you installed is `v1.56.0`, now hidden under `modernc.org/libc`, `modernc.org/memory` etc. — the transitive dependency tree, exactly what go.sum records.

---

## 10. `internal/` Packages — The Privacy Wall

Any package located **under a folder literally named `internal/`** is refused by the Go compiler to any *import path outside that internal's parent*.

```
expense-tracker/
└── internal/
    └── store/

import "expense-tracker/internal/store"   // OK inside this module
import "someone-elses-module/internal/store" // BUILD ERROR:
                                            // use of internal package ...
                                            // not allowed
```

It's the "my guts are not your library" rule: `internal/` means private-to-this-project, **enforced by the compiler** — not by convention, not by naming. If a teammate from another module tries to import your internals, the build refuses.

You used this correctly in the project: every room (`model`, `store`, `web`) lives under `internal/`, and the open doors live in `cmd/`.

> [!tip] **Deciding rule.** Will other people's programs import this? → put it at the top level (it's a public library). Is it your app's private wiring? → `internal/`. When in doubt: `internal/`. Promoting it later (moving a folder up) requires no code changes, only a new path.

---

## 11. Blank Imports

A blank import is a dependency imported **purely for its side effects**, with no name used:

```go
import (
    "database/sql"
    _ "modernc.org/sqlite"   // the blank one
)
```

When Go loads the blank-imported package, it runs that package's `init()`s (section 5) and *nothing else* is kept. For `modernc.org/sqlite`, its init **registers itself** with `database/sql` as the driver called `"sqlite"` — which is why the very next line can say `sql.Open("sqlite", ...)`.

The connection chain:

```
your code → database/sql asks "who's the 'sqlite' driver?"
           → the driver's init() answered: "I am" — at import time, via _ import
```

> [!warning] Blank imports are rare and deliberately shouting "I import this for init side effects". Only a handful of libraries are designed for it (database drivers, image format decoders, profiling tools). Donate imports with names when possible; read the `_` as a label saying *"there's invisible startup code here"*.

---

## 12. Dot Imports (anti-pattern)

A dot import does this:

```go
import . "fmt"

Println("hello")   // method "inlined" into this file
```

It lets you call the imported package's exported names **as if they were local**. Tempting for brevity — but:

- You lose track of where `Println` came from
- Two dot imports can collide (both export `Println`?)
- Tools and humans lose provenance

Go keeps dot imports in the core of the language but the community treats them as a smell. Leave them out. (The one sanctioned corner: writing tests of a package *as if inside it* — advanced, not for now.)

---

## 13. Package Naming

Rules and taste in one string:

- **Lowercase, one word** — `model`, `store`, `web`. No underscores, no camelCase in folder/package names (`syncMap` → `syncmap`? No — just `syncmap` or `sync`).
- **The name is the usage** — a package named `model` is used as `model.Expense`; keep names short so call sites read like sentences.
- **Avoid** colliding with common words (`http`, `fmt`, `json`, `net`) in your own imports — `server/json` and stdlib `encoding/json` in the same file is a rename-waiting-to-happen.

> [!practice] **Project exercise.** Say out loud what each of your project's package names contributes at the call site: `model.Expense`, `store.Open`, `web.ListPage`. If any name were generic (`utils`, `common`, `helpers`), which of your files would get worse? That's the vocabulary argument for good naming.

---

## 14. Organizing Code — the cmd/internal Layout

The layout you already live in is the community standard:

```
expense-tracker/
├── go.mod
├── cmd/
│   └── expense/main.go        # entry points: thin, wire dependencies, run
├── internal/
│   ├── model/                 # pure data + logic, no side effects
│   ├── store/                 # the only SQL, behind own package
│   └── web/                   # handlers, templates
└── web/
    └── templates/             # static-ish HTML
```

The rules embedded in this shape:

1. **`cmd/` holds only the front doors** — thin main.go files that assemble things. Business logic lives below.
2. **Dependencies point downward** — `cmd` imports `internal/web` imports `internal/store` imports `internal/model`; model imports nothing of yours. Never the reverse.
3. **The wall rule** — each room's secrets (SQL in `store`, `db` field) are unexported; doors are the exported methods.

If you respect the flow, you can swap SQLite for JSON without touching web code — the design's escape hatch from the project plan.

> [!info] This is the structure real projects (Docker, Kubernetes, the Go tooling itself) use; you've now *owned* it by working inside it, not just reading about it.

---

## 15. Build Constraints

A build constraint tells the compiler **when a file participates**:

```go
//go:build linux

package sysutil   // this file exists only on Linux builds
```

Uses:

- **OS-specific code**: `file_linux.go` (with `//go:build linux`), `file_windows.go` (`//go:build windows`)
- **Feature flags**: `//go:build cgo`

The most common form is automatic: filename suffixes `_linux`, `_darwin`, `_amd64` already imply constraints without the comment. Enable via the `GOOS`/`GOARCH` env vars or build tags in `go build`.

> [!note] The old `// +build` comment syntax is retired; current Go writes `//go:build` and reformats the older style automatically.

---

## 16. Workspaces (brief)

A **workspace** (`go.work` file at a common root) groups several modules for local development — e.g. when you're developing module A and module B that depends on it, both on disk:

```go
go 1.26

use (
    ./expense-tracker
    ./shared-library
)
```

Everything in the workspace builds from source, ignoring version pins — the command-line equivalent of many `replace` lines. You'll reach for it when you have a multi-repo project or are patching a library you depend on. One module, of course, needs nothing of this.

---

## 17. Quick Reference Cheatsheet

```go
# Module lifecycle
go mod init <path>          # start a module (go.mod)
go get <module>@<version>   # add/update a dependency
go mod tidy                 # reconcile go.mod/go.sum with imports
go mod vendor               # copy deps into vendor/ for hermetic builds
go build ./...              # build everything
go vet ./...                # static-check everything

# Syntax reminder
package main                 # executables; func main() required; lives in cmd/
package store                # libraries: named by folder, imported by path
import "expense-tracker/internal/store"   # module path + folder walk
import _ "modernc.org/sqlite"             # blank import = init side effects
func init() { }              # runs at load; treat as rare

# Visibility is naming
Capital()   # exported — the API anyone may call
lowercase   # unexported — private to the folder

# go.mod
module my/project
go 1.26.3
require example.com/thing v1.4.2
replace example.com/thing => ../local-thing
```

> [!practice] **Project laser.** Open `internal/store/store.go` and answer, from this note only: (1) why is the import of `modernc.org/sqlite` blank? (2) why can `cmd/expense` call `store.Open` but not grab `st.db`? (3) what would happen if tomorrow you moved `internal/store` to the project root? — then discuss with me; three of the hardest chapter concepts, one file.

---

_Previous: [[16 - Generics]] · Next: [[18 - Standard Library]]_