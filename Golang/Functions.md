Functions are the core unit of behavior in Go. Unlike many languages, Go keeps functions deliberately simple at the syntax level but layers a _lot_ of nuance on top: value semantics, multiple returns, closures, `defer`, variadics, generics, and functions-as-types. This note covers all of it, with runnable examples and the gotchas that bite people in practice.
## Contents

- [[#1. Basic Syntax]]
- [[#2. Parameters — Go Is Always Pass-By-Value]]
- [[#3. Return Values]]
- [[#4. Variadic Functions]]
- [[#5. Functions Are Values (First-Class Functions)]]
- [[#6. Anonymous Functions & Function Literals]]
- [[#7. Closures]]
- [[#8. `defer` — Deep Dive]]
- [[#9. `panic` and `recover`]]
- [[#10. Generic Functions (Go 1.18+)]]
- [[#11. `init()` — Package Initialization Functions]]
- [[#12. `main()` — The Entry Point]]
- [[#13. Recursion]]
- [[#14. Methods vs. Functions — Quick Orientation]]
- [[#15. The Functional Options Pattern]]
- [[#16. No Function Overloading, No Default Arguments]]
- [[#17. Order of Evaluation]]
- [[#18. Common Pitfalls — Quick Reference Table]]
- [[#19. Performance Notes]]
- [[#20. Best Practices Checklist]]
- [[#21. Cheat Sheet — Syntax at a Glance]]

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

**Every argument passed to a function is copied.** This is true for `int`, `struct`, arrays, pointers, slices, maps — everything. The _difference_ in behavior comes from **what is being copied**.

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

### 2.3 Arrays — copied entirely (this surprises people coming from C/JS)

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

### 2.4 Slices, Maps, Channels — the "header" is copied, but it shares the underlying data

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

But **reassigning the slice itself** (changing length/pointer/cap) inside the function does **not** affect the caller's variable, because that only changes the local copy of the header:

```go
func appendOne(s []int) {
    s = append(s, 99) // may or may not touch shared array, but
                       // the new header is local — caller never sees it
}

func main() {
    s := []int{1, 2, 3}
    appendOne(s)
    fmt.Println(s) // [1 2 3] — length unchanged!
}
```

> [!warning] The classic slice-mutation gotcha `append` inside a function is **invisible to the caller** unless the function returns the new slice and the caller reassigns it. This is why so many Go functions look like `func addItem(s []int, item int) []int { return append(s, item) }` — and why `s = addItem(s, 4)` is a required pattern, not a style choice.

Maps behave more simply: a map value is _itself_ a pointer to an internal hash table structure, so mutations like `m[key] = value` or `delete(m, key)` inside a function are always visible to the caller — but reassigning the map variable (`m = map[string]int{}`) is not.

### 2.5 Summary table

|Type passed|What's copied|Mutation via index/field visible to caller?|Reassignment visible?|
|---|---|---|---|
|`int`, `string`, `bool`, `struct`|Full value|N/A|No|
|Array `[N]T`|Full array (all N elements)|No (operates on copy)|No|
|Pointer `*T`|The pointer (address)|Yes (dereferenced write)|No|
|Slice `[]T`|Header (ptr, len, cap)|Yes, for existing elements|No (re-slicing/append not seen)|
|Map|Reference to hashtable|Yes (add/update/delete keys)|No|
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

This is one of Go's signature features — no need for tuples, output parameters, or wrapper structs for simple cases.

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

You can name the return values in the signature. This pre-declares variables you can assign to inside the function body, and creates self-documenting signatures:

```go
func divmod(a, b int) (q, r int) {
    q = a / b
    r = a % b
    return // "naked" return — returns current values of q and r
}
```

### 3.4 Naked returns — convenient but risky

A bare `return` with named returns sends back whatever the named variables currently hold.

```go
func split(sum int) (x, y int) {
    x = sum * 4 / 9
    y = sum - x
    return
}
```

> [!warning] Naked returns hurt readability in long functions. In a 50-line function, `return` on its own gives the reader **zero information** about what's being returned — they have to scroll back to find the last assignment to each named return value. The Go team's own style guidance: naked returns are fine in **short** functions (a handful of lines) and actively discouraged in long ones. Prefer explicit `return q, r`.

### 3.5 Named returns + `defer` — the "magic" interaction
	
This is a famous Go idiom and a famous gotcha at the same time: a deferred function **can modify named return values** because they're just variables in the enclosing scope, and `defer` runs _after_ `return` assigns to them but _before_ the function actually exits.

```go
func increment() (result int) {
    defer func() {
        result++ // mutates the named return value
    }()
    return 10
}

fmt.Println(increment()) // 11, not 10!
```

This pattern is the standard way to wrap errors or recover from panics while still being able to "edit" the return value:

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

> [!tip] If your return values are **unnamed**, a deferred function cannot alter them — there's nothing to assign to. This is the #1 reason to use named returns even when you don't care about the names for documentation purposes.

### 3.6 The blank identifier `_`

Use `_` to explicitly discard a return value you don't need:

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

Use `...` to "unpack" an existing slice as variadic arguments:

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

Inside the function body, `nums` has type `[]int` — you can `range` over it, index it, pass it to other functions, check `len(nums)`, etc.

> [!warning] Nil vs empty slice for variadic args If you call `sum()` with zero arguments, `nums` inside the function is `nil` (not an empty non-nil slice). For most operations (`len`, `range`, `append`) this is indistinguishable from an empty slice — but if your function does something like `nums == nil` checks or JSON-marshals the slice, the distinction matters (`nil` marshals to `null`, `[]int{}` marshals to `[]`).

### 4.4 The famous example: `fmt.Println`

```go
func Println(a ...interface{}) (n int, err error)
```

This is _why_ `fmt.Println(1, "two", 3.0, true)` accepts any number of arguments of any type — `interface{}` (or `any` since Go 1.18) plus variadic is the combination that gives you "accept literally anything, any amount."

---

## 5. Functions Are Values (First-Class Functions)

In Go, functions are values like any other — they have types, can be stored in variables, passed as arguments, returned from other functions, and stored in data structures.

### 5.1 Function types

```go
type BinOp func(int, int) int

var op BinOp = func(a, b int) int { return a + b }
fmt.Println(op(2, 3)) // 5
```

A variable can hold a reference to _any_ function matching that signature:

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

This is the foundation of Go's `sort.Slice`, middleware patterns, callbacks, and the `strings` package's `*Func` family (`strings.TrimFunc`, `strings.IndexFunc`, etc.):

```go
words := []string{"banana", "kiwi", "apple"}
sort.Slice(words, func(i, j int) bool {
    return len(words[i]) < len(words[j]) // sort by length
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

A very idiomatic Go pattern: a map from string to function, used as a command dispatcher.

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

### 5.5 Function types satisfying interfaces — the adapter pattern

A function type can have methods, which lets a bare function satisfy an interface. The canonical real-world example is `http.HandlerFunc`:

```go
type HandlerFunc func(ResponseWriter, *Request)

func (f HandlerFunc) ServeHTTP(w ResponseWriter, r *Request) {
    f(w, r) // calls the underlying function
}
```

This lets you write a plain function and pass it anywhere an `http.Handler` interface is expected, because `HandlerFunc` _is_ both a function type and an interface implementer.

### 5.6 Functions are not comparable (except to `nil`)

```go
var f func()
fmt.Println(f == nil) // true — valid

f2 := func() {}
// fmt.Println(f == f2) // COMPILE ERROR: func can only be compared to nil
```

The **zero value** of a function type is `nil`. Calling a `nil` function panics:

```go
var f func()
f() // panic: runtime error: invalid memory address or nil pointer dereference
```

---

## 6. Anonymous Functions & Function Literals

A function literal is a function defined inline, without a name. Anonymous functions are used for:

- Closures (next section)
- One-off goroutines: `go func() { ... }()`
- Deferred cleanup: `defer func() { ... }()`
- Immediately-invoked function expressions (IIFEs)

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

---

## 7. Closures

A closure is a function literal that **references variables from outside its own body**. The function "closes over" those variables — it keeps a live reference to them, not a copy, and they persist as long as the closure is reachable (even after the enclosing function has returned).

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

Each call to `makeCounter()` creates a **new** `count` variable on the heap (Go's escape analysis moves it there automatically because the closure outlives the function). `c1` and `c2` each close over their own independent `count`.

### 7.2 Shared state between multiple closures

If two closures are created in the same scope, they share the _same_ captured variable:

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
fmt.Println(get()) // 2
```

### 7.3 The loop variable capture gotcha (version-dependent!)

This is one of the **most notorious gotchas in Go history**, and the language semantics actually _changed_ in **Go 1.22 (Feb 2024)**.

**Go 1.22 and later** — each iteration of a `for` loop gets its **own** copy of the loop variable:

```go
funcs := make([]func(), 3)
for i := 0; i < 3; i++ {
    funcs[i] = func() { fmt.Println(i) }
}
for _, f := range funcs {
    f()
}
// Go 1.22+: prints 0, 1, 2
```

**Before Go 1.22** — there was a **single shared `i`** variable reused across all iterations. By the time the closures ran, `i` had its final post-loop value:

```go
// Pre-1.22 behavior: prints 3, 3, 3
```

> [!warning] Why this still matters Even though Go 1.22+ "fixed" this, you'll still encounter:
> 
> - Old code/tutorials relying on the old behavior (rare, but exists)
> - Modules built with `go 1.21` or earlier in `go.mod` — the loop semantics are tied to the `go` directive version in `go.mod`, not just your compiler version!
> - Interview questions and code review discussions that assume the old behavior
> 
> **The defensive pattern** (still widely seen and still 100% correct on any version) is to shadow the variable inside the loop body:
> 
> ```go
> for i := 0; i < 3; i++ {
>     i := i // create a new variable scoped to this iteration
>     funcs[i] = func() { fmt.Println(i) }
> }
> ```

### 7.4 The same gotcha with `range` over slices

```go
items := []string{"a", "b", "c"}
var funcs []func()
for _, item := range items {
    funcs = append(funcs, func() { fmt.Println(item) })
}
for _, f := range funcs {
    f()
}
// Go 1.22+: a, b, c
// Pre-1.22:  c, c, c
```

### 7.5 Closures and goroutines — a live production bug pattern

This is the same root issue but appears constantly in concurrent code, **and pre-1.22 it caused real race conditions**:

```go
// DANGEROUS on Go < 1.22 (and still worth being explicit about):
for _, url := range urls {
    go func() {
        fetch(url) // pre-1.22: all goroutines might see the SAME final `url`
    }()
}

// Always-safe version (pass as argument — copies the value):
for _, url := range urls {
    go func(u string) {
        fetch(u)
    }(url)
}
```

> [!tip] Even on Go 1.22+, passing loop values explicitly as function arguments (rather than relying on closure capture) remains a good habit — it's self-documenting and version-independent.

---

## 8. `defer` — Deep Dive

`defer` schedules a function call to run **after** the surrounding function returns (but before it actually hands control back to its caller). Deferred calls run in **LIFO (last-in, first-out)** order.

### 8.1 Basic usage and LIFO order

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

### 8.2 Arguments are evaluated immediately; the call is deferred

This trips up almost everyone at least once:

```go
func main() {
    i := 0
    defer fmt.Println("deferred, i =", i) // i is evaluated NOW → captures 0
    i++
    fmt.Println("current i =", i)
}
// Output:
// current i = 1
// deferred, i = 0
```

If you instead defer a **closure**, the closure's _body_ runs later and reads the variable's value **at that later time**:

```go
func main() {
    i := 0
    defer func() { fmt.Println("deferred, i =", i) }() // body runs later, reads i then
    i++
    fmt.Println("current i =", i)
}
// Output:
// current i = 1
// deferred, i = 1
```

### 8.3 The canonical use case: guaranteed cleanup

```go
func readFile(path string) ([]byte, error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    defer f.Close() // runs no matter how the function exits — error, panic, normal return

    return io.ReadAll(f)
}
```

### 8.4 `defer` inside loops — resource exhaustion gotcha

```go
func processAll(paths []string) error {
    for _, p := range paths {
        f, err := os.Open(p)
        if err != nil {
            return err
        }
        defer f.Close() // BAD: all files stay open until processAll RETURNS, not per-iteration!
        // ... process f ...
    }
    return nil
}
```

If `paths` has thousands of entries, you'll hold thousands of open file descriptors simultaneously and likely hit the OS limit. **Fix**: wrap the loop body in its own function so `defer` fires each iteration:

```go
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
    // ... process f ...
    return nil
}
```

### 8.5 `defer` has a small but nonzero cost

Each `defer` historically required a small heap allocation and bookkeeping. Since Go 1.14, the compiler "open-codes" most `defer` calls (inlining the cleanup directly), making them nearly free in common cases. Still, in extremely hot loops, avoid `defer` inside the loop body if performance profiling shows it matters — but **don't prematurely optimize this**; readability/correctness wins almost always.

---

## 9. `panic` and `recover`

### 9.1 `panic` — stops normal execution

```go
func mustPositive(n int) int {
    if n < 0 {
        panic("n must be positive")
    }
    return n
}
```

When a function panics:

1. Execution of the function stops immediately.
2. Any deferred functions in that function run (in LIFO order).
3. The panic propagates up to the caller, which also stops and runs its defers — and so on up the call stack.
4. If nothing recovers, the program crashes with a stack trace.

### 9.2 `recover` — only works inside a deferred function

`recover()` stops the panic propagation and returns the value passed to `panic()`. **It only has an effect when called directly inside a deferred function** during an active panic. Calling it anywhere else simply returns `nil` and does nothing.

```go
func safeDivide(a, b int) (result int, err error) {
    defer func() {
        if r := recover(); r != nil {
            err = fmt.Errorf("recovered from panic: %v", r)
        }
    }()
    return a / b, nil // panics with "division by zero" if b == 0
}

r, err := safeDivide(10, 0)
fmt.Println(r, err) // 0 recovered from panic: runtime error: integer divide by zero
```

### 9.3 `panic`/`recover` are NOT exceptions — use sparingly

> [!warning] Go idiom: errors for expected failure, panic for programmer bugs Idiomatic Go uses **`error` return values** for anything an honest caller might need to handle (file not found, invalid input, network timeout). `panic` is reserved for **unrecoverable programmer errors** — nil pointer dereference, index out of range, broken invariants — situations that indicate a _bug_, not a normal failure mode.
> 
> A common exception: libraries sometimes use `panic`/`recover` _internally_ to unwind deep recursive parsers cleanly, then recover at the top level and convert to a normal `error` — as long as the panic never escapes the package's public API.

---

## 10. Generic Functions (Go 1.18+)

Generics let a single function work across multiple types while preserving type safety (no `interface{}`/`any` + type assertions needed).

### 10.1 Basic syntax — type parameters

```go
func Max[T cmp.Ordered](a, b T) T {
    if a > b {
        return a
    }
    return b
}

fmt.Println(Max(3, 5))       // 5  (T = int)
fmt.Println(Max(2.5, 1.1))   // 2.5 (T = float64)
fmt.Println(Max("a", "b"))   // "b" (T = string)
```

`[T cmp.Ordered]` declares a type parameter `T` constrained to types supporting `<`, `>`, etc. (`cmp.Ordered` lives in the standard `cmp` package since Go 1.21).

### 10.2 Type inference — usually you don't write `[int]` etc.

```go
Max(3, 5)        // T inferred as int
Max[float64](1, 2) // explicit instantiation also allowed, sometimes required
                    // when args alone don't disambiguate T
```

### 10.3 Common built-in constraints

|Constraint|Meaning|
|---|---|
|`any`|Alias for `interface{}` — no constraint at all|
|`comparable`|Types supporting `==` and `!=` (usable as map keys)|
|`cmp.Ordered`|Types supporting `<, <=, >, >=` (numbers, strings)|

### 10.4 A generic slice utility — `Filter`

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
// evens = [2 4 6]
```

### 10.5 Custom interface constraints

```go
type Number interface {
    int | int64 | float64
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

> [!tip] When to reach for generics Generics shine for **container/algorithm code** (`Map`, `Filter`, `Reduce`, generic data structures like sets and trees). For most everyday application code, plain functions with concrete types remain simpler and more idiomatic — Go's standard library itself uses generics sparingly (`slices`, `maps` packages being the main examples).

---

## 11. `init()` — Package Initialization Functions

```go
func init() {
    // setup code, runs before main()
}
```

- Takes **no arguments** and returns **nothing**.
- A single file or package can have **multiple `init()` functions**.
- Run order: package-level variable initializers run first, then `init()` functions, in the order they appear in the source (within a file, top to bottom; across files, in the order the compiler processes them — by filename, for the standard `gc` compiler).
- Across packages: a package's `init()` functions run only after all of its imported packages' `init()` functions have completed — dependency order is guaranteed.
- `main()`'s package `init()` functions (if any) run last, immediately before `main()` itself.

```go
var config Config

func init() {
    config = loadConfig()
}

func main() {
    fmt.Println(config) // config is already populated
}
```

> [!warning] Use `init()` sparingly Overuse of `init()` makes initialization order implicit and hard to trace, hides dependencies, and complicates testing (init runs even when you just want to import a package for one helper). Prefer explicit constructor functions (`NewServer(...)`, `LoadConfig(...)`) called from `main()` wherever practical.

---

## 12. `main()` — The Entry Point

```go
func main() {
    // program starts here
}
```

- Exists only in `package main`.
- Takes no arguments, returns nothing.
- Command-line args are accessed via `os.Args`, not function parameters.
- When `main()` returns, the program exits with status 0 (success) — unless `os.Exit(n)` was called explicitly with a different code.

> [!warning] `os.Exit` skips deferred functions! `defer` statements in `main()` (or anywhere up the stack) **do not run** if `os.Exit()` is called — it terminates immediately. This is a common source of "my cleanup didn't run" bugs.

---

## 13. Recursion

Go supports recursion normally — a function can call itself.

```go
func factorial(n int) int {
    if n <= 1 {
        return 1
    }
    return n * factorial(n-1)
}
```

### 13.1 Mutual recursion

```go
func isEven(n int) bool {
    if n == 0 {
        return true
    }
    return isOdd(n - 1)
}

func isOdd(n int) bool {
    if n == 0 {
        return false
    }
    return isEven(n - 1)
}
```

### 13.2 Stack growth — Go goroutine stacks are dynamic

Unlike languages with a fixed call stack size, **goroutine stacks start small (a few KB) and grow automatically** as needed, up to a default maximum of **1 GB on 64-bit systems** (configurable via `debug.SetMaxStack`). This means moderately deep recursion that would blow a fixed C-style stack is usually fine in Go — but extremely deep or unbounded recursion will still eventually panic with `fatal error: stack overflow`, and the program **cannot recover from a stack overflow** (it's not a normal panic).

> [!tip] No tail-call optimization Go's compiler does **not** perform tail-call optimization. A "tail-recursive" function in Go still consumes stack frames for every call. If you need to process huge datasets recursively, consider converting to an explicit loop with a stack/slice, or using iteration instead.

---

## 14. Methods vs. Functions — Quick Orientation

Methods are technically a special case of functions: a function with a **receiver** argument, declared between `func` and the method name.

```go
type Rectangle struct{ Width, Height float64 }

// Value receiver — operates on a COPY of the Rectangle
func (r Rectangle) Area() float64 {
    return r.Width * r.Height
}

// Pointer receiver — operates on the ORIGINAL via a pointer
func (r *Rectangle) Scale(factor float64) {
    r.Width *= factor
    r.Height *= factor
}
```

Key points (full depth belongs in a dedicated Methods/Interfaces note, but the essentials):

- **Value receiver**: the method gets a copy; mutations inside don't affect the original. Use for small, immutable-feeling reads (`Area()`, `String()`).
- **Pointer receiver**: the method gets a pointer; mutations are visible to the caller. Required for any method that needs to modify the receiver, and conventionally used for large structs to avoid copying.
- **Method sets and interfaces**: a value of type `T` has access to methods with receiver `T` only. A value of type `*T` has access to methods with receiver `T` _and_ `*T`. This matters for interface satisfaction — if `Scale` has a pointer receiver, only `*Rectangle` (not `Rectangle`) satisfies an interface requiring `Scale()`.
- **Method values**: `r.Area` (without calling it) is a function value bound to `r` — `f := r.Area; f()` works just like `r.Area()`.
- **Method expressions**: `Rectangle.Area` is a function with the receiver as an explicit first parameter: `f := Rectangle.Area; f(r)`.

```go
r := Rectangle{Width: 3, Height: 4}
getArea := r.Area        // method value — r is "baked in"
fmt.Println(getArea())   // 12

areaOf := Rectangle.Area  // method expression — r becomes a parameter
fmt.Println(areaOf(r))    // 12
```

---

## 15. The Functional Options Pattern

A widely-used idiom that combines **variadic parameters + closures + function types** to handle optional configuration cleanly — Go has no function overloading or default parameter values, so this is the idiomatic substitute.

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
        port:    8080,           // sensible defaults
        timeout: 30 * time.Second,
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

// Usage:
s1 := NewServer("localhost")                                  // all defaults
s2 := NewServer("localhost", WithPort(9090), WithTimeout(5*time.Second))
```

This avoids "telescoping constructors" (`NewServer(host, port, timeout, retries, tls, ...)`) and lets callers specify only what they care about, in any order.

---

## 16. No Function Overloading, No Default Arguments

Two things Go _deliberately_ does not support, which surprises newcomers from Python/Java/C++:

- **No overloading**: you cannot declare two functions with the same name and different parameter types/counts in the same scope. Workarounds: different function names (`ParseInt`, `ParseFloat`), variadic parameters, `interface{}`/generics, or the functional options pattern above.
- **No default parameter values**: `func greet(name string, greeting string = "Hello")` is **not valid Go**. Workarounds: variadic "options" structs, functional options, or simply requiring all arguments and providing a second convenience function:

```go
func GreetWithMessage(name, greeting string) string {
    return greeting + ", " + name + "!"
}

func Greet(name string) string {
    return GreetWithMessage(name, "Hello")
}
```

---

## 17. Order of Evaluation

The Go spec **guarantees** that function calls, method calls, and channel operations appearing as operands of an expression are evaluated in **strict left-to-right lexical order**.

```go
func a() int { fmt.Println("a"); return 1 }
func b() int { fmt.Println("b"); return 2 }

sum := a() + b()
// Always prints "a" then "b", regardless of compiler/platform
```

This matters when arguments have side effects:

```go
process(getNext(), getNext(), getNext()) // calls happen in order, left to right
```

---

## 18. Common Pitfalls — Quick Reference Table

|Pitfall|What happens|Fix|
|---|---|---|
|Expecting `append` inside a function to mutate caller's slice|Caller's slice header unchanged — length/data may not update|Return the new slice and reassign: `s = grow(s)`|
|Passing large structs/arrays by value in hot code|Full copy on every call — performance cost|Pass `*T` (pointer) instead|
|`defer fn(x)` expecting `x`'s _future_ value|Arguments evaluated immediately at `defer` time|Use `defer func(){ ...x... }()` to read `x` later|
|`defer resource.Close()` in a loop|All resources held until function returns, not per-iteration|Extract loop body into its own function|
|Closures over loop variables (Go < 1.22, or `go.mod` < 1.22)|All closures share one variable → see final value|Shadow: `i := i` inside the loop, or pass as a goroutine arg|
|Calling `recover()` outside a deferred function|Returns `nil`, does nothing — panic continues propagating|`recover()` must be called _directly_ inside `defer func(){...}()`|
|Calling a `nil` function value|Runtime panic: nil pointer dereference|Check `if f != nil` before calling, or always assign a default|
|`os.Exit()` in `main`|Skips all `defer` calls everywhere|Avoid `os.Exit` except as the very last thing, or restructure to return errors up to `main`|
|Comparing two functions with `==`|Compile error (funcs only comparable to `nil`)|Compare via wrapping in structs with comparable IDs, or avoid the comparison|
|Naked `return` in a long function|Returns named values, but unreadable at a glance|Use explicit `return x, y` except in trivial functions|

---

## 19. Performance Notes

### 19.1 Inlining

The Go compiler automatically **inlines** small, simple functions (no loops, limited complexity) directly at the call site, eliminating call overhead entirely. You can inspect inlining decisions with:

```bash
go build -gcflags="-m" ./...
```

Functions with `defer`, closures capturing variables, recursion, or complex control flow are less likely to be inlined.

### 19.2 Pointers vs. values — the tradeoff

- Passing a **large struct by value** copies all its bytes on every call — costly for big structs, cheap for small ones (a couple of `int64`s is often _faster_ by value than via pointer indirection).
- Passing a **pointer** avoids the copy, but if the compiler's escape analysis determines the pointer "escapes" (e.g., stored somewhere that outlives the function, or the function is not inlined and the pointer must remain valid), the value gets allocated on the **heap** instead of the stack — heap allocations add GC pressure.

```bash
go build -gcflags="-m" file.go   # shows "escapes to heap" diagnostics
```

> [!tip] Rule of thumb For small structs (a few fields, all primitives), pass by value. For large structs, or when the function needs to mutate the original, pass by pointer. Don't micro-optimize this without profiling — readability and correctness come first; Go's compiler is quite good at making the "natural" choice fast.

### 19.3 `defer` cost

As noted in §8.5, modern Go (1.14+) "open-codes" simple, non-loop `defer` statements, making them essentially free. `defer` inside a loop, or with more than ~8 deferred calls in one function, falls back to the slower heap-allocated path.

---

## 20. Best Practices Checklist

- **Keep functions small and single-purpose** — if you struggle to name it concisely, it's probably doing too much.
- **Error as the last return value**, named `err` by convention.
- **Use named returns sparingly** — mainly when combined with `defer`/`recover`, or when it meaningfully documents intent for short functions.
- **Avoid naked returns** in anything longer than ~10 lines.
- **Prefer pointer receivers for methods that mutate**, value receivers for small read-only methods — and be consistent within a type.
- **Don't defer inside loops** — extract a helper function instead.
- **Use the functional options pattern** instead of long parameter lists or boolean "flag" parameters.
- **Reserve `panic` for programmer errors**; return `error` for anything a caller might reasonably need to handle.
- **Be explicit about loop-variable capture** in goroutines/closures even on Go 1.22+ — pass values as arguments for clarity.
- **Check `go.mod`'s `go` directive version** when debugging "weird" closure behavior in older codebases — it changes loop semantics.

---

## 21. Cheat Sheet — Syntax at a Glance

```go
// Basic
func name(p1 T1, p2 T2) ReturnType { ... }

// Multiple returns
func name() (T1, T2) { return v1, v2 }

// Named returns
func name() (a T1, b T2) { a = v1; b = v2; return }

// Variadic
func name(args ...T) { ... }
name(slice...) // spread

// Function type
type Fn func(T1, T2) T3

// Anonymous function / closure
f := func(x T) T { return x }

// Generic function
func Name[T Constraint](x T) T { ... }

// Method (value vs pointer receiver)
func (r Type) Method() { ... }
func (r *Type) Method() { ... }

// Method value / expression
mv := instance.Method      // bound to instance
me := Type.Method           // receiver becomes first arg

// Defer / panic / recover
defer cleanup()
defer func() { recover() }()
panic("message")
```