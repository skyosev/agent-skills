# Smell Hunter — Go reference

Contents: Applicability of conditional categories · Generated-code eligibility · Language-only categories · Per-category Go content · Framework carve-outs · Idiom calibration · Phase 2 — smell scans · Phase 5 — Go-specific evaluation

## Applicability of conditional categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Primitive Obsession | **yes** | type-hunter keeps only the construct of an existing enum or alias (Enum Construct Mechanics, Alias vs Named Type Mechanics); domain modeling is here |
| God Module | **no** | a Go source file is not a module, and splitting files inside one package is organizational. A generic *package* name is boundary-hunter's Generic Boundary Names; a package spanning unrelated concerns is solid-hunter's Responsibility Sprawl |
| Mutable Global State | **yes** | package-level `var` is the canonical form |
| Anemic Domain Model | **no** | functional domain logic over immutable data is idiomatic Go. solid-hunter records plain functions and closures as architecture style and never demands objects (its "Functional-style code" Not-a-finding); flagging it here would contradict a sibling hunter |
| Class Abuse | **no** | Go has no classes |

**Language-only categories added below:** `init()` Abuse, Stuttering Names, Pointer Out-Parameters.

## Generated-code eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs such as `*.pb.go` /
`*_gen.go` / `*_generated.go` approximate it.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

## Language-only categories

### init() Abuse

Complex logic, side effects, or non-trivial initialization in `init()` functions.

**Signals:**

- `init()` that opens database connections, network sockets, or file handles
- `init()` that reads environment variables or configuration files
- `init()` with error handling — errors in `init` cannot be returned, only panicked
- `init()` that registers global state (e.g. `http.HandleFunc` in library code)
- Multiple `init()` functions in one package with ordering dependencies (reported here; Temporal Coupling is the
  cross-reference, one site, one finding)
- `init()` that makes the package untestable through import side effects

**Action:** Move initialization into explicit constructors or a `Setup()` called from `main()`. Reserve `init()` for
truly static registrations with no error conditions and no external dependencies. If `init()` can fail, it does not
belong in `init()`.

**Report table:**

| # | Location | Side Effects | Severity | Impact | Action |
| - | -------- | ------------ | -------- | ------ | ------ |
| 1 | file.go:line | Opens DB connection, reads env vars | High | Medium | Move to explicit `Setup()` called from main |

### Stuttering Names

Exported identifiers that repeat the package name, violating Go's convention that the package name supplies context.

**Ownership:** stuttering as a package-design smell is owned here; slop-hunter owns Go
naming-convention *drift introduced by the audited change* (its diff orientation).

**Signals:** `user.UserName` for `user.Name`; `config.ConfigOption` for `config.Option`; `auth.AuthMiddleware` for
`auth.Middleware`; `db.DBConnection` for `db.Connection`; `errors.ErrorCode` for `errors.Code`.

**Action:** Drop the package-name prefix. `user.Name` already reads as "the Name in the user package"; the stutter is
noise and violates the convention documented in Effective Go. Severity is **Low** however widespread.

**Report table:**

| # | Location | Current Name | Suggested Name | Severity | Impact | Action |
| - | -------- | ------------ | -------------- | -------- | ------ | ------ |
| 1 | user/user.go:12 | `user.UserName` | `user.Name` | Low | Low | Rename |

### Pointer Out-Parameters

A function that writes its result through a pointer parameter instead of returning it. Go's idiom is `x = f(x)`, which
shows the write at the call site; `f(&x)` hides it and adds a level of indirection the reader must carry.

**Ownership:** pointer-level indirection is owned here. Abstraction-layer indirection — an
interface or wrapper serving one call site — is simplicity-hunter's Unnecessary Abstractions.

**Signals:**

- `**T` anywhere in a signature: `func syncOrigin(dst **Origin, live bool)`. The caller's variable is already a `*T`,
  so the function can take and return `*T`
- A `*T` parameter named `dst`, `out`, `output`, `result` or `target` on a function returning nothing or only `error`
- `*[]T` where the function only reads the slice or mutates existing elements — a slice header already aliases its
  backing array, so the extra pointer buys nothing unless the caller must observe a reallocation
- `*map[K]V` where the function only inserts or deletes — a map value already aliases its contents; the pointer is
  needed only to replace the whole map
- Two levels of nil with one meaning: the body tests `dst != nil` and `*dst != nil`, but only the inner test carries
  information

**Not a finding** — each carve-out names the construct that requires the shape:

- **Reflection-based stdlib out-params.** `errors.As(err, &myErr)` with `myErr *MyError` passes a `**MyError`;
  `json.Unmarshal(b, &p)` with `p *T` does the same. Those APIs resolve the type at runtime and cannot return a typed
  value. Callers, and wrappers that forward the same `any` out-param, are correct as written.
