# Go — Goroutines

> **Series:** Go Language Fundamentals **Tags:** #go #golang #goroutines #concurrency #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. What is a Goroutine?]]
- [[#2. The go Keyword — Starting a Goroutine]]
- [[#3. Goroutines vs OS Threads]]
- [[#4. Goroutine Scheduling — The M:N Scheduler]]
- [[#5. Goroutine Stack — Starts Small, Grows Dynamically]]
- [[#6. Goroutine Lifecycle]]
- [[#7. sync.WaitGroup — Waiting for Goroutines]]
- [[#8. Closures and the Loop Capture Bug]]
- [[#9. Data Races — What They Are and How to Detect Them]]
- [[#10. sync.Mutex — Protecting Shared Resources]]
- [[#11. sync.RWMutex — Read-Heavy Workloads]]
- [[#12. Safely Sharing Maps, Slices, and Other Data]]
- [[#13. sync/atomic — Lock-Free Operations for Simple Cases]]
- [[#14. sync.Once — One-Time Initialization]]
- [[#15. Goroutine Panics — What Happens and How to Handle Them]]
- [[#16. Goroutine Leaks — How They Happen and How to Prevent Them]]
- [[#17. Goroutine Patterns]]
- [[#18. Goroutines Are Not Coroutines]]
- [[#19. Debugging Goroutines]]
- [[#20. Goroutines and the net/http Server]]
- [[#21. Quick Reference Cheatsheet]]

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

### Key characteristics

- **Lightweight** — a running goroutine costs ~4 KB of stack space (grows as needed). You can have hundreds of thousands in one process.
- **Independently scheduled** — the Go runtime decides which goroutine runs on which OS thread and for how long. You don't control the schedule.
- **Concurrent by default, parallel when possible** — goroutines interleave on a single core; with `GOMAXPROCS > 1`, they run simultaneously.
- **No identity, no handle** — you cannot kill a goroutine from the outside. You cannot ask "what goroutine am I?" (there is no `goroutine.ID()`). You can only coordinate with it via channels, mutexes, or `sync` primitives.
- **Cooperates with the scheduler at blocking calls** — goroutines automatically yield at I/O, channel operations, `time.Sleep`, mutex locks, and `select` statements.

---

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

## 3. Goroutines vs OS Threads

| Aspect | Goroutine | OS Thread |
|---|---|---|
| **Stack size** | Starts at ~4 KB, grows/shrinks dynamically | Fixed at ~1 MB (or larger) |
| **Creation cost** | ~1-2 μs | ~10-100 μs |
| **Context switch** | User-space, ~10-100 ns | Kernel-space, ~1-10 μs |
| **Max count** | Millions per GB of RAM | Thousands per GB of RAM |
| **Scheduling** | Go runtime (user-space) | OS kernel |
| **Identity** | No ID, no handle | Has PID/TID, killable from outside |
| **Startup memory** | ~4 KB | ~1 MB + kernel bookkeeping |

### What this means in practice

```go
// 100,000 goroutines — perfectly viable
for i := 0; i < 100_000; i++ {
    go func(n int) {
        _ = n
    }(i)
}
fmt.Println(runtime.NumGoroutine()) // 100001 (including main)

// 100,000 OS threads — would crash most machines
```

Each OS thread reserves ~1 MB of virtual memory for its stack. 100,000 threads × 1 MB = ~100 GB before any code runs. Goroutines start at ~4 KB, so 100,000 goroutines × 4 KB = ~400 MB — and most of that never grows beyond the initial allocation.

### Goroutines are multiplexed onto threads

The operating system sees only a handful of threads (typically `GOMAXPROCS` threads running user code, plus a few for syscalls and the garbage collector). The Go runtime schedules thousands of goroutines onto those few threads. From the OS's perspective, the program behaves like a small-threaded application — even if the Go program spawns millions of goroutines.

---

## 4. Goroutine Scheduling — The M:N Scheduler

Go implements an **M:N scheduling** model: **M** goroutines are multiplexed onto **N** OS threads.

### The G-M-P model

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

Three abstractions work together:

- **G (Goroutine)** — represents a goroutine. Contains the stack, instruction pointer, and other state needed to resume execution. This is what your code runs on.
- **M (Machine)** — an OS thread. The M executes Go code by picking up a G and running it. M's are created and destroyed by the runtime as needed.
- **P (Processor)** — a resource that makes an M capable of running Go code. Each P has a local run queue of Gs. `GOMAXPROCS` controls the number of Ps.

### The rule: An M can only run Go code if it holds a P

If an M does not have a P, it cannot execute goroutines — it blocks in the kernel (e.g., during a syscall) or spins waiting for a P.

### How goroutines are scheduled step by step

```
1. A goroutine is created (go f())
2. It is placed in the current P's local run queue
3. When an M becomes available (or the current goroutine blocks):
   a. The M picks a G from its P's local run queue
   b. If the local queue is empty, it steals Gs from another P's queue (work stealing)
   c. If all queues are empty, the M spins or parks
4. The M executes the G until the G blocks or is preempted
5. When the G blocks (I/O, channel, mutex):
   a. The G is moved to a waiting state
   b. The M picks another G from the queue and runs it
6. When the G unblocks, it is placed back in a run queue
```

### Work stealing

When a P's local run queue is empty, it becomes a **thief** — it picks another P at random and steals approximately half of its goroutines. This ensures load is balanced across all processors without a central queue bottleneck.

```go
// Visual of work stealing:
// P1 queue: [G1, G2, G3, G4, G5, G6]
// P2 queue: []  ← empty!

// P2 steals from P1:
// P1 queue: [G1, G2, G3]
// P2 queue: [G4, G5, G6]
```

This is one reason Go scales well on multicore machines — no single lock protects the global run queue (there is one, but it's rarely used).

### Cooperative preemption

Before Go 1.14, a goroutine in a tight loop could **starve** all other goroutines on the same P — it never yielded, so the scheduler never ran another goroutine.

```go
// PRE-Go 1.14: this goroutine could run forever, starving others
go func() {
    for {
        // no function calls, no I/O, no channel operations
    }
}()

// Go 1.14+: the runtime sends a signal (SIGURG) to preempt tight loops
// The goroutine is eventually interrupted and another is scheduled
```

Go 1.14 introduced **asynchronous preemption** — the runtime uses OS signals to interrupt long-running goroutines even if they never yield. This means tight loops no longer block the scheduler indefinitely. However, very tight loops (nanoseconds per iteration) can still delay scheduling briefly.

### Explicit yielding

```go
import "runtime"

// Explicitly yield the processor — let other goroutines run
runtime.Gosched()
```

`runtime.Gosched()` yields the current goroutine's remaining time slice. The goroutine is placed at the back of the run queue. Use it sparingly — in most code, blocking calls handle yielding naturally.

### GOMAXPROCS

```go
import "runtime"

fmt.Println(runtime.GOMAXPROCS(0)) // current value (typically # of CPU cores)
runtime.GOMAXPROCS(8)              // set to 8
```

`GOMAXPROCS` sets the maximum number of OS threads that can execute user-level Go code simultaneously. It defaults to the number of CPU cores.

- `GOMAXPROCS = 1` → **concurrent but not parallel** — goroutines interleave on one thread
- `GOMAXPROCS = N` → up to N goroutines can run **in parallel**

```go
// Set via environment variable
// GOMAXPROCS=4 go run main.go

// Or in code (not recommended after init — affects global scheduler)
runtime.GOMAXPROCS(2) // limit to 2 parallel threads
```

> [!tip] In most applications, the default is optimal. Lowering GOMAXPROCS can reduce parallelism for CPU-bound work. Raising it above the core count rarely helps and can hurt due to thread contention. The exception: IO-bound workloads sometimes benefit from a higher value because goroutines block on I/O frequently and the extra threads fill in while others wait.

### sysmon — the system monitor

The Go runtime runs a special goroutine called **sysmon** (system monitor). It does not need a P to run. sysmon's responsibilities:

- Preempt long-running goroutines (the signal-based preemption)
- Detect blocked network I/O and unblock goroutines
- Detect deadlocks (if no goroutines can make progress)
- Force the garbage collector to run after a certain interval

### Goroutine states

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

A goroutine cycles through these states. The scheduler moves goroutines between Runnable and Running. Blocking operations move them to Waiting, and completion of the blocking operation moves them back to Runnable.

---

## 5. Goroutine Stack — Starts Small, Grows Dynamically

Each goroutine starts with a **tiny stack** (~4 KB) that grows and shrinks as needed — unlike OS threads, which have a fixed 1 MB+ stack that is mostly wasted.

### Growth mechanism

When a goroutine's stack is too small, the runtime triggers a **stack copy**:

1. Allocate a new, larger stack (typically 2× the current size)
2. Copy all existing data from the old stack to the new one
3. Update all pointers on the stack (the compiler emits metadata to make this possible — known as **stack maps**)
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
// After ~4 frames, the stack is full → copy to 8 KB
// After ~12 frames → copy to 16 KB
// After ~28 frames → copy to 32 KB
// ... and so on
```

### Stack shrinking

When a goroutine finishes a deep call and returns to a shallow call depth, the runtime may **shrink** the stack to free memory. This is why goroutines are memory-efficient for bursty workloads.

### What happens if the stack can't grow

The stack is not infinite. If a goroutine's stack keeps growing (e.g., infinite recursion or a very large allocation on the stack), it will eventually exhaust the available address space and crash:

```go
func infiniteRecursion() {
    infiniteRecursion() // stack grows until... runtime: goroutine stack exceeds 1000000000-byte limit
}
```

The limit is ~1 GB per goroutine on 64-bit systems — far beyond any reasonable use. The runtime prints a stack trace and exits the program when this limit is reached.

### Why dynamic stacks matter

Without them, you'd have to choose between:
- **Big stacks** (OS thread model) — wasting memory for the common case
- **Manual stack management** — like C with `getcontext`/`makecontext`, error-prone and slow

Go's dynamic stacks give you the safety of big stacks with the efficiency of small ones.

---

## 6. Goroutine Lifecycle

### The main goroutine

When your program starts, it runs as a single goroutine — the **main goroutine** (the one executing `main()`). All other goroutines are descendants.

### Main exits = program exits

```go
func main() {
    go func() {
        time.Sleep(1 * time.Second)
        fmt.Println("never prints")
    }()
    // main returns immediately — the program exits, killing all goroutines
}
```

When `main()` returns, the Go runtime terminates the process immediately — all goroutines are killed without warning. This is **not** a clean shutdown; defers in other goroutines do not run, and resources are not released.

### Three ways to prevent premature program exit

#### 1. WaitGroup (preferred for fire-and-forget work)

```go
var wg sync.WaitGroup
wg.Add(1)
go func() {
    defer wg.Done()
    doWork()
}()
wg.Wait() // blocks until Done is called
```

#### 2. Channel receive (for signaling)

```go
done := make(chan bool)
go func() {
    doWork()
    done <- true
}()
<-done // blocks until a value is sent
```

#### 3. Select + multiple goroutines

```go
done := make(chan bool, 1)
go func() { doWork(1); done <- true }()
go func() { doWork(2); done <- true }()

// Wait for both
<-done
<-done
```

### A goroutine's natural end

A goroutine exits when the function it was running returns (or panics without recovery):

```go
go func() {
    fmt.Println("I run")
    // implicit return at the end → goroutine exits
}()
```

### Can you restart a goroutine?

No. Once a goroutine exits, it's gone. If you need it again, you spawn a new one. There is no `join`, `restart`, or `resume` — goroutines are not coroutines.

### runtime.Goexit()

A goroutine can exit itself by calling `runtime.Goexit()`:

```go
func worker() {
    defer fmt.Println("cleanup still runs!")
    runtime.Goexit()    // exit the goroutine
    fmt.Println("never prints") // unreachable
}

go worker()
```

`runtime.Goexit()` terminates the calling goroutine **after** running all deferred functions. This is different from a panic — defers run normally, but the function exits immediately after the defer chain completes.

---

## 7. sync.WaitGroup — Waiting for Goroutines

`sync.WaitGroup` is a counter-based synchronisation primitive. It blocks the calling goroutine until an internal counter reaches zero. It is the most common way to wait for a group of goroutines to finish.

### The three methods

```go
var wg sync.WaitGroup

wg.Add(delta int)  // increment the counter (usually 1)
wg.Done()           // decrement the counter by 1
wg.Wait()           // block until the counter reaches 0
```

### Basic usage

```go
func main() {
    var wg sync.WaitGroup

    for i := 1; i <= 5; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            fmt.Println("worker", id, "started")
            time.Sleep(time.Duration(id) * 100 * time.Millisecond)
            fmt.Println("worker", id, "done")
        }(i)
    }

    wg.Wait()
    fmt.Println("all workers finished")
}
```

### The Add before go rule

`Add` must be called **before** the goroutine starts, not inside it:

```go
// WRONG — race: wg.Wait() may run before Add is called
for i := 0; i < 5; i++ {
    go func() {
        wg.Add(1)          // too late! Wait might already be running
        defer wg.Done()
        // ...
    }()
}
wg.Wait() // might return immediately with counter = 0

// RIGHT ───────────────
for i := 0; i < 5; i++ {
    wg.Add(1) // counter is incremented BEFORE the goroutine starts
    go func() {
        defer wg.Done()
        // ...
    }()
}
wg.Wait()
```

### Add with a known total

```go
numJobs := 20
wg.Add(numJobs) // add all at once
for i := 0; i < numJobs; i++ {
    go func(id int) {
        defer wg.Done()
        process(id)
    }(i)
}
wg.Wait()
```

This is slightly more efficient than calling `Add(1)` inside the loop (one atomic operation instead of 20 counter adjustments).

### Negative counter panics

```go
wg.Add(1)
wg.Done()
wg.Done() // panic: sync: negative WaitGroup counter
```

Calling `Done` (or `Add` with a negative delta) more times than the counter allows causes a runtime panic. The counter must never go below zero.

### WaitGroup is not for reuse with different counter patterns

Once `Wait` returns and the counter is back to zero, the WaitGroup can be reused:

```go
var wg sync.WaitGroup

for _, batch := range batches {
    for _, item := range batch {
        wg.Add(1)
        go func(it Item) {
            defer wg.Done()
            process(it)
        }(item)
    }
    wg.Wait() // wait for this batch before starting the next
}
```

But be careful — all `Add` calls must be done before `Wait` begins. Calling `Add` while `Wait` is already running is a data race.

### Never copy a WaitGroup

```go
// WRONG — copying copies the internal state (counter, semaphore)
func processItems(items []string, wg sync.WaitGroup) { // copy!
    for _, item := range items {
        wg.Add(1)
        go func(s string) {
            defer wg.Done()
            // ...
        }(item)
    }
}
// The original wg in the caller NEVER sees these Done calls!

// RIGHT — pass by pointer
func processItems(items []string, wg *sync.WaitGroup) {
    for _, item := range items {
        wg.Add(1)
        go func(s string) {
            defer wg.Done()
            // ...
        }(item)
    }
}
```

> [!warning] `sync.WaitGroup` (and all `sync` types) must never be copied — pass them by pointer. If you embed one in a struct, pass the struct by pointer.

---

## 8. Closures and the Loop Capture Bug

When a goroutine closure captures a loop variable, it captures the **variable itself** (the memory location), not the value at the time the goroutine was created.

### The classic bug

```go
// WRONG — prints 3, 3, 3 (pre-Go 1.22) or random (Go 1.22+)
for i := 1; i <= 3; i++ {
    go func() {
        fmt.Println(i) // captures the variable i, not its value
    }()
}
```

Since Go 1.22, each loop iteration creates a new `i`, so this is safe. But understanding the old behavior is important for historical code.

### Pre-Go 1.22: the fix

```go
for i := 1; i <= 3; i++ {
    i := i // shadow — creates a new variable per iteration
    go func() {
        fmt.Println(i) // each goroutine captures its own i
    }()
}
```

### The same bug with range (pre-Go 1.22)

```go
items := []string{"a", "b", "c"}

// WRONG — all goroutines print "c"
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

### Why this happens

In Go (pre-1.22), the loop variable is a single memory location that gets reassigned each iteration. The goroutine closure holds a reference to that location, not a copy of the value. By the time the goroutine runs (which could be microseconds later), the variable has moved to its final value.

### Go 1.22+ behavior

```go
// Go 1.22+ — each iteration gets a new i, no bug
for i := range 3 {
    go func() {
        fmt.Println(i) // safe — prints 0, 1, 2
    }()
}
```

> [!tip] The `i := i` idiom is still harmless in Go 1.22+ and makes your code safe to backport or use with older tools. Many teams keep it as a defensive habit.

### This applies to all closures, not just goroutines

```go
var funcs []func()
for i := 0; i < 3; i++ {
    funcs = append(funcs, func() { fmt.Println(i) })
}
funcs[0]() // prints 3 (pre-Go 1.22), not 0
```

---

## 9. Data Races — What They Are and How to Detect Them

A **data race** happens when two or more goroutines access the same memory location concurrently, and at least one access is a write.

### The canonical example

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
LOAD  counter  → register
INC   register
STORE register → counter
```

Two goroutines can interleave like this:
```
Goroutine A: LOAD counter (0) → INC → STORE (1)
Goroutine B:                    LOAD counter (0) → INC → STORE (1)
Result: counter = 1, but we expected 2!
```

### Types of races

#### 1. Read-write race

```go
var x int
go func() { fmt.Println(x) }() // read
go func() { x = 42 }()         // write — race!
```

#### 2. Write-write race

```go
var x int
go func() { x = 1 }() // write
go func() { x = 2 }() // write — race!
```

#### 3. Slice/map races

```go
m := make(map[int]int)
go func() { m[1] = 1 }() // write
go func() { _ = m[1] }() // read — concurrent map access, PANIC!

s := make([]int, 1)
go func() { s[0] = 1 }() // write
go func() { _ = s[0] }() // read — race!
```

### The race detector

Go's toolchain includes a **race detector** — enable it with the `-race` flag:

```bash
go run -race main.go
go build -race ./...
go test -race ./...
```

When it detects a race, it prints a detailed report:

```text
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

The report tells you:
- What operation (read/write) and at which line
- Which goroutines were involved
- The stack trace showing where each goroutine was created

### Limitations of the race detector

- **Only finds races that actually occur** during execution — it is dynamic analysis, not static. Untested code paths may hide races.
- **Adds ~5-10× slowdown** and ~2-5× memory overhead. Not for production, but use it constantly during development.
- **Does not detect all races** — the Go memory model is subtle, and the race detector uses the C/C++ ThreadSanitizer under the hood, which has known blind spots (though they are rare).

### Best practice

```bash
# Always test with -race before committing
go test -race -count=1 ./...
```

> [!warning] The race detector only proves the presence of races, not their absence. A clean race run means "no races in this specific execution" — not "no races, period." Run your tests many times, ideally under load.

---

## 10. sync.Mutex — Protecting Shared Resources

A **mutex** (mutual exclusion lock) ensures that only one goroutine can access a critical section at a time.

### Basic usage

```go
var (
    counter int
    mu      sync.Mutex
)

func increment() {
    mu.Lock()
    counter++ // only one goroutine at a time
    mu.Unlock()
}
```

### The idiomatic defer pattern

```go
func increment() {
    mu.Lock()
    defer mu.Unlock()
    counter++
}
```

Use `defer` even in simple cases — it ensures unlock happens if the function:
- Returns early
- Panics

### Lock and Unlock must always be paired

```go
mu.Lock()
mu.Lock() // deadlock! sync.Mutex is not reentrant
```

A `sync.Mutex` is **not reentrant** — if the same goroutine locks it twice, it deadlocks. This is by design: reentrant locks hide bad code.

### NEVER copy a mutex

```go
type Counter struct {
    mu sync.Mutex
    n  int
}

// WRONG — copying c copies the mutex
func process(c Counter) { // copy!
    c.mu.Lock() // this lock protects the COPY, not the original
    c.n++
    c.mu.Unlock()
}

// RIGHT — pass by pointer
func process(c *Counter) {
    c.mu.Lock()
    c.n++
    c.mu.Unlock()
}
```

If a struct embeds a `sync.Mutex`, pass the struct by pointer, not by value.

### Mutex protects data, not code

```go
var (
    balance int
    mu      sync.Mutex
)

func getBalance() int {
    // WRONG — reading without the lock
    return balance
}

func getBalance() int {
    // RIGHT — every access to balance must hold the lock
    mu.Lock()
    defer mu.Unlock()
    return balance
}
```

The mutex protects the **data**. Every goroutine that touches the data — reads or writes — must hold the same mutex. One goroutine writing with `mu.Lock()` while another reads without `mu.Lock()` is still a data race.

### TryLock (Go 1.18+)

```go
if mu.TryLock() {
    defer mu.Unlock()
    fmt.Println("got the lock, doing work")
} else {
    fmt.Println("lock is held by another goroutine, skipping")
}
```

`TryLock` attempts to acquire the lock and returns `true` if successful without blocking. Use it sparingly — it is typically a sign of questionable design. Most code should use `Lock` and block.

### Mutex performance

- An uncontended `Lock`/`Unlock` pair costs ~25 ns (a few dozen CPU cycles)
- A contended lock causes goroutines to be descheduled (→ the goroutine blocks, the M picks up another G)
- Keep critical sections small — do I/O outside the lock, not inside it

---

## 11. sync.RWMutex — Read-Heavy Workloads

`sync.RWMutex` distinguishes between **readers** and **writers**:

- **Multiple readers** can hold `RLock` simultaneously
- **A writer** requires exclusive access via `Lock` — no readers, no other writers

### Basic usage

```go
var (
    cache   map[string]string
    cacheMu sync.RWMutex
)

func get(key string) (string, bool) {
    cacheMu.RLock()
    defer cacheMu.RUnlock()
    v, ok := cache[key]
    return v, ok
}

func set(key, value string) {
    cacheMu.Lock()
    defer cacheMu.Unlock()
    cache[key] = value
}
```

### When to use RWMutex vs Mutex

| Scenario | Use | Why |
|---|---|---|
| Reads: 1000/s, Writes: 1/s | `RWMutex` | Readers don't block each other — massive throughput win |
| Reads: 100/s, Writes: 100/s | `Mutex` | RWMutex overhead for tracking readers isn't worth it |
| Reads: 1/s, Writes: 1/s | `Mutex` | Simpler, faster for low contention |

### Writer starvation prevention

When a writer calls `Lock`, the mutex typically blocks new readers, preventing writer starvation. This means if a writer is waiting, incoming readers are queued behind it rather than jumping ahead.

```go
// Timeline of events:
// T1: Reader acquires RLock ✅ (1 reader active)
// T2: Reader acquires RLock ✅ (2 readers active)
// T3: Writer calls Lock    ⏳ (blocked — waiting for readers)
// T4: Reader calls RLock   ⏳ (blocked — writer is waiting, prevents starvation)
// T5: T1 releases RUnlock  (1 reader active)
// T6: T2 releases RUnlock  (0 readers active)
// T7: Writer acquires Lock ✅ (writer goes first, as promised)
// T8: T4 Reader acquires RLock ✅ (after writer unlocks)
```

This behavior is not strictly guaranteed by the spec, but the standard implementation does it. Never rely on it for correctness — it's a fairness heuristic, not a contract.

### Rules

- `RLock` / `RUnlock` — many goroutines can hold it concurrently
- `Lock` / `Unlock` — exclusive, blocks all readers and writers
- Never copy an `RWMutex` (same rule as `sync.Mutex`)
- Must pair `RLock` with `RUnlock` and `Lock` with `Unlock`

---

## 12. Safely Sharing Maps, Slices, and Other Data

### Maps are not safe for concurrent access

Go maps **panic** when accessed concurrently by multiple goroutines where at least one writes:

```go
var m = make(map[int]int)

for i := 0; i < 10; i++ {
    go func(k int) {
        m[k] = k * 2 // concurrent write → fatal error: concurrent map writes
    }(i)
}
// panic: fatal error: concurrent map writes
```

Even one concurrent write + one concurrent read panics:

```go
go func() { m[1] = 1 }()  // write
go func() { _ = m[2] }()  // read → fatal error: concurrent map read and map write
```

### Fix 1 — Mutex-protected map

```go
type SafeMap struct {
    mu sync.Mutex
    m  map[string]int
}

func (s *SafeMap) Get(key string) (int, bool) {
    s.mu.Lock()
    defer s.mu.Unlock()
    v, ok := s.m[key]
    return v, ok
}

func (s *SafeMap) Set(key string, val int) {
    s.mu.Lock()
    defer s.mu.Unlock()
    s.m[key] = val
}

func (s *SafeMap) Delete(key string) {
    s.mu.Lock()
    defer s.mu.Unlock()
    delete(s.m, key)
}

func (s *SafeMap) Len() int {
    s.mu.Lock()
    defer s.mu.Unlock()
    return len(s.m)
}
```

### Fix 2 — RWMutex for read-heavy maps

```go
type SafeMap struct {
    mu sync.RWMutex
    m  map[string]int
}

func (s *SafeMap) Get(key string) (int, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    v, ok := s.m[key]
    return v, ok
}

func (s *SafeMap) Set(key string, val int) {
    s.mu.Lock()
    defer s.mu.Unlock()
    s.m[key] = val
}
```

### Fix 3 — sync.Map (specialised, not a drop-in)

`sync.Map` is optimised for specific workloads, not a general-purpose concurrent map:

```go
var m sync.Map

m.Store("key", "value")       // set
v, ok := m.Load("key")        // get
m.LoadOrStore("key", "other") // get or set if absent
m.Delete("key")               // delete

m.Range(func(k, v any) bool {
    fmt.Println(k, v)         // iterate (no ordering guarantees)
    return true               // false to stop iteration
})
```

`sync.Map` is appropriate when:
- Keys are written once and read many times (like a configuration cache)
- Multiple goroutines access **disjoint keys** (no contention)
- You need atomic load-or-store semantics

For everything else, use `map + sync.Mutex` — it's simpler and faster at most workloads.

> [!tip] Profile first. `sync.Map` is not faster than `map + Mutex` in general — it is faster only in the specific patterns it was designed for.

### Slices also need protection

```go
var (
    results []int
    mu      sync.Mutex
)

// WRONG — concurrent append without lock
for i := 0; i < 10; i++ {
    go func(n int) {
        results = append(results, n) // race!
    }(i)
}

// RIGHT
for i := 0; i < 10; i++ {
    go func(n int) {
        mu.Lock()
        results = append(results, n)
        mu.Unlock()
    }(i)
}
```

Appending to a slice might reallocate the backing array — two goroutines doing this concurrently can end up with one write being lost entirely.

### Structs too

```go
type Counter struct {
    mu    sync.Mutex
    Value int
}

func (c *Counter) Inc() {
    c.mu.Lock()
    c.Value++
    c.mu.Unlock()
}

func (c *Counter) Get() int {
    c.mu.Lock()
    defer c.mu.Unlock()
    return c.Value
}
```

### The rule

> [!warning] Any mutable data shared between goroutines must be protected by a mutex, an atomic operation, or accessed exclusively through channels. If two goroutines can touch the same memory and at least one writes, synchronise or face a data race.

---

## 13. sync/atomic — Lock-Free Operations for Simple Cases

For simple counters and flags, `sync/atomic` provides **lock-free** operations that are faster than a mutex:

### Atomic counter

```go
import "sync/atomic"

var counter int64

// Increment
atomic.AddInt64(&counter, 1)

// Read
val := atomic.LoadInt64(&counter)

// Write
atomic.StoreInt64(&counter, 0)

// Compare and swap (CAS) — set to new value only if current == old
swapped := atomic.CompareAndSwapInt64(&counter, 42, 99)
// swapped = true if counter was 42 and is now 99
```

### Complete example

```go
var counter int64

func main() {
    var wg sync.WaitGroup
    for i := 0; i < 1000; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            atomic.AddInt64(&counter, 1)
        }()
    }
    wg.Wait()
    fmt.Println(atomic.LoadInt64(&counter)) // 1000 — no mutex needed
}
```

### Available operations

| Function | Purpose |
|---|---|
| `AddT(ptr, delta)` | Atomic increment/decrement (T = Int32, Int64, Uint32, Uint64) |
| `LoadT(ptr)` | Atomic read |
| `StoreT(ptr, val)` | Atomic write |
| `SwapT(ptr, new)` | Atomic swap, returns old value |
| `CompareAndSwapT(ptr, old, new)` | Atomic CAS, returns bool |
| `AddUintptr`, `LoadPointer`, `StorePointer` | For pointer-sized values |

### Atomic bool (using Int32)

```go
var flag int32

func set()  { atomic.StoreInt32(&flag, 1) }
func get() bool { return atomic.LoadInt32(&flag) == 1 }
```

Or use `atomic.Bool` (Go 1.19+):

```go
var flag atomic.Bool
flag.Store(true)
fmt.Println(flag.Load()) // true
```

### When to use atomics vs mutex

- **Atomics** for: simple counters, flags, single-word values
- **Mutex** for: complex data structures, multi-field structs, maps, slices, any state that involves multiple variables that must change together

```go
// Atomics: perfect for this
var requests int64
atomic.AddInt64(&requests, 1)

// Mutex: needed here (multiple fields must stay consistent)
type Account struct {
    mu      sync.Mutex
    balance int
    owner   string
}
```

---

## 14. sync.Once — One-Time Initialization

`sync.Once` ensures a function is called exactly once, no matter how many goroutines call `Do`:

```go
var (
    config  *Config
    loadCfg sync.Once
)

func GetConfig() *Config {
    loadCfg.Do(func() {
        fmt.Println("loading config...")
        config = loadConfig() // called exactly once
    })
    return config
}

// Multiple goroutines can call GetConfig safely:
go GetConfig()
go GetConfig()
go GetConfig()
// "loading config..." prints only once
```

### How it works

The first goroutine to call `Do` runs the function. All subsequent calls (even concurrent ones) **block until the first finishes**, then return immediately without running the function again.

```go
var once sync.Once
once.Do(func() { fmt.Println("once") })
once.Do(func() { fmt.Println("once") }) // does nothing — already ran
// Output: "once" (only once)
```

### Common uses

- Lazy singleton initialisation
- One-time setup (opening a DB connection pool, loading config)
- Ensuring cleanup runs only once (e.g., closing a file descriptor)

### Panic behavior

If the function passed to `Do` panics, `sync.Once` considers it "done" — subsequent calls to `Do` will **not** retry:

```go
var once sync.Once
once.Do(func() { panic("fail") }) // panic
once.Do(func() { fmt.Println("retry?") }) // never runs — once considers it "done"
```

If you need retry-on-panic behavior, implement it yourself with a flag and a mutex.

---

## 15. Goroutine Panics — What Happens and How to Handle Them

### A panic in any goroutine crashes the entire program

```go
func main() {
    go func() {
        panic("boom!") // this panic kills the whole process
    }()
    time.Sleep(time.Second)
    fmt.Println("will this print?")
}
// Output:
// panic: boom!
// goroutine 5 [running]:
// main.main.func1()
//    main.go:6 +0x2a
// exit status 2
```

Panics are **not** per-goroutine. An unrecovered panic in any goroutine terminates the entire program. There is no "catch" in the parent goroutine.

### Recover only works inside the panicking goroutine

```go
// RIGHT — recover in the same goroutine that panics
go func() {
    defer func() {
        if r := recover(); r != nil {
            fmt.Println("recovered:", r)
        }
    }()
    panic("boom!")
    // recover catches this — other goroutines are unaffected
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

### Always recover in goroutines that can panic

```go
go func() {
    defer func() {
        if r := recover(); r != nil {
            log.Printf("goroutine panicked: %v", r)
        }
    }()
    doRiskyWork() // if this panics, we catch it
}()
```

This is especially important for long-running goroutines (like HTTP handlers, workers): a single panic should not take down the entire server.

---

## 16. Goroutine Leaks — How They Happen and How to Prevent Them

A **goroutine leak** is a goroutine that never exits. It sits in memory forever, holding resources — stack, heap references, open file descriptors, database connections.

### Common causes

#### 1. Blocked on an unbuffered channel send with no receiver

```go
func leak() {
    ch := make(chan int) // unbuffered
    go func() {
        ch <- 42 // blocks forever — no one receives
    }()
    // goroutine never exits
}
```

#### 2. Blocked on a channel receive with no sender

```go
func leak() {
    ch := make(chan int)
    go func() {
        <-ch // blocks forever — no one sends
    }()
}
```

#### 3. Writer goroutine outlives the reader

```go
func process(items []string) {
    ch := make(chan Result)
    for _, item := range items {
        go func(s string) {
            ch <- processItem(s) // blocks if nobody reads
        }(item)
    }
    // read only first result, then return
    result := <-ch
    // remaining goroutines leak — they're blocked sending to ch
}
```

#### 4. Infinite loop without a stop condition

```go
go func() {
    for {
        doWork() // never returns, no stop signal
    }
}()
```

#### 5. Blocked on a mutex that never unlocks

```go
var mu sync.Mutex
mu.Lock()
go func() {
    mu.Lock() // blocks forever — main goroutine never unlocks
}()
// main never calls mu.Unlock()
```

### How to prevent leaks

#### 1. Always have a cancellation path

```go
func worker(done <-chan bool) {
    for {
        select {
        case <-done:
            return // clean exit on signal
        default:
            doWork()
        }
    }
}

done := make(chan bool)
go worker(done)

// Later, signal shutdown
close(done) // all goroutines reading from done will unblock
```

#### 2. Use buffered channels when the number of sends is known

```go
// If you know exactly how many values will be sent, buffer accordingly
results := make(chan Result, len(items))

for _, item := range items {
    go func(s string) {
        results <- processItem(s) // won't block — enough buffer space
    }(item)
}

for i := 0; i < len(items); i++ {
    result := <-results // read all results
}
```

#### 3. Use `select` with timeout

```go
ch := make(chan int)
go func() {
    select {
    case ch <- result:
        fmt.Println("sent successfully")
    case <-time.After(5 * time.Second):
        fmt.Println("timeout — nobody received")
    }
}()
```

#### 4. Track lifecycle with WaitGroup

```go
var wg sync.WaitGroup
wg.Add(1)
go func() {
    defer wg.Done()
    work()
}()
wg.Wait() // proven: goroutine has exited
```

#### 5. Context-based cancellation

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

### Detecting leaks

```go
func TestNoLeak(t *testing.T) {
    before := runtime.NumGoroutine()
    doWork()
    time.Sleep(100 * time.Millisecond) // let goroutines settle
    after := runtime.NumGoroutine()
    if after > before {
        t.Errorf("goroutine leak: %d → %d", before, after)
    }
}
```

Use `runtime.NumGoroutine()` as a health check. In production, expose it via a metrics endpoint. A steadily growing goroutine count is a red flag.

---

## 17. Goroutine Patterns

### Pattern 1 — Fire and Forget

Launch a goroutine and don't wait for its result. The goroutine handles its own errors (usually by logging).

```go
go func() {
    if err := sendWelcomeEmail(user); err != nil {
        log.Printf("failed to send welcome email to %s: %v", user.Email, err)
    }
}()
// main continues immediately — email sends asynchronously
```

**Use when:** the caller doesn't need the result, and the goroutine can handle its own errors.

**Risk:** the goroutine can leak if it blocks. Ensure there's no hidden blocking path or unbounded channel.

### Pattern 2 — Fan-Out (N goroutines, N results)

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

**Use when:** items are independent, all results are needed, and you want maximum concurrency.

### Pattern 3 — Worker Pool (limited concurrency)

Limit the number of concurrently running goroutines to control resource usage:

```go
func workerPool(jobs []Job, numWorkers int) []Result {
    jobCh := make(chan Job, len(jobs))
    resultCh := make(chan Result, len(jobs))
    var wg sync.WaitGroup

    // Start fixed number of workers
    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            for job := range jobCh {
                log.Printf("worker %d processing job %d", id, job.ID)
                resultCh <- process(job)
            }
        }(i)
    }

    // Send jobs
    for _, job := range jobs {
        jobCh <- job
    }
    close(jobCh) // signal workers: no more jobs

    wg.Wait()      // wait for all workers to finish
    close(resultCh)

    var results []Result
    for r := range resultCh {
        results = append(results, r)
    }
    return results
}
```

**Use when:** you have many items but want to limit concurrency (e.g., avoid overwhelming a database, API, or file system).

**Choosing the pool size:**
- CPU-bound work: `runtime.GOMAXPROCS(0)` workers
- IO-bound work: experiment, typically 10-100× the CPU count

### Pattern 4 — Worker Pool with error handling

```go
type Result struct {
    Value int
    Err   error
}

func workerPoolWithErrors(jobs []int, numWorkers int) []Result {
    jobCh := make(chan int, len(jobs))
    resultCh := make(chan Result, len(jobs))
    var wg sync.WaitGroup

    for i := 0; i < numWorkers; i++ {
        wg.Add(1)
        go func() {
            defer wg.Done()
            for job := range jobCh {
                val, err := processWithError(job)
                resultCh <- Result{Value: val, Err: err}
            }
        }()
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

### Pattern 5 — Pipeline (stages connected by channels)

Each stage of the pipeline runs in its own goroutine and communicates via channels:

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

func triple(in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for n := range in {
            out <- n * 3
        }
    }()
    return out
}

func main() {
    // Pipeline: generate → square → triple → print
    for result := range triple(square(generate(1, 2, 3, 4))) {
        fmt.Println(result) // 3, 12, 27, 48
    }
}
```

**Use when:** processing flows through clear stages where each stage does one transformation and the stages can run concurrently.

### Pattern 6 — Goroutine with timeout

Use `select` to enforce a deadline on a goroutine's result:

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

### Pattern 7 — Heartbeat

Periodically report that a goroutine is still alive:

```go
func workerWithHeartbeat(done <-chan bool) <-chan bool {
    heartbeat := make(chan bool, 1)

    go func() {
        defer close(heartbeat)
        for {
            select {
            case <-done:
                return
            case heartbeat <- true:
                // signal that we're alive
            default:
                // do work
            }
        }
    }()

    return heartbeat
}

func main() {
    done := make(chan bool)
    hb := workerWithHeartbeat(done)

    for i := 0; i < 3; i++ {
        select {
        case <-hb:
            fmt.Println("worker is alive")
        case <-time.After(2 * time.Second):
            fmt.Println("worker may be dead — no heartbeat")
        }
    }
    close(done)
}
```

### Pattern 8 — Retry with exponential backoff

```go
func retryWithBackoff(attempts int, fn func() error) error {
    var err error
    for i := 0; i < attempts; i++ {
        if err = fn(); err == nil {
            return nil
        }
        delay := time.Duration(math.Pow(2, float64(i))) * 100 * time.Millisecond
        log.Printf("attempt %d failed: %v; retrying in %v", i+1, err, delay)
        time.Sleep(delay)
    }
    return fmt.Errorf("all %d attempts failed: %w", attempts, err)
}

go retryWithBackoff(3, func() error {
    return sendRequest()
})
```

### Pattern 9 — Graceful worker shutdown

Workers consume jobs until the job channel is closed and the queue is empty, then they exit cleanly:

```go
func startWorkers(num int, jobs <-chan Job, results chan<- Result) {
    var wg sync.WaitGroup

    for i := 0; i < num; i++ {
        wg.Add(1)
        go func(id int) {
            defer wg.Done()
            for job := range jobs {
                log.Printf("worker %d processing job %d", id, job.ID)
                results <- process(job)
            }
            log.Printf("worker %d shutting down", id)
        }(i)
    }

    // Wait in a separate goroutine so the caller doesn't block
    go func() {
        wg.Wait()
        close(results) // all workers done — close results channel
    }()
}

func main() {
    jobs := make(chan Job, 100)
    results := make(chan Result, 100)

    startWorkers(5, jobs, results)

    // Send jobs
    for i := 0; i < 100; i++ {
        jobs <- Job{ID: i}
    }
    close(jobs) // signal: no more jobs

    // Collect results
    for res := range results {
        fmt.Println(res)
    }
}
```

---

## 18. Goroutines Are Not Coroutines

Despite the name, goroutines and coroutines are fundamentally different:

| Aspect | Goroutine | Coroutine |
|---|---|---|
| **Scheduling** | Preemptively scheduled by Go runtime | Explicitly yielded by programmer |
| **Stack** | Has its own stack (grows dynamically) | Usually stackless |
| **Concurrency** | Can run in parallel (GOMAXPROCS > 1) | Single-threaded cooperative |
| **Yield points** | Blocking calls (I/O, channels, signals) | Explicit `yield` or `await` |
| **Relationship** | Not hierarchical (no parent-child) | Often hierarchical (caller awaits callee) |
| **Identity** | No identity, no handle | Has identity (e.g., Lua coroutine handle, Python generator) |
| **Resume** | Automatically by scheduler | Manually by caller |

### Key difference in practice

```go
// Goroutine — you start it and forget it
go func() {
    data := <-ch     // runtime yields here if no data available
    result := process(data)
    ch2 <- result    // runtime yields here until receiver is ready
}()
// The scheduler decides when to run/resume this goroutine

// Coroutine (conceptual — Lua/Python style)
co = create_coroutine(func() {
    data = receive(ch) // yields explicitly
    result = process(data)
    send(ch2, result)  // yields explicitly
})
resume(co) // I, the caller, decide when to resume
```

Goroutines let you write **sequential code** that is automatically concurrent. You don't mark yield points; the runtime finds them. This is why Go concurrency is often described as "easy" — you write normal functions and just prefix them with `go`.

> [!info] Goroutines are closer to **green threads** (lightweight, preemptively scheduled, independent stacks) than to **coroutines** (cooperative, stackless, hierarchical). The name "goroutine" was chosen deliberately to avoid this confusion.

---

## 19. Debugging Goroutines

### Getting a goroutine dump

Send `SIGQUIT` to a running Go program on Unix:

```bash
kill -QUIT <pid>
```

The program prints a stack trace of **all goroutines** and exits. This is invaluable for debugging deadlocks and leaks.

```text
goroutine 1 [running]:
main.main()
    /home/user/main.go:10 +0x39

goroutine 5 [chan receive]:
main.worker()
    /home/user/main.go:22 +0x4f
created by main.main in goroutine 1
    /home/user/main.go:15 +0x3a
...
```

### Programmatic stack dump

```go
import "runtime/pprof"

func dumpGoroutines() {
    buf := make([]byte, 64*1024)
    n := runtime.Stack(buf, true) // true = all goroutines
    fmt.Println(string(buf[:n]))
}
```

### runtime.NumGoroutine()

```go
fmt.Println("number of goroutines:", runtime.NumGoroutine())
```

Use this in health checks to detect leaks.

### pprof — profiling goroutines

```go
import (
    "net/http"
    _ "net/http/pprof" // registers /debug/pprof/ handler
)

func main() {
    go func() {
        log.Println(http.ListenAndServe("localhost:6060", nil))
    }()
    // ... your app
}
```

Then visit `http://localhost:6060/debug/pprof/goroutine` to see all goroutines with their stack traces.

### GOTRACEBACK environment variable

Controls the amount of output on a crash:

```bash
GOTRACEBACK=none    # just the panic message, no stacks
GOTRACEBACK=single  # stack of the crashing goroutine only (default)
GOTRACEBACK=all     # stacks of all goroutines
GOTRACEBACK=system  # stacks of all goroutines + runtime frames
GOTRACEBACK=crash   # same as system, but also calls SIGABRT (creates coredump)
```

---

## 20. Goroutines and the net/http Server

The `net/http` server uses goroutines implicitly — **each HTTP request runs in its own goroutine**:

```go
func main() {
    http.HandleFunc("/", handler)
    log.Fatal(http.ListenAndServe(":8080", nil))
}

func handler(w http.ResponseWriter, r *http.Request) {
    // This runs in a NEW goroutine for each request
    fmt.Fprintf(w, "Hello from goroutine %d", goroutineID())
}
```

### Why this matters

- Multiple requests are handled **concurrently** without you writing any `go` statements
- Each handler is a new goroutine — if one blocks, others are unaffected
- You get concurrent request handling for free

### The implication for shared state

```go
var counter int // shared state — not protected!

func handler(w http.ResponseWriter, r *http.Request) {
    counter++ // DATA RACE — multiple goroutines modify this concurrently
    fmt.Fprintf(w, "Request #%d", counter)
}
```

Always protect shared state in HTTP handlers with mutexes.

---

## 21. Quick Reference Cheatsheet

```go
// ── Starting a goroutine ────────────────────────────────────
go myFunction()
go func() { fmt.Println("hi") }()

// ── WaitGroup ───────────────────────────────────────────────
var wg sync.WaitGroup
wg.Add(1)          // before goroutine
go func() {
    defer wg.Done() // in defer
    // ...
}()
wg.Wait()

// ── WaitGroup with known count ──────────────────────────────
n := 10
wg.Add(n)
for i := 0; i < n; i++ {
    go func(id int) {
        defer wg.Done()
        work(id)
    }(i)
}
wg.Wait()

// ── Loop capture bug fix (pre-Go 1.22) ─────────────────────
for i := 0; i < 3; i++ {
    i := i // shadow
    go func() { fmt.Println(i) }()
}

// ── Mutex ───────────────────────────────────────────────────
var mu sync.Mutex
mu.Lock()
// critical section
mu.Unlock()

// Idiomatic:
mu.Lock()
defer mu.Unlock()

// ── RWMutex ─────────────────────────────────────────────────
var rwmu sync.RWMutex
rwmu.RLock()       // multiple readers allowed
rwmu.RUnlock()
rwmu.Lock()        // exclusive writer
rwmu.Unlock()

// ── Atomic counter (sync/atomic) ────────────────────────────
var counter int64
atomic.AddInt64(&counter, 1)
val := atomic.LoadInt64(&counter)

// ── Race detection ──────────────────────────────────────────
// go run -race main.go
// go test -race ./...

// ── sync.Once (one-time init) ───────────────────────────────
var once sync.Once
once.Do(func() { initOnce() })

// ── Recover from goroutine panic ────────────────────────────
go func() {
    defer func() {
        if r := recover(); r != nil {
            log.Printf("recovered: %v", r)
        }
    }()
    riskyWork()
}()

// ── Goroutine leak prevention: done channel ─────────────────
done := make(chan bool)
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

// ── Worker pool ─────────────────────────────────────────────
jobs := make(chan Job, 100)
results := make(chan Result, 100)

for i := 0; i < 5; i++ {
    wg.Add(1)
    go func() {
        defer wg.Done()
        for job := range jobs {
            results <- process(job)
        }
    }()
}
close(jobs)
wg.Wait()
close(results)

// ── GOMAXPROCS ──────────────────────────────────────────────
runtime.GOMAXPROCS(0)  // get
runtime.GOMAXPROCS(8)  // set (rarely needed)

// ── Runtime checks ─────────────────────────────────────────
runtime.NumGoroutine() // count
runtime.Gosched()      // yield
runtime.Goexit()       // exit current goroutine (defers run)

// ── Goroutine dump ──────────────────────────────────────────
// kill -QUIT <pid>
// OR:
pprof.Lookup("goroutine").WriteTo(os.Stdout, 1)

// ── GOTRACEBACK ─────────────────────────────────────────────
// GOTRACEBACK=all ./myapp  → stacks of all goroutines on crash

// ── Rules ───────────────────────────────────────────────────
// ✅ Always Add before go
// ✅ Always defer Done / Unlock / RUnlock
// ✅ Always use -race during development
// ✅ Never copy a sync.Mutex / RWMutex / WaitGroup
// ✅ Never let main() exit while goroutines run
// ✅ Every goroutine needs a way to stop
// ✅ Protect all shared mutable data
// ❌ Never access a map concurrently without synchronization
// ❌ Never use panic for expected errors (even in goroutines)
// ❌ Never assume goroutines finish before main exits
// ❌ Never ignore the race detector output
```

---

_Previous: [[11 - Error Handling]] · Next: [[13 - Channels]]_
