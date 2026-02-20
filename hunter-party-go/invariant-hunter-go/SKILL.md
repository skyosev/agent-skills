---
name: invariant-hunter-go
description: |
  Audit Go code for weak invariants — unchecked errors, nil pointer risks, ignored
  context cancellation, unsafe type assertions, zero-value traps, panic/recover misuse,
  and missing validation at construction boundaries.

  Use when: tightening domain models, reducing panic risks, increasing error handling
  discipline, or establishing a safety baseline before refactoring.
---

# Invariant Hunter

Audit Go code to make invariants explicit and enforced — catching unchecked errors, nil dereferences waiting to happen,
type assertions without ok checks, zero-value traps, and places where panic replaces proper error handling. The goal:
**errors are always handled, nil is never dereferenced unexpectedly, and invalid states are caught at construction
boundaries.**

## When to Use

- Tightening a domain model after initial prototyping
- Reducing panic risks across a codebase
- Improving error handling discipline
- Reviewing zero-value safety of struct types
- Before a major refactor to establish a safety baseline
- After enabling new linters or static analysis tools

## Core Principles

1. **Errors are values, not exceptions.** Every returned error must be handled — checked, propagated, or explicitly
   discarded with documented justification. An unchecked error is a silent failure.

2. **Nil is the billion-dollar mistake in Go too.** A nil pointer dereference panics at runtime. Validate at boundaries,
   return early on nil, and document nil semantics in function contracts.

3. **Resolve at construction boundaries.** Defaults and validation belong where data is created or enters the system —
   constructor functions (`New*`), API handlers, config loaders. Downstream functions should require their inputs to be
   valid. If every caller checks the same condition, push the check to the constructor.

4. **Zero values must be safe or documented.** Go initializes all variables to their zero value. If a struct's zero
   value is invalid (e.g., a nil map, zero ID, empty required field), the constructor must enforce valid construction,
   and this constraint must be documented.

5. **Type assertions must be checked.** A bare type assertion (`x.(T)`) panics on failure. Use the two-value form
   (`v, ok := x.(T)`) or a type switch. Panic-on-assertion is acceptable only in test code or when the assertion
   is provably correct.

6. **Panic is for programmer errors, not runtime conditions.** Panic for truly unreachable code, violated invariants in
   internal logic, or test failures. Never panic on user input, network errors, or recoverable conditions.

7. **Context cancellation is not optional.** Functions that accept `context.Context` must check for cancellation,
   especially in loops, I/O operations, and long-running computations. Ignoring context defeats the purpose of passing
   it.

8. **`recover` is not error handling.** Using `recover` to catch panics and continue is a code smell. It hides bugs.
   The only legitimate use is at the top of goroutines in server code to prevent one request from crashing the process.

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| `_ = f()` (discarded error) | Error is truly ignorable (Close on read-only file, logger flush) with comment |
| Bare type assertion in test | Test code where panic is the desired failure mode |
| Zero-value struct | Struct is explicitly designed for zero-value usability (documented) |
| `recover` in HTTP middleware | Top-level panic recovery to prevent server crash |
| `panic` in init() | Truly fatal configuration error during startup |

## What to Hunt

### 1. Unchecked Errors

Returned errors that are silently discarded or ignored.

**Signals:**

- Function call with error return where error is assigned to `_` without justification
- Error return completely ignored (result count mismatch)
- `defer f.Close()` without checking the error (especially on writes)
- `fmt.Fprintf(w, ...)` in HTTP handlers without checking write error
- Error checked with `if err != nil` but the non-error path doesn't use the result

**Action:** Handle every error: return it, wrap it, or explicitly discard with a justifying comment. For `defer Close`,
use a named return to capture the error.

### 2. Nil Pointer Risks

Code paths that can dereference nil without prior validation.

**Signals:**

- Function that returns `(*T, error)` where callers use `*T` without checking error first
- Map lookup result used without checking the `ok` boolean when the zero value is ambiguous or could mask a missing
  key (`v := m[key]` then using `v` where `v == ""` or `v == 0` is indistinguishable from "not found")
- Interface method call without nil check on the interface value
- Struct fields of pointer type accessed without nil guard after construction
- `range` over a nil slice is safe, but indexing a nil slice is not — check index operations

**Action:** Validate at the boundary where nil could enter. Return early or return error on nil. Document nil
semantics in function contracts.

### 3. Unsafe Type Assertions

Type assertions without the two-value ok check, risking panics.

**Signals:**

