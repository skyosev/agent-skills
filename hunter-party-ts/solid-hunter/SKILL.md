---
name: solid-hunter
description: |
  Audit TypeScript class and interface design for SOLID violations — god classes, rigid
  extension points, broken substitutability, fat interfaces, and concrete dependency
  chains. Focuses on responsibility assignment and abstraction fitness.

  Use when: reviewing class hierarchies, preparing for extension with new variants,
  reducing coupling between services, or improving testability of class-heavy code.
---

# SOLID Hunter

Audit TypeScript code for **SOLID principle violations** at the class and interface level — places where
responsibilities are misassigned, extension requires modification, subtypes break contracts, interfaces force unused
dependencies, or classes are wired to concrete implementations. The goal: **classes have clear responsibilities,
extend without modification, substitute safely, expose cohesive interfaces, and depend on abstractions.**

## When to Use

- Reviewing class hierarchies and inheritance structures
- Preparing a codebase for extension with new variants or strategies
- Reducing coupling between service classes
- Improving testability by enabling dependency injection
- After prototyping, when class responsibilities need sharpening

## Core Principles

1. **Single Responsibility (SRP).** A class should have one reason to change — one actor, one domain concern. When a
   class serves multiple actors (e.g., persistence AND presentation), changes for one actor risk breaking the other.
   This is about *responsibility assignment*, not function count.

2. **Open/Closed (OCP).** A class should be open for extension but closed for modification. Adding a new variant or
   behavior should not require editing existing code. Extension points — strategy interfaces, plugin hooks, polymorphic
   dispatch — allow new behavior without touching proven code.

3. **Liskov Substitution (LSP).** A subtype must be usable wherever its base type is expected, without the caller
   knowing or caring. Overrides must honor the base contract: same preconditions or weaker, same postconditions or
   stronger. If a subclass throws on an inherited method or silently ignores it, the substitution is broken.

4. **Interface Segregation (ISP).** No client should be forced to depend on methods it does not use. Fat interfaces
   that bundle unrelated capabilities force implementors into stub methods and callers into unnecessary coupling. Split
   into role-specific interfaces that each describe one capability.

5. **Dependency Inversion (DIP).** High-level policy should not depend on low-level detail — both should depend on
   abstractions. When a service class `new`s its own dependencies or accepts concrete types in its constructor, it
   becomes untestable and unchangeable without editing the class itself.

### Pragmatic Boundaries

SOLID principles are guidelines for managing change, not rules to apply universally. Do not flag:

- **Value objects and DTOs** — data carriers don't need DIP or ISP; they are the data.
- **Single-implementation interfaces** created speculatively — an interface with no second implementation and no test
  double is premature abstraction (simplicity-hunter territory).
- **Functional-style code** — modules that use plain functions and composition rather than classes are not SOLID
  violations; SOLID applies to class-based design.
- **Exhaustive switches on closed discriminated unions** — when the union is intentionally finite and every consumer
  handles all variants, this is not an OCP violation. Flag only when the switch appears in many places and new variants
  require editing all of them.

## What to Hunt

### 1. SRP Violations — God Classes

Classes that accumulate responsibilities from multiple domain concerns, becoming the "hub" that everything touches.

**Signals:**

- Class with 10+ public methods spanning different domain concepts
- Constructor with 5+ dependencies (high fan-in = multiple reasons to change)
- Class that imports from many unrelated modules (e.g., persistence, HTTP, formatting)
- Filename or class name that uses vague terms: `Manager`, `Handler`, `Service`, `Utils`, `Helper` with broad scope
- Class where half the methods don't use half the fields

**Action:** Identify distinct responsibilities. Extract each into a focused class. The original class becomes a
coordinator that delegates, or is dissolved entirely.

### 2. OCP Violations — Rigid Extension Points

Code that must be modified — not extended — when a new variant, strategy, or behavior is added.

**Signals:**

- `switch`/`if-else` chains on a type discriminant that appear in 3+ locations across the codebase
- Adding a new variant requires editing multiple files beyond the variant definition itself
- Hard-coded strategy selection (`if (type === 'email') sendEmail(); else if (type === 'sms') sendSms();`)
- Factory methods with growing `switch` statements and no registration mechanism
- Boolean parameters that toggle between two fundamentally different behaviors

**Action:** Introduce a strategy/plugin pattern: define an interface for the variant behavior, implement per variant,
dispatch polymorphically. The core class should not know about individual variants.

### 3. LSP Violations — Broken Substitution

Subclasses or interface implementations that violate the contract of their base type.

**Signals:**

- Override method that throws `NotImplementedError`, `UnsupportedOperationError`, or similar
- Override that silently returns a no-op value (empty array, null) instead of performing the base behavior
- Subclass that narrows accepted input beyond what the base type declares
- Subclass that widens error cases (throws where base does not)
- `instanceof` checks in consumer code to handle a specific subclass differently

**Action:** If the subclass genuinely cannot support the base contract, the inheritance is wrong. Extract the shared
behavior into a separate interface or use composition instead of inheritance.

### 4. ISP Violations — Fat Interfaces

Interfaces that bundle unrelated capabilities, forcing implementors to depend on methods they don't use.

**Signals:**

- Interface with 8+ methods where implementors leave some as stubs or throw
- A class that implements an interface but only uses 2-3 of its methods
- Interface that combines query methods (read) with command methods (write) when some consumers only read
- "God interface" pattern: one interface for an entire subsystem

**Action:** Split into role-specific interfaces (e.g., `Readable`, `Writable` instead of `ReadWriteStore`). Clients
depend only on the interface slice they use.

