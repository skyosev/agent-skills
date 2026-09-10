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

**Not covered (owned by other hunters):** type *design* — duplication, derivations, generics, alias-vs-named
mechanics, enum patterns, schema-vs-manual duplication (→ type-hunter); how errors are structured, caught, and
converted — empty catches, catch-and-log, catch-and-return-default, `raise from` / `Error.cause` (→ error-hunter);
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
where the language reference declares them applicable (see Applicability). Go-only categories are defined in
`references/invariant-go.md`.

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Unguarded Type Assertions | Type claim with no guard and no type definition tying a check to it | Guard, predicate, schema parse, two-value form, `satisfies` | Missing content validation at the boundary → security-hunter |
| Loose Optionality | Optional field or parameter always present after construction | Make it required at the construction boundary | Mutually exclusive optionals, no discriminant → smell-hunter (Temporary Field) |
| Defensive Access in Non-Boundary Code | `?.` / `??` / `is not None` / `or default` on a value always present here | Tighten the upstream type; the guard then falls away | Guard the type already rules out → simplicity-hunter (Dead Code Paths) |
| Leaky Discriminated Unions | Parallel flag, no exhaustiveness arm, leaking field, cast past the discriminant | One discriminant; compile-time exhaustiveness; variant-scoped fields | No discriminant yet, and Go tagged structs → smell-hunter (Temporary Field) |
| Runtime Checks Promotable to Types | A guard or validation a type could carry | Promote, or keep runtime with a stated reason | Identity and unit types with no validation boundary → smell-hunter (Primitive Obsession) |
| Type-System Bypasses | `any` / `Any`, double cast, checker suppression | Fix the type; else justify, scope, track | Silent fallback on error → error-hunter; linter suppressions → slop-hunter |
| Unchecked Errors *(Go only)* | Error return discarded or ignored | Handle, propagate, or discard with a verified comment | `_ = x` on a non-error binding → slop-hunter |
| Nil Pointer Risks *(Go only)* | Dereference with no guard on a path that can carry nil | Check the error or the `ok` first; document nil semantics | Guard already guaranteed → simplicity-hunter |
| Zero-Value Traps *(Go only)* | Exported struct usable at zero value yet invalid there | Constructor, unexported type, or a documented zero-value contract | Method call order on a valid value → smell-hunter (Temporal Coupling) |
| Error Chain Correctness *(Go only)* | `%v` where the chain is matched; no `Unwrap`; string comparison of errors | `%w`, `Unwrap`, `errors.Is` / `errors.As` | Wrapping-message redundancy → slop-hunter |
| Context Misuse *(Go only)* | Propagation severed, cancellation never consulted, cancel func not called on every path | Propagate the incoming context; consult it; cancel on every path | — |
| Panic/Recover Misuse *(Go only)* | `panic` reachable by callers; `recover` to continue | Return an error; limit `recover` to goroutine and request tops | — |
| Race Conditions *(Go only)* | Shared state touched from several goroutines without synchronization | Mutex, atomic, or channel ownership | Exploitability → security-hunter; `-race` in tests → test-hunter |

Hunter names are unsuffixed end-state names. Until consolidation completes, live skills are language-suffixed
(`type-hunter-go`, `error-hunter-py`, `security-hunter-ts`, and so on).

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
   open mode, not trusted. A project policy in `CLAUDE.md` withdraws the patterns it names — and nothing reachable
   from untrusted input.

7. **Scans nominate; reading decides.** Nothing is a finding until its producers and consumers have been read. An
   optional field is loose only after every producer and every later write are known.

8. **Bypasses must be justified, scoped, and tracked.** `any`, `Any`, double casts, and checker suppressions each
   need a reason, a boundary-layer home, and tracked debt. Bare, in domain code, is the finding.

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
- **Target scope and context** — findings anchor in the manifest; producers, consumers, and callers outside it are
  read to judge them.

## Not a finding on these grounds alone

Conditionals, not category exemptions — each states what does **not** justify a finding and, where a corresponding
finding exists, what would:

- **A runtime-guarded assertion.** The cast or assertion follows a check the checker cannot correlate, *and* the type
  definition ties that check to the asserted property (`as Extract<…>` after a discriminant test on a discriminated
  union; `cast()` after `isinstance` on a sibling field of a variant class). *Is* a finding when the guard is absent,
  checks a different value, or when nothing in the representation makes `kind == 'leaf'` imply `config: Config`.
