# Go — Select

> **Series:** Go Language Fundamentals **Tags:** #go #golang #select #channels #concurrency #programming **Level:** Intermediate

---

## Table of Contents

- [[#1. What is Select?]]
- [[#2. Blocking & Random Choice (Fairness)]]
- [[#3. Default — Non-blocking]]
- [[#4. for + select — The Event Loop]]
- [[#5. Done Channel — Cancellation]]
- [[#6. Timeout & Ticker]]
- [[#7. Fan-in — Many Channels into One]]
- [[#8. Nil Channels — Self-Disabling Cases]]
- [[#9. select {} — Block Forever]]
- [[#10. Gotchas]]
- [[#11. Quick Reference Cheatsheet]]

---

## 1. What is Select?

`select` waits on **multiple channel operations** and runs the first one that becomes ready. The only way to wait on several channels at once.

```go
select {
case msg := <-ch1:
    fmt.Println("got from ch1:", msg)
case msg := <-ch2:
    fmt.Println("got from ch2:", msg)
}
```

One case runs, then `select` exits. If both are ready at once — it picks randomly.

> [!info] Like a `switch` for channels: `switch` matches on **values**, `select` matches on **readiness**.

## 2. Blocking & Random Choice (Fairness)

- No case ready → `select` **blocks** until one is
- Multiple cases ready → picks **one at random**

```go
ch1 := make(chan int)
ch2 := make(chan int)
close(ch1)   // a closed channel is immediately readable (zero value)
close(ch2)

for i := 0; i < 10; i++ {
    select {
    case <-ch1:
        fmt.Println("ch1")
    case <-ch2:
        fmt.Println("ch2")
    }
}
// ≈ 50/50 split
```

The randomness is **guaranteed**, not an implementation detail — it prevents starvation. If one channel is constantly ready, the others still get a turn.

> [!warning] Random only among cases that are *ready at that moment*. A channel that's usually ready will still win most of the time.

## 3. Default — Non-blocking

`default` runs **immediately** when no other case is ready. No blocking, ever.

```go
select {
case ch <- v:
    fmt.Println("sent")
default:
    fmt.Println("nobody ready — dropped")   // non-blocking send
}
```

Patterns:
- **Non-blocking send** — don't wait for a receiver
- **Non-blocking receive** — peek without blocking
- **Dropping** — skip work when the consumer is behind

## 4. for + select — The Event Loop

The backbone of every long-running goroutine and Go server:

```go
for {
    select {
    case job := <-jobCh:
        process(job)
    case <-done:
        return
    case <-ticker.C:
        flushStats()
    }
}
```

Each `select` iteration handles one event and loops back. One goroutine can serve work, cancellation, and timers at once.

## 5. Done Channel — Cancellation

A `done` channel (`chan struct{}`) broadcasts shutdown. `close(done)` unblocks **all** goroutines waiting on it simultaneously.

```go
done := make(chan struct{})
go worker(jobCh, done)
// ... later:
close(done)   // every worker sees <-done and exits
```

```go
func worker(jobCh <-chan Job, done <-chan struct{}) {
    for {
        select {
        case job := <-jobCh:
            process(job)
        case <-done:
            return      // graceful exit
        }
    }
}
```

This is the manual version of what `context` automates — see [[24 - Context]].

## 6. Timeout & Ticker

`time.After(d)` sends the current time to a channel after `d`. Use it as a deadline in `select`:

```go
result := make(chan string, 1)
go func() { result <- fetchData() }()

select {
case r := <-result:
    fmt.Println("got:", r)
case <-time.After(3 * time.Second):
    fmt.Println("timed out")
}
```

> [!warning] `time.After` allocates a fresh timer per call. In a hot `for { select }` loop this leaks timers. For repeated deadlines use `time.NewTimer` and `Reset`, or `time.Tick`/`time.NewTicker` for periodic events.

```go
ticker := time.NewTicker(time.Second)
for {
    select {
    case <-ticker.C:
        fmt.Println("tick")
    case <-done:
        return
    }
}
```

## 7. Fan-in — Many Channels into One

Fan-in merges N input channels into a single output channel. One goroutine serves all inputs via `select`:

```go
func fanIn(ch1, ch2 <-chan string) <-chan string {
    out := make(chan string)
    go func() {
        defer close(out)
        for {
            select {
            case s := <-ch1:
                out <- s
            case s := <-ch2:
                out <- s
            }
        }
    }()
    return out
}
```

The consumer reads one merged stream instead of juggling two channels. Add more inputs by adding more `case`s.

## 8. Nil Channels — Self-Disabling Cases

A `nil` channel in a `select` is **never ready** — the case is silently skipped. Set a channel to `nil` to turn its case off dynamically:

```go
for {
    select {
    case v, ok := <-ch:
        if !ok { ch = nil }   // disable this case — channel drained
    case <-done:
        return
    }
}
```

After `ch = nil`, that case never fires again — the loop stays alive for `done` without spinning.

## 9. select {} — Block Forever

An empty `select` with no cases blocks forever. Used to keep `main` alive:

```go
select {}   // blocks forever
```

> [!tip] The "keep the program running" pattern — same as `for {}` but without burning CPU.

## 10. Gotchas

- **`time.After` in a hot loop** — allocates a timer per call; leaks under load. Use `time.NewTimer`/`Ticker`.
- **Closed channel + select** — a receive case on a closed channel is *always* ready. Without an `ok` check, the loop spins forever receiving zero values.
- **`default` in a tight loop** — `for { select { ... default: } }` burns 100% CPU (busy loop). Only use non-blocking where spinning is intended, or add `time.Sleep`.
- **Fan-in that never closes `out`** — consumers `range` forever. Close when all inputs are done.
- **Two `case`s ready** — random pick; never write code that depends on one winning.

## 11. Quick Reference Cheatsheet

```go
// Wait on multiple channels
select {
case v := <-ch1:
case v := <-ch2:
}

// Non-blocking (default)
select {
case ch <- v:
default:
}

// Timeout
select {
case v := <-ch:
case <-time.After(3 * time.Second):
}

// Event loop
for {
    select {
    case job := <-jobs: process(job)
    case <-done: return
    case <-ticker.C: flush()
    }
}

// Cancellation broadcast
done := make(chan struct{})
// worker: case <-done: return
close(done)   // unblocks every goroutine waiting on done

// Fan-in
for {
    select {
    case s := <-ch1: out <- s
    case s := <-ch2: out <- s
    }
}

// Disable a case: set its channel to nil
ch = nil

// Block forever
select {}

// Rules
// ✅ exactly one case fires per select
// ✅ random pick when multiple ready — never rely on order
// ✅ nil channel = disabled case
// ✅ check ok on receives from closed channels
// ❌ time.After in hot loops
// ❌ default in tight loops without sleep
```

---

_Previous: [[13 - Channels]] · Next: [[15 - Sync Primitives]]_
