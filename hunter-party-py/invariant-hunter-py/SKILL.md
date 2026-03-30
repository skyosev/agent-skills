---
name: invariant-hunter-py
description: |
  Audit Python code for weak invariants — unnecessary casts, loose optionality, defensive
  None-checks masking missing guarantees, leaky tagged unions, error suppression, and runtime
  checks that the type system or construction boundaries should enforce.

  Use when: tightening post-construction guarantees, reducing type: ignore and cast() usage,
  reviewing dataclass/TypedDict optionality, auditing error-handling hygiene, or establishing
  a type-safety baseline before refactoring.
---

# Invariant Hunter

Audit Python code to make the type system enforce invariants that are currently left to runtime, convention, or
`cast()`/`# type: ignore` assertions. The goal: **guarantees established at construction boundaries hold throughout
downstream code, and consumers narrow via isinstance/match without casts.**

This skill focuses on *enforcement* — whether invariants that should hold are actually enforced. For type *design*
questions (primitive obsession, NewType opportunities, structural vs nominal choice, alias clarity, generic
correctness), see type-hunter-py.

## When to Use

- Tightening post-construction guarantees after initial prototyping
- Reducing `cast()`, `# type: ignore`, and `Any` usage that compensates for loose upstream types
- Migrating from optional/defaulted fields to required fields with factory-boundary defaults
- Reviewing tagged unions (Literal discriminants) for exhaustiveness and consumer ergonomics
- Auditing error-handling patterns for silent invariant violations
- Before a major refactor to establish a type-safety baseline

## Core Principles

1. **Types are documentation that runs.** Encode invariants in the type system. If it cannot be encoded without
   excessive complexity, validate at runtime with a clear error.

2. **Resolve at construction boundaries.** Defaults and validation belong where data is created or enters the system —
   public API entry points, factories, `__init__` methods. Downstream functions should require their inputs. If a
   caller "always passes X", make X required and push the default to the construction boundary.

3. **Every `Optional` is a branch.** An `Optional[T]` field means `T | None` — the consumer must handle the absent
   case. Only use Optional when the domain genuinely permits absence, not as a convenience for callers.

4. **`is not None` checks are symptoms.** None-checks have legitimate uses (truly optional data, external API
   responses), but each occurrence is a branch the reader must reason about. In non-boundary code, they signal a type
   that is too loose. The fix is tightening the upstream type, not adding defensive access.

5. **Discriminants: single source of truth.** The discriminant field must be exhaustive. Redundant fields carrying the
   same information (e.g., `kind` vs `is_active` flag) are a drift risk — eliminate one or derive it.

6. **`cast()` must be justified.** Type casts should be minimized, but **runtime-guarded casts are acceptable** when
   the cast immediately follows a runtime check and mypy's/pyright's control flow analysis cannot correlate the
   discriminants. Do not blindly refactor into verbose alternatives that harm ergonomics without improving safety.

7. **Fail fast.** When an invariant is violated, raise immediately — do not silently return a default or catch-and-log.
   Invariant violations are programmer errors; they should crash loudly to surface bugs. For error handling *design*
   (exception hierarchy, chaining, try/except scope, silent suppression), see error-hunter-py.

8. **Eliminate type-system bypasses.** `Any`, `cast()`, `# type: ignore`, `# pyright: ignore` are escape hatches.
   Each must be justified (why necessary), scoped (boundary layers only), and temporary (tracked as tech debt).

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| Runtime-guarded `cast()` | Cast immediately follows a runtime check |
| Optional utility parameters | Helper accepting Optional when domain type requires |
| `is not None` at true boundaries | External API responses, user input, config defaults |
| Try/except at error boundaries | Top-level handlers, middleware with defined recovery |
| Type bypasses in boundary layers | JSON parsing, FFI, library workarounds — with comment |

## What to Hunt

### 1. Unnecessary Casts

`cast()` assertions and `# type: ignore` where narrowing should work or the type can be tightened.

**Signals:**

- `cast()` not preceded by a runtime check validating the assertion
- `assert x is not None` used to satisfy the type checker where the type should be non-optional
- `# type: ignore` without a specific error code or explanation
- `typing.Any` used as a return type or parameter where a concrete type is known

**Action:** Tighten the upstream type or add a runtime guard. If runtime-guarded, document as acceptable.

### 2. Loose Optionality

`Optional` fields that are always present after construction, or mutually exclusive optional fields that should be a
tagged union.

**Signals:**

