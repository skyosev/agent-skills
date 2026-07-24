---
name: type-hunter-ts
description: |
  Audit TypeScript type definitions for design debt — duplicated shapes, missing derivations,
  over-engineered generics, under-constrained type parameters, reinvented utility types, and
  disorganized type architecture. Type structure and maintainability, not type enforcement.

  Use when: reviewing type definitions for maintainability, reducing type duplication, simplifying
  over-engineered type-level logic, or reorganizing type architecture after growth.
disable-model-invocation: true
---

# Type Hunter

Audit TypeScript type definitions for **type design debt** — places where types are duplicated instead of derived,
generics are more complex than they need to be, built-in utilities are reinvented, or type organization has drifted.
The goal: **types are derived from single sources of truth, use the simplest constructs that work, and are easy to find
and maintain.**

## When to Use

- Reviewing type definitions for maintainability after rapid growth
- Reducing type duplication across modules
- Simplifying over-engineered generic types or conditional type logic
- Reorganizing type architecture (scattered types, god type files)
- After prototyping, when type definitions need cleanup

## Core Principles

1. **Derive, don't duplicate.** When two types share structure, one should be derived from the other using utility types
   (`Pick`, `Omit`, `Partial`, `&`). Parallel type definitions that duplicate fields are a maintenance trap — a change
   to the source shape must be replicated manually in every copy.

2. **Simplest construct wins.** If an interface works, don't use a mapped type. If a mapped type works, don't use a
   conditional type. Reach for advanced type-level constructs only when simpler alternatives fail. Type-level code is
   code — it must be readable and maintainable.

3. **Constraints document intent.** A generic parameter `<T>` accepts anything — it communicates nothing. `<T extends
   Record<string, unknown>>` tells the reader and the compiler what T must be. Every generic should have the tightest
   constraint that works.

4. **Generics must vary.** A type parameter that is always instantiated with the same concrete type is indirection, not
   abstraction. If `Cache<T>` is always `Cache<User>`, remove `T` and use `User` directly. Introduce generics when there
   are 2+ distinct instantiations. **Exception:** library and public API types may carry generic parameters for consumer
   flexibility even with a single internal instantiation — flag only when the generic adds no value to any consumer.

5. **Reuse the standard library.** TypeScript ships `Partial`, `Required`, `Readonly`, `Pick`, `Omit`, `Record`,
   `Extract`, `Exclude`, `NonNullable`, `ReturnType`, `Parameters`, and more. Hand-rolling equivalents wastes tokens
   and creates maintenance surface.

6. **Types have a place.** Shared domain types belong in a central location. Implementation-local types belong next to
   their code. A 500-line types file that mixes domain types with internal helpers is disorganized. A type defined in a
   function body that is used by three modules is misplaced.

7. **Trust inference.** Explicit annotations should earn their keep. Redundant `: string` on obvious literals, return
   types that duplicate what inference already produces, and annotations that force widening hurt maintainability.
   Let the compiler infer when the expression is the source of truth.

## What to Hunt

### 1. Type Duplication

Two or more type definitions that represent the same domain concept with the same or near-identical shape.

**Signals:**

- Two interfaces/types with matching field names and types in different files
- A "create" type and an "update" type that differ only by one optional field
- Request/response types that repeat the entity shape with minor variations
- Parallel enums or union literals representing the same set of values

**Action:** Identify the canonical source type. Derive variants using `Pick`, `Omit`, `Partial`, `&`, or mapped types.
Delete the duplicates.

### 2. Missing Derivations

Types that should be derived from a source type but are manually defined, creating drift risk.

**Signals:**

- A "summary" type that manually lists a subset of fields from a full entity type (should be `Pick<Entity, ...>`)
- A "patch" type that makes all fields optional by hand (should be `Partial<Entity>`)
- A "readonly" variant that adds `readonly` to each field manually (should be `Readonly<Entity>`)
- Function return types that repeat the type of a known data structure
- Manual string-literal union (`type Role = 'admin' | 'user'`) parallel to a runtime array of roles — should derive via
  `const roles = ['admin', 'user'] as const; type Role = (typeof roles)[number]`
- `as const` object with a hand-written union type that duplicates its values

