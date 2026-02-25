---
name: smell-hunter-go
description: |
  Audit Go code for classic code smells — feature envy, data clumps, shotgun surgery,
  primitive obsession, temporal coupling, comments as deodorant, temporary fields, init()
  abuse, package-level mutable state, and stuttering names.

  Use when: reviewing Go code for structural design problems, preparing for a refactor,
  auditing code after rapid feature development, or hunting for misplaced responsibilities.
---

# Smell Hunter

Audit Go code for **code smells** — structural patterns that indicate deeper design problems. This covers selected
Fowler/Beck smells and Go-specific antipatterns that fall outside the scope of specialized hunters (SOLID, type design,
boundaries, invariants, etc.). The goal: **data lives where it's used, changes are localized, domain concepts are
modeled explicitly, and Go idioms are respected.**

**Not covered (owned by other hunters):** long method / mixed concerns (→ simplicity-hunter), dead code
(→ simplicity-hunter / slop-hunter), speculative generality (→ simplicity-hunter), magic numbers (→ doc-hunter),
interface pollution (→ simplicity-hunter / solid-hunter). See Operating Constraints for handoff rules.

Code smells are symptoms, not diagnoses. Each finding indicates a *likely* design problem that warrants investigation.
Context determines whether the smell is a genuine issue or an acceptable trade-off.

## When to Use

- Reviewing code for structural design problems before a refactor
- Auditing code after rapid feature development or prototyping
- Hunting for misplaced responsibilities and data
- Identifying missing domain types and abstractions
- Preparing a codebase for long-term maintainability
- Complementing specialized hunters with cross-cutting smell detection

## Core Principles

1. **Smells are symptoms, not diseases.** A code smell indicates a probable design problem, not a guaranteed one.
   Evaluate each smell in context — some are intentional trade-offs. The goal is awareness, not mechanical elimination.

2. **Follow the data.** Feature envy, data clumps, and primitive obsession all point to misplaced or undermodeled data.
   When data and behavior want to be together, let them. When a group of values always travels together, they are a
   missing type.

3. **One change, one place.** Shotgun surgery means a single logical change requires edits across many unrelated files.
   This is the hallmark of misaligned module boundaries or scattered responsibilities. The fix is cohesion.

4. **Comments should not be deodorant.** A comment explaining confusing code is a band-aid over a design problem. The
   fix is clearer code — better names, extracted functions, simpler structure — not more comments.

5. **Model the domain.** Primitive obsession and data clumps often indicate missing domain types. A `string` that
   represents an email address, a pair of `float64`s that represent a coordinate, or a group of parameters that
   always appear together — these are domain concepts begging for a type.

6. **Respect Go idioms.** Go has specific conventions: no stuttering names, minimal init(), explicit state management,
   composition over inheritance. Language-specific smells are as important as universal ones.

7. **Refactor incrementally.** Split by responsibility, not by size. Introduce abstraction only when needed (wait for
   the second use case). Preserve behavior first — add tests before restructuring.

## What to Hunt

### 1. Feature Envy

A function or method that uses more data from another package or struct than from its own receiver or local state.

**Signals:**

- Method on struct A that primarily accesses fields/methods of struct B (passed as parameter)
- Function that accesses many fields of a struct from another package
- Helper function that exists in package A but only operates on types from package B
- Method that receives a struct and calls 3+ of its methods while using none of its own receiver's fields
- A function whose name suggests it belongs to the type it operates on, not the package it lives in

**Action:** Move the function to the package that owns the data it operates on (you can only define methods on types
in the same package — move the function near its data, minding import cycles). If it uses data from two types equally,
consider whether the shared data should be extracted into its own type.

### 2. Data Clumps

The same group of parameters or fields that always appear together across multiple function signatures or struct
definitions.

**Signals:**

- 3+ parameters that appear together in multiple function signatures (e.g., `host`, `port`, `scheme` or
  `latitude`, `longitude`, `altitude`)
