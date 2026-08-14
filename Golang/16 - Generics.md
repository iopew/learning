# Go — Generics

> **Series:** Go Language Fundamentals **Tags:** #go #golang #generics #type-parameters #constraints #programming **Level:** Intermediate

---

## Table of Contents

- [[#1. Recap — What You Already Know]]
- [[#2. Generic Types (structs with type params)]]
- [[#3. Methods on Generic Types]]
- [[#4. Type Inference Deep + Explicit Instantiation]]
- [[#5. Generic Interfaces (constraints as interfaces)]]
- [[#6. The Constraints Ecosystem — cmp, slices, maps]]
- [[#7. Real-World Generic Utilities]]
- [[#8. Generics vs Interfaces vs any]]
- [[#9. Performance — How Generics Compile]]
- [[#10. Limitations]]
- [[#11. Common Gotchas]]
- [[#12. Quick Reference Cheatsheet]]

---

## 1. Recap — What You Already Know

[[04 - Functions]] §12 covered **generic functions**: the `[T]` syntax, constraints, and the full extent of what a type parameter can require:

| Kind | Example | What it allows |
|---|---|---|
| `any` | `[T any]` | Anything at all |
| `comparable` | `[T comparable]` | `==`, `!=` — usable as map key |
| `cmp.Ordered` | `[T cmp.Ordered]` | `<`, `<=`, `>`, `>=` |
| Union | `int \| float64` | Exactly these types |
| Underlying (`~`) | `~int \| ~float64` | These types or anything based on them |
| Method requirement | `interface { String() string }` | Must implement these methods |
| Multiple params | `[T, U any]` | Independent types, often linked by a function |
| Linked container | `[S ~[]E, E any]` | A slice type and its element type together |

```go
func Filter[T any](items []T, predicate func(T) bool) []T { ... }   // from §12.14
```

> [!note] **What this note adds.** Functions §12 was about *functions only*. This note goes further: generic **types** (structs that carry type params), **methods**, **interfaces as constraints**, the stdlib `cmp`/`slices`/`maps` ecosystem, real-world utilities, when generics are the right tool (and when they are not), how they compile, and their hard limits.

---

## 2. Generic Types (structs with type params)

A struct can have type parameters — the struct becomes a **type factory**:

```go
type Box[T any] struct {
    Value T
}

func main() {
    intBox := Box[int]{Value: 42}
    strBox := Box[string]{Value: "hello"}

    fmt.Println(intBox.Value)   // 42
    fmt.Println(strBox.Value)   // hello
}
```

**Instantiation:** `Box` alone is not a type — you must write `Box[int]`, `Box[string]`, etc. These are fully separate types at run time: `Box[int]` and `Box[string]` share zero memory, zero methods.

```go
var b Box[int]          // OK — zero value: b.Value == 0
b2 := Box[int]{}        // OK
bad := Box{}            // COMPILE ERROR: cannot use generic type Box[T any] without instantiation
```

**Multiple type params — the classic `Pair`:**

```go
type Pair[K comparable, V any] struct {
    Key   K
    Value V
}

func main() {
    p := Pair[string, int]{Key: "age", Value: 30}
    fmt.Println(p)   // {age 30}
}
```

`K comparable` lets `Pair` be used as a map key later — the constraint travels with the type.

> [!tip] **Parallel with functions.** Everything from Functions §12 about *how constraints work* (unions, `~`, `comparable`, `cmp.Ordered`) applies identically to struct type params. Only the syntax position changes: `func F[T any]` → `type Box[T any]`.

---

## 3. Methods on Generic Types

Methods **reuse the type params declared on the receiver** — you do not repeat them:

```go
type Stack[T any] struct {
    items []T
}

func (s *Stack[T]) Push(item T) {
    s.items = append(s.items, item)
}

func (s *Stack[T]) Pop() (T, bool) {
    if len(s.items) == 0 {
        var zero T              // the zero-value idiom inside generics
        return zero, false
    }
    top := s.items[len(s.items)-1]
    s.items = s.items[:len(s.items)-1]
    return top, true
}
```

**The receiver must be instantiated too:** `*Stack[T]`, never `*Stack`.

**You may even specialize methods per concrete type:**

```go
func (s *Stack[int]) Sum() int {
    total := 0
    for _, v := range s.items {
        total += v
    }
    return total
}
```

`Stack[string]` doesn't get `Sum`; `Stack[int]` does. This is allowed and occasionally exactly what you want.

> [!warning] **Methods cannot declare NEW type parameters.** This is a hard rule and the #1 generics frustration:
>
> ```go
> func (s *Stack[T]) Convert[U any]() []U { ... }   // COMPILE ERROR:
> // "methods cannot have type parameters"
> ```
>
> Workaround: make it a free function instead:
>
> ```go
> func ConvertStack[T, U any](s *Stack[T], f func(T) U) []U { ... }
> ```

> [!practice] **Practice: the generic Stack.** Write `Stack[T]` with `Push`, `Pop`, and `Peek` (top without removing). Then instantiate `Stack[int]` and `Stack[string]` in one program — Push ints and strings, pop them back, verify order. Add a `Sum()` method after — does it compile on `Stack[string]`?

---

## 4. Type Inference Deep + Explicit Instantiation

Inference (Functions §12.3) usually just works — the compiler deduces `T` from the arguments:

```go
evens := Filter([]int{1, 2, 3}, func(n int) bool { return n%2 == 0 })
// T inferred = int — you never wrote Filter[int]
```

**When inference FAILS — you must instantiate explicitly:**

**Case A: the type appears only in the return.**
```go
func New[T any]() *T { return new(T) }

p := New[int]()        // explicit — nothing in the args to infer from
// p := New()          // COMPILE ERROR: cannot infer T
```

**Case B: two type params, only one inferrable.**
```go
func MakePair[K comparable, V any](k K, v V) Pair[K, V] {
    return Pair[K, V]{Key: k, Value: v}
}

p := MakePair("name", 30)     // fine — both inferred from args
// need explicit when relationship is unclear:
p2 := MakePair[string, any]("name", 30)
```

**Case C: generic function used as a value.**
```go
var f func(int) bool = Filter[int]   // explicit instantiation required
// var f = Filter                  // ERROR: cannot use generic function without instantiation
```

**Mixed instantiation** — you may also think of `Pair[string, int]{}` as "literal inference by hand".

> [!tip] When the compiler complains "cannot infer T", the fix is always the same: add the explicit `[...]`. The compiler is telling you there's no source of information — so provide it.

---

## 5. Generic Interfaces (constraints as interfaces)

A constraint IS an interface. You can define **named constraints** to reuse across functions and types:

```go
type Number interface {
    ~int | ~int8 | ~int16 | ~int32 | ~int64 |
    ~uint | ~uint8 | ~uint16 | ~uint32 | ~uint64 |
    ~float32 | ~float64
}

func Sum[T Number](nums []T) T {
    var total T
    for _, n := range nums {
        total += n
    }
    return total
}
```

Now `Sum` works on `[]int`, `[]float64`, and any custom named type like `type Celsius float64`.

**Two kinds of interface element, two purposes:**

| Interface element                 | Restricts                                             |
| --------------------------------- | ----------------------------------------------------- |
| Methods: `String() string`        | Values must implement the methods (runtime dispatch)  |
| Type set: `~int \| ~string`       | Values must be one of the listed types (compile-time) |
| Both: `{ ~int; String() string }` | Must be an int-based type AND implement the methods   |

**Type-set interfaces are ordinary values too:**

```go
var n interface{ ~int | ~float64 } = 5
// n = "str"          // ERROR: string not in type set
```

This works because a constraint is just an interface whose type set you've narrowed.

> [!note] `comparable` is a builtin predeclared interface — that's why `map[K comparable]V` and `Contains[T comparable]` are legal without importing anything.

---

## 6. The Constraints Ecosystem — cmp, slices, maps

Go 1.21 finally shipped **generic standard library** — you should reach for these before writing your own:

**`cmp` — the minimalist Ordered toolbox (stdlib, Go 1.21+):**

```go
import "cmp"

func Min[T cmp.Ordered](a, b T) T {
    return cmp.Min(a, b)          // stdlib already has it!
}
// cmp.Ordered = ~int | ~uint | ~float | ~string
// cmp.Compare(a, b) → -1, 0, 1    — works on any Ordered
// cmp.Less(a, b) → a < b
```

**`slices` — generic slice utilities (stdlib):**

```go
import "slices"

slices.Sort(nums)                    // sorts in place (any Ordered)
slices.SortFunc(users, byName)       // custom comparison
slices.Contains(nums, 42)
slices.Index(nums, 42)
slices.Clone(nums)                   // copy
slices.Delete(s, i, j)
```

**`maps` — generic map utilities (stdlib):**

```go
import "maps"

keys := maps.Keys(m)         // all keys (random order, like range)
values := maps.Values(m)
copy := maps.Clone(m)
maps.Copy(dst, src)          // dst gets all src entries
```

> [!warning] **Legacy: `golang.org/x/exp/constraints`.** Older tutorials use `constraints.Ordered` from the experimental x/exp module. It predates the stdlib and requires adding a dependency. Don't use it in new code — `cmp.Ordered` is the same thing, built in. (You'll still see it in older code and must be able to read it.)

> [!practice] **Practice: stdlib first.** Given `m := map[string]int{"b": 2, "a": 1, "c": 3}`, write a program that prints the keys **sorted** using only `maps.Keys` + `slices.Sort`. Then do it again with values sorted by value. No custom generic functions needed — that's the point.

---

## 7. Real-World Generic Utilities

The bread-and-butter generic functions used across codebases. `Filter` already exists in Functions §12.14 — here are its siblings:

```go
// Map — transform every element
func Map[T, U any](items []T, f func(T) U) []U {
    out := make([]U, len(items))
    for i, v := range items {
        out[i] = f(v)
    }
    return out
}

// Reduce — fold the slice into one value
func Reduce[T, U any](items []T, init U, f func(U, T) U) U {
    acc := init
    for _, v := range items {
        acc = f(acc, v)
    }
    return acc
}

// Contains — membership check
func Contains[T comparable](items []T, want T) bool {
    for _, v := range items {
        if v == want {
            return true
        }
    }
    return false
}

// Keys / Values — map views
func Keys[K comparable, V any](m map[K]V) []K {
    keys := make([]K, 0, len(m))
    for k := range m {
        keys = append(keys, k)
    }
    return keys
}

func Values[K comparable, V any](m map[K]V) []V {
    vals := make([]V, 0, len(m))
    for _, v := range m {
        vals = append(vals, v)
    }
    return vals
}

// Zip — pair two slices element-wise
func Zip[T, U any](a []T, b []U) []struct{ A T; B U } {
    n := min(len(a), len(b))
    out := make([]struct{ A T; B U }, n)
    for i := range n {
        out[i] = struct{ A T; B U }{a[i], b[i]}
    }
    return out
}
```

A single program using all of them:

```go
nums := []int{1, 2, 3, 4, 5}

sq := Map(nums, func(n int) int { return n * n })          // [1 4 9 16 25]
sum := Reduce(nums, 0, func(acc, n int) int { return acc + n })  // 15
has3 := Contains(nums, 3)                                   // true
ms := map[string]int{"a": 1, "b": 2}
ks := Keys(ms)                                              // ["a" "b"]
pairs := Zip([]string{"x", "y"}, []int{1, 2})               // [{x 1} {y 2}]
```

> [!note] `min` in the Zip example is the **builtin** `min` (Go 1.21+) — itself a generic function! `min(len(a), len(b))` just works across numeric types.

---

## 8. Generics vs Interfaces vs any

Three tools for "one function, many types" — they are NOT interchangeable:

| | Generics | Interfaces | `any` |
|---|---|---|---|
| Dispatch time | **Compile time** | Runtime (vtable) | Runtime (assert) |
| Type safety | Full — compiler checks | Contract methods only | None until asserted |
| What unifies | Types with a shared op | Types with a shared behavior | Everything blindly |
| Best for | Containers, algorithms, math | Polymorphic behavior (io.Reader-like) | JSON-ish "unknown shape" data |
| Cost | Binary size, compile time | One indirection per call | Panics if assertion wrong |

**The decision rule:**

1. **Generics** when the code is *the same* for any type and the only thing that varies is the type itself: `Sum`, `Map`, `Stack`, `Set`. You want compile-time safety and zero runtime dispatch.
2. **Interfaces** when *behavior* varies per type and you want to swap implementations: `io.Reader`, `fmt.Stringer`, a `Store` interface with Disk/Redis implementations. Runtime polymorphism is the point.
3. **`any`** only when you truly don't know the shape ahead of time — typically data coming from outside (JSON payloads), decoded into a structure you then examine explicitly.

**The Goldilocks example — "max of two":**

```go
// Generics — safe, no dispatch:
func Max[T cmp.Ordered](a, b T) T { return cmp.Max(a, b) }

// interface — why? You already paid for N x runtime dispatch and lost safety:
func MaxI(a, b any) any { ... }   // assertions, checks, slow, unclear return

// Interfaces win when behavior differs per type:
type Sizer interface { Size() int }   // different impl per type — correct use of interface
```

> [!tip] **Go's own standard library barely uses generics** (only `slices`, `maps`, `cmp` and a few others). That's a hint: generics are for **library/utility code**, not everyday application glue. "If you're unsure, concrete types first; refactor to generics when duplication actually hurts."
>
> And note: your `atomic.Pointer[T]` and `sync.Map` already used generics this session (note 15) — that's exactly the "container utility" case.

---

## 9. Performance — How Generics Compile

Go does NOT implement generics via dynamic dispatch (virtual methods) — there's no vtable dance at runtime:

- For each **concrete instantiation** (e.g., `Stack[int]`, `Stack[string]`), the compiler generates **dedicated code** — "monomorphization" (technically with shape-sharing: identical shapes like `int` and `uint64` reuse one copy).
- Result: `Stack[int]`'s `Push` is as fast as if you had hand-written a `StackInt` type with no generics involved. Zero indirection.
- **Costs are at build time, not run time:** larger binaries (every instantiation is real code), slower compilation. A 100-type-per-generic program pays, a 2-type program doesn't.

**Gotchas beyond compile time:**

- Values of huge types (e.g., a generic `Box[MyHugeStruct]`) get stack-copied in and out — same as any value copy, not a generics-specific penalty.
- Dictionary-passing exists for the rare generic-over-interface cases — invisible to you, still fast.

> [!note] "Generics are slow" is false in Go. Generics compile *to* the per-type code you'd write by hand. If it's slow, the algorithm is slow — not the generics.

---

## 10. Limitations

The honest list of what generics **cannot** do:

1. **No new type params on methods** — the §3 rule. Methods reuse receiver params only. Workaround: free functions.

2. **No runtime type creation.** Generics are a compile-time affair. You cannot take a type discovered via reflection and say "instantiate `Box<that>`" — there's nothing to instantiate at runtime. Generic code = code written *before* you knew the types.

3. **You can only do what the constraint allows.** `T + T` requires an `~int | ~float`-ish constraint; `T == T` requires `T comparable`; indexing `T[i]` isn't possible (no combined slice constraint on a single param — that's what `[S ~[]E, E any]` exists for).

4. **No composite literals of `T`.** You cannot write `T{...}` inside a generic function. Settle for `var zero T` or `*new(T)`:

   ```go
   func zeroValue[T any]() T {
       // return T{}       // ERROR
       var z T             // OK
       return z
   }
   ```

5. **Limited use in type switches.** You can't `switch v.(type)` on a `T`-typed value the way you would on an interface — generics pick the type at compile time, so runtime type-switching doesn't apply (except when `T` itself is constrained to be an interface — an advanced corner).

6. **Generic aliases are very new** (Go 1.24+). Expect to see them rarely; normal `type` declarations remain the default.

---

## 11. Common Gotchas

| Mistake | Why it fails | Fix |
|---|---|---|
| `if a == b` with `[T any]` | `any` doesn't allow `==` | `[T comparable]` |
| `Box{}` instead of `Box[int]{}` | generic type used without instantiation | write the `[...]` |
| `New()` where `T` only in return | nothing to infer from | `New[int]()` |
| Copy pasting the constraint everywhere instead of naming it | duplication, errors drift | `type Number interface { ... }` |
| Writing your own `Min`/`Sort`/`Contains` | stdlib has them since 1.21 | use `cmp`, `slices`, `maps` |
| `interface{}` in a generic signature | defeats the point of generics | narrow the constraint (`comparable`, union, ...) |
| Method with new type params | hard language rule | refactor to a free function |

---

## 12. Quick Reference Cheatsheet

```go
// Generic function
func F[T any](x T) T { return x }

// Constraints
[T any]                        // anything
[T comparable]                 // ==, !=, map key
[T cmp.Ordered]                // <, >, cmp.Min, slices.Sort
[T ~int | ~float64]            // union with underlying
type Number interface { ~int | ~float64 }   // named constraint

// Generic type + methods
type Box[T any] struct { Value T }
b := Box[int]{Value: 42}
func (b *Box[T]) Get() T { return b.Value }   // methods reuse [T]

// Explicit instantiation (inference failed)
p := New[int]()
var f func(int) bool = Filter[int]

// Stdlib generics (Go 1.21+)
cmp.Min/Max/Compare/Less(cmp.Ordered)
slices.Sort / SortFunc / Contains / Index / Clone / Delete
maps.Keys / Values / Clone / Copy

// Generic utilities
// Map, Filter, Reduce, Contains, Keys, Values, Zip — see §7

// Zero value of T
var zero T   // T{} is illegal
```

> [!practice] **Practice: analyze real code.** Open `atomic.Pointer[T]` from note 15's §8 — that's a stdlib generic type. Trace: what's `T`'s constraint (`any`), how does `Store`/`Load` use it, and why is `sync.Pointer[T]` fine with `any` while a `Stack[T]` might want `comparable`? Every generic utility you now know how to write exists for a reason.

---

_Previous: [[15 - Sync Primitives]] · Next: [[17 - Packages & Modules]]_