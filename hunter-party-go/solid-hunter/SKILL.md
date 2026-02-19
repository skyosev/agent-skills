---
name: solid-hunter
description: |
  Audit Go code for design principle violations — god packages, rigid extension points,
  broken interface contracts, fat interfaces, and concrete dependency chains. Adapted from
  SOLID for Go's composition-over-inheritance model.

  Use when: reviewing package structure, preparing for extension with new variants,
  reducing coupling between packages, or improving testability.
---

# SOLID Hunter

Audit Go code for **design principle violations** at the package, struct, and interface level — places where
responsibilities are misassigned, extension requires modification, interface contracts are broken, interfaces force
unused dependencies, or structs are wired to concrete implementations. The goal: **packages have clear responsibilities,
extend without modification, honor interface contracts, expose cohesive interfaces, and depend on abstractions.**

Go does not have classes or inheritance, so SOLID applies differently than in object-oriented languages. SRP applies to
packages and structs. OCP applies through interfaces and composition. LSP applies to interface implementations. ISP is
already a Go strength ("accept interfaces, return structs") — but fat interfaces still occur. DIP applies through
constructor injection of interfaces.

## When to Use

- Reviewing package structure and responsibility assignment
- Preparing a codebase for extension with new variants or strategies
- Reducing coupling between packages
- Improving testability by enabling dependency injection
- After prototyping, when package responsibilities need sharpening

## Core Principles

1. **Single Responsibility (SRP).** A package should have one reason to change — one domain concern. When a package
   serves multiple actors (e.g., persistence AND HTTP handling AND business rules), changes for one concern risk
   breaking another. For structs: a struct with 10+ methods spanning different concerns is a god struct. This is about
   *responsibility assignment*, not function count.

2. **Open/Closed (OCP).** A package should be open for extension but closed for modification. Adding a new variant or
   behavior should not require editing existing code. In Go, this is achieved through interfaces, function types, and
   composition — not inheritance hierarchies.

3. **Liskov Substitution (LSP).** Any type implementing an interface must fulfill the full contract implied by that
   interface. If a type implements an interface but panics on certain methods or returns hardcoded zero values, the
   contract is broken. Go's implicit interface satisfaction makes this easy to violate — a type can satisfy an interface
   syntactically without honoring its semantics.

4. **Interface Segregation (ISP).** No consumer should be forced to depend on methods it does not use. Go's idiom of
   small, focused interfaces (`io.Reader`, `io.Writer`, `fmt.Stringer`) is the standard. Fat interfaces that bundle
   unrelated capabilities force implementors into stub methods and callers into unnecessary coupling.

5. **Dependency Inversion (DIP).** High-level policy should not depend on low-level detail — both should depend on
   abstractions (interfaces). When a struct creates its own dependencies with `&ConcreteService{}` or accepts concrete
   types in its constructor, it becomes untestable and unchangeable.

### Pragmatic Boundaries

SOLID principles are guidelines for managing change, not rules to apply universally. Do not flag:

- **Value types and DTOs** — data carriers don't need DIP or ISP; they are the data.
- **Single-implementation interfaces** created speculatively — an interface with no second implementation and no test
  double is premature abstraction (simplicity-hunter territory). Note: DIP may recommend introducing an interface for
  a dependency to enable testing. The distinction is intent.
- **Functional-style code** — packages that use plain functions and closures rather than structs with methods are not
  SOLID violations; SOLID applies to struct-and-interface design.
- **Exhaustive type switches on sealed interfaces** — when the set of types is intentionally finite and every consumer
  handles all variants, this is not an OCP violation. Flag only when the switch appears in many places and new variants
  require editing all of them.

## What to Hunt

### 1. SRP Violations — God Packages and God Structs

Packages or structs that accumulate responsibilities from multiple domain concerns.

**Signals:**

