# Invariant Hunter — Go reference

Language-specific rules for Go.

## Applicability of universal categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Unguarded Type Assertions | **yes** | bare `x.(T)`, assertion chains, assertions on `any` from external sources, open-interface type switches |
| Loose Optionality | **no** | Go has no optional type; pointer-as-optional has no source evidence, and Nil Pointer Risks covers the crash surface |
| Defensive Access in Non-Boundary Code | **no** | a nil guard the preceding logic already guarantees is simplicity-hunter's Dead Code Paths; the "loose type" half has no Go form |
| Leaky Discriminated Unions | **no** | type-switch exhaustiveness is a marker under Unguarded Type Assertions; Go has no compile-time exhaustiveness for type switches, so `default: panic` is the best available and is not a finding. A tagged struct with fields meaningful only in some states stays smell-hunter's Temporary Field |
| Runtime Checks Promotable to Types | **yes, narrowed** | validated-state named types only — see Per-category Go content |
| Type-System Bypasses | **no** | no source evidence; `any` overuse is not claimed by any Go hunter and is not invented here |

**Language-only categories added below:** Unchecked Errors, Nil Pointer Risks, Zero-Value Traps, Error Chain
Correctness, Context Misuse, Panic/Recover Misuse, Race Conditions. They are Go-only because Go has no error-hunter;
Python and TypeScript route error handling there.

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. **Never** guess by filename. Scan globs
such as `*.pb.go` / `*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the
marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`. Test files are still read as context — a
test that passes `nil` proves the parameter is nil-able.

## Go principles

- **Errors are values.** Every returned error is checked, propagated, or discarded with a justification the code
  confirms. An unchecked error is a silent failure.
- **Nil is a runtime panic.** Validate where nil can enter; return early; document nil semantics in the contract.
- **Zero values must be safe or documented.** Go initializes everything to its zero value. A struct whose zero value
  is invalid needs a constructor that is the only non-zero producer, and a stated zero-value contract.
- **Panic is for programmer errors.** Never on user input, network errors, or recoverable conditions. `recover` is
  not error handling; it hides bugs.
- **Context is ownership.** A function that accepts a `context.Context` consults it and propagates it. Replacing it
  severs the caller's cancellation.

## Language-only categories

### Unchecked Errors

Error returns discarded or ignored.

**Signals:**

- `_ = f()` where `f` returns an `error`, with no justifying comment, or with a comment the code contradicts
- An error return ignored by arity — `f()` as a statement where `f` returns `error`; `errcheck` is the detector,
  regex sees only the explicit `_ =` form
- `defer x.Close()` on a write path — the close error carries the flush result
- `fmt.Fprintf(w, …)` / `w.Write(…)` in handlers with the error dropped
- `if err != nil` checked but the non-error path does not use the result

**Evidence bar:** for `_ = f()`, name the callee's error semantics. `Close` on a read-only handle and a logger flush
are the accepted cases when the code confirms the mode; a `Close` on a handle opened for writing is a finding whatever
the comment says.

**Action:** return it, wrap it with `%w`, or discard it with a comment the code confirms. For `defer Close` on a
write path, capture the error in a named return.

**Ownership:** `_ = f()` where `f` returns an `error` is here. `_ = x` silencing a non-error binding, unused
parameters, and unused struct fields are slop-hunter's Trivially Dead Code.

**Report table:**

| # | Location | Call | Severity | Impact | Action |
| - | -------- | ---- | -------- | ------ | ------ |
| 1 | store/save.go:40 | `_ = f.Close()` on a file opened `O_WRONLY` | High | Medium | Named return; report the close error |

### Nil Pointer Risks

Code paths that dereference nil without prior validation.

**Signals:**

- `(*T, error)` result used before the error is checked
- Map lookup without `ok` where the zero value is ambiguous — `v := m[k]` then `v == ""` indistinguishable from
  "not found"
- Interface method call on a possibly-nil interface value
- Pointer field dereferenced with no guard after construction that can leave it nil
- Indexing a possibly-nil slice (`range` over nil is safe; `s[0]` is not)

**Evidence bar:** the Nil Source cell names where nil enters — the constructor that leaves the field nil, the error
path that returns `nil, err`, the map miss.