- **Defensive access at a true boundary** — external API response, user input, config default. *Is* a finding when
  the value has already been resolved at the entry point and the guard sits downstream.
- **An optional utility parameter** on a helper that genuinely serves optional and required callers.
- **A bypass in a boundary layer with a comment and tracked debt** — FFI, a library's wrong types. *Is* a finding when
  bare, or when the same bypass appears in domain code.
- **A schema-validated boundary parse** whose downstream type is derived from the schema. `(await res.json()) as T`
  without a parse is never this.
- **A zero-value struct designed and documented for zero-value use** (Go). *Is* a finding when a method panics on it.
- **`_ = f()` with a justifying comment that the code confirms** — `Close` on a file opened read-only, a logger
  flush (Go). The comment is evidence to verify, not an exemption: *is* a finding on a write path whatever the
  comment says, and with no comment.
- **`recover` at the top of a goroutine or in HTTP middleware** to keep one request from crashing the process (Go).
- **`panic` in `init()` or in constructors when the project's instructions endorse it** (Go). Cite the policy in
  Scope. *Is* a finding when reachable from a trust boundary regardless of policy.
- **A type switch with no `default`** (Go) over a sealed interface (the finite set is known), or over an open
  interface where the code after the switch returns an error, a sentinel, or a deliberate fallback. *Is* a finding
  when unmatched values silently produce a zero value the contract does not permit.
- **A pattern in a test file** — never a finding; test files are out of scope, not exempt (see Test-code scope).

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Type-System Bypasses").

### Unguarded Type Assertions

A type claim whose asserted property lacks sufficient evidence (see Terms).

**Signals:**

- Go: `x.(T)` without the two-value form; assertion chains `x.(A).f.(B)`; assertions on `any` from JSON or config;
  a type switch over an *open* interface whose contract requires handling or rejecting every value, yet the code
  after the switch neither rejects nor deliberately falls back. `fmt`'s `handleMethods` switches on `error` and
  `Stringer` and returns `false` for everything else by design — not a finding
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

### Loose Optionality *(conditional)*

An optional field or parameter whose value is always present after construction, or becomes required after a
pipeline stage but stays optional throughout.

**Signals:**

- Optional field with `??` / `or default` / `if x is None` in every consumer
- Field that becomes present after a pipeline stage but carries `?:` / `| None` throughout
- Dataclass `field(default=None)` or `?:` always set before use

**Evidence bar:** the construction-and-mutation argument in one cell — every producer and every later write read
(assignments, `delete`, deserialization, aliasing). In application code the repository *is* the world and the
argument can close; export alone is no limit. When the type is constructible outside the repository — a library's
public type — and its contract permits omission, the finding is **withdrawn** and the limitation recorded in Scope.
Severity measures consequence, not confidence. A producer count proves nothing on its own.

**Action:** make required at the construction boundary. One finding per invariant: the consumers' `??` sites are
cited as evidence, not reported separately under Defensive Access.

**Ownership:** two optionals never both present, "only valid when X" — no discriminant exists yet — is smell-hunter's
Temporary Field, whose remedy introduces the per-state type. A discriminant present → Leaky Discriminated Unions.
Optionality is owned here in every language; type-hunter keeps type design.

### Defensive Access in Non-Boundary Code *(conditional)*

`?.` / `??` / `is not None` / `or default` compensating for a type looser than the invariant, when the value is
always present in this context.

**Signals:**

- `?.` or `is not None` on a value always present given the current context
- `??` / `or default` applying a default already resolved at the entry point
- A shared helper using `??` / `or` to serve cases that should be separate functions

**Evidence bar:** the Guaranteed By cell names the upstream site that always sets the value.

**Action:** tighten the upstream type; the guard then becomes deletable.

**Ownership:** when the *type already guarantees* presence, the guard is simplicity-hunter's Dead Code Paths (delete
the guard). When the type is optional and the value is always present, it is here (tighten the type; the guard falls
away afterwards). Defensive access at a true boundary is not a finding (see Not-a-finding).

### Leaky Discriminated Unions *(conditional)*

