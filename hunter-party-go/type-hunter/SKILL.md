---
name: type-hunter
description: |
  Audit Go type definitions for design debt — duplicated struct shapes, misused generics,
  under-constrained type parameters, embedding antipatterns, poor enum patterns, and
  disorganized type architecture. Type structure and maintainability.

  Use when: reviewing type definitions for maintainability, reducing type duplication,
  simplifying over-engineered generics, or reorganizing type architecture after growth.
---

# Type Hunter

Audit Go type definitions for **type design debt** — places where types are duplicated instead of composed, generics
are more complex than they need to be, embedding leaks implementation, or type organization has drifted. The goal:
**types are composed from single sources of truth, use the simplest constructs that work, and are easy to find and
maintain.**

## When to Use

- Reviewing type definitions for maintainability after rapid growth
- Reducing type duplication across packages
- Simplifying over-engineered generic types
- Reorganizing type architecture (scattered types, god type files)
- After prototyping, when type definitions need cleanup

## Core Principles

1. **Compose, don't duplicate.** When two types share structure, consider composition: explicit shared fields via a
   common struct, or delegation through a helper function. Prefer explicit field composition over embedding when only
   partial reuse is needed — embedding promotes the full method set, which can leak unintended API surface. Parallel
   struct definitions that duplicate fields are a maintenance trap — a change to one must be replicated in every copy.

2. **Simplest construct wins.** If a concrete type works, don't add a generic. If a struct works, don't use an
   interface. Reach for generics only when the same logic genuinely operates on multiple types. Type-level code
   must be readable and maintainable.

3. **Constraints document intent.** A type parameter `[T any]` accepts anything — it communicates nothing. `[T
   comparable]` or `[T io.Reader]` tells the reader and the compiler what T must be. Every generic should have the
   tightest constraint that works.

4. **Generics must vary.** A type parameter that is always instantiated with the same concrete type is indirection, not
   abstraction. If `Cache[T]` is always `Cache[User]`, remove `T` and use `User` directly. Introduce generics when
   there are 2+ distinct instantiations.

5. **Embedding is composition, not inheritance.** Embedding a struct promotes all its methods and fields. If the outer
   struct only uses 2 of 10 promoted methods, the embedding leaks unnecessary API surface. Embed intentionally; prefer
   explicit field + delegation when only partial access is needed.

6. **Types have a place.** Shared domain types belong in a dedicated package. Implementation-local types belong in their
   package. A 500-line file mixing domain types with internal helpers is disorganized. A type defined in one package but
   used by five others may be misplaced.

## What to Hunt

### 1. Type Duplication

Two or more struct types that represent the same domain concept with the same or near-identical field set.

**Signals:**

- Two structs with matching field names and types in different packages
- A "create" struct and an "update" struct that differ only by one optional field — but note: separate
  request/response types at API boundaries are often intentional (different validation, different consumers). Flag
  only when the types are in the same package serving the same boundary and the separation adds no value
- Request/response types that repeat the entity shape with minor variations in non-boundary code
- Parallel `const` blocks or string sets representing the same values

**Action:** Identify the canonical source type. Derive variants by embedding, composition, or separate request types
that explicitly reference the canonical type. Delete the duplicates.

### 2. Embedding Antipatterns

Struct embedding that leaks implementation details or promotes unintended API surface.

**Signals:**

- Embedding a struct but only using 2-3 of its many methods externally
- Embedding promotes methods that conflict with the outer struct's intended API
- Embedding a mutex (`sync.Mutex`) in an exported struct, promoting `Lock()`/`Unlock()` to the API
- Embedding to "inherit" behavior rather than for genuine composition
- Embedding an interface to partially implement it (relies on nil method panic for unimplemented)

**Action:** Replace embedding with an explicit unexported field and delegate only the needed methods. Embed `sync.Mutex`
only in unexported structs, or use an unexported field.

### 3. Generic Overuse and Misuse

Generic types or functions that are more complex than the problem requires, or generics applied where concrete types
would be simpler.

**Signals:**

- Generic type always instantiated with the same concrete type
- Generic function with a single call site
- Type constraints that are `any` when a narrower constraint would work
- Generic code that immediately type-asserts or type-switches inside (defeating the purpose)
- Generics used for DRY where copy-paste of 5 lines would be clearer

**Action:** Remove the generic and use the concrete type. Tighten constraints. Reserve generics for genuinely
polymorphic data structures and algorithms.

### 4. Poor Enum Patterns

Constant groups that lack type safety, have gaps in iota sequences, or mix concerns.

**Signals:**

- `iota` constants without a named type (bare `const` ints)
- String constants used as enums without validation
- `iota` with gaps or manual assignments that make the sequence fragile
- Missing `String()` method for enum types
- No validation function for enum values received from external input
- Sentinel values (e.g., `Unknown = 0`) that are never checked

**Action:** Define a named type. Use `iota` consistently. Add a `String()` method and a validation function for
external input. Consider using `go generate` with `stringer`.

### 5. Under-Constrained Type Parameters

Generic type parameters with no meaningful constraint.

**Signals:**

- `[T any]` where `T` is always used in a context that assumes comparable or a specific interface
- Generic functions where removing the generic and using the concrete type would work
- Constraints that don't match actual usage: `[T any]` when only `int` and `string` are passed
- Type parameters used in only one position (return only, or parameter only — often removable)

**Action:** Add the tightest constraint that matches actual usage. If the generic accepts only one type, remove it.

### 6. Type Alias and Named Type Confusion