**Action:** Replace with the appropriate derivation. For fixed value sets shared at runtime and compile time, define the
runtime value with `as const` and derive the union from it. If no built-in utility fits, create a project-level utility type.

### 3. Over-Engineered Type-Level Logic

Conditional types, recursive types, or mapped types that are more complex than the problem requires.

**Signals:**

- Conditional types nested 3+ levels deep
- Recursive type definitions where a flat union would suffice
- Mapped types with `as` key remapping where a simple `Pick`/`Omit` would work
- Type-level arithmetic or string manipulation that could be a runtime function with a typed return
- Generic types with 4+ type parameters

**Action:** Simplify to the least powerful construct that solves the problem. If the type-level logic is genuinely
needed (library types, framework constraints), document why.

### 4. Under-Constrained Generics

Generic type parameters with no `extends` constraint, or constraints too broad to be useful.

**Signals:**

- `<T>` where `T` is always used in a context that assumes an object shape
- `<T extends any>` or `<T extends unknown>` — no constraint at all
- Generic functions where removing the generic and using the concrete type would work
- Constraints that don't match actual usage: `<T extends object>` when only `Record<string, string>` is passed

**Action:** Add the tightest constraint that matches actual usage. If the generic accepts only one type, remove it.

### 5. Phantom and Redundant Type Parameters

Generic parameters that don't vary, aren't used meaningfully, or exist only for theoretical extensibility.

**Signals:**

- A generic type always instantiated with the same concrete type across the codebase
- Type parameter declared but only used in covariant position (return type only, never constraining input)
- A generic class where `<T>` is used in one field and nowhere else
- "Future-proofing" generics with no second instantiation in sight

**Action:** Remove the generic and use the concrete type directly. Reintroduce when a real second use case emerges.

### 6. Reinvented Utility Types

Hand-rolled type utilities that replicate built-in TypeScript utility types.

**Signals:**

- `{ [K in keyof T]?: T[K] }` instead of `Partial<T>`
- `{ readonly [K in keyof T]: T[K] }` instead of `Readonly<T>`
- `{ [K in keyof T as K extends U ? K : never]: T[K] }` instead of `Pick<T, Extract<keyof T, U>>`
- Manual `Exclude`/`Extract` implementations using conditional types
- Custom `NonNullable` or `ReturnType` definitions

**Action:** Replace with the built-in. If the custom version has genuinely different semantics, document the difference.

### 7. Schema-Type Duplication and Missed Literal Inference

Parallel manual types that duplicate a runtime source of truth, and generic signatures that lose literal inference.
(The *adoption* of `satisfies`, `as const`, and type predicates as enforcement fixes is invariant-hunter's — this
hunter owns the *duplication* angle: two definitions of one shape.)

**Signals:**

- Validation schemas (Zod, io-ts) that could derive their TypeScript type via `z.infer<>` but instead maintain a
  parallel manual type — a drift trap identical to §1's type duplication
- Generic functions that infer wide types where `const` type parameters would preserve literal inference

**Action:** Derive types from schemas (`type User = z.infer<typeof UserSchema>`) instead of maintaining parallel
definitions. Use const type parameters where literal inference matters.

### 8. Redundant Explicit Annotations

Type annotations that duplicate inference, widen types, or add maintenance overhead without improving clarity.

**Signals:**

- `const name: string = "Ada"` where inference already yields the correct type
- Return type annotations on functions where inference produces an equally precise or better type
- Variable annotations that widen literals (`const mode: string = 'dark'` instead of inferred `'dark'`)
- Generic type arguments passed explicitly when inference would infer correctly (`getData<User>(schema)` vs
  `getData(userSchema)`)
- `@param` / `@returns` JSDoc that only restates types already in the signature (→ slop-hunter-ts for doc noise)

**Action:** Remove redundant annotations. Keep explicit types only at public API boundaries, module exports, or where
inference would be too wide or ambiguous. Prefer schema-driven inference for generic APIs.

### 9. Template Literal Types

Template literal types used where simpler types suffice, or missing where they would replace stringly-typed APIs.

**Signals (missed opportunities):**