**Action:** check the error or the `ok` first; return early or return an error on nil; document nil semantics in the
contract.

**Ownership:** a nil guard the preceding logic already guarantees is simplicity-hunter's Dead Code Paths. `if err !=
nil` is Go working as designed and never a finding of any kind.

**Report table:**

| # | Location | Pattern | Nil Source | Severity | Impact | Action |
| - | -------- | ------- | ---------- | -------- | ------ | ------ |
| 1 | svc/user.go:71 | `u.Name` before `err` check | `FindUser` returns `nil, err` | High | Medium | Check `err` first |

### Zero-Value Traps

An exported struct whose zero value is invalid but can be constructed without a constructor.

**Signals:**

- Map, channel, or func field that is nil at zero value and used without initialization
- Required ID, name, or config with no `New*` constructor, or a constructor that is not the only producer
- Exported struct with methods that panic on the zero value
- `sync.Mutex` / `sync.WaitGroup` copied after first use (`copylocks` nominates)

**Evidence bar:** the Issue cell names the field and the method that fails on the zero value, or the copy site.

**Action:** a constructor; an unexported type when zero-value construction is dangerous; a documented zero-value
contract with lazy init. For types that must not be copied: **Go cannot make a struct non-copyable** — the mitigations
are API design and detection, not enforcement. Keep such types behind pointers (constructors return `*T`; don't accept
or return the struct by value), document the no-copy invariant, and run `go vet`'s `copylocks` analyzer, which is what
actually catches violations. (The unexported `noCopy` marker used by the standard library exists solely to make
`copylocks` fire — a vet convention, not a language guarantee.)

**Ownership:** a type that can be *constructed* invalid is here. A validly constructed value whose *methods* must be
called in order (`Init` before `Run`) is smell-hunter's Temporal Coupling.

**Report table:**

| # | Location | Type | Issue | Severity | Impact | Action |
| - | -------- | ---- | ----- | -------- | ------ | ------ |
| 1 | cfg/config.go:14 | `Config` | nil `overrides` map written by `Set`; no constructor | High | Medium | `NewConfig()`; document zero value |

### Error Chain Correctness

Error handling that loses the chain or prevents `errors.Is` / `errors.As` matching.

**Signals:**

- `fmt.Errorf` with `%v` (or no verb) where a caller matches the chain with `errors.Is` / `errors.As`
- A custom error type with no `Unwrap()` that wraps another error
- `err.Error() == "…"` or `strings.Contains(err.Error(), …)` instead of `errors.Is` / `errors.As`
- Malformed sentinels: `var ErrX = "…"` (a string), `var ErrX error` (nil, never initialized)

**Evidence bar:** for `%v`, name the caller that matches the chain; `%v` with no matching caller is Low.

**Action:** `%w`; implement `Unwrap`; `errors.Is` / `errors.As`; `var ErrX = errors.New("…")`.

**Ownership:** chain *correctness* is here. Wrapping-message *redundancy* (`fmt.Errorf("error: %w", err)`, double
wrapping) is slop-hunter's Unnecessary Error Wrapping. The two compose: wrap correctly, and wrap once.

**Report table:**

| # | Location | Pattern | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | repo/load.go:31 | `fmt.Errorf("load %s: %v", p, err)`; `cmd/run.go:80` uses `errors.Is(err, fs.ErrNotExist)` | High | Medium | `%w` |

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

### Panic/Recover Misuse

Panics used for control flow or error handling.

**Signals:**

- `panic` on input validation failure
- `panic` in library code reachable by callers
- `recover` used to continue normal execution
- `log.Fatal` / `os.Exit` outside `main` and `init`
- `must*` helpers in non-init paths

**Evidence bar:** the Reachable From cell names the entry point — a handler, an exported function, `init` — or
`internal only`. Severity: Critical only when the panic is reachable from a trust boundary *and* nothing recovers it,
so one request kills the process; High when a `recover` contains it to a 500.

**Action:** return an error for anything reachable by external callers; keep `panic` for unreachable code and violated
internal invariants; limit `recover` to goroutine tops and request middleware.

**Policy:** repository instructions that endorse panic in constructors or `init()` for programmer errors withdraw
those sites; cite the instruction in Scope. A panic reachable from a trust boundary is reported regardless.

**Report table:**

| # | Location | Pattern | Reachable From | Severity | Impact | Action |
| - | -------- | ------- | -------------- | -------- | ------ | ------ |
| 1 | api/handler.go:52 | `panic("bad body")` | `POST /orders`; no recovery middleware | Critical | High | Return `400` |

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

**Ownership:** data-race and synchronization *correctness* is here. security-hunter keeps exploitability-framed
concurrency (unbounded goroutines from user input, deadlocks reachable from requests, TOCTOU on auth decisions);
goroutine leaks and `-race` discipline in *tests* stay with test-hunter.

**Report table:**

| # | Location | Shared State | Accessors | Severity | Impact | Action |
| - | -------- | ------------ | --------- | -------- | ------ | ------ |
| 1 | cache/mem.go:18 | `c.items map[string]T` | `Get` (no lock) from handlers; `Set` (locked) from refresher | High | High | Lock in `Get`, or `sync.Map` |

## Per-category Go content

### Unguarded Type Assertions — Go markers

- Bare `x.(T)` — panics on mismatch; the two-value form or a type switch is the fix. **Ownership:** an assertion or
  switch arm that *compensates* for one implementor of a **contract type** (`if _, ok := store.(*memStore); ok {
  skipTx = true }`) is solid-hunter's Broken Substitution, guarded or bare; the panic-on-mismatch guard stays here
  only when no compensation is involved. An assertion that only unlocks an extra outside the contract
  (`pg.Vacuum()`) is neither hunter's
- Assertion chains `x.(A).f.(B)` — one finding, each link a panic point
- Assertions on `any` from JSON, config, or reflection — the value is external and untrusted; these stay here whatever
  the concrete type asserted
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
standard toolchain, and its default analyzers include `copylocks`, `lostcancel`, and `waitgroup`. `errcheck`, and
`golangci-lint` with `errcheck` or `forcetypeassert` enabled, run only when the project has them configured, at the
project's pinned version.

**Execution:** read-only. `go vet ./...` or the project's command; `errcheck ./...` with the project's flags. Record
in Scope, per tool: `ran — <command>, <version>, <coverage>, <options>` / `skipped — not configured` /
`skipped — configured, not installed` / `errored — <message>` (packages fail to load, module download needed).
Options that change what a tool sees are part of the record: `errcheck -blank` (off by default — blank assignments
are then *not* checked), `-asserts`, `-exclude` lists, `golangci-lint` `issues.exclude` rules.

**Outcome rules:**

- `errcheck` not configured → one Low recommendation to adopt it; regex cannot see implicitly ignored returns.
- `errcheck` configured but not installed, or ran with `-blank` off → state the coverage limitation; recommend nothing.
- `go vet` ran → `copylocks`, `lostcancel`, `waitgroup` nominations are triaged; never "recommend enabling" a default
  analyzer.
- Any tool skipped or errored → the heuristic scans below run alone, and the report says so.

Vet's checks are heuristic — low-false-positive, not zero; triage rather than transcribe.

## Idiom calibration

`if err != nil` after every call is Go working as designed, never defensive access and never a finding. Functional
packages built from plain functions with no exported structs are not zero-value traps. Constructors returning `*T`
and accepting dependencies are the idiom, not temporal coupling. A `default: panic("unreachable")` arm on a sealed
type switch is exhaustiveness by convention and is neither a finding here nor Dead Code for simplicity-hunter.

## Evidence path form

Cite findings as `file/path.go:line`.

## Phase 2 — invariant scans

Test files are **excluded** (see Test-code scope in SKILL.md). Every scan takes the eligible Go list; generated-code
globs approximate the authoritative marker.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Unchecked Errors: explicitly discarded returns — regex cannot see implicitly ignored returns (errcheck's job)
rg -n '\b_\s*=\s*\w+[\w.]*\(' --type go $EXCLUDE -- $SCOPE

# Unchecked Errors: deferred Close (then read the open mode)
rg -n 'defer\s+\w+(\.\w+)*\.Close\(\)' --type go $EXCLUDE -- $SCOPE

# Unguarded Type Assertions: census minus .(type) — regex cannot separate bare from two-value forms; triage each
rg -n '\.\(\*?[\w.]+\)' --type go $EXCLUDE -- $SCOPE | rg -v '\.\(type\)'

# Unguarded Type Assertions: type switches (then check the interface is open and what follows the switch)
rg -n 'switch\s+(\w+\s*:=\s*)?\w+\.\(type\)' --type go $EXCLUDE -- $SCOPE

# Zero-Value Traps: exported structs with map/chan/func fields (then look for a constructor)
rg -n -U --pcre2 'type\s+[A-Z]\w*\s+struct\s*\{[^}]*\b(map\[|chan\s|func\()' --type go $EXCLUDE -- $SCOPE

# Error Chain Correctness: fmt.Errorf census (then check %w vs %v against matching callers)
rg -n 'fmt\.Errorf\(' --type go $EXCLUDE -- $SCOPE

# Error Chain Correctness: error string comparison; malformed sentinels
rg -n 'err\.Error\(\)\s*==|strings\.Contains\(err' --type go $EXCLUDE -- $SCOPE
rg -n --pcre2 '^var\s+Err\w+\s*(=\s*"|error\s*$)' --type go $EXCLUDE -- $SCOPE

# Context Misuse: cancel funcs (then read every return path), and Background/TODO as a nomination for
# *severed propagation* only — a hit in a function with no incoming context is discarded in Phase 5
rg -n 'context\.With(Cancel|Timeout|Deadline)(Cause)?\(' --type go $EXCLUDE -- $SCOPE
rg -n 'context\.(Background|TODO)\(\)' --type go $EXCLUDE -- $SCOPE

# Panic/Recover Misuse
rg -n '\bpanic\(' --type go $EXCLUDE -- $SCOPE
rg -n '\brecover\(\)' --type go $EXCLUDE -- $SCOPE
rg -n 'log\.Fatal|os\.Exit' --type go $EXCLUDE -- $SCOPE
rg -n --pcre2 '\bfunc\s+[mM]ust\w*\(' --type go $EXCLUDE -- $SCOPE

# Race Conditions: goroutine launches and sync primitives (then map shared state to its accessors)
rg -n '^\s*go\s+(func|\w+)' --type go $EXCLUDE -- $SCOPE
rg -n 'sync\.(Mutex|RWMutex|WaitGroup)|atomic\.' --type go $EXCLUDE -- $SCOPE
```