Misuse of type aliases (`=`) vs named types, or missing named types where they'd add clarity.

**Signals:**

- Type alias used where a named type with methods would be more appropriate
- Raw `string` or `int` used for domain identifiers (UserID, OrderID) where a named type would prevent mixing
- Named type that never has methods and doesn't prevent misuse — just adds indirection
- `type X = Y` alias that serves no purpose (not for gradual migration)

**Action:** Use named types for domain identifiers to prevent mixing. Use type aliases only for gradual migration or
compatibility layers. Remove aliases that add no value.

### 7. Type Organization Debt

Type definitions that have drifted into the wrong locations or accumulated into unwieldy files.

**Signals:**

- A single file with 300+ lines mixing domain types, DTOs, internal helpers, and utility types
- Domain types defined inside handler or infrastructure files, imported by domain packages
- The same type imported via different paths (re-exported or duplicated)
- Types in unexpected locations (domain type in an infrastructure package)

**Action:** Collocate implementation-local types with their code. Centralize shared domain types in a domain package.
Split large type files by domain concept. Ensure one canonical import path per type.

## Audit Workflow

### Phase 1: Gain Context

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
2. Identify type-heavy areas: dedicated type files, domain packages, shared type directories.
3. Note the project's type conventions (struct naming, enum patterns, generic usage).

### Phase 2: Scan for Type Design Signals

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/**'

# Struct definitions
rg 'type\s+\w+\s+struct' --type go $EXCLUDE

# Interface definitions
rg 'type\s+\w+\s+interface' --type go $EXCLUDE

# Generic type parameters
rg '\[\w+\s+(any|comparable|\w+\.\w+)' --type go $EXCLUDE

# Type aliases
rg 'type\s+\w+\s*=' --type go $EXCLUDE

# Named types (non-struct, non-interface)
rg 'type\s+\w+\s+(string|int|int64|float64|uint)' --type go $EXCLUDE

# iota enums
rg 'iota' --type go $EXCLUDE

# Embedding
rg '^\s+\*?\w+$' --type go $EXCLUDE

# Large type files
rg -c 'type\s+\w+\s+' --type go $EXCLUDE --sort path

# sync.Mutex embedding
rg 'sync\.(Mutex|RWMutex)' --type go $EXCLUDE
```

### Phase 3: Analyze Duplication

1. Identify structs with overlapping field names across packages.
2. Check for "create/update/response" variants that should compose with a base type.
3. Look for parallel const blocks representing the same value set.

### Phase 4: Evaluate Complexity and Reuse

For each generic type: Is the constraint tight? Does the parameter vary? Is a concrete type simpler?
For each embedding: Is the full promoted surface intentional? Would an explicit field be cleaner?
For each enum pattern: Is the type safe? Is there validation?

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-type-hunter-audit.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Type Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Findings

### Type Duplication

| # | Types | Locations | Overlap | Action |
| - | ----- | --------- | ------- | ------ |
| 1 | `User`, `UserDTO` | file:line, file:line | 8/10 fields identical | Compose DTO from embedded User |

### Embedding Antipatterns

| # | Struct | Location | Embedded Type | Issue | Action |
| - | ------ | -------- | ------------- | ----- | ------ |
| 1 | `Server` | file:line | `sync.Mutex` | Promotes Lock/Unlock to API | Use unexported field |

### Generic Overuse

| # | Type/Function | Location | Parameter | Instantiations | Action |
| - | ------------- | -------- | --------- | -------------- | ------ |
| 1 | `Cache[T]` | file:line | `T any` | Always `User` | Remove generic, use `User` |

### Poor Enum Patterns

| # | Type | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | bare `const` ints | file:line | No named type, no validation | Define named type with iota |

### Under-Constrained Generics

| # | Type/Function | Location | Parameter | Action |
| - | ------------- | -------- | --------- | ------ |
| 1 | `process[T any]()` | file:line | `T` always comparable | Add `comparable` constraint |

### Type Alias Misuse

| # | Type | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | `type UserID = string` | file:line | Alias doesn't prevent mixing with OrderID | Use named type |

### Type Organization

| # | File | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | `types.go` | file:line | 400 lines, mixes domain + internal types | Split by domain concept |

## Recommendations (Priority Order)

1. **Must-fix**: {type duplication with drift risk, embedding leaking sensitive API surface}
2. **Should-fix**: {generic overuse, poor enum patterns, under-constrained generics}
3. **Consider**: {type organization, alias cleanup, named type introduction}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: type design and architecture only.** Do not flag type safety issues like unchecked errors or nil panics
  (→ invariant-hunter), package boundary issues (→ boundary-hunter), interface design (→ solid-hunter), structural
  complexity (→ simplicity-hunter), missing documentation (→ doc-hunter), security (→ security-hunter), test quality
  (→ test-hunter), or cosmetic style (→ slop-hunter). If a finding doesn't answer "is this type well-designed and
  maintainable?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact type definition.
- **Complexity is sometimes justified.** Library-level generics, serialization boundaries, and framework types may
  genuinely need advanced type constructs. Flag the complexity, but acknowledge the justification.
- **Don't over-compose.** Not every type relationship warrants embedding or composition. Two structs with 2 overlapping
  fields out of 10 are not duplicates. Composition should reduce maintenance burden, not create abstraction puzzles.
- **Respect Go's simplicity.** Go deliberately has a smaller type system than languages like Rust or TypeScript. Don't
  recommend type-level solutions that fight the language's design philosophy.
