---
name: smell-hunter-ts
description: |
  Audit TypeScript code for classic code smells — feature envy, data clumps, shotgun surgery,
  primitive obsession, temporal coupling, comments as deodorant, temporary fields, and
  class abuse.

  Use when: reviewing TypeScript code for structural design problems, preparing for a refactor,
  auditing code after rapid feature development, or hunting for misplaced responsibilities.
disable-model-invocation: true
---

# Smell Hunter

Audit TypeScript code for **code smells** — structural patterns that indicate deeper design problems. This covers
selected Fowler/Beck smells and TypeScript-specific antipatterns that fall outside the scope of specialized hunters
(SOLID, type design, boundaries, invariants, etc.). The goal: **data lives where it's used, changes are localized,
domain concepts are modeled explicitly, and TypeScript idioms are respected.**

**Not covered (owned by other hunters):** long method / mixed concerns (→ simplicity-hunter), dead code
(→ simplicity-hunter / slop-hunter), speculative generality (→ simplicity-hunter), magic numbers (→ doc-hunter),
interface pollution (→ simplicity-hunter / solid-hunter), callback hell / unflattened promise chains
(→ simplicity-hunter, complex control flow), enum-vs-union design (→ type-hunter). See Operating Constraints for
handoff rules.

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

**Ownership note:** smell-hunter owns primitive obsession as a *domain-modeling* gap. Branded types that encode
*validated* state (parse-don't-validate) belong to invariant-hunter; brands for security-sensitive strings (SQL
fragments, HTML, paths) belong to security-hunter. Cross-reference instead of duplicating.

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

**Ownership note:** smell-hunter owns the temporal-coupling finding and the redesign recommendation. doc-hunter's
role is limited to ordering constraints that are *staying* and are undocumented — a comment is the fallback, not
the fix.

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

**Comment ownership rule** (stated identically in doc-hunter, slop-hunter, and smell-hunter):
- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment present and the code trivial → slop-hunter (delete the redundant comment).
- Comment present and the code non-trivial → smell-hunter (extract/refactor; the comment is deodorant).

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

### 8. Class Abuse

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
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or layers
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

   **Two surfaces.** Findings are reported only against the **target scope** (`$SCOPE`) — every finding anchors
   (file:line) there. Related files may still be *read* as **context** to discover, validate, or trace a finding.
   For this hunter: the Phase 2 scans run against the target scope; the git co-change analysis in Phase 4 is
   inherently project-wide — report only concepts whose files intersect the target scope.
2. Understand the project's domain model — what are the core entities, value objects, and operations?
3. Note the project's conventions for naming, type design, and module organization.

### Phase 2: Scan for Smell Candidates

These scans produce **candidates only** — each match requires manual validation in Phase 3–5 before it becomes a
finding. Expect a high false-positive rate from regex heuristics; the value is in surfacing locations to inspect.

Run every scan against the target scope (`SCOPE=.` in codebase mode).

```bash
# Production-scan exclusions: dependencies, build output, generated code, tests
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

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

# Directory co-occurrence: for each commit, emit its sorted set of touched directories,
# then count identical sets (sort -u makes the per-commit set order deterministic;
# the END block flushes the final commit)
git log --pretty=format:'COMMIT %h' --name-only -50 | awk '
  /^COMMIT/ { c=$2; next }
  /\// { sub(/\/[^\/]*$/, ""); print c, $0 }
' | sort -u | awk '
  { if ($1 != c) { if (c != "") print s; c = $1; s = "" } s = s " " $2 }
  END { if (c != "") print s }
' | sort | uniq -c | sort -rn | head -20
```

For each commit that touches 4+ directories, ask: was this a single logical change scattered across unrelated modules,
or a legitimate cross-cutting concern? Look for patterns: the same directory set appearing in multiple commits
suggests structural coupling.

### Phase 5: Evaluate TypeScript-Specific Smells

For each `class`:
- Does it have state? Does it have more than one public method?
- Could it be a plain function or module?
- Is it a singleton?

(Enum design belongs to type-hunter; callback/promise-chain flattening belongs to simplicity-hunter's complex
control flow — route, don't evaluate here.)

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-smell-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies an
output path (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Smell Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

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

### Class Abuse

| # | Location | Class | Methods | State | Action |
| - | -------- | ----- | ------- | ----- | ------ |
| 1 | file:line | `UserService` | 1 public | none | Replace with exported function |

## Recommendations (Priority Order)

1. **Critical**: {smells actively causing defects on production paths — e.g. swappable primitive IDs already mixed up}
2. **High**: {data clumps with 5+ occurrences, primitive obsession causing type confusion}
3. **Medium**: {feature envy, shotgun surgery patterns, temporal coupling}
4. **Low**: {class abuse, comments as deodorant, temporary fields}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: classic code smells and TypeScript-specific antipatterns only.** If a finding is better described by
  another hunter's scope question (SOLID violation, type design, boundary problem, complexity, security, …), it
  belongs to that hunter — do not flag it here.
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
