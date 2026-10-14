---
name: invariant-hunter
description: |
  Use when reviewing Go, Python, or TypeScript code for invariants left to runtime, convention,
  or type assertions: tightening a domain model after prototyping, reducing casts and
  type-system bypasses, reviewing optionality and discriminated unions, or establishing a
  safety baseline before a refactor. Defaults to the codebase.

  Covers unguarded type assertions, loose optionality, defensive access in non-boundary code,
  leaky discriminated unions, runtime checks promotable to types, type-system bypasses, and
  Go's unchecked errors, nil pointer risks, zero-value traps, error chain correctness, context
  misuse, panic/recover misuse, and race conditions.
disable-model-invocation: true
---

# Invariant Hunter

Audit code for **invariants that are assumed rather than enforced** — a property that must hold ("this field is
present after construction", "this error is handled", "this map is only touched under the lock", "this value was
validated") that the code hopes for instead of guaranteeing. Goal: **guarantees established at construction boundaries
hold throughout downstream code, consumers narrow without casts, and invalid states are caught where data is created.**

Supports Go, Python, TypeScript via per-language reference files.

**Not covered (owned by other hunters):** type *structure* — Duplicated Type Declarations (a sibling type, a runtime
value, or a schema as source), Generics That Never Vary, Loose Type Parameter Constraints, Over-Powered Type
Constructs, Enum Construct Mechanics, Alias vs Named Type Mechanics (→ type-hunter); how errors are structured,
caught, and converted — empty catches, catch-and-log, catch-and-return-default, `raise from` / `Error.cause`
(→ error-hunter);
trust-boundary *content* validation and exploitability (→ security-hunter); a guard the type already rules out
(→ simplicity-hunter, Dead Code Paths); optional fields with no discriminant yet, method call order, identity and
unit types with no validation boundary (→ smell-hunter); linter suppressions and wrapping-message redundancy
(→ slop-hunter); test quality (→ test-hunter). Where ownership is *contested*, the category's **Ownership:** note in
What to Hunt is authoritative.

## When to Use

- Tightening a domain model after initial prototyping
- Reducing `as`, `cast()`, `x.(T)`, `!`, `any` / `Any`, and checker suppressions across a codebase
- Migrating optional or defaulted fields to required fields with construction-boundary defaults
- Reviewing discriminated unions for a single discriminant and exhaustive consumers
- Go: raising error-handling, nil-safety, and concurrency discipline; reviewing zero-value safety
- Establishing a safety baseline before a refactor, or after enabling stricter checker flags

## Quick Reference

Full rules in **What to Hunt**; every finding must also clear Not-a-finding and the category's evidence bar. Category
names are canonical: the heading here, in What to Hunt, and in the report are identical. Universal categories run only
where the language reference declares them applicable (see Applicability); *(conditional)* on a heading marks a
universal category that is n/a for at least one language (here: Go). Go-only categories are defined in
`references/invariant-go.md`.

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Unguarded Type Assertions | Type claim with no guard and no type definition tying a check to it | Guard, predicate, schema parse, two-value form, `satisfies` | Missing content validation at the boundary → security-hunter; an assertion or switch arm compensating for one implementor of a *contract type* → solid-hunter (Broken Substitution); a cast in a generic body that a tighter constraint removes → type-hunter (Loose Type Parameter Constraints) |
| Loose Optionality | Optional field or parameter always present after construction | Make it required at the construction boundary | Mutually exclusive optionals, no discriminant → smell-hunter (Temporary Field) |
| Defensive Access in Non-Boundary Code | `?.` / `??` / `is not None` / `or default` on a value always present here | Tighten the upstream type; the guard then falls away | Guard the type already rules out → simplicity-hunter (Dead Code Paths) |
| Leaky Discriminated Unions | Parallel flag, no exhaustiveness arm, leaking field, cast past the discriminant | One discriminant; compile-time exhaustiveness; variant-scoped fields | No discriminant yet, and Go tagged structs → smell-hunter (Temporary Field); narrowing on a *contract type*, and the cost of extending a scattered variant set → solid-hunter |
| Runtime Checks Promotable to Types | A guard or validation a type could carry | Promote, or keep runtime with a stated reason | Identity and unit types with no validation boundary → smell-hunter (Primitive Obsession) |
| Type-System Bypasses | `any` / `Any`, double cast, checker suppression | Fix the type; else justify, scope, track | Silent fallback on error → error-hunter; linter suppressions → slop-hunter; an `any` bridge in a generic body that a tighter constraint removes → type-hunter (Loose Type Parameter Constraints) |
| Unchecked Errors *(Go only)* | Error return discarded or ignored | Handle, propagate, or discard with a verified comment | `_ = x` on a non-error binding → slop-hunter |
| Nil Pointer Risks *(Go only)* | Dereference with no guard on a path that can carry nil | Check the error or the `ok` first; document nil semantics | Guard already guaranteed → simplicity-hunter |
| Zero-Value Traps *(Go only)* | Exported type usable at zero value yet invalid there; an unchecked zero sentinel; external input converted to a named constant type with no range check | Constructor, unexported type, or a documented zero-value contract | Method call order on a valid value → smell-hunter (Temporal Coupling) |
| Error Chain Correctness *(Go only)* | `%v` where the chain is matched; no `Unwrap`; string comparison of errors | `%w`, `Unwrap`, `errors.Is` / `errors.As` | Wrapping-message redundancy → slop-hunter |
| Context Misuse *(Go only)* | Propagation severed, cancellation never consulted, cancel func not called on every path | Propagate the incoming context; consult it; cancel on every path | — |
| Panic/Recover Misuse *(Go only)* | `panic` reachable by callers; `recover` to continue | Return an error; limit `recover` to goroutine and request tops | — |
| Race Conditions *(Go only)* | Shared state touched from several goroutines without synchronization | Mutex, atomic, or channel ownership | Exploitability → security-hunter; `-race` in tests → test-hunter |

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`test-hunter-go`, `doc-hunter-py`, `security-hunter-ts`): route to the one matching the finding's language.

