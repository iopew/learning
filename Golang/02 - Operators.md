# Go — Operators

> **Series:** Go Language Fundamentals **Tags:** #go #golang #operators #expressions #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. Arithmetic Operators]]
- [[#2. Assignment Operators]]
- [[#3. Comparison Operators]]
- [[#4. Logical Operators]]
- [[#5. Bitwise Operators]]
- [[#6. Address & Pointer Operators]]
- [[#7. Operator Precedence]]
- [[#8. No Ternary Operator]]
- [[#9. Common Gotchas]]
- [[#10. Quick Reference Cheatsheet]]

---

## 1. Arithmetic Operators

Used to perform mathematical calculations. All standard operators work on numeric types.

```go
a := 10
b := 3

fmt.Println(a + b)   // 13  — addition
fmt.Println(a - b)   // 7   — subtraction
fmt.Println(a * b)   // 30  — multiplication
fmt.Println(a / b)   // 3   — division (integer — truncates!)
fmt.Println(a % b)   // 1   — modulus (remainder)
```

### Integer division truncates — it does NOT round

```go
fmt.Println(7 / 2)    // 3, not 3.5
fmt.Println(-7 / 2)   // -3, not -4 (truncates toward zero)
```

To get a decimal result, at least one operand must be a float:

```go
fmt.Println(7.0 / 2)      // 3.5
fmt.Println(float64(7) / 2) // 3.5
```

### Modulus with negative numbers

In Go, the result of `%` takes the **sign of the dividend** (the left side):

```go
fmt.Println(7 % 3)    //  1
fmt.Println(-7 % 3)   // -1  ← negative, not 2
fmt.Println(7 % -3)   //  1  ← positive
```

### Increment and Decrement

Go has `++` and `--`, but they are **statements**, not expressions. You cannot use them inline or assign from them.

```go
x := 5
x++           // x is now 6
x--           // x is now 5

// INVALID in Go — unlike C or JavaScript:
// y := x++   // compile error
// if x++ > 5 // compile error

// Also: only postfix — no prefix ++x or --x
```

### Floating-point arithmetic

```go
a := 0.1
b := 0.2
fmt.Println(a + b)          // 0.30000000000000004 — floating-point imprecision!
fmt.Println(a + b == 0.3)   // false

// Compare with a tolerance (epsilon) instead
epsilon := 1e-9
fmt.Println(math.Abs((a+b)-0.3) < epsilon)  // true
```

> [!warning] Never compare floats with `==` Floating-point arithmetic is inherently imprecise. Always compare using a small tolerance value (`epsilon`). This is true in every programming language, not just Go.

---

## 2. Assignment Operators

### Basic assignment

```go
x := 10      // declare and assign (short declaration)
x = 20       // reassign
```

### Compound assignment operators

These combine an arithmetic or bitwise operation with assignment. They are shorthand — `x += 5` means `x = x + 5`.

```go
x := 10

x += 5    // x = x + 5  → 15
x -= 3    // x = x - 3  → 12
x *= 2    // x = x * 2  → 24
x /= 4    // x = x / 4  → 6
x %= 4    // x = x % 4  → 2

//\
x &= 3    // x = x & 3
x |= 8    // x = x | 8
x ^= 1    // x = x ^ 1
x <<= 2   // x = x << 2
x >>= 1   // x = x >> 1
```

### Multiple assignment

```go
a, b := 1, 2

// Swap without a temp variable — evaluated right side first
a, b = b, a
fmt.Println(a, b)  // 2 1
```

> [!info] Right side evaluates first In `a, b = b, a`, Go evaluates **all** right-hand side values before doing any assignment. That's why the swap works without a temp variable.

---

## 3. Comparison Operators

Comparison operators return a `bool` (`true` or `false`). Both sides must be the **same type**.

```go
a, b := 5, 10

fmt.Println(a == b)   // false — equal
fmt.Println(a != b)   // true  — not equal
fmt.Println(a < b)    // true  — less than
fmt.Println(a > b)    // false — greater than
fmt.Println(a <= b)   // true  — less than or equal
fmt.Println(a >= b)   // false — greater than or equal
```

### Comparing strings

Strings are compared **lexicographically** (alphabetical order by Unicode value):

```go
fmt.Println("apple" == "apple")   // true
fmt.Println("apple" < "banana")   // true  — 'a' < 'b'
fmt.Println("banana" < "Apple")   // false — lowercase 'b' (98) > uppercase 'A' (65)
fmt.Println("abc" < "abd")        // true  — first two chars equal, 'c' < 'd'
```

### Comparing structs

Structs are comparable if **all their fields** are comparable types:

```go
type Point struct{ X, Y int }

p1 := Point{1, 2}
p2 := Point{1, 2}
p3 := Point{3, 4}

fmt.Println(p1 == p2)   // true  — all fields match
fmt.Println(p1 == p3)   // false
```

> [!warning] Slices, maps, and functions cannot be compared with `==`
> 
> ```go
> a := []int{1, 2, 3}
> b := []int{1, 2, 3}
> fmt.Println(a == b)  // compile error!
> ```
> 
> Use `reflect.DeepEqual(a, b)` or compare element by element instead.

---

## 4. Logical Operators

Used to combine boolean expressions.

```go
t, f := true, false

fmt.Println(t && f)   // false — AND: both must be true
fmt.Println(t || f)   // true  — OR:  at least one must be true
fmt.Println(!t)       // false — NOT: inverts the value
```

### Short-circuit evaluation

Go evaluates logical expressions **lazily** — it stops as soon as the result is determined:

```go
// && stops at the first false
// If the left side is false, the right side is NEVER evaluated
false && someExpensiveCall()   // someExpensiveCall() never runs

// || stops at the first true
// If the left side is true, the right side is NEVER evaluated
true || someExpensiveCall()    // someExpensiveCall() never runs
```

This is very useful for nil checks:

```go
// Safe — if user is nil, user.Name is never evaluated
if user != nil && user.Name == "Alice" {
    fmt.Println("Hello Alice")
}

// UNSAFE — if user is nil, this panics
if user.Name == "Alice" && user != nil {
    fmt.Println("Hello Alice")
}
```

> [!tip] Order matters with `&&` Always put the **cheaper / safety check first**. Put nil checks and bounds checks before the actual logic they protect.

### Real-world example

```go
age := 25
hasLicense := true
hasCar := false

canDrive := age >= 18 && hasLicense
fmt.Println(canDrive)           // true

canDriveOwnCar := canDrive && hasCar
fmt.Println(canDriveOwnCar)     // false

needsRide := !hasCar || !hasLicense
fmt.Println(needsRide)          // true
```

---

## 5. Bitwise Operators

Bitwise operators work directly on the **binary representation** of integers. Essential for low-level work, flags, permissions, and performance-critical code.

```go
a := 0b1010   // binary for 10
b := 0b0110   // binary for 6
```

|Operator|Name|Example|Result|Binary|
|---|---|---|---|---|
|`&`|AND|`a & b`|`2`|`0010`|
|`\|`|OR|`a \| b`|`14`|`1110`|
|`^`|XOR|`a ^ b`|`12`|`1100`|
|`^`|NOT (unary)|`^a`|`-11`|inverts all bits|
|`&^`|AND NOT (bit clear)|`a &^ b`|`8`|`1000`|
|`<<`|Left shift|`a << 1`|`20`|`10100`|
|`>>`|Right shift|`a >> 1`|`5`|`0101`|

```go
fmt.Println(a & b)    // 2  — only bits set in BOTH
fmt.Println(a | b)    // 14 — bits set in EITHER
fmt.Println(a ^ b)    // 12 — bits set in ONE but not BOTH
fmt.Println(a &^ b)   // 8  — bits set in a but NOT in b
fmt.Println(a << 1)   // 20 — shift left = multiply by 2
fmt.Println(a >> 1)   // 5  — shift right = divide by 2
```

### Practical use: permission flags

Bitwise operators are perfect for storing multiple boolean flags in a single integer:

```go
const (
    PermRead    = 1 << iota  // 001 = 1
    PermWrite                // 010 = 2
    PermExecute              // 100 = 4
)

// Grant read and write
perms := PermRead | PermWrite   // 011 = 3

// Check if a permission is set
hasRead    := perms & PermRead    != 0   // true
hasExecute := perms & PermExecute != 0   // false

// Add execute permission
perms |= PermExecute   // perms is now 111 = 7

// Remove write permission
perms &^= PermWrite    // perms is now 101 = 5

fmt.Println(hasRead, hasExecute)  // true false
```

### Practical use: powers of 2 with iota

```go
const (
    _  = iota              // skip 0
    KB = 1 << (10 * iota) // 1 << 10 = 1024
    MB                    // 1 << 20 = 1_048_576
    GB                    // 1 << 30 = 1_073_741_824
)
```

---

## 6. Address & Pointer Operators

Two operators deal with memory addresses:

```go
x := 42

p := &x    // & — "address of" — p is *int, holds x's memory address
fmt.Println(p)    // 0xc0000b4008 (some address)

fmt.Println(*p)   // * — "dereference" — 42 (the value at that address)

*p = 100          // modify x through the pointer
fmt.Println(x)    // 100
```

### As a type prefix

`*` is also used in type declarations to mean "pointer to":

```go
var p *int         // p is a pointer to int (nil by default)
var q *Person      // q is a pointer to Person (nil by default)

n := 7
p = &n
fmt.Println(*p)    // 7
```

> [!info] Recap
> 
> - `&x` — gives you the address of `x`
> - `*p` — gives you the value stored at the address `p` holds
> - `*T` as a type — means "pointer to T"

---

## 7. Operator Precedence

When an expression has multiple operators, Go evaluates higher-precedence operators first — just like PEMDAS/BODMAS in maths.

|Precedence|Operators|
|---|---|
|5 (highest)|`*` `/` `%` `<<` `>>` `&` `&^`|
|4|`+` `-` `\|` `^`|
|3|`==` `!=` `<` `<=` `>` `>=`|
|2|`&&`|
|1 (lowest)|`\|`|

```go
// Without parentheses — follows precedence
fmt.Println(2 + 3*4)        // 14, not 20 (* before +)
fmt.Println(10 - 2 + 3)     // 11 (left to right, same precedence)
fmt.Println(true || false && false)  // true (&& before ||)

// With parentheses — explicit, always clearer
fmt.Println((2 + 3) * 4)    // 20
fmt.Println(true || (false && false))  // true (same result, but obvious)
```

> [!tip] When in doubt, use parentheses Don't rely on memorising precedence for complex expressions. Parentheses make intent explicit and prevent bugs. `(a > 0) && (b < 10)` is clearer than `a > 0 && b < 10`, even though both work.

---

## 8. No Ternary Operator

Go deliberately does **not** have a ternary operator (`? :`). You must use a full `if/else`:

```go
// This does NOT exist in Go:
// result := condition ? valueIfTrue : valueIfFalse

// Do this instead:
x := 10
var result string
if x > 5 {
    result = "big"
} else {
    result = "small"
}
fmt.Println(result)  // "big"
```

For simple cases, a helper function cleans this up:

```go
func ternary[T any](condition bool, ifTrue, ifFalse T) T {
    if condition {
        return ifTrue
    }
    return ifFalse
}

result := ternary(x > 5, "big", "small")
fmt.Println(result)  // "big"
```

> [!info] Why no ternary? Go's designers felt ternary expressions — especially nested ones — hurt readability. The explicit `if/else` is more verbose but always unambiguous.

---

## 9. Common Gotchas

### Integer overflow — silent wrapping

Go does not panic on integer overflow — it silently wraps around:

```go
var x int8 = 127   // max value for int8
x++
fmt.Println(x)     // -128 ← wrapped around!

var u uint8 = 0
u--
fmt.Println(u)     // 255 ← wrapped around the other way!
```

Use `math` package constants to check limits:

```go
import "math"
fmt.Println(math.MaxInt8)   // 127
fmt.Println(math.MinInt8)   // -128
fmt.Println(math.MaxUint8)  // 255
```

### Division by zero

Integer division by zero is a **runtime panic**:

```go
a := 10
b := 0
fmt.Println(a / b)   // panic: runtime error: integer divide by zero
```

Float division by zero returns `Inf` (infinity), not a panic:

```go
fmt.Println(10.0 / 0.0)   // +Inf
fmt.Println(-10.0 / 0.0)  // -Inf
fmt.Println(0.0 / 0.0)    // NaN (Not a Number)

import "math"
fmt.Println(math.IsInf(10.0/0.0, 1))   // true
fmt.Println(math.IsNaN(0.0 / 0.0))     // true
```

### String concatenation in loops — use strings.Builder

The `+` operator works for strings, but creates a new string on every call. In a loop this is O(n²):

```go
// BAD — slow for large loops
result := ""
for i := 0; i < 1000; i++ {
    result += "x"   // allocates a new string every iteration
}

// GOOD — use strings.Builder
import "strings"
var sb strings.Builder
for i := 0; i < 1000; i++ {
    sb.WriteString("x")
}
result := sb.String()
```

---

## 10. Quick Reference Cheatsheet

```go
// ── Arithmetic ───────────────────────────────────────────
+    addition
-    subtraction
*    multiplication
/    division          (integer division truncates)
%    modulus / remainder
++   increment         (statement only, postfix only)
--   decrement         (statement only, postfix only)

// ── Assignment ───────────────────────────────────────────
=    assign
:=   declare and assign (inside functions only)
+=   add and assign
-=   subtract and assign
*=   multiply and assign
/=   divide and assign
%=   modulus and assign

// ── Comparison (return bool) ─────────────────────────────
==   equal
!=   not equal
<    less than
>    greater than
<=   less than or equal
>=   greater than or equal

// ── Logical ──────────────────────────────────────────────
&&   AND    (short-circuits on false)
||   OR     (short-circuits on true)
!    NOT

// ── Bitwise ──────────────────────────────────────────────
&    AND
|    OR
^    XOR  (binary) / NOT (unary)
&^   AND NOT (bit clear)
<<   left shift   (× 2 per shift)
>>   right shift  (÷ 2 per shift)

// ── Pointer ──────────────────────────────────────────────
&x   address of x
*p   dereference p
*T   pointer-to-T (type)

// ── Precedence (high → low) ──────────────────────────────
5:  * / % << >> & &^
4:  + - | ^
3:  == != < <= > >=
2:  &&
1:  ||
```

---

_Previous: [[Go - Variables and Types]] · Next: [[03 - Control Flow]]_