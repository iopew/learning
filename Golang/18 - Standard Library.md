# Go — Standard Library

> **Series:** Go Language Fundamentals **Tags:** #go #golang #standard-library #fmt #os #io #time #log #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. fmt — The Printing Family]]
- [[#2. os — The Operating System Door]]
- [[#3. io — The Reader/Writer Contracts]]
- [[#4. bufio — Buffered I/O]]
- [[#5. strings — The Full Reference]]
- [[#6. strconv — Conversions]]
- [[#7. math — Numbers & Constants]]
- [[#8. sort — Ordering Slices]]
- [[#9. time — The Clock]]
- [[#10. log — The Scribe]]
- [[#11. Quick Reference Cheatsheet]]

---

## 1. fmt — The Printing Family

Four members, one family: the **where** differs, the formatting is shared.

```go
fmt.Println("hello", 42, true)      // spaces between operands, newline at end
fmt.Printf("x=%d y=%s\n", 42, "hi") // formatted, NO newline — you add \n
msg := fmt.Sprintf("x=%d", 42)      // returns a string instead of printing
fmt.Fprintf(w, "x=%d", 42)          // writes into any io.Writer
err := fmt.Errorf("bad id %d", 7)   // returns an error
```

- `Print*` → stdout · `Sprintf` → string · `Fprintf` → io.Writer · `Errorf` → error
- You've already used both ends: `fmt.Println` in the prove program, and `fmt.Fprintf(w, ...)` in the hello handler — `http.ResponseWriter` satisfies `io.Writer`, which is *why* Fprintf works there.

**The verbs — the complete table:**

| Verb | Meaning | `42` / `"bread"` |
|---|---|---|
| `%v` | default format | `bread` |
| `%+v` | struct with **field names** | `{ID:1 Description:bread}` |
| `%#v` | Go-syntax representation | `model.Expense{ID:1, Description:"bread"}` |
| `%T` | type name | `string` |
| `%d` | decimal int | `42` |
| `%b` / `%o` / `%x` / `%X` | binary / octal / hex (upper) | `101010` `52` `2a` `2A` |
| `%c` | rune as a character | `A` |
| `%s` / `%q` | string / quoted string | `bread` `"bread"` |
| `%t` | bool | `true` |
| `%f` | fixed decimals | `3.141593` |
| `%e` / `%E` | scientific | `3.141593e+00` |
| `%g` | shortest of %e / %f | `3.14159` |
| `%p` | pointer address | `0xc000010200` |
| `%%` | literal percent | `%` |

**Width & precision:**

```go
fmt.Printf("%5d\n", 42)      // "   42"  pad to width 5
fmt.Printf("%-5d|\n", 42)    // "42   |" left-align
fmt.Printf("%05d\n", 42)     // "00042"  zero-pad
fmt.Printf("%.2f\n", 3.14159)    // "3.14"
fmt.Printf("%8.2f\n", 3.14159)   // "    3.14" width 8, two decimals
```

**fmt talks to your types:** `%v` calls the `String() string` method if the type implements `fmt.Stringer` ([[09 - Structs & Methods]] §Stringer). `%+v` and `%#v` are the debugging pair — your `{3 150000 chicken 2026-08-11 manual}` was `%v`; `%+v` would name every field.

**Errorf and the `%w` verb** — the wrapping bridge to [[11 - Error Handling]]:

```go
err := fmt.Errorf("failed to open %s: %w", path, baseErr)  // %w = wrap
// errors.Is / errors.As can now unwrap it
```

> [!warning] Println inserts spaces between **all** operands and adds a newline; Printf inserts nothing and adds **no** newline. Forgetting the `\n` in Printf is the classic "my output is stuck on one line" bug.

> [!practice] In the prove program change `fmt.Printf("%v\n", e)` to `fmt.Printf("%+v\n", e)` and run — field names appear. Then `%#v`: you get the full Go-syntax literal, copy-pasteable.

---

## 2. os — The Operating System Door

Process, environment, files, streams.

```go
// process
fmt.Println(os.Args)           // ["/path/to/prog", "arg1", "arg2"] — every CLI word

// environment
fmt.Println(os.Getenv("HOME"))         // "" if unset
v, ok := os.LookupEnv("PORT")           // comma-ok: ok=false when unset

// one-shot file I/O (full deep dive: [[21 - File I/O]])
data, err := os.ReadFile("notes.txt")   // whole file → []byte
os.WriteFile("out.txt", data, 0o644)    // []byte → file, with permissions

// streaming handles
f, err := os.Open("notes.txt")          // *os.File for reading
f, err := os.Create("out.txt")          // *os.File for writing (truncates!)

// the three standard streams — every program has them
fmt.Fprintln(os.Stdout, "out")          // stdout
fmt.Fprintln(os.Stderr, "err")          // stderr — errors go here by convention
// os.Stdin + bufio.Scanner → reading what the user types
```

**The `os.Exit` trap — defers do NOT run:**

```go
func main() {
    defer fmt.Println("never printed")
    os.Exit(0)                          // hard stop of the WHOLE process
}
```

`os.Exit` skips every deferred call — no cleanup, no flush, no goodbye. That's exactly why the idiom in main is `log.Fatal(...)`: it prints *then* `os.Exit(1)`s, but you never put `os.Exit` inside a helper — `return` + an error is the normal exit door.

> [!note] `os.Exit` is a process-wide stop from anywhere in the program, not a function return. The idiomatic early exit is `return err`; `os.Exit` belongs only in main (and mostly inside `log.Fatal`).

---

## 3. io — The Reader/Writer Contracts

The two most important interfaces in Go ([[10 - Interfaces]] met them as theory):

```go
type Reader interface { Read(p []byte) (n int, err error) }
type Writer interface { Write(p []byte) (n int, err error) }
```

Anything that can be read from / written to satisfies them: `os.File`, `bytes.Buffer`, `strings.Reader`, network connections — and in your project, `http.ResponseWriter`. One contract, infinite implementations.

**The stream tools:**

```go
n, err := io.Copy(dst, src)       // src → dst until EOF; n = bytes copied
data, err := io.ReadAll(r)        // read EVERYTHING until EOF into []byte
io.Copy(io.Discard, r)            // read and throw away — the "consume" trick
limited := io.LimitReader(r, 1024)  // only the first 1024 bytes pass through
teed := io.TeeReader(r, file)     // reads normally, but ALSO writes a copy into file
```

**The manual read loop** — what `ReadAll` does inside, and what you write when streaming:

```go
buf := make([]byte, 512)
for {
    n, err := r.Read(buf)
    if err == io.EOF { break }        // end of data — the sentinel (note 11)
    if err != nil { /* real error */ }
    process(buf[:n])                  // NEVER buf — only the filled part
}
```

> [!warning] `Read` does **not** guarantee filling the buffer — `n` can be less than `len(buf)`. Always work with `buf[:n]`; using the whole buffer reads garbage.

> [!tip] `io.EOF` is the friendly sentinel error: "I am not broken, I am done." `Read` returning `(0, io.EOF)` simultaneously is the legal end-of-input state.

---

## 4. bufio — Buffered I/O

Raw reads/writes hit the OS per call — slow. `bufio` batches them.

**Reading lines — the Scanner is the king:**

```go
sc := bufio.NewScanner(os.Stdin)
for sc.Scan() {                       // true while a line is available
    fmt.Println(sc.Text())            // the line, without the \n
}
if err := sc.Err(); err != nil { ... } // loop ended broken, not cleanly
```

- Default token = line; **max token 64KB** — longer lines fail with `bufio.ErrTooLong`; fix: `sc.Buffer(make([]byte, 1<<20), 1<<20)`
- `sc.Split(bufio.ScanWords)` — tokenize by words instead of lines

**Reading and writing with buffered handles:**

```go
r := bufio.NewReader(f)
line, err := r.ReadString('\n')       // read up to and including \n

w := bufio.NewWriter(f)
w.WriteString("hello\n")
w.Flush()                             // ← WITHOUT THIS THE DATA NEVER REACHES THE FILE
```

> [!warning] Forgetting `Flush()` is the silent data-loss bug: everything "written" sits in memory. Flush = "push it to the file NOW."

> [!practice] Read a `.txt` file line by line with a Scanner and print each line's length. Then feed it a line longer than 64KB (a 70KB one) — watch `bufio.ErrTooLong` appear — and fix it with `sc.Buffer`.

---

## 5. strings — The Full Reference

The toolbelt. ([[07 - Strings & Runes]] covers string internals and UTF-8; this is every function, grouped.)

**Searching & testing:**

| Function                  | Job                           | Example                              |
| ------------------------- | ----------------------------- | ------------------------------------ |
| `Contains(s, sub)`        | substring present?            | `Contains("bread", "re")` → true     |
| `ContainsAny(s, "aeiou")` | any of these chars?           | → true                               |
| `HasPrefix` / `HasSuffix` | starts / ends with            | `HasPrefix("expense", "exp")` → true |
| `Index(s, sub)`           | first position (−1 if absent) | `Index("bread", "a")` → 3            |
| `LastIndex(s, sub)`       | last position                 | —                                    |
| `Count(s, sub)`           | occurrences (non-overlapping) | `Count("banana", "na")` → 2          |
| `EqualFold(a, b)`         | case-insensitive equality     | `EqualFold("Go", "go")` → true       |

**Splitting & joining:**

| Function | Job | Example |
|---|---|---|
| `Fields(s)` | split on **whitespace** → []string | `Fields("a b\tc")` → `[a b c]` |
| `Split(s, sep)` | split on separator | `Split("a,b,c", ",")` → `[a b c]` |
| `SplitN(s, sep, n)` | at most n pieces | `SplitN("a,b,c", ",", 2)` → `[a b]` |
| `Join(parts, sep)` | the reverse of Split | `Join([]string{"a","b"}, "-")` → `"a-b"` |
| `Cut(s, sep)` | before, after, found — Go 1.18 | `Cut("file.txt", ".")` → `"file"`, `"txt"`, true |

**Replacing & trimming:**

| Function | Job | Example |
|---|---|---|
| `Replace(s, old, new, n)` | first n replacements | `Replace("aaa","a","b",2)` → `"bba"` |
| `ReplaceAll(s, old, new)` | all of them | → `"bbb"` |
| `Repeat(s, n)` | s × n | `Repeat("ab", 3)` → `"ababab"` |
| `ToUpper` / `ToLower` | case | `ToUpper("bread")` → `"BREAD"` |
| `TrimSpace(s)` | strip whitespace off edges | `TrimSpace("  hi \n")` → `"hi"` |
| `Trim(s, cutset)` | strip given chars | `Trim("!!hi!!", "!")` → `"hi"` |
| `TrimPrefix` / `TrimSuffix` | strip exact word | `TrimPrefix("expense.db", "expense")` → `".db"` |
| `Map(f, s)` | apply a func to every rune | `Map(unicode.ToUpper, "hi")` → `"HI"` |
| `NewReplacer` | many replacements at once | — |

**strings.Builder — the efficient concatenation machine** (note 07's gotcha, fixed):

```go
var b strings.Builder
for i := 0; i < 1000; i++ {
    b.WriteString("row ")
    b.WriteString(strconv.Itoa(i))
    b.WriteByte('\n')
}
result := b.String()   // the final string — one allocation
```

> [!warning] `b.String()` does **not** copy — keep writing after taking it and the earlier string changes too. Take it only when done (or `strings.Clone` if you must hold both). And `+=` on strings in a loop is O(n²): each step copies the whole growing string — Builder is the fix.

> [!practice] From `s := "bread 2026-08-12 10000"` produce `"10000|bread|2026-08-12"` using `strings.Fields` + `strings.Join` — the exact shape of form data you'll meet in milestone 2.

---

## 6. strconv — Conversions

Strings ↔ numbers/bools. Every web form hands you strings; every database column wants numbers — this is the bridge (and the plan for `AddExpense`'s amount field).

**string → number:**

```go
n, err := strconv.Atoi("42")              // int; err when not a number
n64, err := strconv.ParseInt("42", 10, 64)   // string, base, bit-size → int64
u64, err := strconv.ParseUint("42", 10, 64)  // unsigned
f, err := strconv.ParseFloat("3.14", 64)     // string, bit-size → float64
b, err := strconv.ParseBool("true")          // accepts 1, t, T, TRUE, true, True...
```

**number → string:**

```go
s := strconv.Itoa(42)                   // "42"
s := strconv.FormatInt(42, 16)          // "2a" — any base
s := strconv.FormatFloat(3.14, 'f', 2, 64)  // "3.14" — format, precision, bits
s := strconv.FormatBool(true)           // "true"
```

**Quoting** (the reverse of `%q`):

```go
strconv.Quote("hi")       // `"hi"` — Go-quoted, escapes included
strconv.Unquote(`"hi"`)   // hi
```

**The error is `*strconv.NumError`** — it carries what failed:

```go
_, err := strconv.Atoi("abc")
// strconv.Atoi: parsing "abc": invalid syntax
// errors.As(err, &ne) → ne.Num == "abc", ne.Func == "Atoi"
```

Two facts worth owning: **base 0 auto-detects** (`ParseInt("0x1F", 0, 64)` = 31, `ParseInt("0b101", 0, 64)` = 5), and `strconv.IntSize` = int's bit width on your machine (64 on modern Macs — why your `Amount int64` fits all your money).

> [!practice] The browser will send amount as `"20000"`. Write the two lines that turn it into `int64` with a guard that surfaces a bad value as an error — you'll paste them into `AddExpense` soon.

---

## 7. math — Numbers & Constants

Float64 math. (For ordering anything else — ints, strings — use the builtin `min`/`max`, [[02 - Operators]].)

```go
// constants
math.Pi, math.E, math.Phi          // 3.14…, 2.71…, 1.61…
math.MaxFloat64                    // the biggest float64
math.SmallestNonzeroFloat64        // the smallest positive one
math.MaxInt, math.MinInt64         // int bounds (Go 1.17+)

// rounding & friends
math.Abs(-3.5)    // 3.5
math.Floor(3.7)   // 3
math.Ceil(3.2)    // 4
math.Round(3.5)   // 4 (half away from zero)
math.Trunc(3.9)   // 3 (toward zero)
math.Mod(7.5, 2)  // 1.5 (float remainder)

// powers & logs
math.Sqrt(9)      // 3
math.Cbrt(27)     // 3
math.Pow(2, 10)   // 1024
math.Exp(1)       // e¹ = e
math.Log(math.E)  // 1 (natural log)
math.Log2(1024)   // 10
math.Log10(100)   // 2

// min/max — floats only here; builtin min/max cover everything since 1.21
math.Min(3.1, 2.9)  // 2.9
math.Max(3.1, 2.9)  // 3.1

// "is it even a number" checks
math.IsNaN(0.0 / 0.0)     // true
math.IsInf(1.0 / 0.0, 1)  // true
```

> [!warning] Never compare floats with `==` (note 02): `math.Sqrt(2)*math.Sqrt(2)` is not exactly 2. Compare with a tolerance: `math.Abs(a-b) < 1e-9`.

> [!note] `math/rand` (and the modern `math/rand/v2`) is a **separate** package — pseudo-random numbers, not math. `rand.IntN(6)` (v2) is your die.

---

## 8. sort — Ordering Slices

Sorts **in place** — the slice you pass gets reordered (mutation, note 05):

```go
ints := []int{3, 1, 2}
sort.Ints(ints)              // [1 2 3] — mutates!

words := []string{"pear", "apple"}
sort.Strings(words)          // [apple pear]

// custom ordering — the workhorse (less = "i before j")
sort.Slice(ints, func(i, j int) bool { return ints[i] > ints[j] })  // descending

// stable — equal elements keep their original order
sort.SliceStable(expenses, func(i, j int) bool {
    return expenses[i].Date < expenses[j].Date   // your Expense struct, by date
})

// binary search: smallest index where the func turns true (list must be sorted!)
i := sort.Search(len(xs), func(i int) bool { return xs[i] >= 5 })

// the interface (note 10's sort.Interface): Len, Less, Swap
sort.Sort(sort.Reverse(sort.StringSlice(words)))  // descending via Reverse wrapper
```

Why *stable* matters: two expenses sharing a date keep insertion order under `SliceStable`; plain `sort.Slice` may swap them.

> [!note] Your store's `List` already returns `ORDER BY date` — the database sorts. `sort.Slice` is for data **already in memory** when you want a different view (by amount, descending) without a second query.

> [!practice] `st.List` your expenses, then build a second slice sorted by `Amount` descending with `sort.Slice`, print both orders, and name which one came from SQL and which from your hand.

---

## 9. time — The Clock

The wall clock, durations, and the layout system.

**Moments & durations:**

```go
now := time.Now()                 // the current moment (wall clock)
t := time.Date(2026, 8, 12, 10, 30, 0, 0, time.UTC)  // construct one by hand
secs := time.Unix(1786500000, 0)  // from Unix epoch seconds

d := time.Second * 5              // Duration IS int64 nanoseconds
d += 250 * time.Millisecond       // 5.25s
time.Sleep(d)                     // actually wait

start := time.Now()
doWork()
elapsed := time.Since(start)      // "how long did it take" — the everyday pattern
remaining := time.Until(deadline) // duration until a future moment
```

**Format & Parse — the magic constant:**

```go
t.Format("2006-01-02")         // "2026-08-12" — THE ISO layout
t.Format("02.01.2006")         // "12.08.2026" — the dd.mm.yyyy you almost used!
t.Format("15:04")              // "10:30" — 24-hour clock
t.Format(time.RFC3339)         // "2026-08-12T10:30:00Z" — JSON API standard

parsed, err := time.Parse("2006-01-02", "2026-08-12")  // string → time.Time
```

> [!warning] The layout string is **not** a format string — it is a literal reference date (`01/02 03:04:05PM '06 -0700`). Use the exact reference numbers; `time.Parse("2026-08-12", ...)` parses nothing.

> [!info] Your project locked ISO dates — that *is* `time.Format("2006-01-02")`. When milestone 3 computes month ranges, this layout is the one word you'll type. The dd.mm.yyyy format we rejected is literally the `"02.01.2006"` layout.

**Timers & tickers — the select citizens from [[14 - Select]]:**

```go
time.After(2 * time.Second)      // <-chan time.Time: fires ONCE after 2s (select timeout!)
time.NewTimer(2 * time.Second)   // *Timer with a C field; timer.Stop() cancels
tk := time.NewTicker(time.Second) // fires every second
for range tk.C { ... }           // one iteration per tick; tk.Stop() to stop
```

**Time zones:**

```go
t.UTC()                                       // convert to UTC
loc, _ := time.LoadLocation("Europe/Tashkent")
t.In(loc)                                     // convert to Tashkent time
time.ParseInLocation(layout, str, loc)        // parse assuming a zone
```

> [!tip] `time.Since` uses the **monotonic clock** underneath, so elapsed time stays correct even if the wall clock jumps (NTP sync, manual changes). That hidden second reading is why `Since` is safe where `now.Sub(now)` arithmetic would lie.

> [!practice] Compute "days between 2026-08-01 and 2026-08-31" with `time.Parse` + `Sub` + `time.Hour`. This exact arithmetic is what milestone 3's avg-per-day needs.

---

## 10. log — The Scribe

Timestamped output to **stderr** by default.

```go
log.Println("server started")                // 2026/08/14 17:20:33 server started
log.Printf("port %d", 8080)
log.SetPrefix("expense-tracker: ")           // prefix every line
log.SetFlags(log.Ldate | log.Ltime | log.Lshortfile)  // + file:line

// custom logger — own prefix, own destination
errLog := log.New(os.Stderr, "ERROR: ", log.LstdFlags)
errLog.Println("boom")

// the three exits
log.Fatal("cannot open db")     // print + os.Exit(1) — DEFERS DO NOT RUN
log.Panic("boom")               // print + panic — defers run, then it unwinds
return err                      // the normal way: nobody dies
```

**The Fatal / panic / return decision** (note 11's deep dive):
- `log.Fatal` — "the program cannot meaningfully continue" *in main*. Your `log.Fatal(http.ListenAndServe(":8080", mux))` is the canonical use: the server loop returns only when it's already dead.
- `panic` — programming errors (index out of range *is* a panic).
- `return err` — everything you can actually handle.

**log/slog — structured logging (Go 1.21+):** logs as key-value pairs, machine-readable:

```go
slog.Info("request", "path", "/expenses", "method", "GET")
// 2026/08/14 17:20:33 INFO request path=/expenses method=GET

h := slog.NewJSONHandler(os.Stdout, nil)     // JSON lines for production
logger := slog.New(h)
logger.Error("db failed", "err", err)
// {"time":"...","level":"ERROR","msg":"db failed","err":"..."}
```

> [!note] `log.Printf` is the debug friend; `slog` is the production friend. When the expense-tracker grows a logging middleware (milestone 6), that's slog's moment.

---

## 11. Quick Reference Cheatsheet

```go
# fmt — printing
fmt.Println(a, b)      # spaces + newline        fmt.Printf(fmt, a)  # NO newline
fmt.Sprintf(fmt, a)    # → string                fmt.Fprintf(w, fmt, a)  # → io.Writer
fmt.Errorf("%w", err)  # wrapped error
verbs: %v %+v %#v %T %d %b %o %x %c %s %q %t %f %e %g %p %%
width: %5d %-5d %05d %.2f %8.2f

# os — process & files
os.Args                  # CLI words
os.Getenv / os.LookupEnv # env (LookupEnv = comma-ok)
os.ReadFile / os.WriteFile(path, data, 0o644)   # one-shot
os.Open / os.Create      # streaming handles     os.Stdin/Stdout/Stderr
os.Exit(n)               # hard exit — defers DON'T run

# io — the contracts
Reader.Read(p []byte) (n, err)   Writer.Write(p []byte) (n, err)
io.Copy(dst, src)  io.ReadAll(r)  io.Discard  io.LimitReader(r, n)  io.TeeReader(r, w)
read loop: n, err := r.Read(buf); err == io.EOF = done; use buf[:n]

# bufio
bufio.NewScanner(r)  sc.Scan() / sc.Text() / sc.Err()   # 64KB token limit
bufio.NewReader(r).ReadString('\n')
bufio.NewWriter(w): WriteString + FLUSH()

# strings (full reference — section 5 table)
Contains HasPrefix Index Count Fields Split Join Cut ReplaceAll Trim TrimSpace
ToUpper EqualFold Map NewReplacer Builder(b.String() does NOT copy)

# strconv
Atoi / Itoa  ParseInt(s, 10, 64)  ParseFloat(s, 64)  ParseBool
FormatInt(n, 16)  FormatFloat(f, 'f', 2, 64)  Quote/Unquote
errors: *strconv.NumError

# math
Abs Sqrt Floor Ceil Round Trunc Mod Pow Exp Log Log2 Log10
Pi E MaxFloat64 MaxInt  IsNaN IsInf
min/max: builtin (1.21+) — math.Min/Max are float-only

# sort — in place!
sort.Ints sort.Strings sort.Slice(xs, less) sort.SliceStable
sort.Search(n, f)  sort.Sort(sort.Reverse(...))
sort.Interface = Len/Less/Swap

# time
time.Now()  time.Date(...)  time.Since(t)  time.Until(t)  time.Sleep(d)
layout: "2006-01-02"  (reference date, NOT a format string)
time.Parse(layout, s)  t.Format(layout)
time.After(d)  time.NewTimer(d)  time.NewTicker(d)  Stop()
time.LoadLocation / t.In(loc)

# log
log.Print/Printf/Println   log.Fatal (exit 1, no defers)   log.Panic (defers run)
log.SetPrefix log.SetFlags log.New(w, prefix, flags)
slog.Info("msg", "key", val)   slog.NewJSONHandler(w, nil)
```

> [!practice] **Project laser.** Look at `cmd/expense/main.go` and answer, from this note only: (1) why can `fmt.Fprintf(w, ...)` write into the HTTP response? (2) why is the `ListenAndServe` line wrapped in `log.Fatal` instead of `fmt.Println` + `os.Exit`? (3) which package will turn the form's `"20000"` into `int64` in `AddExpense`, and which line in this note is the exact call?

---

_Previous: [[17 - Packages & Modules]] · Next: [[19 - net/http]]_