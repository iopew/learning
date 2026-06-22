# Go — Strings & Runes

> **Series:** Go Language Fundamentals **Tags:** #go #golang #strings #runes #unicode #utf8 #programming **Level:** Beginner → Intermediate

---

## Table of Contents

- [[#1. String Internals — Immutable UTF-8 Bytes]]
- [[#2. len() vs Character Count]]
- [[#3. Indexing — Bytes, Not Characters]]
- [[#4. String Literals — Quoted and Raw]]
- [[#5. String Concatenation]]
- [[#6. String Comparison]]
- [[#7. byte vs rune — When to Use Each]]
- [[#8. []byte Conversion — Mutating Strings]]
- [[#9. []rune Conversion — Slicing Unicode Safely]]
- [[#10. range Over a String — Yields Runes]]
- [[#11. The strings Package]]
- [[#12. The strconv Package]]
- [[#13. The unicode Package]]
- [[#14. fmt Verbs for Strings]]
- [[#15. Multiline Strings]]
- [[#16. Performance Gotchas]]
- [[#17. Quick Reference Cheatsheet]]

---

## 1. String Internals — Immutable UTF-8 Bytes

A Go string is, at its core, just a **read-only slice of bytes** — an immutable sequence of bytes that Go's tooling and standard library treat as UTF-8 encoded text.

```go
s := "Hello, 世界"
```

Internally, this is a small struct just like a slice header:

```
type stringHeader struct {
    ptr *byte   // pointer to the first byte
    len int     // number of BYTES (not characters)
}
```

### Immutability

Strings cannot be modified in place. Every "modification" creates a brand new string:

```go
s := "hello"
// s[0] = 'H'   // compile error: cannot assign to s[0]

// The only way to "modify" a string is to build a new one
s = "H" + s[1:]   // creates a new string "Hello", assigns it to s
```

This immutability makes strings safe to pass around freely — sharing a string between goroutines needs no synchronization because nobody can mutate it.

### UTF-8 encoding

Go source files are UTF-8, and string literals are UTF-8 by default. ASCII characters (0–127) are represented as a single byte. Non-ASCII characters use 2–4 bytes:

```
'H'  → 1 byte  (0x48)
'é'  → 2 bytes (0xC3 0xA9)
'世' → 3 bytes (0xE4 0xB8 0x96)
'😊' → 4 bytes (0xF0 0x9F 0x98 0x8A)
```

This is why `len("café") == 5` — the `é` takes 2 bytes, so the string has 5 bytes total even though it visually has 4 characters.

---

## 2. len() vs Character Count

```go
s := "café"

fmt.Println(len(s))            // 5 — number of BYTES
fmt.Println(len([]rune(s)))    // 4 — number of Unicode characters
```

`len()` always counts **bytes**. To count visible characters (Unicode code points, called "runes" in Go), convert to `[]rune` first:

```go
s := "Hello, 世界"
fmt.Println(len(s))            // 13 bytes
fmt.Println(len([]rune(s)))    // 9 characters

// Pure ASCII — bytes and characters coincide
fmt.Println(len("hello"))      // 5 bytes, 5 characters
```

> [!info] "Character" is ambiguous Go uses the term **rune** for a Unicode code point — what a human perceives as "one character." For most Latin-script text these coincide with bytes, but for any non-ASCII language (Arabic, Chinese, Russian, emoji) they don't. Always think in terms of bytes vs runes, not "characters."

---

## 3. Indexing — Bytes, Not Characters

Indexing a string with `s[i]` returns the **byte** at position `i`, not the character:

```go
s := "café"

fmt.Println(s[0])          // 99  — byte value of 'c'
fmt.Println(string(s[0]))  // "c" — fine for ASCII
fmt.Println(s[3])          // 195 — first byte of 'é' (0xC3)
fmt.Println(string(s[3]))  // garbage — half of a 2-byte character!
```

For ASCII-only strings this is fine. For any string that might contain non-ASCII characters, **never index directly** unless you specifically want raw bytes.

### Slicing strings — same problem

```go
s := "café"

fmt.Println(s[:4])            // "caf" + first byte of 'é' — corrupted!
fmt.Println(string([]rune(s)[:4]))   // "café" — correct
```

> [!warning] Direct byte-indexing corrupts multi-byte characters `s[i]` and `s[low:high]` slice by **byte** position. For text that might contain non-ASCII characters, always convert to `[]rune` before indexing or slicing by character position.

---

## 4. String Literals — Quoted and Raw

### Interpreted string literals (double quotes)

Backslash escape sequences are processed:

```go
s := "Hello\nWorld"   // \n becomes an actual newline
s := "Tab:\there"     // \t becomes a tab
s := "Quote: \""      // \" is an escaped double quote
s := "\u4e16\u754c"   // Unicode escape: 世界
```

### Raw string literals (backticks)

No escape processing — what you type is exactly what you get, including newlines:

```go
path := `C:\Users\Alice\Documents`   // backslashes are literal
json := `{
    "name": "Alice",
    "age":  30
}`

regex := `^\d{3}-\d{4}$`   // regex patterns are much cleaner with backticks
```

Raw string literals cannot contain a backtick character — that would end the literal. For everything else (especially multiline text, file paths, regex patterns, SQL queries, JSON templates), backticks are cleaner than escaping.

---

## 5. String Concatenation

### `+` operator — simple but inefficient in loops

```go
greeting := "Hello" + ", " + "World!"
fmt.Println(greeting)   // Hello, World!
```

Every `+` creates a new string allocation. For one or two concatenations this is fine. In a loop it becomes O(n²) — quadratic in the number of concatenations.

### `fmt.Sprintf` — formatted assembly

```go
name := "Alice"
age := 30
s := fmt.Sprintf("Name: %s, Age: %d", name, age)
```

Convenient for mixing types, but has overhead from parsing the format string. Not for tight loops.

### `strings.Builder` — the idiomatic choice for loops

```go
import "strings"

var sb strings.Builder
for i := 0; i < 5; i++ {
    sb.WriteString("item ")
    sb.WriteString(fmt.Sprintf("%d\n", i))
}
result := sb.String()
```

`strings.Builder` maintains a growing byte buffer internally, appending each piece without creating intermediate strings. The final `.String()` call produces the assembled result.

```go
// Common pattern — pre-size if you know the approximate length
var sb strings.Builder
sb.Grow(256)   // pre-allocate ~256 bytes of capacity
for _, s := range items {
    sb.WriteString(s)
    sb.WriteByte(',')
}
```

### `strings.Join` — joining a slice with a separator

```go
parts := []string{"apple", "banana", "cherry"}
result := strings.Join(parts, ", ")
fmt.Println(result)   // apple, banana, cherry
```

`strings.Join` is the most efficient way to join a known slice — it pre-calculates the total length and allocates exactly once.

### `bytes.Buffer` — alternative when working with []byte

```go
import "bytes"

var buf bytes.Buffer
buf.Write([]byte("hello"))
buf.WriteString(" world")
result := buf.String()
```

`bytes.Buffer` is interchangeable with `strings.Builder` for building strings, but is more natural when you're working with `[]byte` values.

---

## 6. String Comparison

Strings are compared **lexicographically** — character by character by Unicode code point value.

```go
fmt.Println("apple" == "apple")   // true
fmt.Println("apple" != "Apple")   // true — case-sensitive!

fmt.Println("apple" < "banana")   // true  — 'a' (97) < 'b' (98)
fmt.Println("banana" < "Apple")   // false — 'b' (98) > 'A' (65)
fmt.Println("abc" < "abd")        // true  — 'c' < 'd' at position 3
fmt.Println("abc" < "abcd")       // true  — "abc" is shorter, exhausts first
```

Comparison is byte-by-byte in Unicode code point order (which is the same as byte order for UTF-8 encoded strings). Uppercase letters have lower code points than lowercase in Unicode (`'A'=65, 'a'=97`), so uppercase sorts before lowercase.

### Case-insensitive comparison

```go
import "strings"

strings.EqualFold("Go", "go")   // true — Unicode case-insensitive equal
strings.EqualFold("Ñoño", "ñoño")   // true — handles non-ASCII correctly
```

`strings.EqualFold` handles Unicode correctly, including characters like `ñ`, `ü`, and `Ö` — use it whenever you need case-insensitive comparison rather than `strings.ToLower(a) == strings.ToLower(b)` (which allocates two new strings unnecessarily).

---

## 7. byte vs rune — When to Use Each

### byte (`uint8`) — raw binary data, ASCII

```go
var b byte = 'A'
fmt.Println(b)          // 65 — the numeric value
fmt.Println(string(b))  // A  — as a string

// byte is an alias for uint8
var u uint8 = 65
fmt.Println(u == b)     // true — they're the same type
```

**Use `byte` / `[]byte` when:**

- Working with raw binary data (file I/O, network protocols, crypto)
- Passing data to I/O functions (`os.File`, `http`, `bufio`) — they all speak `[]byte`
- Processing pure ASCII text where you're certain no non-ASCII characters exist
- Performance-sensitive string manipulation

### rune (`int32`) — Unicode code points

```go
var r rune = '世'
fmt.Printf("%c %d\n", r, r)   // 世 19990

// rune is an alias for int32
var n int32 = 19990
fmt.Println(n == r)   // true — they're the same type
```

**Use `rune` / `[]rune` when:**

- Counting visible characters (not bytes)
- Indexing or slicing text by character position
- Working with any non-ASCII text (Cyrillic, Arabic, CJK, emoji)
- Text processing, parsers, formatters

---

## 8. []byte Conversion — Mutating Strings

Strings are immutable — converting to `[]byte` gives you a **mutable copy** of the bytes:

```go
s := "hello"
b := []byte(s)   // creates a new byte slice, copies the string's bytes

b[0] = 'H'
fmt.Println(string(b))   // "Hello"
fmt.Println(s)           // "hello" — original string untouched
```

The conversion copies — modifying `b` never affects `s`, and modifying `s` (assigning a new string) never affects `b`.

### Common pattern: case conversion manually

```go
b := []byte("hello world")
for i, c := range b {
    if c == ' ' {
        b[i] = '_'   // replace spaces with underscores
    }
}
fmt.Println(string(b))   // "hello_world"
```

### When to use []byte vs strings functions

```go
// strings functions are cleaner for most tasks
result := strings.ReplaceAll("hello world", " ", "_")

// []byte is better when:
// 1. You need to modify multiple positions in one pass
// 2. You're working with binary data that happens to be partly text
// 3. You need to pass data to I/O functions
```

---

## 9. []rune Conversion — Slicing Unicode Safely

Converting to `[]rune` gives you a slice where each element is exactly one Unicode character, regardless of how many bytes it takes:

```go
s := "café"
r := []rune(s)

fmt.Println(len(s))    // 5 — bytes
fmt.Println(len(r))    // 4 — characters
fmt.Println(r[3])      // 233 — code point value of 'é'
fmt.Println(string(r[3]))  // é
```

### Safe slicing by character position

```go
s := "Hello, 世界"

// WRONG — slices by byte, may cut a multi-byte character in half
fmt.Println(s[:9])

// RIGHT — slice by character position
r := []rune(s)
fmt.Println(string(r[:9]))   // "Hello, 世界" — correct
```

### Reversing a string with Unicode

```go
func reverse(s string) string {
    r := []rune(s)
    for i, j := 0, len(r)-1; i < j; i, j = i+1, j-1 {
        r[i], r[j] = r[j], r[i]
    }
    return string(r)
}

fmt.Println(reverse("Hello, 世界"))   // 界世 ,olleH
```

If you tried to reverse by bytes instead, multi-byte characters would become garbled because you'd be reversing their individual bytes rather than treating them as units.

---

## 10. range Over a String — Yields Runes

`range` over a string automatically decodes UTF-8 and yields `(byte_index, rune)` pairs — each `rune` is a complete Unicode code point, never half a character:

```go
for i, ch := range "café" {
    fmt.Printf("index %d: %c (U+%04X)\n", i, ch, ch)
}
// index 0: c (U+0063)
// index 1: a (U+0061)
// index 2: f (U+0066)
// index 3: é (U+00E9)   ← byte index 3, even though é occupies bytes 3 AND 4
```

The `i` value is the **byte** index of where that rune starts — not a sequential character number. This is why the index skips from 3 to 5 after `é` (which is 2 bytes) — but you always receive the complete, valid rune.

```go
// Count characters using range
count := 0
for range "café" {
    count++
}
fmt.Println(count)   // 4 — correct character count
```

### range vs direct byte indexing

```go
s := "café"

// range — SAFE, always gives whole runes
for i, r := range s {
    fmt.Printf("%d: %c\n", i, r)
}

// direct indexing — DANGEROUS for non-ASCII
for i := 0; i < len(s); i++ {
    fmt.Printf("%d: %d\n", i, s[i])   // raw bytes, not characters
}
```

> [!tip] Always use `range` to iterate over strings character by character It's the one built-in mechanism that guarantees you always receive complete Unicode code points, handles UTF-8 decoding automatically, and works correctly for text in any language.

---

## 11. The strings Package

### Searching and checking

```go
import "strings"

s := "Hello, World!"

strings.Contains(s, "World")         // true
strings.ContainsAny(s, "aeiou")      // true — contains any of these chars
strings.ContainsRune(s, '世')         // false
strings.HasPrefix(s, "Hello")        // true
strings.HasSuffix(s, "!")            // true
strings.Count(s, "l")                // 3 — non-overlapping occurrences
strings.Index(s, "World")            // 7 — byte index of first occurrence, -1 if not found
strings.LastIndex(s, "l")            // 10
strings.IndexRune(s, 'W')            // 7
strings.IndexAny(s, "aeiouAEIOU")    // 1 — index of first vowel
```

### Modifying

```go
strings.ToUpper("hello")              // "HELLO"
strings.ToLower("HELLO")              // "hello"
strings.Title("hello world")          // "Hello World" (deprecated — use cases/language package for Unicode)
strings.TrimSpace("  hello  ")        // "hello"
strings.Trim("***hello***", "*")      // "hello" — trims chars in the cutset from both ends
strings.TrimLeft("***hello***", "*")  // "hello***"
strings.TrimRight("***hello***", "*") // "***hello"
strings.TrimPrefix("hello_world", "hello_")  // "world"
strings.TrimSuffix("hello_world", "_world")  // "hello"
strings.TrimFunc("  hello  ", unicode.IsSpace)  // "hello" — trim using a predicate
strings.Replace("aabbcc", "b", "x", 1)         // "aaxbcc" — replace first occurrence
strings.ReplaceAll("aabbcc", "b", "x")          // "aaxxcc" — replace all
strings.Map(unicode.ToUpper, "hello")           // "HELLO" — apply function to each rune
```

### Splitting and joining

```go
strings.Split("a,b,c", ",")          // ["a" "b" "c"] — splits on separator
strings.SplitN("a,b,c", ",", 2)      // ["a" "b,c"] — splits at most N times
strings.SplitAfter("a,b,c", ",")     // ["a," "b," "c"] — keeps the separator
strings.Fields("  foo bar  baz  ")   // ["foo" "bar" "baz"] — splits on whitespace, trims
strings.Join([]string{"a","b","c"}, "-")  // "a-b-c"
strings.Repeat("ab", 3)              // "ababab"
```

### Testing and utility

```go
strings.EqualFold("Go", "go")        // true — case-insensitive equal (Unicode-aware)
strings.NewReader("hello")            // returns an io.Reader — useful for testing
strings.NewReplacer("a", "x", "b", "y").Replace("abc")  // "xyc" — multi-replace efficiently
```

### The Replacer — efficient multi-replacement

`strings.NewReplacer` is far more efficient than calling `strings.Replace` multiple times, as it makes a single pass through the string:

```go
r := strings.NewReplacer(
    "<", "&lt;",
    ">", "&gt;",
    "&", "&amp;",
)
fmt.Println(r.Replace("<b>Hello & World</b>"))
// &lt;b&gt;Hello &amp; World&lt;/b&gt;
```

---

## 12. The strconv Package

`strconv` handles conversions between strings and primitive types.

### int ↔ string

```go
import "strconv"

// int → string
s := strconv.Itoa(42)          // "42"  — "Integer to ASCII"

// string → int
n, err := strconv.Atoi("42")   // 42, nil
n, err = strconv.Atoi("abc")   // 0, error — not a valid integer

// More control with ParseInt
n64, err := strconv.ParseInt("FF", 16, 64)   // 255, nil — base 16, 64-bit
n64, err = strconv.ParseInt("-128", 10, 8)   // -128, nil — base 10, 8-bit (int8 range)

// FormatInt
s = strconv.FormatInt(255, 16)   // "ff" — to hex
s = strconv.FormatInt(42, 2)     // "101010" — to binary
```

### float ↔ string

```go
// float → string
s := strconv.FormatFloat(3.14159, 'f', 2, 64)   // "3.14" — format 'f', 2 decimal places, float64
//                                 ↑   ↑  ↑
//                              format  prec  bitsize

// Format options:
// 'f' — decimal (3.14)
// 'e' — scientific (3.14e+00)
// 'g' — shortest representation

// string → float
f, err := strconv.ParseFloat("3.14", 64)   // 3.14, nil
f, err = strconv.ParseFloat("abc", 64)     // 0, error
```

### bool ↔ string

```go
// bool → string
strconv.FormatBool(true)   // "true"
strconv.FormatBool(false)  // "false"

// string → bool
b, err := strconv.ParseBool("true")    // true, nil
b, err = strconv.ParseBool("1")        // true, nil
b, err = strconv.ParseBool("TRUE")     // true, nil
b, err = strconv.ParseBool("yes")      // false, error — not a valid bool string
// valid: "1", "t", "T", "TRUE", "true", "True", "0", "f", "F", "FALSE", "false", "False"
```

### Quote and Unquote — for debugging and output

```go
s := "hello\nworld"
fmt.Println(strconv.Quote(s))         // "\"hello\\nworld\"" — safe quoted representation
fmt.Println(strconv.QuoteToASCII("世界"))  // "\"\\u4e16\\u754c\"" — non-ASCII as escapes

unquoted, err := strconv.Unquote(`"hello\nworld"`)
fmt.Println(unquoted)   // hello
                        // world
```

### The critical gotcha — string(int) is NOT strconv.Itoa

```go
fmt.Println(string(65))        // "A"  ← the Unicode character at code point 65, NOT "65"!
fmt.Println(strconv.Itoa(65))  // "65" ← the decimal string representation of 65
```

`string(n)` converts an integer to the Unicode character with that code point. `strconv.Itoa(n)` converts an integer to its decimal string. These are completely different operations — don't confuse them.

---

## 13. The unicode Package

The `unicode` package provides functions to classify and convert individual runes:

### Classification

```go
import "unicode"

unicode.IsLetter('A')    // true — any Unicode letter
unicode.IsLetter('1')    // false
unicode.IsLetter('世')   // true — CJK characters are letters too

unicode.IsDigit('5')     // true — decimal digit
unicode.IsDigit('A')     // false

unicode.IsSpace(' ')     // true
unicode.IsSpace('\t')    // true — tab
unicode.IsSpace('\n')    // true — newline
unicode.IsSpace('a')     // false

unicode.IsUpper('A')     // true
unicode.IsLower('a')     // true
unicode.IsPunct('.')     // true — punctuation
unicode.IsNumber('²')    // true — includes ², ½ etc., broader than IsDigit
```

### Conversion

```go
unicode.ToUpper('a')     // 'A'
unicode.ToLower('A')     // 'a'
unicode.ToTitle('a')     // 'A' — title case (differs from upper for some Unicode chars)
```

### Using with strings functions

```go
// strings.TrimFunc with unicode predicates
s := "  Hello World  "
clean := strings.TrimFunc(s, unicode.IsSpace)
fmt.Println(clean)   // "Hello World"

// strings.Map with unicode conversion
upper := strings.Map(unicode.ToUpper, "hello, 世界")
fmt.Println(upper)   // "HELLO, 世界"

// strings.IndexFunc — find first matching rune
s = "abc123"
idx := strings.IndexFunc(s, unicode.IsDigit)
fmt.Println(idx)   // 3 — byte index of first digit
```

---

## 14. fmt Verbs for Strings

```go
s := "Hello"
b := byte('A')

fmt.Printf("%s\n", s)      // Hello          — plain string, no quotes
fmt.Printf("%q\n", s)      // "Hello"         — quoted string, escape special chars
fmt.Printf("%v\n", s)      // Hello           — default format (same as %s for strings)
fmt.Printf("%T\n", s)      // string          — type name

fmt.Printf("%d\n", b)      // 65              — byte as decimal integer
fmt.Printf("%c\n", b)      // A               — byte/rune as Unicode character
fmt.Printf("%x\n", b)      // 41              — byte as hex
fmt.Printf("%b\n", b)      // 1000001         — byte as binary
fmt.Printf("%U\n", '世')   // U+4E16          — Unicode code point format

fmt.Printf("%q\n", '世')   // '世'             — rune as quoted character literal
```

### %q is particularly useful for debugging

```go
s := "hello\nworld"
fmt.Println(s)        // hello
                      // world  (the \n is a real newline)
fmt.Printf("%q\n", s) // "hello\nworld"  (shows escape sequences explicitly)
```

### Formatting a []byte as a string

```go
b := []byte{72, 101, 108, 108, 111}
fmt.Printf("%s\n", b)   // Hello — []byte prints as a string with %s
fmt.Printf("%v\n", b)   // [72 101 108 108 111] — prints as slice of integers
```

---

## 15. Multiline Strings

### Raw string literals — the usual choice

```go
query := `
    SELECT *
    FROM users
    WHERE active = true
    ORDER BY name
`

html := `
<!DOCTYPE html>
<html>
    <body>Hello</body>
</html>
`
```

Leading whitespace is included literally — if that's a problem, use `strings.TrimSpace` or `strings.Dedent` (external library).

### Interpreted string with explicit newlines

```go
s := "line one\n" +
     "line two\n" +
     "line three\n"
```

### Using fmt.Sprintf for templated multiline

```go
name := "Alice"
email := "alice@example.com"

body := fmt.Sprintf(`
Dear %s,

Your account (%s) has been activated.

Regards,
The Team
`, name, email)
```

---

## 16. Performance Gotchas

### Gotcha 1 — string concatenation in a loop is O(n²)

```go
// BAD — creates a new string on EVERY iteration
result := ""
for i := 0; i < 10000; i++ {
    result += "x"   // allocates a new string, copies everything each time
}

// GOOD — use strings.Builder
var sb strings.Builder
sb.Grow(10000)   // pre-allocate if you know the size
for i := 0; i < 10000; i++ {
    sb.WriteByte('x')
}
result := sb.String()
```

### Gotcha 2 — unnecessary []byte or []rune conversions

Every conversion between `string` and `[]byte` or `[]rune` copies the data — don't convert repeatedly in tight loops.

```go
s := "hello world"

// BAD — converts to []byte 10 times
for i := 0; i < 10; i++ {
    b := []byte(s)
    process(b)
}

// GOOD — convert once outside the loop
b := []byte(s)
for i := 0; i < 10; i++ {
    process(b)
}
```

### Gotcha 3 — strings.ToLower for comparison allocates

```go
// BAD — allocates two new strings
if strings.ToLower(a) == strings.ToLower(b) { }

// GOOD — zero allocation case-insensitive comparison
if strings.EqualFold(a, b) { }
```

### Gotcha 4 — building a large string with fmt.Sprintf in a loop

```go
// BAD — fmt.Sprintf parses the format string every call
var parts []string
for _, item := range items {
    parts = append(parts, fmt.Sprintf("%s=%d", item.Key, item.Val))
}
result := strings.Join(parts, "&")

// GOOD — use strings.Builder directly
var sb strings.Builder
for i, item := range items {
    if i > 0 {
        sb.WriteByte('&')
    }
    sb.WriteString(item.Key)
    sb.WriteByte('=')
    sb.WriteString(strconv.Itoa(item.Val))
}
result := sb.String()
```

### Gotcha 5 — ranging over a string to count characters is slow for large strings

```go
// Slower — range decodes UTF-8 character by character
count := 0
for range s { count++ }

// Faster — convert once and use len
count := len([]rune(s))

// Fastest — use utf8.RuneCountInString, no allocation
import "unicode/utf8"
count := utf8.RuneCountInString(s)
```

### The compiler optimization — string ↔ []byte in range/map

The Go compiler is smart enough to eliminate the copy in certain common patterns:

```go
// These do NOT actually allocate — compiler optimizes away the conversion
for i, b := range []byte(s) { }         // optimized
m[string(b)] = v                         // optimized if b is []byte
if string(b) == "hello" { }              // optimized
```

Don't add manual caching for these specific patterns — the compiler already handles them.

---

## 17. Quick Reference Cheatsheet

```go
// ── String basics ────────────────────────────────────────
len(s)                     // number of BYTES, not characters
len([]rune(s))             // number of Unicode characters
s[i]                       // byte at position i — NOT the ith character!
s[low:high]                // byte slice — unsafe for non-ASCII text
string([]rune(s)[low:high])  // safe character-position slicing

// ── Literals ─────────────────────────────────────────────
s := "hello\nworld"        // interpreted — \n is a real newline
s := `hello\nworld`        // raw — \n is literally backslash-n

// ── Concatenation ────────────────────────────────────────
s := "a" + "b"             // simple, fine for 1-2 joins
s := fmt.Sprintf(...)      // formatted assembly
var sb strings.Builder
sb.WriteString(...)
s := sb.String()            // efficient for loops
s := strings.Join(parts, sep)  // join a slice

// ── Comparison ───────────────────────────────────────────
s1 == s2                   // exact equality, case-sensitive
strings.EqualFold(s1, s2)  // case-insensitive, no allocation

// ── byte and rune ────────────────────────────────────────
b := []byte(s)             // mutable copy of bytes
s = string(b)              // back to string
r := []rune(s)             // slice of Unicode code points
s = string(r)              // back to string
for i, ch := range s { }   // always safe — yields (byte_index, rune)

// ── strings package ──────────────────────────────────────
strings.Contains(s, sub)
strings.HasPrefix(s, prefix)
strings.HasSuffix(s, suffix)
strings.Index(s, sub)            // -1 if not found
strings.Count(s, sub)
strings.ToUpper(s)
strings.ToLower(s)
strings.TrimSpace(s)
strings.Trim(s, cutset)
strings.TrimPrefix(s, prefix)
strings.TrimSuffix(s, suffix)
strings.TrimFunc(s, unicode.IsSpace)
strings.Replace(s, old, new, n)  // n=-1 for all
strings.ReplaceAll(s, old, new)
strings.Split(s, sep)
strings.Fields(s)                // split on whitespace
strings.Join(parts, sep)
strings.EqualFold(a, b)          // case-insensitive
strings.Map(fn, s)               // apply fn to each rune
strings.NewReplacer(pairs...).Replace(s)  // multi-replace in one pass

// ── strconv package ──────────────────────────────────────
strconv.Itoa(n)                  // int → "42"
strconv.Atoi(s)                  // "42" → 42, error
strconv.FormatFloat(f, 'f', 2, 64)
strconv.ParseFloat(s, 64)
strconv.FormatBool(b)
strconv.ParseBool(s)
strconv.Quote(s)                 // adds Go-syntax quoting
strconv.Unquote(s)
// string(65) == "A"  ← NOT "65"! Use strconv.Itoa(65) for "65"

// ── unicode package ──────────────────────────────────────
unicode.IsLetter(r)
unicode.IsDigit(r)
unicode.IsSpace(r)
unicode.IsUpper(r)
unicode.IsLower(r)
unicode.ToUpper(r)
unicode.ToLower(r)

// ── fmt verbs ────────────────────────────────────────────
%s   plain string
%q   quoted string — "hello\nworld"
%v   default format
%T   type name
%c   rune as character
%d   byte/int as decimal
%x   as hex
%U   Unicode code point  U+0041

// ── performance rules ────────────────────────────────────
// loops: use strings.Builder, not +=
// comparison: strings.EqualFold, not strings.ToLower(...) ==
// rune count: utf8.RuneCountInString(s), not len([]rune(s))
// convert once outside loops, not inside
```

---

_Previous: [[Go - Maps]] · Next: [[Go - Pointers]]_