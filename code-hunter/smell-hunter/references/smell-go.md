# Smell Hunter — Go reference

Language-specific rules for Go.

## Applicability of conditional categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Primitive Obsession | **yes** | type-hunter cedes domain modeling and keeps only alias-vs-named-type mechanics |
| God Module | **no** | package organization — including "multiple files in a package spanning unrelated concerns" — is boundary-hunter's; a Go source file is not a module, and splitting files inside one package is organizational |
| Mutable Global State | **yes** | package-level `var` is the canonical form |
| Anemic Domain Model | **no** | functional domain logic over immutable data is idiomatic Go. solid-hunter explicitly does not flag packages using plain functions and closures rather than structs with methods; flagging it here would contradict a sibling hunter |
| Class Abuse | **no** | Go has no classes |

**Language-only categories added below:** `init()` Abuse, Stuttering Names.

## Generated-code eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. **Never** guess by filename. Scan globs
such as `*.pb.go` / `*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the
marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

## Language-only categories

### init() Abuse

Complex logic, side effects, or non-trivial initialization in `init()` functions.

**Signals:**

- `init()` that opens database connections, network sockets, or file handles
- `init()` that reads environment variables or configuration files
- `init()` with error handling — errors in `init` cannot be returned, only panicked
- `init()` that registers global state (e.g. `http.HandleFunc` in library code)
- Multiple `init()` functions in one package with ordering dependencies (also → Temporal Coupling)
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

**Boundary with slop-hunter:** stuttering as a package-design smell is owned here; slop-hunter owns Go
naming-convention *drift introduced by the audited change* (its diff orientation).

**Signals:** `user.UserName` for `user.Name`; `config.ConfigOption` for `config.Option`; `auth.AuthMiddleware` for
`auth.Middleware`; `db.DBConnection` for `db.Connection`; `errors.ErrorCode` for `errors.Code`.

**Action:** Drop the package-name prefix. `user.Name` already reads as "the Name in the user package"; the stutter is
noise and violates the convention documented in Effective Go. Severity is **Low** however widespread — this is
hygiene, not behavioral risk.

**Report table:**

| # | Location | Current Name | Suggested Name | Severity | Impact | Action |
| - | -------- | ------------ | -------------- | -------- | ------ | ------ |
| 1 | user/user.go:12 | `user.UserName` | `user.Name` | Low | Low | Rename |

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

No tension with boundary-hunter's "primitives flow" principle — both resolve in shared domain types.

### Mutable Global State — Go markers

- `var db *sql.DB`, `var client *http.Client` at package level, assigned at runtime
- `var cache = map[string]any{}` at package level with writes from multiple functions
- Package-level `sync.Mutex` guarding package-level state
- `var defaultConfig = Config{...}` mutated by a `SetConfig()` function
- Global loggers replaced at runtime: `var logger = log.New(...)` plus `SetLogger()`
- `var once sync.Once` with `var instance *Service`

**Do not flag** effectively-constant lookup tables (`var weekdayMap = map[string]time.Weekday{...}`) when no write
path exists after initialization — Go has no `const` maps, so `var` is the only option. Confirm by the absence of any
assignment to the variable outside its declaration; a `//nolint:gochecknoglobals` with a read-only comment is
corroborating, not decisive.

### Temporal Coupling — Go remedies

Constructor functions returning a fully initialized struct; a builder whose `Build()` validates required fields;
state-machine types where each state is a distinct type exposing only its valid transitions; dependencies accepted in
the constructor rather than through separate `Set*` methods.

## Framework carve-outs

Go has no widely-mandated type shape, so carve-outs are narrow and must name the construct:

- **Driver and codec registration in `init()`** — `database/sql` driver registration, encoding registrations, and
  similar static, error-free registrations are the intended use of `init()`. Not an `init()` Abuse finding.
- **Generated protobuf/gRPC service structs** — shape is mandated by the generator; eligibility already excludes them
  by marker.

"This project uses framework X" is not evidence. Name the construct that requires the shape.

