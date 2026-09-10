# Python

> [!info] **Roadmap 2026-09-10 → 2027-03 — University + Parity Path** (6 months, today 2026-09-10)
> **Goal:** Finish `Python 00-26` parity with `Golang 00-26` + `Python 27-35` Python-only extras + ship university labs (NumPy/Pandas/Visualization + FastAPI/Flask) + keep `quicknotes` Go lab separate.
> **Rhythm:** 3-4h/day — morning 1 note (theory) + afternoon 1 bite (bench/repl). `pytest` + `mypy` after each bite. `Golang/§§ - About Golang.md` and `Golang/Auth/§§ - About Auth.md` remain source for Go/Auth execution order — Python has its own parity order below.

## 0. Roadmap 2026-09-10 → 2027-03

| Phase | Dates | Focus | Deliverable |
|---|---|---|---|
| **Phase 1 — Core Language** | **Sep 10 → Sep 30 (3w)** | `Python 00 Overview` + `01 Variables` + `02 Operators` + `03 Control Flow` + `04 Functions` + `05 Lists & Tuples` + `06 Dictionaries & Sets` + `07 Strings` + `08 References` | `python -m pytest` green on `01-08` katas, `f-string`/`list comp` fluent |
| **Phase 2 — OOP & Errors** | **Oct 01 → Oct 15 (2w)** | `09 Classes` + `10 Protocols` + `11 Exceptions` + `16 Type Hints` + `17 Modules` + `24 Context Managers` | `dataclass` + `Protocol` + `try/except` + `venv`/`pyproject.toml` clean |
| **Phase 3 — Concurrency & IO** | **Oct 16 → Oct 31 (2w)** | `12 Threads & Async` + `13 Generators` + `14 Async Select` + `15 Synchronization` + `21 File I/O` + `18 Standard Library` | `threading` vs `asyncio` demo, `yield` pipeline, `pathlib` + `with` |
| **Phase 4 — Web & Data** | **Nov 01 → Nov 30 (4w)** | `19 Web & HTTP` + `33 Web Frameworks (FastAPI primary, Flask compare)` + `20 JSON` + `27 Comprehensions` + `28 Decorators` | `FastAPI` `GET /notes` JSON `20` + `pytest` `httpx` |
| **Phase 5 — University Data Track** | **Dec 01 → Jan 15 (6w)** | `30 NumPy` + `31 Pandas` + `32 Visualization` + `34 Databases & ORM` + `35 Automation` + `29 Venv & Packaging` deep | `numpy`/`pandas` labs, `matplotlib` plots, `SQLAlchemy` `sqlite`, `argparse` script |
| **Phase 6 — Polish & Patterns** | **Jan 16 → Mar 01 (6w)** | `22 Testing` + `23 CLI` + `25 Introspection` + `26 Patterns & Idioms` + `18` polish | `pytest -cov` + `mypy` green, `click` CLI, portfolio `README` |

> **Parity rule:** File numbers stay `Python 01-26` stable for Anki/Q/A rotation with `Golang 01-26`; execution follows Phase 1→6 above, not numeric order. `27-35` are Python-only short notes at end, like `Auth 21-31` at end of `Golang/Auth/§§ - About Auth.md`.

---

## What is it?

Python is a dynamically typed, interpreted language created by **Guido van Rossum in 1991**. Designed for readability, rapid development, and Batteries Included — heavy use in web, data science, ML, automation, and university labs (Tashkent).

---

## Why use it?

| Strength | Detail |
|---|---|
| Readability | Indentation as syntax, minimal boilerplate — quick to learn |
| Batteries Included | `os`, `json`, `re`, `datetime`, `pathlib` — no extra packages needed |
| Data ecosystem | `numpy`, `pandas`, `matplotlib` — Go's weakness `Golang/§§ - About Golang.md:57` is Python's strength |
| Web frameworks | `Flask` (micro, 2010) / `FastAPI` (modern, 2018, async + type hints + auto docs) |
| Automation | `subprocess`, `argparse`, `pathlib` — glue language for scripts |
| Interactivity | `REPL` (`python`), `Jupyter` — instant feedback vs Go `go run` compile |
| Dynamic typing | No `var int` — `x = 5` infers type; `mypy` adds optional static checks |

---

## Where it's used

