---
name: type-hunter-ts
description: |
  Audit TypeScript type definitions for design debt — duplicated shapes, missing derivations,
  over-engineered generics, under-constrained type parameters, reinvented utility types, and
  disorganized type architecture. Type structure and maintainability, not type enforcement.

  Use when: reviewing type definitions for maintainability, reducing type duplication, simplifying
  over-engineered type-level logic, or reorganizing type architecture after growth.
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

**Action:** Replace with the appropriate derivation. If no built-in utility fits, create a project-level utility type.

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

### 7. Missing Modern Type Features

Opportunities to use `satisfies`, `as const`, or const type parameters to improve type safety without adding complexity.

**Signals:**

- Object literals assigned to a typed variable where `satisfies` would catch typos without widening the type
- Configuration objects or lookup tables without `as const`, losing literal type information
- Generic functions that infer wide types where `const` type parameters would preserve literal inference
- Validation schemas (Zod, io-ts) that could derive their TypeScript type via `z.infer<>` but instead maintain a
  parallel manual type

**Action:** Apply `satisfies` for shape validation at assignment. Use `as const` on fixed data. Use const type
parameters where literal inference matters. Derive types from schemas instead of maintaining parallel definitions.

### 8. Type Organization Debt

Type definitions that have drifted into the wrong locations or accumulated into unwieldy files.

**Signals:**

- A single `types.ts` file with 300+ lines mixing domain types, DTOs, internal helpers, and utility types
- Domain types defined inside implementation files, imported by multiple modules
- The same type imported via 3+ different paths (re-exported inconsistently)
- Type-only files in unexpected locations (e.g., a domain type in an infrastructure directory)

**Action:** Collocate implementation-local types with their code. Centralize shared domain types. Split god type files
by domain concept. Ensure one canonical import path per type.

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
2. Identify type-heavy areas: dedicated type files, shared type directories, barrel exports.
3. Note the project's type conventions (interface vs type alias, naming patterns, file organization).

### Phase 2: Scan for Type Design Signals

```bash
EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/** --glob !**/dist/**'

# Type definitions (interfaces, type aliases)
rg '(interface|type)\s+\w+' --type ts $EXCLUDE

# Generic type parameters
rg --pcre2 '<\w+(\s+extends\s+\w+)?' --type ts $EXCLUDE

# Conditional types (nested extends with ?)
rg --pcre2 'extends\s+.*\?\s+' --type ts $EXCLUDE

# Mapped types
rg '\[.*\s+in\s+keyof' --type ts $EXCLUDE

# Utility type usage (to measure adoption vs hand-rolling)
rg '(Partial|Required|Readonly|Pick|Omit|Record|Exclude|Extract|NonNullable|ReturnType|Parameters)<' --type ts $EXCLUDE

# Large type files
rg -c '(interface|type)\s+\w+' --type ts $EXCLUDE --sort path

# satisfies usage (adoption check)
rg 'satisfies\s' --type ts $EXCLUDE

# as const usage
rg 'as\s+const\b' --type ts $EXCLUDE
```

### Phase 3: Analyze Duplication

1. Identify types with overlapping field names across files.
2. Check for "create/update/summary" variants that should be derived from a base entity type.
3. Look for parallel enum/union definitions representing the same value set.

### Phase 4: Evaluate Complexity and Reuse

For each generic type: Is the constraint tight? Does the parameter vary? Is a simpler construct available?
For each conditional/mapped type: Is this the simplest approach? Could a utility type replace it?
For each hand-rolled utility: Does a built-in equivalent exist?

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-type-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs folder exists).

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

### Type Organization

| # | File | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | `types.ts` | file:line | 400 lines, mixes domain + internal types | Split by domain concept |

## Recommendations (Priority Order)

1. **Must-fix**: {type duplication with drift risk, phantom generics adding complexity}
2. **Should-fix**: {missing derivations, reinvented utilities, under-constrained generics}
3. **Consider**: {type organization, over-engineered types with limited usage}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: type design and architecture only.** Do not flag type enforcement issues like loose optionality, unnecessary
  casts, or discriminated union enforcement (→ invariant-hunter-ts), module boundary issues (→ boundary-hunter-ts),
  class/interface design (→ solid-hunter-ts), structural complexity (→ simplicity-hunter-ts), missing documentation
  (→ doc-hunter-ts), security (→ security-hunter-ts), test quality (→ test-hunter-ts), or cosmetic style (→ slop-hunter-ts).
  If a finding doesn't answer "is this type well-designed and maintainable?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact type definition.
- **Complexity is sometimes justified.** Library-level types, framework constraints, and serialization boundaries may
  genuinely need advanced type-level logic. Flag the complexity, but acknowledge the justification.
- **Don't over-derive.** Not every type relationship warrants a derivation. Two types with 2 overlapping fields out of
  10 are not duplicates — they happen to share some properties. Derivation should reduce maintenance burden, not create
  abstraction puzzles.
