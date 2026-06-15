# Go — Variables and Types

> **Series:** Go Language Fundamentals **Tags:** #go #golang #variables #types #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. Variable Declaration]]
- [[#2. Short Variable Declaration]]
- [[#3. Zero Values]]
- [[#4. Multiple Assignment]]
- [[#5. Constants]]
- [[#6. Basic Types]]
    - [[#Boolean]]
    - [[#Integer Types]]
    - [[#Floating-Point Types]]
    - [[#Complex Types]]
    - [[#String]]
    - [[#Byte and Rune]]
- [[#7. Type Conversions]]
- [[#8. Type Inference]]
- [[#9. Composite Types Overview]]
    - [[#Arrays]]
    - [[#Slices]]
    - [[#Maps]]
    - [[#Structs]]
- [[#10. Pointers]]
- [[#11. The blank identifier]]
- [[#12. Scope and Shadowing]]
- [[#13. Quick Reference Cheatsheet]]

---

## 1. Variable Declaration

Go uses the `var` keyword for explicit variable declarations. The type comes **after** the variable name.

```go
package main

import "fmt"

func main() {
    var name string       // declared, zero value ""
    var age  int          // declared, zero value 0
    var pi   float64 = 3.14159

    name = "Alice"
    age  = 30

    fmt.Println(name, age, pi)
    // Output: Alice 30 3.14159
}
```

### Block-style declaration

Group related `var` declarations together for readability:

```go
var (
    firstName string  = "Bob"
    lastName  string  = "Smith"
    score     int     = 100
    active    bool    = true
)
```

---

## 2. Short Variable Declaration

The `:=` operator declares **and** initialises a variable, inferring the type automatically. Only usable **inside** functions.

```go
func main() {
    city    := "Tashkent"   // string
    temp    := 36.5         // float64
    raining := false        // bool

    fmt.Printf("%s: %.1f°C, rain: %v\n", city, temp, raining)
    // Output: Tashkent: 36.5°C, rain: false
}
```

> [!warning] `:=` vs `=`
> 
> - `:=` declares a **new** variable and assigns it (inside functions only)
> - `=` assigns to an **already declared** variable At least **one** variable on the left of `:=` must be new.

---

## 3. Zero Values

Every variable in Go is automatically initialised to its **zero value** — no garbage memory.

| Type                                   | Zero Value                          |
| -------------------------------------- | ----------------------------------- |
| `int`, `int8` … `int64`                | `0`                                 |
| `uint`, `uint8` … `uint64`             | `0`                                 |
| `float32`, `float64`                   | `0.0`                               |
| `complex64`, `complex128`              | `(0+0i)`                            |
| `bool`                                 | `false`                             |
| `string`                               | `""`                                |
| pointer, slice, map, channel, function | `nil`                               |
| struct                                 | all fields set to their zero values |

```go
var count   int
var ratio   float64
var message string
var flag    bool

fmt.Printf("int:%d  float:%f  string:%q  bool:%t\n",
    count, ratio, message, flag)
// Output: int:0  float:0.000000  string:""  bool:false
```

---

## 4. Multiple Assignment

Go allows assigning multiple variables in a single line — very useful for swapping values.

```go
// Declare multiple variables at once
x, y, z := 10, 20, 30
fmt.Println(x, y, z) // 10 20 30

// Swap without a temp variable
x, y = y, x
fmt.Println(x, y) // 20 10

// Receive multiple return values
func divide(a, b float64) (float64, error) {
    if b == 0 {
        return 0, fmt.Errorf("division by zero")
    }
    return a / b, nil
}

result, err := divide(10, 3)
if err != nil {
    fmt.Println("Error:", err)
} else {
    fmt.Printf("%.4f\n", result) // 3.3333
}
```

---

## 5. Constants

Constants are declared with `const` and must be assigned at compile time. They cannot be changed.

```go
const Pi      = 3.14159265358979
const AppName = "MyApp"
const MaxSize = 1024

// Typed constant
const timeout time.Duration = 30 * time.Second

// Block of constants
const (
    StatusOK       = 200
    StatusNotFound = 404
    StatusError    = 500
)
```

### iota — Auto-incrementing constants

`iota` resets to `0` at the start of each `const` block and increments by 1 for each spec.

```go
type Direction int

const (
    North Direction = iota // 0
    East                   // 1
    South                  // 2
    West                   // 3
)

// iota with expressions
const (
    _  = iota             // skip 0
    KB = 1 << (10 * iota) // 1 << 10 = 1024
    MB                    // 1 << 20 = 1048576
    GB                    // 1 << 30 = 1073741824
)

fmt.Println(KB, MB, GB) // 1024 1048576 1073741824
```

---

## 6. Basic Types

### Boolean

```go
var isReady bool = true
isLoggedIn := false

fmt.Println(isReady && !isLoggedIn) // true
fmt.Println(isReady || isLoggedIn)  // true
```

---

### Integer Types

|Type|Size|Range|
|---|---|---|
|`int8`|8-bit|−128 to 127|
|`int16`|16-bit|−32 768 to 32 767|
|`int32`|32-bit|−2 147 483 648 to 2 147 483 647|
|`int64`|64-bit|−9.2 × 10¹⁸ to 9.2 × 10¹⁸|
|`int`|platform (32 or 64-bit)|same as above|
|`uint8`|8-bit|0 to 255|
|`uint16`|16-bit|0 to 65 535|
|`uint32`|32-bit|0 to 4 294 967 295|
|`uint64`|64-bit|0 to 1.8 × 10¹⁹|
|`uint`|platform|same as above|
|`uintptr`|pointer-sized|stores a pointer value|

```go
var a int    = -42
var b uint   = 42
var c int8   = 127     // max int8
var d uint64 = 18446744073709551615

// Arithmetic
sum := a + int(b)     // type conversion required
fmt.Println(sum)      // 0

// Bitwise operations
x := 0b1010  // binary literal = 10
y := 0b0110  // binary literal = 6

fmt.Println(x & y)  // AND  = 2  (0010)
fmt.Println(x | y)  // OR   = 14 (1110)
fmt.Println(x ^ y)  // XOR  = 12 (1100)
fmt.Println(x << 1) // Left shift = 20
```

---

### Floating-Point Types

|Type|Size|Precision|
|---|---|---|
|`float32`|32-bit|~7 decimal digits|
|`float64`|64-bit|~15 decimal digits|

```go
var f32 float32 = 3.14
var f64 float64 = 3.141592653589793

fmt.Printf("float32: %.10f\n", f32)
// float32: 3.1400001049  ← precision loss!

fmt.Printf("float64: %.15f\n", f64)
// float64: 3.141592653589793

// Scientific notation
avogadro := 6.022e23
planck    := 6.626e-34
fmt.Println(avogadro, planck)
```

> [!tip] Prefer `float64` Always use `float64` by default. Use `float32` only when memory is a hard constraint (e.g. large arrays, GPU-bound work).

---

### Complex Types

```go
c1 := complex(3, 4)       // 3+4i
c2 := 1 + 2i              // shorthand

fmt.Println(c1 + c2)      // (4+6i)
fmt.Println(real(c1))     // 3
fmt.Println(imag(c1))     // 4

// Modulus
import "math/cmplx"
fmt.Println(cmplx.Abs(c1)) // 5 (√(3²+4²))
```

---

### String

Strings in Go are **immutable sequences of bytes** (UTF-8 encoded).

```go
s := "Hello, 世界"

fmt.Println(len(s))         // 13 (bytes, not characters!)
fmt.Println(s[0])           // 72 (byte value of 'H')
fmt.Println(string(s[0]))   // "H"

// Iterate over runes (Unicode code points)
for i, r := range s {
    fmt.Printf("index %d: %c (U+%04X)\n", i, r, r)
}

// Raw string literal (backticks — no escape processing)
path := `C:\Users\Alice\Documents`
json := `{
    "name": "Alice",
    "age": 30
}`

// String concatenation
greeting := "Hello" + ", " + "World!"

// Multi-line with Sprintf
msg := fmt.Sprintf("Name: %s, Age: %d", "Bob", 25)
```

#### Common string operations

```go
import "strings"

s := "  Go is awesome!  "

fmt.Println(strings.TrimSpace(s))          // "Go is awesome!"
fmt.Println(strings.ToUpper(s))            // "  GO IS AWESOME!  "
fmt.Println(strings.Contains(s, "awesome")) // true
fmt.Println(strings.Replace(s, "awesome", "great", 1))
fmt.Println(strings.Split("a,b,c", ","))   // [a b c]
fmt.Println(strings.HasPrefix(s, "  Go"))  // true
```

---

### Byte and Rune
### `byte` (`uint8`) — raw binary data

A byte is just a number 0–255. Use it when you care about **the actual bytes**, not the human-readable characters.

**When to use `byte` / `[]byte`:**

- Reading/writing files, network data, binary protocols
- Passing data to I/O functions (`os.File`, `http`, `bufio`) — they all speak `[]byte`
- Performance-sensitive string manipulation (avoids allocations)
- Working with pure ASCII text

go

```go
// I/O — the standard library works in []byte
data, _ := os.ReadFile("file.txt")  // returns []byte
os.WriteFile("out.txt", data, 0644)

// Mutating a string (strings are immutable, []byte is not)
b := []byte("hello")
b[0] = 'H'
fmt.Println(string(b))  // "Hello"

// ASCII manipulation is safe with bytes
s := "hello"
for i, b := range []byte(s) {
    fmt.Printf("byte %d: %c\n", i, b)
}
```

### `rune` (`int32`) — Unicode characters

A rune represents a single **Unicode code point** — what a human would call "one character". Use it when you care about **readable text**, especially any language beyond basic ASCII.

**When to use `rune` / `[]rune`:**

- Counting visible characters (not bytes)
- Indexing or slicing by character position
- Working with non-ASCII text (Cyrillic, CJK, Arabic, emoji…)
- Text processing, parsers, formatters

go

```go
s := "café"

// WRONG — slices by byte, can cut 'é' in half
fmt.Println(s[:4])  // "caf\xc3" — corrupted!

// RIGHT — convert to runes first
r := []rune(s)
fmt.Println(string(r[:4]))   // "café" — correct
fmt.Println(len(r))          // 4 — actual character count
fmt.Println(len(s))          // 5 — byte count

// Iterating: range on a string gives runes automatically
for i, ch := range s {
    fmt.Printf("index %d: %c\n", i, ch)
}
// index 0: c
// index 1: a
// index 2: f
// index 3: é   ← index jumps from 3 to 5 in bytes, but you get the whole rune
```

---


```go
// byte is an alias for uint8 — represents a single ASCII character
var b byte = 'A'
fmt.Println(b)        // 65
fmt.Println(string(b)) // A

// rune is an alias for int32 — represents a Unicode code point
var r rune = '世'
fmt.Printf("%c %d\n", r, r) // 世 19990

// Converting between string and []byte / []rune
s     := "Hello"
bytes := []byte(s)   // [72 101 108 108 111]
runes := []rune(s)   // [72 101 108 108 111]

bytes[0] = 'h'
fmt.Println(string(bytes)) // hello
```

---

## 7. Type Conversions

Go is **strictly typed** — there are no implicit conversions. You must convert explicitly.

```go
var i int     = 42
var f float64 = float64(i)   // int → float64
var u uint    = uint(f)      // float64 → uint

fmt.Println(i, f, u) // 42 42 42

// string ↔ int (use strconv, not casting)
import "strconv"

n := 123
s := strconv.Itoa(n)        // int to string: "123"
m, err := strconv.Atoi("456") // string to int: 456, nil

// string ↔ float
fs := strconv.FormatFloat(3.14, 'f', 2, 64) // "3.14"
fv, _ := strconv.ParseFloat("2.718", 64)     // 2.718

// Unsafe: direct cast string(int) gives a Unicode character, not a digit!
fmt.Println(string(65))    // "A"  ← NOT "65"!
fmt.Println(strconv.Itoa(65)) // "65" ← correct
```

---

## 8. Type Inference

Go infers types from the right-hand side of `:=` and `var x =`.

```go
a := 42          // int
b := 3.14        // float64
c := "hello"     // string
d := true        // bool
e := 'x'         // int32 (rune)

// Untyped constants take their type from context
const big = 1000000000
var x int32 = big   // ok — fits in int32
var y int8  = big   // compile error — overflow

// Check type at runtime
import "fmt"
fmt.Printf("%T\n", a) // int
fmt.Printf("%T\n", b) // float64
fmt.Printf("%T\n", c) // string
```

---

## 9. Composite Types Overview

### Arrays

Fixed-length sequence of elements of the same type. Size is part of the type.

```go
var arr [5]int                     // [0 0 0 0 0]
primes := [5]int{2, 3, 5, 7, 11}  // literal
auto   := [...]int{10, 20, 30}     // compiler counts: len=3

fmt.Println(primes[0])    // 2
fmt.Println(len(primes))  // 5

// Arrays are VALUE types — copied on assignment
copy := primes
copy[0] = 99
fmt.Println(primes[0]) // still 2
```

---

### Slices

Dynamic, flexible view into an underlying array. The most-used sequence type in Go.

```go
// From a literal
fruits := []string{"apple", "banana", "cherry"}

// Using make(type, length, capacity)
nums := make([]int, 3, 5) // [0 0 0], len=3, cap=5

// Append
fruits = append(fruits, "date")

// Slice of a slice
sub := fruits[1:3] // ["banana", "cherry"]

// Slices are REFERENCE types — they share the underlying array
a := []int{1, 2, 3, 4, 5}
b := a[1:4]  // [2 3 4]
b[0] = 99
fmt.Println(a) // [1 99 3 4 5] ← a is affected!

fmt.Printf("len=%d cap=%d\n", len(b), cap(b)) // len=3 cap=4
```

---

### Maps

Unordered key-value store (hash table).

```go
// Declare and initialise
ages := map[string]int{
    "Alice": 30,
    "Bob":   25,
}

// Using make
scores := make(map[string]float64)
scores["Alice"] = 98.5
scores["Bob"]   = 87.0

// Access
fmt.Println(ages["Alice"]) // 30

// Check existence — always use the two-value form
val, ok := ages["Charlie"]
if !ok {
    fmt.Println("Charlie not found") // prints this
}

// Delete
delete(ages, "Bob")

// Iterate (order not guaranteed)
for name, age := range ages {
    fmt.Printf("%s is %d\n", name, age)
}
```

---

### Structs

A struct groups fields of different types under one name.

```go
type Person struct {
    Name    string
    Age     int
    Email   string
}

// Create a value
alice := Person{
    Name:  "Alice",
    Age:   30,
    Email: "alice@example.com",
}

// Access fields
fmt.Println(alice.Name) // Alice
alice.Age = 31

// Anonymous struct (one-off)
point := struct {
    X, Y int
}{X: 10, Y: 20}

// Structs are VALUE types
bob := alice
bob.Name = "Bob"
fmt.Println(alice.Name) // still "Alice"
```

---

## [[10. Pointers]]


A pointer holds the **memory address** of a value. Go has no pointer arithmetic.

```go
x := 42
p := &x         // p is *int — holds address of x

fmt.Println(p)  // 0xc0000b4008  (some address)
fmt.Println(*p) // 42           (dereference)

*p = 100        // modify x through pointer
fmt.Println(x)  // 100

// new() allocates zeroed memory and returns a pointer
n := new(int)   // *int pointing to 0
*n = 7
fmt.Println(*n) // 7

// Pointer to struct
type Point struct{ X, Y int }
pt := &Point{X: 1, Y: 2}
pt.X = 10       // shorthand for (*pt).X = 10
fmt.Println(*pt) // {10 2}
```

> [!info] When to use pointers
> 
> - To **mutate** a value inside a function
> - To avoid **copying** large structs
> - To represent **optional** values (`nil` pointer = absent)

---

## 11. The Blank Identifier

`_` discards a value you don't need — required when a function returns multiple values and you only need some.

```go
// Ignore the index in a range loop
for _, v := range []int{10, 20, 30} {
    fmt.Println(v)
}

// Ignore an error (use with caution!)
val, _ := strconv.Atoi("42")
fmt.Println(val) // 42

// Ignore second return value
result, _ := divide(10.0, 2.0)
```

---

## 12. Scope and Shadowing

Go uses **lexical (block) scoping**. A variable declared inside `{}` is only visible there.

```go
x := "outer"

{
    x := "inner"         // NEW variable — shadows outer x
    fmt.Println(x)       // inner
}

fmt.Println(x)           // outer — unchanged

// Common pitfall in if blocks
if y := compute(); y > 0 {
    fmt.Println("positive:", y) // y visible here
}
// fmt.Println(y) // compile error — y out of scope
```

> [!warning] Shadowing pitfall
> 
> ```go
> err := doFirst()
> if condition {
>     result, err := doSecond() // new err — shadows outer err!
>     _ = result
> }
> // outer err is unchanged — this is a common bug
> ```
> 
> Use `=` instead of `:=` when you want to reuse an existing variable.

---

## 13. Quick Reference Cheatsheet

```go
// ── Declaration ─────────────────────────────────────────
var x int                    // zero value
var x int = 10               // explicit type + value
var x = 10                   // inferred type
x := 10                      // short (inside func only)
var (x, y int; s string)     // block

// ── Constants ───────────────────────────────────────────
const Pi = 3.14
const ( A = iota; B; C )     // 0, 1, 2

// ── Basic Types ─────────────────────────────────────────
bool          true / false
int  int8  int16  int32  int64
uint uint8 uint16 uint32 uint64  uintptr
float32  float64
complex64  complex128
string    byte (=uint8)   rune (=int32)

// ── Composite Types ─────────────────────────────────────
[5]int{1,2,3,4,5}             // array
[]int{1,2,3}                  // slice literal
make([]int, len, cap)         // slice via make
map[string]int{"a":1}         // map literal
make(map[string]int)          // map via make
struct{ X, Y int }            // anonymous struct
type Point struct{ X, Y int } // named struct

// ── Pointers ────────────────────────────────────────────
p := &x     // address-of
*p          // dereference
new(T)      // *T pointing to zero value

// ── Conversions ─────────────────────────────────────────
float64(i)           // int → float64
int(f)               // float64 → int (truncates)
string(r)            // rune → string (Unicode char)
[]byte(s)            // string → byte slice
strconv.Itoa(n)      // int → decimal string
strconv.Atoi(s)      // decimal string → int, error
```

---

_Next topic: → [[Operators]]_