## Phase 5 — Go-specific evaluation

For each `_ = f()`:

- Does `f` return an `error`? No → slop-hunter's `_ = x`; cross-reference, do not score.
- Is there a comment, and does the code confirm it (open mode, callee semantics)? A write-path `Close` is a finding
  whatever the comment says.

For each type assertion candidate:

- Does the branch compensate for one implementor of a contract type failing its promise? → solid-hunter's Broken
  Substitution, guarded or bare; cross-reference, do not score.
- Two-value form or inside a type switch? Not a finding.
- Bare: what is the source of the value — internal and provably typed, or external (`any` from JSON, config)?
- Type switch with no `default`: is the interface sealed? If open, does the code after the switch reject or
  deliberately fall back? Silent zero value → finding.

For each `fmt.Errorf` with `%v` or no verb:

- Does any caller match the chain with `errors.Is` / `errors.As`? Name it. None → Low.
- Is the message redundant rather than the verb wrong? That is slop-hunter's; cross-reference.

For each `context.Background()` / `TODO()`:

- Does the enclosing function receive a `ctx`? No → not a finding. Yes → is the new context passed downstream in
  place of the incoming one? That severs propagation.

For each `WithCancel` / `WithTimeout` / `WithDeadline` (and `*Cause`):

- Is `cancel` called on every return path — deferred, explicit, or handed to an owner that calls it? Read before
  flagging; `lostcancel` nominations are triaged the same way.

For each `panic`:

- Is it reachable from a trust boundary? Does repository policy endorse this site (constructor, `init`)? Policy
  withdraws the site unless it is reachable from untrusted input.
- Is there a `recover` between the panic and the process boundary? Critical only when there is none.

For each exported struct without a constructor:

- Which field is invalid at zero value, and which method fails on it? Is the zero value documented and lazily
  initialized? Documented and safe → not a finding.

For each shared variable touched by more than one goroutine:

- Name the accessors on both sides and the lock state of each. One side unlocked → finding.
