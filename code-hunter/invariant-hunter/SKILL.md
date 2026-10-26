---
name: invariant-hunter
description: Audit Go, Python, or TypeScript code for invariants assumed rather than enforced — unguarded type assertions, loose optionality, defensive access, leaky unions, promotable runtime checks, type-system bypasses, and Go nil, zero-value, context, and race discipline. Defaults to the codebase.
disable-model-invocation: true
---

# Invariant Hunter

Audit code for **invariants that are assumed rather than enforced** — a property that must hold ("this field is
present after construction", "this map is only touched under the lock", "this value was validated") that the code
hopes for instead of guaranteeing. Goal: **guarantees established at construction boundaries
hold throughout downstream code, consumers narrow without casts, and invalid states are caught where data is created.**

**Not covered (owned by other hunters):** type *structure* — Duplicated Type Declarations (a sibling type, a runtime
value, or a schema as source), Generics That Never Vary, Loose Type Parameter Constraints, Over-Powered Type
Constructs, Enum Construct Mechanics, Alias vs Named Type Mechanics (→ type-hunter); how failures are handled,
matched, wrapped, and converted — Go discarded errors, error chains, and panics included (→ exception-hunter);
trust-boundary *content* validation and exploitability (→ security-hunter); a guard the type already rules out
(→ simplicity-hunter, Dead Code Paths); optional fields with no discriminant yet, method call order, identity and
unit types with no validation boundary (→ smell-hunter); linter suppressions and wrapping-message redundancy
(→ slop-hunter); test quality (→ test-hunter). Where ownership is *contested*, the category's **Ownership:** note in
What to Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `security-hunter-go`, `security-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical. Go-only categories
are defined in `references/invariant-go.md`.

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Unguarded Type Assertions | Type claim with no guard and no type definition tying a check to it | Guard, predicate, schema parse, two-value form, `satisfies` |
| Loose Optionality | Optional field or parameter always present after construction | Make it required at the construction boundary |
| Defensive Access in Non-Boundary Code | `?.` / `??` / `is not None` / `or default` on a value always present here | Tighten the upstream type; the guard then falls away |
| Leaky Discriminated Unions | Parallel flag, no exhaustiveness arm, leaking field, cast past the discriminant | One discriminant; compile-time exhaustiveness; variant-scoped fields |
| Runtime Checks Promotable to Types | A guard or validation a type could carry | Promote, or keep runtime with a stated reason |
| Type-System Bypasses | `any` / `Any`, double cast, checker suppression | Fix the type; else justify, scope, track |
| Nil Pointer Risks *(Go only)* | Dereference with no guard on a path that can carry nil | Check the error or the `ok` first; document nil semantics |
| Zero-Value Traps *(Go only)* | Exported type usable at zero value yet invalid there; an unchecked zero sentinel; external input converted to a named constant type with no range check | Constructor, unexported type, or a documented zero-value contract |
| Context Misuse *(Go only)* | Propagation severed, cancellation never consulted, cancel func not called on every path | Propagate the incoming context; consult it; cancel on every path |
| Race Conditions *(Go only)* | Shared state touched from several goroutines without synchronization | Mutex, atomic, or channel ownership |

## Terms

- **Guard** — a runtime check that narrows a type or establishes a fact: `if x != nil`, `isinstance`, a type
  predicate, a two-value type assertion, a schema validation. A validation guards by behaviour, in three cases:
  a failure-*returning* API (`safeParse`, io-ts `decode`) guards only when the failure branch is inspected; a
  *throwing*, validation-only check guards the unchanged input even when its return value is discarded; a
  *transforming* validation (coercion, defaults, sanitizing) guards only the returned value, so the claimed property
  holds for the output, not the input. A library call and a hand-written check are judged the same way.
- **Discriminant** — the field whose value selects a union variant. Its *existence* is the ownership test with
  smell-hunter's Temporary Field: no discriminant yet → smell-hunter; discriminant present → here.
- **Construction boundary** — where a value is created or enters the system: constructors, factories, `New*`
  functions, parse steps, handlers, config loaders. Defaults and validation belong there and downstream code requires
  valid input, so a condition every caller checks belongs in the constructor. **Trust boundary** — a construction
  boundary whose input is external (wire, user, file, env). Runtime validation there is mandatory and never a finding;
  validation *missing* there is a finding here for the unguarded type claim and security-hunter's for the content.
- **Boundary layer** — a module whose job is adapting external code (FFI bindings, third-party SDK wrappers,
  deserializers), or one that repository instructions name as such. **Domain code** — every other module.
- **Tracked** — a bypass comment that cites an issue or ticket ID, or a TODO with a named owner.

## What to Hunt

### Unguarded Type Assertions

A single type claim whose asserted property has insufficient evidence: no preceding guard, and no representation or
construction contract that ties a preceding check to the claimed property.

**Signals:** `as T`, `x!`, `cast()`, `x.(T)`, or a checker-satisfying `assert x is not None` with no guard that
reaches the asserted property. Per-language markers — including `(await res.json()) as T`, never acceptable — are in
each language reference.

**Not a finding:**

- **A runtime-guarded assertion.** The cast or assertion follows a check the checker cannot correlate, *and* the type
  definition ties that check to the asserted property (`as Extract<…>` after a discriminant test on a discriminated
  union; `cast()` after `isinstance` on a sibling field of a variant class). *Is* a finding when the guard is absent,
  checks a different value, or when nothing in the representation makes `kind == 'leaf'` imply `config: Config`.
- **A schema-validated boundary parse** whose downstream type is derived from the schema. `(await res.json()) as T`
  without a parse is never this.

**Evidence bar:** name the guard present (`none`, `isinstance on sibling`, `zod parse`) and, when one is present,
why it does or does not reach the asserted property.

**Action:** two-value form or type switch (Go); guard, type predicate, assertion function, schema parse, or
`satisfies` (TypeScript); guard or tightened upstream type (Python).

**Ownership:** the unguarded type claim is here wherever it sits, including `(await res.json()) as T`. The missing
content validation at that boundary — schema coverage, ranges, formats — is security-hunter's.
An assertion or type-switch arm that **compensates for one implementor of a contract type** — a behavioral
abstraction with methods — is solid-hunter's Broken Substitution, whatever the guard form; the guardedness is noted in
its Action, not scored again here. Assertions from `any` or open data (JSON, config, `interface{}` payloads), and
narrowing on a data variant set, stay here. Exception: a cast inside a generic body that a tighter type parameter
constraint removes (`as T`, `cast(T, x)`, Go `any(v).(X)` where `v` is a type parameter) is type-hunter's Loose Type
Parameter Constraints — one finding there, not scored here.

### Loose Optionality *(conditional)*

An optional field or parameter whose value is always present after construction, or becomes required after a
pipeline stage but stays optional throughout. Optional is for domains that permit absence, not a convenience for
callers.

**Signals:**

- Optional field with `??` / `or default` / `if x is None` in every consumer
- Field that becomes present after a pipeline stage but carries `?:` / `| None` throughout
- Dataclass `field(default=None)` or `?:` always set before use

**Not a finding:** an optional utility parameter on a helper that genuinely serves optional and required callers.

**Evidence bar:** the **construction-and-mutation argument** in one cell — every producer and every later write read
(assignments, `delete`, deserialization, aliasing). In a closed unit the repository *is* the world and the argument
can close; export alone is no limit. When the type's unit is open (Closed consumer set, below) and its
contract permits omission, the finding is **withdrawn** and the limitation recorded in Scope.

**Closed consumer set.** An exported type whose unit is closed is judged in tree, export alone being no limit; one
whose unit is open has producers and writers outside the tree that cannot be enumerated, and is **withdrawn** when
its contract permits omission. The question is asked per exported type, from the unit that exports it; no
repository-wide classification. Closed and open follow boundary-hunter's **Published unit** definition, copied here:
**any evidence of documented import use opens the set** (mixed → open → withdrawn). **Closed** (judged in tree): Go —
a `main` package; an `internal/` path; a package of a module that contains a `main` package **and** whose repository
documents no import use (no `go get <module path>` line or quoted `"<module path>…"` import path in a README or doc,
no `doc.go` on a non-main package, no `examples/` directory). TypeScript — a workspace package with `private: true`,
or a unit not reachable from any `package.json` `exports` / `main`. Python — a `_`-prefixed or `internal` package; a
distribution with a `Private :: Do Not Upload` classifier; a repository whose entry is a web or framework application
(`manage.py`, `wsgi.py`, `asgi.py`). **Open** (withdrawn): Go — a module with no `main` package and a public module
path, or any documented import use; TypeScript — reachable from `exports` / `main` without `private: true`; Python —
a package a `[project]` / `[tool.poetry]` distribution declares with a public import path and none of the closing
signals. `__main__.py` and `[project.scripts]` are **not** application signals — libraries ship CLIs that way. No
release workflows or tags are read.

**Action:** make required at the construction boundary. One finding per invariant: when this finding exists for a
field, its consumers' `??`, `?.`, `!`, `assert x is not None`, and `cast` sites are cited in Evidence, not reported
separately under Defensive Access or Unguarded Type Assertions.

**Ownership:** two optionals never both present, "only valid when X" — no discriminant exists yet — is smell-hunter's
Temporary Field, whose remedy introduces the per-state type. A discriminant present → Leaky Discriminated Unions.
Optionality is owned here; type-hunter owns type structure, never optionality.

### Defensive Access in Non-Boundary Code *(conditional)*

`?.` / `??` / `is not None` / `or default` compensating for a type looser than the invariant, when the value is
always present in this context.

**Signals:**

- `?.` or `is not None` on a value always present given the current context
- `??` / `or default` applying a default already resolved at the construction boundary
- A shared helper using `??` / `or` to serve cases that should be separate functions

**Not a finding:** defensive access at a trust boundary — external API response, user input, config default. *Is* a
finding when the value has already been resolved at the construction boundary and the guard sits downstream.

**Evidence bar:** the Guaranteed By cell names the upstream site that always sets the value.

**Action:** tighten the upstream type; the guard then becomes deletable.

**Ownership:** when the *type already guarantees* presence, the guard is simplicity-hunter's Dead Code Paths (delete
the guard). When the type is optional and the value is always present, it is here (tighten the type; the guard falls
away afterwards).

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
here and a Rigid Extension Points finding there, at different anchors.

### Runtime Checks Promotable to Types

A guard, assertion, or validation that a type could carry.

**Signals:**

- A **validated-state** brand or named type — validated email, sanitized string, checked unit — travelling downstream
  as plain `string`
- Empty-check branches a non-empty type removes
- Boolean validators that should be type predicates, assertion functions, or `TypeGuard` / `TypeIs`
- Config objects that should be `as const`; mutable containers as config where `tuple` / `frozenset` would do

**Immutability is promotable only where the type blocks the actual mutation path.** The language forms and their
limits (compile-time-only `Readonly<T>` / `as const`; shallow `frozen=True`) are in each language reference.

**Go — narrowed** to validated-state named types; the zero-value rule is in `references/invariant-go.md`.

**Action:** promote, or keep runtime with a stated complexity reason.

**Ownership:** smell-hunter routes brands encoding validated state here for every language. An ID or unit with no
validation boundary is smell-hunter's Primitive Obsession — `NewType('UserId', str)` for a bare `user_id: str` is
not a finding here. A manual type beside a schema (`z.infer` candidates) is type-hunter's Duplicated Type Declarations.
A presence check (`if (node.config)`, `if node.config is not None`) after a discriminant test is not this category:
the variant type still marks the field optional → Leaky Discriminated Unions (`leaking field`); the variant type
already makes it required → simplicity-hunter's Dead Code Paths.

### Type-System Bypasses *(conditional)*

A bypass — a construct that disables the checker rather than claiming one type: `Any` / `any` where a concrete type
or `unknown` plus narrowing would do; `as any`; `as unknown as T`; `# type: ignore` (with or without an error code);
`# pyright: ignore`; `@ts-ignore`; `@ts-expect-error`.

**Signals:**

- `any` / `Any` as parameter, return, or variable type without justification
- `as any`, `as unknown as T`, `<any>` — a bypass inside a `catch` (`catch (e) { throw e as any }`) is still here
- A checker suppression with no error code, no trailing reason, or in domain code

**Not a finding:** a bypass in a boundary layer with a comment and tracked debt — FFI, a library's wrong types. *Is* a
finding when bare, or when the same bypass appears in domain code.

**Evidence bar:** the Justification cell is `none`, `bare`, or the quoted reason. A quoted reason is verified against
the code the way any comment is.

**Action:** fix the underlying type. If the bypass is necessary, justify it, scope it to a boundary layer, track it.

**Ownership:** owned **wholly** here, including "does it have a reason?" — one line, one hunter.
slop-hunter keeps *linter* suppressions: `# noqa`, `# pylint: disable`, `// eslint-disable*`, `// biome-ignore`,
`//nolint`. Silent fallbacks on invalid input (`return []`, `return null`) are exception-hunter's. A
bypass inside a generic body that a tighter type parameter constraint removes (`(o as any)[k]`, `cast(Any, x)`) is
type-hunter's Loose Type Parameter Constraints — one finding there, not scored here.

### Within-skill routing

A *single* type claim (`as T`, `cast(T, x)`, `x!`, `x.(T)`) is an Unguarded Type Assertion. A construct that
*disables* checking (`any`, `Any`, double cast, ignore directive) is a Type-System Bypass. A cast to a union variant
(`s as Leaf`, `cast(Leaf, s)`) on a value whose union has a discriminant is Leaky Discriminated Unions
(`cast past discriminant`), not an Unguarded Type Assertion.

### Go-only categories

Nil Pointer Risks, Zero-Value Traps, Context Misuse, Race Conditions — defined entirely in
`references/invariant-go.md`.

## Applicability

Each language reference's Applicability table declares which universal categories run for that language, with the
reason. *(conditional)* on a What to Hunt heading marks a category that is n/a for at least one language (here: Go).

## Test-code scope

**Test files are excluded from every category.** Invariants are production guarantees; a panicking assertion in a
test is the intended failure mode, and `as any` on a mock is test-hunter's Test Double Misuse. Test paths
are listed in each language reference. The exclusion is by path: a helper imported by production code from a non-test
path is audited; a production helper under `tests/` is not.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is.** It measures consequence, not confidence.

- **Critical** — the finding names all four: the triggering input, the violated contract, the downstream consequence
  (data loss, crash, corrupted state), and why nothing contains it. `json() as T` on a public route where the wrong
  shape reaches a write; a data race on state the server mutates per request. A cast being *reachable* is not
  Critical by itself; the finding takes the severity its shown consequence supports, and an unknown consequence is
  stated as such.
- **High** — a crash or silent wrong result awaiting the first unexpected value: nil dereference after an unchecked
  error; an open-interface type switch that silently yields a zero value.
- **Medium** — the invariant holds today by convention only: optional field always set; defensive access in
  non-boundary code; a bypass without justification; a missing exhaustiveness arm with no runtime rejection.
- **Low** — hygiene and adoption: `satisfies` over object-literal `as`; `as const` on fixed tables; strictness flags
  off; documenting a zero-value contract.

**Impact — how much the change is worth:** defect exposure reduced, cognitive burden reduced, surface affected.
Contextual; never derived from occurrence count. Forty `?.` on one hot type read in every handler are High impact at
Medium severity.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

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
   surface kind, counts) from `scope-meta.txt` when present. Use the manifest verbatim; the resolution
   above is for standalone runs only.

   **Persist run state.** Shell variables do not survive between tool calls, and `rg … --` with an empty variable
   searches the whole working directory. Create one run directory (`RUN=$(mktemp -d) && echo "$RUN"`) and use the
   printed path literally from then on. Every call starts at the repository root (`cd "$(git rev-parse
   --show-toplevel)"`), because every list holds root-relative paths. Write `$SCOPE` to `<run>/scope.txt` and, in diff mode, `$MB` to `<run>/mb`.
   A later call restores what it uses (`SCOPE=$(cat <run>/scope.txt)`); an empty restore is a STOP, never an empty
   result. If the resolved surface exceeds the context budget, report the file count and ask to narrow or chunk.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section. On a dirty tree, line numbers match no
   commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent: on a mixed scope it stays whole, so every hunter in a
   party audits the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from file extensions alone: the manifest's, or in codebase mode those of
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the scans still search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**. Record `excluded — no reference for .<ext>: {count} files` in Scope,
   naming each extension.