- Web APIs & sites — `Flask`/`FastAPI`/`Django`
- Data analysis & ML — `numpy`/`pandas`/`scikit-learn`
- Automation & CLI — `os`/`subprocess`/`argparse`/`click`
- University labs — Tashkent `numpy`/`matplotlib` tasks

**Real-world examples:** Instagram (Django), YouTube, Dropbox, Netflix (data), Ansible

---

## Weaknesses

- GIL — only one thread runs Python bytecode at a time (vs Go goroutines `12 - Goroutines.md`)
- Slower than Go/Rust for CPU-bound loops — needs `numpy` vectorization
- Dynamic typing — `TypeError` at runtime vs Go compile-time `int` check
- Packaging — `venv`/`pip`/`poetry`/`pyproject.toml` more fragmented than `go.mod`
- Version drift — `2` vs `3`, `3.10` `match` vs older

---

## Key Concepts

```text
Python/
├── 00 - Overview.md
│     What Python is, why it exists, REPL vs compiled `go run`,
│     `python -m venv`, `pip`, `pyproject.toml` vs `go.mod`,
│     indentation, dynamic typing, GIL intro
│
├── 01 - Variables & Types.md
│     x = 5 (dynamic), int/float/str/bool/None, type() / isinstance(),
│     is vs ==, id(), mutable vs immutable, None as nil, annotations x: int
│
├── 02 - Operators.md
│     arithmetic (+ - * / // % **), assignment (=, := walrus), comparison,
│     logical and/or/not (short-circuit), bitwise (& | ^ ~ << >>),
│     membership in / is, precedence, no ++/--, no ternary (X if C else Y)
│
├── 03 - Control Flow.md
│     if/elif/else, if with walrus, match (3.10+ vs Go switch),
│     for (for x in xs, for i in range), while, for...else, while...else,
│     break/continue, pass, try/except intro
│
├── 04 - Functions.md
│     def, return (multiple via tuple), *args/**kwargs, defaults (mutable trap),
│     first-class functions, lambda, closures, decorators intro, higher-order,
│     * unpacking, recursion, no overloading (vs Go functional options)
│
├── 05 - Lists & Tuples.md
│     list (dynamic array, append/pop, [low:high:step], copy vs view),
│     tuple (immutable, packing/unpacking), list vs tuple, array module footnote,
│     nested lists, 2D lists, sorting (sort/sorted, key=), searching
│
├── 06 - Dictionaries & Sets.md
│     dict {} syntax, dict comprehensions, get()/setdefault(), del/pop,
│     iteration (unordered pre-3.7, ordered 3.7+), nested dicts, dict of lists,
│     counting with dict/Counter, set {}/set(), set ops (| & - ^)
│
├── 07 - Strings.md
│     str immutable, f-strings (f"{x}"), len vs chars, raw r"", .format(),
│     concatenation (+, join, builder via list+join), str methods (split/join,
│     strip, upper/lower, replace, find, startswith), re module, bytes vs str
│     (vs Go byte/rune), encoding utf-8, slicing safely
│
├── 08 - References & Mutability.md
│     No &/*, but id() and is, mutable (list/dict) vs immutable (int/str/tuple),
│     aliasing gotcha (a = b; a.append), copy.copy vs copy.deepcopy,
│     None as nil, default mutable argument trap (def f(x=[]))
│
├── 09 - Classes & Objects.md
│     class, __init__ (vs Go struct), self, instance vs class vars,
│     methods, @dataclass, inheritance (vs Go embedding), super(), composition,
│     @property, __str__/__repr__ (vs Go Stringer), __eq__/__hash__
│
├── 10 - Protocols & ABCs.md
│     Duck typing (if it quacks), typing.Protocol, abc.ABC/abstractmethod,
│     __dunder__ as interfaces ( __len__, __iter__), isinstance vs Protocol,
│     when NOT to use ABCs (vs Go small interfaces)
│
├── 11 - Exceptions.md
│     try/except/else/finally, raise, custom Exception class,
│     hierarchy (BaseException vs Exception), traceback,
│     with vs defer, logging exceptions, bare except anti-pattern
│
├── 12 - Concurrency - Threads & Async.md
│     threading.Thread, GIL vs Go M:N scheduler, async def / await,
│     asyncio.run/gather, threading vs multiprocessing vs asyncio,
│     main exits = program exits (vs Go)
│
├── 13 - Generators & Iterators.md
│     iter() / next(), yield (vs Go channels), generator expression (x for x in xs),
│     yield from, range as iterator, infinite generators, pipeline pattern
│
├── 14 - Async Select & Event Loop.md
│     asyncio.gather/wait, wait_for (timeout), as_completed, queue as channel,
│     event loop, run_until_complete, cancellation via CancelledError
│
├── 15 - Synchronization.md
│     threading.Lock (with), RLock, Semaphore, Event, Condition, Barrier,
│     queue.Queue (thread-safe, vs Go chan), multiprocessing.Value
│
├── 16 - Type Hints & Generics.md
│     typing: List[int], Dict[str,int], Optional, Union, TypeVar, Generic[T],
│     dataclass Generic, mypy, when to use hints vs any
│
├── 17 - Modules & Packages.md
│     import (absolute/relative), __init__.py, __name__ == "__main__",
│     pip, venv (python -m venv), pyproject.toml (vs go.mod), requirements.txt,
│     PYTHONPATH, namespace packages
│
├── 18 - Standard Library.md
│     os/sys, pathlib (Join→/ , Dir→parent, Abs→resolve), datetime,
│     collections (Counter, defaultdict, deque), itertools, re, json,
│     math, random, logging (vs Go log/slog)
│
├── 19 - Web & HTTP.md
│     http.server (stdlib, vs Go net/http), requests (GET/POST), http.client,
│     urllib, headers, status codes, cookies (http.cookies), timeouts
│
├── 20 - JSON.md
│     json.loads/dumps, json.load/dump (files), indent, custom via default,
│     dataclass + json, pydantic (vs Go struct tags json:"name")
│
├── 21 - File I/O.md
│     open() modes (r/w/a/x, b), with open() as f: (vs Go defer f.Close()),
│     read/write (read/readline/readlines), pathlib read_text/write_text,
│     csv, JSON files, tempfile, os.scandir/walk
│
├── 22 - Testing.md
│     pytest (test_*.py, assert), unittest, fixtures, parametrize (table-driven),
│     mock (unittest.mock), coverage (pytest-cov), benchmarks (pytest-benchmark)
│
├── 23 - CLI.md
│     sys.argv, argparse (vs Go flag), click (vs cobra), env vars (os.environ),
│     subprocess.run, exit codes (sys.exit)
│
├── 24 - Context Managers.md
│     with (vs Go context.Context — semantic shift), __enter__/__exit__,
│     contextlib.contextmanager, closing, suppress
│
├── 25 - Introspection.md
│     type(), isinstance(), issubclass(), dir(), getattr/hasattr/setattr,
│     inspect (signature, getsource), __dict__, annotations
│
├── 26 - Patterns & Idioms.md
│     EAFP vs LBYL, comprehensions, with, decorators, generators,
│     context managers, dataclasses, singledispatch
│
├── 27 - Comprehensions & Functional.md          ← Python-only
│     list/dict/set comps, nested comps, walrus in comps,
│     lambda, map/filter/reduce vs comps, itertools (chain, islice)
│
├── 28 - Decorators & Metaprogramming.md         ← Python-only
│     @decorator syntax, @property/@classmethod/@staticmethod,
│     closures, functools.wraps, decorators with args,
│     __call__, metaclass intro (type)
│
├── 29 - Virtual Environments & Packaging.md     ← Python-only
│     python -m venv .venv, source .venv/bin/activate, pip install,
│     pip freeze, pyproject.toml [project] vs go.mod, poetry,
│     requirements.txt vs poetry.lock, PYTHONPATH vs GOPATH
│
├── 30 - NumPy Fundamentals.md                   ← Python-only — uni core
│     ndarray vs list, dtype, shape/ndim, broadcasting, vectorization,
│     indexing/slicing, boolean masking, ufuncs, axis, reshape
│
├── 31 - Pandas & Data Analysis.md               ← Python-only — uni core
│     Series/DataFrame, read_csv/read_excel, head/info/describe,
│     loc/iloc, groupby, merge/join/concat, handling NaN (dropna/fillna),
│     apply/map, pivot, time series
│
├── 32 - Visualization.md                        ← Python-only — uni core
│     matplotlib.pyplot, figure/axes, plot/scatter/bar/hist, subplots,
│     seaborn (countplot, heatmap), styling, saving fig.savefig
│
├── 33 - Web Frameworks.md                       ← Python-only
│     Flask (@app.route, Jinja) vs FastAPI (@app.get, pydantic, auto /docs),
│     routing, request/response, JSON (pydantic vs dataclass), cookies/sessions,
│     SQLAlchemy intro, uvicorn vs gunicorn
│
├── 34 - Databases & ORM.md                      ← Python-only
│     sqlite3 (stdlib), SQLAlchemy Core/ORM, DB-API, migrations (alembic),
│     transactions, INDEX, vs Go database/sql + modernc.org/sqlite
│
└── 35 - Automation & Scripting.md                ← Python-only
      os/pathlib, subprocess.run, re, glob, argparse scripting,
      cron, .env via python-dotenv (vs Go os.Getenv), scheduling
```