- Multiple structs with the same subset of fields (e.g., `Street`, `City`, `Zip`, `Country` in several types)
- Functions that pass a group of related values individually instead of as a struct
- Struct with fields that form a logical sub-group (e.g., `StartDate`, `EndDate`, `Timezone` inside a larger config)

**Action:** Extract the group into a named struct. Replace the individual parameters/fields with the struct. If the
group appears only in function signatures, create a parameter struct. If it appears in multiple struct definitions,
extract a shared embedded or composed type.

### 3. Shotgun Surgery

A single logical change requires edits across many unrelated files or packages.

**Signals:**

- Adding a new field to a domain type requires updating 5+ files (handlers, validators, mappers, tests, serializers)
- Adding a new error type requires changes in the error package, every handler, and every test
- A config change requires editing code in multiple packages rather than just the config package
- Renaming a concept requires find-and-replace across the entire codebase
- A new feature flag requires changes in config, middleware, handlers, and templates

**Action:** Consolidate the scattered responsibility. If a change to concept X requires touching packages A, B, C, D,
and E, then X's logic is spread too thin. Consider:
- A registry or map-based dispatch instead of scattered switch cases
- Code generation for boilerplate that varies with each new type/field
- A single package that owns the concept end-to-end

### 4. Primitive Obsession

Using primitive types (`string`, `int`, `float64`, `bool`) for domain concepts that deserve their own named types.

**Signals:**

- Functions that accept `string` parameters for IDs, emails, URLs, currencies, or status codes
- Functions where two `string` or `int` parameters could be accidentally swapped (e.g., `Transfer(from, to string,
  amount int)`)
- Validation logic for a "typed" string scattered across multiple call sites instead of enforced at construction
- `float64` used for money calculations (precision loss)
- `int` used for durations without unit clarity (seconds? milliseconds?)
- Boolean parameters that control behavior: `Process(data []byte, compress bool, encrypt bool)`
- Raw `string` comparisons for status/state values instead of typed constants

**Action:** Define a named type: `type UserID string`, `type Email string`, `type Money int64` (cents). Add a
constructor that validates. The type system then prevents mixing `UserID` with `OrderID` at compile time. For boolean
flags, consider typed constants with `iota` or functional options.

### 5. Temporal Coupling

Functions or operations that must be called in a specific order, but nothing in the API enforces that order.

**Signals:**

- A struct with `Init()`, `Setup()`, or `Configure()` methods that must be called before `Run()` or `Process()`
- Documentation or comments that say "must call X before Y"
- Panic or nil dereference when methods are called in the wrong order
- A builder pattern where `Build()` can be called before required fields are set
- State machine transitions that are valid only from certain states but not enforced by the API

**Action:** Redesign the API to make the order implicit:
- Use constructor functions that return a fully initialized struct
- Use the builder pattern with a `Build()` that validates all required fields
- Use state-machine types where each state is a different type with only valid transitions as methods
- Accept dependencies in the constructor rather than via separate `Set*` methods

### 6. Comments as Deodorant

Comments that explain *what* confusing code does rather than *why* — masking a design problem instead of fixing it.

**Signals:**

- A comment like `// Convert the user data to the format expected by the billing system` above a 20-line block that
  should be an extracted function named `toBillingFormat()`
- Comments that explain complex boolean expressions rather than extracting them into named functions
- Inline comments at each step of a long function, effectively creating "sections" that should be separate functions
- Comments explaining workarounds for the code's own design rather than external constraints
- `// This is confusing because...` — if you're writing this comment, refactor instead

**Action:** Replace the comment with a code change:
- Extract the commented block into a function with an intent-revealing name
- Replace complex expressions with named variables or helper functions
- Split long functions at the comment boundaries into named sub-functions
- Only keep comments that explain *why* (business rules, external constraints, workarounds for third-party bugs)

### 7. Temporary Field

Struct fields that are meaningful only in certain states or during specific operations — they are set for one code
path and nil/zero for all others.