## Idiom calibration

Go's `error` return pattern, explicit control flow, composition over inheritance, and small interfaces defined at the
consumer are the language working as designed — never smells. Repeated `if err != nil` is not a smell here.
Functional-style packages built from plain functions and closures are idiomatic and are explicitly out of scope (see
Applicability). Calibrate to Go conventions, not to patterns from Java, C#, or Python.

## Evidence path form

Cite findings as `file/path.go:line`.

## Phase 2 — smell scans

Test files are **included** (see Test-code scope in SKILL.md). Data Clumps and Mutable Global State exclude them, so
test setup duplication and shared test state stay with test-hunter.

```bash
# Generated-code globs approximate the authoritative marker (eligibility uses the marker).
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go --glob !**/mock_*.go --glob !**/mocks/**'
TEST_OWNED_EXCLUDE="$EXCLUDE --glob '!**/*_test.go'"

# Feature envy: methods that heavily reference another package's types
rg --pcre2 '\b[a-z]\w+\.[A-Z]\w+\.' --type go $EXCLUDE -- $SCOPE

# Data clumps: repeated parameter groups (long signatures) — test setup belongs to test-hunter
rg --pcre2 'func\s+(\(\w+\s+\*?\w+\)\s+)?\w+\([^)]{100,}\)' --type go $TEST_OWNED_EXCLUDE -- $SCOPE

# Primitive obsession: two bare string/int params in sequence (swap candidates)
rg --pcre2 'func.*\(\s*\w+\s+string\s*,\s*\w+\s+string' --type go $EXCLUDE -- $SCOPE
rg --pcre2 'func.*\(\s*\w+\s+int\d*\s*,\s*\w+\s+int\d*' --type go $EXCLUDE -- $SCOPE
rg --pcre2 '\bfloat64\b.*(?i)(price|amount|money|cost|balance)' --type go $EXCLUDE -- $SCOPE

# Temporal coupling: Init/Setup/Configure methods on receiver types
rg --pcre2 'func\s+\(\w+\s+\*?\w+\)\s+(Init|Setup|Configure|Prepare)\b' --type go $EXCLUDE -- $SCOPE

# init() functions (then inspect for side effects)
rg -n '^func init\(\)' --type go $EXCLUDE -- $SCOPE

# Mutable global state: package-level var declarations — shared test state belongs to test-hunter
rg -n '^var\s+\(?' --type go $TEST_OWNED_EXCLUDE -- $SCOPE
rg -n 'sync\.Once|sync\.Mutex' --type go $TEST_OWNED_EXCLUDE -- $SCOPE

# Temporary field: optional/transient-looking struct fields
rg -n --pcre2 '^\s+\w*(?i)(temp|cached|last|pending)\w*\s+' --type go $EXCLUDE -- $SCOPE

# Comments as deodorant: comment blocks before code (inspect for "what" vs "why")
rg -n -B1 -A1 '^\s*// ' --type go $EXCLUDE -- $SCOPE | head -200

# Stuttering names: compare each package name against its exported symbols
rg -n '^package\s+\w+' --type go $EXCLUDE -- $SCOPE
rg -n '^(func|type|var|const)\s+[A-Z]\w+' --type go $EXCLUDE -- $SCOPE
```

## Phase 5 — Go-specific evaluation

For each `init()`:

- Does it have side effects — I/O, network, global state registration?
- Can it fail? Does it panic? Is the failure recoverable by a caller?
- Does it make the package hard to test through import side effects?
- Is it one of the carve-out registrations?

For each package-level `var`:

- Is it written to anywhere outside its declaration? If not, it is not a finding.
- Is it reachable from multiple goroutines?
- Is it a `sync.Once` + instance pair — a stateful singleton, reported as Mutable Global State?

For each exported identifier:

- Does the name repeat its package name? Cross-check the `package` line against the symbol prefix.

For Primitive Obsession candidates:

- Could two adjacent same-typed parameters actually be transposed at a real call site, type-checking silently?