# Prompts

I’d like to learn about Functions in Python comprehensively with detailed examples. Include all the data, so that I have no questions left. Just Everything. Make it copyable for Obsidian. Include all the nuances, problems, limitations and advantages. Make very clear and engaging. Use a lot of examples with detailed explanation

---

Make questions for anki until the the end of 12th section (generic functions). Avoid Yes\No questions. Make them contemplative and complex. Include coding. Make a lot of questions, do not limit yourself to a few questions for the section, make a lot of them, so that YOU COVER EVERYTHING, do not miss anything. I expect a MINIMUM of 50 questions

---

---

## Context for Claude

I am learning **Python** from scratch for university, alongside **Go (Golang)**. Here is everything you need to know to continue helping me effectively.

---

### My Setup

- **Editor:** Obsidian (notes use wikilinks `[[#Section]]`, callout blocks `> [!warning]`, `> [!tip]`, `> [!info]`)
- **Platform:** Mac (Apple M2, Mac14,2)
- **Location:** Tashkent, Uzbekistan
- **Learning tools:** Anki (flashcards with spaced repetition), YouTube videos
- **Python knowledge level:** Beginner (university), progressing systematically — Go 01-19 ✅ DONE per `Golang/§§ - About Golang.md`, Python greenfield
- **Go knowledge level:** Intermediate (01-19 DONE, Auth 01 DONE, 02-31 pending)