- `x.(ConcreteType)` without ok check (panics if wrong type)
- Type assertion chain: `x.(A).field.(B)` — multiple panic points
- Type assertions on `interface{}` / `any` values from external sources (JSON, config, etc.)
- Type switch with no `default` case on an open interface (where new implementations can appear). Exhaustive type
  switches on sealed/internal interfaces with a known finite set of types are not a concern

**Action:** Use two-value form `v, ok := x.(T)` or type switch. Handle the failure case explicitly.

### 4. Zero-Value Traps

Structs whose zero value is invalid but can be created without a constructor.

**Signals:**

- Struct with map, channel, or func fields that are nil at zero value and used without initialization
- Struct that requires non-zero ID, name, or config but has no `New*` constructor
- Exported struct type with no constructor and methods that panic on zero value
- `sync.Mutex` or `sync.WaitGroup` copied after first use (detected via `go vet`)

**Action:** Provide a constructor. Make the struct unexported if zero-value construction is dangerous. Document zero-
value behavior. Use `sync.Locker` interface for mutexes that shouldn't be copied.

### 5. Error Wrapping and Sentinel Errors

Poor error handling patterns that lose context or prevent `errors.Is`/`errors.As` matching.

**Signals:**

- `fmt.Errorf` without `%w` (loses the error chain — cannot use `errors.Is`)
- Custom error type that doesn't implement `Unwrap()` method
- String comparison of error messages instead of `errors.Is` / `errors.As`
- Sentinel errors defined incorrectly: e.g., `var ErrNotFound = "not found"` (string, not error) or
  `var ErrNotFound error` (nil, not initialized) instead of `var ErrNotFound = errors.New("not found")`
- Error wrapping that adds no useful context: `fmt.Errorf("error: %w", err)`

**Action:** Use `%w` in `fmt.Errorf` for wrappable errors. Use `errors.Is`/`errors.As` for comparison. Add meaningful
context when wrapping: package name, operation, relevant parameters.

### 6. Context Misuse

Ignoring context cancellation, improper context construction, or missing context propagation.

**Signals:**

- Function accepts `context.Context` but never checks `ctx.Err()` or `ctx.Done()` in loops/I/O
- `context.Background()` or `context.TODO()` in non-main, non-test code
- Context values used for passing dependencies (should use struct fields)
- `context.WithCancel` or `context.WithTimeout` without calling the cancel function
- Missing `ctx` parameter in functions that make network/DB calls

**Action:** Check context in loops and before expensive operations. Use `context.TODO()` only temporarily with a
comment. Pass context through the call chain. Always defer cancel functions.

### 7. Panic/Recover Misuse

Panics used for control flow or error handling instead of proper error returns.

**Signals:**

- `panic()` called on user input validation failure
- `panic()` in library code reachable by callers (not internal assertions)
- `recover()` used to suppress errors and continue normal execution
- `log.Fatal()` or `os.Exit()` in library code (not `main` or init)
- `must*` functions that panic in non-test, non-init contexts

**Action:** Replace panic with error return for any condition reachable by external callers. Use panic only for
genuinely unreachable code (exhaustive switch defaults, violated internal invariants). Limit `recover` to goroutine
crash prevention in server code.

### 8. Race Conditions and Synchronization Gaps

Shared mutable state accessed without proper synchronization.

**Signals:**

- Map read/write from multiple goroutines without mutex
- Struct field accessed from multiple goroutines without sync primitives
- `sync.Mutex` locked in one path but not in another that accesses the same state
- `sync.WaitGroup.Add()` called inside the goroutine instead of before `go`
- Non-atomic read-modify-write on shared variables

**Action:** Protect shared state with `sync.Mutex`, `sync.RWMutex`, `sync/atomic`, or channels. Run tests with
`-race` flag.

## Audit Workflow

### Phase 1: Establish Baseline

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.

2. Check tooling configuration: `go vet` settings, `staticcheck` or `golangci-lint` config, race detection in CI.