- Route paths, event names, query keys, or CSS utility classes typed as plain `string` when a template union would
  enforce structure (e.g., `` `/api/${string}` ``, `` `user:${string}` ``)
- Lookup maps keyed by string literals where `` Record<`prefix:${string}`, T> `` or a finite template union would catch typos
- Parallel string constants and union types maintained separately instead of derived from the same `as const` source

**Signals (overuse):**

- Multi-level conditional string manipulation where a runtime function with a typed return would be clearer
- Template literal types encoding business logic that belongs in runtime validation

**Action:** Introduce template literal types for finite, structured string domains (routes, events, design tokens).
Simplify or replace over-engineered template-literal metaprogramming with runtime functions when complexity exceeds benefit.

### 10. Type Organization Debt

Type definitions that have drifted into the wrong locations or accumulated into unwieldy files.

**Signals:**

- A single `types.ts` file with 300+ lines mixing domain types, DTOs, internal helpers, and utility types
- Domain types defined inside implementation files, imported by multiple modules
- The same type imported via 3+ different paths (re-exported inconsistently)
- Type-only files in unexpected locations (e.g., a domain type in an infrastructure directory)

**Action:** Collocate implementation-local types with their code. Centralize shared domain types. Split god type files
by domain concept. Ensure one canonical import path per type.

### 11. Enum Abuse

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
a type and runtime access — derive the union from the runtime value (see §2 Missing Derivations):
```typescript
const Status = { Active: 'active', Inactive: 'inactive' } as const;
type Status = typeof Status[keyof typeof Status]; // 'active' | 'inactive'
// or: const roles = ['admin', 'user'] as const; type Role = (typeof roles)[number];
```
Keep `enum` only when you need: reverse mapping (numeric enums), bitwise flags, or compatibility with non-TS
consumers. When a recommendation would affect serialization behavior or non-TS consumers, note the risk in the
Action column.

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
   (file:line) there. Related files may still be *read* as **context**: duplication analysis (Phase 3) searches
   the whole project for the canonical type and its variants.
2. Identify type-heavy areas: dedicated type files, shared type directories, barrel exports.
3. Note the project's type conventions (interface vs type alias, naming patterns, file organization).

### Phase 2: Scan for Type Design Signals

Run every scan against the target scope (`SCOPE=.` in codebase mode).