- Package with files spanning different domain concepts (e.g., `user.go`, `email.go`, `billing.go` in same package)
- Struct with 10+ methods spanning different domain concepts
- Constructor (`New*`) with 5+ dependencies (high fan-in = multiple reasons to change)
- Package that imports from many unrelated packages (persistence, HTTP, formatting, crypto)
- Package name using vague terms: `utils`, `helpers`, `common`, `misc`, `service` with broad scope

**Action:** Identify distinct responsibilities. Extract each into a focused package. The original package becomes a
coordinator that delegates, or is dissolved entirely.

### 2. OCP Violations — Rigid Extension Points

Code that must be modified — not extended — when a new variant, strategy, or behavior is added.

**Signals:**

- `switch`/`if-else` chains on a type discriminant that appear in 3+ locations across the codebase
- Adding a new variant requires editing multiple files beyond the variant definition itself
- Hard-coded strategy selection (`if typ == "email" { sendEmail() } else if typ == "sms" { sendSMS() }`)
- Factory functions with growing `switch` statements and no registration mechanism
- Boolean parameters that toggle between two fundamentally different behaviors

**Action:** Introduce an interface for the variant behavior, implement per variant, dispatch polymorphically via a map
or registry. The core package should not know about individual variants.

### 3. LSP Violations — Broken Interface Contracts

Types that implement an interface syntactically but violate its semantic contract.

**Signals:**

- Method implementation that panics with "not implemented" or "unsupported"
- Implementation that silently returns a zero value instead of performing the expected behavior
- Implementation that narrows accepted input beyond what the interface implies
- Implementation that returns errors where the interface contract implies success
- Type assertions or type switches in consumer code to handle a specific implementation differently

**Action:** If the type genuinely cannot support the interface contract, it shouldn't implement it. Use composition or
a narrower interface instead.

### 4. ISP Violations — Fat Interfaces

Interfaces that bundle unrelated capabilities, forcing implementors to depend on methods they don't use.

**Signals:**

- Interface with 6+ methods where implementors leave some as no-ops or panics
- A struct that accepts an interface but only calls 1-2 of its methods
- Interface that combines read methods with write methods when some consumers only read
- "God interface" pattern: one interface for an entire subsystem
- Interface defined in the consumer's package that mirrors the full API of a dependency

**Action:** Split into role-specific interfaces. Go's idiom: define interfaces where they are consumed, not where they
are implemented. `io.Reader` and `io.Writer` exist separately for a reason.

### 5. DIP Violations — Concrete Dependency Chains

Structs that directly depend on concrete implementations instead of interfaces.

**Signals:**

- `&ConcreteService{}` inside a constructor or method (not a composition root)
- Constructor parameter typed as a concrete struct instead of an interface
- Direct imports of infrastructure implementations (database driver, HTTP client) in domain packages
- Package-level `var db = sql.Open(...)` used directly in business logic

**Action:** Define a small interface in the consumer package. Accept the interface in the constructor. Wire the concrete
implementation at the composition root (`main`, `cmd/`, wire setup).

**Note:** Direct instantiation of value types, slices, maps, and builders is fine — DIP applies to *service*
dependencies that represent behavior, not data construction.

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
2. Identify whether the project uses struct-based architecture (services, repositories, handlers) or
   functional-style composition. If primarily functional, note this in the report — SOLID findings will be limited.
3. Identify the composition root (where dependencies are wired: `main()`, `cmd/`, wire/fx setup).