---

### Note Style & Preferences

Every Obsidian note follows this structure (same as `Golang/§§ - About Golang.md`):

- File name: `NN - Topic.md` (zero-padded number, e.g. `04 - Functions.md`)
- `# Python — Topic` H1 (NOT frontmatter-YAML; the metadata is a blockquote on line 3: `> **Series:** Python Fundamentals **Tags:** #python #... **Level:** Beginner → Intermediate`)
- `## Table of Contents` with `[[#Section]]` wikilinks
- Sections numbered `## 1.`, `## 2.`, ... (subsections `### 1.1`)
- Obsidian callout blocks: `> [!note]`, `> [!warning]`, `> [!tip]`, `> [!info]`, `> [!practice]` — practice callouts end each meaningful section
- Code blocks with `python` syntax highlighting — examples are complete/runnable when relevant (if __name__ == "__main__" included)
- Cross-reference other notes as wikilinks with link text: `[[04 - Functions]] §12`
- Cheatsheet is the SECOND-TO-LAST section (`## N. Quick Reference Cheatsheet`)
- Last line: navigation `_Previous: [[x]] · Next: [[y]]_`
- Follow-ups/gotchas are mirrored in About.md (descriptor + tree entry), and marked `✅ DONE` / `← NEXT` in the tree above
- Vault location: `~/Documents/Learning/Python/` — sibling to `~/Documents/Learning/Golang/` and `~/Documents/Learning/Golang/Auth/`

---

### How the Assistant Works in This Project

When a new session starts, the user pastes a session summary. The assistant should:

1. Read this file (`Python/§§ - About Python.md`) — it is the source of truth for conventions, curriculum, and state. No questions about note style or topic order; follow conventions directly.
2. **Answer questions in chat FIRST.** Explanations happen in the chat conversation, teaching style:
   - Examples before theory, minimal jargon, short blocks matching the vault notes
   - Mental models/analogies (list as dynamic array vs tuple as sealed box, GIL as single cashier, etc.)
   - When the user says "I don't understand" — re-explain from zero with a concrete tiny example, then ask WHERE it breaks (which step)