## Core Principles

1. **Enforcement, not design.** The question here is "does the code guarantee this invariant, or merely hope?"
   Whether a type is well-shaped, derived from one source of truth, or no more generic than needed is type-hunter's
   question. Optionality, union hygiene, and unguarded narrowing are enforcement questions and live here.

2. **Resolve at construction boundaries.** Defaults and validation belong where a value is created or enters the
   system: constructors, factories, `New*` functions, parse steps, handlers, config loaders. Downstream code requires
   valid input. If every caller checks the same condition, the check belongs in the constructor.

3. **Every optional is a branch.** `?:`, `Optional[T]`, `T | None` mean the consumer must handle absence. Optional
   is for domains that permit absence, not a convenience for callers.

4. **A guard is behaviour, not a library name.** Whether a check guards a value is decided by what happens on its
   failure path — see Terms. `schema.parse(x)` and a hand-written `assertUser(x)` are judged the same way.

5. **Types end at runtime boundaries.** `(await res.json()) as User` compiles and guarantees nothing. External input
   needs a parse whose result carries the type. The cast is this skill's finding; the missing content validation is
   security-hunter's.

6. **Comments are claims; the code is evidence.** `// read-only; close error carries nothing` is checked against the
   open mode, not trusted. Repository policy is handled in Phase 1 step 5.

7. **Scans nominate; reading decides.** Nothing is a finding until its producers and consumers have been read. An
   optional field is loose only after every producer and every later write are known.

8. **Bypasses must be justified, scoped, and tracked.** `any`, `Any`, double casts, and checker suppressions each
   need a reason, a boundary-layer home, and tracked debt. A bypass that is bare **or** sits in domain code is the
   finding.

## Terms

- **Guard** — a runtime check that narrows a type or establishes a fact: `if x != nil`, `isinstance`, a type
  predicate, a two-value type assertion, a schema validation. A validation guards by behaviour, in three cases:
  a failure-*returning* API (`safeParse`, io-ts `decode`) guards only when the failure branch is inspected; a
  *throwing*, validation-only check guards the unchanged input even when its return value is discarded; a
  *transforming* validation (coercion, defaults, sanitizing) guards only the returned value, so the claimed property
  holds for the output, not the input.
- **Unguarded assertion** — a type claim whose asserted property has insufficient evidence: no preceding guard, and no
  representation or construction contract that ties a preceding check to the claimed property. A check the checker
  cannot correlate still counts as evidence when the type definition establishes the relationship (variant class,
  `Literal`-discriminated dataclass, `Extract` on a discriminant).
- **Bypass** — a construct that disables checking rather than claiming one type: `any` / `Any`, `as any`,
  `as unknown as T`, `@ts-ignore`, `@ts-expect-error`, `# type: ignore`, `# pyright: ignore`.
