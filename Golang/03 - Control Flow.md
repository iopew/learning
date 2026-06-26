# Go — Control Flow

> **Series:** Go Language Fundamentals **Tags:** #go #golang #controlflow #loops #conditionals #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. if / else]]
- [[#2. if with an initialiser]]
- [[#3. switch]]
- [[#4. Type switch]]
- [[#5. for — the only loop in Go]]
- [[#6. for as a while loop]]
- [[#7. Infinite loop]]
- [[#8. range]]
- [[#9. break and continue]]
- [[#10. Labels]]
- [[#11. goto]]
- [[#12. defer]]
- [[#13. defer + panic + recover]]
- [[#14. select]]
- [[#15. Control Flow Patterns]]
- [[#16. Quick Reference Cheatsheet]]

---

## 1. if / else

Go's `if` is standard — but no parentheses around the condition, and the braces `{}` are always required.

```go
x := 10

if x > 5 {
    fmt.Println("big")
} else if x == 5 {
    fmt.Println("exactly five")
} else {
    fmt.Println("small")
}
// Output: big
```

> [!info] No parentheses, always braces Go enforces this at compile time. `if (x > 5)` works but is redundant — the Go formatter (`gofmt`) removes the parens. `if x > 5 { ... }` without braces is a compile error.

---

## 2. if with an initialiser

### The syntax

A normal `if` is just a condition:

```go
if x > 5 {
    fmt.Println("big")
}
```

An `if` with an initialiser adds a statement before the condition, separated by `;`:

```go
if x := 10; x > 5 {
    fmt.Println("big")
}
```

The `;` separates two things:

```
if  DECLARE ; CONDITION {
    ↑              ↑
    runs first     checked second
```

- **Left of `;`** — declare and assign a variable
- **Right of `;`** — the condition that uses it

Both the `if` body and the `else` body can use the variable — but nothing outside the block can.

### The one thing that makes it different — scope

The variable only exists **inside the if/else block**. Once the block ends, it's gone.

```go
if x := 10; x > 5 {
    fmt.Println(x)  // fine
}
fmt.Println(x)      // compile error — x doesn't exist here
```

With the normal way, `x` survives outside:

```go
x := 10
if x > 5 {
    fmt.Println(x)
}
fmt.Println(x)  // fine — x still exists
```

### Use cases

The initialiser works for any value you only need inside the `if` — not just errors.

**Checking an error:**

```go
if err := doSomething(); err != nil {
    fmt.Println("error:", err)
}
// err is gone — you don't need it anymore
```

**Capturing multiple return values:**

```go
if n, err := fmt.Println("hello"); err != nil {
    log.Fatal(err)
} else {
    fmt.Println("wrote", n, "bytes")
}
// both n and err are gone after the block
```

**Checking a map lookup:**

```go
if val, ok := ages["Alice"]; ok {
    fmt.Println(val)
}
// val and ok are gone
```

**Checking a type assertion:**

```go
if str, ok := i.(string); ok {
    fmt.Println("it's a string:", str)
}
```

**Checking a computed value:**

```go
if score := calculate(); score > 100 {
    fmt.Println("high score!")
} else if score > 50 {
    fmt.Println("good score")
} else {
    fmt.Println("keep trying")
}
// score is gone
```

### Main purpose — keeping scope clean

Imagine a function with multiple error checks the normal way:

```go
// WITHOUT initialiser — err floats around the whole function
err := stepOne()
if err != nil { ... }

err = stepTwo()
if err != nil { ... }

err = stepThree()
if err != nil { ... }
// err is still alive here even though you're done with it
```

With the initialiser, each variable lives and dies with its own block:

```go
// WITH initialiser — each err is self-contained
if err := stepOne();   err != nil { ... }
if err := stepTwo();   err != nil { ... }
if err := stepThree(); err != nil { ... }
// no pollution, no accidental reuse
```

### When NOT to use it

If you need the variable **after** the `if` block, declare it outside — the initialiser will make it inaccessible:

```go
// DON'T — user is out of scope after the block
if user := getUser(id); user != nil {
    fmt.Println(user.Name)
}
fmt.Println(user)  // compile error!

// DO — declare outside if you need it later
user := getUser(id)
if user != nil {
    fmt.Println(user.Name)
}
fmt.Println(user)  // fine
```

### Decision rule

```
Do I need this variable after the if block?
├── YES → declare outside with :=
└── NO  → put it in the initialiser
```

---

## 3. switch

Go's `switch` is cleaner than most languages — no `break` needed between cases (they don't fall through by default), and the cases can be expressions.

```go
day := "Monday"

switch day {
case "Monday", "Tuesday", "Wednesday", "Thursday", "Friday":
    fmt.Println("weekday")
case "Saturday", "Sunday":
    fmt.Println("weekend")
default:
    fmt.Println("unknown")
}
// Output: weekday
```

### switch with no condition — replaces if/else chains

A `switch` with no expression is equivalent to `switch true`. Each case is evaluated as a boolean:

```go
score := 85

switch {
case score >= 90:
    fmt.Println("A")
case score >= 80:
    fmt.Println("B")
case score >= 70:
    fmt.Println("C")
default:
    fmt.Println("F")
}
// Output: B
```

### switch with an initialiser

Like `if`, `switch` also accepts an initialiser:

```go
switch os := runtime.GOOS; os {
case "darwin":
    fmt.Println("macOS")
case "linux":
    fmt.Println("Linux")
default:
    fmt.Println("Other:", os)
}
```

```go
switch err := doSomething(); err {
case nil:
    fmt.Println("success")
case io.EOF:
    fmt.Println("end of file")
default:
    fmt.Println("unexpected error:", err)
}
```
### fallthrough

	By default cases do NOT fall through. Use `fallthrough` explicitly when you want the next case to execute unconditionally:

```go
n := 3

switch n {
case 3:
    fmt.Println("three")
    fallthrough   // forces execution of next case
case 2:
    fmt.Println("two or less")
case 1:
    fmt.Println("one")
}
// Output:
// three
// two or less   ← executed because of fallthrough
```

> [!warning] fallthrough is unconditional `fallthrough` runs the next case body regardless of its condition. It cannot be used in the last case of a switch. Use it sparingly — it often makes code harder to read.

### Cases are evaluated top to bottom — order matters

Go evaluates cases in order and stops at the first match. Put the most specific or most likely cases first:

```go
switch {
case x > 100:
    fmt.Println("very large")  // checked first
case x > 50:
    fmt.Println("large")       // only reached if x <= 100
case x > 0:
    fmt.Println("positive")    // only reached if x <= 50
default:
    fmt.Println("zero or negative")
}
```

If you put `x > 0` first, it would match everything positive — the more specific cases below would never run.

### break inside switch

`break` inside a switch only exits the switch, not an enclosing loop. This trips up developers coming from other languages:

```go
// break exits the switch, NOT the loop
for i := 0; i < 5; i++ {
    switch i {
    case 3:
        break        // only exits the switch!
    }
    fmt.Println(i)   // 3 still prints
}
// 0 1 2 3 4

// To exit the loop from inside a switch, use a label
loop:
    for i := 0; i < 5; i++ {
        switch i {
        case 3:
            break loop   // exits the outer for loop
        }
        fmt.Println(i)
    }
// 0 1 2
```

### Empty case — explicit no-op

An empty case does nothing and does NOT fall through — unlike C:

```go
switch x {
case 0:
    // intentionally do nothing
case 1:
    fmt.Println("one")
}
```

---

## 4. Type switch

A type switch checks the **dynamic type** of an interface value. Essential when working with `interface{}` or `any`.

```go
func describe(i interface{}) {
    switch v := i.(type) {
    case int:
        fmt.Printf("int: %d\n", v)
    case string:
        fmt.Printf("string: %q\n", v)
    case bool:
        fmt.Printf("bool: %t\n", v)
    case []int:
        fmt.Printf("[]int with %d elements\n", len(v))
    default:
        fmt.Printf("unknown type: %T\n", v)
    }
}

describe(42)           // int: 42
describe("hello")      // string: "hello"
describe(true)         // bool: true
describe([]int{1,2,3}) // []int with 3 elements
describe(3.14)         // unknown type: float64
```

> [!info] `v := i.(type)` syntax Inside the switch, `v` automatically has the concrete type of the matched case — so inside `case int`, `v` is already an `int`, not an `interface{}`. This is why no casting is needed.

### Multiple types in one case

When you list multiple types in one case, `v` stays as `interface{}` — because it could be any of them:

```go
switch v := i.(type) {
case int, int64:
    fmt.Println("some integer:", v)   // v is interface{} here
case string, []byte:
    fmt.Println("some text:", v)      // v is interface{} here
}
```

If you need to work with the concrete value, use separate cases.

### Handling nil

A nil interface value has its own case:

```go
switch v := i.(type) {
case nil:
    fmt.Println("i is nil")
case int:
    fmt.Println("int:", v)
default:
    fmt.Printf("unknown type: %T\n", v)
}
```

---

## 5. for — the only loop in Go

Go has **one** loop keyword: `for`. It covers all loop patterns.

### Classic C-style for loop

```go
for i := 0; i < 5; i++ {
    fmt.Println(i)
}
// 0 1 2 3 4

// Count down
for i := 5; i > 0; i-- {
    fmt.Println(i)
}
// 5 4 3 2 1

// Step by 2
for i := 0; i <= 10; i += 2 {
    fmt.Println(i)
}
// 0 2 4 6 8 10
```

### The three parts explained

```
for  init ; condition ; post {
     ↑         ↑          ↑
     runs      checked    runs after
     once      before     each iteration
               each iter
```

- **init** — runs once before the loop starts. Usually declares the loop variable.
- **condition** — checked before every iteration. Loop stops when it becomes false.
- **post** — runs after every iteration. Usually increments or updates the counter.

### All three parts are optional

Any part can be omitted:

```go
i := 0
for ; i < 5; {   // init and post omitted — semicolons still needed
    fmt.Println(i)
    i++
}

for n < 100 {    // condition only — no semicolons needed
    n *= 2
}

for { }          // all omitted — infinite loop
```

> [!info] Semicolons rule Semicolons are only required when you keep the init or post part. A condition-only loop needs no semicolons at all: `for n < 100 { }`.

### The post statement is not limited to i++

The post runs after every iteration — it can be any simple statement, not just an increment:

```go
// Two variables moving toward each other
for i, j := 0, 10; i < j; i, j = i+1, j-1 {
    fmt.Println(i, j)
}
// 0 10
// 1 9
// 2 8
// 3 7
// 4 6
```

---

## 6. for as a while loop

Omit the init and post — just keep the condition:

```go
n := 1
for n < 100 {
    n *= 2
}
fmt.Println(n) // 128

// Reading input until a condition is met
scanner := bufio.NewScanner(os.Stdin)
for scanner.Scan() {
    line := scanner.Text()
    if line == "quit" {
        break
    }
    fmt.Println("You typed:", line)
}
```

---

## 7. Infinite loop

Omit everything — loop forever until a `break` or `return`:

```go
for {
    fmt.Println("running...")
    time.Sleep(time.Second)
    // break or return to exit
}
```

Common in servers, background workers, and game loops:

```go
func runServer() {
    for {
        conn, err := listener.Accept()
        if err != nil {
            log.Println(err)
            continue
        }
        go handleConnection(conn)
    }
}
```

---

## 8. range

`range` iterates over arrays, slices, maps, strings, and channels. It returns up to two values depending on the type.

### range over a slice

```go
fruits := []string{"apple", "banana", "cherry"}

for i, v := range fruits {
    fmt.Printf("%d: %s\n", i, v)
}
// 0: apple
// 1: banana
// 2: cherry

// Ignore index
for _, v := range fruits {
    fmt.Println(v)
}

// Ignore value (index only)
for i := range fruits {
    fmt.Println(i)
}
```

### range over a map

```go
ages := map[string]int{"Alice": 30, "Bob": 25}

for name, age := range ages {
    fmt.Printf("%s is %d\n", name, age)
}
// Order is NOT guaranteed — maps are unordered
```

### range over a string — yields runes, not bytes

```go
for i, ch := range "café" {
    fmt.Printf("index %d: %c\n", i, ch)
}
// index 0: c
// index 1: a
// index 2: f
// index 3: é   ← index 3, even though é is 2 bytes (3 and 4)
```

> [!tip] range on strings is always safe `range` automatically decodes UTF-8 and gives you whole runes. Indexing directly with `s[i]` gives you raw bytes — which can corrupt multi-byte characters.

### range over a channel

```go
ch := make(chan int)

go func() {
    for i := 0; i < 5; i++ {
        ch <- i
    }
    close(ch)
}()

for v := range ch {   // stops when channel is closed
    fmt.Println(v)
}
// 0 1 2 3 4
```

### range summary table

|Type|First value|Second value|
|---|---|---|
|array / slice|index|element|
|map|key|value|
|string|byte index|rune (character)|
|channel|element|— (one value only)|

### range copies the value — mutations don't affect the original

`range` gives you a **copy** of each element. Modifying `v` inside the loop does nothing to the original slice:

```go
nums := []int{1, 2, 3}

for _, v := range nums {
    v *= 10   // modifies the copy, not nums
}
fmt.Println(nums)  // [1 2 3] — unchanged!

// To modify the original, use the index
for i := range nums {
    nums[i] *= 10
}
fmt.Println(nums)  // [10 20 30]
```

### range over an array vs slice

`range` works on both arrays and slices. On an array, it ranges over a **copy** of the whole array if the array is assigned to a variable first — use a slice or pointer to avoid this:

```go
arr := [3]int{1, 2, 3}
for i, v := range arr {   // ranges over a copy of arr
    fmt.Println(i, v)
}
```

### range over an integer — Go 1.22+

Since Go 1.22, you can range directly over an integer to loop N times:

```go
// Replaces: for i := 0; i < 5; i++
for i := range 5 {
    fmt.Println(i)  // 0 1 2 3 4
}

// Useful for generating sequences
squares := make([]int, 5)
for i := range 5 {
    squares[i] = i * i
}
fmt.Println(squares)  // [0 1 4 9 16]
```

> [!info] Go version requirement `for i := range N` requires Go 1.22 or later. In older versions, use the classic `for i := 0; i < N; i++`.

---

## 9. break and continue

### break — exit the loop immediately

```go
for i := 0; i < 10; i++ {
    if i == 5 {
        break   // stops the loop entirely
    }
    fmt.Println(i)
}
// 0 1 2 3 4

// break also works in switch
switch x {
case 1:
    fmt.Println("one")
    break   // exits the switch (rarely needed — cases don't fall through)
}
```

### continue — skip to the next iteration

```go
for i := 0; i < 10; i++ {
    if i%2 == 0 {
        continue   // skip even numbers
    }
    fmt.Println(i)
}
// 1 3 5 7 9
```

### continue as a filter — cleaner than nesting

Using `continue` to skip unwanted items keeps the main logic at the top level instead of nested inside an `if`:

```go
// WITHOUT continue — main logic is nested
for _, user := range users {
    if user.Active {
        if user.Age >= 18 {
            process(user)
        }
    }
}

// WITH continue — guard clauses, flat structure
for _, user := range users {
    if !user.Active { continue }
    if user.Age < 18 { continue }
    process(user)
}
```

---

## 10. Labels

Labels let `break` and `continue` target an **outer** loop, not just the innermost one.

### break with a label

```go
outer:
    for i := 0; i < 3; i++ {
        for j := 0; j < 3; j++ {
            if i == 1 && j == 1 {
                break outer   // exits BOTH loops
            }
            fmt.Printf("i=%d j=%d\n", i, j)
        }
    }
// i=0 j=0
// i=0 j=1
// i=0 j=2
// i=1 j=0
// (stops here — break outer exits the outer loop)
```

### continue with a label

```go
outer:
    for i := 0; i < 3; i++ {
        for j := 0; j < 3; j++ {
            if j == 1 {
                continue outer   // skip to next iteration of OUTER loop
            }
            fmt.Printf("i=%d j=%d\n", i, j)
        }
    }
// i=0 j=0
// i=1 j=0
// i=2 j=0
// (j=1 and j=2 are always skipped)
```

---

## 11. goto

`goto` jumps to a labelled statement. Rarely used in Go — prefer loops and functions. One legitimate use is jumping out of deeply nested code in error handling.

```go
func process() error {
    result, err := step1()
    if err != nil {
        goto cleanup
    }

    err = step2(result)
    if err != nil {
        goto cleanup
    }

    return nil

cleanup:
    cleanupResources()
    return err
}
```

> [!warning] goto limitations You cannot jump over variable declarations, and you cannot jump into a block from outside it. In practice, `defer` is almost always a cleaner solution than `goto` for cleanup.

---

## 12. defer

`defer` schedules a function call to run **just before the surrounding function returns** — regardless of how it returns (normally, via `return`, or via `panic`).

```go
func main() {
    fmt.Println("start")
    defer fmt.Println("deferred 1")
    defer fmt.Println("deferred 2")
    defer fmt.Println("deferred 3")
    fmt.Println("end")
}
// Output:
// start
// end
// deferred 3   ← LIFO — last in, first out
// deferred 2
// deferred 1
```

### The most important use: cleanup

`defer` ensures cleanup always happens, even if the function panics or returns early:

```go
func readFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close()   // guaranteed to run when readFile returns

    // ... read the file ...
    return nil
}

func withMutex() {
    mu.Lock()
    defer mu.Unlock()   // always unlocked, even on panic

    // ... critical section ...
}

func withDB() {
    rows, err := db.Query("SELECT ...")
    if err != nil {
        return
    }
    defer rows.Close()   // always closed

    // ... process rows ...
}
```

### defer evaluates arguments immediately

The deferred function's **arguments** are evaluated at the `defer` statement, not when it executes:

```go
x := 10
defer fmt.Println(x)   // x is captured as 10 right now
x = 20
// Output: 10  ← not 20
```

But if the deferred function is a **closure**, it sees the current value:

```go
x := 10
defer func() {
    fmt.Println(x)   // x is read when defer runs
}()
x = 20
// Output: 20  ← sees the updated value
```

### defer in a loop — a common mistake

```go
// WRONG — all defers run AFTER the loop, not per iteration
for _, f := range files {
    defer f.Close()   // all closes stack up until function returns!
}

// RIGHT — wrap in a function to defer per iteration
for _, f := range files {
    func(f *os.File) {
        defer f.Close()
        process(f)
    }(f)
}
```

### defer with named return values

`defer` can read and modify **named return values** — useful for wrapping errors or cleanup that depends on the result:

```go
func readFile(path string) (err error) {
    f, err := os.Open(path)
    if err != nil {
        return
    }
    defer func() {
        closeErr := f.Close()
        if err == nil {
            err = closeErr   // only set close error if no other error occurred
        }
    }()

    // ... read file ...
    return
}
```

The deferred closure sees the named return variable `err` by reference — so it can inspect and change what the function ultimately returns.

> [!warning] Named returns + defer is advanced This pattern is useful but subtle. Misusing it can cause silent bugs where a deferred function accidentally overwrites a meaningful error. Only use it when you genuinely need to modify the return value.

---

## 13. defer + panic + recover

`panic` and `recover` are Go's mechanism for handling **truly unexpected situations** — things that should never happen in normal program flow.

---

### panic — what it is

When Go hits a panic, it immediately stops executing the current function and starts **unwinding the stack** — going back up through every function that called this one, running deferred functions along the way, until it either hits a `recover()` or crashes the program with a stack trace.

go

```go
func main() {
    fmt.Println("start")
    panic("something went terribly wrong")
    fmt.Println("this never runs")
}
// Output:
// start
// goroutine 1 [running]:
// main.main()
//     /tmp/main.go:4 +0x58
// exit status 2
```

---

### What causes a panic

**You call panic() explicitly:**

go

```go
panic("something is wrong")
panic(fmt.Sprintf("invalid value: %d", n))
panic(err)   // can panic with any value, including errors
```

**The runtime panics automatically:**

go

```go
// nil pointer dereference
var p *int
fmt.Println(*p)      // panic: runtime error: invalid memory address

// index out of bounds
s := []int{1, 2, 3}
fmt.Println(s[10])   // panic: runtime error: index out of range [10]

// integer divide by zero
a, b := 10, 0
fmt.Println(a / b)   // panic: runtime error: integer divide by zero

// type assertion on wrong type (without ok check)
var i interface{} = "hello"
n := i.(int)         // panic: interface conversion: string is not int
```

---

### The unwinding process

Panic doesn't crash immediately — it walks back up the call stack running deferred functions at every level:

go

```go
func a() {
    defer fmt.Println("defer in a")
    b()
}

func b() {
    defer fmt.Println("defer in b")
    c()
}

func c() {
    defer fmt.Println("defer in c")
    panic("something broke")
}

func main() {
    a()
}
// Output:
// defer in c   ← c's defers run first
// defer in b   ← then b's
// defer in a   ← then a's
// panic: something broke
// stack trace...
```

This is why `defer f.Close()` still closes your file even if something panics deep in your code — deferred functions always run during unwinding.

---

### recover — catching a panic

`recover()` stops the panic and returns the value passed to `panic()`. It **only works inside a deferred function** — nowhere else.

go

```go
func safeDiv(a, b int) (result int, err error) {
    defer func() {
        if r := recover(); r != nil {
            err = fmt.Errorf("recovered from panic: %v", r)
        }
    }()

    return a / b, nil   // panics if b is 0
}

result, err := safeDiv(10, 0)
fmt.Println(result, err)
// 0 recovered from panic: runtime error: integer divide by zero
```

---

### Why recover only works in defer

Because by the time a panic happens, normal code has stopped running. The only code still executing is deferred functions. So `recover()` outside of defer is useless:

go

```go
// WRONG — recover() outside defer always returns nil
func bad() {
    r := recover()   // nil — no panic is happening yet
    panic("oh no")
}

// RIGHT — recover() inside defer catches the panic
func good() {
    defer func() {
        r := recover()   // catches "oh no"
    }()
    panic("oh no")
}
```

---

### What recover returns

`recover()` returns whatever was passed to `panic()` as `interface{}` (any):

go

```go
panic("a string")           // recover() returns "a string"
panic(42)                   // recover() returns 42
panic(errors.New("oops"))   // recover() returns an error value
```

You check `r != nil` to know if a panic actually happened — if no panic occurred, `recover()` returns nil.

---

### The full flow

```
normal execution
      ↓
panic() called (or runtime panics)
      ↓
current function stops immediately
      ↓
deferred functions in current function run (LIFO)
      ↓                              ↓
  recover() found              no recover()
      ↓                              ↓
panic stops                   move up to caller
execution continues           run caller's defers
after deferred func                ↓
                              ... up the stack ...
                                   ↓
                              reaches main() — no recover()
                                   ↓
                              program crashes + stack trace
```

---

### When panic IS appropriate

> [!warning] panic / recover is not for normal error handling Regular errors are returned as values (`error` type). `panic` is reserved for truly unexpected states. Don't use it as a substitute for proper error handling.

**1. Programmer errors — things that should never happen:**

go

```go
func mustPositive(n int) int {
    if n <= 0 {
        panic(fmt.Sprintf("mustPositive: got %d", n))
    }
    return n
}
```

**2. Unrecoverable startup failures:**

go

```go
func main() {
    cfg, err := loadConfig()
    if err != nil {
        log.Fatal(err)   // preferred over panic in main() — cleaner output
    }
}
```

**3. Package-level setup — bad hardcoded values are programming errors:**

go

```go
var validEmail = regexp.MustCompile(`^[a-z]+@[a-z]+\.[a-z]+$`)
// MustCompile panics if the regex is invalid
// acceptable because a bad hardcoded regex is a programming error, not a runtime condition
```

**4. Unimplemented code during development:**

go

```go
func handlePayment(method string) {
    switch method {
    case "card":
        processCard()
    case "crypto":
        panic("crypto payments not implemented yet")
    }
}
```

For everything else — file not found, network timeout, invalid user input — return an `error`.

---

### When NOT to use panic

go

```go
// WRONG — file not found is not exceptional, it's expected
func readConfig(path string) Config {
    data, err := os.ReadFile(path)
    if err != nil {
        panic(err)
    }
}

// RIGHT — let the caller decide what to do
func readConfig(path string) (Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return Config{}, err
    }
}
```

---

### A realistic recover use case — HTTP server

The most common real use of `recover` — preventing one panicking handler from crashing the whole server:

go

```go
func safeHandler(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        defer func() {
            if rec := recover(); rec != nil {
                log.Printf("panic in handler: %v", rec)
                http.Error(w, "internal server error", 500)
            }
        }()
        next(w, r)
    }
}

// Wrap your handlers
http.HandleFunc("/api/users", safeHandler(getUsersHandler))
```

If `getUsersHandler` panics, the server catches it, logs it, returns a 500 to the client, and keeps running for other requests.

---

### The three-line summary

- **panic** — stop everything, unwind the stack, run defers, crash (unless recovered)
- **recover** — catch a panic inside a defer, stop the crash, return the panic value
- **Use errors for expected failures, panic only for programmer mistakes or truly unrecoverable states**
## 14. select

`select` is like a `switch` but for **channel operations**. It waits for one of several channels to be ready and executes that case. If multiple are ready, one is picked at random.

```go
ch1 := make(chan string)
ch2 := make(chan string)

go func() { ch1 <- "one" }()
go func() { ch2 <- "two" }()

select {
case msg := <-ch1:
    fmt.Println("received from ch1:", msg)
case msg := <-ch2:
    fmt.Println("received from ch2:", msg)
}
```

### select with a default case — non-blocking

Without `default`, `select` blocks until a channel is ready. With `default`, it proceeds immediately if no channel is ready:

```go
select {
case msg := <-ch:
    fmt.Println("got:", msg)
default:
    fmt.Println("no message ready — moving on")
}
```

### select with a timeout

Combine `select` with `time.After` to give up if a channel takes too long:

```go
select {
case result := <-ch:
    fmt.Println("got result:", result)
case <-time.After(3 * time.Second):
    fmt.Println("timed out after 3 seconds")
}
```

### select in a loop — processing until done

```go
for {
    select {
    case msg := <-messages:
        fmt.Println("message:", msg)
    case <-quit:
        fmt.Println("shutting down")
        return
    }
}
```

> [!info] select vs switch `switch` matches values. `select` matches channel readiness. They look similar but are completely different — `select` can only be used with channel send/receive operations.

---

## 15. Control Flow Patterns

### Early return — the Go way of avoiding deep nesting

```go
// BAD — arrow-shaped code, deeply nested
func process(user *User) error {
    if user != nil {
        if user.Active {
            if user.Age >= 18 {
                doSomething(user)
                return nil
            } else {
                return errors.New("too young")
            }
        } else {
            return errors.New("inactive")
        }
    } else {
        return errors.New("nil user")
    }
}

// GOOD — guard clauses, early returns
func process(user *User) error {
    if user == nil {
        return errors.New("nil user")
    }
    if !user.Active {
        return errors.New("inactive")
    }
    if user.Age < 18 {
        return errors.New("too young")
    }

    doSomething(user)
    return nil
}
```

### The error handling pattern

The most common control flow in Go — check error immediately after every call:

```go
func run() error {
    conn, err := net.Dial("tcp", "localhost:8080")
    if err != nil {
        return fmt.Errorf("dial: %w", err)
    }
    defer conn.Close()

    data, err := io.ReadAll(conn)
    if err != nil {
        return fmt.Errorf("read: %w", err)
    }

    result, err := process(data)
    if err != nil {
        return fmt.Errorf("process: %w", err)
    }

    fmt.Println(result)
    return nil
}
```

### Comma-ok pattern

Used with maps, type assertions, and channel receives to safely check if an operation succeeded:

```go
// Map lookup
val, ok := myMap["key"]
if !ok {
    // key not present
}

// Type assertion
str, ok := i.(string)
if !ok {
    // i is not a string
}

// Channel receive
val, ok := <-ch
if !ok {
    // channel is closed
}
```

### for range with index — a common mutation mistake

A very common bug: trying to build a slice of pointers inside a range loop:

```go
// WRONG — all pointers point to the same loop variable
nums := []int{1, 2, 3}
ptrs := make([]*int, len(nums))

for i, v := range nums {
    ptrs[i] = &v   // &v is always the address of the loop variable!
}

fmt.Println(*ptrs[0], *ptrs[1], *ptrs[2])  // 3 3 3 — all point to last value!

// RIGHT — take address from the original slice
for i := range nums {
    ptrs[i] = &nums[i]   // address of the actual element
}

fmt.Println(*ptrs[0], *ptrs[1], *ptrs[2])  // 1 2 3
```

The loop variable `v` is a single variable that gets reassigned each iteration — its address never changes. By the time you read the pointers, `v` holds the last value.

> [!info] This is fixed in Go 1.22+ From Go 1.22 onwards, each loop iteration gets its own copy of the loop variable, so `&v` is safe. In older Go versions, this is a notorious source of bugs.

---

## 16. Quick Reference Cheatsheet

```go
// ── if / else ────────────────────────────────────────────
if x > 0 { ... }
if x > 0 { ... } else { ... }
if x > 0 { ... } else if x < 0 { ... } else { ... }
if err := f(); err != nil { ... }           // with initialiser — err scoped to block
if val, ok := m["k"]; ok { ... }            // map check with initialiser
if str, ok := i.(string); ok { ... }        // type assert with initialiser

// ── switch ───────────────────────────────────────────────
switch x { case 1: ... case 2: ... default: ... }
switch { case x > 0: ... case x < 0: ... }  // no condition = if/else chain
switch os := runtime.GOOS; os { ... }        // with initialiser
switch v := i.(type) { case int: ... }       // type switch
case nil:                                    // nil case in type switch
case int, int64:                             // multiple types — v is interface{}
// No break needed between cases.
// Use fallthrough to explicitly run the next case.
// break inside switch exits the switch, NOT an enclosing loop — use a label for that.

// ── for ──────────────────────────────────────────────────
for i := 0; i < n; i++ { ... }             // classic: init ; condition ; post
for i, j := 0, 10; i < j; i, j = i+1, j-1 // multiple vars in init + post
for x < 100 { ... }                         // while-style: condition only
for { ... }                                 // infinite: all parts omitted
for i := range 5 { ... }                    // loop N times (Go 1.22+)

// ── range ────────────────────────────────────────────────
for i, v := range slice { ... }             // v is a COPY — mutate via slice[i]
for k, v := range myMap { ... }             // order not guaranteed
for i, ch := range "string" { ... }         // ch is a rune, not a byte
for v := range channel { ... }              // stops when channel is closed
for i := range slice { ... }               // index only
for _, v := range slice { ... }            // value only

// ── break / continue ─────────────────────────────────────
break                   // exit loop or switch
continue                // next iteration
break label             // exit labelled outer loop
continue label          // next iteration of labelled outer loop

// ── select ───────────────────────────────────────────────
select {
case msg := <-ch:    ...   // receive
case ch <- value:    ...   // send
default:             ...   // non-blocking — runs if no channel is ready
case <-time.After(t): ...  // timeout
}

// ── defer ────────────────────────────────────────────────
defer f()               // runs when surrounding function returns (LIFO)
defer f.Close()         // classic cleanup — always runs even on panic
defer mu.Unlock()       // classic mutex unlock
// Arguments evaluated NOW, not when defer runs
// Closures see the current value when they run
// Avoid defer inside loops — use a helper function instead

// ── panic / recover ──────────────────────────────────────
panic("message")        // crash — use for programmer errors only
log.Fatal(err)          // preferred over panic in main() for startup failures
defer func() {
    if r := recover(); r != nil { ... }
}()                     // catch a panic — must be inside a deferred function
```

---

_Previous: [[Go - Operators]] · Next: [[04 - Functions]]_