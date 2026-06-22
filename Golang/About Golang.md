# Go (Golang)

## What is it?

Go is a statically typed, compiled language built at **Google in 2009** by Robert Griesemer, Rob Pike, and Ken Thompson. Designed to fix slow compiles, verbose code, and poor concurrency in existing languages.

---

## Why use it?

| Strength          | Detail                                                     |
| ----------------- | ---------------------------------------------------------- |
| Fast compilation  | Near-instant builds even for large codebases               |
| Goroutines        | Cheap, lightweight concurrency (not OS threads)            |
| Single binary     | Compiles to one self-contained executable — easy to deploy |
| Strong stdlib     | HTTP, JSON, testing, file I/O — no extra packages needed   |
| Simple syntax     | Small spec, no inheritance, quick to learn                 |
| Garbage collected | No manual memory management                                |

---

## Where it's used

- API servers & microservices
- CLI tools
- DevOps / infrastructure tooling
- Bots and background services

**Real-world examples:** Docker, Kubernetes, Terraform, Prometheus, CockroachDB, Hugo

---

## Weaknesses

- Verbose error handling (`if err != nil` everywhere)
- Generics only added in 1.18 — still maturing
- Not ideal for CPU-bound number crunching (vs Rust/C)
- Smaller ecosystem than Python/JS for ML

---

## Key Concepts