- **Rewiring a slot in a linked structure.** `func insert(n **node, v int)` takes the address of the link it replaces,
  which removes the root special case. The returning variant usually reads better; the pointer form is a design choice,
  not a smell.
- **cgo, `syscall` and atomics.** `atomic.CompareAndSwapPointer(addr *unsafe.Pointer, …)` and C out-params are fixed by
  the boundary.
- **In-place mutation through `*T`.** That is what pointer receivers and pointer parameters are for. The smell is a
  pointer standing in for a return value, not a pointer used to mutate.
- **Table-driven slot binding.** A `[]struct{ … ; dest **T }` table pairing each source field with the destination
  field it fills. The loop body cannot name the field, so the slot address *is* the binding, and the alternative is a
  closure per row. Flag only a one- or two-row table, where the loop earns nothing over straight-line assignment.

**Action:** Return the value.

```go
// before — the write is invisible at the call site and there are two nils to reason about
func syncOrigin(dst **Origin, live bool) {
	if !live {
		*dst = nil
		return
	}
	…
}

// after — x = f(x) shows the write; one nil left
func syncOrigin(current *Origin, live bool) *Origin {
	if !live {
		return nil
	}
	…
}
```

Converting lengthens each call site from `f(&x.Field, …)` to `x.Field = f(x.Field, …)`, which can cross an `lll`
limit. Shorten the function name rather than keeping the pointer.

**Severity:** **Low** by default — hygiene, no behavioral risk. **Medium** when the two nil levels carry different
meanings the body conflates, or when the hidden write is why a caller misreads the flow.

**Report table:**

| # | Location | Signature | Why a return works | Severity | Impact | Action |
| - | -------- | --------- | ------------------ | -------- | ------ | ------ |
| 1 | model/origin.go:105 | `syncOrigin(dst **Origin, live bool)` | Sets or clears one field the caller can assign | Low | Medium | Return `*Origin` |

## Per-category Go content

### Feature Envy — Go note

Methods can only be defined on types in the same package. The remedy is therefore "move the function next to its
data", not "add a method to the foreign type" — and it must not create an import cycle. Note the cycle risk in the
Action column when the move crosses packages that already reference each other.

### Data Clumps — Go remedies

Extract a named struct. Signature-only clumps become a parameter struct; clumps recurring across struct definitions
become a shared embedded or composed type.

### Primitive Obsession — Go remedies

Define a named type and a validating constructor: `type UserID string` with `func NewUserID(s string) (UserID,
error)`; `type Money int64` in cents rather than `float64`; `time.Duration` rather than a bare `int`; typed string
constants rather than raw comparisons. The type system then prevents mixing `UserID` with `OrderID` at compile time.

### Mutable Global State — Go markers

- `var db *sql.DB`, `var client *http.Client` at package level, assigned at runtime
- `var cache = map[string]any{}` at package level with writes from multiple functions
- Package-level `sync.Mutex` guarding package-level state
- `var defaultConfig = Config{...}` mutated by a `SetConfig()` function
- Global loggers replaced at runtime: `var logger = log.New(...)` plus `SetLogger()`
- `var once sync.Once` with `var instance *Service`

An effectively-constant lookup table (`var weekdayMap = map[string]time.Weekday{...}`) is the read-only-table
Not-a-finding: Go has no `const` maps, so `var` is the only option, and filling the table in `init()` is
initialization. A `//nolint:gochecknoglobals` with a read-only comment is corroborating, not decisive.

### Temporal Coupling — Go remedies

Constructor functions returning a fully initialized struct; a builder whose `Build()` validates required fields;
state-machine types where each state is a distinct type exposing only its valid transitions; dependencies accepted in
the constructor rather than through separate `Set*` methods.

## Framework carve-outs

Go has no widely-mandated type shape, so carve-outs are narrow (Pointer Out-Parameters lists its own):

- **Driver and codec registration in `init()`** — `database/sql` driver registration, encoding registrations, and
  similar static, error-free registrations are the intended use of `init()`. Not an `init()` Abuse finding.

## Idiom calibration

Go's `error` return pattern, explicit control flow, composition over inheritance, and small interfaces defined at the
consumer are the language working as designed — never smells. Repeated `if err != nil` is not a smell here.
Functional-style packages built from plain functions and closures are idiomatic and are explicitly out of scope (see
Applicability). Calibrate to Go conventions, not to patterns from Java, C#, or Python.

## Phase 2 — smell scans

Test files are `*_test.go`. Data Clumps and Mutable Global State scans run on `$GO_PROD`, the list without test
files, with `$TEST_OWNED_EXCLUDE` for codebase mode. A list of test files only becomes `/dev/null`, never empty.