- **Discriminant** — the field whose value selects a union variant. Its *existence* is the ownership test with
  smell-hunter's Temporary Field: no discriminant yet → smell-hunter; discriminant present → here.
- **Construction boundary** — where a value is created or enters the system. **Trust boundary** — a construction
  boundary whose input is external (wire, user, file, env). Runtime validation there is mandatory and never a finding;
  validation *missing* there is a finding here for the unguarded type claim and security-hunter's for the content.
- **Boundary layer** — a module whose job is adapting external code (FFI bindings, third-party SDK wrappers,
  deserializers), or one that repository instructions name as such. **Domain code** — every other module.
- **Tracked** — a bypass comment that cites an issue or ticket ID, or a TODO with a named owner.
- **Closed consumer set** — the per-symbol rule for Loose Optionality's construction-and-mutation argument. An exported
  type whose unit is closed is judged in tree, export alone being no limit; one whose unit is open has producers and
  writers outside the tree that cannot be enumerated, and is **withdrawn** when its contract permits omission. The
  question is asked per exported type, from the unit that exports it; no repository-wide classification. Closed and open
  follow boundary-hunter's **Published unit** definition, copied here: **any evidence of documented import use opens the
  set** (mixed → open → withdrawn). **Closed** (judged in tree): Go — a `main` package; an `internal/` path; a package
  of a module that contains a `main` package **and** whose repository documents no import use (no `go get <module path>`
  line or quoted `"<module path>…"` import path in a README or doc, no `doc.go` on a non-main package, no `examples/`
  directory). TypeScript — a workspace package with `private: true`, or a unit not reachable from any `package.json`
  `exports` / `main`. Python — a `_`-prefixed or `internal` package; a distribution with a `Private :: Do Not Upload`
  classifier; a repository whose entry is a web or framework application (`manage.py`, `wsgi.py`, `asgi.py`). **Open**
  (withdrawn): Go — a module with no `main` package and a public module path, or any documented import use; TypeScript —
  reachable from `exports` / `main` without `private: true`; Python — a package a `[project]` / `[tool.poetry]`
  distribution declares with a public import path and none of the closing signals. `__main__.py` and `[project.scripts]`
  are **not** application signals — libraries ship CLIs that way. No release workflows or tags are read.
- **Target scope and context** — findings anchor in the manifest; producers, consumers, and callers outside it are
  read to judge them.

## Not a finding on these grounds alone

Conditionals, not category exemptions — each states what does **not** justify a finding and, where a corresponding
finding exists, what would:

- **A runtime-guarded assertion.** The cast or assertion follows a check the checker cannot correlate, *and* the type
  definition ties that check to the asserted property (`as Extract<…>` after a discriminant test on a discriminated
  union; `cast()` after `isinstance` on a sibling field of a variant class). *Is* a finding when the guard is absent,
  checks a different value, or when nothing in the representation makes `kind == 'leaf'` imply `config: Config`.
- **Defensive access at a trust boundary** — external API response, user input, config default. *Is* a finding when
  the value has already been resolved at the construction boundary and the guard sits downstream.
- **An optional utility parameter** on a helper that genuinely serves optional and required callers.
- **A bypass in a boundary layer with a comment and tracked debt** — FFI, a library's wrong types. *Is* a finding when
  bare, or when the same bypass appears in domain code.
- **A schema-validated boundary parse** whose downstream type is derived from the schema. `(await res.json()) as T`
  without a parse is never this.

Go adds its own cases (documented zero values, verified `_ = f()`, `recover` at goroutine tops, policy-endorsed
`panic`, type switches with no `default`) in `references/invariant-go.md`.

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Type-System Bypasses").

### Unguarded Type Assertions

A type claim whose asserted property lacks sufficient evidence (see Terms).

**Signals:**

- Go: bare `x.(T)`, assertion chains, assertions on `any` from JSON or config, open-interface type switches — markers
  and exceptions in `references/invariant-go.md`
- TypeScript: `as T` not preceded by a check; `x!` on a value that could be non-optional at its source;
  object-literal `as T` where `satisfies T` validates without widening; `(await res.json()) as T` and
  `JSON.parse(x) as T` with no schema parse — **never acceptable**
- Python: `cast()` not preceded by a check; `assert x is not None` written to satisfy the checker where the type
  should be non-optional