A union with a discriminant that is not the single source of truth, a consumer that must handle every variant with
no compile-time exhaustiveness enforcement, fields present on every variant but meaningful on some, or consumers that
cast past the discriminant instead of narrowing. The Python forms — `Literal` discriminant over dataclass variants,
a class hierarchy narrowed by `isinstance`, `match` — are the same category.

**Signals:**

- A parallel boolean carrying the same fact as the discriminant (`kind` vs `isActive`)
- `switch` / `match` / `if-elif` over the discriminant whose consumer must cover every variant, with no enforcement
- Fields on every variant that are meaningful on some (TypeScript: missing `?: never`)
- A call site that casts to a variant instead of narrowing by control flow

**Exhaustiveness evidence bar:** the finding requires (a) a consumer that must cover every variant — not one that
deliberately handles a subset and does something meaningful in `default`; and (b) no enforcement already in place: no
`assertNever` / `assert_never` arm, no configured `switch-exhaustiveness-check` or `reportMatchNotExhaustive`, no
return type that makes the checker fail on a missing case. `else: raise` and `default: throw` are *runtime rejection*,
not exhaustiveness; they lower severity and are named in Action, they do not close the finding.

**Action:** one discriminant; a compile-time exhaustiveness arm; variant-scoped fields; narrow by control flow.

**Ownership:** the discriminant test (see Terms). Go: n/a — type-switch exhaustiveness is a Go marker under Unguarded
Type Assertions; Go has no compile-time exhaustiveness for type switches, so `default: panic` is the best available
and is not a finding there. A Go tagged struct with fields meaningful only in some states stays smell-hunter's
Temporary Field whether or not a tag exists.

### Runtime Checks Promotable to Types

A guard, assertion, or validation that a type could carry.

**Signals:**

- `if (node.config)` / `if node.config is not None` where the discriminant already guarantees it
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

**Go — narrowed** to validated-state named types (unexported field, `New*` returning `(T, error)`) whose constructor
is the only *non-zero* producer. Go cannot stop `pkg.T{}` or `var x pkg.T`: the proposal must also say what the zero
value does — safe by design, or rejected on use (`IsZero`, a method returning an error). A proposed type whose zero
value would be usable and invalid is a Zero-Value Traps finding first.

**Action:** promote, or keep runtime with a stated complexity reason. Cascading effects (removing a fallback trips
`noUnusedParameters`; requiring a field breaks a fixture) are named in the Action column.

**Ownership:** smell-hunter routes brands encoding validated state here for every language. An ID or unit with no
validation boundary is smell-hunter's Primitive Obsession — `NewType('UserId', str)` for a bare `user_id: str` is
not a finding here. Schema-vs-manual type duplication (`z.infer` candidates) is type-hunter's.

### Type-System Bypasses *(conditional)*

A construct that disables the checker: `Any` / `any` where a concrete type or `unknown` plus narrowing would do;
`as any`; `as unknown as T`; `# type: ignore` (without an error code, or at all); `# pyright: ignore`; `@ts-ignore`;
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
`// biome-ignore`, `//nolint`. Silent fallbacks on invalid input (`return []`, `return null`) are error-hunter's.

### Within-skill routing

A *single* type claim (`as T`, `cast(T, x)`, `x!`, `x.(T)`) is an Unguarded Type Assertion. A construct that
*disables* checking (`any`, `Any`, double cast, ignore directive) is a Type-System Bypass. One finding per site.

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
| Leaky Discriminated Unions | **n/a** — type-switch exhaustiveness is a marker under Unguarded Type Assertions | yes | yes |
| Runtime Checks Promotable to Types | **yes, narrowed** to validated-state named types | yes | yes |
| Type-System Bypasses | **n/a** — `any` overuse is not claimed by any Go hunter and is not invented here | yes | yes |

Language-only categories: the seven Go categories above. Python and TypeScript have none.

## Test-code scope

**Test files are excluded from every category** — the deliberate deviation from the sibling hunters, which keep test
code in scope. Invariants are production guarantees; a panicking assertion, `as any` on a mock, or an ignored error
in a test is the intended failure mode or test-hunter's hygiene. Each language reference's eligibility rule adds the
test-path exclusion: Go `*_test.go`; Python `test_*.py`, `*_test.py`, `tests/`, `conftest.py`; TypeScript `*.test.*`,
`*.spec.*`, `*.e2e.*`, `__tests__/`. The exclusion is by path: a helper imported by production code from a non-test
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
  non-boundary code; a bypass without justification; a missing exhaustiveness arm on a union that is not currently
  growing.