3. Scan for patterns:
   ```bash
   EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/**'

   # Unchecked errors (discarded with _)
   rg '\b_\s*=\s*\w+\(' --type go $EXCLUDE

   # Bare type assertions (no ok check)
   rg --pcre2 '\.\(\*?\w+\)(?!\s*$)' --type go $EXCLUDE

   # Panic calls
   rg 'panic\(' --type go $EXCLUDE

   # Recover calls
   rg 'recover\(\)' --type go $EXCLUDE

   # log.Fatal / os.Exit outside main
   rg 'log\.Fatal|os\.Exit' --type go $EXCLUDE

   # context.Background() / context.TODO() in non-main
   rg 'context\.(Background|TODO)\(\)' --type go $EXCLUDE

   # fmt.Errorf without %w
   rg 'fmt\.Errorf' --type go $EXCLUDE

   # Error string comparison
   rg 'err\.Error\(\)\s*==|strings\.Contains\(err' --type go $EXCLUDE

   # Nil map/channel field access
   rg 'make\(map|make\(chan' --type go $EXCLUDE

   # Deferred close without error check
   rg 'defer\s+\w+\.Close\(\)' --type go $EXCLUDE
   ```

4. Produce counts by category, grouped by package.

### Phase 2: Evaluate Error Handling

For each function that returns error: Is every caller handling it?
For each `_ = f()`: Is the discard justified?
For each error wrap: Does it use `%w`? Does it add context?

### Phase 3: Evaluate Nil Safety

For each pointer return: Do callers check error before using the pointer?
For each map lookup: Is the ok value checked when the zero value is meaningful?
For each interface parameter: Is nil handled or documented?

### Phase 4: Evaluate Type Safety

For each type assertion: Is the ok check present?
For each type switch: Is there a default case?
For each zero-value struct: Is the zero value safe or documented?

### Phase 5: Evaluate Concurrency Safety

For each shared variable: Is it protected?
For each goroutine: Is there a cancellation mechanism?
For each sync primitive: Is it used correctly and consistently?

## Output Format

Save as `YYYY-MM-DD-invariant-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Invariant Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Tooling Context

- `go vet`: {enabled/disabled in CI}
- Static analysis: {golangci-lint / staticcheck / none}
- Race detection: {enabled/disabled in CI}

## Baseline

| Category | Count |
| -------- | ----- |
| Discarded errors (`_ =`) | {n} |
| Bare type assertions | {n} |
| `panic()` calls (non-test) | {n} |
| `recover()` calls | {n} |
| `log.Fatal` / `os.Exit` in non-main | {n} |
| `context.Background()` in non-main | {n} |
| `fmt.Errorf` without `%w` | {n} |
| Error string comparison | {n} |
| Deferred Close without error check | {n} |

## Unchecked Errors

| # | Location | Call | Action |
| - | -------- | ---- | ------ |
| 1 | file:line | `_ = db.Close()` | Check error or add justification comment |

## Nil Pointer Risks

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `user.Name` without nil check after `FindUser` | Check error before dereference |

## Type Assertion Safety

| # | Location | Assertion | Action |
| - | -------- | --------- | ------ |
| 1 | file:line | `val.(string)` | Use `val, ok := val.(string)` |

## Zero-Value Traps

| # | Type | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | `Config` | file:line | Nil map field, no constructor | Add `NewConfig()` constructor |

## Error Wrapping Issues

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `fmt.Errorf("failed: %v", err)` | Use `%w` for unwrappable error |

## Context Misuse

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `context.Background()` in service layer | Accept context from caller |

## Panic/Recover Misuse

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `panic("invalid input")` | Return error instead |

## Race Condition Risks

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | Shared map without mutex | Add sync.RWMutex |

## Recommendations (Priority Order)

1. **Must-fix**: {unchecked errors on critical paths, nil dereference risks, bare type assertions on external data}
2. **Should-fix**: {error wrapping without %w, context misuse, panic in library code}
3. **Consider**: {zero-value documentation, deferred close error handling, race detection in CI}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: invariant enforcement only.** Do not flag type design/architecture (→ type-hunter-go), package boundary issues
  (→ boundary-hunter-go), structural complexity (→ simplicity-hunter-go), interface design (→ solid-hunter-go), missing
  documentation (→ doc-hunter-go), security (→ security-hunter-go), test quality (→ test-hunter-go), or cosmetic style
  (→ slop-hunter-go). If a finding doesn't answer "is this invariant enforced?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Architecture-first.** Understand the project's error handling conventions before flagging violations.
- **Complexity honesty.** Some invariants are expensive to encode in Go's type system. When recommending a runtime
  check, say so explicitly.
- **Challenge assumptions.** If the current approach makes a deliberate trade-off (e.g., panic in must-succeed init),
  acknowledge it rather than mechanically flagging it.
- **Prioritize**: unchecked errors > nil dereferences > bare type assertions > zero-value traps > error wrapping >
  context misuse. Fix the crashing bugs first.