3. **Write to the vault ONLY when asked** ("create the topic", "update the note").
4. When creating a topic note: follow the descriptor in "What Each Note Should Cover" below, the style above, and the existing `Golang/NN - Topic.md` notes as templates (same callouts, depth, structure). After creating: update the tree marker (`✅ DONE`/`← NEXT`) and note any new facts in "Current State" below.
5. Code demos live as `.py` files next to the notes (`python_demos/`). Run `python -m pytest` / `python file.py` to verify before presenting. Small one-off snippets go in chat only, unless the user asks for a demo file.
6. Verify cross-links after creating a note (Previous/Next navigation both directions).
7. **Session exports live in `~/Documents/Learning/session-exports/`** — one level ABOVE `Python/` + `Golang/`, shared across learning projects. Write new exports there — never loose in `Python/` or `Golang/` or anywhere else. Naming: `session-YYYY-MM-DD.md`, where the date is the day the session **ended** (its last Updated timestamp).

### Current State

- Topics **00 Overview ← NEXT** (not yet created) — you are about to start Python while `Golang 01-19 ✅ DONE` and `Auth 01 ✅ DONE` (14 sections, bench explained). Next: **00 - Overview.md** then `01 - Variables & Types.md`.
- Vault location: `~/Documents/Learning/Python/` — sibling to `~/Documents/Learning/Golang/` (01-19 DONE). Python vault is `00-35` (36 notes inc Overview) — `27-35` are Python-only short notes at end (Comprehensions, Decorators, Venv, NumPy, Pandas, Visualization, Web Frameworks, Databases, Automation) like `Auth 21-31` at end of `Golang/Auth/§§ - About Auth.md`.
- Pending lab: University labs will be the bench for `30-32` (NumPy/Pandas/Matplotlib) — `Python/python_demos/` mirrors `Golang` demo shape.
- Naming: `NN - Topic.md` zero-padded, `§§ - About Python.md` is the index — same as `§§ - About Golang.md` and `§§ - About Auth.md`.
- **2026-09-10 Created:** Python vault scaffolded as 35-topic parity + Python-only structure per your "add as much as relevant, I do not want to miss on something" — `00-26` mirrors `Golang 00-26` for Anki/Q/A rotation, `27-35` are Python-only short topics at end.

---

### Curriculum Structure

The full Python learning path I am following (files stay `NN` stable; **execution follows Phase 1→6** above):

```
Python/  — file numbers (stable for Obsidian links)
├── 00 - Overview.md                 ← NEXT
├── 01 - Variables & Types.md
├── 02 - Operators.md
├── 03 - Control Flow.md
├── 04 - Functions.md
├── 05 - Lists & Tuples.md
├── 06 - Dictionaries & Sets.md
├── 07 - Strings.md
├── 08 - References & Mutability.md
├── 09 - Classes & Objects.md
├── 10 - Protocols & ABCs.md
├── 11 - Exceptions.md
├── 12 - Concurrency - Threads & Async.md
├── 13 - Generators & Iterators.md
├── 14 - Async Select & Event Loop.md
├── 15 - Synchronization.md
├── 16 - Type Hints & Generics.md
├── 17 - Modules & Packages.md
├── 18 - Standard Library.md
├── 19 - Web & HTTP.md
├── 20 - JSON.md
├── 21 - File I/O.md
├── 22 - Testing.md
├── 23 - CLI.md
├── 24 - Context Managers.md
├── 25 - Introspection.md
├── 26 - Patterns & Idioms.md
├── 27 - Comprehensions & Functional.md
├── 28 - Decorators & Metaprogramming.md
├── 29 - Virtual Environments & Packaging.md
├── 30 - NumPy Fundamentals.md
├── 31 - Pandas & Data Analysis.md
├── 32 - Visualization.md
├── 33 - Web Frameworks.md
├── 34 - Databases & ORM.md
└── 35 - Automation & Scripting.md

Execution order (parity + Python extras):
Phase 1 — Core Language (00-08) → Phase 2 — OOP & Errors (09-11,16,17,24) → Phase 3 — Concurrency & IO (12-15,21,18) → Phase 4 — Web & Data (19,33,20,27-28) → Phase 5 — University Data Track (30-32,34-35,29) → Phase 6 — Polish (22-23,25-26)
See ## Roadmap 2026-09-10 → 2027-03 for the phased sequence.
Note: 27-35 are Python-only short topics at end — you study 00 now, so 35 stays at end.
```

