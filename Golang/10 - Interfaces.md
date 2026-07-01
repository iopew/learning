## Table of Contents

- [[#What is an Interface? — A Contract, Not Inheritance]]
- [[#Implicit Satisfaction — No implements Keyword]]
- [[#Defining Interfaces]]
- [[#Small Interfaces — io.Reader, io.Writer, fmt.Stringer]]
- [[#Interface Values — Type + Value Pair]]
- [[#Nil Interfaces vs Nil Concrete Values — The Nil Interface Trap]]
- [[#Empty Interface — any / interface{}]]
- [[#Type Assertions]]
- [[#Type Switches]]
- [[#Interface Composition]]
- [[#Interfaces and Polymorphism]]
- [[#Common Standard Library Interfaces]]
- [[#When NOT to Use Interfaces]]
- [[#Interface Satisfaction Check Pattern]]
- [[#Errors as Interfaces]]
- [[#Quick Reference Cheatsheet]]

---

## What is an Interface? — A Contract, Not Inheritance

An interface is a **contract**: a list of method signatures that a type must have in order to be usable wherever that interface is expected. It says nothing about _what_ the type is — only what it can _do_.

```go
type Greeter interface {
    Greet() string
}
```

This says: "anything with a `Greet() string` method counts as a `Greeter`." It doesn't matter if that thing is a `Person`, a `Robot`, or a `Dog` — if it has that method, it qualifies.

> [!info] This is fundamentally different from inheritance (covered in [[09 - Structs & Methods]]). Inheritance is about **what a type IS** (a Dog IS-A Animal). Interfaces are about **what a type CAN DO** (anything that CAN Greet). Go deliberately favors this "can-do" model over "is-a" hierarchies.

```go
type Person struct{ Name string }
func (p Person) Greet() string { return "Hi, I'm " + p.Name }

type Robot struct{ ID string }
func (r Robot) Greet() string { return "BEEP BOOP, UNIT " + r.ID }

// Both totally unrelated types satisfy Greeter
func sayHello(g Greeter) {
    fmt.Println(g.Greet())
}

sayHello(Person{Name: "Alice"}) // Hi, I'm Alice
sayHello(Robot{ID: "R2"})       // BEEP BOOP, UNIT R2
```

---

## Implicit Satisfaction — No implements Keyword

Unlike Java or C#, Go has **no `implements` keyword**. A type automatically satisfies an interface simply by having the required methods — there's no declaration linking them.

```go
type Writer interface {
    Write(p []byte) (n int, err error)
}

type Logger struct{}

// Logger never says "implements Writer" anywhere.
// It just happens to have a matching method:
func (l Logger) Write(p []byte) (int, error) {
    fmt.Print(string(p))
    return len(p), nil
}

var w Writer = Logger{} // ✅ works — implicit satisfaction
```

### Why does Go do this?

> [!tip] Implicit satisfaction means you can define an interface **after** the type already exists — even in a completely different package you don't control. You can write an interface today that's satisfied by code someone wrote years ago, as long as the method signatures line up. This makes Go interfaces extremely flexible for decoupling code.

```go
// Standard library type — you didn't write this, can't modify it
// os.File already has a Read(p []byte) (n int, err error) method

// You can still define your own interface that os.File happens to satisfy:
type MyReader interface {
    Read(p []byte) (n int, err error)
}

var r MyReader = someOSFile // ✅ works — os.File already had the right method
```

---

## Defining Interfaces

```go
type Interface_Name interface {
    Method1(params) returnType
    Method2(params) returnType
}
```

```go
type Shape interface {
    Area() float64
    Perimeter() float64
}

type Rectangle struct {
    Width, Height float64
}

func (r Rectangle) Area() float64      { return r.Width * r.Height }
func (r Rectangle) Perimeter() float64 { return 2 * (r.Width + r.Height) }

type Circle struct {
    Radius float64
}

func (c Circle) Area() float64      { return math.Pi * c.Radius * c.Radius }
func (c Circle) Perimeter() float64 { return 2 * math.Pi * c.Radius }

shapes := []Shape{
    Rectangle{Width: 3, Height: 4},
    Circle{Radius: 5},
}

for _, s := range shapes {
    fmt.Printf("Area: %.2f, Perimeter: %.2f\n", s.Area(), s.Perimeter())
}
```

A type must implement **every** method in the interface to satisfy it — there's no partial satisfaction.

---

## Small Interfaces — io.Reader, io.Writer, fmt.Stringer

Go's standard library favors small, single-purpose interfaces — often with just one method. This is a deliberate design philosophy.

```go
type Reader interface {
    Read(p []byte) (n int, err error)
}

type Writer interface {
    Write(p []byte) (n int, err error)
}

type Stringer interface {
    String() string
}
```

> [!tip] The famous Go proverb: **"The bigger the interface, the weaker the abstraction."** A one-method interface is trivially easy for any type to satisfy, which makes it maximally reusable. `io.Reader` is implemented by files, network connections, byte buffers, compressed streams, HTTP bodies, and more — all because it asks for almost nothing.

```go
// Any of these can be passed to a function expecting an io.Reader:
strings.NewReader("hello")
bytes.NewReader([]byte("hello"))
os.Open("file.txt")           // returns *os.File, which implements Reader
http.Response.Body            // implements Reader
```

Small interfaces compose well — you'll see this in [[#Interface Composition]] below, where `io.ReadWriter` is built by combining `Reader` and `Writer`.

---

## Interface Values — Type + Value Pair

An interface value in Go is internally a **pair**: the concrete type stored, and the actual value.

```go
var s Shape // interface value: (type=nil, value=nil)

s = Circle{Radius: 5}
// now: (type=Circle, value={Radius:5})

s = Rectangle{Width: 2, Height: 3}
// now: (type=Rectangle, value={Width:2, Height:3})
```

You can inspect this pair at runtime:

```go
fmt.Printf("%T\n", s) // main.Rectangle — the dynamic TYPE
fmt.Println(s)        // {2 3}         — the dynamic VALUE
```

> [!info] This is why interfaces can hold _any_ type that satisfies them — the interface variable isn't a fixed-size box for a specific type, it's a two-word structure: a pointer to type information, and a pointer (or small value) for the actual data.

---

## Nil Interfaces vs Nil Concrete Values — The Nil Interface Trap

This is one of the most infamous Go gotchas. An interface value is only truly `nil` when **both** its type and value are nil. A nil concrete value stored inside a non-nil interface type is **NOT** a nil interface.

```go
type MyError struct{}
func (e *MyError) Error() string { return "something broke" }

func doSomething() error {
    var err *MyError = nil // a nil pointer, but a real, non-nil TYPE
    return err              // returns an interface wrapping (type=*MyError, value=nil)
}

func main() {
    err := doSomething()
    if err != nil {
        fmt.Println("Error occurred!") // this PRINTS — surprising!
    }
}
```

### Why does this happen?

```
err's interface value = (type: *MyError, value: nil)
nil                    = (type: nil,     value: nil)
```

`err != nil` compares the whole pair, not just the value. Since `err`'s **type** is `*MyError` (not nil), the comparison `err != nil` is `true` — even though the underlying pointer is nil.

> [!warning] The fix: **never return a typed nil pointer as an interface value if you intend "no error."** Return a literal `nil` directly instead.

```go
func doSomething() error {
    var errPtr *MyError = nil
    if somethingWentWrong {
        return errPtr // fine if genuinely returning an error
    }
    return nil // ✅ return untyped nil directly — this really is a nil interface
}
```

```go
// The safest pattern: don't declare typed nil vars for errors at all
func doSomething() error {
    if somethingWentWrong {
        return &MyError{}
    }
    return nil // clean, unambiguous
}
```

---

## Empty Interface — any / interface{}

The empty interface has **zero methods**, which means **every type** satisfies it — it can hold a value of any type.

```go
var x interface{} // old syntax
var y any          // modern syntax (Go 1.18+), identical meaning — 'any' is an alias

x = 42
x = "hello"
x = []int{1, 2, 3}
x = Person{Name: "Alice"}
// all valid — any type satisfies an interface with zero method requirements
```

### Common use cases

```go
// Generic-ish containers before Go had real generics
func printAnything(v any) {
    fmt.Println(v)
}

// JSON unmarshaling into unknown structure
var data map[string]any
json.Unmarshal(jsonBytes, &data)
```

> [!warning] The empty interface sacrifices type safety — the compiler can't check what you do with the value at compile time. You need a type assertion or type switch to use it meaningfully. Prefer generics (covered later in the curriculum) or concrete/small interfaces when possible; reach for `any` only when you truly don't know or care about the type ahead of time.

---

## Type Assertions

A type assertion extracts the concrete value out of an interface, asserting it's a specific type.

### Single-value form — panics if wrong

```go
var s Shape = Circle{Radius: 5}

c := s.(Circle) // asserts s holds a Circle
fmt.Println(c.Radius) // 5

r := s.(Rectangle) // panic! s does NOT hold a Rectangle
```

### Two-value form — safe, returns ok bool

```go
var s Shape = Circle{Radius: 5}

c, ok := s.(Circle)
if ok {
    fmt.Println("It's a circle:", c.Radius)
}

r, ok := s.(Rectangle)
if !ok {
    fmt.Println("Not a rectangle") // this branch runs
}
```

> [!warning] Always prefer the two-value form unless you are certain of the type (or want the program to crash loudly on a genuine bug). The single-value form panics on mismatch — a common source of runtime crashes in careless code.

---

## Type Switches

A type switch lets you branch on the concrete type stored in an interface — cleaner than a chain of type assertions.

```go
func describe(i any) {
    switch v := i.(type) {
    case int:
        fmt.Println("int:", v*2)
    case string:
        fmt.Println("string, length:", len(v))
    case bool:
        fmt.Println("bool:", !v)
    case Circle:
        fmt.Println("circle with radius:", v.Radius)
    case nil:
        fmt.Println("nil value")
    default:
        fmt.Printf("unknown type: %T\n", v)
    }
}

describe(42)             // int: 84
describe("hello")        // string, length: 5
describe(true)           // bool: false
describe(Circle{Radius: 3}) // circle with radius: 3
describe(3.14)           // unknown type: float64
```

Inside each `case`, `v` is automatically typed as that specific case's type — no manual assertion needed within the branch.

---

## Interface Composition

Interfaces can be built by embedding other interfaces — combining smaller contracts into a larger one.

```go
type Reader interface {
    Read(p []byte) (n int, err error)
}

type Writer interface {
    Write(p []byte) (n int, err error)
}

// Composed from two smaller interfaces
type ReadWriter interface {
    Reader
    Writer
}
```

A type satisfies `ReadWriter` only if it implements **both** `Read` and `Write`:

```go
type File struct{}
func (f File) Read(p []byte) (int, error)  { return 0, nil }
func (f File) Write(p []byte) (int, error) { return 0, nil }

var rw ReadWriter = File{} // ✅ works — File has both methods
```

This mirrors composition in structs ([[09 - Structs & Methods]]) — build bigger contracts out of small, focused pieces rather than writing one giant interface from scratch.

```go
// The real io.ReadWriter is defined exactly this way in the standard library
type ReadWriter interface {
    Reader
    Writer
}
```

---

## Interfaces and Polymorphism

Polymorphism means writing code that works across many different concrete types, as long as they share a common interface — "one interface, many implementations."

```go
type Shape interface {
    Area() float64
}

type Rectangle struct{ Width, Height float64 }
func (r Rectangle) Area() float64 { return r.Width * r.Height }

type Triangle struct{ Base, Height float64 }
func (t Triangle) Area() float64 { return 0.5 * t.Base * t.Height }

type Circle struct{ Radius float64 }
func (c Circle) Area() float64 { return math.Pi * c.Radius * c.Radius }

// totalArea works with ANY slice of Shapes, regardless of concrete type
func totalArea(shapes []Shape) float64 {
    total := 0.0
    for _, s := range shapes {
        total += s.Area()
    }
    return total
}

shapes := []Shape{
    Rectangle{Width: 3, Height: 4},
    Triangle{Base: 6, Height: 2},
    Circle{Radius: 2},
}

fmt.Println(totalArea(shapes)) // works across three totally different types
```

> [!info] This is Go's version of polymorphism — no class hierarchy required. `totalArea` doesn't know or care whether it's summing rectangles, triangles, or circles. It only needs each element to satisfy `Shape`.

---

## Common Standard Library Interfaces

|Interface|Method(s)|Purpose|
|---|---|---|
|`io.Reader`|`Read(p []byte) (n int, err error)`|reading a stream of bytes|
|`io.Writer`|`Write(p []byte) (n int, err error)`|writing a stream of bytes|
|`io.Closer`|`Close() error`|releasing resources (files, connections)|
|`io.ReadWriter`|`Read` + `Write`|composed — supports both|
|`fmt.Stringer`|`String() string`|custom readable formatting|
|`error`|`Error() string`|representing failure|
|`sort.Interface`|`Len()`, `Less(i, j int) bool`, `Swap(i, j int)`|making a collection sortable|

### sort.Interface example

```go
type ByAge []Person

func (a ByAge) Len() int           { return len(a) }
func (a ByAge) Less(i, j int) bool { return a[i].Age < a[j].Age }
func (a ByAge) Swap(i, j int)      { a[i], a[j] = a[j], a[i] }

people := []Person{
    {Name: "Bob", Age: 31},
    {Name: "Alice", Age: 25},
}

sort.Sort(ByAge(people))
// people is now sorted by Age ascending
```

> [!info] Implementing `sort.Interface`'s three methods lets `sort.Sort` work on any custom collection — this predates generics in Go and is still common in older or performance-sensitive code, though `sort.Slice` with a comparison function is more concise for quick one-off sorts.

---

## When NOT to Use Interfaces

> [!warning] A very common beginner mistake is over-abstracting — defining an interface for every struct "just in case," even when there's only ever one implementation.

```go
// ❌ Unnecessary — there's only ever one UserRepository implementation
type UserRepository interface {
    GetUser(id string) (*User, error)
}

type userRepo struct{ db *sql.DB }
func (r *userRepo) GetUser(id string) (*User, error) { ... }

// Just use the concrete type directly instead:
type UserRepo struct{ db *sql.DB }
func (r *UserRepo) GetUser(id string) (*User, error) { ... }
```

### The Go proverb on this

> [!tip] **"Accept interfaces, return structs."** Function parameters should often be interfaces (for flexibility/testability), but return concrete types, not interfaces — this keeps callers able to see the full API of what they get back, and avoids unnecessary abstraction.

**Reasonable reasons to introduce an interface:**

- You genuinely have multiple implementations (e.g. a real database and a mock for tests)
- You're defining a contract for external packages to implement against
- You need to decouple a package's internals from its callers deliberately

**Not good reasons:**

- "Just in case I need to swap the implementation later" (you can refactor to an interface later, when actually needed — Go's implicit satisfaction makes this cheap)
- Every struct automatically gets a matching interface as a matter of habit

---

## Interface Satisfaction Check Pattern

A common idiom to catch, at **compile time**, whether a type actually satisfies an interface it's meant to — without waiting to discover a mismatch at runtime.

```go
type Shape interface {
    Area() float64
}

type Circle struct{ Radius float64 }
func (c *Circle) Area() float64 { return math.Pi * c.Radius * c.Radius }

// Compile-time check: does *Circle satisfy Shape?
var _ Shape = (*Circle)(nil)
```

### How this works

`(*Circle)(nil)` creates a nil pointer of type `*Circle` (never actually used at runtime — it's purely for the type checker). Assigning it to `_ Shape` forces the compiler to verify `*Circle` satisfies `Shape` **right here, right now** — if it doesn't, you get a compile error immediately, at the point of definition, rather than discovering it later when something tries to actually use `*Circle` as a `Shape`.

```go
// If Area() had the wrong signature or was missing, this line alone
// would fail to compile — pinpointing the exact problem immediately:
var _ Shape = (*Circle)(nil) // ❌ compile error if *Circle doesn't satisfy Shape
```

> [!tip] This pattern is extremely common in the standard library and well-written Go packages — placed right after a type definition, it documents intent ("this type is meant to implement this interface") and fails fast if that intent is ever broken by a future edit.

---

## Errors as Interfaces

`error` is just another interface — with exactly one method:

```go
type error interface {
    Error() string
}
```

Any type with an `Error() string` method satisfies `error` and can be returned as one.

```go
type NotFoundError struct {
    ID string
}

func (e *NotFoundError) Error() string {
    return fmt.Sprintf("resource %s not found", e.ID)
}

func findUser(id string) (*User, error) {
    if id == "" {
        return nil, &NotFoundError{ID: id}
    }
    return &User{ID: id}, nil
}

_, err := findUser("")
if err != nil {
    fmt.Println(err) // "resource  not found" — Error() called automatically by fmt
}
```

### Custom error types + type assertions

Because errors are just interface values, you can type-assert them to extract structured information:

```go
_, err := findUser("")
var nfErr *NotFoundError
if errors.As(err, &nfErr) {
    fmt.Println("Missing ID:", nfErr.ID)
}
```

> [!info] This connects directly back to [[#Nil Interfaces vs Nil Concrete Values — The Nil Interface Trap]] — `error` being an interface is exactly why the nil interface trap happens with error-returning functions specifically. Always be deliberate about returning literal `nil`, not a nil-valued typed pointer, when a function succeeds.

---

## Quick Reference Cheatsheet

```go
// === DEFINING ===
type Shape interface {
    Area() float64
}

// === IMPLICIT SATISFACTION — no "implements" keyword ===
type Circle struct{ Radius float64 }
func (c Circle) Area() float64 { return math.Pi * c.Radius * c.Radius }
var s Shape = Circle{Radius: 5} // just works, no declaration needed

// === INTERFACE VALUE — type + value pair ===
var s Shape          // (nil, nil)
s = Circle{Radius: 5} // (Circle, {5})

// === NIL INTERFACE TRAP ===
var errPtr *MyError = nil
var err error = errPtr  // err != nil is TRUE! (type=*MyError, value=nil)
// Fix: return literal nil directly for "no error"

// === EMPTY INTERFACE ===
var x any = 42          // any type satisfies interface{}/any

// === TYPE ASSERTION ===
c := s.(Circle)         // panics if wrong
c, ok := s.(Circle)     // safe, ok=false if wrong

// === TYPE SWITCH ===
switch v := i.(type) {
case int:
    // v is int here
case string:
    // v is string here
default:
    // v is the original type
}

// === INTERFACE COMPOSITION ===
type ReadWriter interface {
    Reader
    Writer
}

// === COMMON STDLIB INTERFACES ===
io.Reader   { Read(p []byte) (int, error) }
io.Writer   { Write(p []byte) (int, error) }
io.Closer   { Close() error }
fmt.Stringer{ String() string }
error       { Error() string }

// === SATISFACTION CHECK PATTERN ===
var _ Shape = (*Circle)(nil) // compile-time check

// === ERRORS ===
type MyErr struct{ Msg string }
func (e *MyErr) Error() string { return e.Msg }
errors.As(err, &target) // extract typed error info

// === GO PROVERBS TO REMEMBER ===
// "The bigger the interface, the weaker the abstraction."
// "Accept interfaces, return structs."
```

---

### Key Rules to Remember

|Rule|Detail|
|---|---|
|Contract, not inheritance|interfaces define behavior (what you CAN DO), not identity|
|No `implements` keyword|satisfaction is implicit, structural, checked by the compiler|
|Small interfaces|prefer 1-2 methods; more reusable, "the bigger the interface, the weaker the abstraction"|
|Interface value|internally a (type, value) pair|
|Nil interface trap|a nil concrete value in a non-nil-typed interface is NOT a nil interface|
|Empty interface|zero methods, every type satisfies it — use sparingly|
|Type assertion|prefer two-value form (`v, ok := x.(T)`) to avoid panics|
|Type switch|cleanest way to branch across multiple possible concrete types|
|Composition|build big interfaces from small ones via embedding|
|Don't over-abstract|only introduce an interface when you have a real reason to|
|Satisfaction check|`var _ Interface = (*Type)(nil)` catches mismatches at compile time|
|`error` is an interface|just `Error() string` — same nil trap applies|

---

Previous: [[09 - Structs & Methods]] · Next: [[11 - Error Handling]]