### Phase 2: Scan for SOLID Signals

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/**'

# Structs (starting point for SRP, DIP analysis)
rg 'type\s+\w+\s+struct' --type go $EXCLUDE

# Interfaces (starting point for ISP analysis)
rg 'type\s+\w+\s+interface' --type go $EXCLUDE

# Embedding (composition relationships)
rg '^\s+\w+\.\w+$|^\s+\*?\w+$' --type go $EXCLUDE

# Direct instantiation in non-factory code (DIP signal)
rg '&\w+\{|new\(\w+\)' --type go $EXCLUDE

# Type assertions/switches (LSP signal — consumer sniffing implementations)
rg '\.\(\w+\)|switch\s+\w+\.\(type\)' --type go $EXCLUDE

# switch chains on discriminants (OCP signal)
rg 'switch\s+\w+' --type go $EXCLUDE

# Not-implemented panics (LSP signal)
rg -i 'not.?implemented|unsupported|panic\(' --type go $EXCLUDE
```

### Phase 3: Evaluate Each Struct and Interface

For each struct found in Phase 2:

- **SRP**: How many distinct responsibilities does it serve? Would a change from one concern require touching methods
  used by another?
- **OCP**: If a new variant were added, how many files would need to change? Is this struct one of them?
- **DIP**: Are constructor dependencies typed as interfaces or concrete structs? Does it create its own service
  dependencies?

For each interface:

- **ISP**: How many methods? Do all implementors use all methods? Are there no-op implementations?

For each interface implementation:

- **LSP**: Does the type fully honor the interface contract? Are there type assertions that work around broken
  contracts?

### Phase 4: Produce Report

## Output Format

Save as `YYYY-MM-DD-solid-hunter-audit.md` in the project's docs folder (or project root if no docs folder exists).

```md
# SOLID Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- Architecture style: {struct-based / mixed / functional (limited findings)}

## SRP Violations — God Packages/Structs

| # | Package/Struct | Location | Responsibilities | Dependencies | Action |
| - | -------------- | -------- | ---------------- | ------------ | ------ |
| 1 | `OrderService` | file:line | order CRUD + email + invoicing | 7 injected | Split into 3 focused packages |

## OCP Violations — Rigid Extension Points

| # | Location | Pattern | Occurrences | Action |
| - | -------- | ------- | ----------- | ------ |
| 1 | file:line | `switch typ` with 5 variants in 4 files | 4 | Extract strategy interface |

## LSP Violations — Broken Interface Contracts

| # | Type | Interface | Location | Violation | Action |
| - | ---- | --------- | -------- | --------- | ------ |
| 1 | `ReadOnlyStore` | `Store` | file:line | `Save()` panics | Use narrower interface |

## ISP Violations — Fat Interfaces

| # | Interface | Location | Methods | Avg Used by Consumers | Action |
| - | --------- | -------- | ------- | --------------------- | ------ |
| 1 | `DataStore` | file:line | 12 | 3 | Split into `Reader` + `Writer` + `Admin` |

## DIP Violations — Concrete Dependencies

| # | Struct | Location | Concrete Dependency | Action |
| - | ------ | -------- | ------------------- | ------ |
| 1 | `UserService` | file:line | `&EmailClient{}` | Inject via constructor interface |

## Recommendations (Priority Order)

1. **Must-fix**: {god packages with 5+ responsibilities, broken interface contracts causing panics}
2. **Should-fix**: {rigid extension points touched by every new variant, fat interfaces with no-op methods}
3. **Consider**: {concrete dependency chains limiting testability, speculative interface splits}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: struct, interface, and package design only.** Do not flag package boundary issues (→ boundary-hunter), type
  safety (→ invariant-hunter), type design (→ type-hunter), structural complexity (→ simplicity-hunter), missing
  documentation (→ doc-hunter), security (→ security-hunter), test quality (→ test-hunter), or cosmetic style
  (→ slop-hunter). If a finding doesn't answer "is this type/package designed for change?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Pragmatism over dogma.** SOLID principles exist to manage change, not to achieve theoretical purity. A struct with
  two related responsibilities that change together is fine. An interface with five methods that every implementor uses
  fully is fine. Flag violations that create real maintenance friction, not cosmetic deviations.
- **Respect Go idioms.** Go favors small interfaces defined at the consumer, composition over inheritance, and explicit
  wiring in `main()`. Calibrate findings to Go's design philosophy, not Java/C# SOLID patterns.
- **Tension with simplicity-hunter is expected.** SOLID may recommend adding an interface where simplicity-hunter would
  recommend removing one. Both are valid lenses. Flag the design issue; let the team decide the trade-off.