- Optional field with `or default` / `if x is None` pattern in every consumer
- Two Optional fields never both present / both absent
- Field that becomes non-None after a pipeline stage but carries `Optional` throughout
- Dataclass fields with `field(default=None)` that are always set before use

**Action:** Make required at construction boundary. Replace mutually exclusive optionals with a tagged union
(Literal discriminant + dataclass variants).

### 3. Defensive Access in Non-Boundary Code

`is not None` checks and `or default` patterns that compensate for a loose upstream type rather than handling genuine
absence.

**Signals:**

- `is not None` on a value that is always present given the current context
- `or default_value` applying a default that was already resolved at the entry point
- Shared helper using `or` / `if x is None` to handle cases that should be separate functions

**Action:** Tighten the upstream type so the value is guaranteed present. Move defaults to construction boundaries.

### 4. Leaky Tagged Unions

Unions with redundant discriminants, missing exhaustiveness checks, or fields that leak across variants.

**Signals:**

- Parallel fields carrying equivalent information (e.g., `kind` vs a boolean flag)
- `match`/`if-elif` over discriminant without a final `else: raise`/`assert_never()` for exhaustiveness
- Fields existing on all variants but meaningful only on some
- Call sites that bypass narrowing with a cast instead of `isinstance`/`match`

**Action:** Eliminate redundant discriminants. Add exhaustiveness guards (`assert_never()` from `typing`). Separate
variant-specific fields into distinct dataclasses.

### 5. Runtime Checks Promotable to Types

Guards, assertions, and validations that could be compile-time guarantees.

**Signals:**

- `if node.config is not None` where `config` should be guaranteed by the discriminant
- `NewType` candidates: IDs, units, validated strings used as plain `str`
- Empty-check branches that a custom `NonEmpty[T]` type or `Annotated[list, MinLen(1)]` would eliminate
- Mutation guards that `@dataclass(frozen=True)` would enforce
- Validation functions that return `bool` instead of using `TypeGuard[T]` to narrow the caller's scope
- Mutable containers used as config where `tuple`/`frozenset` would enforce immutability

**Action:** Promote to type constraint. Use `NewType` for domain identifiers. Use `TypeGuard` for runtime guards that
should narrow control flow. Use `frozen=True` for immutable data. If type complexity would be excessive, keep as
runtime with documentation.

### 6. Type-System Bypasses

`Any`, `cast()`, `# type: ignore`, and `# pyright: ignore` — escape hatches that circumvent the type checker.

**Boundary with error-hunter:** invariant-hunter owns type-system escape hatches (`Any`, `cast()`, `# type: ignore`).
error-hunter owns error suppression patterns (bare `except:`, catch-and-log-only, silent fallbacks). If the finding
is about bypassing the type checker, it belongs here. If it’s about swallowing exceptions, it belongs in error-hunter.

**Signals:**

- `Any` as parameter type, return type, or variable annotation without justification
- `# type: ignore` without a specific error code (e.g., `# type: ignore[attr-defined]`)
- `cast()` without justification comment
- `# pyright: ignore` or `# mypy: ignore` without explanation

**Action:** Fix the underlying type issue. If bypass is necessary, add justification and track as tech debt.

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

2. Record mypy/pyright config: check `pyproject.toml`, `mypy.ini`, or `pyrightconfig.json` for strictness flags
   (`strict`, `disallow_any_generics`, `disallow_untyped_defs`, `warn_return_any`). If key flags are off, note this
   prominently.

3. Scan for patterns:
   ```bash
   EXCLUDE='--glob !**/*_test.py --glob !**/test_*.py --glob !**/tests/** --glob !**/venv/** --glob !**/.venv/**'

   rg 'cast\(' --type py $EXCLUDE                                   # cast() usage
   rg '# type: ignore' --type py $EXCLUDE                           # type ignores
   rg ':\s*Any\b|-> Any\b' --type py $EXCLUDE                      # Any usage
   rg '# (pyright|mypy): ignore' --type py $EXCLUDE                 # tool-specific ignores
   rg 'Optional\[' --type py $EXCLUDE                               # Optional usage
   rg 'is not None|is None' --type py $EXCLUDE                      # None checks
   rg 'assert_never\|TypeGuard' --type py $EXCLUDE                  # modern typing adoption
   rg 'NewType\(' --type py $EXCLUDE                                # NewType usage
   ```

4. Produce counts by category, grouped by module/layer.

### Phase 2: Evaluate Tagged Unions

For each tagged union (Literal discriminant, dataclass hierarchy, or class hierarchy):

