# Invariant Hunter — Go reference

Contents: Applicability of universal categories · Generated-code and test-path eligibility · Go principles · Not a finding on these grounds alone — Go · Language-only categories · Per-category Go content · Toolchain · Idiom calibration · Phase 2 — invariant scans · Phase 5 — Go-specific evaluation

## Applicability of universal categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Unguarded Type Assertions | **yes** | bare `x.(T)`, assertion chains, assertions on `any` from external sources, open-interface type switches |
| Loose Optionality | **no** | Go has no optional type; pointer-as-optional has no source evidence, and Nil Pointer Risks covers the crash surface |
| Defensive Access in Non-Boundary Code | **no** | a nil guard the preceding logic already guarantees is simplicity-hunter's Dead Code Paths; the "loose type" half has no Go form |
| Leaky Discriminated Unions | **no** | type-switch exhaustiveness is a marker under Unguarded Type Assertions; Go has no compile-time exhaustiveness for type switches, so `default: panic` is the best available and is not a finding. A tagged struct with fields meaningful only in some states stays smell-hunter's Temporary Field |
| Runtime Checks Promotable to Types | **yes, narrowed** | validated-state named types only — see Per-category Go content |
| Type-System Bypasses | **no** | no source evidence; `any` overuse is not claimed by any Go hunter and is not invented here |

**Language-only categories added below:** Nil Pointer Risks, Zero-Value Traps, Context Misuse, Race Conditions.
Failure handling — discarded errors, error chains, panic and recover — is exception-hunter's in every language.

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs such as `*.pb.go` /
`*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`.

## Go principles

- **Nil is a runtime panic.** Validate where nil can enter; return early; document nil semantics in the contract.
- **Zero values must be safe or documented.** Go initializes everything to its zero value. A struct whose zero value
  is invalid needs a constructor that is the only non-zero producer, and a stated zero-value contract.
- **Context is ownership.** A function that accepts a `context.Context` consults it and propagates it. Replacing it
  severs the caller's cancellation.

## Not a finding on these grounds alone — Go

- **A zero-value type designed and documented for zero-value use.** *Is* a finding when a method panics on it.
- **A type switch with no `default`** over a sealed interface (the finite set is known), or over an open interface
  where the code after the switch returns an error, a sentinel, or a deliberate fallback. *Is* a finding when
  unmatched values silently produce a zero value the contract does not permit.

## Language-only categories

### Nil Pointer Risks

Code paths that dereference nil without prior validation.

**Signals:**

- `(*T, error)` result used before the error is checked
- Map lookup without `ok` on a map of pointers or interfaces, then dereferenced (`m[k].Name`)
- Interface method call on a possibly-nil interface value
- Pointer field dereferenced with no guard after construction that can leave it nil
- Indexing a possibly-nil slice (`range` over nil is safe; `s[0]` is not)

**Evidence bar:** the Nil Source cell names where nil enters — the constructor that leaves the field nil, the error
path that returns `nil, err`, the map miss.

**Action:** check the error or the `ok` first; return early or return an error on nil; document nil semantics in the
contract.

