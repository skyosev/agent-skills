---
name: invariant-hunter
description: |
  Audit TypeScript types for weak invariants — unnecessary casts, loose optionality,
  defensive `?.`/`??` masking missing guarantees, leaky discriminated unions, and
  runtime checks the type system should enforce.

  Use when: tightening domain models, reducing type assertions, increasing type coverage,
  reviewing discriminated unions, or establishing a type-safety baseline before refactoring.
---

# Invariant Hunter

Audit TypeScript code to make the type system enforce invariants that are currently left to runtime, convention, or `as`
assertions. The goal: **illegal states become unrepresentable, and consumers narrow via control flow without casts.**

## When to Use

- Tightening a domain model after initial prototyping
- Reducing `as` assertions and type casts across a codebase
- Migrating from optional/defaulted fields to required fields with API-boundary defaults
- Reviewing discriminated unions for completeness, drift, or consumer ergonomics
- Before a major refactor to establish a type-safety baseline

## Core Principles

1. **Types are documentation that compiles.** Encode invariants in the type system. If it cannot be encoded without
   excessive complexity, validate at runtime with a clear error.

2. **Resolve at construction boundaries.** Defaults and validation belong where data is created or enters the system —
   public API entry points, builders, factories. Downstream functions should require their inputs. If a caller "always
   passes X", make X required and push the default to the construction boundary.

3. **Every `?` is a branch.** A `?:` field means `T | undefined` — the consumer must handle the absent case. Only use
   optional when the domain genuinely permits absence, not as a convenience for callers.

4. **`?.` and `??` are symptoms.** Optional chaining and nullish coalescing have legitimate uses (truly optional data,
   external API responses), but each occurrence is a branch the reader must reason about. In non-boundary code, they
   signal a type that is too loose. The fix is tightening the upstream type, not adding defensive access.

5. **Discriminants: single source of truth.** The discriminant field must be exhaustive. Redundant fields carrying the
   same information (e.g., `shape` vs `arch.kind`) are a drift risk — eliminate one or derive it.

6. **`as` must be justified.** Type assertions should be minimized, but **runtime-guarded casts are acceptable** when
   the cast immediately follows a runtime check and TypeScript's control flow analysis cannot correlate the
   discriminants. Do not blindly refactor into verbose alternatives that harm ergonomics without improving safety.

7. **Fail fast.** When an invariant is violated, throw immediately — do not silently return a default or catch-and-log.
   Invariant violations are programmer errors; they should crash loudly to surface bugs. Empty catches and broad
   `catch(e) { log(e) }` blocks are never acceptable.

8. **Eliminate type-system bypasses.** `as any`, `as unknown as T`, `@ts-ignore`, `@ts-expect-error` are escape hatches.
   Each must be justified (why necessary), scoped (boundary layers only), and temporary (tracked as tech debt).

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| Runtime-guarded `as Extract<...>` | Cast immediately follows a runtime check |
| Optional utility parameters | Helper accepting optional when domain type requires |
| `??` / `?.` at true boundaries | External API responses, user input, config defaults |
| Try/catch at error boundaries | Top-level handlers, middleware with defined recovery |
| Type bypasses in boundary layers | JSON parsing, FFI, library workarounds — with comment |

## What to Hunt

### 1. Unnecessary Casts

`as` assertions and `!` non-null assertions where narrowing should work or the type can be tightened.

**Signals:**

- `as` not preceded by a runtime check validating the assertion
- `!` on a value that could be made non-optional at its source
- `as unknown as T` double-cast bypasses

**Action:** Tighten the upstream type or add a runtime guard. If runtime-guarded, document as acceptable.

### 2. Loose Optionality

`?:` fields that are always present after construction, or mutually exclusive optional fields that should be a
discriminated union.

**Signals:**

- Optional field with `??` default in every consumer
- Two optional fields never both present / both absent
- Field that becomes required after a pipeline stage but carries `?:` throughout