```bash
# Production-scan exclusions: dependencies, build output, generated code, tests
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Type definitions (interfaces, type aliases) — the starting point for generics review too;
# a bare `<\w+` scan is deliberately omitted (it matches JSX, comparisons, and every generic use)
rg '(interface|type)\s+\w+' --type ts $EXCLUDE -- $SCOPE

# Conditional types (nested extends with ?)
rg --pcre2 'extends\s+.*\?\s+' --type ts $EXCLUDE -- $SCOPE

# Mapped types
rg '\[.*\s+in\s+keyof' --type ts $EXCLUDE -- $SCOPE

# Utility type usage (to measure adoption vs hand-rolling)
rg '(Partial|Required|Readonly|Pick|Omit|Record|Exclude|Extract|NonNullable|ReturnType|Parameters)<' --type ts $EXCLUDE -- $SCOPE

# Large type files
rg -c '(interface|type)\s+\w+' --type ts $EXCLUDE --sort path -- $SCOPE

# Enum declarations (then evaluate for enum abuse, §11)
rg 'enum\s+\w+' --type ts $EXCLUDE -- $SCOPE

# Schema definitions with potential parallel manual types (§7)
rg 'z\.object\(|z\.infer<' --type ts $EXCLUDE -- $SCOPE

# as const usage (derivation source check, §2)
rg 'as\s+const\b' --type ts $EXCLUDE -- $SCOPE

# Redundant explicit annotations on literals
rg --pcre2 'const\s+\w+\s*:\s*(string|number|boolean)\s*=' --type ts $EXCLUDE -- $SCOPE

# Template literal types
rg --pcre2 'type\s+\w+\s*=\s*`' --type ts $EXCLUDE -- $SCOPE
```

### Phase 3: Analyze Duplication

1. Identify types with overlapping field names across files.
2. Check for "create/update/summary" variants that should be derived from a base entity type.
3. Look for parallel enum/union definitions representing the same value set.
4. Check for runtime `as const` arrays/objects with hand-maintained parallel union types.

### Phase 4: Evaluate Complexity and Reuse

For each generic type: Is the constraint tight? Does the parameter vary? Is a simpler construct available?
For each conditional/mapped/template-literal type: Is this the simplest approach? Could a utility type or runtime
function replace it?
For each hand-rolled utility: Does a built-in equivalent exist?
For each explicit annotation: Does it add precision, or duplicate/widen inference?

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-type-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies an
output path (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Type Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

## Findings

### Type Duplication

| # | Types | Locations | Overlap | Action |
| - | ----- | --------- | ------- | ------ |
| 1 | `User`, `UserDTO` | file:line, file:line | 8/10 fields identical | Derive DTO with `Omit<User, 'password'>` |

### Missing Derivations

| # | Type | Location | Source Type | Action |
| - | ---- | -------- | ----------- | ------ |
| 1 | `UserSummary` | file:line | `User` | Replace with `Pick<User, 'id' \| 'name'>` |

### Over-Engineered Types

| # | Type | Location | Complexity | Action |
| - | ---- | -------- | ---------- | ------ |
| 1 | `DeepMerge<A, B>` | file:line | 4-level conditional + recursion | Replace with `A & B` (sufficient for actual usage) |

### Under-Constrained Generics

| # | Type/Function | Location | Parameter | Action |
| - | ------------- | -------- | --------- | ------ |
| 1 | `cache<T>()` | file:line | `T` (no constraint) | Add `T extends Record<string, unknown>` |

### Phantom Type Parameters

| # | Type | Location | Parameter | Instantiations | Action |
| - | ---- | -------- | --------- | -------------- | ------ |
| 1 | `Store<T>` | file:line | `T` | Always `User` | Remove generic, use `User` directly |

### Reinvented Utilities

| # | Type | Location | Built-In Equivalent | Action |
| - | ---- | -------- | ------------------- | ------ |
| 1 | `MakeOptional<T>` | file:line | `Partial<T>` | Replace with built-in |

### Redundant Explicit Annotations

| # | Location | Annotation | Issue | Action |
| - | -------- | ---------- | ----- | ------ |
| 1 | file:line | `const mode: string = 'dark'` | Widens literal | Remove annotation; let inference preserve `'dark'` |

### Template Literal Types

| # | Type / API | Location | Issue | Action |
| - | ---------- | -------- | ----- | ------ |
| 1 | `eventName: string` | file:line | Missed opportunity | Use `` `user:${string}` `` union or template type |

### Enum Abuse

| # | Location | Enum | Members | Action |
| - | -------- | ---- | ------- | ------ |
| 1 | file:line | `enum Status` | 3 string values | Replace with `type Status = 'active' \| 'inactive' \| 'suspended'` |

### Type Organization

| # | File | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | `types.ts` | file:line | 400 lines, mixes domain + internal types | Split by domain concept |

## Recommendations (Priority Order)

1. **High**: {type duplication with drift risk, phantom generics adding complexity}
2. **Medium**: {missing derivations, reinvented utilities, under-constrained generics, enum abuse}
3. **Low**: {type organization, over-engineered types with limited usage, template literal opportunities,
   redundant annotations}
```

(Type design debt is rarely Critical on its own; use Critical only when a drifted duplicate type is actively
producing wrong behavior in production.)

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: type design and architecture only.** If a finding doesn't answer "is this type well-designed and
  maintainable?", it belongs to another hunter — do not flag it here. Boundary with invariant-hunter: it owns type
  *enforcement* (loose optionality, unnecessary casts, discriminated-union enforcement, and the adoption of
  `satisfies` / `as const` / type predicates); this hunter owns type *structure* — duplication, derivation,
  complexity, and organization.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact type definition.
- **Complexity is sometimes justified.** Library-level types, framework constraints, and serialization boundaries may
  genuinely need advanced type-level logic. Flag the complexity, but acknowledge the justification.
- **Don't over-derive.** Not every type relationship warrants a derivation. Two types with 2 overlapping fields out of
  10 are not duplicates — they happen to share some properties. Derivation should reduce maintenance burden, not create
  abstraction puzzles.