3. **Load language references.** For every detected language, read `references/invariant-<lang>.md` from the
   directory this SKILL.md was read from (e.g. `references/invariant-go.md`). **Fail closed:** if a required
   reference cannot be read, **stop and report**.

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
   boundary layers, sanctioned escape hatches, and how the project runs its own checks. A stated policy is respected,
   acknowledged in the report's `Policy:` line, and overridden only where the pattern is reachable from untrusted
   input.

6. **Run the toolchain — the project's own invocation, never installed or reconfigured.** Each loaded reference's
   Toolchain section names the adoption evidence, the exact read-only command, and the strictness flags to read.
   Record each tool's outcome in Scope in report-format.md's Toolchain-line form; **errored** means a non-analysis
   failure. Tool output nominates, like a scan.

   Strictness flags are recorded whether or not the tool ran, because several evidence bars depend on them. Flags
   off: findings are still reported — the code's invariants do not depend on the checker's settings — and one Low
   recommendation names the flag.

   Toolchain skipped or errored: the heuristic scans run alone and the report says so. Recommend enabling only
   analyzers and checks that did not run.

### Phase 2: Scan for Candidates

Scans and tool output **nominate**: every hit is a candidate, and nothing is a finding until Phase 3 has read its
producers and consumers. For each loaded reference, run its Phase 2 scan block on the eligible list restored in the
same call (Phase 1 step 4). Diff mode nominates from the working tree over the manifest files, not from added lines:
an invariant is a property of the current code, and a manifest file's producers and consumers are read wherever they
live.