**Action:** Make required at construction boundary. Replace mutually exclusive optionals with a discriminated union.

### 3. Defensive Access in Non-Boundary Code

`?.` and `??` that compensate for a loose upstream type rather than handling genuine absence.

**Signals:**

- `?.` on a property that is always present given the current context
- `??` applying a default that was already resolved at the entry point
- Shared helper using `??` to handle cases that should be separate functions

**Action:** Tighten the upstream type so the value is guaranteed present. Move defaults to construction boundaries.

### 4. Leaky Discriminated Unions

Unions with redundant discriminants, missing exhaustiveness checks, or fields that leak across variants.

**Signals:**

- Parallel fields carrying equivalent information (e.g., `type` vs a boolean flag)
- `switch` over discriminant without `default: assertNever(x)`
- Fields existing on all variants but meaningful only on some (missing `?: never` guards)
- Call sites that bypass narrowing with a cast instead of `if`/`switch`

**Action:** Eliminate redundant discriminants. Add exhaustiveness guards. Apply `?: never` to variant-exclusive fields.

### 5. Runtime Checks Promotable to Types

Guards, assertions, and validations that could be compile-time guarantees.

**Signals:**

- `if (node.config)` where `config` should be guaranteed by the discriminant
- Branded type candidates: IDs, units, validated strings used as plain `string`
- Empty-check branches that a `NonEmptyArray<T>` type would eliminate
- Mutation guards that `Readonly<T>` would enforce

**Action:** Promote to type constraint. If type complexity would be excessive, keep as runtime with documentation.

### 6. Type-System Bypasses and Error Suppression

`as any`, `@ts-ignore`, double-casts, empty catch blocks, and catch-only-log patterns.

**Signals:**

- `as any` or `as unknown as T` without justification comment
- `@ts-ignore` / `@ts-expect-error` without explanation
- `catch { }` or `catch(e) { console.log(e) }` with no recovery logic
- Silent fallback (`return []`, `return null`) on invalid input instead of throwing

**Action:** Fix the underlying type issue. If bypass is necessary, add justification and track as tech debt. For catch
blocks: remove if suppressing invariant violations, keep if at a defined error boundary with recovery.

## Audit Workflow

### Phase 1: Establish Baseline

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

2. Record `tsconfig.json` strictness flags (`strict`, `strictNullChecks`, `exactOptionalPropertyTypes`,
   `noUncheckedIndexedAccess`). If key flags are off, note this prominently.

3. Scan for patterns:
   ```bash
   EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/**'

   rg --pcre2 '\bas\s+(?!const\b)' --type ts $EXCLUDE              # as assertions
   rg --pcre2 '[a-zA-Z0-9_\]\)]\!(?!=)' --type ts $EXCLUDE         # non-null assertions
   rg ':\s*any\b|<any>|\bas\s+any\b' --type ts $EXCLUDE             # any usage
   rg '@ts-ignore|@ts-expect-error' --type ts                        # suppressions
   rg '\?\.' --type ts $EXCLUDE                                      # optional chaining
   rg '\?\?' --type ts $EXCLUDE                                      # nullish coalescing
   rg 'as\s+(unknown|any)\s+as' --type ts $EXCLUDE                  # double-casts
   rg -U 'catch\s*\([^)]*\)\s*\{\s*(//.*)?\s*\}' --type ts $EXCLUDE # empty catches
   ```

4. Produce counts by category, grouped by module/layer.

### Phase 2: Evaluate Discriminated Unions

For each discriminated union:

- **Inference**: Can consumers narrow via `if`/`switch` without `as`? List bypass sites.
- **Redundancy**: Is the discriminant the single source of truth? Flag parallel fields.
- **Exhaustiveness**: Do `switch` statements have `assertNever` defaults?
- **Never guards**: Do exclusive-to-variant fields use `?: never` on other variants?

### Phase 3: Evaluate Optionality and Defensive Access

For each `?:` field in core types: Is absence meaningful, or always present after construction?
For each `?.` / `??` in non-boundary code: Is the property guaranteed present in this context?