**Evidence bar:** name the guard present (`none`, `isinstance on sibling`, `zod parse`) and, when one is present,
why it does or does not reach the asserted property.

**Action:** two-value form or type switch (Go); guard, type predicate, assertion function, schema parse, or
`satisfies` (TypeScript); guard or tightened upstream type (Python).

**Ownership:** the unguarded type claim is here wherever it sits, including `(await res.json()) as T`. The missing
content validation at that boundary — schema coverage, ranges, formats — is security-hunter's. Until security-hunter
unifies, `security-hunter-ts` also flags the cast; the intended split is written here so one side is already fixed.
An assertion or type-switch arm that **compensates for one implementor of a contract type** — a behavioral
abstraction with methods — is solid-hunter's Broken Substitution, whatever the guard form; the guardedness is noted in
its Action, not scored again here. Assertions from `any` or open data (JSON, config, `interface{}` payloads), and
narrowing on a data variant set, stay here. Exception: a cast inside a generic body that a tighter type parameter
constraint removes (`as T`, `cast(T, x)`, Go `any(v).(X)` where `v` is a type parameter) is type-hunter's Loose Type
Parameter Constraints — one finding there, not scored here.

### Loose Optionality *(conditional)*

An optional field or parameter whose value is always present after construction, or becomes required after a
pipeline stage but stays optional throughout.

**Signals:**

- Optional field with `??` / `or default` / `if x is None` in every consumer
- Field that becomes present after a pipeline stage but carries `?:` / `| None` throughout
- Dataclass `field(default=None)` or `?:` always set before use

**Evidence bar:** the construction-and-mutation argument in one cell — every producer and every later write read
(assignments, `delete`, deserialization, aliasing). In a closed unit the repository *is* the world and the argument
can close; export alone is no limit. When the type's unit is open (see Closed consumer set in Terms) and its
contract permits omission, the finding is **withdrawn** and the limitation recorded in Scope.
Severity measures consequence, not confidence. A producer count proves nothing on its own.

**Action:** make required at the construction boundary. One finding per invariant: when this finding exists for a
field, its consumers' `??`, `?.`, `!`, `assert x is not None`, and `cast` sites are cited in Evidence, not reported
separately under Defensive Access or Unguarded Type Assertions.

**Ownership:** two optionals never both present, "only valid when X" — no discriminant exists yet — is smell-hunter's
Temporary Field, whose remedy introduces the per-state type. A discriminant present → Leaky Discriminated Unions.
Optionality is owned here in every language; type-hunter owns type structure, never optionality.

### Defensive Access in Non-Boundary Code *(conditional)*

`?.` / `??` / `is not None` / `or default` compensating for a type looser than the invariant, when the value is
always present in this context.

**Signals:**

- `?.` or `is not None` on a value always present given the current context
- `??` / `or default` applying a default already resolved at the construction boundary
- A shared helper using `??` / `or` to serve cases that should be separate functions

**Evidence bar:** the Guaranteed By cell names the upstream site that always sets the value.

**Action:** tighten the upstream type; the guard then becomes deletable.

**Ownership:** when the *type already guarantees* presence, the guard is simplicity-hunter's Dead Code Paths (delete
the guard). When the type is optional and the value is always present, it is here (tighten the type; the guard falls
away afterwards). Defensive access at a trust boundary is not a finding (see Not-a-finding).

### Leaky Discriminated Unions *(conditional)*

A union with a discriminant that is not the single source of truth, a consumer that must handle every variant with
no compile-time exhaustiveness enforcement, fields present on every variant but meaningful on some, or consumers that
cast past the discriminant instead of narrowing. The Python forms — `Literal` discriminant over dataclass variants,
a **variant hierarchy** (dataclass or sealed data classes carrying no overridable behavior) narrowed by `isinstance`,
`match` — are the same category.

**Signals:**

- A parallel boolean carrying the same fact as the discriminant (`kind` vs `isActive`)
- `switch` / `match` / `if-elif` over the discriminant whose consumer must cover every variant, with no enforcement
- Fields on every variant that are meaningful on some (TypeScript: missing `?: never`)
- A call site that casts to a variant instead of narrowing by control flow

**Exhaustiveness evidence bar:** the finding requires (a) a consumer that must cover every variant — not one that
deliberately handles a subset and does something meaningful in `default`; and (b) no enforcement already in place: no
`assertNever` / `assert_never` arm, no configured `switch-exhaustiveness-check` or `reportMatchNotExhaustive`, no
return type that makes the checker fail on a missing case. `else: raise` and `default: throw` are *runtime rejection*,
not exhaustiveness; they drop the finding to Low and are named in Action, they do not close it.