### 5. DIP Violations — Concrete Dependency Chains

High-level classes that directly depend on low-level implementations instead of abstractions.

**Signals:**

- `new ConcreteService()` inside a class method (not a factory or composition root)
- Constructor parameter typed as a concrete class instead of an interface
- Direct imports of infrastructure implementations (database client, HTTP library) in domain/application classes
- Static method calls to concrete utility classes that could be injected

**Action:** Define an interface for the dependency. Accept the interface in the constructor. Wire the concrete
implementation at the composition root (app startup, DI container, factory).

**Note:** Direct instantiation of value objects, data structures, and builders is fine — DIP applies to *service*
dependencies that represent behavior, not data construction.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. Identify whether the project uses class-based architecture (services, repositories, controllers) or
   functional-style composition. If primarily functional, note this in the report — SOLID findings will be limited.
3. Identify the composition root (where dependencies are wired: DI container, app entry point, factory modules).

### Phase 2: Scan for SOLID Signals

```bash
EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/** --glob !**/dist/**'

# Classes (starting point for SRP, DIP analysis)
rg 'class\s+\w+' --type ts $EXCLUDE

# Interfaces (starting point for ISP analysis)
rg 'interface\s+\w+' --type ts $EXCLUDE

# extends / implements (inheritance and interface relationships)
rg 'extends\s+\w+|implements\s+\w+' --type ts $EXCLUDE

# Direct instantiation in non-factory code (DIP signal)
rg 'new\s+[A-Z]\w+\(' --type ts $EXCLUDE

# instanceof checks (LSP signal — caller sniffing subtypes)
rg 'instanceof\s+\w+' --type ts $EXCLUDE

# switch/if-else chains on discriminants (OCP signal)
rg 'switch\s*\(' --type ts $EXCLUDE

# NotImplemented / Unsupported throws (LSP signal)
rg -i 'not.?implemented|unsupported' --type ts $EXCLUDE
```

### Phase 3: Evaluate Each Class and Interface

For each class found in Phase 2:

- **SRP**: How many distinct responsibilities does it serve? Would a change from one actor require touching methods
  used by another?
- **OCP**: If a new variant were added, how many files would need to change? Is this class one of them?
- **DIP**: Are constructor dependencies typed as interfaces or concrete classes? Does it `new` its own service
  dependencies?

For each interface:

- **ISP**: How many methods? Do all implementors use all methods? Are there stub implementations?

For each inheritance relationship:

- **LSP**: Does the subclass fully honor the base contract? Are there `instanceof` checks that work around broken
  substitution?

### Phase 4: Produce Report

## Output Format

Save as `Y-m-d-solid-hunter-audit.md` in the project's docs folder.

```md
# SOLID Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- Architecture style: {class-based / mixed / functional (limited findings)}

## SRP Violations — God Classes

| # | Class | Location | Responsibilities | Dependencies | Action |
| - | ----- | -------- | ---------------- | ------------ | ------ |
| 1 | `OrderService` | file:line | order CRUD + email + invoicing | 7 injected | Split into 3 focused services |

## OCP Violations — Rigid Extension Points

| # | Location | Pattern | Occurrences | Action |
| - | -------- | ------- | ----------- | ------ |
| 1 | file:line | `switch(type)` with 5 variants in 4 files | 4 | Extract strategy interface |

## LSP Violations — Broken Substitution

| # | Class | Base | Location | Violation | Action |
| - | ----- | ---- | -------- | --------- | ------ |
| 1 | `ReadOnlyRepo` | `Repository` | file:line | `save()` throws NotImplemented | Use composition, not inheritance |

## ISP Violations — Fat Interfaces

| # | Interface | Location | Methods | Avg Used by Implementors | Action |
| - | --------- | -------- | ------- | ------------------------ | ------ |
| 1 | `DataStore` | file:line | 12 | 5 | Split into `Reader` + `Writer` + `Admin` |

## DIP Violations — Concrete Dependencies

| # | Class | Location | Concrete Dependency | Action |
| - | ----- | -------- | ------------------- | ------ |
| 1 | `UserService` | file:line | `new EmailClient()` | Inject via constructor interface |

## Recommendations (Priority Order)

1. **Must-fix**: {god classes with 5+ responsibilities, broken substitution causing runtime errors}
2. **Should-fix**: {rigid extension points touched by every new variant, fat interfaces with stub methods}
3. **Consider**: {concrete dependency chains limiting testability, speculative interface splits}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: class and interface design only.** Do not flag module boundary issues (→ boundary-hunter), type invariants
  (→ invariant-hunter), type design (→ type-hunter), structural complexity (→ simplicity-hunter), missing documentation
  (→ doc-hunter), security (→ security-hunter), test quality (→ test-hunter), or cosmetic style (→ slop-hunter).
  If a finding doesn't answer "is this class/interface designed for change?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Pragmatism over dogma.** SOLID principles exist to manage change, not to achieve theoretical purity. A class with
  two related responsibilities that change together is fine. An interface with five methods that every implementor uses
  fully is fine. Flag violations that create real maintenance friction, not cosmetic deviations.
- **Respect the architecture.** Some codebases deliberately use a thin-class style, or avoid DI in favor of module-level
  composition. Note the style and calibrate findings accordingly.
- **Tension with simplicity-hunter is expected.** SOLID may recommend adding an abstraction where simplicity-hunter would
  recommend removing one. Both are valid lenses. Flag the design issue; let the team decide the trade-off.