---

### What Each Note Should Cover

When I say “let’s explore topic X”, create a **full, detailed Obsidian note** covering everything listed below for that topic.

**00 - Overview.md** What Python is, why it exists, REPL vs compiled `go run`, `python -m venv`, `pip`, `pyproject.toml` vs `go.mod`, indentation, dynamic typing, GIL intro

**01 - Variables & Types.md** `x = 5` dynamic typing, `int/float/str/bool/None`, `type()`/`isinstance()`, `is` vs `==`, `id()`, `None` as `nil`, mutability overview, annotations `x: int = 5`, `Final`, `type` aliases

**02 - Operators.md** Arithmetic `+ - * / // % **`, assignment `=`, walrus `:=`, comparison, logical `and/or/not` (short-circuit), `is`/`in`, bitwise `& | ^ ~ << >>`, precedence, `no ++/--`

**03 - Control Flow.md** `if/elif/else`, `if` with walrus, `match` (3.10+, vs Go switch), `for` (`for x in xs`, `range`), `while`, `for...else`/`while...else`, `break/continue`, `pass`, `try/except` intro

**04 - Functions.md** `def`, `return` multiple via tuple, `*args/**kwargs`, defaults mutable trap `def f(x=[])`, first-class, `lambda`, closures (shared state, loop capture), higher-order, `*` unpacking, recursion, decorators intro

**05 - Lists & Tuples.md** `list` dynamic array (`append/pop`, slicing `[low:high:step]`, `copy`), `tuple` immutable packing/unpacking, `list` vs `tuple`, `array` module footnote, nested lists, sorting (`sort`/`sorted` `key=`), searching

**06 - Dictionaries & Sets.md** `dict` `{}`, comprehensions, `get`/`setdefault`/`pop`, `del`, iteration (ordered 3.7+), nested dicts, `Counter`, `set` ops `| & - ^`, `frozenset`

**07 - Strings.md** `str` immutable, `f""`/`format()`, `len` vs bytes, `str` methods `split/join/strip/upper/lower/replace/find/startswith`, `re`, `bytes` vs `str` (vs Go `byte/rune`), `utf-8`

**08 - References & Mutability.md** No `&/*`, `id()`/`is`, mutable `list/dict` vs immutable `int/str/tuple`, aliasing `a=b; a.append(1)`, `copy.copy`/`deepcopy`, `None`, default arg trap

**09 - Classes & Objects.md** `class`, `__init__`, `self`, instance/class vars, methods, `@dataclass`, inheritance, `super()`, composition, `@property`, `__str__/__repr__`, `__eq__/__hash__`

**10 - Protocols & ABCs.md** Duck typing, `typing.Protocol`, `abc.ABC`/`abstractmethod`, `__dunder__` as interfaces, `isinstance` vs `Protocol`, when NOT to use ABCs

**11 - Exceptions.md** `try/except/else/finally`, `raise`, custom `Exception`, hierarchy, `traceback`, `with` vs `defer`, bare `except` anti-pattern

**12 - Concurrency - Threads & Async.md** `threading.Thread`, GIL vs Go M:N scheduler, `async def`/`await`, `asyncio.run`/`gather`, `threading` vs `multiprocessing` vs `asyncio`, GIL single cashier analogy

**13 - Generators & Iterators.md** `iter`/`next`, `yield`, generator expression, `yield from`, infinite generators, pipeline pattern (vs Go channels)

**14 - Async Select & Event Loop.md** `asyncio.gather/wait`, `wait_for` timeout, `as_completed`, `queue` as channel, event loop, `CancelledError`

**15 - Synchronization.md** `threading.Lock` (`with`), `RLock`, `Semaphore`, `Event`, `Condition`, `Barrier`, `queue.Queue` (vs Go chan), `multiprocessing`

**16 - Type Hints & Generics.md** `typing` `List[int]`/`Dict[str,int]`/`Optional`/`Union`/`TypeVar`/`Generic[T]`, `mypy`, when to use hints vs `any`

