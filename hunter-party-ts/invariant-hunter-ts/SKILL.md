---
name: invariant-hunter-ts
description: |
  Audit TypeScript types for weak invariants — unnecessary casts, loose optionality,
  defensive `?.`/`??` masking missing guarantees, leaky discriminated unions, and
  runtime checks the type system should enforce.

  Use when: tightening domain models, reducing type assertions, increasing type coverage,
  reviewing discriminated unions, or establishing a type-safety baseline before refactoring.
disable-model-invocation: true
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

6. **Prefer `satisfies` over `as`.** When validating that an object literal conforms to a type, `satisfies Type`
   checks shape without widening or erasing literal inference. Object-literal `as Type` is a cast — it silences the
   compiler and provides no runtime guarantee.

7. **`as` must be justified.** Type assertions should be minimized, but **runtime-guarded casts are acceptable** when
   the cast immediately follows a runtime check and TypeScript's control flow analysis cannot correlate the
   discriminants. Do not blindly refactor into verbose alternatives that harm ergonomics without improving safety.

8. **Prefer `unknown` over `any`.** `any` disables the type checker and leaks through the codebase. At boundaries and
   for untyped values, use `unknown` and narrow with type predicates, assertion functions, or schema validation — never
   `as T` without a preceding guard.

9. **Fail fast.** When an invariant is violated, throw immediately — do not silently return a default. Invariant
   violations are programmer errors; they should crash loudly to surface bugs. (How errors are caught, suppressed,
   or converted — empty catches, catch-and-log, boundary handling — is error-hunter's domain; do not hunt catch
   blocks here.)

10. **Eliminate type-system bypasses.** `as any`, `as unknown as T`, `@ts-ignore`, `@ts-expect-error` are escape hatches.
   Each must be justified (why necessary), scoped (boundary layers only), and temporary (tracked as tech debt).

11. **Type-safe ≠ runtime safe.** Compile-time types end at runtime boundaries. `(await response.json()) as User`
    compiles but provides zero runtime guarantee. Typed API responses, parsed JSON, and external input require validation
    at the boundary — see security-hunter-ts for trust-boundary patterns; flag the cast here, hand off schema gaps there.

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| Runtime-guarded `as Extract<...>` | Cast immediately follows a runtime check |
| Optional utility parameters | Helper accepting optional when domain type requires |
| `??` / `?.` at true boundaries | External API responses, user input, config defaults |
| Type bypasses in boundary layers | FFI, library workarounds — with comment and tracked debt |
| Schema-validated boundary parse | Zod/io-ts parse at trust boundary; type derived via `z.infer<>` |

Do **not** treat `(await response.json()) as T` or `JSON.parse(x) as T` as acceptable — flag as must-fix unless
immediately followed by schema validation that narrows to `T`.

## What to Hunt

### 1. Unnecessary Casts

`as` assertions and `!` non-null assertions where narrowing should work or the type can be tightened.

**Signals:**

- Object-literal `as Type` where `satisfies Type` would validate shape without widening
- `as` not preceded by a runtime check validating the assertion
- `(await response.json()) as T` or `JSON.parse(...) as T` without schema validation at the boundary
- `!` on a value that could be made non-optional at its source
- `as unknown as T` double-cast bypasses

**Action:** Replace object-literal `as` with `satisfies`. Tighten the upstream type or add a runtime guard (type
predicate, assertion function, or schema parse). If runtime-guarded, document as acceptable.

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
- Branded type candidates for *validated* state: values whose validity is established at a parse/validation
  boundary (validated email, sanitized string, checked unit) but that travel downstream as plain `string`/`number`
  — the brand should encode "already validated"
- Empty-check branches that a `NonEmptyArray<T>` type would eliminate
- Mutation guards that `Readonly<T>` would enforce
- Object literals without `satisfies` where shape conformance is intended but unchecked
- Validation functions that return `boolean` instead of using `asserts param is T` to narrow the caller's scope
- Repeated inline `typeof` / `in` checks at multiple call sites instead of a reusable type predicate (`value is T`)
- Mutable arrays/objects used as config where `as const` would enforce literal types and immutability

**Action:** Promote to type constraint. Use `satisfies` to validate shape at assignment without widening. Extract
reusable type predicates (`function isUser(x: unknown): x is User`) or assertion functions (`asserts x is T`) for
boundary narrowing. Use `as const` for fixed configuration and lookup objects. If type complexity would be excessive,
keep as runtime with documentation.

**Ownership notes:** invariant-hunter owns the *adoption* of `satisfies`, `as const`, type predicates, and assertion
functions as type-enforcement fixes. type-hunter owns schema-vs-manual-type *duplication* (parallel `z.infer`
candidates) as design debt. Branded types for plain domain modeling (swappable IDs, units without a validation
boundary) are smell-hunter's primitive obsession; brands for security-sensitive strings are security-hunter's.

### 6. Type-System Bypasses

`as any`, `@ts-ignore`, and double-casts. (Empty catches and catch-only-log patterns are error-hunter's findings —
except type bypasses *inside* catch blocks, e.g. `catch (e) { throw e as any }`, which stay here.)

**Signals:**

- `any` where `unknown` plus narrowing would preserve safety
- `as any` or `as unknown as T` without justification comment
- `@ts-ignore` / `@ts-expect-error` without explanation
- Silent fallback (`return []`, `return null`) on invalid input instead of throwing