- **Inference**: Can consumers narrow via `isinstance`/`match` without `cast`? List bypass sites.
- **Redundancy**: Is the discriminant the single source of truth? Flag parallel fields.
- **Exhaustiveness**: Do `match`/`if-elif` chains have `assert_never()` or `else: raise` defaults?

### Phase 3: Evaluate Optionality and Defensive Access

**Boundary with type-hunter:** If the type *definition* should not be Optional (the field is always present), that’s
a type-hunter finding. If the type is correctly non-Optional but downstream code still does `is not None` checks,
that’s an invariant-hunter finding.

For each `Optional` field in core types: Is absence meaningful, or always present after construction?
For each `is not None` / `or default` in non-boundary code: Is the property guaranteed present in this context?

Classify each as: tighten type / move default to boundary / acceptable (see Canonical Exceptions).

### Phase 4: Evaluate Runtime vs Type Enforcement

For each runtime guard/assertion, classify:

- **Promote to type**: replace runtime check with compile-time guarantee
- **Keep as runtime**: external boundary, serialization, or excessive type complexity
- **Remove**: redundant with existing type guarantees

### Phase 5: Evaluate Error Handling and Bypasses

For each except block: classify as Remove (no recovery) / Keep (defined boundary) / Move (too broad).
For each type bypass: verify justification, scoping, and tech debt tracking.

### Phase 6: Evaluate Ergonomics

- Count branches required to handle each variant in consuming code.
- Identify boilerplate patterns (repeatedly checking discriminant then casting).
- Test extensibility: can a new variant be added by extending the union and handling new cases?

## Output Format

Save as `YYYY-MM-DD-invariant-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs
folder exists).

```md
# Invariant Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Type Checker Context

- Tool: {mypy / pyright / both}
- Config: {path}
- `strict`: {on/off}, `disallow_any_generics`: {on/off}
- `disallow_untyped_defs`: {on/off}, `warn_return_any`: {on/off}

## Baseline

| Category | Count |
| -------- | ----- |
| `cast()` usage | {n} |
| `# type: ignore` (total) | {n} |
| `Any` usage | {n} |
| Tool-specific ignores | {n} |
| `Optional` fields in core types | {n} |
| `is not None` in non-boundary code | {n} |

## Tagged Unions

### {UnionName}

- Discriminant: `{field}`
- Inference: {pass/fail}
- Redundancy: {none / {field} duplicates {other}}
- Exhaustiveness: {pass/fail}

## Optionality and Defensive Access

| # | Field/Expression | Location | Current | Proposed | Rationale |
| - | ---------------- | -------- | ------- | -------- | --------- |
| 1 | ... | file:line | Optional | required | ... |

## Runtime → Type Promotions

| # | Invariant | Location | Current | Proposed | Complexity |
| - | --------- | -------- | ------- | -------- | ---------- |
| 1 | ... | file:line | runtime guard | type constraint | low/med/high |

## Type-System Bypasses

| # | Location | Pattern | Classification | Action |
| - | -------- | ------- | -------------- | ------ |
| 1 | file:line | `Any` return | Remove | Fix type |

## Ergonomics

- Consumer branch count per variant: ...
- Boilerplate patterns: ...
- Extensibility: ...

## Recommendations (Priority Order)

1. **Must-fix**: {narrowing failures, forced casts, silent fallbacks masking bugs}
2. **Should-fix**: {defaults in wrong layer, always-present optionals}
3. **Consider**: {ergonomic improvements, extensibility prep}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: type invariants only.** Do not flag type design/architecture (→ type-hunter-py), module boundary issues
  (→ boundary-hunter-py), structural complexity (→ simplicity-hunter-py), class/interface design (→ solid-hunter-py),
  missing documentation (→ doc-hunter-py), security (→ security-hunter-py), error handling design (→ error-hunter-py),
  test quality (→ test-hunter-py), or cosmetic style (→ slop-hunter-py). If a finding doesn't answer "is this type
  tight enough?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact code.
- **Architecture-first.** Understand the project's intended layering before flagging violations. Ask if unclear.
- **Complexity honesty.** If encoding an invariant requires deeply nested generics or impractical Protocol gymnastics,
  say so and recommend runtime validation.
- **Challenge assumptions.** If the current type design makes a deliberate trade-off, acknowledge it rather than
  mechanically flagging it.
- **Prioritize**: dead fallbacks > representational correctness > tagged unions > optional strictness flags.
  Assess cascading effects — removing fallbacks may trigger unused variable warnings; include cleanup.