**17 - Modules & Packages.md** `import` absolute/relative, `__init__.py`, `__name__=="__main__"`, `pip`, `venv`, `pyproject.toml` (vs `go.mod`), `requirements.txt`, `PYTHONPATH`

**18 - Standard Library.md** `os/sys`, `pathlib`, `datetime`, `collections` (`Counter`/`defaultdict`/`deque`), `itertools`, `re`, `json`, `math`, `random`, `logging`

**19 - Web & HTTP.md** `http.server` (vs Go `net/http`), `requests` `GET/POST`, `urllib`, headers/status/cookies/timeouts

**20 - JSON.md** `json.loads/dumps`, `load/dump`, `indent`, custom via `default`, `dataclass` + `json`, `pydantic`

**21 - File I/O.md** `open()` modes `r/w/a/x/b`, `with open() as f:` (vs `defer f.Close()`), `read/readline`, `pathlib` `read_text`, `csv`, `tempfile`

**22 - Testing.md** `pytest` `test_*.py` `assert`, `unittest`, `fixtures`, `parametrize` (table-driven), `mock`, `coverage` `pytest-cov`, benchmarks

**23 - CLI.md** `sys.argv`, `argparse` (vs Go `flag`), `click` (vs `cobra`), `os.environ`, `subprocess.run`, `sys.exit`

**24 - Context Managers.md** `with` (vs Go `context.Context` — semantic shift noted), `__enter__/__exit__`, `contextlib.contextmanager`, `closing`/`suppress`

**25 - Introspection.md** `type()`/`isinstance()`/`issubclass()`, `dir()`/`getattr`/`hasattr`/`setattr`, `inspect` (`signature`/`getsource`), `__dict__`, `annotations`

**26 - Patterns & Idioms.md** EAFP vs LBYL, comprehensions, `with`, decorators, generators, `dataclasses`, `singledispatch`, `contextlib`

**27 - Comprehensions & Functional.md** `list/dict/set` comps, nested comps, walrus in comps, `lambda`, `map/filter` vs comps, `itertools` `chain/islice`

**28 - Decorators & Metaprogramming.md** `@decorator`, `@property`/`@classmethod`/`@staticmethod`, `functools.wraps`, decorators with args, `__call__`, metaclass `type` intro

**29 - Virtual Environments & Packaging.md** `python -m venv .venv`, `source .venv/bin/activate`, `pip install`, `pip freeze`, `pyproject.toml` `[project]` vs `go.mod`, `poetry`, `requirements.txt`

**30 - NumPy Fundamentals.md** `ndarray` vs `list`, `dtype`, `shape/ndim`, broadcasting, vectorization, indexing/slicing, boolean masking, `ufuncs`, `axis`, `reshape`

**31 - Pandas & Data Analysis.md** `Series`/`DataFrame`, `read_csv`/`read_excel`, `head/info/describe`, `loc/iloc`, `groupby`, `merge/join/concat`, `NaN` `dropna/fillna`, `apply/map`, `pivot`, time series

**32 - Visualization.md** `matplotlib.pyplot`, `figure`/`axes`, `plot/scatter/bar/hist`, `subplots`, `seaborn` `countplot/heatmap`, styling, `savefig`

**33 - Web Frameworks.md** `Flask` (`@app.route`, `Jinja`) vs `FastAPI` (`@app.get`, `pydantic`, auto `/docs`) — **FastAPI primary** per your 35 choice, routing, `request`/`response`, JSON, cookies/sessions, `uvicorn`

**34 - Databases & ORM.md** `sqlite3` stdlib, `SQLAlchemy` Core/ORM, `DB-API`, migrations `alembic`, transactions, `INDEX`, vs Go `database/sql` + `modernc.org/sqlite` `Golang/Auth/13`

**35 - Automation & Scripting.md** `os`/`pathlib`, `subprocess.run`, `re`, `glob`, `argparse` scripting, `cron`, `.env` via `python-dotenv` (vs Go `os.Getenv`), scheduling

---

### Anki Card Style

When making Anki questions:

- **No yes/no questions** — all questions must be contemplative and complex
- **Include coding questions** — predict output, spot the bug, write the fix
- **Cover everything** — aim for minimum 25-30 cards per topic, do not miss sections
- **Format:**
    
    ```
    Q: [question]A: [answer with code if needed]
    ```
    

---

### Teaching Style Preferences