- **Low** — hygiene and adoption: `satisfies` over object-literal `as`; `as const` on fixed tables; strictness flags
  off; adopting `errcheck`; documenting a zero-value contract.

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
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project (default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line). Read run metadata (base SHA, surface kind, counts) from `scope-meta.txt` when present. Use
   the manifest verbatim; do not re-resolve. The resolution below is for standalone runs only.

   For diff mode, resolve fail-closed:
   ```bash
   BASE=$(git symbolic-ref -q refs/remotes/origin/HEAD | sed 's@^refs/remotes/@@')
   git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || BASE=
   if [ -z "$BASE" ]; then
     for b in origin/main origin/master main master; do
       git rev-parse -q --verify "$b^{commit}" >/dev/null && BASE=$b && break
     done
   fi
   # BASE still empty: STOP and ask for an explicit base. Do not continue.
   MB=$(git merge-base "$BASE" HEAD) || exit 1                        # STOP: no merge base
   CHANGED=$(git diff --name-only --diff-filter=d "$MB") || exit 1    # STOP: diff failed
   UNTRACKED=$(git ls-files --others --exclude-standard) || exit 1    # STOP: ls-files failed
   DELETED=$(git diff --name-only --diff-filter=D "$MB") || exit 1    # STOP: diff failed
   SCOPE=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u)
   ```
   Every command that supplies audit data is checked; only the base-discovery probes may fail, because failure
   there means "try the next candidate". One diff from the merge base to the working tree covers committed, staged,
   and unstaged changes. A file that existed at the merge base and is gone from the working tree lands in
   `$DELETED`; a file added after the merge base and deleted again appears nowhere. A failed command is never an
   empty scope.

   If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope",
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop. If the resolved surface exceeds the context
   budget, report the file count and ask to narrow or chunk.

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

6. **Run the toolchain — the project's own invocation, never installed or reconfigured.** Per the language
   reference: Go — the repository's vet/lint entry point (Makefile, CI, `golangci-lint` config), else `go vet ./...`,
   whose default analyzers already include `copylocks`, `lostcancel`, and `waitgroup`; `errcheck` only when the
   project has it configured. TypeScript — the project's typecheck script, or `tsc --noEmit` when `typescript` is in
   `node_modules`. Python — `mypy` or `pyright` when configured and installed.

   Four outcomes per tool, recorded in Scope: **ran**, **skipped — not configured**, **skipped — configured, not
   installed**, **errored** (a non-analysis failure). "Ran" records the exact command, the tool version, the package
   coverage, and the options that change what it sees: `errcheck -blank` (blank assignments are *not* checked by
   default), `-asserts`, exclusion lists, `golangci-lint` `exclude` rules. A tool that ran with `-blank` off is *not*
   coverage of `_ = f()`. Tool output is a nomination list, triaged like a scan.

   Strictness flags are recorded whether or not the tool ran, because several evidence bars depend on them:
   `strict`, `strictNullChecks`, `exactOptionalPropertyTypes`, `noUncheckedIndexedAccess`; mypy / pyright `strict`,
   `disallow_any_generics`, `disallow_untyped_defs`, `warn_return_any`; typescript-eslint
   `switch-exhaustiveness-check`, pyright `reportMatchNotExhaustive`. Flags off: findings are still reported — the
   code's invariants do not depend on the checker's settings — and one Low recommendation names the flag.

   Toolchain skipped or errored: the heuristic scans run alone and the report says so. Go, `errcheck` *not
   configured*: one Low recommendation to adopt it, since regex cannot see implicitly ignored return values.
   Configured but not installed, or ran without `-blank`: the coverage limitation is stated and nothing is
   recommended — the project already made its choice. Analyzers that ran are never "recommended for enabling".

### Phase 2: Scan for Candidates

Scans produce **candidates only**. For each loaded reference, run its Phase 2 scan block against that language's
eligible subset (`SCOPE=.` in codebase mode). Pass an explicit path to **every** `rg` invocation. Diff mode nominates
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
- **Keep as runtime** — trust boundary, serialization, or excessive type complexity; say which in Complexity.
- **Delete** — the type already guarantees it → simplicity-hunter's Dead Code Paths; cross-reference, do not score.

