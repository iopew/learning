# Go — Functions

> **Series:** Go Language Fundamentals **Tags:** #go #golang #functions #closures #defer #panic #generics #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. Basic Syntax]]
- [[#2. Parameters — Go Is Always Pass-By-Value]]
- [[#3. Return Values]]
- [[#4. Variadic Functions]]
- [[#5. Functions Are Values (First-Class Functions)]]
- [[#6. Anonymous Functions & Function Literals]]
- [[#7. Closures]]
- [[#8. What is a Handler]]
- [[#9. What is Middleware — and How the Chain Works]]
- [[#10. defer — Deep Dive]]
- [[#11. panic and recover]]
- [[#12. Generic Functions (Go 1.18+)]]
- [[#13. init() — Package Initialization Functions]]
- [[#14. main() — The Entry Point]]
- [[#15. Recursion]]
- [[#16. Methods vs. Functions — Quick Orientation]]
- [[#17. The Functional Options Pattern]]
- [[#18. No Function Overloading, No Default Arguments]]
- [[#19. Order of Evaluation]]
- [[#20. Common Pitfalls — Quick Reference Table]]
- [[#21. Performance Notes]]
- [[#22. Best Practices Checklist]]
- [[#23. Cheat Sheet — Syntax at a Glance]]

---

## 1. Basic Syntax

```go
func functionName(param1 Type1, param2 Type2) ReturnType {
    // body
    return value
}
```

- `func` keyword starts every function declaration.
- Parameters: `name Type`. Consecutive parameters of the **same type** can share a type annotation:

```go
func add(a, b int) int {
    return a + b
}
```

- No parameters, no return value:

```go
func greet() {
    fmt.Println("Hello!")
}
```

- A function with no `return` statement and no return type simply ends when execution reaches the closing `}`.

> [!tip] Naming convention Go uses `camelCase` for function names. A **capitalized** first letter (`Add`, `ParseConfig`) makes the function **exported** — visible outside its package. Lowercase (`add`, `parseConfig`) keeps it package-private. There's no `public`/`private` keyword — visibility is encoded purely in capitalization.

---

## 2. Parameters — Go Is Always Pass-By-Value

This is the single most important semantic fact about Go functions, and the source of most "why did my function not mutate my data?!" confusion.

**Every argument passed to a function is copied.** This is true for `int`, `struct`, arrays, pointers, slices, maps — everything. The difference in behavior comes from **what is being copied**.

### 2.1 Primitives and structs — copied entirely

```go
func double(x int) {
    x = x * 2
    fmt.Println("inside:", x) // 20
}

func main() {
    n := 10
    double(n)
    fmt.Println("outside:", n) // still 10 — unaffected
}
```

```go
type Point struct{ X, Y int }

func move(p Point) {
    p.X += 100 // mutates the COPY
}

func main() {
    pt := Point{1, 2}
    move(pt)
    fmt.Println(pt) // {1 2} — unchanged
}
```

### 2.2 Pointers — the pointer value is copied, but it points to the same memory

```go
func movePtr(p *Point) {
    p.X += 100 // dereferences the copied pointer, mutates the ORIGINAL
}

func main() {
    pt := Point{1, 2}
    movePtr(&pt)
    fmt.Println(pt) // {101 2}
}
```

### 2.3 Arrays — copied entirely

```go
func zeroOut(arr [3]int) {
    arr[0] = 0 // mutates the copy only
}

func main() {
    a := [3]int{1, 2, 3}
    zeroOut(a)
    fmt.Println(a) // [1 2 3] — unchanged
}
```

### 2.4 Slices, Maps, Channels — the header is copied, but it shares the underlying data

A slice is a small struct: `{ pointer, length, capacity }`. That struct gets copied — but the pointer inside it still points to the same backing array.

```go
func setFirst(s []int) {
    if len(s) > 0 {
        s[0] = 999 // mutates shared backing array — VISIBLE to caller
    }
}

func main() {
    s := []int{1, 2, 3}
    setFirst(s)
    fmt.Println(s) // [999 2 3]
}
```

But **reassigning the slice itself** inside the function does **not** affect the caller:

```go
func appendOne(s []int) {
    s = append(s, 99) // local header change — caller never sees it
}

func main() {
    s := []int{1, 2, 3}
    appendOne(s)
    fmt.Println(s) // [1 2 3] — length unchanged!
}
```

> [!warning] The classic slice-mutation gotcha `append` inside a function is **invisible to the caller** unless the function returns the new slice and the caller reassigns it. This is why Go functions look like `func addItem(s []int, item int) []int { return append(s, item) }` — and why `s = addItem(s, 4)` is required.

### 2.5 Summary table

|Type passed|What's copied|Mutation visible to caller?|Reassignment visible?|
|---|---|---|---|
|`int`, `string`, `bool`, `struct`|Full value|N/A|No|
|Array `[N]T`|Full array|No|No|
|Pointer `*T`|The pointer (address)|Yes (dereferenced write)|No|
|Slice `[]T`|Header (ptr, len, cap)|Yes, for existing elements|No|
|Map|Reference to hashtable|Yes (add/update/delete)|No|
|Channel|Reference|Yes (send/receive)|No|

---

## 3. Return Values

### 3.1 Single return

```go
func square(x int) int {
    return x * x
}
```

### 3.2 Multiple return values

```go
func divmod(a, b int) (int, int) {
    return a / b, a % b
}

q, r := divmod(17, 5) // q = 3, r = 2
```

The overwhelmingly common use is **value + error**:

```go
func parseAge(s string) (int, error) {
    n, err := strconv.Atoi(s)
    if err != nil {
        return 0, fmt.Errorf("invalid age %q: %w", s, err)
    }
    if n < 0 {
        return 0, errors.New("age cannot be negative")
    }
    return n, nil
}
```

### 3.3 Named return values

You can name the return values in the signature:

```go
func divmod(a, b int) (q, r int) {
    q = a / b
    r = a % b
    return // "naked" return — returns current values of q and r
}
```

### 3.4 Naked returns — convenient but risky

> [!warning] Naked returns hurt readability in long functions In a 50-line function, a bare `return` gives the reader zero information. Prefer explicit `return q, r` except in very short functions.

### 3.5 Named returns + defer — the "magic" interaction

A deferred function **can modify named return values** because they're variables in the enclosing scope, and `defer` runs after `return` assigns to them but before the function actually exits:

```go
func increment() (result int) {
    defer func() {
        result++ // mutates the named return value
    }()
    return 10
}

fmt.Println(increment()) // 11, not 10!
```

The execution order:

```
1. return 10        → result = 10
2. deferred func    → result++ → result = 11
3. actually returns → caller gets 11
```

```go
func doWork() (err error) {
    defer func() {
        if r := recover(); r != nil {
            err = fmt.Errorf("doWork panicked: %v", r)
        }
    }()
    // ... risky code ...
    return nil
}
```

> [!tip] If your return values are **unnamed**, a deferred function cannot alter them — there's nothing to assign to.

### 3.6 The blank identifier `_`

```go
value, _ := someFunc() // ignore the error — almost always a code smell!
_, err := someFunc()   // ignore the value, keep the error
```

---

## 4. Variadic Functions

A variadic parameter accepts zero or more arguments of a given type, collected into a slice inside the function.

```go
func sum(nums ...int) int {
    total := 0
    for _, n := range nums {
        total += n
    }
    return total
}

sum()        // 0
sum(1)       // 1
sum(1, 2, 3) // 6
```

### 4.1 Spreading a slice into variadic args

```go
nums := []int{1, 2, 3, 4}
total := sum(nums...) // 10
```

### 4.2 Rules and constraints

- A variadic parameter **must be the last parameter** in the list.
- A function can have **at most one** variadic parameter.
- You can mix fixed and variadic params:

```go
func logMessage(level string, args ...interface{}) {
    fmt.Printf("[%s] ", level)
    fmt.Println(args...)
}

logMessage("INFO", "user", 42, "logged in")
```

### 4.3 `nums ...int` is just `[]int` inside the function

Inside the function body, `nums` has type `[]int` — you can `range` over it, index it, check `len(nums)`, etc.

> [!warning] Nil vs empty slice for variadic args If you call `sum()` with zero arguments, `nums` inside the function is `nil`. For most operations this is fine — but `nil` marshals to `null` in JSON while `[]int{}` marshals to `[]`.

---

## 5. Functions Are Values (First-Class Functions)

In Go, functions are values — they have types, can be stored in variables, passed as arguments, returned from other functions, and stored in data structures.

### 5.1 Function types

```go
type BinOp func(int, int) int

var op BinOp = func(a, b int) int { return a + b }
fmt.Println(op(2, 3)) // 5
```

```go
func add(a, b int) int { return a + b }
func mul(a, b int) int { return a * b }

var op BinOp
op = add
fmt.Println(op(2, 3)) // 5
op = mul
fmt.Println(op(2, 3)) // 6
```

### 5.2 Passing functions as arguments (higher-order functions)

```go
func apply(a, b int, op func(int, int) int) int {
    return op(a, b)
}

result := apply(3, 4, func(a, b int) int { return a * b }) // 12
```

This is the foundation of `sort.Slice`, middleware, callbacks, and `strings.TrimFunc`:

```go
words := []string{"banana", "kiwi", "apple"}
sort.Slice(words, func(i, j int) bool {
    return len(words[i]) < len(words[j])
})
// words is now ["kiwi" "apple" "banana"]
```

### 5.3 Returning functions (function factories)

```go
func multiplier(factor int) func(int) int {
    return func(x int) int {
        return x * factor
    }
}

double := multiplier(2)
triple := multiplier(3)
fmt.Println(double(5)) // 10
fmt.Println(triple(5)) // 15
```

### 5.4 Functions in data structures — dispatch tables

```go
var operations = map[string]func(int, int) int{
    "add": func(a, b int) int { return a + b },
    "sub": func(a, b int) int { return a - b },
    "mul": func(a, b int) int { return a * b },
}

if op, ok := operations["add"]; ok {
    fmt.Println(op(3, 4)) // 7
}
```

### 5.5 Functions are not comparable (except to nil)

```go
var f func()
fmt.Println(f == nil) // true — valid

f2 := func() {}
// fmt.Println(f == f2) // COMPILE ERROR
```

Calling a nil function panics:

```go
var f func()
f() // panic: runtime error: invalid memory address or nil pointer dereference
```

---

## 6. Anonymous Functions & Function Literals

A function literal is a function defined inline, without a name.

```go
// Assign to a variable
square := func(x int) int { return x * x }
fmt.Println(square(5)) // 25

// Immediately invoke (IIFE)
result := func(a, b int) int {
    return a + b
}(3, 4)
fmt.Println(result) // 7
```

Common uses: closures, one-off goroutines (`go func() { ... }()`), deferred cleanup (`defer func() { ... }()`).

---

## 7. Closures

A closure is a function literal that **references variables from outside its own body**. The function "closes over" those variables — it keeps a live reference to them, not a copy, and they persist as long as the closure is reachable.

### 7.1 The classic counter

```go
func makeCounter() func() int {
    count := 0
    return func() int {
        count++
        return count
    }
}

c1 := makeCounter()
c2 := makeCounter()

fmt.Println(c1()) // 1
fmt.Println(c1()) // 2
fmt.Println(c1()) // 3
fmt.Println(c2()) // 1 — independent state, separate closure
```

`makeCounter` has finished — normally `count` would be gone. But the returned function still holds a reference to it. Go moves `count` to the heap automatically so it survives.

### 7.2 Why each closure gets its own copy

Each call to `makeCounter` creates a **new** `count` variable. `c1` and `c2` close over their own independent `count` — they never share state.

### 7.3 Shared state between multiple closures

If two closures are created in the **same scope**, they share the same captured variable:

```go
func makePair() (func(), func() int) {
    count := 0
    increment := func() { count++ }
    get := func() int { return count }
    return increment, get
}

inc, get := makePair()
inc()
inc()
fmt.Println(get()) // 2 — both closures share the same count
```

### 7.4 The loop variable capture gotcha

**Go 1.22+** — each iteration gets its own copy of the loop variable (safe):

```go
funcs := make([]func(), 3)
for i := 0; i < 3; i++ {
    funcs[i] = func() { fmt.Println(i) }
}
// Go 1.22+: prints 0, 1, 2
```

**Before Go 1.22** — one shared `i` variable, all closures see the final value:

```go
// Pre-1.22: prints 3, 3, 3
```

> [!warning] The loop semantics are tied to the `go` directive in `go.mod`, not just your compiler version. Old codebases with `go 1.21` still use the old behavior even with a newer compiler.

The defensive pattern (works on any version):

```go
for i := 0; i < 3; i++ {
    i := i // shadow — new variable per iteration
    funcs[i] = func() { fmt.Println(i) }
}
```

### 7.5 Closures and goroutines

```go
// DANGEROUS on Go < 1.22
for _, url := range urls {
    go func() {
        fetch(url) // pre-1.22: all goroutines may see the SAME final url
    }()
}

// Always-safe — pass as argument, copies the value
for _, url := range urls {
    go func(u string) {
        fetch(u)
    }(url)
}
```

---

## 8. What is a Handler

A **handler** is a function that is called **in response to an event**. You register it somewhere — a router, an event system, a channel — and the system calls it for you when the event occurs. You don't call the handler yourself.

In Go's HTTP world, a handler has this exact signature:

```go
func(w http.ResponseWriter, r *http.Request)
// w = where you write the response (what goes back to the client)
// r = the incoming request (URL, headers, body, method)
```

A concrete example:

```go
func getUsers(w http.ResponseWriter, r *http.Request) {
    // this is the handler — it runs when someone visits /users
    users := fetchUsersFromDB()
    json.NewEncoder(w).Encode(users)
}

// Register it — "when someone requests /users, call getUsers"
http.HandleFunc("/users", getUsers)
```

`getUsers` doesn't know when it will be called, or by whom. The HTTP server calls it for you every time a request to `/users` comes in.

### What a handler receives

`r *http.Request` gives you everything about the incoming request:

```go
func handler(w http.ResponseWriter, r *http.Request) {
    fmt.Println(r.Method)          // "GET", "POST", "DELETE" etc.
    fmt.Println(r.URL.Path)        // "/users/42"
    fmt.Println(r.URL.Query())     // ?page=2&limit=10
    fmt.Println(r.Header.Get("Authorization"))  // "Bearer token123"

    // read the request body (for POST/PUT)
    body, _ := io.ReadAll(r.Body)
}
```

### What a handler writes

`w http.ResponseWriter` is where you write the response back to the client:

```go
func handler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.WriteHeader(200)                    // status code
    w.Write([]byte(`{"status": "ok"}`))   // body
}
```

### http.HandlerFunc — the type

Go defines a named type for handler functions:

```go
type HandlerFunc func(ResponseWriter, *Request)
```

This means your handler function IS a value — you can pass it around, wrap it, store it in a variable, all because functions are first-class in Go.

```go
var h http.HandlerFunc = getUsers   // store it in a variable
h(w, r)                             // call it directly
```

---

## 9. What is Middleware — and How the Chain Works

### The problem

You have 10 endpoints and need to log every request, check authentication, and track response times — without copying that code into every handler.

### What middleware is

Middleware is a function that:

1. Takes a handler as input
2. Returns a new handler that does something extra before and/or after calling the original

```go
func withLogging(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        log.Printf("→ %s %s", r.Method, r.URL.Path)   // BEFORE
        next(w, r)                                      // call original handler
        log.Printf("← done")                           // AFTER
    }
}
```

The key insight: `withLogging` returns a **new function** that wraps `next`. The original handler is untouched — it has no idea logging is happening.

### How `next` works — the handoff

`next` is just a captured variable — it's the handler you passed in. When the middleware calls `next(w, r)`, it's calling the original handler and passing the same `w` and `r` along:

```go
func withLogging(next http.HandlerFunc) http.HandlerFunc {
    //              ↑
    //   next = getUsers (captured here)

    return func(w http.ResponseWriter, r *http.Request) {
        log.Println("before")
        next(w, r)   // ← calls getUsers(w, r)
        log.Println("after")
    }
}

http.HandleFunc("/users", withLogging(getUsers))
//                                     ↑
//              next = getUsers is locked in at registration time
```

When a request comes in, the flow is:

```
request arrives
    ↓
withLogging's returned function runs
    ↓
logs "before"
    ↓
next(w, r) → calls getUsers(w, r)
    ↓
getUsers does its work, writes response
    ↓
back in withLogging
    ↓
logs "after"
    ↓
response sent to client
```

### Stacking middleware — the chain

You can wrap multiple middleware together:

```go
func withAuth(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        token := r.Header.Get("Authorization")
        if token == "" {
            http.Error(w, "unauthorized", 401)
            return   // stops here — next is NEVER called
        }
        next(w, r)   // auth passed — continue to actual handler
    }
}

// Stack: logging wraps auth wraps handler
http.HandleFunc("/users", withLogging(withAuth(getUsers)))
```

Reading inside-out: `withAuth(getUsers)` creates an auth-protected version of getUsers. `withLogging(...)` wraps that with logging.

Request flow through the chain:

```
request
    ↓
withLogging    → logs "before"
    ↓
withAuth       → checks token
    ↓               if no token: writes 401, returns — chain STOPS here
getUsers       → does the work
    ↓
withAuth       → (nothing after next)
    ↓
withLogging    → logs "after"
    ↓
response
```

### Middleware can stop the chain

If middleware doesn't call `next`, the chain stops there:

```go
func withAuth(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        if !isAuthenticated(r) {
            http.Error(w, "unauthorized", 401)
            return   // next is never called — handler never runs
        }
        next(w, r)
    }
}
```

The client gets a 401 and the request never reaches the actual handler.

### Why it's a closure

The inner function returned by `withLogging` is a closure — it captures `next` from the outer scope:

```go
func withLogging(next http.HandlerFunc) http.HandlerFunc {
    // next is captured here ↓
    return func(w http.ResponseWriter, r *http.Request) {
        log.Println("before")
        next(w, r)   // uses captured next — still accessible here
    }
}
```

When `withLogging(getUsers)` is called, `next` = `getUsers` is locked in. The returned function remembers it forever — every request that comes in calls the right handler.

### A complete example

```go
package main

import (
    "fmt"
    "log"
    "net/http"
    "time"
)

// Middleware 1: logging
func withLogging(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        log.Printf("→ %s %s", r.Method, r.URL.Path)
        next(w, r)
        log.Printf("← %s %s took %v", r.Method, r.URL.Path, time.Since(start))
    }
}

// Middleware 2: authentication
func withAuth(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        token := r.Header.Get("Authorization")
        if token != "secret-token" {
            http.Error(w, "unauthorized", http.StatusUnauthorized)
            return
        }
        next(w, r)
    }
}

// The actual handler — knows nothing about logging or auth
func getUsers(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintln(w, `{"users": ["Alice", "Bob"]}`)
}

func main() {
    // Each request: logging → auth → handler
    http.HandleFunc("/users", withLogging(withAuth(getUsers)))
    http.ListenAndServe(":8080", nil)
}
```

---

## 10. defer — Deep Dive

`defer` schedules a function call to run **after** the surrounding function returns. Deferred calls run in **LIFO (last-in, first-out)** order.

### 10.1 Basic usage and LIFO order

```go
func main() {
    defer fmt.Println("1")
    defer fmt.Println("2")
    defer fmt.Println("3")
    fmt.Println("main body")
}
// Output:
// main body
// 3
// 2
// 1
```

### 10.2 Arguments are evaluated immediately

```go
func main() {
    i := 0
    defer fmt.Println("deferred, i =", i) // i captured as 0 NOW
    i++
    fmt.Println("current i =", i)
}
// Output:
// current i = 1
// deferred, i = 0
```

Closure reads value when it runs, not when registered:

```go
func main() {
    i := 0
    defer func() { fmt.Println("deferred, i =", i) }() // reads i later
    i++
    fmt.Println("current i =", i)
}
// Output:
// current i = 1
// deferred, i = 1
```

### 10.3 The canonical use case: guaranteed cleanup

```go
func readFile(path string) ([]byte, error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    defer f.Close() // always runs — even on panic or early return

    return io.ReadAll(f)
}
```

### 10.4 defer inside loops — resource exhaustion gotcha

```go
// BAD — all files stay open until processAll returns
func processAll(paths []string) error {
    for _, p := range paths {
        f, _ := os.Open(p)
        defer f.Close() // stacks up — all 1000 files open at once!
    }
    return nil
}

// GOOD — extract to a function so defer fires per iteration
func processAll(paths []string) error {
    for _, p := range paths {
        if err := processOne(p); err != nil {
            return err
        }
    }
    return nil
}

func processOne(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close() // fires when processOne returns — once per file
    return nil
}
```

---

## 11. panic and recover

### panic — stops normal execution

```go
func mustPositive(n int) int {
    if n < 0 {
        panic("n must be positive")
    }
    return n
}
```

When a function panics:

1. Execution stops immediately
2. Deferred functions run (LIFO)
3. Panic propagates up the call stack
4. If nothing recovers — program crashes with stack trace

### recover — only works inside a deferred function

```go
func safeDivide(a, b int) (result int, err error) {
    defer func() {
        if r := recover(); r != nil {
            err = fmt.Errorf("recovered: %v", r)
        }
    }()
    return a / b, nil
}

r, err := safeDivide(10, 0)
fmt.Println(r, err) // 0 recovered: runtime error: integer divide by zero
```

> [!warning] panic/recover are NOT exceptions Use `error` return values for anything a caller might reasonably handle. `panic` is for unrecoverable programmer bugs — nil pointer, broken invariants, index out of range.

---

## 12. Generic Functions (Go 1.18+)

Generics let a single function work across multiple types while preserving type safety — no `interface{}`/`any` + type assertions needed.

### 12.1 The problem they solve

Without generics, the same logic has to be duplicated per type:

```go
func MaxInt(a, b int) int {
    if a > b { return a }
    return b
}

func MaxFloat(a, b float64) float64 {
    if a > b { return a }
    return b
}
```

Generics let you write this once.

### 12.2 Basic syntax — type parameters

```go
func Max[T cmp.Ordered](a, b T) T {
    if a > b {
        return a
    }
    return b
}
```

Breaking down the signature:

```
func Max [T cmp.Ordered] (a, b T) T
         ↑                  ↑      ↑
    type parameter      uses T   returns T
    + constraint
```

```go
fmt.Println(Max(3, 5))       // 5  (T = int)
fmt.Println(Max(2.5, 1.1))   // 2.5 (T = float64)
fmt.Println(Max("a", "b"))   // "b" (T = string)
```

`[T cmp.Ordered]` declares a type parameter `T` constrained to types supporting `<`, `>`, etc. (`cmp.Ordered` lives in the standard `cmp` package since Go 1.21).

### 12.3 Type inference — usually you don't write `[int]` etc.

```go
Max(3, 5)           // T inferred as int
Max[float64](1, 2)  // explicit instantiation — sometimes required
                     // when args alone don't disambiguate T
```

### 12.4 Constraints — what limits T

A constraint defines what operations are allowed on `T`. Without one, you can't assume anything:

```go
func Broken[T any](a, b T) bool {
    return a > b   // compile error — any doesn't guarantee > works
}
```

### 12.5 Built-in predeclared constraints

```go
any           // no constraint — accepts literally anything, alias for interface{}
comparable    // supports == and != (required for map keys)
```

```go
func Contains[T comparable](items []T, target T) bool {
    for _, item := range items {
        if item == target {   // comparable guarantees == works
            return true
        }
    }
    return false
}

Contains([]int{1, 2, 3}, 2)        // true
Contains([]string{"a", "b"}, "c")  // false
```

### 12.6 Standard library constraints — `cmp` package

```go
cmp.Ordered    // <, <=, >, >= — numbers and strings
```

### 12.7 Custom union constraints — listing specific types

```go
type Number interface {
    int | int8 | int16 | int32 | int64 | float32 | float64
}

func Sum[T Number](nums []T) T {
    var total T
    for _, n := range nums {
        total += n
    }
    return total
}

Sum([]int{1, 2, 3})         // 6
Sum([]float64{1.5, 2.5})    // 4.0
```

The `|` means "any one of these types" — `T` can be any of the listed types, and the operations used (`+=`) are guaranteed to work because all of them support it.

### 12.8 Constraints with underlying types — the `~` operator

```go
type Number interface {
    ~int | ~int64 | ~float64
}
```

`~` means "this type, or anything whose **underlying type** is this." This matters because Go lets you define named types based on others:

```go
type Celsius float64   // underlying type is float64

temps := []Celsius{20.5, 21.0}
Sum(temps)   // works because ~float64 matches Celsius too
```

> [!warning] Without `~`, named types don't satisfy the constraint `type Number interface { int | float64 }` (no `~`) would reject `Celsius` even though it behaves identically to `float64`. The `~` is what allows custom named types to satisfy a constraint based on their underlying type.

### 12.9 Constraints with method requirements

A constraint can require specific methods, just like a regular interface:

```go
type Stringer interface {
    String() string
}

func PrintAll[T Stringer](items []T) {
    for _, item := range items {
        fmt.Println(item.String())
    }
}
```

`T` must implement `String() string` — this works exactly like a normal interface constraint.

### 12.10 Combining type lists AND methods

```go
type Number interface {
    ~int | ~float64
    String() string   // must ALSO implement this
}
```

`T` must be based on `int` or `float64`, AND have a `String()` method.

### 12.11 Multiple type parameters

Functions can have more than one type parameter — they don't need to be related:

```go
func Map[T, U any](items []T, fn func(T) U) []U {
    result := make([]U, len(items))
    for i, item := range items {
        result[i] = fn(item)
    }
    return result
}

nums := []int{1, 2, 3}
strs := Map(nums, func(n int) string {
    return fmt.Sprintf("num-%d", n)
})
// ["num-1" "num-2" "num-3"]
```

`T` is the input type, `U` is the output type — Go infers both from how you call the function.

```go
func Keys[K comparable, V any](m map[K]V) []K {
    keys := make([]K, 0, len(m))
    for k := range m {
        keys = append(keys, k)
    }
    return keys
}
```

### 12.12 Linked container constraints — `S ~[]E`

This pattern links a slice type to its element type — used in the real standard library `slices` package:

```go
func SumSlice[S ~[]E, E Number](nums S) E {
    var total E
    for _, n := range nums {
        total += n
    }
    return total
}
```

`S` represents "any slice type," `E` represents its element type. This lets the function work on both a plain `[]int` and a custom named slice type like `type Scores []int`.

### 12.13 Quick reference — kinds of type parameters

|Kind|Example|What it allows|
|---|---|---|
|`any`|`[T any]`|Anything at all|
|`comparable`|`[T comparable]`|`==`, `!=` — usable as map key|
|`cmp.Ordered`|`[T cmp.Ordered]`|`<`, `<=`, `>`, `>=`|
|Union|`int \| float64`|Exactly these types|
|Underlying (`~`)|`~int \| ~float64`|These types or anything based on them|
|Method requirement|`interface { String() string }`|Must implement these methods|
|Multiple params|`[T, U any]`|Independent types, often linked by a function|
|Linked container|`[S ~[]E, E any]`|A slice type and its element type together|

### 12.14 A practical generic — Filter

```go
func Filter[T any](items []T, predicate func(T) bool) []T {
    var result []T
    for _, item := range items {
        if predicate(item) {
            result = append(result, item)
        }
    }
    return result
}

nums := []int{1, 2, 3, 4, 5, 6}
evens := Filter(nums, func(n int) bool { return n%2 == 0 })
// [2 4 6]

names := []string{"Alice", "Bob", "Anna"}
aNames := Filter(names, func(s string) bool { return strings.HasPrefix(s, "A") })
// [Alice Anna]
```

Same `Filter` function works on `[]int`, `[]string`, or any slice type — no duplication needed.

> [!tip] When to reach for generics Generics shine for **container/algorithm code** (`Map`, `Filter`, `Reduce`, generic data structures like sets and trees). For most everyday application code, plain functions with concrete types remain simpler and more idiomatic. In everyday Go code you'll mostly use `any`, `comparable`, and simple union constraints (`int | float64`) — `~` and linked container constraints (`S ~[]E`) mainly show up when writing generic library code meant to work with custom named types. Go's own standard library uses generics sparingly — `slices` and `maps` packages being the main examples.

---

## 13. init() — Package Initialization Functions

```go
func init() {
    // setup code, runs before main()
}
```

- Takes no arguments, returns nothing
- A single file or package can have **multiple `init()` functions**
- Package-level variables initialize first, then `init()`, then `main()`
- Across packages: a package's `init()` runs after all imported packages' `init()` functions

```go
var config Config

func init() {
    config = loadConfig()
}

func main() {
    fmt.Println(config) // already populated
}
```

> [!warning] Use `init()` sparingly Overuse makes initialization order implicit and hard to trace. Prefer explicit constructor functions called from `main()`.

---

## 14. main() — The Entry Point

```go
func main() {
    // program starts here
}
```

- Exists only in `package main`
- Takes no arguments, returns nothing
- Command-line args accessed via `os.Args`
- When `main()` returns, program exits with status 0

> [!warning] `os.Exit` skips deferred functions `defer` statements do **not** run if `os.Exit()` is called — it terminates immediately.

---

## 15. Recursion

Go supports recursion — a function calling itself:

```go
func factorial(n int) int {
    if n <= 1 {
        return 1
    }
    return n * factorial(n-1)
}
```

### Mutual recursion

```go
func isEven(n int) bool {
    if n == 0 { return true }
    return isOdd(n - 1)
}

func isOdd(n int) bool {
    if n == 0 { return false }
    return isEven(n - 1)
}
```

### Stack growth

Go goroutine stacks start small (a few KB) and **grow automatically** up to 1 GB on 64-bit systems. Moderately deep recursion is fine. Unbounded recursion will panic with `fatal error: stack overflow` — which cannot be recovered.

> [!tip] No tail-call optimization Go does not perform TCO. Very deep recursion still consumes one stack frame per call. For huge datasets, prefer explicit iteration with a stack/slice.

---

## 16. Methods vs. Functions — Quick Orientation

Methods are functions with a **receiver** argument:

```go
type Rectangle struct{ Width, Height float64 }

// Value receiver — operates on a COPY
func (r Rectangle) Area() float64 {
    return r.Width * r.Height
}

// Pointer receiver — operates on the ORIGINAL
func (r *Rectangle) Scale(factor float64) {
    r.Width *= factor
    r.Height *= factor
}
```

- **Value receiver**: use for small, read-only methods (`Area()`, `String()`)
- **Pointer receiver**: required for methods that mutate, or for large structs

```go
r := Rectangle{Width: 3, Height: 4}

// Method value — receiver is baked in
getArea := r.Area
fmt.Println(getArea()) // 12

// Method expression — receiver becomes a parameter
areaOf := Rectangle.Area
fmt.Println(areaOf(r)) // 12
```

---

## 17. The Functional Options Pattern

Go has no function overloading or default parameter values. This pattern is the idiomatic substitute:

```go
type Server struct {
    host    string
    port    int
    timeout time.Duration
}

type Option func(*Server)

func WithPort(port int) Option {
    return func(s *Server) { s.port = port }
}

func WithTimeout(d time.Duration) Option {
    return func(s *Server) { s.timeout = d }
}

func NewServer(host string, opts ...Option) *Server {
    s := &Server{
        host:    host,
        port:    8080,
        timeout: 30 * time.Second,
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage
s1 := NewServer("localhost")
s2 := NewServer("localhost", WithPort(9090), WithTimeout(5*time.Second))
```

Each `With*` function is a closure that captures its argument and modifies the server when called. Callers specify only what they care about, in any order.

---

## 18. No Function Overloading, No Default Arguments

Go deliberately does not support:

- **Overloading**: two functions with the same name and different parameters — use different names instead (`ParseInt`, `ParseFloat`)
- **Default values**: `func greet(name string, greeting string = "Hello")` is invalid

Workaround for defaults:

```go
func GreetWithMessage(name, greeting string) string {
    return greeting + ", " + name + "!"
}

func Greet(name string) string {
    return GreetWithMessage(name, "Hello")
}
```

---

## 19. Order of Evaluation

Go guarantees function arguments are evaluated **left to right**:

```go
func a() int { fmt.Println("a"); return 1 }
func b() int { fmt.Println("b"); return 2 }

sum := a() + b()
// Always prints "a" then "b"
```

---

## 20. Common Pitfalls — Quick Reference Table

|Pitfall|What happens|Fix|
|---|---|---|
|`append` inside a function|Caller's slice header unchanged|Return new slice, reassign: `s = grow(s)`|
|Large structs by value in hot code|Full copy on every call|Pass `*T` instead|
|`defer fn(x)` expecting future value of x|x captured immediately|Use `defer func(){ ...x... }()`|
|`defer` inside a loop|All resources held until function returns|Extract loop body into its own function|
|Closures over loop variables (Go < 1.22)|All closures see final value|Shadow: `i := i` inside loop|
|`recover()` outside deferred function|Returns nil, does nothing|Must be inside `defer func(){ }()`|
|Calling a nil function value|Runtime panic|Check `if f != nil` before calling|
|`os.Exit()` in main|Skips all defers|Avoid except as very last thing|
|Comparing two functions with `==`|Compile error|Functions only comparable to nil|
|Naked return in long function|Returns named values, unreadable|Use explicit `return x, y`|

---

## 21. Performance Notes

### Inlining

The Go compiler inlines small, simple functions automatically. Inspect with:

```bash
go build -gcflags="-m" ./...
```

Functions with `defer`, closures capturing variables, or complex control flow are less likely to be inlined.

### Pointers vs values

- Large struct by value → copies all bytes every call
- Pointer → avoids copy, but may escape to heap (GC pressure)

```bash
go build -gcflags="-m" file.go   # shows "escapes to heap" diagnostics
```

> [!tip] For small structs (a few primitive fields), pass by value. For large structs or mutation, pass by pointer. Don't micro-optimize without profiling.

### defer cost

Go 1.14+ "open-codes" simple, non-loop `defer` statements — essentially free in common cases. `defer` inside a loop falls back to the slower heap-allocated path.

---

## 22. Best Practices Checklist

- Keep functions small and single-purpose
- Error as the last return value, named `err` by convention
- Use named returns sparingly — mainly with `defer`/`recover`
- Avoid naked returns in anything longer than ~10 lines
- Prefer pointer receivers for methods that mutate, value receivers for small read-only methods
- Don't defer inside loops — extract a helper function instead
- Use the functional options pattern instead of long parameter lists
- Reserve `panic` for programmer errors; return `error` for anything a caller might handle
- Be explicit about loop-variable capture in goroutines/closures even on Go 1.22+
- Check `go.mod`'s `go` directive version when debugging closure behavior in older codebases

---

## 23. Cheat Sheet — Syntax at a Glance

```go
// Basic
func name(p1 T1, p2 T2) ReturnType { ... }

// Multiple returns
func name() (T1, T2) { return v1, v2 }

// Named returns
func name() (a T1, b T2) { a = v1; b = v2; return }

// Variadic
func name(args ...T) { ... }
name(slice...)              // spread

// Function type
type Fn func(T1, T2) T3

// Anonymous function / closure
f := func(x T) T { return x }

// Generic function
func Name[T Constraint](x T) T { ... }
func Name[T any](x T) T { ... }                  // no constraint
func Name[T comparable](x T) bool { ... }        // == and !=
func Name[T cmp.Ordered](a, b T) T { ... }       // <, <=, >, >=
type Number interface { int | float64 }          // union constraint
type Number interface { ~int | ~float64 }        // underlying-type constraint
func Name[T, U any](x T) U { ... }               // multiple type params
func Name[S ~[]E, E any](s S) E { ... }          // linked container constraint

// Method (value vs pointer receiver)
func (r Type) Method() { ... }
func (r *Type) Method() { ... }

// Method value / expression
mv := instance.Method        // bound to instance
me := Type.Method            // receiver becomes first arg

// Handler
func handler(w http.ResponseWriter, r *http.Request) { ... }
http.HandleFunc("/path", handler)

// Middleware
func withSomething(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        // before
        next(w, r)   // call the wrapped handler
        // after
    }
}
http.HandleFunc("/path", withLogging(withAuth(handler)))

// Defer / panic / recover
defer cleanup()
defer func() { recover() }()
panic("message")
```

---

_Previous: [[Go - Control Flow]] · Next: [[Arrays & Slices]]_