- Explain things **from scratch with examples** when I say I don't understand
- When I ask "explain this" with a screenshot or code snippet — break it down step by step, simply
- When I ask for **more examples** — give different scenarios, not variations of the same one
- Keep explanations **focused** — no unnecessary padding
- When I paste a document and ask to **update it** — only change what was asked, leave everything else untouched
- When I say **"make questions for Anki"** with a pasted document — cover every section, minimum 25 cards
- When I say **"lets explore [topic]"** — create the full Obsidian note outputting it as a downloadable `.md` file

---

### Conversation Patterns Established

- I paste my Obsidian note → ask for Anki cards → you cover every section
- I paste a screenshot of code from my notes → ask "explain this" → you break it down simply
- I ask "what is X" mid-topic → you explain it clearly with examples, then offer to connect it back to the current topic
- I say "update the document" → you only change what was requested
- I say "add more detail to section X" → you update just that section, leave others untouched
- When I don't understand something → I tell you directly, you start fresh with a simpler explanation
- Notes that are already done do NOT need to be recreated — just reference them

---

### Topics Already Deeply Discussed (Beyond the Notes)

These came up during conversation and were explained in detail — no need to re-explain unless asked:

- Why `defer` captures arguments immediately vs closures seeing current values
- Named return values + defer interaction
- Why `f.Close()` can fail and why the named return pattern catches it
- `panic` unwind, `log.Fatal` vs `panic`
- Handlers, parsers, middleware chains
- `recover()` only in `defer`
- Closures, shared state
- `any` vs `interface{}` (Go)
- Type assertions on interfaces
- `init()` FIFO
- Functional options, set pattern `map[T]struct{}`
- Typed nil vs untyped nil (Go)
- Cookies, AuthN vs AuthZ, sessions vs JWT (Go Auth)
- Bcrypt cost tuning, bench `ms/op`, pepper, rehashing, salt collisions, quantum nuance

---

## Context for OpenCode

You are teaching me **Python + Go (Golang) + Auth**. Follow these rules precisely:

### Style

- **No water.** Be concise, precise, concrete. Cut fluff, verbose explanations, analogies, and content that belongs in other topics.
- **Examples first.** Lead with runnable code, then explain.
- **Obsidian format.** Use `[[#Section]]` wikilinks, `> [!note]`/`> [!warning]`/`> [!tip]` callouts, `python` syntax highlighting, frontmatter tags, and navigation links at the bottom.

### How to handle requests

- **"Let's explore [topic]"** — Create a full Obsidian note for that topic covering every listed point. Output as downloadable `.md`.
- **"Explain this"** (code/screenshot) — Break it down step by step from scratch.
- **"Make questions for Anki"** — Cover every section. No yes/no. Include code questions. Minimum 25-30.
- **"Remove water from [topic]"** — Strip fluff, cut verbose explanations, remove off-topic content, keep concrete examples.
- **"Update the document"** — Only change what was asked. Leave everything else untouched.
- User says they don't understand — Explain more simply with fresh examples.

### Curriculum state

Topics `Golang 01-19 ✅ DONE`, `Golang 20 - encoding/json ← NEXT`. `Python 00-35` scaffolded `2026-09-10` as `00-26` parity + `27-35` Python-only (35 notes inc Overview) — `27` Comprehensions `28` Decorators `29` Venv `30` NumPy `31` Pandas `32` Visualization `33` Web Frameworks (FastAPI primary) `34` Databases `35` Automation. Auth `Golang/Auth 01 ✅ DONE` (14 sections), `00 Overview ← NEXT`. Vaults: `Golang/` + `Python/` siblings under `~/Documents/Learning/`, Auth under `Golang/Auth/`.

---

## Prompts (Python)

I’d like to learn about Variables & Types in Python comprehensively with detailed examples. Include all the data, so that I have no questions left. Just Everything. Make it copyable for Obsidian. Include all the nuances, problems, limitations and advantages. Make very clear and engaging. Use a lot of examples with detailed explanation

---

Make questions for anki until the end of 06 - Dictionaries section. Avoid Yes\No questions. Make them contemplative and complex. Include coding. Make a lot of questions, do not limit yourself to a few questions for the section, make a lot of them, so that YOU COVER EVERYTHING, do not miss anything. I expect a MINIMUM of 50 questions

---