**Action:** Replace `any` with `unknown` and narrow at use sites. Fix the underlying type issue. If bypass is necessary,
add justification and track as tech debt.

## Audit Workflow

### Phase 1: Establish Baseline

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
   (file:line) there. Related files may still be *read* as **context**: evaluating a union or an optional field
   requires reading its consumers and construction sites, wherever they live.

2. Record `tsconfig.json` strictness flags (`strict`, `strictNullChecks`, `exactOptionalPropertyTypes`,
   `noUncheckedIndexedAccess`). If key flags are off, note this prominently.

3. Scan for patterns (against the target scope; `SCOPE=.` in codebase mode):
   ```bash
   # Production-scan exclusions: dependencies, build output, generated code, tests
   EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

   # as assertions — the post-filter drops import/export alias lines (`import * as fs`, `import { foo as bar }`),
   # which would otherwise dominate the matches
   rg -n --pcre2 '\bas\s+(?!const\b)' --type ts $EXCLUDE -- $SCOPE | rg -v ':\s*(import|export)\b'
   rg --pcre2 '[a-zA-Z0-9_\]\)]\!(?!=)' --type ts $EXCLUDE -- $SCOPE  # non-null assertions
   rg ':\s*any\b|<any>|\bas\s+any\b' --type ts $EXCLUDE -- $SCOPE     # any usage
   rg '@ts-ignore|@ts-expect-error' --type ts -- $SCOPE                # suppressions
   rg '\?\.' --type ts $EXCLUDE -- $SCOPE                              # optional chaining
   rg '\?\?' --type ts $EXCLUDE -- $SCOPE                              # nullish coalescing
   rg 'as\s+(unknown|any)\s+as' --type ts $EXCLUDE -- $SCOPE          # double-casts
   rg 'satisfies\s' --type ts $EXCLUDE -- $SCOPE                      # satisfies usage (adoption check)
   rg 'asserts\s+\w+\s+is\s' --type ts $EXCLUDE -- $SCOPE            # assertion functions
   rg --pcre2 '\):\s*\w+\s+is\s+\w+' --type ts $EXCLUDE -- $SCOPE   # type predicates (value is T)
   rg --pcre2 '\.json\(\)\)\s+as\s|\bJSON\.parse\([^)]+\)\s+as\s' --type ts $EXCLUDE -- $SCOPE  # cast without validation
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

### Phase 5: Evaluate Bypasses

For each type bypass: verify justification, scoping, and tech debt tracking. (Catch-block classification is
error-hunter's job; only type bypasses inside catch blocks are evaluated here.)

### Phase 6: Evaluate Ergonomics

- Count branches required to handle each variant in consuming code.
- Identify boilerplate patterns (repeatedly checking discriminant then casting).
- Test extensibility: can a new variant be added by extending the union and handling new cases?

## Output Format

Save as `YYYY-MM-DD-invariant-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies
an output path (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Invariant Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

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

## Type-System Bypasses

| # | Location | Pattern | Classification | Action |
| - | -------- | ------- | -------------- | ------ |
| 1 | file:line | `as any` | Remove | Fix type |

## Ergonomics

- Consumer branch count per variant: ...
- Boilerplate patterns: ...
- Extensibility: ...

## Recommendations (Priority Order)

1. **Critical**: {unvalidated boundary casts on production input paths — `(await res.json()) as T` reachable by attackers}
2. **High**: {narrowing failures, forced casts, silent fallbacks masking bugs}
3. **Medium**: {defaults in wrong layer, always-present optionals}
4. **Low**: {ergonomic improvements, extensibility prep}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: type invariants only.** If a finding doesn't answer "is this type tight enough?", it belongs to another
  hunter — do not flag it here.
- **Boundary with security-hunter**: `(json()) as T` and missing schema validation at trust boundaries are must-fix in
  both skills — invariant-hunter flags the unsafe cast and loose typing; security-hunter flags the exploitable boundary
  and recommends schema + `z.infer<>`. Do not duplicate full trust-boundary audits here.
- **Boundary with error-hunter**: invariant-hunter owns type-system bypasses (`as any`, `@ts-ignore`,
  `@ts-expect-error`) and loose optionality from a type-enforcement perspective. Error-hunter owns how errors are
  structured, propagated, caught, and converted — the *design* of the error handling strategy. If the finding is about
  `as any` without justification, it belongs here. If the finding is about an empty `catch` block or missing
  `Error.cause` chain, it belongs in error-hunter. Type-system bypass patterns that appear *inside* catch blocks
  (e.g., `catch (e) { throw e as any }`) are invariant-hunter findings.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact code.
- **Architecture-first.** Understand the project's intended layering before flagging violations. Ask if unclear.
- **Complexity honesty.** If encoding an invariant requires conditional types three levels deep, say so and recommend
  runtime validation.
- **Challenge assumptions.** If the current type design makes a deliberate trade-off, acknowledge it rather than
  mechanically flagging it.
- **Prioritize** in this order: casts and silent fallbacks that mask real bugs; then making illegal states
  unrepresentable (construction-boundary defaults, discriminated-union fixes); then union hygiene (exhaustiveness,
  `?: never` guards); then strictness-flag adoption. Assess cascading effects — removing fallbacks may trigger
  `noUnusedParameters`; include cleanup.
