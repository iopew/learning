******# Go — Maps

> **Series:** Go Language Fundamentals **Tags:** #go #golang #maps #datastructures #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. map[K]V Syntax]]
- [[#2. Creating Maps]]
- [[#3. The nil Map Panic]]
- [[#4. CRUD Operations]]
- [[#5. Comma-ok Existence Check]]
- [[#6. delete()]]
- [[#7. Iteration — Order Is Never Guaranteed]]
- [[#8. Maps Are Reference Types]]
- [[#9. Nested Maps]]
- [[#10. Maps of Slices]]
- [[#11. Counting With Maps]]
- [[#12. The Set Pattern — map[T]struct{}]]
- [[#13. Maps and Concurrency]]
- [[#14. Comparing Maps]]
- [[#15. JSON and Maps]]
- [[#16. Performance Notes]]
- [[#17. Quick Reference Cheatsheet]]

---

## 1. map[K]V Syntax

A map is Go's built-in hash table — an unordered collection of key-value pairs.

```go
var m map[string]int   // declares the TYPE: keys are string, values are int
```

```
map [ K ] V
    ↑     ↑
   key   value
   type  type
```

### What can be a key

Map keys must be a **comparable** type — anything that supports `==`. This includes all basic types (int, string, bool, float), arrays, structs (if all their fields are comparable), and pointers.

```go
map[string]int        // string keys
map[int]string         // int keys
map[bool]string         // bool keys (rare, but valid)
map[[2]int]string       // array keys — arrays ARE comparable

type Point struct{ X, Y int }
map[Point]string         // struct keys — valid if all fields are comparable
```

> [!warning] Slices, maps, and functions cannot be map keys These types are not comparable with `==`, so Go rejects them as keys:
> 
> ```go
> // map[[]int]string{}   // compile error — slice is not comparable
> // map[map[string]int]string{}  // compile error
> ```

---

## 2. Creating Maps

### Using make

```go
m := make(map[string]int)
m["Alice"] = 30
m["Bob"] = 25

fmt.Println(m)   // map[Alice:30 Bob:25]
```

### Map literals

```go
ages := map[string]int{
    "Alice": 30,
    "Bob":   25,
    "Carol": 35,
}
```

```go
// An empty map literal — NOT nil, ready to use
empty := map[string]int{}
```

### make with a size hint

```go
m := make(map[string]int, 100)   // hint: expect ~100 entries
// this is a PERFORMANCE hint only — the map still grows automatically
// beyond 100 if needed, this just pre-allocates buckets to reduce
// reallocation as you insert
```

---

## 3. The nil Map Panic

A **declared but uninitialized** map is `nil` — and writing to a nil map panics:

```go
var m map[string]int   // nil map — no underlying hash table

fmt.Println(m == nil)   // true
fmt.Println(len(m))      // 0 — reading from nil map is SAFE
fmt.Println(m["key"])    // 0 — reading a missing key from nil map is SAFE, returns zero value

m["key"] = 1   // PANIC: assignment to entry in nil map
```

> [!warning] Reading from nil is safe, writing is not This is the single most important rule about nil maps. You can `range` over a nil map (zero iterations), read any key from it (returns the zero value), and call `len()` on it (returns 0) — all completely safely. The moment you try to **write** a key, it panics.

### The fix

```go
var m map[string]int
m = make(map[string]int)   // initialize before writing
m["key"] = 1                // now safe
```

```go
// Or initialize at declaration
m := make(map[string]int)
m["key"] = 1   // safe from the start
```

---

## 4. CRUD Operations

```go
m := make(map[string]int)

// Create / Update — same syntax for both
m["Alice"] = 30          // create
m["Alice"] = 31           // update — overwrites silently, no error

// Read
age := m["Alice"]          // 31
missing := m["Zara"]       // 0 — zero value, NOT an error or panic

// Delete
delete(m, "Alice")
```

> [!info] No distinction between create and update Unlike some databases or ORMs, `m[key] = value` always works the same way whether the key exists already or not — it simply sets the value. There's no separate "insert" vs "update" operation.

### Reading a missing key returns the zero value — this can be misleading

```go
scores := map[string]int{"Alice": 0}   // Alice genuinely has a score of 0
missing := scores["Bob"]                // Bob doesn't exist, also returns 0

// Both look identical here — you CANNOT tell them apart with plain indexing!
fmt.Println(scores["Alice"])   // 0
fmt.Println(scores["Bob"])     // 0 — but Bob was never in the map
```

This ambiguity is exactly what the comma-ok pattern solves.

---

## 5. Comma-ok Existence Check

```go
m := map[string]int{"Alice": 30}

val, ok := m["Alice"]
fmt.Println(val, ok)   // 30 true

val, ok = m["Bob"]
fmt.Println(val, ok)   // 0 false — Bob doesn't exist
```

`ok` is a `bool` that's `true` if the key was found, `false` if not. This is the **only** reliable way to distinguish "key exists with zero value" from "key doesn't exist."

```go
// The idiomatic check
if val, ok := m["Alice"]; ok {
    fmt.Println("found:", val)
} else {
    fmt.Println("not found")
}
```

```go
// Common shorthand when you only care about existence, not the value
if _, ok := m["Alice"]; ok {
    fmt.Println("Alice is in the map")
}
```

---

## 6. delete()

```go
m := map[string]int{"Alice": 30, "Bob": 25}

delete(m, "Alice")
fmt.Println(m)   // map[Bob:25]
```

### delete on a missing key is a safe no-op

```go
delete(m, "Zara")   // Zara doesn't exist — does nothing, no panic, no error
```

`delete` is one of the few Go built-ins that's completely forgiving — you never need to check existence before calling it.

### delete inside a range loop — safe in Go

```go
m := map[string]int{"a": 1, "b": 2, "c": 3}

for k, v := range m {
    if v == 2 {
        delete(m, k)   // safe — Go's map iteration is designed to handle this
    }
}
fmt.Println(m)   // map[a:1 c:3]
```

> [!info] Deleting during iteration is explicitly safe in Go The Go specification guarantees that deleting the current key during a `range` over a map is safe and won't cause a panic or skip entries unpredictably. Adding new keys during iteration, however, has undefined behavior — the new key may or may not be visited.

---

## 7. Iteration — Order Is Never Guaranteed

```go
m := map[string]int{"Alice": 30, "Bob": 25, "Carol": 35}

for name, age := range m {
    fmt.Println(name, age)
}
// order is RANDOM — different every time you run this program
```

> [!warning] Go deliberately randomizes map iteration order This isn't just "unspecified" — Go's runtime actively randomizes the starting point of map iteration on each run, specifically to prevent developers from accidentally writing code that depends on a particular order (which would then break unpredictably when the internal hash implementation changes).

### If you need a consistent order — sort the keys first

```go
import "sort"

m := map[string]int{"Carol": 35, "Alice": 30, "Bob": 25}

keys := make([]string, 0, len(m))
for k := range m {
    keys = append(keys, k)
}
sort.Strings(keys)

for _, k := range keys {
    fmt.Println(k, m[k])
}
// Alice 30
// Bob 25
// Carol 35
// — now deterministic
```

---

## 8. Maps Are Reference Types

Unlike structs and arrays, a map variable is internally a pointer to a hash table structure. Copying a map variable copies the pointer, not the data — both variables refer to the **same** underlying map.

```go
original := map[string]int{"a": 1}
alias := original          // copies the reference, NOT the data

alias["b"] = 2
fmt.Println(original)      // map[a:1 b:2] — original is affected too!
```

This is fundamentally different from struct or array assignment:

```go
// Structs and arrays — full copy, independent
type Point struct{ X, Y int }
p1 := Point{1, 2}
p2 := p1
p2.X = 99
fmt.Println(p1)   // {1 2} — unaffected

// Maps — shared reference, NOT independent
m1 := map[string]int{"x": 1}
m2 := m1
m2["x"] = 99
fmt.Println(m1)   // map[x:99] — affected!
```

### Passing maps to functions

Because maps are reference types, mutations inside a function are visible to the caller without needing a pointer:

```go
func addEntry(m map[string]int) {
    m["new"] = 1   // mutates the SAME underlying map the caller has
}

m := map[string]int{}
addEntry(m)
fmt.Println(m)   // map[new:1] — visible! No pointer needed.
```

> [!info] This is the same behavior as slices Maps and slices share this property: passing them to a function lets the function mutate the shared underlying data without needing `*map[K]V`. You almost never see map pointers in idiomatic Go code for this reason.

### How to make an independent copy of a map

```go
func cloneMap(m map[string]int) map[string]int {
    clone := make(map[string]int, len(m))
    for k, v := range m {
        clone[k] = v
    }
    return clone
}

original := map[string]int{"a": 1}
copy := cloneMap(original)
copy["b"] = 2

fmt.Println(original)   // map[a:1] — unaffected
fmt.Println(copy)        // map[a:1 b:2]
```

> [!info] maps.Clone — Go 1.21+ The standard library `maps` package provides `maps.Clone(m)`, doing exactly the above in one call.

---

## 9. Nested Maps

```go
// map of string to map of string to int
data := map[string]map[string]int{
    "alice": {"math": 90, "science": 85},
    "bob":   {"math": 75, "science": 95},
}

fmt.Println(data["alice"]["math"])   // 90
```

### The nil-map-of-maps trap

```go
data := map[string]map[string]int{}

data["alice"]["math"] = 90   // PANIC! data["alice"] doesn't exist yet — it's nil
```

When you access `data["alice"]` and it doesn't exist, you get the zero value for `map[string]int`, which is `nil`. Writing into a nil inner map panics, just like any nil map.

### The fix — initialize the inner map first

```go
data := map[string]map[string]int{}

if _, ok := data["alice"]; !ok {
    data["alice"] = make(map[string]int)
}
data["alice"]["math"] = 90   // safe now
```

```go
// Helper function pattern — common in real code
func setNested(data map[string]map[string]int, outer, inner string, val int) {
    if data[outer] == nil {
        data[outer] = make(map[string]int)
    }
    data[outer][inner] = val
}
```

---

## 10. Maps of Slices

```go
groups := map[string][]string{
    "fruits":     {"apple", "banana"},
    "vegetables": {"carrot", "potato"},
}

groups["fruits"] = append(groups["fruits"], "cherry")
fmt.Println(groups["fruits"])   // [apple banana cherry]
```

### Appending to a key that might not exist yet

```go
groups := map[string][]string{}

// This works even if "fruits" doesn't exist yet!
groups["fruits"] = append(groups["fruits"], "apple")
fmt.Println(groups["fruits"])   // [apple]
```

This works because `groups["fruits"]` on a missing key returns the zero value for `[]string`, which is `nil` — and `append` on a nil slice works perfectly fine (it allocates a new backing array). This is the one case where the "missing key returns zero value" behavior is genuinely convenient rather than a trap.

### A common grouping pattern

```go
type Person struct {
    Name string
    City string
}

people := []Person{
    {"Alice", "NYC"},
    {"Bob", "LA"},
    {"Carol", "NYC"},
}

byCity := map[string][]Person{}
for _, p := range people {
    byCity[p.City] = append(byCity[p.City], p)
}

fmt.Println(byCity["NYC"])   // [{Alice NYC} {Carol NYC}]
```

---

## 11. Counting With Maps

The most common practical use of maps — frequency counting.

```go
words := []string{"go", "is", "fun", "go", "is", "go"}

counts := map[string]int{}
for _, w := range words {
    counts[w]++   // missing key reads as 0, then ++ makes it 1
}

fmt.Println(counts)   // map[fun:1 go:3 is:2]
```

`counts[w]++` works in one line because of the same "missing key returns zero value" behavior — no need to check existence first, since the zero value for `int` (`0`) is exactly the right starting point for counting.

### Finding the most frequent item

```go
maxWord := ""
maxCount := 0
for word, count := range counts {
    if count > maxCount {
        maxWord = word
        maxCount = count
    }
}
fmt.Println(maxWord, maxCount)   // go 3
```

---

## 12. The Set Pattern — map[T]struct{}

Go has no built-in `Set` type — the idiomatic substitute is a map where you only care about the keys, with `struct{}` (the empty struct) as the value because it takes **zero bytes** of memory.

```go
set := map[string]struct{}{
    "apple":  {},
    "banana": {},
}

// Check membership
_, exists := set["apple"]
fmt.Println(exists)   // true

// Add
set["cherry"] = struct{}{}

// Remove
delete(set, "banana")
```

### Why struct{} instead of bool

```go
// Using bool — wastes 1 byte per entry, and creates ambiguity
setBool := map[string]bool{"apple": true}
setBool["banana"] = false   // is "banana" in the set or not?? confusing!

// Using struct{} — zero bytes, unambiguous (presence = membership)
setEmpty := map[string]struct{}{"apple": {}}
// there's no "false" state — a key is either present or absent, period
```

With `map[string]bool`, someone could set a value to `false` and accidentally make the membership check ambiguous (`if set[x]` returns false both for "not in the set" and "explicitly set to false"). `struct{}` eliminates that ambiguity entirely — presence in the map is the only signal.

### Building a set from a slice

```go
func toSet(items []string) map[string]struct{} {
    set := make(map[string]struct{}, len(items))
    for _, item := range items {
        set[item] = struct{}{}
    }
    return set
}

fruits := toSet([]string{"apple", "banana", "apple"})   // duplicates collapse
fmt.Println(len(fruits))   // 2 — "apple" only counted once
```

### Set operations

```go
func union(a, b map[string]struct{}) map[string]struct{} {
    result := make(map[string]struct{})
    for k := range a {
        result[k] = struct{}{}
    }
    for k := range b {
        result[k] = struct{}{}
    }
    return result
}

func intersection(a, b map[string]struct{}) map[string]struct{} {
    result := make(map[string]struct{})
    for k := range a {
        if _, ok := b[k]; ok {
            result[k] = struct{}{}
        }
    }
    return result
}
```

A set is a collection where each item appears **at most once** — no duplicates. It answers one question efficiently: **"is this item in the collection?"**

Go has no built-in set type. The idiomatic substitute is a map where you only care about the keys, not the values.

---

### Why map[T]struct{} and not map[T]bool

You could use either, but `struct{}` is the standard:

go

```go
// With bool — works, but has problems
set := map[string]bool{}
set["apple"] = true
set["banana"] = false   // what does this mean? is banana "in" the set or not?

if set["apple"] { }    // true — apple is in the set
if set["banana"] { }   // false — but is banana absent, or just false?
```

The `bool` version creates ambiguity — a key set to `false` looks the same as a missing key when you check it. This defeats the purpose.

go

```go
// With struct{} — unambiguous
set := map[string]struct{}{}
set["apple"] = struct{}{}

_, ok := set["apple"]   // ok=true means present, ok=false means absent
                         // there is no "false" state — presence IS membership
```

Also, `struct{}` takes **zero bytes** of memory for its values — it's the empty struct. Using it signals clearly: "I only care about the keys."

---

### The four operations

go

```go
set := map[string]struct{}{}

// Add
set["apple"] = struct{}{}

// Check membership
_, ok := set["apple"]
if ok {
    fmt.Println("apple is in the set")
}

// Remove
delete(set, "apple")

// Size
fmt.Println(len(set))
```

---

### When to use a set

#### 1. Deduplication — removing duplicates from a slice

go

```go
words := []string{"go", "is", "fun", "go", "is", "go"}

seen := map[string]struct{}{}
var unique []string
for _, w := range words {
    if _, ok := seen[w]; !ok {
        seen[w] = struct{}{}
        unique = append(unique, w)
    }
}
fmt.Println(unique)   // [go is fun]
```

#### 2. Fast membership checking — "have I seen this before?"

go

```go
// Check if a username is already taken — O(1) lookup
taken := map[string]struct{}{
    "alice": {},
    "bob":   {},
    "carol": {},
}

username := "alice"
if _, ok := taken[username]; ok {
    fmt.Println("username taken")
}
```

Without a set, you'd have to linearly scan a slice every time — O(n). With a set, every check is O(1) regardless of how large the collection grows.

#### 3. Tracking visited items — graph traversal, cycle detection

go

```go
visited := map[string]struct{}{}

func dfs(node string) {
    if _, ok := visited[node]; ok {
        return   // already visited — stop
    }
    visited[node] = struct{}{}

    for _, neighbor := range graph[node] {
        dfs(neighbor)
    }
}
```

#### 4. Filtering — keeping only items that appear in a reference collection

go

```go
allowed := map[string]struct{}{
    "GET":    {},
    "POST":   {},
    "DELETE": {},
}

methods := []string{"GET", "PATCH", "POST", "PUT", "DELETE"}

var valid []string
for _, m := range methods {
    if _, ok := allowed[m]; ok {
        valid = append(valid, m)
    }
}
fmt.Println(valid)   // [GET POST DELETE]
```

---

### Set operations

go

```go
func union(a, b map[string]struct{}) map[string]struct{} {
    result := make(map[string]struct{})
    for k := range a { result[k] = struct{}{} }
    for k := range b { result[k] = struct{}{} }
    return result
}

func intersection(a, b map[string]struct{}) map[string]struct{} {
    result := make(map[string]struct{})
    for k := range a {
        if _, ok := b[k]; ok {
            result[k] = struct{}{}
        }
    }
    return result
}

func difference(a, b map[string]struct{}) map[string]struct{} {
    result := make(map[string]struct{})
    for k := range a {
        if _, ok := b[k]; !ok {
            result[k] = struct{}{}   // in a but NOT in b
        }
    }
    return result
}
```

---

### The short version

A set is just a map where the value type carries no information — `struct{}` is used because it's the smallest possible value (zero bytes). The keys ARE the set. Presence in the map means "in the set," absence means "not in the set." Use it whenever you need to track uniqueness or test membership efficiently.

---

## 13. Maps and Concurrency

> [!warning] Plain maps are NOT safe for concurrent use If multiple goroutines read and write to the same map simultaneously without synchronization, Go's runtime will detect this and **crash the program** with `fatal error: concurrent map writes` — this is not a panic you can recover from with `recover()`, it terminates the process immediately.

```go
m := map[string]int{}

// DANGEROUS — multiple goroutines writing concurrently
for i := 0; i < 10; i++ {
    go func(n int) {
	        m[fmt.Sprintf("key%d", n)] = n   // fatal error: concurrent map writes
    }(i)
}
```

### Fix 1 — protect with a sync.Mutex

```go
import "sync"

type SafeMap struct {
    mu sync.Mutex
    m  map[string]int
}

func (sm *SafeMap) Set(key string, val int) {
    sm.mu.Lock()
    defer sm.mu.Unlock()
    sm.m[key] = val
}

func (sm *SafeMap) Get(key string) (int, bool) {
    sm.mu.Lock()
    defer sm.mu.Unlock()
    val, ok := sm.m[key]
    return val, ok
}
```

### Fix 2 — sync.Map

The standard library provides `sync.Map`, a built-in concurrent-safe map — but it has a different (less convenient) API:

```go
var sm sync.Map

sm.Store("key", 42)

val, ok := sm.Load("key")
fmt.Println(val, ok)   // 42 true

sm.Delete("key")

sm.Range(func(key, value any) bool {
    fmt.Println(key, value)
    return true   // return false to stop iteration early
})
```

> [!tip] When to use sync.Map vs a mutex-protected map `sync.Map` is optimized for two specific access patterns: when keys are written once and read many times (a cache that rarely changes), or when many goroutines access entirely disjoint sets of keys. For general-purpose concurrent map usage with frequent writes, a regular `map` protected by a `sync.Mutex` is usually simpler, more predictable, and often faster. Don't reach for `sync.Map` by default — only when you specifically have one of these access patterns.

---

## 14. Comparing Maps

Just like slices, maps **cannot** be compared with `==` (except against `nil`):

```go
a := map[string]int{"x": 1}
b := map[string]int{"x": 1}

// fmt.Println(a == b)   // compile error — maps are not comparable
fmt.Println(a == nil)     // valid — checking against nil works
```

### Use reflect.DeepEqual

```go
import "reflect"

a := map[string]int{"x": 1, "y": 2}
b := map[string]int{"y": 2, "x": 1}   // different insertion order — doesn't matter

fmt.Println(reflect.DeepEqual(a, b))   // true — DeepEqual compares contents, not order
```

### Modern alternative — maps.Equal (Go 1.21+)

```go
import "maps"

fmt.Println(maps.Equal(a, b))   // true — purpose-built, faster than reflect.DeepEqual
```

---

## 15. JSON and Maps

### Marshaling a map to JSON

```go
import "encoding/json"

m := map[string]int{"Alice": 30, "Bob": 25}
b, _ := json.Marshal(m)
fmt.Println(string(b))
// {"Alice":30,"Bob":25}
```

> [!info] JSON object keys are always sorted alphabetically Even though Go map iteration order is random, `json.Marshal` specifically sorts map keys alphabetically before encoding, to produce deterministic, reproducible JSON output.

### Unmarshaling unknown JSON into a map

When you don't know the shape of incoming JSON ahead of time, decode into `map[string]any`:

```go
data := []byte(`{"name": "Alice", "age": 30, "active": true}`)

var result map[string]any
json.Unmarshal(data, &result)

fmt.Println(result["name"])     // Alice (string)
fmt.Println(result["age"])      // 30 (float64 — see warning below!)
fmt.Println(result["active"])   // true (bool)
```

> [!warning] JSON numbers decode as float64 in map[string]any Because JSON has no distinction between integers and floats, `encoding/json` always decodes numeric values into `float64` when the destination type is `any`. If you need the value as an `int`, you must explicitly convert it: `int(result["age"].(float64))`.

### Nested JSON into nested maps

```go
data := []byte(`{"user": {"name": "Alice", "scores": {"math": 90}}}`)

var result map[string]any
json.Unmarshal(data, &result)

user := result["user"].(map[string]any)
scores := user["scores"].(map[string]any)
fmt.Println(scores["math"])   // 90
```

---

## 16. Performance Notes

### Pre-allocate with make when the size is known

```go
// Less efficient — map grows and rehashes multiple times
m := map[string]int{}
for i := 0; i < 10000; i++ {
    m[fmt.Sprintf("key%d", i)] = i
}

// More efficient — size hint reduces rehashing
m := make(map[string]int, 10000)
for i := 0; i < 10000; i++ {
    m[fmt.Sprintf("key%d", i)] = i
}
```

### Map lookups are O(1) average case

Unlike a linear search through a slice (O(n)), map key lookups are average constant-time, making maps the right choice whenever you're checking membership or looking up values repeatedly.

```go
// SLOW for repeated lookups — O(n) every check
func containsSlice(s []string, target string) bool {
    for _, v := range s {
        if v == target {
            return true
        }
    }
    return false
}

// FAST for repeated lookups — O(1) average per check
func containsSet(set map[string]struct{}, target string) bool {
    _, ok := set[target]
    return ok
}
```

If you're checking membership against the same collection many times, convert it to a set/map once, rather than linearly scanning a slice on every check.

### ==Struct keys vs pointer keys==

```go
type Point struct{ X, Y int }

// Struct as key — compares by VALUE, two Points with same X,Y are the same key
m1 := map[Point]string{}
m1[Point{1, 2}] = "a"
fmt.Println(m1[Point{1, 2}])   // "a" — found! same value = same key

// Pointer as key — compares by ADDRESS, even identical values are different keys
m2 := map[*Point]string{}
p1 := &Point{1, 2}
p2 := &Point{1, 2}   // different address, even though same values
m2[p1] = "a"
fmt.Println(m2[p2])   // "" — NOT found! different pointer, different key
```

==This distinction matters — choose struct keys when you want "same data = same key," and pointer keys only when you specifically want "same instance = same key."==

---

## 17. Quick Reference Cheatsheet

```go
// ── Declaration & Creation ───────────────────────────────
var m map[string]int             // nil map — read-only safe, writes panic
m := make(map[string]int)        // empty, ready to use
m := make(map[string]int, 100)   // with size hint
m := map[string]int{"a": 1}      // literal

// ── nil map rules ────────────────────────────────────────
m == nil                  // true for declared-but-not-made map
len(m)                    // 0 — safe even on nil
m["key"]                  // zero value — safe even on nil
m["key"] = 1              // PANIC if m is nil

// ── CRUD ─────────────────────────────────────────────────
m["key"] = val             // create or update (same syntax)
val := m["key"]             // read — zero value if missing
val, ok := m["key"]         // comma-ok — distinguishes missing from zero value
delete(m, "key")            // remove — safe no-op if missing

// ── Iteration ────────────────────────────────────────────
for k, v := range m { }     // order is RANDOM, never rely on it
for k := range m { }        // keys only
// delete(m, k) during range IS safe; adding keys during range is NOT

// ── Reference semantics ──────────────────────────────────
m2 := m1                    // copies the REFERENCE — both point to same data
func f(m map[K]V) { }       // mutations inside ARE visible to caller — no pointer needed

// ── Independent copy ─────────────────────────────────────
clone := make(map[string]int, len(m))
for k, v := range m {
    clone[k] = v
}
// or: maps.Clone(m)  — Go 1.21+

// ── Nested maps ──────────────────────────────────────────
if data[outer] == nil {
    data[outer] = make(map[string]int)   // must init inner map first!
}
data[outer][inner] = val

// ── Maps of slices ───────────────────────────────────────
groups[key] = append(groups[key], item)   // works even if key is missing — nil slice append is fine

// ── Counting pattern ─────────────────────────────────────
counts[item]++   // works even on missing key — zero value is 0

// ── Set pattern ───────────────────────────────────────────
set := map[string]struct{}{}
set[item] = struct{}{}        // add
_, ok := set[item]             // check membership
delete(set, item)              // remove

// ── Concurrency ───────────────────────────────────────────
// Plain maps: NOT safe for concurrent read/write — fatal error, not recoverable
var mu sync.Mutex             // protect a regular map with a mutex (general purpose)
var sm sync.Map                // OR use sync.Map (write-once-read-many patterns)

// ── Comparison ────────────────────────────────────────────
// m1 == m2          // compile error — maps not comparable (except to nil)
reflect.DeepEqual(m1, m2)     // works, but slower
maps.Equal(m1, m2)             // Go 1.21+, purpose-built and faster

// ── JSON ──────────────────────────────────────────────────
json.Marshal(m)                          // keys sorted alphabetically in output
json.Unmarshal(data, &map[string]any{})  // numbers decode as float64!
```

---

_Previous: [[Go - Arrays and Slices]] · Next: [[07 - Strings and Runes]]_