# Go — Goroutines

> **Series:** Go Language Fundamentals **Tags:** #go #golang #goroutines #concurrency #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. What is a Goroutine?]]
- [[#2. The go Keyword — Starting a Goroutine]]
- [[#3. Goroutines: Fundamentals]]
  - [[#3.1 Goroutines vs OS Threads]]
  - [[#3.2 Goroutine Scheduling — The M:N Scheduler]]
  - [[#3.3 Goroutine Stack — Starts Small, Grows Dynamically]]
  - [[#3.4 Goroutine Lifecycle]]
- [[#4. Goroutines: Safety & Leaks]]
  - [[#4.1 Closures and the Loop Capture Bug]]
  - [[#4.2 Data Races and the Race Detector]]
  - [[#4.3 Goroutine Panics]]
  - [[#4.4 Goroutine Leaks]]
- [[#5. Goroutines: Patterns & Reference]]
  - [[#5.1 Goroutine Patterns]]
  - [[#5.2 The select Statement]]
  - [[#5.3 Goroutines Are Not Coroutines]]
  - [[#5.4 Debugging Goroutines]]
  - [[#5.5 Goroutines and the net/http Server]]
  - [[#5.6 Quick Reference Cheatsheet]]

---

## 1. What is a Goroutine?

A **goroutine** is a lightweight concurrent execution unit managed by the Go runtime — a function that runs independently of, and potentially in parallel with, the code that started it.

```go
func sayHello() {
    fmt.Println("Hello from a goroutine!")
}

go sayHello()
fmt.Println("Hello from main!")
```

The `go` keyword spawns a new goroutine and returns **immediately**, before the spawned function even begins executing. Both the caller and the spawned function run concurrently.

### The core analogy

Think of your program's **main goroutine** as the lead actor on stage. Calling `go f()` is like hiring a stagehand — they start working on their task immediately, in parallel, while the lead actor keeps delivering their lines. You don't wait for the stagehand to finish before continuing the scene. If the lead actor walks off stage (main exits), the entire production stops — the stagehands are gone too, even if they're mid-task.


```pseudocode
mail_slot = empty box that can hold one note at a time,
	with these rules:
		- putting a note in BLOCKS if the box already has one
		waiting (must wait for someone to take it first)
		- taking a note BLOCKS if the box is empty
		(must wait until someone puts one in)
```

### Key characteristics

- **Lightweight** — a running goroutine costs ~4 KB of stack space (grows as needed). You can have hundreds of thousands in one process.
- **Independently scheduled** — the Go runtime decides which goroutine runs on which OS thread and for how long. **You don't control the schedule.**
- **Concurrent by default, parallel when possible** — goroutines interleave on a single core; with `GOMAXPROCS > 1`, they run simultaneously.
- **No identity, no handle** — you cannot kill a goroutine from the outside. You cannot ask "what goroutine am I?" (there is no `goroutine.ID()`). You can only coordinate with it via channels, mutexes, or `sync` primitives.
- **Cooperates with the scheduler at blocking calls** — goroutines automatically yield at I/O, channel operations, `time.Sleep`, mutex locks, and `select` statements.

---

### The problem channels solve

When multiple goroutines run concurrently, they might try to read and write the same piece of memory at the same time. This is a **race condition**. Take something as simple as this:

go

```go
var counter int

func increment() {
    counter++
}

go increment()
go increment()
```

`counter++` looks like one operation, but it's actually three: read the value, add 1, write it back. If two goroutines interleave those three steps, you can lose an update entirely — the final `counter` might be 1 instead of 2. This isn't rare or theoretical; it happens constantly in real concurrent code, and it's notoriously hard to debug because it's often non-deterministic — the bug might not show up every run.

### Two ways to fix it

**Option A: locks (mutexes).** Wrap the shared variable in a `sync.Mutex`, and force goroutines to take turns:

go

```go
var mu sync.Mutex
mu.Lock()
counter++
mu.Unlock()
```

This works, but it means every goroutine still shares the same memory, and _you_ are responsible for remembering to lock and unlock correctly, everywhere that memory is touched. Forget one lock, and you're back to a race condition — the compiler won't catch it for you.

**Option B: channels.** Instead of goroutines sharing memory and fighting over it, one goroutine **owns** a piece of data and other goroutines **send it messages** asking for changes or handing off results:

go

```go
ch <- value  // hand this value off
value := <-ch  // receive it
```

No two goroutines ever touch the same variable directly. Ownership passes cleanly from one goroutine to the next, one at a time, enforced by the channel itself.


## The problem, in pseudocode

Imagine two workers sharing one whiteboard with a single number written on it, starting at 0. Each worker's job is "add 1 to the number, 1000 times."

```
shared_number = 0

worker_A:
    repeat 1000 times:
        read shared_number into temp
        temp = temp + 1
        write temp back to shared_number

worker_B:
    repeat 1000 times:
        read shared_number into temp
        temp = temp + 1
        write temp back to shared_number

run worker_A and worker_B at the same time
```

You'd expect the final answer to be 2000 (1000 from each worker). But here's what can actually happen if they're not coordinated:

```
worker_A: reads shared_number → 5
worker_B: reads shared_number → 5      (before A writes back!)
worker_A: computes 5 + 1 = 6, writes 6
worker_B: computes 5 + 1 = 6, writes 6      ← A's update just got erased
```

Both workers read the _same_ starting value before either had a chance to write their update back. One increment silently vanishes. Run this a thousand times over and the final number ends up **less than 2000** — how much less depends on random timing, which is what makes this bug so nasty: it's not wrong every time, just unpredictably.

## The fix, in pseudocode — a lock

```
lock = available

worker_A:
    repeat 1000 times:
        wait until lock is available, then take it
        read shared_number into temp
        temp = temp + 1
        write temp back to shared_number
        release the lock

worker_B:
    (same, with the lock)
```

Now, whichever worker grabs the lock first gets to do their full read-modify-write **uninterrupted**, and the other worker has to wait its turn. No lost updates. But notice the cost: _you_, the programmer, had to remember to add the lock around every single place that touches `shared_number`. Miss one spot anywhere in a large program, and the bug is back — silently.

## Why this matters for understanding channels

This pseudocode is the _problem_. Channels are one particular _solution_ to it — instead of two workers sharing one whiteboard and taking turns with a lock, you give each worker their own private whiteboard, and if they need to hand a number to the other worker, they physically pass a note through a mail slot (the channel). Nobody ever reads or writes the other's whiteboard directly, so there's nothing to race over in the first place — the "taking turns" happens automatically, built into the mail slot.

Does the lock example make it clear why "unprotected shared state" is the root problem, before we connect it back to how channels sidestep it entirely?

## 2. The go Keyword — Starting a Goroutine

### Syntax

Prefix any function call with `go`:

```go
go myFunction()
go func() {
    fmt.Println("started!")
}()
```

Both named functions and anonymous function literals work. The `go` keyword is an expression statement — it cannot appear inside an expression.

### What happens internally when you call `go f()`

1. The runtime allocates a new goroutine struct (the `G` in the scheduler)
2. It gives the goroutine a tiny stack (~4 KB)
3. It sets the goroutine's entry point to `f`
4. The goroutine is placed in the local run queue of the current P (processor)
5. Control returns to the caller immediately — the caller **does not wait** for `f` to start or finish

The new goroutine is **runnable** immediately. The scheduler picks it up at its next scheduling point — typically within microseconds.

### You cannot capture a goroutine's return value

```go
// WRONG — compilation error
result := go doWork() // syntax error: unexpected go, expecting expression

// RIGHT — use a channel
ch := make(chan int)
go func() {
    ch <- doWork()
}()
result := <-ch
```

The `go` keyword itself has no result. The goroutine executes the function, and any return value is silently discarded. If you need the result, you must communicate it back via a channel or shared memory protected by a mutex.

### Goroutines are not function calls

```go
// This is a synchronous function call — blocks until f returns
f()

// This starts f in a new goroutine — returns immediately
go f()
```

The difference is fundamental. The first runs `f` on the current goroutine; the second runs `f` on a new goroutine. Both `f()` and `go f()` execute the same function body — the difference is **when** and **where** they run.

### Named functions vs anonymous closures

```go
// Named function
func process(id int) { /* ... */ }
go process(42)

// Anonymous closure — capture variables from surrounding scope
go func() {
    fmt.Println(x) // x is captured from the enclosing scope
}()

// Anonymous closure with parameters — avoid capture bugs
go func(id int) {
    fmt.Println(id)
}(i)
```

---

## 3 Goroutines: Fundamentals

### 3.1 Goroutines vs OS Threads

| Aspect | Goroutine | OS Thread |
|---|---|---|
| **Stack size** | Starts at ~4 KB, grows/shrinks dynamically | Fixed at ~1 MB (or larger) |
| **Creation cost** | ~1-2 µs | ~10-100 µs |
| **Context switch** | User-space, ~10-100 ns | Kernel-space, ~1-10 µs |
| **Max count** | Millions per GB of RAM | Thousands per GB of RAM |
| **Scheduling** | Go runtime (user-space) | OS kernel |
| **Identity** | No ID, no handle | Has PID/TID, killable from outside |
| **Startup memory** | ~4 KB | ~1 MB + kernel bookkeeping |

```go
// 100,000 goroutines — perfectly viable
for i := 0; i < 100_000; i++ {
    go func(n int) {
        _ = n
    }(i)
}
fmt.Println(runtime.NumGoroutine()) // 100001 (including main)
```

Each OS thread reserves ~1 MB of virtual memory for its stack. 100,000 threads × 1 MB = ~100 GB before any code runs. Goroutines start at ~4 KB, so 100,000 goroutines × 4 KB = ~400 MB — and most of that never grows beyond the initial allocation.

The OS sees only a handful of threads (typically `GOMAXPROCS` threads running user code, plus a few for syscalls and GC). The Go runtime schedules thousands of goroutines onto those few threads.

---

### 3.2 Goroutine Scheduling — The M:N Scheduler

Go implements an **M:N scheduling** model: **M** goroutines are multiplexed onto **N** OS threads.

#### The G-M-P model

```
┌──────────┐   ┌──────────┐   ┌──────────┐
│  Goroutine│   │  Goroutine│   │  Goroutine│  ← Gs (user-level threads)
│  (G)      │   │  (G)      │   │  (G)      │
└─────┬─────┘   └─────┬─────┘   └─────┬─────┘
      │               │               │
      ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  Processor   │ │  Processor   │ │  Processor   │  ← Ps (logical CPUs)
│  (P)         │ │  (P)         │ │  (P)         │
│  run queue   │ │  run queue   │ │  run queue   │
└──────┬──────┘ └──────┬──────┘ └──────┬──────┘
       │               │               │
       ▼               ▼               ▼
┌────────────┐  ┌────────────┐  ┌────────────┐
│ Machine     │  │ Machine     │  │ Machine     │  ← Ms (OS threads)
│ (M)         │  │ (M)         │  │ (M)         │
└────────────┘  └────────────┘  └────────────┘
```

- **G (Goroutine)** — represents a goroutine. Contains the stack, instruction pointer, and state needed to resume execution.
- **M (Machine)** — an OS thread. Executes Go code by picking up a G and running it.
- **P (Processor)** — a resource that makes an M capable of running Go code. Each P has a local run queue of Gs. `GOMAXPROCS` controls the number of Ps.

**Rule:** An M can only run Go code if it holds a P. Without a P, the M blocks in the kernel or spins waiting.

#### How scheduling works

```
1. go f() creates a G → placed in current P's local run queue
2. When an M is free:
   a. M picks a G from its P's local queue
   b. If empty, it steals Gs from another P's queue (work stealing)
   c. If all queues empty, M spins or parks
3. M executes G until G blocks or is preempted
4. When G blocks (I/O, channel, mutex):
   a. G moves to waiting state
   b. M picks another G and runs it
5. When G unblocks → placed back in a run queue
```

#### Work stealing

When a P's local queue is empty, it becomes a **thief** — it picks another P at random and steals ~half its goroutines. This balances load without a central queue bottleneck.

```
P1 queue: [G1, G2, G3, G4, G5, G6]
P2 queue: []  ← empty!

P2 steals from P1:
P1 queue: [G1, G2, G3]
P2 queue: [G4, G5, G6]
```

#### Cooperative preemption

Pre-Go 1.14, a goroutine in a tight loop could **starve** all others on the same P:

```go
go func() {
    for {
        // no function calls, no I/O, no channel ops — runs forever
    }
}()
```

	Go 1.14+ uses **asynchronous preemption** — the runtime sends a signal (SIGURG) to interrupt long-running goroutines even if they never yield. Very tight loops (ns/iteration) can still delay scheduling briefly.

#### GOMAXPROCS

```go
runtime.GOMAXPROCS(0) // get current value (typically # of CPU cores)
runtime.GOMAXPROCS(8) // set to 8
```

Controls the number of OS threads executing user-level Go code simultaneously. Defaults to CPU core count.

- `GOMAXPROCS = 1` → concurrent but not parallel (interleaved on one thread)
- `GOMAXPROCS = N` → up to N goroutines run **in parallel**

> [!tip] The default is optimal for most apps. Lower = less parallelism for CPU-bound work. Higher than core count rarely helps and can hurt due to thread contention. IO-bound workloads sometimes benefit from a higher value.

#### Goroutine states

```
   ┌──────────┐
   │  Runnable │ ← ready to execute, waiting for an M
   └─────┬────┘
         │
   ┌─────▼──────┐
   │  Running    │ ← currently executing on an M
   └─────┬──────┘
         │
   ┌─────▼──────┐
   │  Waiting    │ ← blocked (channel, mutex, I/O, sleep)
   └────────────┘
         │
   ┌─────▼──────┐
   │  Dead       │ ← finished execution, will be cleaned up
   └────────────┘
```

---

### 3.3 Goroutine Stack — Starts Small, Grows Dynamically

Each goroutine starts with ~4 KB of stack, growing and shrinking as needed — unlike OS threads with a fixed 1 MB+ stack.

#### Growth mechanism

When the stack is too small, the runtime does a **stack copy**:

1. Allocate a new stack (typically 2× current size)
2. Copy all data from old stack to new
3. Update all pointers on the stack (compiler emits metadata — **stack maps**)
4. Free the old stack

```go
func deepRecursion(n int) {
    if n == 0 {
        return
    }
    var buf [1024]byte // each frame uses ~1 KB
    deepRecursion(n - 1)
}

go deepRecursion(100)
// Stack starts at 4 KB
// After ~4 frames → copy to 8 KB
// After ~12 frames → copy to 16 KB
// After ~28 frames → copy to 32 KB
```

#### Stack shrinking

After a deep call returns to shallow depth, the runtime may **shrink** the stack to free memory. This makes goroutines memory-efficient for bursty workloads.

#### Stack overflow

Infinite recursion eventually hits the ~1 GB limit on 64-bit systems:

```go
func infiniteRecursion() {
    infiniteRecursion()
    // runtime: goroutine stack exceeds 1000000000-byte limit
}
```

---

### 3.4 Goroutine Lifecycle

#### The main goroutine

When `main()` starts, it runs as a single goroutine — the **main goroutine**. All others are descendants.

```go
func main() {
    go func() {
        time.Sleep(1 * time.Second)
        fmt.Println("never prints")
    }()
    // main returns — program exits, all goroutines die
}
```

**When `main()` returns, the process terminates immediately.** All goroutines are killed without warning. Defers in other goroutines do not run. Resources are not released.

#### Preventing premature exit

Use `sync.WaitGroup` to wait for goroutines:

```go
var wg sync.WaitGroup
wg.Add(1)
go func() {
    defer wg.Done()
    doWork()
}()
wg.Wait() // blocks until Done is called
```

> [!warning] `wg.Add` must be called **before** the goroutine starts, not inside it. See [[15 - Sync Primitives]] for full `WaitGroup` coverage.

#### A goroutine's natural end

A goroutine exits when the function it was running returns (or panics without recovery):

```go
go func() {
    fmt.Println("I run")
    // implicit return → goroutine exits
}()
```

You cannot restart a goroutine. Once it exits, it's gone. Spawn a new one if needed.

#### runtime.Goexit()

```go
func worker() {
    defer fmt.Println("cleanup still runs!")
    runtime.Goexit()    // exit the goroutine
    fmt.Println("never prints")
}

go worker()
```

`runtime.Goexit()` terminates the calling goroutine **after** running all deferred functions. Unlike panic, defers run normally, and the function exits after the defer chain completes.

---

## 4 Goroutines: Safety & Leaks

### 4.1 Closures and the Loop Capture Bug

When a goroutine closure captures a loop variable, it captures the **variable itself** (the memory location), not the value at the time the goroutine was created.

#### Pre-Go 1.22: the bug

```go
// WRONG — all goroutines likely print the final value of i
for i := 1; i <= 3; i++ {
    go func() {
        fmt.Println(i) // captures variable i, not its value
    }()
}
// Typical output (pre-1.22): 3, 3, 3
```

Pre-Go 1.22, the loop variable is a single memory location reassigned each iteration. The closure holds a reference to that location. By the time the goroutine runs, the variable is at its final value.

#### Pre-Go 1.22: the fix

```go
for i := 1; i <= 3; i++ {
    i := i // shadow — creates a new variable per iteration
    go func() {
        fmt.Println(i) // each goroutine captures its own i
    }()
}
```

Or pass the value as a parameter:

```go
for i := 1; i <= 3; i++ {
    go func(id int) {
        fmt.Println(id) // id is a copy
    }(i)
}
```

#### Range variant

```go
items := []string{"a", "b", "c"}

// WRONG — all goroutines print "c" (pre-1.22)
for _, item := range items {
    go func() {
        fmt.Println(item)
    }()
}

// FIX
for _, item := range items {
    item := item
    go func() {
        fmt.Println(item)
    }()
}
```

#### Go 1.22+ behavior

Since Go 1.22, each loop iteration creates a new variable — the bug is fixed:

```go
// Go 1.22+ — safe, each iteration gets a new i
for i := range 3 {
    go func() {
        fmt.Println(i) // prints 0, 1, 2
    }()
}
```

The `i := i` idiom is harmless in 1.22+ and makes code safe to backport. Many teams keep it as a defensive habit.

> [!tip] This applies to all closures, not just goroutines — deferred functions, callbacks, and stored `func()` values all exhibit the same capture behavior.

---

### 4.2 Data Races and the Race Detector

A **data race** occurs when two or more goroutines access the same memory concurrently, and at least one access is a write.

#### The canonical example

```go
var counter int

func main() {
    for i := 0; i < 1000; i++ {
        go func() {
            counter++ // race: read-modify-write without synchronization
        }()
    }
    time.Sleep(time.Second)
    fmt.Println(counter) // ??? — might be 897, 942, 1000, anything
}
```

`counter++` compiles to three operations:
```
LOAD  counter → register
INC   register
STORE register → counter
```

Two goroutines can interleave:
```
Goroutine A: LOAD counter (0) → INC → STORE (1)
Goroutine B:                    LOAD counter (0) → INC → STORE (1)
Result: counter = 1, but expected 2!
```

```go
// Read-write race
var x int
go func() { fmt.Println(x) }() // read
go func() { x = 42 }()         // write — race!

// Concurrent map access — panics, not just wrong
m := make(map[int]int)
go func() { m[1] = 1 }() // write
go func() { _ = m[1] }() // read → fatal error: concurrent map read and map write
```

#### The race detector

```bash
go run -race main.go
go build -race ./...
go test -race ./...
```

When it detects a race, it prints a detailed report:

```
$ go run -race racy.go
==================
WARNING: DATA RACE
Read at 0x00c0000a0008 by goroutine 7:
  main.main.func1()
      racy.go:12 +0x3a

Previous write at 0x00c0000a0008 by goroutine 6:
  main.main.func1()
      racy.go:12 +0x50

Goroutine 7 (running) created at:
  main.main()
      racy.go:11 +0x44

Goroutine 6 (finished) created at:
  main.main()
      racy.go:11 +0x44
==================
```

The report tells you: the operation (read/write), the line, which goroutines were involved, and where each was created.

#### Limitations

- **Dynamic analysis** — only finds races that actually occur during execution. Untested code paths may hide races.
- **~5-10× slowdown**, ~2-5× memory overhead. Use during development, not in production.
- A clean race run means "no races in this specific execution" — not "no races, period." Run tests many times under load.

> [!warning] Always test with `-race` before committing:
> ```bash
> go test -race -count=1 ./...
> ```

---

### 4.3 Goroutine Panics

#### A panic in any goroutine crashes the entire program

```go
func main() {
    go func() {
        panic("boom!") // this kills the whole process
    }()
    time.Sleep(time.Second)
    fmt.Println("will this print?")
}
// panic: boom!
// exit status 2
```

Panics are **not** per-goroutine. An unrecovered panic in any goroutine terminates the entire program. There is no "catch" in the parent goroutine.

#### Recover only works inside the panicking goroutine

```go
// RIGHT — recover in the same goroutine that panics
go func() {
    defer func() {
        if r := recover(); r != nil {
            fmt.Println("recovered:", r)
        }
    }()
    panic("boom!")
}()

// WRONG — recover in main does NOT catch panics from other goroutines
defer func() {
    if r := recover(); r != nil {
        fmt.Println("this never runs for goroutine panics")
    }
}()
go func() {
    panic("boom!") // still crashes the program
}()
```

#### Always recover in goroutines that can panic

```go
go func() {
    defer func() {
        if r := recover(); r != nil {
            log.Printf("goroutine panicked: %v", r)
        }
    }()
    doRiskyWork()
}()
```

Essential for long-running goroutines (HTTP handlers, workers) — a single panic should not take down the entire server.

---

### 4.4 Goroutine Leaks

A **goroutine leak** is a goroutine that never exits. It sits in memory forever, holding stack, heap references, and resources.

#### Common causes

**1. Blocked on an unbuffered channel send with no receiver**

```go
func leak() {
    ch := make(chan int) // unbuffered
    go func() {
        ch <- 42 // blocks forever — no one receives
    }()
}
```

**2. Blocked on a channel receive with no sender**

```go
func leak() {
    ch := make(chan int)
    go func() {
        <-ch // blocks forever — no one sends
    }()
}
```

**3. Writer goroutine outlives the reader**

```go
func process(items []string) {
    ch := make(chan Result)
    for _, item := range items {
        go func(s string) {
            ch <- processItem(s) // blocks if nobody reads
        }(item)
    }
    result := <-ch      // read only first result, then return
    // remaining goroutines leak — blocked sending
}
```

**4. Infinite loop without a stop condition**

```go
go func() {
    for {
        doWork() // never returns, no stop signal
    }
}()
```

#### How to prevent leaks

**1. Context-based cancellation**

```go
ctx, cancel := context.WithCancel(context.Background())
go func() {
    for {
        select {
        case <-ctx.Done():
            return // cancelled
        default:
            doWork()
        }
    }
}()
cancel() // signal cancellation
```

**2. Done channel pattern**

```go
done := make(chan struct{})
go func() {
    for {
        select {
        case <-done:
            return
        default:
            doWork()
        }
    }
}()
close(done) // all goroutines reading done will unblock
```

**3. Buffered channels when send count is known**

```go
results := make(chan Result, len(items))
for _, item := range items {
    go func(s string) {
        results <- processItem(s) // won't block — enough buffer
    }(item)
}
for i := 0; i < len(items); i++ {
    result := <-results // read all
}
```

**4. `select` with timeout**

```go
ch := make(chan int)
go func() {
    select {
    case ch <- result:
    case <-time.After(5 * time.Second):
        fmt.Println("timeout — nobody received")
    }
}()
```

#### Detecting leaks

```go
func TestNoLeak(t *testing.T) {
    before := runtime.NumGoroutine()
    doWork()
    time.Sleep(100 * time.Millisecond)
    after := runtime.NumGoroutine()
    if after > before {
        t.Errorf("goroutine leak: %d → %d", before, after)
    }
}
```

Expose `runtime.NumGoroutine()` via a metrics endpoint in production. A steadily growing count is a red flag.

> [!warning] Every goroutine needs a way to stop. Always have a cancellation path — context, done channel, or timeout.

---

## 5 Goroutines: Patterns & Reference

### 5.1 Goroutine Patterns

#### Pattern 1 — Fire and Forget

Launch a goroutine without waiting for its result. The goroutine handles its own errors.

```go
go func() {
    if err := sendWelcomeEmail(user); err != nil {
        log.Printf("failed to send welcome email: %v", err)
    }
}()
// main continues immediately
```

**Use when:** the caller doesn't need the result. **Risk:** the goroutine can leak if it blocks.

#### Pattern 2 — Fan-Out (N goroutines, N results)

Process N items with N goroutines, collect all results:

```go
func fanOut(items []int) []int {
    n := len(items)
    results := make(chan int, n)
    var wg sync.WaitGroup

    for _, item := range items {
        wg.Add(1)
        go func(val int) {
            defer wg.Done()
            results <- process(val)
        }(item)
    }

    wg.Wait()
    close(results)

    var out []int
    for r := range results {
        out = append(out, r)
    }
    return out
}
```

**Use when:** items are independent, all results needed, max concurrency desired.

#### Pattern 3 — Worker Pool (limited concurrency)

Limit concurrent goroutines to control resource usage:

```go
func workerPool(jobs []Job, numWorkers int) []Result {
    jobCh := make(chan Job, len(jobs))
    resultCh := make(chan Result, len(jobs))
    var wg sync.WaitGroup

    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            for job := range jobCh {
                resultCh <- process(job)
            }
        }(i)
    }

    for _, job := range jobs {
        jobCh <- job
    }
    close(jobCh)

    wg.Wait()
    close(resultCh)

    var results []Result
    for r := range resultCh {
        results = append(results, r)
    }
    return results
}
```

**Pool size:** CPU-bound → `runtime.GOMAXPROCS(0)`. IO-bound → experiment, typically 10-100× CPU count.

**Use when:** many items but want to limit concurrency (avoid overwhelming a DB, API, or filesystem).

#### Pattern 4 — Pipeline (stages connected by channels)

```go
func generate(nums ...int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for _, n := range nums {
            out <- n
        }
    }()
    return out
}

func square(in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for n := range in {
            out <- n * n
        }
    }()
    return out
}

func main() {
    // Pipeline: generate → square → print
    for result := range square(generate(1, 2, 3, 4)) {
        fmt.Println(result) // 1, 4, 9, 16
    }
}
```

**Use when:** processing flows through clear stages that can run concurrently.

#### Pattern 5 — Goroutine with timeout

```go
func fetchWithTimeout(url string, timeout time.Duration) ([]byte, error) {
    result := make(chan []byte, 1)
    errCh := make(chan error, 1)

    go func() {
        data, err := httpFetch(url)
        if err != nil {
            errCh <- err
            return
        }
        result <- data
    }()

    select {
    case data := <-result:
        return data, nil
    case err := <-errCh:
        return nil, err
    case <-time.After(timeout):
        return nil, fmt.Errorf("timeout fetching %s", url)
    }
}
```

---

### 5.2 The select Statement

`select` lets a goroutine wait on **multiple channel operations at once** — it blocks until one of them can proceed.

```go
select {
case msg := <-ch1:
    fmt.Println("got from ch1:", msg)
case msg := <-ch2:
    fmt.Println("got from ch2:", msg)
}
```

Whichever channel has data ready first wins, that case runs, `select` exits. If both are ready, it picks randomly.

#### Non-blocking send/receive with default

```go
select {
case ch <- value:
    fmt.Println("sent")
default:
    fmt.Println("nobody receiving, skipped")
}
```

The `default` case fires immediately if no other case can proceed — no blocking.

#### Timeout

```go
select {
case result := <-ch:
    fmt.Println(result)
case <-time.After(2 * time.Second):
    fmt.Println("timeout")
}
```

If `ch` doesn't deliver within 2 seconds, the timeout case fires. The goroutine doesn't leak — it moves on.

#### Done channel — graceful shutdown

```go
for {
    select {
    case job := <-jobCh:
        process(job)
    case <-done:
        return
    }
}
```

This goroutine processes jobs until someone closes `done`. Without `select`, you'd be stuck on `<-jobCh` with no way to shut down.

#### Empty select blocks forever

```go
select {} // blocks forever — useful in toy programs to keep main alive
```

#### Rules

- `select` picks one ready case at random if multiple are ready
- If no case is ready, it blocks (unless there's a `default`)
- A `nil` channel in a `select` case is never ready — the case is ignored
- `close()` on a channel makes receives from it unblock immediately (zero value + ok=false)

---

### 5.3 Goroutines Are Not Coroutines

| Aspect | Goroutine | Coroutine |
|---|---|---|
| **Scheduling** | Preemptively scheduled by Go runtime | Explicitly yielded by programmer |
| **Stack** | Has its own stack (grows dynamically) | Usually stackless |
| **Concurrency** | Can run in parallel (GOMAXPROCS > 1) | Single-threaded cooperative |
| **Yield points** | Blocking calls (I/O, channels, signals) | Explicit `yield` or `await` |
| **Relationship** | Not hierarchical (no parent-child) | Often hierarchical (caller awaits callee) |
| **Identity** | No identity, no handle | Has identity (e.g., Lua coroutine handle) |
| **Resume** | Automatically by scheduler | Manually by caller |

```go
// Goroutine — start it and forget it
go func() {
    data := <-ch       // runtime yields here if no data
    result := process(data)
    ch2 <- result      // runtime yields here until receiver ready
}()
// Scheduler decides when to run/resume

// Coroutine (conceptual — Lua/Python style)
co = create_coroutine(func() {
    data = receive(ch) // yields explicitly
    result = process(data)
    send(ch2, result)  // yields explicitly
})
resume(co) // I decide when to resume
```

Goroutines let you write **sequential code** that is automatically concurrent. You don't mark yield points; the runtime finds them.

> [!info] Goroutines are closer to **green threads** (lightweight, preemptively scheduled, independent stacks) than to **coroutines** (cooperative, stackless, hierarchical). The name "goroutine" was chosen deliberately to avoid this confusion.

---

### 5.4 Debugging Goroutines

#### Goroutine dump via SIGQUIT

```bash
kill -QUIT <pid>
```

Prints a stack trace of **all goroutines** and exits. Invaluable for deadlocks and leaks.

```
goroutine 1 [running]:
main.main()
    /home/user/main.go:10 +0x39

goroutine 5 [chan receive]:
main.worker()
    /home/user/main.go:22 +0x4f
created by main.main in goroutine 1
    /home/user/main.go:15 +0x3a
```

#### Programmatic stack dump

```go
import "runtime/pprof"

buf := make([]byte, 64*1024)
n := runtime.Stack(buf, true) // true = all goroutines
fmt.Println(string(buf[:n]))
```

#### runtime.NumGoroutine()

```go
fmt.Println("number of goroutines:", runtime.NumGoroutine())
```

Use in health checks to detect leaks.

#### pprof

```go
import (
    "net/http"
    _ "net/http/pprof"
)

go func() {
    log.Println(http.ListenAndServe("localhost:6060", nil))
}()
```

Visit `http://localhost:6060/debug/pprof/goroutine` to see all goroutines with stack traces.

#### GOTRACEBACK

```bash
GOTRACEBACK=none    # just panic message
GOTRACEBACK=single  # stack of crashing goroutine only (default)
GOTRACEBACK=all     # stacks of all goroutines
GOTRACEBACK=system  # all goroutines + runtime frames
GOTRACEBACK=crash   # same as system + SIGABRT (coredump)
```

---

### 5.5 Goroutines and the net/http Server

The `net/http` server runs **each HTTP request in its own goroutine**:

```go
func main() {
    http.HandleFunc("/", handler)
    log.Fatal(http.ListenAndServe(":8080", nil))
}

func handler(w http.ResponseWriter, r *http.Request) {
    // This runs in a NEW goroutine for each request
    fmt.Fprintf(w, "Hello!")
}
```

Multiple requests are handled **concurrently** without writing any `go` statements. If one handler blocks, others are unaffected.

#### The implication for shared state

```go
var counter int // shared — not protected!

func handler(w http.ResponseWriter, r *http.Request) {
    counter++ // DATA RACE — multiple goroutines modify this concurrently
    fmt.Fprintf(w, "Request #%d", counter)
}
```

Always protect shared state in HTTP handlers with mutexes. See [[15 - Sync Primitives]].

---

### 5.6 Quick Reference Cheatsheet

```go
// ── Starting a goroutine ───────────────────────────
go myFunction()
go func() { fmt.Println("hi") }()

// ── Loop capture bug fix (pre-Go 1.22) ────────────
for i := 0; i < 3; i++ {
    i := i // shadow
    go func() { fmt.Println(i) }()
}

// ── Pass parameter instead of capture ────────────
for i := 0; i < 3; i++ {
    go func(id int) { fmt.Println(id) }(i)
}

// ── GOMAXPROCS ─────────────────────────────────────
runtime.GOMAXPROCS(0)  // get
runtime.GOMAXPROCS(8)  // set (rarely needed)

// ── Runtime checks ────────────────────────────────
runtime.NumGoroutine() // count
runtime.Gosched()      // yield
runtime.Goexit()       // exit current goroutine (defers run)

// ── Recover from goroutine panic ──────────────────
go func() {
    defer func() {
        if r := recover(); r != nil {
            log.Printf("recovered: %v", r)
        }
    }()
    riskyWork()
}()

// ── Goroutine leak prevention: done channel ───────
done := make(chan struct{})
go func() {
    for {
        select {
        case <-done:
            return
        default:
            doWork()
        }
    }
}()
close(done)

// ── Goroutine dump ─────────────────────────────────
// kill -QUIT <pid>
// OR:
pprof.Lookup("goroutine").WriteTo(os.Stdout, 1)

// ── GOTRACEBACK ────────────────────────────────────
// GOTRACEBACK=all ./myapp  → stacks of all goroutines on crash

// ── Rules ──────────────────────────────────────────
// ✅ Every goroutine needs a way to stop
// ✅ Always use -race during development
// ✅ Never let main() exit while goroutines run
// ✅ Protect all shared mutable data
// ❌ Never access a map concurrently without sync
// ❌ Never use panic for expected errors
// ❌ Never assume goroutines finish before main exits
// ❌ Never ignore the race detector output
```

---

_Previous: [[11 - Error Handling]] · Next: [[13 - Channels]]_