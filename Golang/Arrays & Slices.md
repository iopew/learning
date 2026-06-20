# Go — Arrays & Slices

> **Series:** Go Language Fundamentals **Tags:** #go #golang #arrays #slices #append #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. Arrays]]
- [[#2. Multi-Dimensional Arrays]]
- [[#3. Arrays vs Slices — When to Use Each]]
- [[#4. Slices — Internal Structure]]
- [[#5. Creating Slices]]
- [[#6. nil vs Empty Slice]]
- [[#7. append — Mechanics and Growth]]
- [[#8. copy()]]
- [[#9. Slice Expressions — [low:high:max]]]
- [[#10. Slices of Slices]]
- [[#11. Passing Slices to Functions]]
- [[#12. Common Gotchas]]
- [[#13. Sorting]]
- [[#14. Searching]]
- [[#15. 2D Slices]]
- [[#16. Performance Notes]]
- [[#17. Quick Reference Cheatsheet]]

---

## 1. Arrays

An array is a **fixed-length** sequence of elements of the same type. The size is part of the type itself.

```go
var arr [5]int                    // [0 0 0 0 0] — zero-valued
primes := [5]int{2, 3, 5, 7, 11}  // literal with explicit size
auto := [...]int{10, 20, 30}      // compiler counts elements → [3]int

fmt.Println(len(primes))   // 5
fmt.Println(primes[0])     // 2
```

### `[N]T` — size is part of the type

```go
var a [3]int
var b [5]int

// a and b are DIFFERENT types — [3]int and [5]int are not interchangeable
// a = b           // compile error
// func f(x [3]int) cannot accept a [5]int
```

This is a critical distinction from slices — `[3]int` and `[5]int` are as different to the compiler as `int` and `string`.

### `[...]T` — let the compiler count

```go
weekdays := [...]string{"Mon", "Tue", "Wed", "Thu", "Fri"}
fmt.Println(len(weekdays))   // 5 — compiler counted the literal
```

You can also set specific indices, leaving gaps to be zero-valued:

```go
sparse := [10]int{0: 1, 5: 99, 9: 42}
fmt.Println(sparse)   // [1 0 0 0 0 99 0 0 0 42]
```

### Arrays are VALUE types

This is the single most important fact about arrays in Go. Assigning or passing an array **copies the entire thing**, every element.

```go
original := [3]int{1, 2, 3}
copy := original          // full copy — independent array
copy[0] = 99

fmt.Println(original)     // [1 2 3] — unchanged
fmt.Println(copy)         // [99 2 3]
```

```go
func zeroOut(arr [3]int) {
    arr[0] = 0   // mutates the COPY only
}

a := [3]int{1, 2, 3}
zeroOut(a)
fmt.Println(a)   // [1 2 3] — unchanged, unlike C or JavaScript!
```

> [!warning] Passing large arrays by value is expensive A `[10000]int` passed to a function copies 80KB every single call. If you must pass a large array, pass a pointer: `func f(arr *[10000]int)`.

### Comparing arrays

Unlike slices, arrays **can** be compared with `==` — as long as the element type is comparable:

```go
a := [3]int{1, 2, 3}
b := [3]int{1, 2, 3}
c := [3]int{1, 2, 4}

fmt.Println(a == b)   // true — same length, same values
fmt.Println(a == c)   // false
```

---

## 2. Multi-Dimensional Arrays

```go
var grid [3][3]int   // 3x3 grid, all zero

grid[0][0] = 1
grid[1][1] = 5
grid[2][2] = 9

fmt.Println(grid)
// [[1 0 0] [0 5 0] [0 0 9]]

// Literal form
matrix := [2][3]int{
    {1, 2, 3},
    {4, 5, 6},
}

fmt.Println(matrix[1][2])   // 6
```

### Iterating a 2D array

```go
for i := range grid {
    for j := range grid[i] {
        fmt.Printf("grid[%d][%d] = %d\n", i, j, grid[i][j])
    }
}
```

Multi-dimensional arrays are rare in real Go code — 2D **slices** (covered later) are used far more often because of their flexibility.

---

## 3. Arrays vs Slices — When to Use Each

||Array|Slice|
|---|---|---|
|Size|Fixed, part of the type|Dynamic, can grow|
|Type|`[N]T`|`[]T`|
|Assignment|Full copy|Shares backing array|
|Passed to function|Copied entirely|Header copied, data shared|
|Comparable with `==`|Yes|No (compile error)|
|Common usage|Rare|Extremely common|

> [!tip] The practical rule In real Go code, you almost always want a **slice**, not an array. Arrays show up mainly in three situations: fixed-size buffers where the size genuinely never changes (like a SHA-256 hash `[32]byte`), as the backing store that a slice points into, or in performance-critical code where avoiding heap allocation matters. When in doubt, use a slice.

```go
// Array — genuinely fixed size, used in crypto
type Hash [32]byte

// Slice — the normal choice for "a list of things"
func processUsers(users []User) { ... }
```

---

## 4. Slices — Internal Structure

A slice is **not** the data itself — it's a small struct (called the "slice header") containing three fields:

```
type sliceHeader struct {
    ptr *T   // pointer to the first element in the backing array
    len int  // number of elements currently accessible
    cap int  // total capacity of the backing array from ptr onward
}
```

```go
s := []int{10, 20, 30, 40, 50}
fmt.Println(len(s))   // 5 — accessible elements
fmt.Println(cap(s))   // 5 — backing array capacity
```

### Visualizing the relationship

```
backing array:  [10, 20, 30, 40, 50]
                  ↑
s.ptr  ───────────┘
s.len  = 5
s.cap  = 5
```

Every slice "points into" an underlying array. Multiple slices can point into the **same** backing array simultaneously — this is the source of both slices' power and their most common gotchas.

```go
s := []int{10, 20, 30, 40, 50}
sub := s[1:3]   // [20 30]

fmt.Println(len(sub))   // 2
fmt.Println(cap(sub))   // 4 — from index 1 to the END of the backing array, not just len!
```

`cap` of a sub-slice extends from its starting point to the end of the **original** backing array, not just to where the sub-slice's elements end.

---

## 5. Creating Slices

### From a literal

```go
fruits := []string{"apple", "banana", "cherry"}
// no size in the brackets — that's what makes it a slice, not an array
```

### Using `make`

```go
make([]T, length)          // len = cap = length, zero-valued
make([]T, length, capacity) // len = length, cap = capacity (cap >= length)

a := make([]int, 3)       // [0 0 0], len=3, cap=3
b := make([]int, 3, 10)   // [0 0 0], len=3, cap=10 — room to grow without reallocation
```

### From an array

```go
arr := [5]int{1, 2, 3, 4, 5}
s := arr[:]          // slice covering the whole array
s2 := arr[1:4]        // [2 3 4]
```

A slice created from an array **shares the array's memory** — modifying the slice modifies the array and vice versa.

### Slice of structs

```go
type Point struct{ X, Y int }

points := []Point{
    {X: 1, Y: 2},
    {X: 3, Y: 4},
}
```

---

## 6. nil vs Empty Slice

This distinction trips up a lot of people — both behave almost identically in everyday code, but they are NOT the same thing.

```go
var nilSlice []int          // nil — no backing array at all
emptySlice := []int{}       // non-nil — backing array exists, just has 0 elements

fmt.Println(nilSlice == nil)    // true
fmt.Println(emptySlice == nil)  // false

fmt.Println(len(nilSlice))      // 0
fmt.Println(len(emptySlice))    // 0
// both have len 0 — looks identical in most operations
```

### Operations that work fine on both

```go
// range works the same on both — zero iterations either way
for _, v := range nilSlice { }
for _, v := range emptySlice { }

// append works on both — nil slices grow normally
nilSlice = append(nilSlice, 1)   // works fine, allocates a backing array
```

### Where the difference actually matters

```go
import "encoding/json"

var nilSlice []int
emptySlice := []int{}

b1, _ := json.Marshal(nilSlice)
b2, _ := json.Marshal(emptySlice)

fmt.Println(string(b1))   // null
fmt.Println(string(b2))   // []
```

A nil slice marshals to JSON `null`. An empty (non-nil) slice marshals to `[]`. If your API consumer expects an array and gets `null`, that can break their code.

> [!tip] Idiomatic default Prefer returning `nil` for "no results" in regular Go code — it's the zero value and requires no allocation. Only construct an explicit `[]T{}` when you specifically need JSON output to be `[]` rather than `null`.

---

## 7. append — Mechanics and Growth

`append` adds elements to the end of a slice, returning a (possibly new) slice.

```go
s := []int{1, 2, 3}
s = append(s, 4)        // [1 2 3 4]
s = append(s, 5, 6, 7)  // [1 2 3 4 5 6 7] — multiple values

other := []int{8, 9}
s = append(s, other...)  // spread — appends all elements of other
```

### What happens under the hood

`append` checks if there's spare capacity in the backing array:

**Case 1 — spare capacity exists:** writes directly into the existing backing array, just increases `len`.

```go
s := make([]int, 3, 10)   // len=3, cap=10 — 7 spare slots
s = append(s, 4)          // writes into slot 4, len becomes 4
                           // SAME backing array — cap stays 10
```

**Case 2 — no spare capacity:** Go allocates a **brand new, larger** backing array, copies all existing elements over, then appends the new one.

```go
s := make([]int, 3, 3)    // len=3, cap=3 — completely full
s = append(s, 4)          // no room! Go allocates a new array
                           // (commonly doubles capacity for small slices)
                           // copies [1,2,3] into it, then adds 4
                           // s now points to a DIFFERENT backing array
```

### The growth pattern

Go's growth strategy roughly doubles capacity for small slices and grows more conservatively (around 1.25x) for larger ones, to balance speed against wasted memory. This is an implementation detail and can change between Go versions — never rely on exact growth numbers.

```go
s := make([]int, 0)
for i := 0; i < 10; i++ {
    s = append(s, i)
    fmt.Println(len(s), cap(s))
}
// len/cap typically grows: 1/1, 2/2, 3/4, 4/4, 5/8, 6/8, 7/8, 8/8, 9/16, 10/16
// (exact numbers vary by Go version — don't hardcode logic around them)
```

### Why you must always reassign the result of append

```go
s := []int{1, 2, 3}
append(s, 4)         // WRONG — return value discarded, s unchanged!
fmt.Println(s)       // [1 2 3]

s = append(s, 4)     // RIGHT — reassign
fmt.Println(s)       // [1 2 3 4]
```

`append` may or may not return a slice pointing to the same backing array — you cannot know which case you're in without checking, so you must **always** capture and use the return value.

---

## 8. copy()

`copy(dst, src)` copies elements from `src` into `dst`, returning the number of elements actually copied (the minimum of `len(dst)` and `len(src)`).

```go
src := []int{1, 2, 3, 4, 5}
dst := make([]int, 3)

n := copy(dst, src)
fmt.Println(dst)   // [1 2 3] — only 3 elements fit
fmt.Println(n)      // 3 — number copied
```

### The idiomatic way to make an independent copy

```go
original := []int{1, 2, 3}
clone := make([]int, len(original))
copy(clone, original)

clone[0] = 99
fmt.Println(original)   // [1 2 3] — unaffected
fmt.Println(clone)      // [99 2 3]
```

`copy` is also safe with overlapping slices (copying within the same backing array), unlike a naive manual loop.

```go
s := []int{1, 2, 3, 4, 5}
copy(s[1:], s[:4])   // shift everything right by 1
fmt.Println(s)        // [1 1 2 3 4]
```

---

## 9. Slice Expressions — [low:high:max]

```go
s := []int{0, 1, 2, 3, 4, 5}

a := s[1:4]      // [1 2 3] — elements from index 1 up to (not including) 4
b := s[:3]       // [0 1 2] — from the start up to index 3
c := s[2:]       // [2 3 4 5] — from index 2 to the end
d := s[:]        // [0 1 2 3 4 5] — the whole slice
```

### The three-index form — controlling capacity

A third index controls the **capacity** of the resulting slice, capping how far `append` can grow it before triggering a reallocation:

```go
s := []int{0, 1, 2, 3, 4, 5}

a := s[1:3]      // len=2, cap=5 (extends to end of backing array)
b := s[1:3:3]    // len=2, cap=2 (capped at index 3)

fmt.Println(len(a), cap(a))   // 2 5
fmt.Println(len(b), cap(b))   // 2 2
```

This is used to deliberately **prevent** a sub-slice from sharing capacity with the original — appending to `b` is now guaranteed to allocate a new backing array rather than silently overwriting data the original slice still references.

```go
original := []int{1, 2, 3, 4, 5}
sub := original[1:3:3]      // capped — cannot grow into original's space
sub = append(sub, 99)       // forces a new backing array

fmt.Println(original)       // [1 2 3 4 5] — completely unaffected
fmt.Println(sub)            // [2 3 99]
```

---

## 10. Slices of Slices

```go
matrix := [][]int{
    {1, 2, 3},
    {4, 5, 6},
    {7, 8, 9},
}

fmt.Println(matrix[1][2])   // 6

// Iterate
for i, row := range matrix {
    for j, val := range row {
        fmt.Printf("matrix[%d][%d] = %d\n", i, j, val)
    }
}
```

Unlike a 2D array, each row in a `[][]int` is an **independent slice** with its own backing array — rows don't need to be the same length (a "jagged" or "ragged" slice):

```go
jagged := [][]int{
    {1},
    {2, 3},
    {4, 5, 6},
}
fmt.Println(jagged[2])   // [4 5 6]
```

---

## 11. Passing Slices to Functions

The slice header (ptr, len, cap) is copied — but the pointer inside still points to the same backing array.

```go
func setFirst(s []int) {
    if len(s) > 0 {
        s[0] = 999   // writes through the shared pointer — VISIBLE to caller
    }
}

s := []int{1, 2, 3}
setFirst(s)
fmt.Println(s)   // [999 2 3]
```

But reassigning the slice variable itself inside the function only changes the **local copy of the header**:

```go
func appendOne(s []int) {
    s = append(s, 99)   // local header reassignment — invisible to caller
}

s := []int{1, 2, 3}
appendOne(s)
fmt.Println(s)   // [1 2 3] — unchanged!
```

### The fix — return the new slice

```go
func appendOne(s []int) []int {
    return append(s, 99)
}

s := []int{1, 2, 3}
s = appendOne(s)    // caller reassigns
fmt.Println(s)      // [1 2 3 99]
```

This is why so many slice-related functions in Go (and the standard library) follow the `s = f(s, ...)` pattern.

---

## 12. Common Gotchas

### Gotcha 1 — append silently overwriting shared data

```go
original := []int{1, 2, 3, 4, 5}
sub := original[1:3]        // [2 3], but cap=4 — extends into original's space

sub = append(sub, 999)      // fits within capacity — writes into original's backing array!

fmt.Println(original)       // [1 2 3 999 5] — corrupted!
fmt.Println(sub)            // [2 3 999]
```

`sub` had spare capacity (because it shared `original`'s backing array), so `append` wrote directly into memory `original` also references — silently corrupting data the caller didn't expect to change.

> [!warning] The fix Use the three-index slice expression `original[1:3:3]` to cap the capacity, forcing any `append` to allocate fresh memory instead of overwriting the source.

### Gotcha 2 — range gives you a copy

```go
nums := []int{1, 2, 3}
for _, v := range nums {
    v *= 10   // modifies the COPY, not the original
}
fmt.Println(nums)   // [1 2 3] — unchanged!

// Fix — use the index
for i := range nums {
    nums[i] *= 10
}
fmt.Println(nums)   // [10 20 30]
```

### Gotcha 3 — taking the address of a loop variable

```go
nums := []int{1, 2, 3}
ptrs := make([]*int, len(nums))

for i, v := range nums {
    ptrs[i] = &v   // &v is always the SAME address — the loop variable's
}

fmt.Println(*ptrs[0], *ptrs[1], *ptrs[2])   // 3 3 3 — all point to the last value!

// Fix — take the address from the slice directly
for i := range nums {
    ptrs[i] = &nums[i]
}
fmt.Println(*ptrs[0], *ptrs[1], *ptrs[2])   // 1 2 3
```

> [!info] Fixed in Go 1.22+ From Go 1.22 onward, each loop iteration gets its own copy of the loop variable, so `&v` is safe. This remains a notorious bug source in code targeting older Go versions or modules with `go 1.21` or earlier in `go.mod`.

### Gotcha 4 — append return value discarded

```go
s := []int{1, 2, 3}
append(s, 4)         // return value thrown away — does nothing useful
fmt.Println(s)       // [1 2 3] — append's result was never captured
```

### Gotcha 5 — comparing slices with ==

```go
a := []int{1, 2, 3}
b := []int{1, 2, 3}
// fmt.Println(a == b)   // compile error — slices are not comparable

// Use reflect.DeepEqual instead
import "reflect"
fmt.Println(reflect.DeepEqual(a, b))   // true

// Or compare manually for performance-sensitive code
func equal(a, b []int) bool {
    if len(a) != len(b) {
        return false
    }
    for i := range a {
        if a[i] != b[i] {
            return false
        }
    }
    return true
}
```

> [!info] slices.Equal — Go 1.21+ The standard library `slices` package provides `slices.Equal(a, b)`, which is the idiomatic modern way to compare slices without writing your own loop.

---

## 13. Sorting

### sort.Slice — custom comparison

```go
import "sort"

words := []string{"banana", "kiwi", "apple"}

sort.Slice(words, func(i, j int) bool {
    return len(words[i]) < len(words[j])   // sort by length
})
// ["kiwi" "apple" "banana"]
```

```go
type Person struct {
    Name string
    Age  int
}

people := []Person{
    {"Bob", 30},
    {"Alice", 25},
    {"Carol", 35},
}

sort.Slice(people, func(i, j int) bool {
    return people[i].Age < people[j].Age
})
// sorted by age: Alice(25), Bob(30), Carol(35)
```

### Built-in convenience sorters

```go
nums := []int{5, 2, 8, 1, 9}
sort.Ints(nums)
fmt.Println(nums)   // [1 2 5 8 9]

strs := []string{"banana", "apple", "cherry"}
sort.Strings(strs)
fmt.Println(strs)   // [apple banana cherry]

floats := []float64{3.1, 1.4, 2.7}
sort.Float64s(floats)
fmt.Println(floats)   // [1.4 2.7 3.1]
```

### Checking if a slice is sorted

```go
fmt.Println(sort.IntsAreSorted([]int{1, 2, 3}))   // true
fmt.Println(sort.IntsAreSorted([]int{3, 1, 2}))   // false
```

### sort.Stable — preserving relative order

`sort.Slice` does not guarantee that equal elements keep their original relative order. `sort.SliceStable` does:

```go
sort.SliceStable(people, func(i, j int) bool {
    return people[i].Age < people[j].Age
})
```

### Modern alternative — the slices package (Go 1.21+)

```go
import "slices"

nums := []int{5, 2, 8, 1, 9}
slices.Sort(nums)               // generic, works on any ordered type
fmt.Println(nums)               // [1 2 5 8 9]

slices.SortFunc(people, func(a, b Person) int {
    return a.Age - b.Age
})
```

---

## 14. Searching

### sort.Search — binary search on a sorted slice

`sort.Search` requires the slice to already be sorted, and finds the smallest index where a condition becomes true:

```go
nums := []int{1, 3, 5, 7, 9, 11}

idx := sort.Search(len(nums), func(i int) bool {
    return nums[i] >= 5
})
fmt.Println(idx)   // 2 — index of the first element >= 5
```

### Convenience wrappers

```go
nums := []int{1, 3, 5, 7, 9}
idx := sort.SearchInts(nums, 7)
fmt.Println(idx)   // 3
```

### Linear search — when the slice isn't sorted

```go
func contains(s []int, target int) bool {
    for _, v := range s {
        if v == target {
            return true
        }
    }
    return false
}
```

### Modern alternative — slices package

```go
import "slices"

nums := []int{1, 3, 5, 7, 9}
idx, found := slices.BinarySearch(nums, 7)
fmt.Println(idx, found)   // 3 true

fmt.Println(slices.Contains(nums, 5))   // true — linear search, no sort needed
```

---

## 15. 2D Slices

### Creating a 2D slice properly

The naive approach creates rows that all share the same backing array — a common trap:

```go
// WRONG — every row shares the same underlying array slot pattern issue
rows := 3
cols := 3
grid := make([][]int, rows)
for i := range grid {
    grid[i] = make([]int, cols)   // each row gets its OWN backing array — this part is correct
}
grid[0][0] = 1
fmt.Println(grid)   // [[1 0 0] [0 0 0] [0 0 0]] — correct, rows are independent
```

The above is actually correct — each row is independently allocated. The real trap is forgetting to allocate each row at all:

```go
// WRONG — rows are nil, indexing panics
grid := make([][]int, 3)
grid[0][0] = 1   // panic: index out of range — grid[0] is nil, has len 0
```

### Flattened 2D — a single backing array (better cache locality)

For performance-sensitive code, a flattened single slice often outperforms a slice-of-slices because all data lives contiguously in memory:

```go
rows, cols := 3, 3
flat := make([]int, rows*cols)

set := func(r, c, val int) { flat[r*cols+c] = val }
get := func(r, c int) int { return flat[r*cols+c] }

set(1, 1, 5)
fmt.Println(get(1, 1))   // 5
```

---

## 16. Performance Notes

### Pre-allocate with make when the size is known

```go
// BAD — repeated reallocation as the slice grows
var s []int
for i := 0; i < 10000; i++ {
    s = append(s, i)   // may reallocate and copy many times
}

// GOOD — allocate once with the right capacity
s := make([]int, 0, 10000)
for i := 0; i < 10000; i++ {
    s = append(s, i)   // never reallocates — capacity already sufficient
}
```

### make([]T, n) vs make([]T, 0, n)

```go
a := make([]int, 5)      // len=5, cap=5 — 5 zero-valued elements, ready to INDEX into
b := make([]int, 0, 5)   // len=0, cap=5 — empty, ready to APPEND into

a[0] = 1       // works — index 0 exists
// b[0] = 1    // panic: index out of range — b has len 0
b = append(b, 1)   // works — appending into spare capacity
```

Use `make([]T, n)` when you'll be **indexing** into specific positions. Use `make([]T, 0, n)` when you'll be **appending**.

### Avoid unnecessary copying

```go
// Passing a slice is cheap — only the header (24 bytes) is copied
func process(data []byte) { ... }   // fine even for huge data

// Returning a slice is also cheap — same reason
func generate() []int { ... }
```

Unlike arrays, slices are cheap to pass around regardless of how much data they reference — only the small header gets copied, never the underlying data.

---

## 17. Quick Reference Cheatsheet

```go
// ── Arrays ───────────────────────────────────────────────
var a [5]int                    // zero-valued array
a := [5]int{1, 2, 3, 4, 5}      // literal
a := [...]int{1, 2, 3}          // compiler counts size
a == b                          // arrays ARE comparable
copy := original                // arrays are FULLY COPIED on assignment

// ── Creating slices ──────────────────────────────────────
s := []int{1, 2, 3}             // slice literal
s := make([]int, 5)             // len=5 cap=5, zero-valued
s := make([]int, 0, 5)          // len=0 cap=5, ready to append
s := arr[:]                     // slice from array, shares memory

// ── nil vs empty ─────────────────────────────────────────
var s []int        // nil, len=0, json → null
s := []int{}       // not nil, len=0, json → []

// ── append ───────────────────────────────────────────────
s = append(s, 1)                // single element
s = append(s, 1, 2, 3)          // multiple elements
s = append(s, other...)         // spread another slice
// ALWAYS reassign — append may or may not reallocate

// ── copy ─────────────────────────────────────────────────
n := copy(dst, src)             // copies min(len(dst), len(src))
clone := make([]int, len(s))
copy(clone, s)                  // idiomatic independent copy

// ── slicing ──────────────────────────────────────────────
s[1:4]        // elements 1,2,3 (low inclusive, high exclusive)
s[:3]         // from start
s[2:]         // to end
s[:]          // whole slice
s[1:3:3]      // three-index — caps capacity, prevents append aliasing

// ── 2D ───────────────────────────────────────────────────
grid := make([][]int, rows)
for i := range grid {
    grid[i] = make([]int, cols)  // each row needs its OWN allocation
}

// ── sorting ──────────────────────────────────────────────
sort.Ints(nums)
sort.Strings(strs)
sort.Slice(items, func(i, j int) bool { return items[i].X < items[j].X })
sort.SliceStable(items, less)   // preserves equal-element order
slices.Sort(nums)               // generic, Go 1.21+

// ── searching ────────────────────────────────────────────
sort.Search(len(s), func(i int) bool { return s[i] >= target })
slices.BinarySearch(s, target)  // Go 1.21+
slices.Contains(s, target)      // linear search, Go 1.21+

// ── gotchas to remember ──────────────────────────────────
// 1. append into a shared backing array can corrupt the original
// 2. range gives a COPY — use s[i] to mutate
// 3. &v in a range loop is always the same address (pre Go 1.22)
// 4. always reassign: s = append(s, x)
// 5. slices can't use ==, use reflect.DeepEqual or slices.Equal
```

---

_Previous: [[Go - Functions]] · Next: [[Maps]]_