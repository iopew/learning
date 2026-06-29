## Table of Contents

- [[#What is a Pointer?]]
- [[#The & and * Operators]]
- [[#The *T Type Syntax]]
- [[#Nil Pointers and Panics]]
- [[#new(T)]]
- [[#Pointer to Struct — Automatic Dereferencing]]
- [[#Pass by Pointer vs Pass by Value]]
- [[#Pointers and Interfaces]]
- [[#Double Pointers (**T)]]
- [[#Pointer Receivers vs Value Receivers]]
- [[#Common Patterns]]
- [[#What Go Does NOT Have]]
- [[#Escape Analysis — Stack vs Heap]]
- [[#unsafe.Pointer]]
- [[#Quick Reference Cheatsheet]]

---

## What is a Pointer?

A pointer is a variable that stores the **memory address** of another variable — not the value itself, but _where_ the value lives in memory.

Think of memory like a street with numbered houses. A normal variable is the house. A pointer is a piece of paper with the house's address written on it.

```go
x := 42        // the house — stores the value 42
p := &x        // the paper — stores the address of x
```

This matters because:

- You can pass the address to a function, and the function can go to that address and **modify the original** value
- You can avoid copying large amounts of data by passing a reference instead

---

## The & and * Operators

There are two operators you need to know:

|Operator|Name|What it does|
|---|---|---|
|`&`|address-of|gives you the memory address of a variable|
|`*`|dereference|follows a pointer to get the value at that address|

```go
x := 42

p := &x         // & gives us the address of x
                // p is now something like 0xc000018080

fmt.Println(p)  // 0xc000018080  (a memory address)
fmt.Println(*p) // 42            (* follows the address to get the value)

*p = 100        // change the value AT that address
fmt.Println(x)  // 100 — x changed because p points to x
```

> [!tip] A helpful way to read these: `&x` means "address of x", `*p` means "value at p".

> [!warning] `&` and `*` are opposites — `&` goes from value → address, `*` goes from address → value.

---

## The *T Type Syntax

When you declare a pointer variable, the type is written as `*T` where `T` is the type it points to.

```go
var p *int        // p is a pointer to an int (currently nil)
var q *string     // q is a pointer to a string (currently nil)

x := 42
p = &x            // now p holds the address of x

name := "Alice"
q = &name         // now q holds the address of name
```

Reading types:

- `int` → a plain integer
- `*int` → a pointer to an integer
- `*string` → a pointer to a string
- `*[]int` → a pointer to a slice of ints

```go
// Full example
func double(n *int) {
    *n = *n * 2   // follow the pointer, multiply value by 2
}

x := 5
double(&x)
fmt.Println(x) // 10
```

---

## Nil Pointers and Panics

A pointer that hasn't been assigned an address holds the value `nil` — it points to nothing.

```go
var p *int
fmt.Println(p)  // <nil>
```

If you try to dereference a nil pointer (access the value it points to), your program **panics and crashes**:

```go
var p *int
fmt.Println(*p) // panic: runtime error: invalid memory address or nil pointer dereference
```

> [!warning] Always check if a pointer is nil before dereferencing it when the pointer might not have been set.

```go
func printValue(p *int) {
    if p == nil {
        fmt.Println("no value")
        return
    }
    fmt.Println(*p)
}
```

This is one of the most common runtime errors in Go — nil pointer dereference. The compiler won't catch it, only runtime will.

---

## new(T)

`new(T)` is a built-in function that:

1. Allocates memory for a value of type `T`
2. Sets it to its zero value
3. Returns a pointer to it (`*T`)

```go
p := new(int)
fmt.Println(*p) // 0 — zero value for int
fmt.Println(p)  // 0xc000018080 — a valid memory address

*p = 42
fmt.Println(*p) // 42
```

It's equivalent to:

```go
x := 0
p := &x
```

> [!info] `new(T)` is rarely used in practice. Most Go code uses struct literals or short variable declarations instead. You'll mostly see `new` used for simple types like `new(int)` or `new(bool)` when you need a pointer to a zero value.

```go
// These are equivalent:
p1 := new(int)

var x int
p2 := &x
```

---

## Pointer to Struct — Automatic Dereferencing

When you have a pointer to a struct, Go automatically dereferences it when you access fields. You don't need to write `(*p).field` — just `p.field` works.

```go
type Person struct {
    Name string
    Age  int
}

p := &Person{Name: "Alice", Age: 30}

// These are identical:
fmt.Println((*p).Name) // "Alice" — manual dereference
fmt.Println(p.Name)    // "Alice" — Go does it automatically
```

This is called **automatic dereferencing** (or "syntactic sugar"). Go does it for you because writing `(*p).field` everywhere would be painful.

```go
// Modifying struct fields through a pointer
p.Age = 31         // same as (*p).Age = 31
fmt.Println(p.Age) // 31
```

> [!tip] In practice you'll almost never write `(*p).field`. Just use `p.field` and Go handles the rest.

---

## Pass by Pointer vs Pass by Value

In Go, everything is passed **by value** by default — the function gets a copy.

```go
func addTen(n int) {
    n += 10        // modifies the local copy only
}

x := 5
addTen(x)
fmt.Println(x) // still 5 — original unchanged
```

To let a function modify the original, pass a pointer:

```go
func addTen(n *int) {
    *n += 10       // follows the pointer, modifies the original
}

x := 5
addTen(&x)
fmt.Println(x) // 15 — original changed
```

### When to use each

**Use pass by value when:**

- The data is small (int, bool, float, small struct)
- You don't want the function to modify the original
- You want a clear, immutable function (easier to reason about)

```go
func area(width, height float64) float64 {
    return width * height  // no need to modify, pass by value
}
```

**Use pass by pointer when:**

- You need the function to modify the original value
- The struct is large and copying it would be expensive
- You want to signal that a value is optional (can be nil)

```go
type Config struct {
    // 50+ fields — copying this every call is wasteful
}

func applyDefaults(cfg *Config) {
    cfg.Timeout = 30
    cfg.MaxRetries = 3
}
```

> [!info] Slices, maps, and channels are already reference types internally — they contain a pointer under the hood. Passing them by value still lets functions modify the underlying data, so you rarely need `*[]int` or `*map[...]...`.

---

## Pointers and Interfaces

Interfaces in Go are satisfied by either value types or pointer types — but there's an important distinction.

```go
type Greeter interface {
    Greet() string
}

type Person struct {
    Name string
}

// Value receiver — both Person and *Person satisfy Greeter
func (p Person) Greet() string {
    return "Hello, " + p.Name
}

var g Greeter

g = Person{Name: "Alice"}   // ✅ works
g = &Person{Name: "Alice"}  // ✅ also works
```

```go
// Pointer receiver — only *Person satisfies Greeter
func (p *Person) Greet() string {
    return "Hello, " + p.Name
}

var g Greeter

g = Person{Name: "Alice"}   // ❌ does NOT work
g = &Person{Name: "Alice"}  // ✅ works
```

> [!warning] If any method on a type uses a pointer receiver, you must use a pointer (`&T`) when assigning to an interface. A value won't satisfy the interface.

The rule: a pointer type `*T` has access to both pointer receiver and value receiver methods. A value type `T` only has access to value receiver methods.

---

## Double Pointers (**T)

A double pointer is a pointer to a pointer. It stores the address of another pointer.

```go
x := 42
p := &x    // *int  — pointer to x
pp := &p   // **int — pointer to p (which points to x)

fmt.Println(x)   // 42
fmt.Println(*p)  // 42
fmt.Println(**pp) // 42

**pp = 100
fmt.Println(x)   // 100
```

### When would you actually use this?

Mostly when you need a function to modify a pointer itself (not just the value it points to):

```go
func makeNew(pp **int) {
    x := 99
    *pp = &x   // changes what the pointer points to
}

var p *int
makeNew(&p)
fmt.Println(*p) // 99
```

> [!info] Double pointers are uncommon in everyday Go code. You might see them when working with low-level APIs, certain data structures (like linked list nodes), or CGo. In most cases there's a cleaner Go-idiomatic alternative.

---

## Pointer Receivers vs Value Receivers

Methods in Go can be defined with either a value receiver or a pointer receiver.

```go
type Counter struct {
    count int
}

// Value receiver — works on a COPY
func (c Counter) Value() int {
    return c.count
}

// Pointer receiver — works on the ORIGINAL
func (c *Counter) Increment() {
    c.count++
}
```

```go
c := Counter{}
c.Increment()  // count is now 1
c.Increment()  // count is now 2
fmt.Println(c.Value()) // 2
```

### The consistency rule

> [!warning] If any method on a type uses a pointer receiver, all methods should use pointer receivers. Mixing them leads to confusion about interface satisfaction and subtle bugs.

```go
// ✅ Consistent — all pointer receivers
func (c *Counter) Increment() { c.count++ }
func (c *Counter) Reset()     { c.count = 0 }
func (c *Counter) Value() int { return c.count }

// ❌ Inconsistent — mixing receivers
func (c *Counter) Increment() { c.count++ }
func (c Counter) Value() int  { return c.count }  // avoid mixing
```

### When to use which

**Value receiver when:**

- The method doesn't need to modify the struct
- The struct is small and cheap to copy
- You want the method to work on a copy (safe, no side effects)

**Pointer receiver when:**

- The method needs to modify the struct
- The struct is large (avoid expensive copies)
- Consistency — other methods on the type use pointer receivers

---

## Common Patterns

### Optional values via nil

A pointer being nil naturally represents "no value" — useful for optional fields:

```go
type User struct {
    Name     string
    Nickname *string  // nil means no nickname set
}

nick := "gopher"
u1 := User{Name: "Alice", Nickname: &nick}
u2 := User{Name: "Bob"}   // Nickname is nil — not set

if u1.Nickname != nil {
    fmt.Println(*u1.Nickname) // "gopher"
}

if u2.Nickname == nil {
    fmt.Println("no nickname")
}
```

This is the Go equivalent of `null` / `None` / `Optional` in other languages.

### Mutation in functions

When you need a function to modify something and return multiple values is awkward:

```go
type Config struct {
    Debug   bool
    Timeout int
    Host    string
}

func configure(cfg *Config) {
    cfg.Debug = true
    cfg.Timeout = 30
    cfg.Host = "localhost"
}

cfg := &Config{}
configure(cfg)
fmt.Println(cfg.Debug)   // true
fmt.Println(cfg.Timeout) // 30
```

### Avoiding large copies

```go
type BigData struct {
    Records [100000]int
    // ... many more fields
}

// ❌ Copies the entire 800KB struct on every call
func processBad(data BigData) { ... }

// ✅ Passes just an 8-byte pointer
func processGood(data *BigData) { ... }
```

---

## What Go Does NOT Have

Go intentionally removed features that cause bugs in C/C++:

### No pointer arithmetic

In C you can do `p++` to move a pointer forward in memory. Go does not allow this:

```go
x := 42
p := &x
p++  // ❌ compile error: invalid operation
p+1  // ❌ compile error: invalid operation
```

This prevents entire classes of bugs like buffer overflows and out-of-bounds memory access.

### No manual memory management

In C you call `malloc` to allocate memory and `free` to release it. Forgetting to `free` causes memory leaks. Double-freeing causes crashes.

Go has a **garbage collector** — it automatically detects when memory is no longer reachable and reclaims it. You never call `free`.

```go
func makeSlice() *[]int {
    s := []int{1, 2, 3}
    return &s   // perfectly fine — Go's GC keeps this alive
}               // in C, returning a pointer to a local variable is dangerous
```

> [!tip] The tradeoff is that the garbage collector adds a small runtime overhead. For most applications this is completely acceptable. For extremely performance-sensitive systems code, Go provides `unsafe` escape hatches.

---

## Escape Analysis — Stack vs Heap

Go's compiler decides where to store each variable — on the **stack** or the **heap**.

### Stack

- Fast allocation and deallocation (just move a pointer)
- Automatically cleaned up when the function returns
- Limited size

### Heap

- Slower to allocate (garbage collector manages it)
- Lives as long as something references it
- Can be large

### How Go decides

The compiler runs **escape analysis** to figure out if a variable's lifetime extends beyond the function that creates it. If it does, the variable "escapes to the heap."

```go
func noEscape() int {
    x := 42      // stays on the stack — x doesn't escape
    return x     // returning the VALUE, not a reference
}

func escapes() *int {
    x := 42      // escapes to the heap — we're returning a pointer to x
    return &x    // x must outlive this function, so Go puts it on the heap
}
```

> [!info] You don't need to manage this manually — Go handles it for you. But it's useful to know because:
> 
> - Variables on the stack are faster
> - Lots of heap allocations can put pressure on the garbage collector
> - You can check what escapes with `go build -gcflags="-m" .`

```bash
# See escape analysis decisions
go build -gcflags="-m" .
# Output like: "./main.go:8:2: moved to heap: x"
```

> [!tip] Don't prematurely optimize for escape analysis. Write clear code first. Only investigate if profiling shows GC pressure is a real problem.

---

## unsafe.Pointer

`unsafe.Pointer` is a special pointer type that can hold the address of any type — bypassing Go's type system entirely.

```go
import "unsafe"

x := 42
p := unsafe.Pointer(&x)   // can point to anything
```

### Why it exists

Some very low-level operations genuinely need it:

- Interacting with C code via CGo
- Implementing certain runtime data structures
- Reading binary data at specific memory offsets
- Performance-critical code that needs to reinterpret memory

### Why you should almost never use it

> [!warning] `unsafe` lives up to its name. Using it:
> 
> - Bypasses Go's type safety — the compiler can't protect you
> - Can cause memory corruption, panics, or silent data corruption
> - Makes your code dependent on internal memory layout that can change between Go versions
> - Breaks garbage collector assumptions

```go
// ❌ Example of dangerous unsafe usage
x := float64(3.14)
bits := *(*uint64)(unsafe.Pointer(&x))  // reinterpret float64 bits as uint64
```

> [!tip] In 99% of Go programs you will never need `unsafe.Pointer`. If you think you need it, there's almost certainly a safer Go-idiomatic way to solve the problem. The standard library uses it internally so you don't have to.

---

## Quick Reference Cheatsheet

```go
// === BASICS ===
x := 42
p := &x          // & gives address of x → *int
fmt.Println(*p)  // * dereferences → 42
*p = 100         // modify value through pointer

// === TYPE SYNTAX ===
var p *int        // pointer to int (nil)
var q *string     // pointer to string (nil)

// === NIL CHECK ===
if p == nil {
    fmt.Println("no value")
}

// === new(T) ===
p := new(int)    // allocates, zero-valued, returns *int
*p = 42

// === STRUCT POINTER ===
type Point struct{ X, Y int }
p := &Point{X: 1, Y: 2}
p.X = 10         // auto-dereferenced (same as (*p).X = 10)

// === PASS BY VALUE vs POINTER ===
func readOnly(n int) {}       // copy — original safe
func mutate(n *int) { *n++ } // pointer — modifies original
mutate(&x)

// === RECEIVERS ===
func (c Counter) Value() int  { return c.count }  // value — copy
func (c *Counter) Inc()       { c.count++ }        // pointer — mutates

// === OPTIONAL VALUE PATTERN ===
type User struct {
    Nickname *string   // nil = not set
}

// === DOUBLE POINTER ===
pp := &p         // **int — pointer to pointer
**pp = 99

// === ESCAPE ANALYSIS ===
// go build -gcflags="-m" .

// === WHAT GO DOESN'T HAVE ===
// p++       ❌ no pointer arithmetic
// free(p)   ❌ no manual memory management
// unsafe.Pointer — exists but almost never needed
```

---

### Key Rules to Remember

|Rule|Detail|
|---|---|
|`&` gets address|`p := &x`|
|`*` dereferences|`*p` gives the value|
|nil pointer → panic|always check before dereferencing|
|Struct auto-deref|`p.Field` works, no need for `(*p).Field`|
|Pointer receivers|needed to mutate struct in methods|
|Consistency rule|don't mix pointer and value receivers on same type|
|No pointer arithmetic|Go prevents it by design|
|No manual free|garbage collector handles memory|
|Escape analysis|compiler decides stack vs heap automatically|
|`unsafe.Pointer`|exists, avoid it|

---

Previous: [[07 - Strings & Runes]] · Next: [[09 - Structs & Methods]]