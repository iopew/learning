****# Go — Channels

> **Series:** Go Language Fundamentals **Tags:** #go #golang #channels #concurrency #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. What is a Channel?]]
- [[#2. Unbuffered vs Buffered]]
- [[#3. Send and Receive]]
- [[#4. Closing a Channel]]
- [[#5. Range Over a Channel]]
- [[#6. Channel Direction]]
- [[#7. Select — The Basics]]
- [[#8. Deadlocks]]
- [[#9. Nil Channels]]
- [[#10. Channel Ownership]]
- [[#11. Channel vs Mutex]]
- [[#12. Quick Reference Cheatsheet]]

---

## 1. What is a Channel?

A **channel** is a typed pipe goroutines use to communicate: a value sent on one end, received on the other.

```go
ch := make(chan int)        // channel of int
go func() { ch <- 42 }()    // send
v := <-ch                   // receive
fmt.Println(v)              // 42
```

**The mail-slot analogy** (from [[12 - Goroutines]]): a box holding one note at a time — putting a note in blocks if the box already has one, taking a note blocks if it's empty.

> [!info] Channels are **typed** — `chan int` carries only `int`. The compiler enforces it.

## 2. Unbuffered vs Buffered

**Unbuffered** (`make(chan T)`) — **synchronous**: send blocks until someone receives, receive blocks until someone sends. A strict handshake.

**Buffered** (`make(chan T, n)`) — **asynchronous**: up to `n` values wait in the buffer.

```go
unbuf := make(chan int)   // send blocks until a receiver exists
buf := make(chan int, 3)  // 3 values can wait
buf <- 1                  // no receiver needed — fits in buffer
buf <- 2
buf <- 3
buf <- 4                  // BLOCKS — buffer is full
```

| | Unbuffered | Buffered |
|---|---|---|
| Send blocks when | no receiver | buffer full |
| Receive blocks when | no sender | buffer empty |
| Guarantee | receiver gets value immediately | values queue up |
| Use case | strict handshake / sync | decouple producer & consumer |

> [!tip] Buffered channels do **not** lose messages — they just queue them. Order is FIFO.

## 3. Send and Receive

```go
ch <- 42        // send — arrow points INTO the channel
v := <-ch       // receive — arrow points OUT of the channel
v, ok := <-ch   // comma-ok form — ok=false if channel closed and drained
```

> [!warning] Sending to a **closed** channel panics. Receiving from one never panics — it returns the zero value with `ok=false`.

## 4. Closing a Channel

`close(ch)` signals "no more values coming." Receivers detect the end via comma-ok:

```go
ch := make(chan int)
close(ch)
v, ok := <-ch
fmt.Println(v, ok)  // 0 false — zero value, channel closed
```

**Rules:**
- Only the **sender** closes. Receivers never close.
- Closing an already-closed channel panics. Sending to a closed channel panics.
- After close, receives return `zero, false` **forever**.

## 5. Range Over a Channel

`for v := range ch` receives until the channel is closed. The standard way to consume a stream:

```go
ch := make(chan int)
go func() {
    for i := 1; i <= 3; i++ { ch <- i }
    close(ch)   // without this, range blocks forever
}()
for v := range ch {
    fmt.Println(v)  // 1, 2, 3
}
```

> [!warning] If the sender never closes, `range` blocks forever — a goroutine leak.

## 6. Channel Direction

Parameters can declare direction so the compiler enforces who does what:

- `chan<- T` — send-only
- `<-chan T` — receive-only

```go
func produce(ch chan<- int) { ch <- 1 }   // can only send
func consume(ch <-chan int) { v := <-ch } // can only receive
```

The same `make(chan T)` value is passed in; direction is just the contract on the parameter. This is what the worker pool and pipeline used.

## 7. Select — The Basics

`select` waits on **multiple channel operations**, runs the first one that's ready. Deep dive in [[14 - Select]].

```go
select {
case v := <-ch1:
    fmt.Println("got from ch1:", v)
case ch2 <- 42:
    fmt.Println("sent to ch2")
case <-time.After(2 * time.Second):
    fmt.Println("timed out")
default:
    fmt.Println("nothing ready — don't block")
}
```

- Blocks until one case is ready
- Multiple ready → picks **randomly** (fairness)
- `default` → runs immediately if nothing ready (non-blocking)

## 8. Deadlocks

A deadlock: every goroutine is blocked, none can ever proceed. Go detects this at runtime and crashes the program:

```go
ch := make(chan int)
ch <- 1
// fatal error: all goroutines are asleep - deadlock!
// main sends, no one receives — and main is the only goroutine
```

Common causes:
- Sending without a receiver (unbuffered)
- Receiving without a sender
- `range` over a channel that never closes
- Locking the same mutex twice

> [!info] The deadlock detector only fires when **no** goroutine can make progress. A goroutine blocked while others work is not a deadlock — it's just waiting.

## 9. Nil Channels

The zero value of a channel is `nil`. Send or receive on a nil channel **blocks forever** — silently:

```go
var ch chan int   // nil — zero value
ch <- 1           // blocks forever
<-ch              // also blocks forever
```

> [!tip] In `select`, a nil channel case is **disabled** — never ready. This is a real technique, covered in [[14 - Select]].

## 10. Channel Ownership

A channel is created by one goroutine but used by many. The rules that prevent leaks and panics:

- **Creator owns it** — whoever does `make` is responsible for it
- **Only the sender closes** — never the receiver
- **One sender** → it closes when done
- **Multiple senders** → use a separate `done` channel or a coordinator; never close from two goroutines

Follow "creator owns, sender closes" and you get no double-close panics and no range leaks.

## 11. Channel vs Mutex

> [!info] **Go proverb:** "Don't communicate by sharing memory; share memory by communicating."

| | Channel | Mutex |
|---|---|---|
| Purpose | pass data between goroutines | protect shared data |
| Mental model | mail slot / pipe | lock on a room |
| Blocks when | send/receive not ready | lock already held |
| Use when | producer → consumer, pipelines | many goroutines updating one map/counter |

Mutexes are covered in depth in [[15 - Sync Primitives]].

## 12. Quick Reference Cheatsheet

```go
// Create
ch := make(chan T)         // unbuffered (synchronous)
buf := make(chan T, n)     // buffered — n slots

// Send / receive
ch <- v                    // send (blocks if no receiver / buffer full)
v := <-ch                  // receive (blocks if no sender / buffer empty)
v, ok := <-ch              // ok=false → closed and drained

// Close
close(ch)                  // only the sender closes!
// sending to closed channel → panic
// receiving from closed channel → zero value + ok=false

// Range
for v := range ch { }      // consumes until closed

// Direction
func f(ch chan<- T) {}     // send-only parameter
func g(ch <-chan T) {}     // receive-only parameter

// Select basics (deep dive: 14 - Select)
select {
case v := <-ch1: ...
case <-time.After(1 * time.Second): ...
default: ...
}

// Nil channel — blocks forever; disabled case in select
var nilCh chan int

// Rules
// ✅ only sender closes
// ✅ range until close
// ✅ creator owns the channel
// ❌ never send to closed channel
// ❌ never close twice
// ❌ never let goroutines wait forever (leaks)
```

---

_Previous: [[12 - Goroutines]] · Next: [[14 - Select]]_
