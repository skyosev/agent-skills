---
name: smell-hunter-ts
description: |
  Audit TypeScript code for classic code smells — feature envy, data clumps, shotgun surgery,
  primitive obsession, temporal coupling, comments as deodorant, temporary fields, callback
  hell, enum abuse, and class abuse.

  Use when: reviewing TypeScript code for structural design problems, preparing for a refactor,
  auditing code after rapid feature development, or hunting for misplaced responsibilities.
---

# Smell Hunter

Audit TypeScript code for **code smells** — structural patterns that indicate deeper design problems. This covers
selected Fowler/Beck smells and TypeScript-specific antipatterns that fall outside the scope of specialized hunters
(SOLID, type design, boundaries, invariants, etc.). The goal: **data lives where it's used, changes are localized,
domain concepts are modeled explicitly, and TypeScript idioms are respected.**

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
   represents an email address, a tuple of `number`s that represent a coordinate, or a group of parameters that
   always appear together — these are domain concepts begging for a type.

6. **Use the language, not fight it.** TypeScript has powerful features — union types, branded types, discriminated
   unions, `satisfies`, `as const` — that eliminate entire categories of smells. When the type system can enforce a
   constraint, use it instead of runtime checks or conventions.

7. **Refactor incrementally.** Split by responsibility, not by size. Introduce abstraction only when needed (wait for
   the second use case). Preserve behavior first — add tests before restructuring.

## What to Hunt

### 1. Feature Envy

A function or method that uses more data from another module or class than from its own context.

**Signals:**

- Method on class A that primarily accesses properties/methods of class B (passed as parameter)
- Function that destructures an object from another module and operates on most of its properties
- Helper function that exists in module A but only operates on types from module B
- Function that receives an object and calls 3+ of its methods while using none of its own scope
- A function whose name suggests it belongs to the type it operates on, not the module it lives in

**Action:** Move the function to the module/class that owns the data it operates on. If it uses data from two types
equally, consider whether the shared data should be extracted into its own type.

### 2. Data Clumps

The same group of parameters or properties that always appear together across multiple function signatures or type
definitions.

**Signals:**

- 3+ parameters that appear together in multiple function signatures (e.g., `host`, `port`, `scheme` or
  `latitude`, `longitude`, `altitude`)
- Multiple interfaces/types with the same subset of properties (e.g., `street`, `city`, `zip`, `country` in several
  types)
- Functions that pass a group of related values individually instead of as an object
- Interface with properties that form a logical sub-group (e.g., `startDate`, `endDate`, `timezone` inside a larger
  config)
- React components with 4+ props that always appear together across multiple components

**Action:** Extract the group into a named type/interface. Replace the individual parameters/properties with the type.
If the group appears only in function signatures, create a parameter type. If it appears in multiple type definitions,
extract a shared type and use intersection (`&`) or composition.

### 3. Shotgun Surgery

A single logical change requires edits across many unrelated files or modules.

**Signals:**

- Adding a new field to a domain type requires updating 5+ files (handlers, validators, mappers, tests, serializers)
- Adding a new API endpoint requires changes in routes, controller, service, repository, types, and tests with
  boilerplate that could be generated or derived
- A config change requires editing code in multiple modules rather than just the config module
- Renaming a concept requires find-and-replace across the entire codebase
- A new feature flag requires changes in config, middleware, components, and tests

**Action:** Consolidate the scattered responsibility. If a change to concept X requires touching modules A, B, C, D,
and E, then X's logic is spread too thin. Consider:
- A registry or map-based dispatch instead of scattered switch cases
- Code generation or schema-driven types for boilerplate that varies with each new type/field
- A single module that owns the concept end-to-end
- Derive types from a single source of truth using utility types (`Pick`, `Omit`, `Partial`)

### 4. Primitive Obsession

Using primitive types (`string`, `number`, `boolean`) for domain concepts that deserve their own named or branded types.

**Signals:**

- Functions that accept `string` parameters for IDs, emails, URLs, currencies, or status codes
- Functions where two `string` or `number` parameters could be accidentally swapped (e.g., `transfer(from: string,
  to: string, amount: number)`)
- Validation logic for a "typed" string scattered across multiple call sites instead of enforced at construction
- `number` used for money calculations (floating-point precision loss)
- `number` used for durations without unit clarity (seconds? milliseconds?)
- Boolean parameters that control behavior: `process(data: Buffer, compress: boolean, encrypt: boolean)`
- Raw `string` comparisons for status/state values instead of union types or enums

**Action:** Define a branded type or a `NewType` pattern:
```typescript
type UserId = string & { readonly __brand: unique symbol };
type Email = string & { readonly __brand: unique symbol };
```
Or use a Zod schema / validation function that narrows to the branded type. For boolean flags, use discriminated
unions or option objects. For status values, use string literal unions: `type Status = 'active' | 'inactive' |
'suspended'`.

