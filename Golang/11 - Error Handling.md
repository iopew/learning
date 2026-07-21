# Go — Error Handling

> **Series:** Go Language Fundamentals **Tags:** #go #golang #errors #errorhandling #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. The error Interface — What Errors Actually Are]]
- [[#2. nil Means No Error — The Contract]]
- [[#3. errors.New() — Simple Static Errors]]
- [[#4. fmt.Errorf() — Dynamic Error Messages]]
- [[#5. Sentinel Errors — io.EOF and Friends]]
- [[#6. errors.Is() — Unwrapping Sentinel Checks]]
- [[#7. Custom Error Types — Structs That Implement error]]
- [[#8. errors.As() — Extracting Typed Error Information]]
- [[#9. Error Wrapping — The %w Verb and Error Chains]]
- [[#10. Unwrap() — How the Chain Works Internally]]
- [[#11. Wrapping vs Not Wrapping — When to Use Each]]
- [[#12. Multiple Error Strategies]]
- [[#13. Panic vs Error — When to Use Each]]
- [[#14. log.Fatal vs panic vs return error]]
- [[#15. Error Handling Patterns — The Go Way]]
- [[#16. Error Handling in Goroutines]]
- [[#17. Common Mistakes — And How to Fix Them]]
- [[#18. Quick Reference Cheatsheet]]

---

## 1. The error Interface — What Errors Actually Are

The `error` type is a **built-in interface** — just like any other interface you saw in [[10 - Interfaces]]:

```go
type error interface {
    Error() string
}
```

That's it. One method. Any type that has an `Error() string` method automatically satisfies the `error` interface — no `implements` keyword, no declaration needed.

```go
type MyError struct{ Message string }

func (e MyError) Error() string {
    return e.Message
}

var err error = MyError{Message: "something broke"}
fmt.Println(err) // something broke
```

### What this means in practice

The `error` type is the **universal return value for failures** in Go. Functions that can fail return `error` as their last return value. Callers check it immediately.

```go
f, err := os.Open("file.txt")
if err != nil {
    // handle the error
    return
}
// use f
```

There is no try/catch, no exceptions, no throws clause. Just an interface value returned from a function.

### fmt.Println calls Error() automatically

When you use `fmt.Println(err)` or `fmt.Printf("%s", err)`, the `fmt` package checks if the value implements `error`, and if so, calls its `Error() string` method to get the message. You never call `.Error()` explicitly in print statements — `fmt` does it for you.

```go
err := errors.New("disk full")
fmt.Println(err)       // disk full
fmt.Printf("%v\n", err) // disk full
fmt.Printf("%s\n", err) // disk full
```

---

## 2. nil Means No Error — The Contract

The zero value of the `error` interface is `nil`. By convention — and it is a strict Go convention, not something the compiler enforces — returning `nil` from a function means **"everything worked fine, no error."**

```go
func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, errors.New("division by zero")
    }
    return a / b, nil // nil means "no error"
}

result, err := divide(10, 2)
if err != nil {
    fmt.Println("Error:", err)
    return
}
fmt.Println(result) // 5
```

### The rule

```go
if err != nil {
    // something went wrong — handle it
}
```

This check appears constantly in Go code. It is the fundamental pattern. Any function that can fail returns `error` as its last value, and the caller checks immediately.

### Never ignore the error

```go
// WRONG — ignoring the error
result, _ := divide(10, 0)
fmt.Println(result) // 0 — but you'd never know it was an error

// RIGHT — always check
result, err := divide(10, 0)
if err != nil {
    fmt.Println("error:", err)
    return
}
fmt.Println(result)
```

> [!warning] The blank identifier `_` to discard errors is almost always wrong If a function returns an error, there is a reason. Ignoring it silently hides bugs. Only discard an error when you have explicitly considered it and decided it truly does not matter — which is rare in practice.

---

## 3. errors.New() — Simple Static Errors

`errors.New()` creates a simple error value from a string message. The result is an `error` value that prints as that string.

```go
import "errors"

err := errors.New("file not found")
fmt.Println(err) // file not found
```

### How it works internally

`errors.New()` returns a pointer to a private struct that implements the `error` interface:

```go
// This is approximately what errors.New does internally:
func New(text string) error {
    return &errorString{text}
}

type errorString struct {
    s string
}

func (e *errorString) Error() string {
    return e.s
}
```

The key detail: it returns a **pointer** to the struct. This matters because two `errors.New` calls with the same string produce **different** error values (different memory addresses):

```go
err1 := errors.New("not found")
err2 := errors.New("not found")

fmt.Println(err1 == err2) // false — different pointers!
```

### When to use errors.New

Use it for **static** error messages — errors that never change, have no dynamic data, and need no additional context:

```go
var ErrNotFound = errors.New("not found")
var ErrPermission = errors.New("permission denied")
```

These are typically defined as package-level variables (sentinel errors — covered in [[#5. Sentinel Errors]]).

> [!tip] Error messages should be lowercase and contain no punctuation. This is a Go convention — errors often get wrapped with additional context, and uppercased or punctuated messages look odd when combined: `"file not found: permission denied"` reads naturally, `"File not found.: Permission denied!"` does not.

---

## 4. fmt.Errorf() — Dynamic Error Messages

When your error message needs to include dynamic values (a filename, a number, whatever), use `fmt.Errorf()`:

```go
import "fmt"

name := "config.yaml"
err := fmt.Errorf("file %s not found", name)
fmt.Println(err) // file config.yaml not found
```

`fmt.Errorf` works exactly like `fmt.Sprintf` — same format verbs — but returns an `error` instead of a `string`.

```go
port := 8080
err := fmt.Errorf("port %d is already in use", port)
fmt.Println(err) // port 8080 is already in use
```

### The critical difference — %w for wrapping

`fmt.Errorf` has one verb that `fmt.Sprintf` does not: `%w`. This **wraps** an existing error into a new one, creating an error chain:

```go
import "fmt"

originalErr := errors.New("connection refused")
wrappedErr := fmt.Errorf("failed to connect: %w", originalErr)

fmt.Println(wrappedErr) // failed to connect: connection refused
```

`%w` is specifically for error wrapping. It is the only verb that creates a chainable error. All other verbs (`%s`, `%v`, `%d`) just format the error's message as text — they do not preserve the error identity for `errors.Is` and `errors.As`.

> [!warning] Use `%w`, not `%v` or `%s`, when wrapping errors `err := fmt.Errorf("context: %v", originalErr)` creates a new error with the message `"context: connection refused"`, but the original error is **lost** — `errors.Is` and `errors.As` will never find it. Only `%w` preserves the chain.

---

## 5. Sentinel Errors — io.EOF and Friends

A **sentinel error** is a predefined error value that callers can compare against to know exactly what went wrong. They are usually declared as package-level variables.

```go
package mydb

var ErrNotFound = errors.New("record not found")
var ErrDuplicateKey = errors.New("duplicate key")
var ErrConnectionClosed = errors.New("connection closed")
```

### The standard library's most famous sentinel: io.EOF

```go
import (
    "io"
    "strings"
)

r := strings.NewReader("hello")
buf := make([]byte, 10)
n, err := r.Read(buf)
if err == io.EOF {
    fmt.Println("end of file reached") // this runs after reading all data
}
```

`io.EOF` is defined as:

```go
var EOF = errors.New("EOF")
```

Callers check for it specifically to know when reading is complete — it is not an error in the "something broke" sense, it is a signal that there is nothing more to read.

### Other common sentinel errors

```go
sql.ErrNoRows      // no rows in result set
io.ErrUnexpectedEOF // unexpected EOF during read
os.ErrNotExist     // file does not exist
os.ErrPermission   // permission denied
context.Canceled    // context was cancelled
context.DeadlineExceeded // context deadline passed
```

### Checking sentinel errors — the direct comparison

Before Go 1.13, the way to check sentinel errors was direct `==` comparison:

```go
if err == io.EOF {
    // end of file
}

if err == os.ErrNotExist {
    // file doesn't exist
}
```

> [!warning] Direct == comparison breaks with wrapped errors If someone wraps your sentinel error with `fmt.Errorf("reading config: %w", sql.ErrNoRows)`, then `err == sql.ErrNoRows` is `false` — the wrapper is a different error value. This is exactly why `errors.Is()` was introduced.

---

## 6. errors.Is() — Unwrapping Sentinel Checks

Introduced in Go 1.13, `errors.Is()` checks **through the entire error chain** to see if any error in the chain matches a target sentinel:

```go
import "errors"

err := fmt.Errorf("reading config: %w", sql.ErrNoRows)

// Direct comparison — FAILS
fmt.Println(err == sql.ErrNoRows) // false

// errors.Is — WORKS, walks the chain
fmt.Println(errors.Is(err, sql.ErrNoRows)) // true
```

### How it works

`errors.Is` walks the error chain:

1. Checks if `err == target` → if yes, returns `true`
2. If `err` has an `Unwrap()` method that returns another error, calls `Is` recursively on that unwrapped error
3. If `err` has its own `Is` method, it delegates to that (rarely needed — covered below)
4. Repeats until it finds a match or reaches the end of the chain

### The standard pattern

```go
err := someFunction()
if errors.Is(err, sql.ErrNoRows) {
    // handle "no rows" case
} else if errors.Is(err, context.DeadlineExceeded) {
    // handle timeout case
} else if err != nil {
    // handle any other error
}
```

### Use errors.Is everywhere, not ==

> [!tip] In modern Go (1.13+), always use `errors.Is(err, target)` instead of `err == target`. Even if the error is not wrapped today, it might be wrapped tomorrow — using `errors.Is` makes your code forward-compatible.

### Custom Is methods — rare but possible

A custom error type can implement its own `Is` method to define custom matching logic:

```go
type RetryableError struct {
    Code int
}

func (e RetryableError) Error() string {
    return fmt.Sprintf("retryable error %d", e.Code)
}

func (e RetryableError) Is(target error) bool {
    // Any RetryableError matches any other RetryableError
    _, ok := target.(RetryableError)
    return ok
}
```

This is uncommon. In most code, the default `errors.Is` behavior (walking the chain comparing with `==`) is sufficient.

---

## 7. Custom Error Types — Structs That Implement error

When you need to carry structured information beyond a message string — a status code, an offending value, a list of causes — define a custom type that implements the `error` interface.

### The simplest custom error

```go
type NotFoundError struct {
    ID string
}

func (e *NotFoundError) Error() string {
    return fmt.Sprintf("resource %s not found", e.ID)
}

// Usage
func findUser(id string) (*User, error) {
    return nil, &NotFoundError{ID: id}
}

err := findUser("xyz")
fmt.Println(err) // resource xyz not found
```

### Why use a pointer receiver (*NotFoundError) vs value

In the example above, `Error()` is defined on `*NotFoundError` (pointer receiver), not `NotFoundError` (value receiver). This matters:

```go
// If Error has a value receiver — both pointer and value satisfy error
func (e NotFoundError) Error() string { ... }

var err error = NotFoundError{ID: "x"}  // ✅ works
var err error = &NotFoundError{ID: "x"} // ✅ also works

// If Error has a pointer receiver — only the pointer satisfies error
func (e *NotFoundError) Error() string { ... }

var err error = NotFoundError{ID: "x"}  // ❌ does NOT work
var err error = &NotFoundError{ID: "x"} // ✅ works
```

The convention is to use **pointer receivers** for custom error types. This keeps the error type consistent with how `errors.New` works (it returns a pointer), and avoids confusion with `errors.As` (covered next).

### A richer custom error

```go
type ValidationError struct {
    Field   string
    Value   any
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed on %s: %s (got %v)", e.Field, e.Message, e.Value)
}

// Usage
func validateAge(age int) error {
    if age < 0 {
        return &ValidationError{
            Field:   "age",
            Value:   age,
            Message: "must be non-negative",
        }
    }
    if age > 150 {
        return &ValidationError{
            Field:   "age",
            Value:   age,
            Message: "unrealistic value",
        }
    }
    return nil
}
```

### Custom errors with unwrapping

A custom error type can participate in the error chain by implementing `Unwrap()`:

```go
type WrappedError struct {
    Msg string
    Err error
}

func (e *WrappedError) Error() string {
    return fmt.Sprintf("%s: %v", e.Msg, e.Err)
}

func (e *WrappedError) Unwrap() error {
    return e.Err
}

// Now it works with errors.Is and errors.As:
inner := errors.New("disk full")
outer := &WrappedError{Msg: "write failed", Err: inner}

fmt.Println(errors.Is(outer, inner)) // true — walks through Unwrap
```

---

## 8. errors.As() — Extracting Typed Error Information

`errors.As()` finds the **first error in the chain that matches a target type**, and extracts it into the target. It is the typed equivalent of `errors.Is`:

```go
err := someFunction()

var notFound *NotFoundError
if errors.As(err, &notFound) {
    // notFound is now *NotFoundError — you can access its fields
    fmt.Println("missing ID:", notFound.ID)
}
```

### How it works

`errors.As` walks the error chain:

1. Checks if `err` can be **assigned to** the target type (using `reflect` under the hood)
2. If yes, it sets the target and returns `true`
3. If `err` has an `Unwrap()` method, it recurses on the unwrapped error
4. If the type has its own `As` method, it delegates to that

### The target must be a pointer to a pointer (or pointer to interface)

```go
var notFound *NotFoundError  // this is a nil pointer of type *NotFoundError
errors.As(err, &notFound)    // pass the ADDRESS of the pointer — **NotFoundError
```

If you pass just `notFound` (not `&notFound`), `errors.As` receives a `*NotFoundError` that is nil and cannot set it — it will never match.

```go
// WRONG
var notFound *NotFoundError
errors.As(err, notFound) // ❌ notFound is nil, and As receives a value, not a settable pointer

// RIGHT
var notFound *NotFoundError
errors.As(err, &notFound) // ✅ &notFound is **NotFoundError — settable
```

### Real-world example with ValidationError

```go
type ValidationError struct {
    Field   string
    Value   any
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

func processRequest(data map[string]any) error {
    name, ok := data["name"].(string)
    if !ok || name == "" {
        return &ValidationError{
            Field:   "name",
            Value:   data["name"],
            Message: "must be a non-empty string",
        }
    }
    return nil
}

// Somewhere up the call stack:
err := processRequest(input)
var valErr *ValidationError
if errors.As(err, &valErr) {
    fmt.Printf("Field '%s' failed: %s (got %v)\n", valErr.Field, valErr.Message, valErr.Value)
    // You can return a structured error response, highlight the field in the UI, etc.
}
```

### errors.As with interface targets

You can also use `errors.As` to check if any error in the chain implements a specific **interface**:

```go
type Temporary interface {
    Temporary() bool
}

err := doSomething()
var temp Temporary
if errors.As(err, &temp) {
    if temp.Temporary() {
        // retry the operation
    }
}
```

This pattern is used in the standard library — `net.Error` has `Temporary()` and `Timeout()` methods, and `errors.As` can extract them from any level of the chain.

---

## 9. Error Wrapping — The %w Verb and Error Chains

**Wrapping** means taking an existing error and adding context to it while preserving the original error's identity. This creates an **error chain** — a linked list of errors that `errors.Is` and `errors.As` can walk through.

### The wrapping syntax

```go
original := errors.New("connection refused")
wrapped := fmt.Errorf("failed to connect to server: %w", original)
```

The `%w` verb tells `fmt.Errorf` to create an error that:
1. Has the message `"failed to connect to server: connection refused"`
2. Can be unwrapped to reveal the original `"connection refused"` error

### Why wrapping matters

Without wrapping, every function in the call stack creates a brand new error with no connection to the original cause:

```go
// NO wrapping — error identity is lost at every level
func readConfig() error {
    err := readFile("config.yaml")
    if err != nil {
        return fmt.Errorf("read config: %v", err) // original error lost!
    }
    return nil
}
```

With wrapping, the chain preserves the full path:

```go
// WITH wrapping — full chain preserved
func readConfig() error {
    err := readFile("config.yaml")
    if err != nil {
        return fmt.Errorf("read config: %w", err) // original preserved
    }
    return nil
}

// Caller can still inspect the original:
err := readConfig()
if errors.Is(err, os.ErrNotExist) {
    // This works even though readConfig wrapped the original os.ErrNotExist
}
```

### The full chain in action

```go
func loadConfig() error {
    return fmt.Errorf("load config: %w", readConfig())
}

func readConfig() error {
    return fmt.Errorf("read config file: %w", openFile())
}

func openFile() error {
    return fmt.Errorf("open file: %w", os.ErrNotExist)
}

err := loadConfig()
fmt.Println(err) // load config: read config file: open file: file does not exist

fmt.Println(errors.Is(err, os.ErrNotExist)) // true — walks the entire chain
```

### Multiple %w verbs

You can wrap multiple errors in a single `fmt.Errorf` using multiple `%w` verbs:

```go
err1 := errors.New("first error")
err2 := errors.New("second error")
err := fmt.Errorf("multiple errors: %w and %w", err1, err2)

fmt.Println(errors.Is(err, err1)) // true
fmt.Println(errors.Is(err, err2)) // true
```

However, the `Unwrap()` method can only return a single error. When there are multiple `%w` verbs, `fmt.Errorf` returns a special type that implements `Unwrap() []error` (note the slice). Both `errors.Is` and `errors.As` handle this automatically — they check all unwrapped errors.

### Wrapping with custom error types

Your custom error types can participate in the chain by implementing the `Unwrap()` method:

```go
type ConfigError struct {
    Msg string
    Err error
}

func (e *ConfigError) Error() string {
    if e.Err != nil {
        return fmt.Sprintf("config: %s: %v", e.Msg, e.Err)
    }
    return fmt.Sprintf("config: %s", e.Msg)
}

func (e *ConfigError) Unwrap() error {
    return e.Err
}

// Usage
inner := errors.New("syntax error on line 42")
outer := &ConfigError{Msg: "parse failed", Err: inner}

fmt.Println(errors.Is(outer, inner)) // true
```

---

## 10. Unwrap() — How the Chain Works Internally

The entire error wrapping system is built on a single convention: if a type has a method `Unwrap() error`, then `errors.Is` and `errors.As` will follow it to the next error in the chain.

```go
type Wrapper interface {
    Unwrap() error
}
```

This is NOT a built-in interface in the language — it is a **convention** that the `errors` package checks for. Any type with an `Unwrap() error` method is part of the chain.

### How errors.Is uses Unwrap

This is approximately what `errors.Is` does internally:

```go
func Is(err, target error) bool {
    for {
        if err == target {
            return true
        }
        // Check if err has an Unwrap method
        u, ok := err.(interface{ Unwrap() error })
        if !ok {
            return false // end of chain
        }
        err = u.Unwrap() // move to the next error in the chain
    }
}
```

### How errors.As uses Unwrap

Similarly, `errors.As` walks the chain trying to assign each error to the target type:

```go
func As(err error, target interface{}) bool {
    for {
        if assignable(err, target) {
            // set target to err
            return true
        }
        u, ok := err.(interface{ Unwrap() error })
        if !ok {
            return false
        }
        err = u.Unwrap()
    }
}
```

### Unwrap() []error — multiple wrapped errors

When a `fmt.Errorf` call uses multiple `%w` verbs, the resulting type implements `Unwrap() []error` instead of `Unwrap() error`:

```go
type multiError struct {
    errs []error
}

func (m *multiError) Error() string { /* ... */ }
func (m *multiError) Unwrap() []error {
    return m.errs
}
```

Both `errors.Is` and `errors.As` check for both single and multi forms of `Unwrap`, iterating through all errors in the slice for the multi form.

### Implementing Unwrap on your custom types

```go
type HTTPError struct {
    StatusCode int
    Err        error
}

func (e *HTTPError) Error() string {
    return fmt.Sprintf("HTTP %d: %v", e.StatusCode, e.Err)
}

func (e *HTTPError) Unwrap() error {
    return e.Err
}

// Now HTTPError works with errors.Is and errors.As:
inner := errors.New("unauthorized")
httpErr := &HTTPError{StatusCode: 401, Err: inner}

fmt.Println(errors.Is(httpErr, inner))         // true
fmt.Println(errors.Is(httpErr, os.ErrNotExist)) // false
.
```

---

## 11. Wrapping vs Not Wrapping — When to Use Each

### Wrap (use %w) when:

**The caller might need to check the error type or identity:**

```go
func readUserFile(path string) error {
    data, err := os.ReadFile(path)
    if err != nil {
        // Caller may want to check if it's os.ErrNotExist, os.ErrPermission, etc.
        return fmt.Errorf("reading user file %s: %w", path, err)
    }
    // ...
}
```

**You are adding context to an error from your own package or the standard library:**

```go
func connect() error {
    conn, err := net.Dial("tcp", addr)
    if err != nil {
        return fmt.Errorf("connect to %s: %w", addr, err)
    }
    // ...
}
```

### Do NOT wrap (use %v or %s or a new error) when:

**The error is an implementation detail the caller should not know about:**

```go
func processPayment(amount float64) error {
    encrypted, err := encrypt(amount)
    if err != nil {
        // The caller does not need to know about encryption details
        // They just need to know payment processing failed
        return fmt.Errorf("process payment: %v", err) // %v, not %w
    }
    // ...
}
```

**You are returning a sentinel error — do not wrap the sentinel itself:**

```go
var ErrInsufficientFunds = errors.New("insufficient funds")

func withdraw(amount float64) error {
    if balance < amount {
        return ErrInsufficientFunds // return the sentinel directly, not wrapped
    }
    // ...
}
```

**The error is a new semantic error, not additional context around an existing one:**

```go
func parseAge(s string) (int, error) {
    n, err := strconv.Atoi(s)
    if err != nil {
        return 0, fmt.Errorf("invalid age %q: %w", s, err)
    }
    if n < 0 {
        return 0, errors.New("age cannot be negative") // new error, no wrapping
    }
    return n, nil
}
```

### The rule of thumb

> [!tip] Wrap errors when adding context that helps identify the **cause**. Do not wrap when the error represents a **new failure** that the caller handles differently, or when exposing the underlying error would leak implementation details.

### The official position — always wrap with %w

The Go blog (Go 1.13) recommends wrapping errors as you return them up the call stack, so that every level adds context. This is the dominant convention in idiomatic Go:

```go
func loadConfig() error {
    f, err := os.Open("config.yaml")
    if err != nil {
        return fmt.Errorf("load config: %w", err)
    }
    defer f.Close()
    // parse...
}
```

The message reads top-down: `"load config: open config.yaml: file does not exist"` — where each level added its own context.

---

## 12. Multiple Error Strategies

Sometimes a single operation can produce **multiple errors** — for example, validating many fields, or running several independent steps. Go has several strategies for handling this.

### Strategy 1 — First error wins (simplest, most common)

Stop at the first error and return immediately:

```go
func processAll(items []string) error {
    for _, item := range items {
        if err := process(item); err != nil {
            return fmt.Errorf("process %s: %w", item, err)
        }
    }
    return nil
}
```

This is the default pattern. It is simple, clear, and sufficient for most code.

### Strategy 2 — Collect all errors (validation)

When you need to report every problem at once:

```go
func validateUser(u User) error {
    var errs []string

    if u.Name == "" {
        errs = append(errs, "name is required")
    }
    if u.Age < 0 || u.Age > 150 {
        errs = append(errs, "age must be between 0 and 150")
    }
    if u.Email == "" {
        errs = append(errs, "email is required")
    }

    if len(errs) > 0 {
        return fmt.Errorf("validation failed: %s", strings.Join(errs, "; "))
    }
    return nil
}
```

### Strategy 3 — errors.Join (Go 1.20+)

Go 1.20 introduced `errors.Join`, which combines multiple errors into a single error:

```go
import "errors"

err1 := errors.New("first error")
err2 := errors.New("second error")
err3 := errors.New("third error")

combined := errors.Join(err1, err2, err3)
fmt.Println(combined)
// Output:
// first error
// second error
// third error

// errors.Is works through the joined errors:
fmt.Println(errors.Is(combined, err2)) // true

// errors.As works too:
// (if any of the joined errors matches the target type, it is found)
```

`errors.Join` is ideal for:

```go
func validateUser(u User) error {
    var err error
    if u.Name == "" {
        err = errors.Join(err, errors.New("name is required"))
    }
    if u.Age < 0 {
        err = errors.Join(err, errors.New("age must be non-negative"))
    }
    return err // nil if no errors were joined
}
```

### Strategy 4 — Custom error aggregator

For complex cases, create a dedicated error type:

```go
type AggregateError struct {
    Errors []error
}

func (e *AggregateError) Error() string {
    msgs := make([]string, len(e.Errors))
    for i, err := range e.Errors {
        msgs[i] = err.Error()
    }
    return strings.Join(msgs, "; ")
}

func (e *AggregateError) Unwrap() []error {
    return e.Errors
}

// Usage
func runSteps() error {
    var agg AggregateError
    for _, step := range steps {
        if err := step(); err != nil {
            agg.Errors = append(agg.Errors, err)
        }
    }
    if len(agg.Errors) > 0 {
        return &agg
    }
    return nil
}
```

---

## 13. Panic vs Error — When to Use Each

This is one of the most important distinctions in Go. The rule is simple:

> [!info] **Errors are for expected failures. Panics are for unexpected bugs.**

### Use errors (return error) for:

- File not found
- Network timeout
- Invalid user input
- Database connection failed
- Permission denied
- Any situation a caller might reasonably anticipate and handle

```go
func readFile(path string) ([]byte, error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, fmt.Errorf("read file: %w", err)
    }
    defer f.Close()
    return io.ReadAll(f)
}
```

### Use panic for:

- **Nil pointer dereference** — the runtime panics automatically for this
- **Index out of bounds** — also automatic
- **Programming bugs** — calling a function with invalid arguments that should never happen
- **Unimplemented code during development**
- **Startup failures in unrecoverable situations** (rare — usually handled differently)

```go
// Programmer error — mustPositive should never receive a negative number
func mustPositive(n int) int {
    if n <= 0 {
        panic(fmt.Sprintf("mustPositive: called with %d", n))
    }
    return n
}

// Unimplemented — development guard
func handleCryptoPayment(amount float64) {
    panic("crypto payments not implemented yet")
}
```

### The critical distinction

```go
// EXPECTED — file might not exist, caller should handle it
func loadConfig() (Config, error) { ... }

// UNEXPECTED — regex is hardcoded, if it is invalid it is a programming mistake
var validEmail = regexp.MustCompile(`^[a-z]+@[a-z]+\.[a-z]+$`)
// regexp.MustCompile panics if the regex is invalid — acceptable because
// a bad hardcoded regex is a bug in the code, not a runtime condition
```

### The "panics are not exceptions" rule

Developers from Python, Java, or C# often reach for panic/recover as a substitute for exceptions. This is wrong in Go:

```go
// WRONG — using panic as an exception
func divide(a, b int) int {
    if b == 0 {
        panic("division by zero")
    }
    return a / b
}

func main() {
    defer func() {
        if r := recover(); r != nil {
            fmt.Println("caught panic:", r)
        }
    }()
    result := divide(10, 0)
}

// RIGHT — returning an error
func divide(a, b int) (int, error) {
    if b == 0 {
        return 0, errors.New("division by zero")
    }
    return a / b, nil
}
```

> [!warning] Do not use panic/recover as a control flow mechanism It is slower, harder to reason about, and signals the wrong intent. Go has explicit error returns for exactly this purpose — use them.

---

## 14. log.Fatal vs panic vs return error

All three can stop or signal failure, but they serve different purposes:

### return error — the standard way

Returns control to the caller. The caller decides what to do:

```go
func doWork() error {
    return errors.New("something failed")
}

func main() {
    if err := doWork(); err != nil {
        fmt.Println("handled gracefully:", err)
        // Program can continue or retry
    }
}
```

**Use for:** any error the caller might reasonably handle or recover from.

### log.Fatal — immediate termination with log message

Calls `os.Exit(1)` after printing the message. **Deferred functions do NOT run.**

```go
func main() {
    cfg, err := loadConfig()
    if err != nil {
        log.Fatalf("failed to load config: %v", err)
        // os.Exit(1) is called — nothing after this runs
        // Not even deferred functions from earlier in main()
    }
}
```

```go
// IMPORTANT — defers do NOT run after log.Fatal:
func main() {
    defer fmt.Println("this never prints")
    log.Fatal("goodbye")
}
```

**Use for:** failures in `main()` where there is nothing left to do — missing config, cannot bind to port, database unreachable at startup. Once in `main()`, there is no caller to return an error to.

### panic — stops the goroutine, unwinds the stack

Panic runs deferred functions up the stack, then crashes (unless recovered):

```go
func main() {
    defer fmt.Println("this DOES print") // runs during panic unwinding
    panic("something broke")
    fmt.Println("this never prints")
}
```

**Use for:** programmer bugs — invariants violated, impossible states, unrecoverable errors within library code where there is no meaningful way for the caller to continue.

### Comparison table

| Mechanism | Deferred funcs run? | Stack trace? | Program continues? | Typical use |
|---|---|---|---|---|
| `return error` | N/A (normal return) | No | Yes (caller decides) | Expected failures |
| `log.Fatal` | **No** | No (unless you add it) | No — exits immediately | Main() startup failures |
| `panic` | Yes | Yes (full trace) | No — crashes (unless recovered) | Programming bugs, invariants |

### The best practice

```go
// In library code — always return error
func connect() error { ... }

// In main() at startup — log.Fatal is acceptable
func main() {
    db, err := connect()
    if err != nil {
        log.Fatalf("cannot start: %v", err)
    }
    defer db.Close()
    // ... run server ...
}

// In library code — panic only for programmer errors
func (s *Server) Serve() {
    if s == nil {
        panic("nil server") // calling Serve on nil is a programming mistake
    }
    // ...
}
```

---

## 15. Error Handling Patterns — The Go Way

### Pattern 1 — The standard if-check

```go
result, err := doSomething()
if err != nil {
    // handle error
    return err
}
```

This is the most common pattern in Go. It appears thousands of times in every non-trivial Go program.

### Pattern 2 — The initialiser + if (scoped error)

```go
if err := doSomething(); err != nil {
    fmt.Println("error:", err)
    return err
}
// err is out of scope here — clean
```

This keeps the error variable scoped to the `if` block. It is especially useful when you do not need the error after the check.

### Pattern 3 — Guard clauses (flat over nested)

```go
// BAD — deeply nested
func process(r *Request) error {
    if r != nil {
        if r.User != nil {
            if r.User.Active {
                return doSomething(r)
            } else {
                return errors.New("user inactive")
            }
        } else {
            return errors.New("nil user")
        }
    }
    return errors.New("nil request")
}

// GOOD — guard clauses, flat structure
func process(r *Request) error {
    if r == nil {
        return errors.New("nil request")
    }
    if r.User == nil {
        return errors.New("nil user")
    }
    if !r.User.Active {
        return errors.New("user inactive")
    }
    return doSomething(r)
}
```

### Pattern 4 — Wrapping every level

```go
func handleRequest() error {
    data, err := readInput()
    if err != nil {
        return fmt.Errorf("handle request: %w", err)
    }

    result, err := processData(data)
    if err != nil {
        return fmt.Errorf("process data: %w", err)
    }

    err = saveResult(result)
    if err != nil {
        return fmt.Errorf("save result: %w", err)
    }

    return nil
}
```

The error message reads like a breadcrumb trail: `"save result: process data: handle request: ..."`

### Pattern 5 — The "defer close with error check"

```go
func readFile(path string) (data []byte, err error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    defer func() {
        closeErr := f.Close()
        if err == nil {
            err = closeErr // only set close error if no other error occurred
        }
    }()

    return io.ReadAll(f)
}
```

This pattern ensures that if reading succeeds but closing fails, the caller sees the close error. If reading fails, the read error is preserved (the close error is not silently lost, but it does not overwrite the more important read error).

### Pattern 6 — The "contextual message, not the full trace"

Not every error needs the full chain. Sometimes a simple message is better:

```go
func getUsername(id int) (string, error) {
    u, err := db.FindUserByID(id)
    if err != nil {
        // The caller probably does not need to know about SQL details
        return "", fmt.Errorf("get username: %v", err) // %v, not %w
    }
    return u.Name, nil
}
```

---

## 16. Error Handling in Goroutines

> ⚠️ This section references goroutines, channels, `sync.WaitGroup`, and `errgroup`. If you have not yet covered [[12 - Goroutines]], **skip this section** and return to it after reading that file.

Errors inside goroutines cannot be returned to the caller in the usual way — goroutines run independently and their return values are lost. You need a mechanism to get errors out.

### Problem — lost errors

```go
// WRONG — the error is lost
func processItems(items []string) {
    for _, item := range items {
        go func(item string) {
            if err := process(item); err != nil {
                // Where does this error go? Nobody is listening!
                fmt.Println("error:", err) // just logging — not a real solution
            }
        }(item)
    }
    // Goroutines may not have finished yet
}
```

### Solution 1 — error channel

```go
func processItems(items []string) []error {
    errCh := make(chan error, len(items))

    for _, item := range items {
        item := item // capture
        go func() {
            if err := process(item); err != nil {
                errCh <- err
            }
        }()
    }

    var errs []error
    for i := 0; i < len(items); i++ {
        if err := <-errCh; err != nil {
            errs = append(errs, err)
        }
    }
    return errs
}
```

### Solution 2 — sync.WaitGroup + safe error collector

```go
func processItems(items []string) error {
    var (
        wg   sync.WaitGroup
        mu   sync.Mutex
        errs []error
    )

    for _, item := range items {
        item := item
        wg.Add(1)
        go func() {
            defer wg.Done()
            if err := process(item); err != nil {
                mu.Lock()
                errs = append(errs, err)
                mu.Unlock()
            }
        }()
    }

    wg.Wait()

    if len(errs) > 0 {
        return fmt.Errorf("encountered %d errors: %v", len(errs), errs[0])
        // Or use errors.Join to combine them
    }
    return nil
}
```

### Solution 3 — errgroup (golang.org/x/sync)

A popular third-party package that combines goroutine spawning with error propagation:

```go
import "golang.org/x/sync/errgroup"

func processItems(items []string) error {
    g := new(errgroup.Group)

    for _, item := range items {
        item := item
        g.Go(func() error {
            return process(item)
        })
    }

    // Wait returns the first non-nil error (or nil if all succeeded)
    return g.Wait()
}
```

`errgroup` also supports context cancellation — if one goroutine fails, the group cancels the context and all other goroutines see the cancellation.

### The rule

> [!tip] Any goroutine that can produce an error must have a way to communicate that error back. Use channels, WaitGroup + mutex, or errgroup. Do not let goroutine errors vanish into logs — they are real failures that callers need to know about.

---

## 17. Common Mistakes — And How to Fix Them

### Mistake 1 — Ignoring errors with `_`

```go
// WRONG
f, _ := os.Open("file.txt")
f.Write([]byte("data")) // silently fails if file wasn't opened

// RIGHT
f, err := os.Open("file.txt")
if err != nil {
    return fmt.Errorf("open file: %w", err)
}
```

### Mistake 2 — Checking the wrong variable

```go
// WRONG — checking the wrong err
func do() error {
    var err error
    if result, err := step1(); err != nil {
        return err // this err is the one from step1 — correct
    }
    // But err here is still the outer var — nil
    step2() // ignores the outer err entirely
    return err // nil, even though step2 might have failed
}

// RIGHT
func do() error {
    if err := step1(); err != nil {
        return err
    }
    if err := step2(); err != nil {
        return err
    }
    return nil
}
```

### Mistake 3 — Wrapping with %v instead of %w

```go
// WRONG — error identity lost
if err != nil {
    return fmt.Errorf("context: %v", err)
}

// RIGHT — error identity preserved
if err != nil {
    return fmt.Errorf("context: %w", err)
}
```

### Mistake 4 — Over-wrapping

```go
// WRONG — wrapping errors from your own package's sentinel
var ErrNotFound = errors.New("not found")

func find(id int) error {
    return fmt.Errorf("find: %w", ErrNotFound) // wrapping a sentinel!
}
// Now errors.Is(err, ErrNotFound) is false — the sentinel is wrapped

// RIGHT — return sentinel directly
func find(id int) error {
    return ErrNotFound
}

// RIGHT — create a new sentinel or custom type for the specific case
func find(id int) error {
    return fmt.Errorf("find %d: %w", id, ErrNotFound) // wrapping with context is OK
    // errors.Is(err, ErrNotFound) still works — ErrNotFound is the inner error
}
```

### Mistake 5 — The nil interface trap with error

This is the same trap from [[10 - Interfaces]] — a nil concrete pointer stored in an `error` interface variable is NOT a nil error:

```go
// WRONG — the classic nil interface trap
type MyError struct{}

func (e *MyError) Error() string { return "my error" }

func do() error {
    var e *MyError = nil
    return e // returns (type=*MyError, value=nil) — NOT a nil interface!
}

func main() {
    err := do()
    if err != nil {
        fmt.Println("error occurred!") // THIS PRINTS — even though e was nil!
    }
}

// RIGHT — return nil directly
func do() error {
    var e *MyError = nil
    if somethingWentWrong {
        return &MyError{} // return a real error
    }
    return nil // return untyped nil
}
```

> [!warning] Never declare a variable as a typed nil error and return it. Always return the literal `nil` for "no error."

### Mistake 6 — Sending from a nil channel in goroutine error handling

When using channels to collect goroutine errors, a nil channel blocks forever. Ensure your error channel is properly initialized:

```go
var errCh chan error // nil! Channel send/receive blocks forever
// errCh := make(chan error, 1) — must initialize
```

### Mistake 7 — Using == with wrapped errors

```go
// WRONG — breaks if the error is wrapped
if err == io.EOF { ... }

// RIGHT — works even if the error is wrapped
if errors.Is(err, io.EOF) { ... }
```

### Mistake 8 — Excessive logging before returning

```go
// WRONG — logs and returns, resulting in double-logging at the caller
func process() error {
    if err := step(); err != nil {
        log.Println("error:", err) // logged here
        return err                  // AND logged again by caller
    }
}

// RIGHT — either log or return, not both
func process() error {
    return step() // let the caller decide how to log
}

// Or wrap with context but do not log — the message carries the context
func process() error {
    if err := step(); err != nil {
        return fmt.Errorf("process: %w", err) // context is in the error message
    }
    return nil
}
```

### Mistake 9 — Swallowing errors in defer

```go
// WRONG — close error silently lost
func readFile(path string) ([]byte, error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    defer f.Close() // what if Close returns an error?
    return io.ReadAll(f)
}

// BETTER — capture close error
func readFile(path string) (data []byte, err error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    defer func() {
        closeErr := f.Close()
        if err == nil {
            err = closeErr
        }
    }()
    return io.ReadAll(f)
}
```

### Mistake 10 — Panic in library code for non-bug situations

```go
// WRONG — file not found is not a bug, it is an expected condition
func readConfig(path string) *Config {
    data, err := os.ReadFile(path)
    if err != nil {
        panic(err) // caller cannot handle this gracefully
    }
}

// RIGHT — return an error
func readConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("read config: %w", err)
    }
}
```

---

## 18. Quick Reference Cheatsheet

```go
// ── The error interface ────────────────────────────────────
// type error interface { Error() string }
// Any type with Error() string satisfies error

// ── Creating errors ───────────────────────────────────────
errors.New("message")                    // simple static error
fmt.Errorf("format %v", arg)            // dynamic message
fmt.Errorf("context: %w", originalErr)   // wrapping — preserves chain

// ── Checking errors ───────────────────────────────────────
if err != nil { ... }                    // exists?
errors.Is(err, sentinel)                // is it (or wrapped?) this sentinel?
errors.As(err, &target)                 // extract typed error from chain

// ── Sentinel errors ───────────────────────────────────────
var ErrNotFound = errors.New("not found")

// ── Custom error type ────────────────────────────────────
type ValidationError struct {
    Field string
    Value any
}
func (e *ValidationError) Error() string {
    return fmt.Sprintf("%s: invalid %v", e.Field, e.Value)
}
func (e *ValidationError) Unwrap() error { // optional — for chaining
    return e.Err
}

// ── errors.As usage ──────────────────────────────────────
var valErr *ValidationError
if errors.As(err, &valErr) {
    fmt.Println(valErr.Field) // access typed fields
}

// ── errors.Join (Go 1.20+) ────────────────────────────────
err := errors.Join(err1, err2, err3)

// ── Wrapping rules ────────────────────────────────────────
// %w — preserves chain for errors.Is/As
// %v/%s — formats message, breaks chain
// Wrap implementation details you want the caller to inspect
// Do not wrap sentinel errors themselves — return them directly
// Do not wrap errors that leak internal implementation

// ── panic rules ───────────────────────────────────────────
// panic — programmer errors, invariants, unrecoverable states
// recover — only works inside defer, catches panic value
// Do NOT use panic/recover as exceptions
// Expected failures → return error

// ── log.Fatal ─────────────────────────────────────────────
log.Fatal("msg")   // prints message, calls os.Exit(1)
// DEFERRED FUNCTIONS DO NOT RUN after log.Fatal!
// Use only in main() for startup failures

// ── Common patterns ──────────────────────────────────────
if err := do(); err != nil {         // scoped error variable
    return fmt.Errorf("do: %w", err) // wrap with context
}

// ── Defer + error capture ────────────────────────────────
func do() (err error) {
    f, _ := os.Open("f")
    defer func() {
        if ce := f.Close(); ce != nil && err == nil {
            err = ce
        }
    }()
    return nil
}

// ── Goroutine error collection ───────────────────────────
errCh := make(chan error, n) // buffered channel
go func() {
    errCh <- do()
}()
err := <-errCh

// ── Mistakes to avoid ─────────────────────────────────────
// ❌ Ignoring errors:  result, _ := do()
// ❌ == with sentinels: err == io.EOF (use errors.Is)
// ❌ Typed nil error:   var e *MyError; return e (return nil)
// ❌ Log + return:      logs double, caller cannot suppress
// ❌ Panic for expected failures (file not found)
// ❌ Swallowing defer errors without checking
```

---

_Previous: [[10 - Interfaces]] · Next: [[12 - Goroutines]]_
