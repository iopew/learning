# Go (Golang)

## What is it?

Go is a statically typed, compiled language built at **Google in 2009** by Robert Griesemer, Rob Pike, and Ken Thompson. Designed to fix slow compiles, verbose code, and poor concurrency in existing languages.

---

## Why use it?

| Strength          | Detail                                                     |
| ----------------- | ---------------------------------------------------------- |
| Fast compilation  | Near-instant builds even for large codebases               |
| Goroutines        | Cheap, lightweight concurrency (not OS threads)            |
| Single binary     | Compiles to one self-contained executable — easy to deploy |
| Strong stdlib     | HTTP, JSON, testing, file I/O — no extra packages needed   |
| Simple syntax     | Small spec, no inheritance, quick to learn                 |
| Garbage collected | No manual memory management                                |

---

## Where it's used

- API servers & microservices
- CLI tools
- DevOps / infrastructure tooling
- Bots and background services

**Real-world examples:** Docker, Kubernetes, Terraform, Prometheus, CockroachDB, Hugo

---

## Weaknesses

- Verbose error handling (`if err != nil` everywhere)
- Generics only added in 1.18 — still maturing
- Not ideal for CPU-bound number crunching (vs Rust/C)
- Smaller ecosystem than Python/JS for ML

---

## Key Concepts

```text
Go/
├── 00 - Overview.md
├── 01 - Variables & Types.md        ← var, :=, const, iota, zero values
├── 02 - Operators.md                ← arithmetic, comparison, logical, bitwise
├── 03 - Control Flow.md             ← if/else, switch, for, break, continue, goto
├── 04 - Loops.md                    ← for variants, range, infinite loops, labels
├── 05 - Functions.md                ← signatures, multiple returns, variadic, defer, closures, init
├── 06 - Arrays & Slices.md          ← internals, append, copy, gotchas
├── 07 - Maps.md                     ← CRUD, nil maps, iteration order, existence check
├── 08 - Strings & Runes.md          ← UTF-8, byte vs rune, string iteration, conversion
├── 09 - Pointers.md                 ← *, &, nil pointers, when to use
├── 10 - Structs & Methods.md        ← embedding, value vs pointer receivers, tags
├── 11 - Interfaces.md               ← implicit satisfaction, empty interface, type assertion, type switch
├── 12 - Error Handling.md           ← errors as values, wrapping, unwrapping, custom errors, sentinel errors
├── 13 - Goroutines.md
├── 14 - Channels.md                 ← buffered, unbuffered, direction, select, close
├── 15 - Sync Primitives.md          ← Mutex, RWMutex, WaitGroup, Once, atomic
├── 16 - Generics.md                 ← type parameters, constraints, when to use
├── 17 - Packages & Modules.md       ← go.mod, go.sum, imports, visibility, init order
├── 18 - Standard Library.md         ← fmt, os, io, bufio, strings, strconv, math, sort, time
├── 19 - net/http.md                 ← server, client, handlers, middleware, request/response
├── 20 - encoding/json.md            ← marshal, unmarshal, struct tags, streaming
├── 21 - File I/O.md                 ← os, bufio, filepath, reading, writing, walking
├── 22 - Testing.md                  ← testing package, table tests, subtests, mocks, benchmarks, fuzzing
├── 23 - CLI Tools.md                ← os.Args, flag package, cobra (optional)
├── 24 - Context.md                  ← cancellation, timeout, WithValue, propagation
├── 25 - Reflection.md               ← reflect package, use cases, why to avoid it
└── 26 - Patterns & Idioms.md        ← worker pools, pipelines, functional options, builder, singleton
```


# Prompts 

I’d like to learn about Functions in Go comprehensively with detailed examples. Include all the data, so that I have no questions left. Just Everything. Make it copyable for Obsidian. Include all the nuances, problems, limitations and advantages. Make very clear and engaging. Use a lot of examples with detailed explanation

---

Make questions for anki until the the end of 12th section (generic functions). Avoid Yes\No questions. Make them contemplative and complex. Include coding. Make a lot of questions, do not limit yourself to a few questions for the section, make a lot of them, so that YOU COVER EVERYTHING, do not miss anything. I expect a MINIMUM of 50 questions