```text
Go/
├── 00 - Overview.md
│     What Go is, why it exists, key design philosophy,
│     compilation, toolchain (go run, go build, go fmt,
│     go vet, go mod), workspace layout, GOPATH vs modules
│
├── 01 - Variables & Types.md              ✅ DONE
│     var, :=, const, iota, zero values, all basic types
│     (bool, int variants, float, complex, string, byte, rune),
│     type inference, type conversions (strconv), composite
│     types overview (arrays, slices, maps, structs), pointers
│     overview, blank identifier, scope & shadowing
│
├── 02 - Operators.md                      ✅ DONE
│     arithmetic, assignment, compound assignment, comparison,
│     logical (short-circuit), bitwise (&, |, ^, &^, <<, >>),
│     address & pointer operators, precedence table,
│     no ternary, gotchas (overflow, float ==, strings.Builder)
│
├── 03 - Control Flow.md                   ✅ DONE
│     if/else, if with initialiser, switch (all variants,
│     fallthrough, type switch), for (all 3 forms), range
│     (all types, copy gotcha, Go 1.22 int range), break,
│     continue, labels, goto, defer (LIFO, args evaluated
│     immediately, named returns, loop gotcha), panic/recover
│     (unwinding, when to use, log.Fatal vs panic), select
│     (blocking, non-blocking, timeout, loop pattern),
│     control flow patterns (guard clauses, comma-ok,
│     pointer capture bug)
│
├── 04 - Functions.md                      ✅ DONE
│     basic syntax, pass-by-value (all types), multiple
│     returns, named returns, naked returns, blank identifier,
│     variadic functions, first-class functions, function types,
│     higher-order functions, dispatch tables, anonymous
│     functions, closures (counter, shared state, loop capture
│     gotcha, goroutines), handlers, middleware chain,
│     defer deep dive, panic/recover deep dive, generics
│     (all constraint kinds, ~, linked container, Filter/Map),
│     init(), main(), recursion, methods vs functions,
│     functional options pattern, no overloading/defaults,
│     evaluation order, pitfalls table, performance notes
│
├── 05 - Arrays & Slices.md
│     Arrays: fixed size, value type, [N]T syntax, [...]T,
│     multi-dimensional arrays, when to use arrays vs slices.
│     Slices: internal structure (ptr + len + cap), make(),
│     slice literals, nil vs empty slice, append() mechanics
│     (growth, new backing array), copy(), slice expressions
│     [low:high:max], slices of slices, passing to functions
│     (header copied, shared backing array), common gotchas
│     (append not visible to caller, slice aliasing, range
│     copy), sorting (sort.Slice, sort.Ints, sort.Strings),
│     searching (sort.Search), 2D slices, performance notes
│     (pre-allocating with make)
│
├── 06 - Maps.md
│     map[K]V syntax, make(), map literals, nil map panic,
│     CRUD operations, comma-ok existence check, delete(),
│     iteration (unordered — never rely on order), maps as
│     reference types, nested maps, maps of slices, counting
│     with maps, set pattern (map[T]struct{}), maps and
│     concurrency (not safe — use sync.Map or mutex),
│     comparing maps (reflect.DeepEqual), JSON and maps,
│     performance notes
│
├── 07 - Strings & Runes.md
│     String internals (immutable []byte, UTF-8), len() vs
│     character count, indexing (bytes not chars), raw string
│     literals (backticks), string concatenation (+, Sprintf,
│     strings.Builder), strings package (Contains, HasPrefix,
│     HasSuffix, Index, Replace, ReplaceAll, Split, Join,
│     TrimSpace, ToUpper, ToLower, Fields, Map, TrimFunc),
│     strconv package (Itoa, Atoi, FormatFloat, ParseFloat,
│     ParseBool, Quote, Unquote), byte vs rune (when to use
│     each), []byte conversion (mutating strings), []rune
│     conversion (slicing Unicode safely), range over string
│     (yields runes), unicode package (IsLetter, IsDigit,
│     IsSpace, ToUpper, ToLower), fmt verbs for strings
│     (%s, %q, %v, %T, %d for bytes), multiline strings,
│     string comparison (lexicographic), performance gotchas
│
├── 08 - Pointers.md
│     What a pointer is, & and * operators, *T type syntax,
│     nil pointers and panics, new(T), pointer to struct
│     (automatic dereferencing), pass by pointer vs value
│     (when to use each), pointers and interfaces, double
│     pointers (**T), pointer receivers vs value receivers,
│     common patterns (optional values via nil, mutation in
│     functions, avoiding large copies), what Go does NOT
│     have (pointer arithmetic, manual memory management),
│     escape analysis (stack vs heap), unsafe.Pointer
│     (brief mention — when it exists and why to avoid it)
│
├── 09 - Structs & Methods.md
│     struct syntax, field access, struct literals (named
│     vs positional), anonymous structs, zero value structs,
│     struct embedding (composition over inheritance), promoted
│     fields and methods, struct tags (json, db, validate),
│     comparing structs (== only for comparable fields),
│     copying structs, methods (value vs pointer receivers,
│     consistency rule), method sets, method values vs method
│     expressions, constructor functions (New* pattern),
│     the Stringer interface (String() string), embedding
│     interfaces in structs, struct design patterns
│     (functional options recap, builder pattern)
│
├── 10 - Interfaces.md
│     What an interface is (a contract, not inheritance),
│     implicit satisfaction (no implements keyword), defining
│     interfaces, small interfaces (io.Reader, io.Writer,
│     fmt.Stringer), interface values (type + value pair),
│     nil interfaces vs nil concrete values (the nil interface
│     trap), empty interface (any / interface{}), type
│     assertions (single and two-value form), type switches,
│     interface composition, interfaces and polymorphism,
│     common standard library interfaces (io.Reader,
│     io.Writer, io.Closer, io.ReadWriter, fmt.Stringer,
│     error, sort.Interface), when NOT to use interfaces
│     (don't over-abstract), interface satisfaction check
│     pattern (var _ Interface = (*Type)(nil)), errors as
│     interfaces
│
├── 11 - Error Handling.md
│     error as an interface (Error() string), nil means no
│     error, errors.New(), fmt.Errorf(), error wrapping
│     (%w verb), errors.Is() (sentinel errors), errors.As()
│     (type checking errors), custom error types (struct
│     implementing error), sentinel errors (io.EOF, sql.ErrNoRows),
│     error handling patterns (early return, guard clauses,
│     wrapping with context), panic vs error (when to use
│     each), log.Fatal vs panic vs return error, multiple
│     error strategies (first error wins, collecting all
│     errors), error handling in goroutines, the error
│     interface and type assertions, common mistakes
│     (ignoring errors, over-wrapping, losing context)
│
├── 12 - Goroutines.md
|	│What a goroutine is (lightweight thread), go keyword,
|	goroutines vs OS threads, goroutine scheduling (M:N
|	scheduler, GOMAXPROCS), goroutine lifecycle, main
|	goroutine exits = all goroutines exit, sync.WaitGroup
|	(Add, Done, Wait), goroutine stack (starts small,
|	grows dynamically), goroutines and closures (the loop
|	capture bug), DATA RACES (what they are, how to detect
|	with -race flag), SYNC.MUTEX (Lock, Unlock, protecting
|	shared resources, defer Unlock, NEVER copy a Mutex,
|	RWMutex for read-heavy workloads), applying Mutex to
|	maps and other shared data, goroutine leaks (how they
|	happen, how to prevent), goroutine patterns (fire and
|	forget, worker pool, fan-out), goroutines are not
|	coroutines
│
├── 13 - Channels.md
│     What a channel is (typed pipe), make(chan T),
│     unbuffered channels (synchronous), buffered channels
│     (make(chan T, n)), send (<-) and receive (->),
│     closing a channel (close()), receiving from closed
│     channel (zero value + ok=false), range over channel,
│     channel direction (chan<- T, <-chan T), select statement
│     (recap + deep dive), channel patterns (done channel,
│     pipeline, fan-out, fan-in, semaphore, timeout),
│     deadlocks (what causes them), nil channel behavior
│     (blocks forever), channel vs mutex (when to use each),
│     channel ownership (who creates, who closes)
│
├── 14 - Sync Primitives.md
│     sync.Mutex (Lock, Unlock, defer Unlock pattern),
│     sync.RWMutex (RLock, RUnlock for readers),
│     sync.WaitGroup (coordinate goroutine completion),
│     sync.Once (run something exactly once — singleton),
│     sync.Map (concurrent map — when to use vs regular
│     map + mutex), atomic operations (sync/atomic package:
│     AddInt64, LoadInt64, StoreInt64, CompareAndSwap),
│     race detector (-race flag), common concurrency patterns
│     and mistakes (mutex copy bug, deadlock, livelock,
│     starvation)
│
├── 15 - Generics.md                       (partial in Functions)
│     Full deep dive: type parameters syntax, constraints
│     (any, comparable, cmp.Ordered, union |, underlying ~,
│     method requirements, combining), multiple type params,
│     linked container [S ~[]E, E any], type inference,
│     explicit instantiation, generic types (structs + methods),
│     generic interfaces, constraints package, real-world
│     generic utilities (Map, Filter, Reduce, Contains, Keys,
│     Values, Zip), when to use generics vs interfaces vs any,
│     performance (monomorphization), limitations (no generic
│     methods, no runtime type creation)
│
├── 16 - Packages & Modules.md
│     Package basics (package declaration, main vs library),
│     import paths, visibility (exported vs unexported),
│     init() order across packages, go.mod (module path,
│     Go version, require, replace, exclude), go.sum,
│     go get, go mod tidy, go mod vendor, semantic versioning,
│     internal packages, blank imports, dot imports, package
│     naming conventions, organizing code (flat vs nested
│     packages), build constraints (//go:build), workspaces
│     (go.work for multi-module development)
│
├── 17 - Standard Library.md
│     fmt (Printf verbs: %v %+v %#v %T %d %s %q %f %e %b,
│     Println vs Printf vs Sprintf vs Fprintf, Errorf),
│     os (Args, Exit, Getenv, Setenv, ReadFile, WriteFile,
│     Create, Open, Stdin/Stdout/Stderr),
│     io (Reader, Writer, Closer, Copy, ReadAll, Discard,
│     LimitReader, TeeReader),
│     bufio (Scanner, NewReader, NewWriter, ReadString),
│     strings (all functions — full reference),
│     strconv (all conversions),
│     math (Abs, Sqrt, Floor, Ceil, Round, Min, Max, Pow,
│     Log, Pi, MaxInt, MaxFloat64),
│     sort (Slice, Ints, Strings, Search, Stable),
│     time (Now, Since, Until, Duration, Format, Parse,
│     Sleep, Timer, Ticker, time zones),
│     log (Print, Fatal, Panic, SetFlags, SetPrefix,
│     log/slog for structured logging)
│
├── 18 - net/http.md
│     HTTP server (ListenAndServe, ServeMux, Handle,
│     HandleFunc), handlers and HandlerFunc, request
│     (Method, URL, Header, Body, Form, Context),
│     response writer (Header, WriteHeader, Write),
│     middleware (full pattern, chaining, common middleware:
│     logging, auth, CORS, rate limiting), routing (stdlib
│     mux vs gorilla/mux vs chi), HTTP client (http.Get,
│     http.Post, http.NewRequest, client.Do, custom client
│     with timeout), reading response body, JSON APIs
│     (encoding/decoding request/response bodies), cookies,
│     TLS/HTTPS, timeouts (server + client), context
│     cancellation in handlers, testing HTTP handlers
│
├── 19 - encoding/json.md
│     json.Marshal, json.Unmarshal, struct tags (json:"name",
│     omitempty, -, string option), json.Encoder/Decoder
│     (streaming — for HTTP bodies), working with unknown
│     JSON (map[string]any), json.RawMessage, custom
│     marshaling (MarshalJSON / UnmarshalJSON methods),
│     handling null vs missing fields, json.Number,
│     indented output (json.MarshalIndent), common mistakes
│     (unexported fields silently ignored, interface{}
│     number as float64)
│
├── 20 - File I/O.md
│     os.Open vs os.Create vs os.OpenFile (flags: O_RDONLY,
│     O_WRONLY, O_RDWR, O_CREATE, O_TRUNC, O_APPEND),
│     reading (io.ReadAll, bufio.Scanner line by line,
│     Read into []byte), writing (Write, WriteString,
│     bufio.Writer, Flush), defer f.Close() pattern,
│     named return + defer for close errors,
│     os.ReadFile / os.WriteFile (simple one-shot),
│     filepath package (Join, Dir, Base, Ext, Abs, Walk,
│     Glob, Match), os.MkdirAll, os.Remove, os.Rename,
│     os.Stat (file info: size, modtime, IsDir),
│     directory traversal (os.ReadDir, filepath.Walk,
│     filepath.WalkDir), temp files (os.CreateTemp,
│     os.MkdirTemp), embed package (//go:embed for
│     embedding files into binary)
│
├── 21 - Testing.md
│     testing package basics (func TestXxx(t *testing.T)),
│     t.Error vs t.Fatal vs t.Log, running tests (go test,
│     -v, -run, -count), table-driven tests ([]struct pattern),
│     subtests (t.Run), setup and teardown (TestMain),
│     benchmarks (func BenchmarkXxx(b *testing.B), b.N,
│     go test -bench, -benchmem), examples (func ExampleXxx
│     — also acts as documentation), test helpers (t.Helper),
│     test coverage (go test -cover, -coverprofile,
│     go tool cover), mocking (interfaces as seams,
│     testify/mock brief mention), httptest (httptest.NewRecorder,
│     httptest.NewServer for testing HTTP handlers),
│     fuzzing (go test -fuzz, f.Add, f.Fuzz — Go 1.18+),
│     testing best practices (test the behavior not the
│     implementation, avoid global state, test files
│     end in _test.go)
│
├── 22 - CLI Tools.md
│     os.Args (raw argument access), flag package
│     (flag.String, flag.Int, flag.Bool, flag.Parse,
│     flag.Args, custom usage message), subcommands pattern
│     (flag.NewFlagSet), environment variables (os.Getenv,
│     os.Setenv, os.LookupEnv), reading stdin (bufio.Scanner,
│     os.Stdin), exit codes (os.Exit(0/1/2)), cobra library
│     (brief overview — commands, flags, args, Run),
│     building and distributing (go build -o, GOOS/GOARCH
│     for cross-compilation, ldflags for version injection)
│
├── 23 - Context.md
│     What context is and why it exists (cancellation,
│     deadlines, values propagation), context.Background(),
│     context.TODO(), context.WithCancel (cancel function,
│     <-ctx.Done()), context.WithTimeout,
│     context.WithDeadline, context.WithValue (key type
│     pattern — never use string keys directly), passing
│     context as first parameter (convention), checking
│     ctx.Err() (Canceled vs DeadlineExceeded),
│     context in HTTP handlers (r.Context()),
│     context in database queries, context propagation
│     patterns, common mistakes (storing context in structs,
│     using context.Background() everywhere, wrong key types)
│
├── 24 - Reflection.md
│     reflect package (reflect.TypeOf, reflect.ValueOf),
│     Kind vs Type, inspecting struct fields and tags
│     (reflect.Type.Field, StructTag.Get), modifying values
│     via reflection (Value.Set, Value.Elem, CanSet),
│     calling methods via reflection (Value.Method,
│     Value.Call), reflect.DeepEqual, creating values
│     dynamically (reflect.New, reflect.MakeSlice,
│     reflect.MakeMap), when reflection is justified
│     (ORM, JSON marshaling, dependency injection),
│     performance cost of reflection, why to avoid it
│     in hot paths, alternatives (generics, code generation)
│
└── 25 - Patterns & Idioms.md
      Worker pool pattern (goroutines + channels + WaitGroup),
      pipeline pattern (stages connected by channels),
      fan-out / fan-in, done channel pattern (cancellation),
      semaphore pattern (buffered channel as semaphore),
      functional options (recap as a pattern),
      builder pattern, singleton (sync.Once),
      options struct pattern (alternative to functional options),
      table-driven design, error wrapping conventions,
      the io.Reader / io.Writer composition pattern,
      interface segregation (small interfaces),
      dependency injection via interfaces,
      embed for static assets,
      go:generate for code generation
```

# Prompts 

I’d like to learn about Functions in Go comprehensively with detailed examples. Include all the data, so that I have no questions left. Just Everything. Make it copyable for Obsidian. Include all the nuances, problems, limitations and advantages. Make very clear and engaging. Use a lot of examples with detailed explanation

---

Make questions for anki until the the end of 12th section (generic functions). Avoid Yes\No questions. Make them contemplative and complex. Include coding. Make a lot of questions, do not limit yourself to a few questions for the section, make a lot of them, so that YOU COVER EVERYTHING, do not miss anything. I expect a MINIMUM of 50 questions