**Signals:**

- Struct field that is non-nil in only one of several code paths
- Fields that are set in method A and read in method B but meaningless in methods C, D, E
- Optional fields that exist because the struct is used in multiple contexts with different data requirements
- Fields documented as "only valid when X is true" or "set only during processing"
- Struct with fields like `tempResult`, `cachedX`, `lastError` that serve a single transient use

**Action:** Extract the temporary fields into a separate struct used only where needed. If the struct represents
multiple states, use a discriminated pattern: separate structs for each state, or a method-scoped local variable
instead of a field.

### 8. init() Abuse

Complex logic, side effects, or non-trivial initialization in `init()` functions.

**Signals:**

- `init()` that opens database connections, network sockets, or file handles
- `init()` that reads environment variables or configuration files
- `init()` with error handling (errors in init cannot be returned, only panicked)
- `init()` that registers global state (e.g., `http.HandleFunc` in library code)
- Multiple `init()` functions in the same package with ordering dependencies
- `init()` that makes the package untestable (side effects on import)

**Action:** Move initialization logic to explicit constructor functions or a `Setup()` function called from `main()`.
Reserve `init()` for truly static registrations (e.g., `database/sql` driver registration, codec registration) that
have no error conditions and no external dependencies. If `init()` can fail, it should not be in `init()`.

### 9. Package-Level Mutable State

Global variables at the package level that hold mutable state, creating hidden coupling and test interference.

**Signals:**

- `var db *sql.DB` or `var client *http.Client` at package level, modified at runtime
- `var cache = map[string]interface{}{}` at package level, written to by multiple functions
- Package-level `sync.Mutex` protecting package-level state (sign of a god package)
- `var defaultConfig = Config{...}` that is mutated by `SetConfig()` functions
- Global loggers modified at runtime: `var logger = log.New(...)` with `SetLogger()` functions
- Package-level `var once sync.Once` with `var instance *Service` (singleton pattern)

**Do not flag:**

- `var` declarations that are effectively constant lookup tables (e.g., `var weekdayMap = map[string]time.Weekday{...}`)
  when there is no write path after initialization. Go does not support `const` maps, so `var` is the only option.
  Check for: (1) explicit annotations like `nolint: gochecknoglobals` with "read-only" comments, (2) absence of any
  assignment to the variable outside its declaration. The smell is actual mutation (writes after init), not the `var`
  keyword on a read-only structure.

**Action:** Move state into struct instances passed via dependency injection. If truly global state is needed (rare),
encapsulate it in a struct with a constructor and pass the struct explicitly. Package-level constants and immutable
variables (`var Version = "1.0"`) are fine — the smell is mutability.

### 10. Stuttering Names

Exported identifiers that repeat the package name, violating Go's naming convention where the package name provides
context.

**Signals:**

- `user.UserName` instead of `user.Name`
- `config.ConfigOption` instead of `config.Option`
- `http.HTTPClient` instead of `http.Client` (Go standard library gets this right)
- `auth.AuthMiddleware` instead of `auth.Middleware`
- `db.DBConnection` instead of `db.Connection`
- `errors.ErrorCode` instead of `errors.Code`

**Action:** Remove the package-name prefix from the identifier. In Go, `user.Name` reads as "the Name in the user
package" — the package name already provides the context. Stuttering adds noise and violates the convention documented
in Effective Go.

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
2. Understand the project's domain model — what are the core entities, value objects, and operations?
3. Note the project's conventions for naming, struct design, and package organization.

### Phase 2: Scan for Smell Candidates

These scans produce **candidates only** — each match requires manual validation in Phase 3–5 before it becomes a
finding. Expect a high false-positive rate from regex heuristics; the value is in surfacing locations to inspect.