### 5. Temporal Coupling

Functions or operations that must be called in a specific order, but nothing in the API enforces that order.

**Signals:**

- A class with `init()`, `setup()`, or `configure()` methods that must be called before `run()` or `process()`
- Documentation or comments that say "must call X before Y"
- Runtime error or undefined behavior when methods are called in the wrong order
- A builder pattern where `build()` can be called before required fields are set
- State machine transitions that are valid only from certain states but not enforced by the type system
- React hooks that depend on other hooks being called first (beyond React's rules)

**Action:** Redesign the API to make the order implicit:
- Use constructor functions / factory functions that return a fully initialized object
- Use the builder pattern with required fields enforced at the type level (builder type changes after each step)
- Use discriminated union types where each state is a different variant with only valid transitions
- Accept dependencies in the constructor rather than via separate setter methods

### 6. Comments as Deodorant

Comments that explain *what* confusing code does rather than *why* — masking a design problem instead of fixing it.

**Signals:**

- A comment like `// Convert the user data to the format expected by the billing system` above a 20-line block that
  should be an extracted function named `toBillingFormat()`
- Comments that explain complex boolean expressions rather than extracting them into named functions
- Inline comments at each step of a long function, effectively creating "sections" that should be separate functions
- Comments explaining workarounds for the code's own design rather than external constraints
- `// This is confusing because...` — if you're writing this comment, refactor instead
- JSDoc `@description` that describes the implementation algorithm rather than the public contract

**Action:** Replace the comment with a code change:
- Extract the commented block into a function with an intent-revealing name
- Replace complex expressions with named variables or helper functions
- Split long functions at the comment boundaries into named sub-functions
- Only keep comments that explain *why* (business rules, external constraints, workarounds for third-party bugs)

### 7. Temporary Field

Object properties or class fields that are meaningful only in certain states or during specific operations — they are
set for one code path and undefined/null for all others.

**Signals:**

- Class field that is non-null in only one of several code paths
- Properties set in method A and read in method B but meaningless in methods C, D, E
- Optional properties that exist because the type is used in multiple contexts with different data requirements
- Properties documented as "only valid when X is true" or "set only during processing"
- Interface with properties like `tempResult`, `cachedData`, `lastError` that serve a single transient use
- React component state that holds intermediate computation results between renders

**Action:** Extract the temporary properties into a separate type used only where needed. If the type represents
multiple states, use a discriminated union: separate types for each state. For transient computation, use local
variables or return values instead of fields.

### 8. Callback Hell and Unflattened Promises

Deeply nested callback chains or `.then()` chains that could be flattened with `async`/`await`.

**Signals:**

- 3+ levels of nested callbacks (Node.js-style `(err, result) => { ... }`)
- `.then().then().then()` chains longer than 3 steps without `async`/`await`
- Nested `.then()` creating a "promise pyramid" instead of a flat chain
- Mixing callbacks and promises in the same function
- Error handling scattered across multiple `.catch()` blocks instead of a single `try`/`catch`
- Event listener callbacks with complex logic that should be extracted into named functions

**Action:** Convert to `async`/`await` with `try`/`catch`. Flatten nested callbacks into sequential awaited calls.
Extract complex callback bodies into named functions. If truly parallel operations are needed, use
`Promise.all()`/`Promise.allSettled()` with `await`.

### 9. Enum Abuse

Using TypeScript `enum` where a string literal union type would be simpler, more type-safe, and more idiomatic.

**Signals:**

- `enum Status { Active = 'active', Inactive = 'inactive' }` where `type Status = 'active' | 'inactive'` suffices
- Numeric enums used for values that aren't truly ordered or bitwise-combinable
- `enum` values compared with `===` against string literals (defeating the purpose of the enum)
- `const enum` used for values that need to be preserved at runtime (e.g., serialized, logged)
- `enum` with a single member
- Enums used as object keys where `Record<Status, T>` with a union would be simpler
- Enum values imported across the codebase creating coupling to the enum module

**Action:** Replace with string literal union types for simple value sets. Use `as const` objects when you need both
a type and runtime access:
```typescript
const Status = { Active: 'active', Inactive: 'inactive' } as const;
type Status = typeof Status[keyof typeof Status]; // 'active' | 'inactive'
```
Keep `enum` only when you need: reverse mapping (numeric enums), bitwise flags, or compatibility with non-TS
consumers.

### 10. Class Abuse

Using classes where plain functions, closures, or modules would be simpler and more idiomatic TypeScript.

**Signals:**

- Class with only a constructor and one public method (a function in disguise)
- Class with only static methods (a namespace/module in disguise)
- Class that holds no state — all methods are pure functions operating on their parameters
- Class with a `getInstance()` static method (singleton — use a module-level instance instead)
- Class used only to group related functions without shared state (use a module with named exports)
- Class where the constructor just assigns parameters to fields with no validation or initialization logic
- "Service" classes with no state that receive all data through method parameters

**Action:** Replace with the simpler construct:
- Single-method class → exported function (possibly with closure for dependencies)
- Static-only class → module with named function exports
- Stateless class → module with named function exports
- Singleton class → module-level instance or factory function
- State-holding class with meaningful behavior → keep the class, it's the right tool

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
2. Understand the project's domain model — what are the core entities, value objects, and operations?
3. Note the project's conventions for naming, type design, and module organization.

### Phase 2: Scan for Smell Candidates

These scans produce **candidates only** — each match requires manual validation in Phase 3–5 before it becomes a
finding. Expect a high false-positive rate from regex heuristics; the value is in surfacing locations to inspect.

For diff/path mode, append the resolved file list (`$SCOPE`) to each `rg` command. For codebase mode, omit it.

```bash
EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/**'

# Feature envy: methods that heavily reference another module's types
# (look for obj.prop.prop patterns across module boundaries — verify manually)
rg --pcre2 '\b[a-z]\w+\.[a-z]\w+\.[a-z]\w+' --type ts $EXCLUDE -- $SCOPE

# Data clumps: repeated parameter groups (functions with 4+ params)
rg --pcre2 'function\s+\w+\s*\([^)]{100,}\)' --type ts $EXCLUDE -- $SCOPE
rg --pcre2 '(?:const|let)\s+\w+\s*=\s*(?:async\s+)?\([^)]{100,}\)\s*(?:=>|:)' --type ts $EXCLUDE -- $SCOPE

# Primitive obsession: functions with 2+ bare string/number params in sequence
rg --pcre2 'function\s+\w+\s*\([^)]*:\s*string\s*,[^)]*:\s*string' --type ts $EXCLUDE -- $SCOPE

# Temporal coupling: init/setup/configure methods
rg --pcre2 '(init|setup|configure|prepare)\s*\(' --type ts $EXCLUDE -- $SCOPE

# Callback hell: nested .then() chains
rg --pcre2 '\.then\([^)]*\)\s*\.then\([^)]*\)\s*\.then' --type ts $EXCLUDE -- $SCOPE

# Enum declarations (then evaluate for abuse)
rg 'enum\s+\w+' --type ts $EXCLUDE -- $SCOPE

# Classes (then evaluate for class abuse)
rg 'class\s+\w+' --type ts $EXCLUDE -- $SCOPE

# Singleton pattern
rg 'getInstance\s*\(' --type ts $EXCLUDE -- $SCOPE

# Comments as deodorant: multi-line comment blocks before code (inspect for "what" vs "why")
rg -B1 -A1 '^\s*// ' --type ts $EXCLUDE -- $SCOPE | head -200

# Shotgun surgery: per-commit co-occurrence (see Phase 4)
```

### Phase 3: Evaluate Feature Envy and Data Clumps

For each function with cross-module data access:
- Does it access more properties/methods from another type than from its own scope?
- Would moving it to the other module improve cohesion?

For each function with 4+ parameters:
- Do the same parameters appear together in other function signatures?
- Is there a domain concept these parameters represent?

### Phase 4: Evaluate Shotgun Surgery

Shotgun surgery is detected through **per-commit co-change analysis**, not raw file churn. High churn on a single file
is not shotgun surgery — the signal is many *unrelated* files changing together for a single logical change.

```bash
# Per-commit file sets: show which files change together in each commit
git log --pretty=format:'--- %h %s' --name-only -30 | head -200

# Directory co-occurrence: for each commit, list distinct directories touched
git log --pretty=format:'COMMIT' --name-only -50 | awk '
  /^COMMIT/ { if (NR>1) { for (d in dirs) printf "%s ", d; print "" } delete dirs; next }
  /\// { sub(/\/[^\/]*$/, ""); dirs[$0]=1 }
' | sort | uniq -c | sort -rn | head -20
```

For each commit that touches 4+ directories, ask: was this a single logical change scattered across unrelated modules,
or a legitimate cross-cutting concern? Look for patterns: the same directory set appearing in multiple commits
suggests structural coupling.

### Phase 5: Evaluate TypeScript-Specific Smells

For each `enum`:
- Is it a string enum that could be a union type?
- Is it a numeric enum with non-bitwise usage?
- Is it imported across many modules creating coupling?

For each `class`:
- Does it have state? Does it have more than one public method?
- Could it be a plain function or module?
- Is it a singleton?

For each `.then()` chain or callback:
- Can it be converted to `async`/`await`?
- How many nesting levels?

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
| 1 | file:line | `formatOrder()` | `billing.Invoice` | 0 properties | 5 properties | `inv.total + inv.tax...` | Move to billing module |

### Data Clumps

| # | Locations | Parameters/Properties | Evidence | Suggested Type | Action |
| - | --------- | -------------------- | -------- | -------------- | ------ |
| 1 | file:line, file:line, file:line | `host, port, scheme` | 3 func signatures | `Endpoint` type | Extract type |

### Shotgun Surgery

| # | Concept | Files Touched | Modules Touched | Action |
| - | ------- | ------------- | --------------- | ------ |
| 1 | "Add new payment method" | 8 files | 5 modules | Consolidate payment logic |

### Primitive Obsession

| # | Location | Parameter/Property | Current Type | Evidence | Suggested Type | Action |
| - | -------- | ------------------ | ------------ | -------- | -------------- | ------ |
| 1 | file:line | `userId: string` | `string` | swappable with `orderId: string` | `UserId` (branded) | Define branded type |

### Temporal Coupling

| # | Location | Class/Object | Required Order | Action |
| - | -------- | ------------ | -------------- | ------ |
| 1 | file:line | `Server` | `init()` → `start()` | Require deps in constructor |

### Comments as Deodorant

| # | Location | Comment | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `// Parse and validate the user input` | Extract `parseAndValidateInput()` |

### Temporary Field

| # | Location | Type | Property | Used In | Action |
| - | -------- | ---- | -------- | ------- | ------ |
| 1 | file:line | `Processor` | `lastResult` | `process()` only | Use discriminated union or local var |

### Callback Hell

| # | Location | Pattern | Depth | Action |
| - | -------- | ------- | ----- | ------ |
| 1 | file:line | `.then().then().then()` | 4 | Convert to async/await |

### Enum Abuse

| # | Location | Enum | Members | Action |
| - | -------- | ---- | ------- | ------ |
| 1 | file:line | `enum Status` | 3 string values | Replace with `type Status = 'active' \| 'inactive' \| 'suspended'` |

### Class Abuse

| # | Location | Class | Methods | State | Action |
| - | -------- | ----- | ------- | ----- | ------ |
| 1 | file:line | `UserService` | 1 public | none | Replace with exported function |

## Recommendations (Priority Order)

1. **Must-fix**: {data clumps with 5+ occurrences, primitive obsession causing type confusion, callback hell > 3 levels}
2. **Should-fix**: {feature envy, shotgun surgery patterns, enum abuse, temporal coupling}
3. **Consider**: {class abuse, comments as deodorant, temporary fields}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: classic code smells and TypeScript-specific antipatterns only.** Do not flag SOLID violations
  (→ solid-hunter-ts), type design debt (→ type-hunter-ts), module boundary issues (→ boundary-hunter-ts), invariant
  enforcement (→ invariant-hunter-ts), structural complexity (→ simplicity-hunter-ts), missing documentation
  (→ doc-hunter-ts), security (→ security-hunter-ts), test quality (→ test-hunter-ts), or AI-generated noise
  (→ slop-hunter-ts). If a finding is better described as a SOLID principle violation, type design issue, or boundary
  problem, defer to the specialized hunter.
- **Evidence required.** Every finding must cite `file/path.ts:line` with the exact code.
- **Context matters.** A smell in a prototype is less urgent than a smell in a payment system. Assess severity
  relative to the code's criticality and change frequency.
- **Pragmatism.** Not every smell requires action. A data clump that appears twice may not justify a new type.
  Feature envy in a utility function may be intentional. An enum in a legacy codebase may not be worth converting.
  Report the smell, assess the cost/benefit, and let the team decide.
- **Respect TypeScript idioms.** TypeScript's structural type system, union types, and module system are its strengths.
  Calibrate to TypeScript conventions, not patterns from Java, C#, or Python.
- **Handoff, not duplication.** Smells often have root causes owned by other hunters. Smell-hunter owns the
  *symptom detection* (e.g., "these 8 files always change together"); the root-cause fix may belong to
  boundary-hunter (dependency direction), solid-hunter (SRP), or simplicity-hunter (mixed concerns). When a finding
  clearly belongs to another hunter's domain, note it as a cross-reference in the report and do not duplicate the
  analysis. When the smell is the primary signal and no other hunter covers the detection method, own the finding.
- **Assess refactoring risk briefly.** Actions are recommendations, not commands — implementation is a separate step.
  When a recommendation would affect exported API surface, serialization behavior, or framework constraints (e.g.,
  class-based DI in Nest/Angular), note the risk in the Action column (e.g., "Replace enum — verify serialization
  compatibility").