**Action:** one discriminant; a compile-time exhaustiveness arm; variant-scoped fields; narrow by control flow.

**Ownership:** the discriminant test (see Terms), plus the contract/variant test: a union of **data shapes** is here;
narrowing on a **contract type** to special-case an implementor is solid-hunter's Broken Substitution. Exhaustiveness
is owned here and never decides solid-hunter's extension-cost question — one union can carry a missing-arm finding
here and a Rigid Extension Points finding there, at different anchors. Go: n/a (see Applicability).

### Runtime Checks Promotable to Types

A guard, assertion, or validation that a type could carry.

**Signals:**

- A **validated-state** brand or named type — validated email, sanitized string, checked unit — travelling downstream
  as plain `string`
- Empty-check branches a non-empty type removes
- Boolean validators that should be type predicates, assertion functions, or `TypeGuard` / `TypeIs`
- Config objects that should be `as const`; mutable containers as config where `tuple` / `frozenset` would do

**Immutability is promotable only where the type blocks the actual mutation path.** TypeScript `Readonly<T>` and
`as const` are compile-time only, and a `Readonly<T>` is assignable to `T`, so even fully type-checked code writes
through an alias. In TypeScript they are therefore *adoption* findings at Low on values with no runtime guard; a
runtime mutation guard is never a candidate for replacement by them. Python `frozen=True`, `tuple`, `frozenset`
enforce at runtime but shallowly: a nested list or dict stays mutable, so they replace a guard only against
reassignment of the field or element itself, and the Proposed cell names any nested mutable content left unguarded.

**Go — narrowed** to validated-state named types; the zero-value rule is in `references/invariant-go.md`.

**Action:** promote, or keep runtime with a stated complexity reason. Cascading effects (removing a fallback trips
`noUnusedParameters`; requiring a field breaks a fixture) are named in the Action column.

**Ownership:** smell-hunter routes brands encoding validated state here for every language. An ID or unit with no
validation boundary is smell-hunter's Primitive Obsession — `NewType('UserId', str)` for a bare `user_id: str` is
not a finding here. A manual type beside a schema (`z.infer` candidates) is type-hunter's Duplicated Type Declarations.
A presence check (`if (node.config)`, `if node.config is not None`) after a discriminant test is not this category:
the variant type still marks the field optional → Leaky Discriminated Unions (`leaking field`); the variant type
already makes it required → simplicity-hunter's Dead Code Paths.

### Type-System Bypasses *(conditional)*

A construct that disables the checker: `Any` / `any` where a concrete type or `unknown` plus narrowing would do;
`as any`; `as unknown as T`; `# type: ignore` (with or without an error code); `# pyright: ignore`; `@ts-ignore`;
`@ts-expect-error`.

**Signals:**

- `any` / `Any` as parameter, return, or variable type without justification
- `as any`, `as unknown as T`, `<any>` — a bypass inside a `catch` (`catch (e) { throw e as any }`) is still here
- A checker suppression with no error code, no trailing reason, or in domain code

**Evidence bar:** the Justification cell is `none`, `bare`, or the quoted reason. A quoted reason is verified against
the code the way any comment is.

**Action:** fix the underlying type. If the bypass is necessary, justify it, scope it to a boundary layer, track it.

**Ownership:** owned **wholly** here, including "does it have a reason?" — two hunters must not score one line.
slop-hunter keeps *linter* suppressions: `# noqa`, `# pylint: disable`, `# pragma: no cover`, `// eslint-disable*`,
`// biome-ignore`, `//nolint`. Silent fallbacks on invalid input (`return []`, `return null`) are error-hunter's. A
bypass inside a generic body that a tighter type parameter constraint removes (`(o as any)[k]`, `cast(Any, x)`) is
type-hunter's Loose Type Parameter Constraints — one finding there, not scored here.

### Within-skill routing

A *single* type claim (`as T`, `cast(T, x)`, `x!`, `x.(T)`) is an Unguarded Type Assertion. A construct that
*disables* checking (`any`, `Any`, double cast, ignore directive) is a Type-System Bypass. A cast to a union variant
(`s as Leaf`, `cast(Leaf, s)`) on a value whose union has a discriminant is Leaky Discriminated Unions
(`cast past discriminant`), not an Unguarded Type Assertion. One finding per site.