For diff/path mode, append the resolved file list (`$SCOPE`) to each `rg` command. For codebase mode, omit it.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go --glob !**/mock_*.go --glob !**/mocks/**'

# Feature envy: methods that heavily reference another package's types
# (look for pkg.Type.Field or pkg.Func().Method patterns — then verify manually)
rg --pcre2 '\b[a-z]\w+\.[A-Z]\w+\.' --type go $EXCLUDE -- $SCOPE

# Data clumps: repeated parameter groups (functions with 4+ params)
rg --pcre2 'func\s+(\(\w+\s+\*?\w+\)\s+)?\w+\([^)]{100,}\)' --type go $EXCLUDE -- $SCOPE

# Primitive obsession: functions with 2+ bare string/int params in sequence
rg --pcre2 'func.*\(\s*\w+\s+string\s*,\s*\w+\s+string' --type go $EXCLUDE -- $SCOPE

# Temporal coupling: Init/Setup/Configure methods on receiver types
rg --pcre2 'func\s+\(\w+\s+\*?\w+\)\s+(Init|Setup|Configure|Prepare)\b' --type go $EXCLUDE -- $SCOPE

# init() functions (then inspect for side effects)
rg '^func init\(\)' --type go $EXCLUDE -- $SCOPE

# Package-level mutable state (var declarations — filter for mutability manually)
rg '^var\s+\w+\s' --type go $EXCLUDE -- $SCOPE

# Stuttering names (package name repeated in exported identifiers)
# Manual check per package — compare package name to exported symbol prefixes

# Comments as deodorant: multi-line comment blocks before code (inspect for "what" vs "why")
rg -B1 -A1 '^\s*// ' --type go $EXCLUDE -- $SCOPE | head -200

# Shotgun surgery: per-commit co-occurrence (see Phase 4)
```

### Phase 3: Evaluate Feature Envy and Data Clumps

For each function with cross-package data access:
- Does it access more fields/methods from another type than from its receiver?
- Would moving it to the other type's package improve cohesion?

For each function with 4+ parameters:
- Do the same parameters appear together in other function signatures?
- Is there a domain concept these parameters represent?

### Phase 4: Evaluate Shotgun Surgery

Shotgun surgery is detected through **per-commit co-change analysis**, not raw file churn. High churn on a single file
is not shotgun surgery — the signal is many *unrelated* files changing together for a single logical change.

```bash
# Per-commit file sets: show which files change together in each commit
git log --pretty=format:'--- %h %s' --name-only -30 | head -200

# Package co-occurrence: for each commit, list distinct packages touched
git log --pretty=format:'COMMIT' --name-only -50 | awk '
  /^COMMIT/ { if (NR>1) { for (p in pkgs) printf "%s ", p; print "" } delete pkgs; next }
  /\// { sub(/\/[^\/]*$/, ""); pkgs[$0]=1 }
' | sort | uniq -c | sort -rn | head -20
```

For each commit that touches 4+ packages, ask: was this a single logical change scattered across unrelated modules,
or a legitimate cross-cutting concern? Look for patterns: the same package set appearing in multiple commits suggests
structural coupling.

### Phase 5: Evaluate Go-Specific Smells

For each `init()` function:
- Does it have side effects (I/O, network, global state)?
- Can it fail? Does it panic?
- Does it make the package hard to test?

For each package-level `var`:
- Is it mutable? Is it written to after initialization?
- Is it accessed from multiple goroutines?

For each exported identifier:
- Does the name repeat the package name?

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-smell-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Smell Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Findings

### Feature Envy

| # | Location | Function | Envied Type | Own Data Used | Foreign Data Used | Evidence | Action |
| - | -------- | -------- | ----------- | ------------- | ----------------- | -------- | ------ |
| 1 | file:line | `FormatOrder()` | `billing.Invoice` | 0 fields | 5 fields | `inv.Total + inv.Tax...` | Move to `billing` package |

### Data Clumps

| # | Locations | Parameters/Fields | Evidence | Suggested Type | Action |
| - | --------- | ----------------- | -------- | -------------- | ------ |
| 1 | file:line, file:line, file:line | `host, port, scheme` | 3 func signatures | `Endpoint` struct | Extract type |

### Shotgun Surgery

| # | Concept | Files Touched | Packages Touched | Action |
| - | ------- | ------------- | ---------------- | ------ |
| 1 | "Add new payment method" | 8 files | 5 packages | Consolidate payment logic |

### Primitive Obsession

| # | Location | Parameter/Field | Current Type | Evidence | Suggested Type | Action |
| - | -------- | --------------- | ------------ | -------- | -------------- | ------ |
| 1 | file:line | `userID string` | `string` | swappable with `orderID string` | `UserID` | Define named type with constructor |

### Temporal Coupling

| # | Location | Struct | Required Order | Action |
| - | -------- | ------ | -------------- | ------ |
| 1 | file:line | `Server` | `Init()` → `Start()` | Require deps in constructor |

### Comments as Deodorant

| # | Location | Comment | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `// Parse and validate the user input` | Extract `parseAndValidateInput()` |