**Ownership:** a nil guard the preceding logic already guarantees is simplicity-hunter's Dead Code Paths. `if err !=
nil` is Go working as designed, not a nil guard; what its branch does with the error is exception-hunter's.

**Report table:**

| # | Location | Pattern | Nil Source | Severity | Impact | Action |
| - | -------- | ------- | ---------- | -------- | ------ | ------ |
| 1 | svc/user.go:71 | `u.Name` before `err` check | `FindUser` returns `nil, err` | High | Medium | Check `err` first |

### Zero-Value Traps

An exported type whose zero value is invalid but can be produced without a constructor, or a named constant type
whose values arrive unchecked.

**Signals:**

- Map, channel, or func field that is nil at zero value and used without initialization
- Required ID, name, or config with no `New*` constructor, or a constructor that is not the only producer
- Exported struct with methods that panic on the zero value
- `sync.Mutex` / `sync.WaitGroup` copied after first use (`copylocks` nominates)
- A zero sentinel (`Unknown Status = iota`) that no consumer rejects, so an unset field reads as a valid-looking
  member
- A conversion `T(n)` of external input (request body, config, DB column) into a named constant type with no range
  check. The unchecked conversion is here; content validation and exploitability are security-hunter's

**Evidence bar:** the Issue cell names the field and the method that fails on the zero value, the copy site, the
consumer that accepts the unchecked sentinel, or the conversion site and the input it converts.

**Action:** a constructor; an unexported type when zero-value construction is dangerous; a documented zero-value
contract with lazy init. For types that must not be copied: **Go cannot make a struct non-copyable** — the mitigations
are API design and detection, not enforcement. Keep such types behind pointers (constructors return `*T`; don't accept
or return the struct by value), document the no-copy invariant, and run `go vet`'s `copylocks` analyzer, which is what
actually catches violations.

**Action (sentinels and conversions):** reject the zero sentinel at the consumer or the constructor; convert external
input through a parse function that range-checks (`ParseStatus(n) (Status, error)`).

**Ownership:** a type that can be *constructed* invalid is here. A validly constructed value whose *methods* must be
called in order (`Init` before `Run`) is smell-hunter's Temporal Coupling. The construct of the constant group itself
(missing named type, no `String()`) is type-hunter's Enum Construct Mechanics.

**Report table:**

| # | Location | Type | Issue | Severity | Impact | Action |
| - | -------- | ---- | ----- | -------- | ------ | ------ |
| 1 | cfg/config.go:14 | `Config` | nil `overrides` map written by `Set`; no constructor | High | Medium | `NewConfig()`; document zero value |

### Context Misuse

Propagation and cancellation ownership — not the spelling of `context.Background()`.

**Signals:**

- A function accepting `context.Context` that never consults it in a loop or around blocking I/O
- An incoming `ctx` *replaced* by `context.Background()` / `context.TODO()` for a downstream call, severing
  cancellation
- A network or DB call with no `ctx` parameter in a call chain that has one
- A cancel func from `WithCancel` / `WithTimeout` / `WithDeadline` and their `*Cause` variants not called on every
  path — `defer cancel()` is the idiom, not the test; explicit calls and transferred ownership are read before flagging
  (`lostcancel` in default vet nominates)

**Not signals:** `context.Background()` / `TODO()` where no context is available to propagate; context values used
as dependency injection. Both are design smells, not unenforced invariants, and are not findings here.

**Action:** propagate the incoming context; consult it in loops and before blocking calls; cancel on every path.

**Report table:**

| # | Location | Pattern | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | svc/sync.go:44 | `ctx := context.Background()` replaces the parameter before `db.QueryContext` | High | Medium | Pass the incoming `ctx` |

### Race Conditions

Shared mutable state accessed without synchronization.

**Signals:**

- A map or struct field read and written from multiple goroutines with no mutex
- A mutex taken on one path but not on another that touches the same state
- `WaitGroup.Add` inside the goroutine instead of before `go`
- Non-atomic read-modify-write on a shared variable

**Evidence bar:** the Accessors cell names the goroutines or call paths on both sides — one writer and one reader at
least, with the lock state of each.

**Action:** `sync.Mutex` / `RWMutex`, `sync/atomic`, or channel ownership.

**Ownership:** data-race and synchronization *correctness* is here. security-hunter keeps goroutine creation a
request can grow without a bound (Resource Exhaustion); check-then-act races on persistent state are reported by
neither hunter; goroutine leaks and `-race` discipline in *tests* stay with test-hunter.

**Report table:**

| # | Location | Shared State | Accessors | Severity | Impact | Action |
| - | -------- | ------------ | --------- | -------- | ------ | ------ |
| 1 | cache/mem.go:18 | `c.items map[string]T` | `Get` (no lock) from handlers; `Set` (locked) from refresher | High | High | Lock in `Get`, or `sync.Map` |

## Per-category Go content

### Unguarded Type Assertions — Go markers

- Bare `x.(T)` — panics on mismatch; the two-value form or a type switch is the fix. **Ownership:** an assertion or
  switch arm that *compensates* for one implementor of a **contract type** (`if _, ok := store.(*memStore); ok {
  skipTx = true }`) is solid-hunter's Broken Substitution, guarded or bare; the panic-on-mismatch guard stays here
  only when no compensation is involved. A *two-value* check that only unlocks an extra outside the contract
  (`if pg, ok := s.(*pgStore); ok { pg.Vacuum() }`) is neither hunter's; the bare form (`s.(*pgStore).Vacuum()`) is
  an Unguarded Type Assertion here
- Assertion chains `x.(A).f.(B)` — one finding, each link a panic point
- Assertions on `any` from JSON, config, or reflection — the value is external and untrusted; these stay here whatever
  the concrete type asserted, except `any(v).(X)` where `v` is a type parameter inside a generic body — that is
  type-hunter's Loose Type Parameter Constraints
- A type switch over an *open* interface with no `default`, in a function whose contract requires handling or
  rejecting every value, when the code after the switch neither rejects nor deliberately falls back. Sealed
  interfaces (unexported method, finite set in the package) are not findings. `fmt`'s `handleMethods` switches on
  `error` and `Stringer` and returns `false` for everything else by design — not a finding. A switch that silently
  yields a zero value the contract does not permit is High. **Ownership:** an arm that compensates for one
  implementor of a contract type is solid-hunter's Broken Substitution; the missing-rejection question stays here.

### Runtime Checks Promotable to Types — Go narrowing

Only validated-state named types: `type Email struct{ s string }` with `func NewEmail(string) (Email, error)` whose
constructor is the only *non-zero* producer, replacing a validation re-run at every consumer. Go cannot stop `Email{}`
or `var e Email`, so the Proposed cell states what the zero value does — safe by design, or rejected on use (`IsZero`,
a method returning an error). A proposed type whose zero value would be usable and invalid (`Email{}.String()`
returning `""` silently) is a Zero-Value Traps finding first. Identity and unit types with no validation boundary are
smell-hunter's Primitive Obsession.

## Toolchain

**Adoption evidence:** the repository's own vet/lint entry point — a Makefile target, a CI step, a `.golangci.yml`.
When none exists, `go vet ./...` is still run when a Go toolchain is on `PATH` and packages load: vet is part of the
standard toolchain, and its default analyzers include `copylocks`, `lostcancel`, and `waitgroup`. `golangci-lint`
with `forcetypeassert` enabled runs only when the project has it configured, at the project's pinned version.

**Execution:** read-only. `GOPROXY=off go vet ./...` or the project's command. `GOPROXY=off` stops the go command
from downloading missing modules; a load failure (packages fail to load, module download needed) is then `errored`,
never a fetch. Options that change what a tool sees are part of the record: `golangci-lint` exclusion rules
(`issues.exclude-rules` in v1, `linters.exclusions` in v2).

**Outcome rules:**

- `go vet` ran → `copylocks`, `lostcancel`, `waitgroup` nominations are triaged.

Vet's checks are heuristic — low-false-positive, not zero; triage rather than transcribe.

## Idiom calibration

Functional
packages built from plain functions with no exported structs are not zero-value traps. Constructors returning `*T`
and accepting dependencies are the idiom, not temporal coupling. A `default: panic("unreachable")` arm on a sealed
type switch is exhaustiveness by convention and is neither a finding here nor Dead Code for simplicity-hunter.

## Phase 2 — invariant scans

`$GO_FILES` is this language's eligible list, restored from `<run>/go.txt` (SKILL.md Phase 1 step 4). Generated-code
globs in `$EXCLUDE` approximate the authoritative marker.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Unguarded Type Assertions: census minus .(type) — regex cannot separate bare from two-value forms; triage each
rg -H -n '\.\(\*?[\w.]+\)' --type go $EXCLUDE -- $GO_FILES | rg -v '\.\(type\)'

# Unguarded Type Assertions: type switches (then check the interface is open and what follows the switch)
rg -H -n 'switch\s+(\w+\s*:=\s*)?\w+\.\(type\)' --type go $EXCLUDE -- $GO_FILES

# Zero-Value Traps: exported structs with map/chan/func fields (then look for a constructor)
rg -H -n -U --pcre2 'type\s+[A-Z]\w*\s+struct\s*\{[^}]*\b(map\[|chan\s|func\()' --type go $EXCLUDE -- $GO_FILES

# Zero-Value Traps: typed iota zero members (then check whether any consumer rejects the zero sentinel)
rg -H -n --pcre2 '^\s*\w+\s+[A-Z]\w*\s*=\s*iota\b' --type go $EXCLUDE -- $GO_FILES

# Context Misuse: cancel funcs (then read every return path), and Background/TODO as a nomination for
# *severed propagation* only — a hit in a function with no incoming context is discarded in Phase 5
rg -H -n 'context\.With(Cancel|Timeout|Deadline)(Cause)?\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n 'context\.(Background|TODO)\(\)' --type go $EXCLUDE -- $GO_FILES

# Race Conditions: goroutine launches and sync primitives (then map shared state to its accessors)
rg -H -n '^\s*go\s+(func|\w+)' --type go $EXCLUDE -- $GO_FILES
rg -H -n 'sync\.(Mutex|RWMutex|WaitGroup)|atomic\.' --type go $EXCLUDE -- $GO_FILES
```