```bash
GO_FILES=$(cat <run>/go.txt); [ -n "$GO_FILES" ] || exit 1          # STOP: empty restore
GO_PROD=$(printf '%s\n' $GO_FILES | grep -v '_test\.go$'); GO_PROD=${GO_PROD:-/dev/null}
# Generated-code globs approximate the authoritative marker (eligibility uses the marker).
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go --glob !**/mock_*.go --glob !**/mocks/**'
TEST_OWNED_EXCLUDE="$EXCLUDE --glob !**/*_test.go"

# Feature envy: methods that heavily reference another package's types
rg -nH --pcre2 '\b[a-z]\w+\.[A-Z]\w+\.' --type go $EXCLUDE -- $GO_FILES

# Data clumps: signatures with 3+ parameters, multi-line included — test setup belongs to test-hunter
rg -nHU --pcre2 'func\s+(\(\w+\s+\*?\w+\)\s+)?\w+\((?:[^,)]*,){2,}[^)]*\)' --type go $TEST_OWNED_EXCLUDE -- $GO_PROD

# Primitive obsession: two bare string/int params in sequence (swap candidates)
rg -nH --pcre2 'func.*\(\s*\w+\s+string\s*,\s*\w+\s+string' --type go $EXCLUDE -- $GO_FILES
rg -nH --pcre2 'func.*\(\s*\w+\s+int\d*\s*,\s*\w+\s+int\d*' --type go $EXCLUDE -- $GO_FILES
rg -nH --pcre2 '\bfloat64\b.*(?i)(price|amount|money|cost|balance)' --type go $EXCLUDE -- $GO_FILES

# Temporal coupling: Init/Setup/Configure methods on receiver types
rg -nH --pcre2 'func\s+\(\w+\s+\*?\w+\)\s+(Init|Setup|Configure|Prepare)\b' --type go $EXCLUDE -- $GO_FILES

# init() functions (then inspect for side effects)
rg -nH '^func init\(\)' --type go $EXCLUDE -- $GO_FILES

# Mutable global state: package-level var declarations — shared test state belongs to test-hunter
rg -nH '^var\s+\(?' --type go $TEST_OWNED_EXCLUDE -- $GO_PROD
rg -nH 'sync\.Once|sync\.Mutex' --type go $TEST_OWNED_EXCLUDE -- $GO_PROD

# Temporary field: optional/transient-looking struct fields
rg -nH --pcre2 '^\s+\w*(?i)(temp|cached|last|pending)\w*\s+' --type go $EXCLUDE -- $GO_FILES

# Comments as deodorant: comment blocks before code (inspect for "what" vs "why"). Written to a file, never
# truncated: read it in pages.
rg -nH -B1 -A1 '^\s*// ' --type go $EXCLUDE -- $GO_FILES > <run>/comments-go.txt; wc -l <run>/comments-go.txt

# Pointer out-parameters: pointer-to-pointer types. Go has no ** operator, so **Ident is a type.
# Unanchored on purpose — it catches signatures that span lines, which the two below miss.
rg -nH --pcre2 '\*\*[A-Za-z_]' --type go $EXCLUDE -- $GO_FILES

# Pointer out-parameters: dst/out/result pointer params (then read the return list)
rg -nH --pcre2 'func[^{]*\b(dst|out|output|result|target)\s+\*' --type go $EXCLUDE -- $GO_FILES

# Pointer out-parameters: pointer-to-slice and pointer-to-map params
rg -nH --pcre2 'func[^{]*(\*\[\]|\*map\[)' --type go $EXCLUDE -- $GO_FILES

# Stuttering names: compare each package name against its exported symbols
rg -nH '^package\s+\w+' --type go $EXCLUDE -- $GO_FILES
rg -nH '^(func|type|var|const)\s+[A-Z]\w+' --type go $EXCLUDE -- $GO_FILES
```

## Phase 5 — Go-specific evaluation

For each `init()`:

- Does it have side effects — I/O, network, global state registration?
- Can it fail? Does it panic? Is the failure recoverable by a caller?
- Does it make the package hard to test through import side effects?
- Is it one of the carve-out registrations?

For each package-level `var` with a write after initialization:

- Is it reachable from multiple goroutines?
- Is it a `sync.Once` + instance pair — a stateful singleton, reported as Mutable Global State?

For each exported identifier:

- Does the name repeat its package name? Cross-check the `package` line against the symbol prefix.

For each pointer-out-parameter candidate:

- Can the function return the value, so the call site reads `x = f(x, …)`? If yes, the pointer is the finding.
- Does the outer nil mean something the inner nil does not? If not, the second level is noise.
- Is the type resolved only at runtime, leaving no typed return possible (`errors.As`, `json.Unmarshal`)? Carve-out.
- For `*[]T`: must the caller observe a reallocation, or does the function only read or mutate elements in place?
- For `*map[K]V`: does the function replace the whole map, or only insert and delete?