### Temporary Field

| # | Location | Struct | Field | Used In | Action |
| - | -------- | ------ | ----- | ------- | ------ |
| 1 | file:line | `Processor` | `lastResult` | `Process()` only | Move to method-local var or return value |

### init() Abuse

| # | Location | Side Effects | Action |
| - | -------- | ------------ | ------ |
| 1 | file:line | Opens DB connection, reads env vars | Move to explicit `Setup()` called from main |

### Package-Level Mutable State

| # | Location | Variable | Mutated By | Action |
| - | -------- | -------- | ---------- | ------ |
| 1 | file:line | `var defaultClient` | `SetClient()` | Inject via struct field |

### Stuttering Names

| # | Location | Current Name | Suggested Name | Action |
| - | -------- | ------------ | -------------- | ------ |
| 1 | file:line | `user.UserName` | `user.Name` | Rename |

## Recommendations (Priority Order)

1. **Must-fix**: {data clumps with 5+ occurrences, primitive obsession causing type confusion, init() with error paths}
2. **Should-fix**: {feature envy, shotgun surgery patterns, package-level mutable state, temporal coupling}
3. **Consider**: {stuttering names, comments as deodorant, temporary fields}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: classic code smells and Go-specific antipatterns only.** Do not flag SOLID violations (→ solid-hunter-go),
  type design debt (→ type-hunter-go), package boundary issues (→ boundary-hunter-go), invariant enforcement
  (→ invariant-hunter-go), structural complexity (→ simplicity-hunter-go), missing documentation (→ doc-hunter-go),
  security (→ security-hunter-go), test quality (→ test-hunter-go), or AI-generated noise (→ slop-hunter-go).
  If a finding is better described as a SOLID principle violation, type design issue, or boundary problem, defer to
  the specialized hunter.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact code.
- **Context matters.** A smell in a prototype is less urgent than a smell in a payment system. Assess severity
  relative to the code's criticality and change frequency.
- **Pragmatism.** Not every smell requires action. A data clump that appears twice may not justify a new type.
  Feature envy in a utility function may be intentional. Report the smell, assess the cost/benefit, and let the team
  decide.
- **Respect Go idioms.** Go's `error` return pattern, explicit control flow, and composition-based design are not
  smells. Calibrate to Go conventions, not patterns from other languages.
- **Handoff, not duplication.** Smells often have root causes owned by other hunters. Smell-hunter owns the
  *symptom detection* (e.g., "these 8 files always change together"); the root-cause fix may belong to
  boundary-hunter (dependency direction), solid-hunter (SRP), or simplicity-hunter (mixed concerns). When a finding
  clearly belongs to another hunter's domain, note it as a cross-reference in the report and do not duplicate the
  analysis. When the smell is the primary signal and no other hunter covers the detection method, own the finding.
- **Assess refactoring risk briefly.** Actions are recommendations, not commands — implementation is a separate step.
  When a recommendation would affect exported API surface, serialization behavior, or could introduce import cycles,
  note the risk in the Action column (e.g., "Extract type — verify no external importers").
