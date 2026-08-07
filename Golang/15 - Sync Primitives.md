# Go — Sync Primitives

> **Series:** Go Language Fundamentals **Tags:** #go #golang #sync #mutex #waitgroup #atomic #concurrency #programming **Level:** Intermediate

---

## Table of Contents

- [[#1. What are Sync Primitives?]]
- [[#2. WaitGroup]]
- [[#3. Mutex]]
- [[#4. RWMutex]]
- [[#5. Once]]
- [[#6. sync.Cond]]
- [[#7. sync.Map]]
- [[#8. sync/atomic]]
- [[#9. CAS Retry-Loop Pattern]]
- [[#10. Safe Sharing Patterns]]
- [[#11. Race Detector]]
- [[#12. Quick Reference Cheatsheet]]

---

## 1. What are Sync Primitives?

	Channels and locks solve **different** problems:

|              | Channel                          | Mutex / atomic                           |
| ------------ | -------------------------------- | ---------------------------------------- |
| Problem      | **Pass data** between goroutines | **Protect shared data** from goroutines  |
| Mental model | mail slot / pipe                 | lock on a room                           |
| Typical use  | producer → consumer, pipelines   | many goroutines updating one counter/map |

> [!info] **Go proverb:** "Don't communicate by sharing memory; share memory by communicating." Channels move the data around so it's never shared. When you *must* share (one map, one counter, one config), sync primitives make the sharing safe.

This note covers `sync` (WaitGroup, Mutex, RWMutex, Once, Map) and `sync/atomic` (lock-free operations).

---

## 2. WaitGroup

A **counter with a wait**: `Add(n)` increments, `Done()` decrements, `Wait()` blocks until the counter hits zero.

```go
var wg sync.WaitGroup
wg.Add(2)               // two goroutines to track
go func() { defer wg.Done(); work1() }()
go func() { defer wg.Done(); work2() }()
wg.Wait()               // blocks until both finish
```

**The three rules:**

1. **`Add` before `go`** — call `Add` *before* spawning the goroutine, never inside it. If a goroutine calls `Add(1)` while `Wait()` is already running, the counter can hit zero early and `Wait` returns too soon.

2. **`Done` via `defer`** — `defer wg.Done()` right after `Add`, so it fires even if the goroutine panics.

3. **Never copy a WaitGroup** — pass `*sync.WaitGroup` as a pointer. Copying gives each goroutine its own counter; `Wait` never sees the `Done`s. The race detector will flag it.

**Panic:** `Add` with a negative result (e.g. more `Done` than `Add`) panics — `sync: negative WaitGroup counter`.

```go
// WRONG — Add inside the goroutine races with Wait
go func() { wg.Add(1); defer wg.Done(); work() }()
wg.Wait()   // may return before the goroutine even starts

// WRONG — wg passed by value (copied)
func work(wg sync.WaitGroup) { wg.Done() }

// RIGHT
wg.Add(1)
go func() { defer wg.Done(); work() }()
wg.Wait()
```

> [!practice] **Practice: 100 files, one goroutine each.** Create a fake `process(name string)` that sleeps 20ms and logs. Spawn one goroutine per file for 100 names, `wg.Wait()`, measure time. Then break it: move `wg.Add(1)` *inside* the goroutine — run it repeatedly and watch it fail nondeterministically. That's the "Add before go" rule made visible.

This is what the worker pool and chat hub used — the counter they hang on until everyone is done.

---

## 3. Mutex

A **lock**: only one goroutine holds it at a time. Others block until it's released.

```go
type Counter struct {
    mu sync.Mutex
    n  int
}

func (c *Counter) Increment() {
    c.mu.Lock()
    defer c.mu.Unlock()   // ALWAYS unlock, even on panic
    c.n++
}

func (c *Counter) Value() int {
    c.mu.Lock()
    defer c.mu.Unlock()
    return c.n
}
```

`c.n++` is three operations (read, add, write) — without the lock, two goroutines can interleave and lose an update (the classic race from [[12 - Goroutines]]).

**Rules:**

- **`defer mu.Unlock()`** — one line, can't forget it on early returns. The lock/unlock *must* be paired.
- **Not reentrant** — locking the same mutex twice in one goroutine **deadlocks** (unlike Python/Java). Never call a locking method from inside another locking method.
- **Never copy a Mutex** — same rule as WaitGroup. Always use a pointer receiver (as above).
- **`TryLock()`** (Go 1.18+) — non-blocking attempt: returns `true` if acquired, `false` if held.

```go
if mu.TryLock() {
    defer mu.Unlock()
    // got it — do the work
} else {
    // someone else holds it — skip
}
```

> [!practice] **Practice: the racy counter.** `var n int` + 1000 goroutines doing `n++`, run with `go run -race`. See the report. Then wrap in a Mutex — `-race` comes back clean. This is the single most valuable race-detector exercise in Go.

---

## 4. RWMutex

A Mutex where **many readers** may hold the lock **simultaneously**, but a **writer** needs exclusive access.

```go
type Cache struct {
    mu sync.RWMutex
    m  map[string]string
}

func (c *Cache) Get(key string) string {
    c.mu.RLock()
    defer c.mu.RUnlock()
    return c.m[key]
}

func (c *Cache) Set(key, val string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.m[key] = val
}
```

- Any number of `RLock` holders run at once (reads are safe to overlap)
- A `Lock` waits until **all readers finish** — then runs alone
- New readers arriving while a writer waits must **wait too** (or the writer starves)

**When:** read-heavy workloads — a config cache read 10,000×/s, written 1×/minute. When writes are frequent, RWMutex is *slower* than plain Mutex (lock bookkeeping), and plain Mutex is the right tool.

> [!practice] **Practice: read-heavy cache.** Build `Cache` above, spawn 10 reader goroutines hammering `Get` + 1 writer doing `Set` every 100ms, run with `-race`. Then swap to plain Mutex and compare `time.Since` — see the read overlap win.

---

## 5. Once

Runs a function **exactly once**, even if `Do` is called from many goroutines simultaneously. The other callers *block* until it finishes.

```go
var (
    once  sync.Once
    cfg   Config
)

func Config() Config {
    once.Do(func() { cfg = loadConfig() })  // runs exactly once
    return cfg
}
```

The lazy singleton pattern: 100 goroutines call `Config()`, the loader runs once, all 100 get the same value.

**Panic behavior:** if the function panics, the panic propagates, but **Once still counts it as done** — a retry will NOT re-run the function. If your init can panic and needs retrying, `Once` is the wrong tool (use a mutex + a `done` bool instead).

> [!practice] **Practice: count the executions.** Wrap `loadConfig()` in `fmt.Println("loading...")`, call `Config()` from 100 goroutines, count how many times "loading..." prints. Exactly one.

---

## 6. sync.Cond

A **condition variable** — goroutines **wait** for a condition to become true, and another goroutine **signals** them when it might be true. Unlike a channel, which passes a value, Cond is purely a "wake up and re-check" primitive.

```go
type Queue struct {
    mu sync.Mutex
    items []int
    ready sync.Cond
}

q := &Queue{ready: *sync.NewCond(&q.mu)}

// producer — add an item, wake one waiter
q.mu.Lock()
q.items = append(q.items, 1)
q.ready.Signal()
q.mu.Unlock()

// consumer — wait until there's work, then take one
q.mu.Lock()
for len(q.items) == 0 {
    q.ready.Wait()
}
item := q.items[0]
q.items = q.items[1:]
q.mu.Unlock()
```

**How it works:**

- `Cond` is always **bound to a mutex** (`sync.NewCond(&mu)`)

- `Wait()` — atomically releases the mutex and parks the goroutine. When woken, it re-acquires the lock **before returning** — which is why it must sit inside `for ... { }`, not `if`: after waking, the condition may already be false again (classic "spurious/check-again" wakeup)

- `Signal()` — wakes **one** waiter (works best when there's one consumer per item)

- `Broadcast()` — wakes **all** waiters (use when a condition change affects everyone, e.g. shutdown)

> [!warning] Always use `Broadcast()` for **shutdown-style** conditions — a single `Signal()` wakes only one waiter, and the rest sleep forever.

> [!tip] **Choosing:** A channel usually beats Cond for one-shot handoffs ("send this value"). Cond shines when you have a **condition shared by many waiters** (a queue that grows/shrinks, a pool with available slots) — places where a single `chan struct{}` can't express "several of you might now proceed."

> [!practice] **Practice: the waiter-restaurant.** One producer goroutine appends a number to a shared `items []int` every 200ms and calls `Broadcast()`. Two consumer goroutines `Wait()` in a `for` loop until `len(items) > 0`, each popping and printing one item. Run it: both consumers should wake and split the work. Then change `Broadcast` to `Signal` and watch one consumer starve forever — that's the warning above made real.

## 7. sync.Map

A **concurrency-safe map** that doesn't need a mutex around it.

```go
var m sync.Map
m.Store("key", "value")
v, ok := m.Load("key")
m.Delete("key")
m.Range(func(k, v any) bool { ... })   // iterate
```

**The caveat: it is NOT the default.** `map + Mutex` is usually simpler and faster. `sync.Map` exists for specific access patterns where it beats a mutex:

- **Append-only growth** (keys are written once, read many times)
- **Disjoint keys** (different goroutines touch different keys)
- **Read-heavy with rare writes** (e.g. a cache of open connections)

If you're not sure you need it — you don't. Use `map + Mutex` (or RWMutex) and switch only if profiling says the lock is a hotspot.

> [!tip] The **shared map rule** from [[06 - Maps]]: `map[K]V` is **not** concurrency-safe — concurrent access panics with `fatal error: concurrent map read and map write`. Wrapping in a Mutex or using `sync.Map` is mandatory, never optional.

---

## 8. sync/atomic

**Lock-free** operations on single words (int64, uintptr, pointers, bool). Atomic ops have no lock and no blocking — hardware-level instructions.

```go
var counter uint64

n := atomic.AddUint64(&counter, 1)   // increment, get the new value
atomic.StoreUint64(&counter, 0)      // write
v := atomic.LoadUint64(&counter)     // read
```

Why it matters: `counter++` is three steps (load, add, store) and races; `atomic.AddUint64` is **one step** — safe, no mutex, no contention.

**`atomic.Bool`** (Go 1.19+) — the ergonomic flag:

```go
var ready atomic.Bool
ready.Store(true)
if ready.Load() { ... }
```

**`atomic.Pointer[T]`** — lock-free reads of a shared pointer, the modern config-cache idiom:

```go
type Config struct { Timeout time.Duration }

var current atomic.Pointer[Config]

// writer (rare):
current.Store(&Config{Timeout: 5 * time.Second})

// readers (hot path, no lock):
cfg := current.Load()
```

Readers get a consistent snapshot with zero locking — the config pointer is swapped atomically. This is how production servers hot-reload configs without a mutex on the read path.

> [!practice] **Practice: the downloader's counter.** In the worker-pool download task you wrote `atomic.AddUint64(&globalCounter, 1)` for unique filenames. Re-run it with `-race` — it stays clean. Then swap it back to a plain `counter++` and watch `-race` scream. Atomic vs racy in one edit.

---

## 9. CAS Retry-Loop Pattern

`CompareAndSwap(old, new)` sets the value **only if it still equals old**, returning `true` on success, `false` if someone changed it in between.

That "in between" is the problem: between your `Load` and your `CAS`, another goroutine can modify the value. The fix is a **retry loop** — reload and retry until the CAS succeeds:

```go
var n atomic.Int64

for {
    old := n.Load()
    new := old + 1
    if n.CompareAndSwap(old, new) {
        break        // no one else changed it — we won
    }
    // lost the race — loop and retry with the fresh value
}
```

This is the atomic replacement for `mutex + read-modify-write`: optimistic, lock-free, retries on contention. Use it for complex updates (`Add` only handles simple +1); for plain increments, `atomic.AddInt64` is simpler and faster.

---

## 10. Safe Sharing Patterns

The three ways to share state across goroutines, in order of preference:

1. **Don't share — pass it.** Channels hand the data over; ownership moves (the pipeline, worker pool).
2. **Share read-only.** Slices/maps that are never written after setup — safe to read from any goroutine, no lock needed.
3. **Share with protection.** Mutable shared state + one of: Mutex (writes + reads), RWMutex (read-heavy), atomic (single words), sync.Map (specialized).

**The checklist for any shared value:**

- [ ] Written from more than one goroutine?
- [ ] Written from one, read from many?
- [ ] Never written after setup (read-only)?

| Answer | Solution |
|---|---|
| Never written | no protection needed |
| Written once, read many | `sync.Once` or atomic pointer |
| One writer, many readers | RWMutex |
| Many writers | Mutex or channels |
| Single word, hot path | `sync/atomic` |

**Protect the *data*, not the function.** A method that locks, unlocks, and then *returns a pointer to the data* just moved the race outside. If you hand out a reference, the lock must be held (or a copy returned).

---

## 11. Race Detector

The compiler inserts instrumentation that watches every memory access and reports when two goroutines access the same location with at least one write, without synchronization:

```bash
go run -race main.go
go test -race ./...
go build -race ./...
```

```
==================
WARNING: DATA RACE
Read at 0x00c0000a0008 by goroutine 7:
  main.main.func1()
      main.go:12 +0x3a

Previous write at 0x00c0000a0008 by goroutine 6:
  main.main.func1()
      main.go:12 +0x50
==================
```

**How to read it:** the location (`main.go:12`), the two goroutines involved (read + previous write), and where each was created.

**Limits:**

- **Dynamic analysis** — only finds races that actually happen in *this* run. Run many times under load.
- **~5-10× slower, 2-5× more memory** — development tool, not production.
- A clean run means "no races in this execution" — not "no races, ever."

> [!warning] Always test with `-race` before committing: `go test -race -count=1 ./...`

> [!practice] **Practice: interpret a report.** Deliberately race a counter (see Mutex practice), run `-race`, and walk the report: which goroutine wrote, which read, at which line, created where. Being able to *read* the report is the skill.

---

## 12. Quick Reference Cheatsheet

```go
// WaitGroup — wait for N goroutines
var wg sync.WaitGroup
wg.Add(1)                 // BEFORE go, never inside
go func() { defer wg.Done(); work() }()
wg.Wait()

// Mutex — exclusive access
mu.Lock()
defer mu.Unlock()
mu.TryLock()              // non-blocking attempt

// RWMutex — many readers, one writer
mu.RLock(); defer mu.RUnlock()   // reads
mu.Lock();  defer mu.Unlock()    // writes

// Once — run exactly once
var once sync.Once
once.Do(func() { init() })

// sync.Map — specialized concurrent map
m.Store(k, v); v, ok := m.Load(k); m.Delete(k)

// sync/atomic — lock-free single words
atomic.AddUint64(&n, 1)
atomic.LoadUint64(&n)
atomic.StoreUint64(&n, 0)
var flag atomic.Bool       // flag.Store(true) / flag.Load()
var cfg atomic.Pointer[T]  // cfg.Store(&t) / cfg.Load()

// CAS retry loop
for {
    old := n.Load()
    if n.CompareAndSwap(old, old+1) { break }
}

// Race detector
// go run -race main.go
// go test -race ./...

// errgroup (x/sync, not stdlib): WaitGroup + error propagation
// g := errgroup.Group{}; g.Go(func() error {...}); err := g.Wait()

// Rules
// ✅ Add before go, Done via defer
// ✅ defer mu.Unlock() always
// ✅ pointer receivers for sync types (never copy)
// ✅ -race before committing
// ❌ mutex is not reentrant — no double-lock
// ❌ never share a map without protection
// ❌ sync.Map only for its specialized patterns
```

---

_Previous: [[14 - Select]] · Next: [[16 - Generics]]_