Done when every scan in each loaded reference's Phase 2 block has run and every hit is listed as a candidate.

### Phase 3: Trace Producers and Consumers

For each optional field, union, and asserted value nominated: read every producer (constructors, factories,
deserialization) and every later write (assignment, `delete`, aliasing), then every consumer. This is where Loose
Optionality's construction-and-mutation argument closes or is withdrawn, where a union's consumers are classified as
must-cover-every-variant or deliberate-subset, and where a guard is located for each assertion.

Done when every nominated optional field, union, and asserted value has its producers, later writes, and consumers
read.

### Phase 4: Classify Runtime Checks

For each runtime guard, assertion, or validation nominated:

- **Promote to type** — a type can carry it and blocks the actual failure path (see the immutability rule).
- **Keep as runtime** — trust boundary, serialization, or excessive type complexity; the Complexity cell names which
  (see report-format.md).
- **Delete** — the type already guarantees it → simplicity-hunter's Dead Code Paths; hand off.

### Phase 5: Evaluate Each Finding

For each candidate: apply the category's own Not-a-finding line first (Go: also the reference's Not-a-finding list);
confirm the category is applicable to that file's language; apply the within-skill routing (assertion vs. bypass vs.
cast past discriminant); clear the category's evidence bar from What to Hunt; check repository policy (Phase 1
step 5). Run each loaded reference's Phase 5 block for its language-only categories and language-specific judgment.

Assign **Severity and Impact** to every finding. Nothing is held back; `Audit completed: N findings` counts every
reported finding.

Done when every candidate is a reported finding, withdrawn or dismissed by a named Not-a-finding case, or handed off
to its owning hunter.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-invariant-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or
return mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line` with the exact code, and the category's evidence column —
  named in report-format.md or the language reference's table schema — is filled, never inferred.
- **Comments are claims; the code is evidence.** A justifying comment (`// never nil: set in NewServer`)
  is checked against the code — here, the constructors — never trusted.
- **One site, one finding.** When two categories describe the same code, pick the primary one and cross-reference.
  The within-skill routing rule is the worked example.
- **Never install.** Run only tools the project already has; a tool that is configured but absent is `skipped`,
  never fetched.
- **Hand off.** A candidate another hunter owns is cross-referenced to that hunter and not scored here.
