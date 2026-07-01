## Table of Contents

- [[#Struct Syntax]]
- [[#Field Access]]
- [[#Struct Literals — Named vs Positional]]
- [[#Anonymous Structs]]
- [[#Zero Value Structs]]
- [[#Struct Embedding — Composition Over Inheritance]]
- [[#Promoted Fields and Methods]]
- [[#Struct Tags]]
- [[#Comparing Structs]]
- [[#Copying Structs]]
- [[#Methods — Value vs Pointer Receivers]]
- [[#Method Sets]]
- [[#Method Values vs Method Expressions]]
- [[#Constructor Functions]]
- [[#The Stringer Interface]]
- [[#Embedding Interfaces in Structs]]
- [[#Struct Design Patterns]]
- [[#Quick Reference Cheatsheet]]

---

## Struct Syntax

A struct is a typed collection of named fields — Go's way of grouping related data together.

```go
type Person struct {
    Name string
    Age  int
    City string
}
```

`type Person struct { ... }` defines a new type called `Person`. Each line inside is a **field**: a name followed by its type.

```go
// Multiple fields of the same type can share one line
type Point struct {
    X, Y int
}
```

> [!info] Struct field names conventionally start with an uppercase letter (`Name`, not `name`) if you want them accessible from other packages — uppercase means exported, lowercase means package-private. This is the same rule that applies to functions and variables.

---

## Field Access

You access struct fields using the dot `.` operator:

```go
p := Person{Name: "Alice", Age: 30, City: "Tashkent"}

fmt.Println(p.Name) // "Alice"
fmt.Println(p.Age)  // 30

p.Age = 31           // fields are mutable
fmt.Println(p.Age)   // 31
```

If you have a pointer to a struct, field access works the same way thanks to automatic dereferencing (covered in [[08 - Pointers]]):

```go
pp := &p
fmt.Println(pp.Name) // "Alice" — auto-dereferenced, no need for (*pp).Name
pp.Age = 32
fmt.Println(p.Age)   // 32 — modifies the original through the pointer
```

---

## Struct Literals — Named vs Positional

### Named fields (recommended)

You specify which value goes with which field name:

```go
p := Person{
    Name: "Alice",
    Age:  30,
    City: "Tashkent",
}
```

Fields can be in any order, and you can omit fields (they default to their zero value):

```go
p := Person{Name: "Bob"}  // Age: 0, City: ""
```

### Positional fields

You provide values in the exact order the fields were declared — **all fields are required**:

```go
p := Person{"Alice", 30, "Tashkent"}
// Name="Alice", Age=30, City="Tashkent" — order matters!
```

> [!warning] Positional struct literals are fragile. If someone reorders the struct's fields or adds a new field, every positional literal silently breaks or shifts values into the wrong fields. Always prefer named fields except for very small, stable structs (like `Point{X, Y}`).

```go
// This compiles fine but is a trap waiting to happen:
type Point struct{ X, Y int }
p := Point{1, 2}  // X=1, Y=2 — fine here, but risky habit for bigger structs
```

---

## Anonymous Structs

A struct type can be declared inline, without a name, when you only need it once:

```go
point := struct {
    X, Y int
}{
    X: 10,
    Y: 20,
}

fmt.Println(point.X, point.Y) // 10 20
```

### When this is useful

Common in tests (table-driven test cases) or one-off data shapes you don't need to reuse elsewhere:

```go
tests := []struct {
    input    int
    expected int
}{
    {input: 2, expected: 4},
    {input: 3, expected: 9},
    {input: 5, expected: 25},
}

for _, tc := range tests {
    result := tc.input * tc.input
    if result != tc.expected {
        fmt.Printf("FAIL: got %d, want %d\n", result, tc.expected)
    }
}
```

> [!tip] If you find yourself reusing the same anonymous struct shape in multiple places, that's a signal to give it a proper named type instead.

---

## Zero Value Structs

Every struct has a zero value — when you declare one without initializing it, every field gets its own type's zero value.

```go
type Person struct {
    Name string
    Age  int
    City string
}

var p Person
fmt.Println(p) // {  0 }
fmt.Println(p.Name) // ""  — zero value for string
fmt.Println(p.Age)  // 0   — zero value for int
fmt.Println(p.City) // ""  — zero value for string
```

```go
type Config struct {
    Debug    bool
    Timeout  int
    Tags     []string
    Settings map[string]string
}

var cfg Config
fmt.Println(cfg.Debug)    // false
fmt.Println(cfg.Timeout)  // 0
fmt.Println(cfg.Tags)     // [] (nil slice)
fmt.Println(cfg.Settings) // map[] (nil map)
```

> [!warning] A zero-value struct is **ready to use** — there's no concept of an "uninitialized" struct causing a crash, unlike pointers. But nested reference types (slices, maps, pointers, channels) inside it are `nil`, and using them incorrectly (e.g. writing to a nil map) will still panic.

```go
var cfg Config
cfg.Settings["debug"] = "true" // panic: assignment to entry in nil map
```

---

## Struct Embedding — Composition Over Inheritance

Go has no class inheritance. Instead, structs achieve code reuse through **embedding** — placing one struct inside another without a field name.

```go
type Animal struct {
    Name string
    Age  int
}

type Dog struct {
    Animal      // embedded — no field name, just the type
    Breed string
}

d := Dog{
    Animal: Animal{Name: "Rex", Age: 3},
    Breed:  "Labrador",
}

fmt.Println(d.Name)  // "Rex" — accessed directly, as if it were Dog's own field
fmt.Println(d.Breed) // "Labrador"
```

This is **composition**, not inheritance. `Dog` doesn't "extend" `Animal` — it literally **contains** an `Animal` value as an anonymous field. Go just gives you direct access to its fields as a convenience.

### Why composition instead of inheritance?

> [!info] Inheritance creates tight coupling and deep hierarchies that become hard to reason about (the classic "fragile base class" problem). Composition is more flexible — you build complex types by combining small, focused pieces, and you can embed multiple types without the diamond-inheritance problems found in some other languages.

```go
type Engine struct {
    Horsepower int
}

type Wheels struct {
    Count int
}

// A Car is composed of an Engine and Wheels — not "inherited" from them
type Car struct {
    Engine
    Wheels
    Model string
}

c := Car{
    Engine: Engine{Horsepower: 300},
    Wheels: Wheels{Count: 4},
    Model:  "Tesla",
}
fmt.Println(c.Horsepower, c.Count, c.Model) // 300 4 Tesla
```

---

## Promoted Fields and Methods

When you embed a struct, its fields **and methods** become directly accessible on the outer struct — this is called **promotion**.

```go
type Animal struct {
    Name string
}

func (a Animal) Speak() string {
    return a.Name + " makes a sound"
}

type Dog struct {
    Animal
    Breed string
}

d := Dog{Animal: Animal{Name: "Rex"}, Breed: "Labrador"}

fmt.Println(d.Speak()) // "Rex makes a sound" — promoted method!
```

`Dog` never defined `Speak()` itself — it got it for free from the embedded `Animal`. This is how Go achieves method reuse without inheritance.

### Overriding a promoted method

If `Dog` defines its own method with the same name, it **shadows** the embedded one:

```go
func (d Dog) Speak() string {
    return d.Name + " barks"
}

fmt.Println(d.Speak()) // "Rex barks" — Dog's own method wins
fmt.Println(d.Animal.Speak()) // "Rex makes a sound" — explicit access to the embedded method
```

### Promotion only goes one level deep automatically per hop, but chains naturally

```go
type Base struct{ ID int }
type Middle struct{ Base }
type Outer struct{ Middle }

o := Outer{Middle: Middle{Base: Base{ID: 1}}}
fmt.Println(o.ID) // 1 — promoted through two levels of embedding
```

> [!warning] If two embedded structs both have a field or method with the same name, you must disambiguate manually (`d.Animal.Name` vs `d.Robot.Name`) — Go won't guess which one you mean, and accessing the ambiguous name directly causes a compile error.

---

## Struct Tags

A struct tag is metadata attached to a field, written as a backtick-quoted string after the type. It's read by reflection at runtime — most commonly by `encoding/json`.

```go
type User struct {
    Name  string `json:"name"`
    Email string `json:"email"`
    Age   int    `json:"age,omitempty"`
    password string `json:"-"` // unexported, json ignores anyway
}
```

### Common json tag options

```go
type Product struct {
    ID       int     `json:"id"`
    Name     string  `json:"name"`
    Price    float64 `json:"price,omitempty"` // omit field if zero value
    Internal string  `json:"-"`                // never include in JSON
    SKU      string  `json:"sku_code"`         // rename the JSON key
}
```

|Tag|Meaning|
|---|---|
|`json:"name"`|use `"name"` as the JSON key instead of the Go field name|
|`json:"-"`|exclude this field from JSON entirely|
|`json:",omitempty"`|omit the field if it has its zero value|
|`json:"name,omitempty"`|rename AND omit if zero|

### Other common tags

```go
type Record struct {
    ID    int    `db:"id"`
    Name  string `db:"full_name" validate:"required,min=2"`
    Email string `validate:"required,email"`
}
```

`db` tags are used by some database/ORM libraries to map struct fields to column names. `validate` tags are used by validation libraries (like `go-playground/validator`) to enforce rules. Go itself doesn't interpret these tags — they're just strings that specific libraries choose to read via reflection.

> [!tip] Struct tags are completely inert without a library reading them. They're just metadata strings stored alongside the field — `encoding/json`, validators, and ORMs use the `reflect` package to read and act on them at runtime.

---

## Comparing Structs

Structs can be compared with `==` and `!=` **only if every field is comparable**.

```go
type Point struct{ X, Y int }

p1 := Point{1, 2}
p2 := Point{1, 2}
p3 := Point{3, 4}

fmt.Println(p1 == p2) // true — all fields equal
fmt.Println(p1 == p3) // false
```

### What makes a field "comparable"?

Basic types (int, string, bool, float), arrays, and structs made entirely of comparable types are comparable. Slices, maps, and functions are **not** comparable.

```go
type Bad struct {
    Tags []string // slice — not comparable
}

b1 := Bad{Tags: []string{"a"}}
b2 := Bad{Tags: []string{"a"}}
// b1 == b2 // ❌ compile error: invalid operation, struct containing []string cannot be compared
```

If you need to compare structs with non-comparable fields, use `reflect.DeepEqual`:

```go
import "reflect"

fmt.Println(reflect.DeepEqual(b1, b2)) // true — deep comparison
```

> [!warning] `reflect.DeepEqual` is slower than `==` because it recursively walks the entire structure. Use `==` whenever possible; reach for `DeepEqual` only when the struct contains slices, maps, or other non-comparable fields.

---

## Copying Structs

Assigning a struct or passing it by value creates a **complete copy** — every field is duplicated.

```go
type Point struct{ X, Y int }

p1 := Point{X: 1, Y: 2}
p2 := p1        // copies p1 entirely

p2.X = 100
fmt.Println(p1.X) // 1   — unaffected
fmt.Println(p2.X) // 100 — only the copy changed
```

### The gotcha with embedded reference types

If a struct contains a slice or map, copying the struct copies the **slice header** or **map reference**, not the underlying data — so both copies still point to the same backing array/map.

```go
type Bag struct {
    Items []string
}

b1 := Bag{Items: []string{"a", "b"}}
b2 := b1            // copies the struct, but Items slice header points to same array

b2.Items[0] = "z"
fmt.Println(b1.Items[0]) // "z" — b1 affected too! Same underlying array.
```

> [!warning] Copying a struct does NOT deep-copy slices, maps, or pointers inside it. If you need true independence, you must manually copy those fields (e.g. `copy()` for slices, or building a new map).

---

## Methods — Value vs Pointer Receivers

A method is a function attached to a type via a receiver. (This was covered in depth in [[08 - Pointers]] — quick recap here for context.)

```go
type Counter struct{ count int }

// Value receiver — operates on a copy
func (c Counter) Value() int { return c.count }

// Pointer receiver — operates on the original
func (c *Counter) Increment() { c.count++ }
```

### The consistency rule

If any method on a type uses a pointer receiver, all methods on that type should use pointer receivers — mixing them creates confusion about which variables satisfy interfaces and invites subtle mutation bugs.

```go
// ✅ Consistent
func (c *Counter) Increment() { c.count++ }
func (c *Counter) Value() int { return c.count }
```

---

## Method Sets

A type's **method set** is the collection of methods that can be called on a value of that type.

|Receiver type of a value|Method set includes|
|---|---|
|`T` (value)|only methods with value receivers|
|`*T` (pointer)|methods with both value AND pointer receivers|

```go
type Counter struct{ count int }

func (c Counter) Value() int  { return c.count }  // value receiver
func (c *Counter) Inc()       { c.count++ }        // pointer receiver

c := Counter{}
c.Inc()           // ✅ Go automatically takes &c for you here
fmt.Println(c.Value())

var ic interface{ Inc() }
// ic = c          // ❌ Counter's method set does NOT include Inc (pointer receiver)
ic = &c            // ✅ *Counter's method set includes both Value and Inc
```

> [!info] When calling a method directly on an addressable variable (like a local variable `c`), Go automatically takes its address for you if needed. This auto-addressing does NOT happen for interface satisfaction — that's checked strictly by method set rules, which is why `Counter` (not `*Counter`) fails to satisfy an interface requiring `Inc()`.

### Why *T's method set is bigger than T's

It can feel backwards at first — shouldn't the plain value have access to everything? It doesn't, and here's the reasoning:

A pointer (`*T`) holds an **address**. From an address you can always reach the underlying value — just dereference it (`*p`). So a pointer can do everything a value can, _plus_ it can mutate through that address.

A value (`T`) just holds **data**. It has no address information — it cannot produce a pointer to itself out of nowhere.

```
*T can derive T   (dereference: *p)
T cannot derive *T   (no address to give)
```

Since `*T` can always get to the underlying value, it can call **value receiver methods** (which only need the data) — and it can obviously call **pointer receiver methods** too (it already has the address). So `*T`'s method set includes both.

`T` only has the data, no address — so it can only call **value receiver methods**.

```go
type Counter struct{ count int }
func (c Counter) Value() int { return c.count }  // value receiver
func (c *Counter) Inc()      { c.count++ }        // pointer receiver

var c Counter
c.Inc() // Go secretly rewrites this as (&c).Inc() — works here because
        // c is an addressable local variable in a direct call

var i interface{ Inc() } = c // ❌ fails — Counter's method set does NOT include Inc()
```

This is the key distinction: the auto-addressing trick (`(&c).Inc()`) only applies to **direct calls on addressable variables**. It does NOT apply to **interface satisfaction**, which is checked strictly against the declared method set at compile time. `Counter` was never declared to have `Inc()` — only `*Counter` was.

> [!tip] A simple way to remember it: a pointer is "value + address." A value is just "value." Since pointer ⊇ value in terms of what it carries, the pointer's capabilities are a superset of the value's. More information → more abilities, not less.

---

## Method Values vs Method Expressions

### Method value — a method bound to a specific receiver

```go
type Counter struct{ count int }
func (c *Counter) Increment() { c.count++ }

c := &Counter{}
inc := c.Increment   // "method value" — bound to c
inc()                // calls c.Increment() — c is already baked in
inc()
fmt.Println(c.count) // 2
```

`c.Increment` here is a function value that already has `c` captured — you can pass it around and call it later without needing `c` again.

### Method expression — a method as an unbound function

```go
type Counter struct{ count int }
func (c *Counter) Increment() { c.count++ }

incExpr := (*Counter).Increment  // "method expression" — receiver is explicit, first parameter

c := &Counter{}
incExpr(c)            // you must pass the receiver explicitly
incExpr(c)
fmt.Println(c.count)  // 2
```

`(*Counter).Increment` turns the method into a regular function whose **first parameter is the receiver**. You call it by passing the receiver explicitly, rather than it being pre-bound.

||Bound to receiver?|Call syntax|
|---|---|---|
|Method value|Yes (captured at creation)|`inc()`|
|Method expression|No (receiver passed manually)|`incExpr(c)`|

> [!info] Method values and expressions are uncommon in everyday code, but you'll see method values used for things like passing a method as a callback (`http.HandleFunc("/path", handler.ServeHTTP)`).

---

## Constructor Functions

Go has no built-in concept of a "constructor." Instead, the idiomatic pattern is a function named `New` (or `NewTypeName`) that builds and returns the type, often with default values or validation.

```go
type Server struct {
    Host    string
    Port    int
    Timeout int
}

func NewServer(host string, port int) *Server {
    return &Server{
        Host:    host,
        Port:    port,
        Timeout: 30, // sensible default
    }
}

s := NewServer("localhost", 8080)
fmt.Println(s.Host, s.Port, s.Timeout) // localhost 8080 30
```

### Why use a constructor instead of a plain struct literal?

> [!tip] Constructors let you enforce invariants, set defaults, validate input, and hide internal complexity. As a struct evolves, callers using `NewServer(...)` are insulated from changes to its internal fields, while callers using raw struct literals would need to update every call site.

```go
func NewServer(host string, port int) (*Server, error) {
    if port <= 0 || port > 65535 {
        return nil, fmt.Errorf("invalid port: %d", port)
    }
    return &Server{Host: host, Port: port, Timeout: 30}, nil
}
```

> [!info] Returning a pointer (`*Server`) from a constructor is the common convention — it avoids an unnecessary copy and allows the caller to share the same instance.

---

## The Stringer Interface

`fmt.Stringer` is a single-method interface from the standard library:

```go
type Stringer interface {
    String() string
}
```

If a type implements `String() string`, `fmt.Println` and friends automatically use it to format the value instead of the default struct dump.

```go
type Point struct{ X, Y int }

// Without Stringer
p := Point{1, 2}
fmt.Println(p) // {1 2}

// With Stringer
func (p Point) String() string {
    return fmt.Sprintf("(%d, %d)", p.X, p.Y)
}

fmt.Println(p) // (1, 2) — uses our custom String() method
```

```go
type Status int

const (
    StatusPending Status = iota
    StatusActive
    StatusDone
)

func (s Status) String() string {
    switch s {
    case StatusPending:
        return "Pending"
    case StatusActive:
        return "Active"
    case StatusDone:
        return "Done"
    default:
        return "Unknown"
    }
}

fmt.Println(StatusActive) // "Active" — instead of just printing 1
```

> [!tip] Implementing `Stringer` is extremely common for enum-like types and any struct you'll frequently print or log — it makes debug output and logs human-readable instead of raw field dumps or magic numbers.

### Why the exact name `String` matters

`Stringer` isn't special because of language magic — `fmt`'s own source code does a type assertion against this exact interface:

```go
type Stringer interface {
    String() string
}
```

This checks for a method with the **exact name `String`** and the **exact signature `() string`**. If you rename the method to anything else — `Display()`, `Show()`, `Render()` — even with an identical signature, `fmt` will never find it. Method names are part of the interface contract in Go, not just the parameter/return types.

```go
type Money struct{ Cents int64 }

// Renamed from String() to Display() — breaks automatic detection
func (m Money) Display() string {
	return fmt.Sprintf("$%d.%02d", m.Cents/100, m.Cents%100)
}

m := Money{Cents: 500}
fmt.Println(m)           // {500} — fmt has no idea Display() exists
fmt.Println(m.Display()) // $5.00 — only works if called explicitly, every time
```

With `String()` instead of `Display()`, `fmt.Println(m)` would automatically print `$5.00` — no manual call needed anywhere in the codebase.

> [!info] `fmt` also checks for `Stringer` on **nested struct fields**, not just the top-level value. So implementing `String()` once on `Money` automatically makes it format correctly everywhere it's embedded — inside an `Order` struct, a slice, a log line — without extra work at each call site.

```go
type Order struct {
	ID    string
	Total Money
}

order := Order{ID: "ORD-1", Total: Money{Cents: 500}}
fmt.Println(order) // {ORD-1 $5.00} — Stringer found recursively on the nested field
```

This is the same pattern used by other standard library interfaces — `error` (`Error() string`), `io.Reader` (`Read(...)`), `json.Marshaler` (`MarshalJSON() ([]byte, error)`). None are language keywords; each is a plain interface that specific standard library functions check for by exact method name and signature at runtime.

---

## Embedding Interfaces in Structs

You can embed an **interface** inside a struct, not just another struct. This is a common pattern for partial implementations, mocking, and decorators.

```go
type Reader interface {
    Read(p []byte) (n int, err error)
}

type LoggingReader struct {
    Reader // embedded interface
}

func (lr LoggingReader) Read(p []byte) (int, error) {
    n, err := lr.Reader.Read(p) // delegate to the wrapped Reader
    fmt.Printf("read %d bytes\n", n)
    return n, err
}
```

`LoggingReader` wraps any `Reader` and adds logging, while still satisfying the `Reader` interface itself (so it can be passed anywhere a `Reader` is expected).

### Why this is useful

> [!info] Embedding an interface lets a struct "promise" to implement that interface (satisfying the type system) while you only override the specific methods you care about — the rest come from whatever concrete value you assign to the embedded interface field at runtime.

### What "satisfy" and "promise" actually mean here

These aren't special Go keywords — they're plain-language ways to describe what's happening with the type system.

**"Satisfy an interface"** simply means: a type has all the methods the interface requires.

```go
type Reader interface {
    Read(p []byte) (n int, err error)
}

type File struct{}
func (f File) Read(p []byte) (int, error) { return 0, nil }

var r Reader = File{} // ✅ File has a matching Read() method, so it satisfies Reader
```

**Now with embedding:**

```go
type LoggingReader struct {
    Reader // embedded interface — no Read() written by LoggingReader itself
}

var r Reader = LoggingReader{} // ✅ this still compiles!
```

`LoggingReader` never wrote its own `Read()`. But because it embeds `Reader`, Go automatically promotes a `Read()` method onto it — borrowed from whatever concrete value sits inside the embedded field. The compiler is satisfied purely because of the embedding, not because real, working code was written.

This is the **"promise"**: the struct type-checks as a `Reader` on paper, but that promise is only backed by whatever real value is placed in the embedded field at runtime.

```go
var lr LoggingReader // embedded Reader field is nil — nothing to delegate to
lr.Read(buf)          // 💥 panic — the promise was empty, nothing behind it
```

The compiler was happy (`LoggingReader` satisfies `Reader`), but at runtime there's no actual implementation behind the promoted method, because the embedded field was never assigned a real value.

> [!tip] Analogy: a résumé listing "Skills: Driving" because you own a car qualifies you on paper (satisfies the requirement) — but if you've never actually driven and there's no gas in the tank, asking you to drive (calling the method) fails immediately. Satisfying an interface via embedding is the same — it passes the compiler's check, but only works at runtime if something real is actually behind it.

```go
// Partial mock for testing — only override what you need
type MockReader struct {
    Reader // nil by default — only safe if you only call overridden methods
}

func (m MockReader) Read(p []byte) (int, error) {
    return 0, io.EOF // pretend the stream is always empty
}
```

> [!warning] If the embedded interface field is left `nil` and you call a method that ISN'T overridden, you'll get a nil pointer/interface panic. Only use this pattern when you're certain which methods are actually called.

---

## Struct Design Patterns

### Functional options (recap)

A pattern for constructors with many optional parameters, avoiding long parameter lists or telescoping constructors.

```go
type Server struct {
    Host    string
    Port    int
    Timeout int
}

type Option func(*Server)

func WithPort(port int) Option {
    return func(s *Server) { s.Port = port }
}

func WithTimeout(t int) Option {
    return func(s *Server) { s.Timeout = t }
}

func NewServer(host string, opts ...Option) *Server {
    s := &Server{Host: host, Port: 8080, Timeout: 30} // defaults
    for _, opt := range opts {
        opt(s)
    }
    return s
}

s := NewServer("localhost", WithPort(9000), WithTimeout(60))
fmt.Println(s.Port, s.Timeout) // 9000 60
```

### Builder pattern

A pattern where you chain method calls to incrementally construct a complex object, each method returning the builder itself for chaining.

```go
type RequestBuilder struct {
    method  string
    url     string
    headers map[string]string
}

func NewRequestBuilder() *RequestBuilder {
    return &RequestBuilder{headers: make(map[string]string)}
}

func (b *RequestBuilder) Method(m string) *RequestBuilder {
    b.method = m
    return b // return self for chaining
}

func (b *RequestBuilder) URL(u string) *RequestBuilder {
    b.url = u
    return b
}

func (b *RequestBuilder) Header(key, value string) *RequestBuilder {
    b.headers[key] = value
    return b
}

req := NewRequestBuilder().
    Method("GET").
    URL("https://api.example.com").
    Header("Authorization", "Bearer token").
    Header("Accept", "application/json")

fmt.Println(req.method, req.url, req.headers)
```

> [!tip] Builder pattern shines when construction involves many steps or conditional logic. Functional options shine when you have a fixed constructor but want optional, named parameters. Both achieve readable, flexible object construction — choose based on whether your config is naturally a sequence of steps (builder) or a flat set of optional settings (functional options).

---

## Quick Reference Cheatsheet

```go
// === DEFINING ===
type Person struct {
    Name string
    Age  int
}

// === FIELD ACCESS ===
p := Person{Name: "Alice", Age: 30}
p.Age = 31

// === LITERALS ===
p := Person{Name: "Alice", Age: 30}  // named — safe
p := Person{"Alice", 30}             // positional — fragile

// === ANONYMOUS STRUCT ===
point := struct{ X, Y int }{X: 1, Y: 2}

// === ZERO VALUE ===
var p Person // {  0 } — all fields zero-valued, ready to use

// === EMBEDDING ===
type Dog struct {
    Animal       // embedded — no field name
    Breed string
}
d.Name  // promoted field, accessed directly
d.Speak() // promoted method

// === STRUCT TAGS ===
type User struct {
    Name string `json:"name"`
    Pass string `json:"-"`              // exclude
    Age  int    `json:"age,omitempty"`  // omit if zero
}

// === COMPARISON ===
p1 == p2                      // works if all fields comparable
reflect.DeepEqual(p1, p2)     // works even with slices/maps

// === COPYING ===
p2 := p1   // full copy of value fields
           // BUT slices/maps inside are shared references!

// === RECEIVERS ===
func (c Counter) Value() int  { return c.count }  // value — copy
func (c *Counter) Inc()       { c.count++ }        // pointer — mutates

// === METHOD SETS ===
// T  → only value-receiver methods
// *T → value-receiver AND pointer-receiver methods

// === METHOD VALUE vs EXPRESSION ===
inc := c.Increment           // bound to c — call as inc()
incExpr := (*Counter).Increment  // unbound — call as incExpr(c)

// === CONSTRUCTOR ===
func NewServer(host string, port int) *Server {
    return &Server{Host: host, Port: port, Timeout: 30}
}

// === STRINGER ===
func (p Point) String() string {
    return fmt.Sprintf("(%d, %d)", p.X, p.Y)
}
// fmt.Println(p) now uses String() automatically

// === EMBEDDED INTERFACE ===
type LoggingReader struct {
    io.Reader // embed interface, override selectively
}

// === FUNCTIONAL OPTIONS ===
NewServer("host", WithPort(9000), WithTimeout(60))

// === BUILDER ===
NewRequestBuilder().Method("GET").URL(u).Header(k, v)
```

---

### Key Rules to Remember

|Rule|Detail|
|---|---|
|Named literals|always prefer over positional for clarity and safety|
|Zero value structs|ready to use, but nested maps/slices are nil|
|Embedding|composition, not inheritance — fields/methods promoted|
|Struct tags|inert metadata — only matter if a library reads them|
|`==` comparison|only works if all fields are comparable|
|Copying|shallow — slices/maps inside are shared, not deep-copied|
|Receiver consistency|pick value or pointer receivers, don't mix|
|Method set rule|`*T` gets both value and pointer methods, `T` gets only value methods|
|Constructors|`New*` pattern — enforce defaults, validation, encapsulation|
|Stringer|implement `String() string` for readable `fmt` output|

---

Previous: [[08 - Pointers]] · Next: [[10 - Interfaces]]