---
name: solid-hunter-go
description: |
  Audit Go code for design principle violations — god packages, rigid extension points,
  broken interface contracts, fat interfaces, and concrete dependency chains. Adapted from
  SOLID for Go's composition-over-inheritance model.

  Use when: reviewing package structure, preparing for extension with new variants,
  reducing coupling between packages, or improving testability.
disable-model-invocation: true
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
- **Cohesive domain aggregates** — a struct with many methods is not a god struct if those methods all operate on the
  same data for the same workflow. Evaluate *cohesion*, not method count. If the struct's methods form a single
  transaction boundary (e.g., state mutation + rule execution + audit logging that are inseparable), it is a cohesive
  aggregate, not an SRP violation. Split only when responsibilities can change independently.
- **Small switch dispatchers** — a switch statement with ≤3 cases in ≤2 locations is not an OCP violation worth a
  strategy registry. The cost of a registry (type definitions, registration, lookup) exceeds the cost of maintaining
  a small switch. Flag only when the switch has 4+ cases AND appears in 3+ distinct locations.
- **Composition roots** — direct instantiation of concrete types in the composition root (`main()`, `RegisterEndpoints`,
  `cmd/` setup functions) is correct wiring, not a DIP violation. DIP applies to business logic and domain packages,
  not to the place where dependencies are assembled. Do not recommend interfaces or DI containers for composition roots
  with a single implementation per dependency.

## What to Hunt

### 1. SRP Violations — God Packages and God Structs

Packages or structs that accumulate responsibilities from multiple domain concerns.

SRP here is *responsibility and change analysis* — multiple actors, independent reasons to change, constructor
fan-in. Package *naming and organization* (vague names like `utils`/`common`, name-vs-directory mismatches) is
owned by boundary-hunter-go §7; the two lenses should produce different findings for the same package.

**Signals:**

- Package serving multiple actors — changes requested by different stakeholders land in the same files
- Struct with 10+ methods spanning different domain concepts
- Constructor (`New*`) with 5+ dependencies (high fan-in = multiple reasons to change)
- Package that imports from many unrelated packages (persistence, HTTP, formatting, crypto)

**Action:** Identify distinct responsibilities. Extract each into a focused package. The original package becomes a
coordinator that delegates, or is dissolved entirely.

### 2. OCP Violations — Rigid Extension Points

Code that must be modified — not extended — when a new variant, strategy, or behavior is added.

**Signals:**

- `switch`/`if-else` chains on a type discriminant that appear in 3+ locations across the codebase
- Adding a new variant requires editing multiple files beyond the variant definition itself
- Hard-coded strategy selection (`if typ == "email" { sendEmail() } else if typ == "sms" { sendSMS() }`)
- Factory functions with growing `switch` statements and no registration mechanism
- Boolean parameters that select between behaviors *that will grow variants* (a genuine OCP setup — a bool that
  will become a three-way choice). Boolean-parameter findings in general are owned by simplicity-hunter-go, which
  carries the calibrated do-not-flag rule; claim only this growth case here, with a cross-reference

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
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project (the default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot (a resolved file list), use it verbatim and do
   not re-resolve. The resolution below applies to standalone runs only.

   For diff mode, resolve fail-closed:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
   if [ -z "$BASE" ]; then
     for b in origin/main origin/master main master; do
       git rev-parse -q --verify "$b" >/dev/null && BASE=$b && break
     done
   fi
   # If BASE is still empty: STOP. Ask for an explicit base. Do not continue.

   SCOPE=$( { git diff --name-only --diff-filter=d "$BASE"...HEAD;
              git diff --name-only --diff-filter=d HEAD;
              git ls-files --others --exclude-standard; } | sort -u )
   DELETED=$( { git diff --name-only --diff-filter=D "$BASE"...HEAD;
                git diff --name-only --diff-filter=D HEAD; } | sort -u )
   ```
   If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope",
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop. If the resolved surface exceeds what can be
   read within the context budget, report the file count and ask to narrow or chunk.

   **Two surfaces.** Consumer counting (ISP "avg used by consumers", OCP occurrence counts, implementation
   enumeration) legitimately runs project-wide — an interface's consumers live outside any diff scope. Findings
   are still *reported* only against the target scope: every finding anchors (file:line) there.
2. Identify whether the project uses struct-based architecture (services, repositories, handlers) or
   functional-style composition. If primarily functional, note this in the report — SOLID findings will be limited.
3. Identify the composition root (where dependencies are wired: `main()`, `cmd/`, wire/fx setup).

### Phase 2: Scan for SOLID Signals

Run the anchoring scans against the target scope (`SCOPE=.` in codebase mode); consumer-counting follow-ups may
search project-wide.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Structs (starting point for SRP, DIP analysis)
rg 'type\s+\w+\s+struct' --type go $EXCLUDE -- $SCOPE

# Interfaces (starting point for ISP analysis)
rg 'type\s+\w+\s+interface' --type go $EXCLUDE -- $SCOPE

# Embedding (composition relationships): no reliable regex exists — bare-identifier patterns match
# return/break/continue, and qualified embeds (sync.Mutex, pkg.Client) defeat case anchoring.
# Enumerate the `type X struct` sites found above and inspect their bodies by eye.

# Direct instantiation in non-factory code (DIP signal)
rg '&\w+\{|new\(\w+\)' --type go $EXCLUDE -- $SCOPE

# Type assertions/switches (LSP signal — consumer sniffing implementations)
rg '\.\(\w+\)|switch\s+\w+\.\(type\)' --type go $EXCLUDE -- $SCOPE

# switch chains on discriminants (OCP signal)
rg 'switch\s+\w+' --type go $EXCLUDE -- $SCOPE

# Not-implemented panics (LSP signal)
rg -i 'not.?implemented|unsupported|panic\(' --type go $EXCLUDE -- $SCOPE
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

Save as `YYYY-MM-DD-solid-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies an
output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# SOLID Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings
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

1. **High**: {god packages with 5+ responsibilities, broken interface contracts causing panics}
2. **Medium**: {rigid extension points touched by every new variant, fat interfaces with no-op methods}
3. **Low**: {concrete dependency chains limiting testability, speculative interface splits}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: struct, interface, and package design only.** If a finding doesn't answer "is this type/package designed
  for change?", it belongs to another hunter — do not flag it here. Named boundaries: package naming/organization
  belongs to boundary-hunter-go (§1 here keeps responsibility/change analysis); boolean parameters belong to
  simplicity-hunter-go except the will-grow-variants OCP case (§2).
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Pragmatism over dogma.** SOLID principles exist to manage change, not to achieve theoretical purity. A struct with
  two related responsibilities that change together is fine. An interface with five methods that every implementor uses
  fully is fine. Flag violations that create real maintenance friction, not cosmetic deviations.
- **Respect Go idioms.** Go favors small interfaces defined at the consumer, composition over inheritance, and explicit
  wiring in `main()`. Calibrate findings to Go's design philosophy, not Java/C# SOLID patterns.
- **Tension with simplicity-hunter is expected.** SOLID may recommend adding an interface where simplicity-hunter would
  recommend removing one. Both are valid lenses. Flag the design issue; let the team decide the trade-off.