Classify each as: tighten type / move default to boundary / acceptable (see Canonical Exceptions).

### Phase 4: Evaluate Runtime vs Type Enforcement

For each runtime guard/assertion, classify:

- **Promote to type**: replace runtime check with compile-time guarantee
- **Keep as runtime**: external boundary, serialization, or excessive type complexity
- **Remove**: redundant with existing type guarantees

### Phase 5: Evaluate Error Handling and Bypasses

For each catch block: classify as Remove (no recovery) / Keep (defined boundary) / Move (too broad).
For each type bypass: verify justification, scoping, and tech debt tracking.

### Phase 6: Evaluate Ergonomics

- Count branches required to handle each variant in consuming code.
- Identify boilerplate patterns (repeatedly checking discriminant then casting).
- Test extensibility: can a new variant be added by extending the union and handling new cases?

## Output Format

Save as `Y-m-d-invariant-hunter-audit.md` in the project's docs folder.

```md
# Invariant Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Compiler Context

- tsconfig: {path}
- `strict`: {on/off}, `strictNullChecks`: {on/off}
- `exactOptionalPropertyTypes`: {on/off}, `noUncheckedIndexedAccess`: {on/off}

## Baseline

| Category | Count |
| -------- | ----- |
| `as` assertions (non-const) | {n} |
| Non-null assertions `!` | {n} |
| `any` usage | {n} |
| `@ts-ignore` / `@ts-expect-error` | {n} |
| Double-cast bypasses | {n} |
| Empty/logging-only catch blocks | {n} |
| Optional fields in core types | {n} |
| `??` in non-boundary code | {n} |
| `?.` in non-boundary code | {n} |

## Discriminated Unions

### {UnionName}

- Discriminant: `{field}`
- Inference: {pass/fail}
- Redundancy: {none / {field} duplicates {other}}
- Exhaustiveness: {pass/fail}
- Never guards: {pass/fail}

## Optionality and Defensive Access

| # | Field/Expression | Location | Current | Proposed | Rationale |
| - | ---------------- | -------- | ------- | -------- | --------- |
| 1 | ... | file:line | optional | required | ... |

## Runtime → Type Promotions

| # | Invariant | Location | Current | Proposed | Complexity |
| - | --------- | -------- | ------- | -------- | ---------- |
| 1 | ... | file:line | runtime guard | type constraint | low/med/high |

## Error Handling and Bypasses

| # | Location | Pattern | Classification | Action |
| - | -------- | ------- | -------------- | ------ |
| 1 | file:line | `as any` | Remove | Fix type |

## Ergonomics

- Consumer branch count per variant: ...
- Boilerplate patterns: ...
- Extensibility: ...

## Recommendations (Priority Order)

1. **Must-fix**: {narrowing failures, forced casts, silent fallbacks masking bugs}
2. **Should-fix**: {defaults in wrong layer, always-present optionals, catch cleanup}
3. **Consider**: {ergonomic improvements, extensibility prep}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: type invariants only.** Do not flag type design/architecture (→ type-hunter), module boundary issues
  (→ boundary-hunter), structural complexity (→ simplicity-hunter), class/interface design (→ solid-hunter), missing
  documentation (→ doc-hunter), security (→ security-hunter), test quality (→ test-hunter), or cosmetic style
  (→ slop-hunter). If a finding doesn't answer "is this type tight enough?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Architecture-first.** Understand the project's intended layering before flagging violations. Ask if unclear.
- **Complexity honesty.** If encoding an invariant requires conditional types three levels deep, say so and recommend
  runtime validation.
- **Challenge assumptions.** If the current type design makes a deliberate trade-off, acknowledge it rather than
  mechanically flagging it.
- **Prioritize**: dead fallbacks > representational correctness > discriminated unions > optional strictness flags.
  Assess cascading effects — removing fallbacks may trigger `noUnusedParameters`; include cleanup.