### Phase 5: Evaluate Each Finding

For each candidate: apply Not-a-finding first; confirm the category is applicable to that file's language; apply the
within-skill routing (assertion vs. bypass; guard-guaranteed-by-type vs. loose type); clear the category's evidence
bar from What to Hunt; check repository policy (a `Policy:` line withdraws what it names). Run each loaded reference's
Phase 5 block for its language-only categories and language-specific judgment.

Assign **Severity and Impact** to every finding (both required; they diverge). One finding per site. Nothing is held
back; `Audit completed: N findings` counts every reported finding.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-invariant-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if none exists). A caller-specified output path or
return mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas. Go-only categories use
the table schemas supplied in `references/invariant-go.md`.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "The scan matched an `as` — finding" | Scans nominate. Where is the guard, and does the type definition tie it to the claim? |
| "Three constructors set it, so it's always present" | And every later write? `delete`, deserialization, aliasing, callers outside the repository. No bounded argument, no finding. |
| "It's an exported type, so I can't know" | Export alone is no limit. Application code: the repository is the world. Library public type permitting omission: withdraw. |
| "The cast is reachable from a request — Critical" | Name the input, the contract, the consequence, and why nothing contains it. Otherwise the shown consequence sets the severity. |
| "There's a `default: throw`, so it's exhaustive" | Runtime rejection lowers severity; it is not compile-time exhaustiveness. Is an `assertNever` arm or lint configured? |
| "`schema.parse(x)` ran, so `x` is guarded" | Does the schema coerce or default? Then only the output is guarded. Was `safeParse`'s failure branch inspected? |
| "`Readonly<T>` would enforce this" | It compiles away and is assignable to `T`. Adoption at Low; never a replacement for a runtime guard. |
| "The comment says the close error is ignorable" | Open the file's open mode. A comment is a claim to verify. |
| "`CLAUDE.md` says panic is policy" | For the patterns it names. A `panic` on a request body is still reachable from untrusted input. |
| "No `default` on this type switch" | Sealed set? Rejects or falls back after the switch? Then not a finding. Silent zero value → finding. |
| "`context.Background()` in a service — finding" | Is there an incoming `ctx` being replaced? No incoming context, no severed propagation. |
| "`go vet` ran; I'll recommend enabling `copylocks`" | It is a default analyzer and already ran. Triage its output; recommend nothing. |
| "This `?.` is redundant" | Is the type optional? Then tighten it (here). Is the type already non-optional? Then simplicity-hunter deletes the guard. |
| "Bare `# type: ignore` — slop's" | Type-checker suppressions are here, wholly. Linter suppressions are slop's. |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do universal categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** Audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only *categories* with findings. Omit a category heading, table, or list
  entirely when it would contain zero items — no empty tables, placeholder subsections, or negative statements like
  "none found" or "no issues". The Scope section is not a category and is filled in from the template every run,
  including the Toolchain lines and any `Policy:` line.
- **Scope: invariant enforcement only.** A finding that doesn't answer "is this invariant enforced?" belongs to
  another hunter. Contested boundaries are resolved at the category that owns them: each **Ownership:** note in What
  to Hunt states what is kept here and what routes away.
- **Evidence required.** Every finding cites `file:line` (path form per the language reference) with the exact code,
  and the category's evidence cell — Guard, Evidence, Guaranteed By, Justification — is filled, never inferred.
- **One finding per site.** When two categories describe the same code, pick the primary one and cross-reference.
  The within-skill routing rule is the worked example.
- **Never install.** A tool that is configured but absent is `skipped`, never fetched. Analyzers that ran are never
  "recommended for enabling".
- **Architecture-first.** Understand the project's stated conventions before flagging; a policy withdraws what it
  names and nothing reachable from untrusted input.
- **Complexity honesty.** Some invariants are expensive to encode. When recommending a runtime check instead, say
  so, and name the complexity in the Proposed or Complexity cell.
- **Handoff, not duplication.** When a candidate belongs to another hunter — a guard the type rules out, a silent
  catch, a bare `# noqa`, a temporary field with no discriminant — cross-reference it and do not score it here.