### Go-only categories

Defined entirely in `references/invariant-go.md`: signals, evidence bars, ownership, scans, evaluation, and table
schemas — **Unchecked Errors**, **Nil Pointer Risks**, **Zero-Value Traps**, **Error Chain Correctness**, **Context
Misuse**, **Panic/Recover Misuse**, **Race Conditions**. They are Go-only because Python and TypeScript route error
handling to error-hunter and Go has no error-hunter. Listed here so the category set is complete in one place.

## Applicability

Six categories are universal in definition. Each language reference declares them applicable or not, with the
reason. **A language with no reference is not supported** — its files are excluded, never implicitly audited.

| Universal category | Go | Python | TypeScript |
| ------------------ | -- | ------ | ---------- |
| Unguarded Type Assertions | yes | yes | yes |
| Loose Optionality | **n/a** — no optional type; Nil Pointer Risks covers the crash surface | yes | yes |
| Defensive Access in Non-Boundary Code | **n/a** — redundant nil guards are simplicity-hunter's; the "loose type" half has no Go form | yes | yes |
| Leaky Discriminated Unions | **n/a** — type-switch exhaustiveness is a marker under Unguarded Type Assertions; tagged structs stay smell-hunter's Temporary Field | yes | yes |
| Runtime Checks Promotable to Types | **yes, narrowed** to validated-state named types | yes | yes |
| Type-System Bypasses | **n/a** — `any` overuse is not claimed by any Go hunter and is not invented here | yes | yes |

Language-only categories: the seven Go categories above. Python and TypeScript have none.

## Test-code scope

**Test files are excluded from every category** — the deliberate deviation from the sibling hunters, which keep test
code in scope. Invariants are production guarantees; a panicking assertion, `as any` on a mock, or an ignored error
in a test is the intended failure mode or test-hunter's hygiene. Each language reference's eligibility rule lists
its test paths. The exclusion is by path: a helper imported by production code from a non-test
path is audited; a production helper under `tests/` is not.

Test files are still read as **context** — a test can prove a value is nil-able.

**Recorded gap:** an unexplained `@ts-ignore` / `# type: ignore` inside a test file has no owner. slop-hunter ceded
type-checker suppressions to this skill, and this skill excludes tests. Suppression hygiene in tests is test-hunter's
kind of check, and no `test-hunter-*` has the category yet — resolved at test-hunter's unification. A chosen
trade-off, not a technical limit.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is:**

- **Critical** — the finding names all four: the triggering input, the violated contract, the downstream consequence
  (data loss, crash, corrupted state), and why nothing contains it. An unchecked error on a write path whose caller
  reports success; `json() as T` on a public route where the wrong shape reaches a write; a data race on state the
  server mutates per request. A cast or panic being *reachable* is not Critical by itself; the finding takes the
  severity its shown consequence supports, and an unknown consequence is stated as such.
- **High** — a crash or silent wrong result awaiting the first unexpected value: nil dereference after an unchecked
  error; an open-interface type switch that silently yields a zero value; `%v` where a caller matches with
  `errors.Is`.
- **Medium** — the invariant holds today by convention only: optional field always set; defensive access in
  non-boundary code; a bypass without justification; a missing exhaustiveness arm with no runtime rejection.
- **Low** — hygiene and adoption: `satisfies` over object-literal `as`; `as const` on fixed tables; strictness flags
  off; adopting `errcheck`; documenting a zero-value contract; a missing exhaustiveness arm whose consumer ends in
  runtime rejection (`else: raise`, `default: throw`).

**Impact — how much the change is worth:** defect exposure reduced, cognitive burden reduced, surface affected.
Contextual; never derived from occurrence count. Forty `?.` on one hot type read in every handler are High impact at
Medium severity.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