## Phase 5 — Go-specific evaluation

For each type assertion candidate:

- Does the branch compensate for one implementor of a contract type failing its promise? → solid-hunter's Broken
  Substitution, guarded or bare; cross-reference, do not score.
- Two-value form or inside a type switch? Not a finding.
- Bare: what is the source of the value — internal and provably typed, or external (`any` from JSON, config)?
- Type switch with no `default`: is the interface sealed? If open, does the code after the switch reject or
  deliberately fall back? Silent zero value → finding.

For each `context.Background()` / `TODO()`:

- Does the enclosing function receive a `ctx`? No → not a finding. Yes → is the new context passed downstream in
  place of the incoming one? That severs propagation.

For each `WithCancel` / `WithTimeout` / `WithDeadline` (and `*Cause`):

- Is `cancel` called on every return path — deferred, explicit, or handed to an owner that calls it? Read before
  flagging; `lostcancel` nominations are triaged the same way.

For each exported struct without a constructor:

- Which field is invalid at zero value, and which method fails on it? Is the zero value documented and lazily
  initialized? Documented and safe → not a finding.

For each typed `iota` zero member and each `T(n)` conversion into a named constant type:

- Is the zero member a deliberate "unset" sentinel? Does every consumer reject it, or the constructor refuse it? One
  consumer that treats it as a valid member → finding.
- Does `n` come from external input with no range check before or after the conversion? → finding; content →
  security-hunter. Internal, provably in range → not a finding.

For each shared variable touched by more than one goroutine:

- Name the accessors on both sides and the lock state of each. One side unlocked → finding.