Recommendations group by Severity (Critical → High → Medium → Low), then by Impact within each group.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve the raw manifest.** Scope may be:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked. Resolve it with
     `references/diff-scope.md`.
   - **Path**: specific files, folders, or packages — `SCOPE=$(git ls-files --cached --others --exclude-standard
     -- <paths>)`, which expands folders to files
   - **Codebase**: the entire project (default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line): `SCOPE=$(cat <snapshot>/scope.txt)`. Read run metadata (base SHA — `$MB` in diff mode —
   surface kind, counts) from `scope-meta.txt` when present. Use the manifest verbatim; do not re-resolve. The
   resolution above is for standalone runs only.

   **Persist run state.** Shell variables do not survive between tool calls, and `rg … --` with an empty variable
   searches the whole working directory. Create one run directory (`RUN=$(mktemp -d) && echo "$RUN"`) and use the
   printed path literally from then on. Every call starts at the repository root (`cd "$(git rev-parse
   --show-toplevel)"`), because every list holds root-relative paths. Write `$SCOPE` to `<run>/scope.txt` and, in diff mode, `$MB` to `<run>/mb`.
   A later call restores what it uses (`SCOPE=$(cat <run>/scope.txt)`); an empty restore is a STOP, never an empty
   result. If the resolved surface exceeds the context budget, report the file count and ask to narrow or chunk.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section. On a dirty tree, line numbers match no
   commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent. Do not redefine it on a mixed scope — silently
   narrowing breaks the party guarantee that all hunters audit the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from manifest extensions alone:
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**: without a reference there is no eligibility rule, no scan set, no
   evidence form, no toolchain contract. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming
   each extension.

3. **Load language references.** For every detected language, read `references/invariant-<lang>.md` from the
   directory this SKILL.md was read from (e.g. `references/invariant-go.md`). **Fail closed:** if a required
   reference cannot be read, **stop and report**; do not continue with universal categories only.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus
   the test-path exclusion** to that language's files. These subsets are then immutable. Record in Scope: raw
   manifest count, each per-language eligible subset, exclusions with the test paths listed, and
   `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, Markdown-only inputs, test paths, and generated files
   identified by each reference's authoritative **in-file marker** — **never** by filename guessing.

   Write each subset to `<run>/<lang>.txt` (`go.txt`, `python.txt`, `typescript.txt`). Codebase mode: the single line
   `.`. Diff and path mode: the eligible files, one per line — `comm -12 <(rg --files --type <t> $EXCLUDE | sort)
   <(printf '%s\n' $SCOPE | sort)` with the loaded reference's `--type` and `$EXCLUDE`, minus files carrying a
   generated-code marker (`| while read -r f; do rg -q -m1 '<marker>' "$f" || echo "$f"; done`, the marker regex built
   from the reference's eligibility section); the reference's generated-file globs are the same scan approximation a
   codebase run uses. Filter before scanning: `rg` applies `--type` and `--glob` only while walking a folder and
   searches every file named on its command line. Each scan call restores its list first — `GO_FILES=$(cat
   <run>/go.txt)` (`PY_FILES`, `TS_FILES`) — and the reference blocks pass it as `rg -H … -- $GO_FILES`: given one file,
   `rg` prints no file name unless `-H` is set.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop
   before scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Files outside it, test files included, are *read* as **context**: judging whether an optional field is
   always present requires reading every producer, wherever it lives. Diff and path scope narrow the manifest, never
   the context reading.

5. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) for stated policies:
   panic-on-invariant conventions, boundary layers, sanctioned escape hatches, and how the project runs its own
   checks. A stated policy is respected, acknowledged in the report's `Policy:` line, and overridden only where the
   pattern is reachable from untrusted input. This step precedes the toolchain so no command runs against the
   project's instructions.

6. **Run the toolchain — the project's own invocation, never installed or reconfigured.** Each loaded reference's
   Toolchain section names the adoption evidence, the exact read-only command, and the strictness flags to read.

   Four outcomes per tool, recorded in Scope: **ran**, **skipped — not configured**, **skipped — configured, not
   installed**, **errored** (a non-analysis failure). "Ran" records the exact command, the tool version, the package
   coverage, and the options that change what it sees. Tool output is a nomination list, triaged like a scan.

   Strictness flags are recorded whether or not the tool ran, because several evidence bars depend on them. Flags
   off: findings are still reported — the code's invariants do not depend on the checker's settings — and one Low
   recommendation names the flag.

   Toolchain skipped or errored: the heuristic scans run alone and the report says so. Analyzers and checks that ran
   are never "recommended for enabling".

### Phase 2: Scan for Candidates

Scans produce **candidates only**. For each loaded reference, run its Phase 2 scan block against the eligible list
written in Phase 1 step 4: restore `<run>/<lang>.txt` into `GO_FILES` / `PY_FILES` / `TS_FILES` in the same call
as the scans (`.` in codebase mode, files in diff and path mode). Never run a scan with `$SCOPE`. Diff mode nominates
from the working tree over the manifest files, not from added lines: an invariant is a property of the current code,
and a manifest file's producers and consumers are read wherever they live.

### Phase 3: Trace Producers and Consumers

For each optional field, union, and asserted value nominated: read every producer (constructors, factories,
deserialization) and every later write (assignment, `delete`, aliasing), then every consumer. This is where Loose
Optionality closes or is withdrawn, where a union's consumers are classified as must-cover-every-variant or
deliberate-subset, and where a guard is located for each assertion. Test files are read here as context.

### Phase 4: Classify Runtime Checks

For each runtime guard, assertion, or validation nominated:

- **Promote to type** — a type can carry it and blocks the actual failure path (see the immutability rule).
- **Keep as runtime** — trust boundary, serialization, or excessive type complexity; the Complexity cell names which
  (see report-format.md).
- **Delete** — the type already guarantees it → simplicity-hunter's Dead Code Paths; cross-reference, do not score.

### Phase 5: Evaluate Each Finding

For each candidate: apply Not-a-finding first; confirm the category is applicable to that file's language; apply the
within-skill routing (assertion vs. bypass; guard-guaranteed-by-type vs. loose type); clear the category's evidence
bar from What to Hunt; check repository policy (Phase 1 step 5). Run each loaded reference's
Phase 5 block for its language-only categories and language-specific judgment.

Assign **Severity and Impact** to every finding (both required; they diverge). One finding per site. Nothing is held
back; `Audit completed: N findings` counts every reported finding.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-invariant-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or
return mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas. Go-only categories use
the table schemas supplied in `references/invariant-go.md`.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "The scan matched an `as` — finding" | Scans nominate. Where is the guard, and does the type definition tie it to the claim? |
| "Three constructors set it, so it's always present" | And every later write? `delete`, deserialization, aliasing, callers outside the repository. No bounded argument, no finding. |
| "It's an exported type, so I can't know" | Export alone is no limit. A closed unit: the repository is the world. An open unit whose type permits omission: withdraw. |
| "The cast is reachable from a request — Critical" | Name the input, the contract, the consequence, and why nothing contains it. Otherwise the shown consequence sets the severity. |
| "There's a `default: throw`, so it's exhaustive" | Runtime rejection drops the finding to Low; it is not compile-time exhaustiveness. Is an `assertNever` arm or lint configured? |
| "`schema.parse(x)` ran, so `x` is guarded" | Does the schema coerce or default? Then only the output is guarded. Was `safeParse`'s failure branch inspected? |
| "`Readonly<T>` would enforce this" | It compiles away and is assignable to `T`. Adoption at Low; never a replacement for a runtime guard. |
| "This `?.` is redundant" | Is the type optional? Then tighten it (here). Is the type already non-optional? Then simplicity-hunter deletes the guard. |
| "Bare `# type: ignore` — slop's" | Type-checker suppressions are here, wholly. Linter suppressions are slop's. |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do universal categories only" | Fail closed. Stop and report. |

Go-only red flags are in `references/invariant-go.md`.

## Operating Constraints

- **No code edits.** Audit report only. Implementation is a separate step.
- **The report is the template.** `references/report-format.md` fixes the shape: Scope, then one section per
  category with at least one finding, then Recommendations. A category with no findings gets no heading, table,
  or "none found" line.
- **Scope: invariant enforcement only.** A finding that doesn't answer "is this invariant enforced?" belongs to
  another hunter. Contested boundaries are resolved at the category that owns them: each **Ownership:** note in What
  to Hunt states what is kept here and what routes away.
- **Evidence required.** Every finding cites `file:line` (path form per the language reference) with the exact code,
  and the category's evidence column — named in report-format.md or the language reference's table schema — is
  filled, never inferred.
- **One finding per site.** When two categories describe the same code, pick the primary one and cross-reference.
  The within-skill routing rule is the worked example.
- **Never install.** A tool that is configured but absent is `skipped`, never fetched.
- **Architecture-first.** Understand the project's stated conventions before flagging (Phase 1 step 5).
- **Complexity honesty.** Some invariants are expensive to encode. When recommending a runtime check instead, say
  so, and name the complexity in the Complexity cell.
- **Handoff, not duplication.** When a candidate belongs to another hunter — a guard the type rules out, a silent
  catch, a bare `# noqa`, a temporary field with no discriminant — cross-reference it and do not score it here.
