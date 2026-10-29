---
name: type-hunter
description: Audit Go, Python, or TypeScript code for type structure debt — duplicated type declarations, generics that never vary, loose type parameter constraints, over-powered type constructs, enum and alias construct mechanics, Go embedding antipatterns, reinvented TypeScript utility types. Defaults to the codebase.
disable-model-invocation: true
---

# Type Hunter

Audit code for **type structure debt**: a type declared more than once by hand, more generic than its uses, or built
with a construct more powerful than its uses need at **equal precision**. Examples: one shape declared twice by hand,
a type parameter every instantiation binds to the same type, a constraint that hides what the body does with `T`, a
constant group with no named type, an exported struct promoting `Lock` and `Unlock` to every importer.

**Not covered (owned by other hunters):** primitives standing in for domain concepts where no named construct exists
yet, values travelling together with no type, a file accumulating unrelated types (→ smell-hunter); package
organization (→ boundary-hunter's Generic Boundary Names); canonical import paths (→ boundary-hunter's Deep Imports);
the *crossing* beside a cross-layer mirror (→ boundary-hunter's External Type Leaks; see Cross-layer mirror);
optionality, unguarded narrowing, `any` / `Any` as a *value* type, exhaustiveness, `as const` adoption for a value with
no parallel declaration (→ invariant-hunter's Runtime Checks Promotable to Types), `satisfies` in place of an `as T`
(→ invariant-hunter's Unguarded Type Assertions), validation of external input into an enum, never-checked zero
sentinels (→ invariant-hunter); repeated logic and repeated runtime values, abstractions with one call site, runtime
control flow, reinvented runtime primitives (→ simplicity-hunter); a struct embedding an interface it implements only
partly, interface width (→ solid-hunter); test design (→ test-hunter; type structure inside test files is out of scope,
see Test-code scope); documentation restating types (→ slop-hunter); content validation at trust boundaries
(→ security-hunter). Where ownership is *contested*, the category's **Ownership:** note in What to Hunt is
authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `perf-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical. A language tag
marks a category that applies only there; each language reference's Applicability table states, per category,
whether it applies and why.

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Duplicated Type Declarations | One shape declared twice by hand, where one declaration could follow the other, a runtime value, or a schema | Derive with the named mechanism, or delete one copy and use the survivor |
| Generics That Never Vary | A type parameter bound to one concrete production type across every instantiation | Remove the parameter; use the concrete type |
| Loose Type Parameter Constraints | A constraint that does not express what the body does with `T` | Tighten to the operation the body performs; Go type switch → concrete functions, an interface, or a union constraint; TypeScript → `const` type parameter |
| Over-Powered Type Constructs *(Python, TypeScript)* | A type-level construct more powerful than any existing use needs | Replace with the simpler construct at equal precision |
| Enum Construct Mechanics | An existing constant group or enum built with the wrong construct, with a consumer that pays for it | Go: named type, `String()`; TypeScript: string-literal union or `as const` object with the derived union; Python: member comparison |
| Alias vs Named Type Mechanics *(Go, Python)* | An alias where a distinct type was meant | Go: named type, or delete the alias; Python: `NewType` |
| Embedding Antipatterns *(Go)* | An embedding that promotes API surface the outer type's consumers should not have | Unexported field; delegate the used methods |
| Reinvented Utility Types *(TypeScript)* | A hand-rolled type equal to a built-in utility | Replace with the built-in |

## Core Principles

1. **Scans nominate; reading decides.** Scan hits, occurrence counts, member counts, and parameter counts *nominate*
   candidates. Nothing is a finding until every site its evidence bar names has been read.

2. **Respect the language.** Recommend only constructs the audited language expresses and the project's version gates
   permit; the language reference carries the calibration.

## Terms

- **Declaration vs value** — the simplicity/type ownership test. Repeated *logic or runtime values* across functions
  is simplicity-hunter's Duplication. Two *type declarations* of one shape — interface, type alias, struct, dataclass,
  `TypedDict`, Pydantic model, enum, union — are this skill's Duplicated Type Declarations, whatever the language. A
  hand-written union parallel to a runtime array is a declaration duplicating a value, so it is here.
- **Source kind** — where the canonical declaration lives: *sibling type* (the other hand-written declaration),
  *runtime value* (`as const` array or object), *schema* (Zod, io-ts, Valibot, ArkType, TypeBox, Pydantic, msgspec —
  whatever the project already has). Named in the report's Source cell.
- **Consolidation path** — the concrete fix a Duplicated Type Declarations finding must name; one of two. (a) A
  *type-level derivation* that preserves the shape: TypeScript `Pick` / `Omit` / `Partial` / `Readonly` /
  intersection, `(typeof arr)[number]`, the installed schema library's inference type in the right role; Go embedding
  a shared struct where the outer type should carry its method set, otherwise an explicit field where the wire or
  storage shape allows it; Python inheritance of `TypedDict`, dataclass, or Pydantic model, `Required` / `NotRequired`
  for omittable-key variants. (b) *Delete and use*: one copy is deleted and the other used directly, which requires that
  every former site of the deleted copy accepts the surviving one. **A finding requires one of the two**; where neither
  exists for the variant at hand, the candidate is dropped.
- **Cross-layer mirror** — a hand-written declaration mirroring a generated, ORM, SDK, or protobuf type, with or
  without a mapper and whatever the mapper does. Never duplication here, because the only "fix" this skill could name
  puts the external type where boundary-hunter says it must not go. boundary-hunter's External Type Leaks judges the
  **crossing** — the external type used inward beside the mirror, or a mapper output still carrying it; the mirror
  itself is never a finding there, and a same-layer clone is nobody's finding by design. Generated files are still read
  as context to identify a mirror. Duplication is between two *hand-written* declarations whose consolidation path
  exists.
- **Instantiation** — one concrete binding of a type parameter, found project-wide by reading call sites and
  declarations, not by regex: TypeScript and Python infer arguments without writing them, Go writes them rarely at
  call sites.
- **Closed consumer set** — invariant-hunter's per-symbol rule, reused for every usage-based narrowing (Generics That
  Never Vary, Over-Powered Type Constructs, Embedding Antipatterns' used-subset argument). An exported symbol whose unit
  is closed is judged in tree, export alone being no limit; one whose unit is open has instantiations or callers outside
  the tree that cannot be enumerated, and is **withdrawn**. The question is asked per exported symbol, from the unit
  that exports it; no repository-wide classification. Closed and open follow boundary-hunter's **Published unit**
  definition, copied here: **any evidence of documented import use opens the set** (mixed → open → withdrawn).
  **Closed** (judged in tree): Go — a `main` package; an `internal/` path; a package of a module that contains a `main`
  package **and** whose repository documents no import use (no `go get <module path>` line or quoted `"<module path>…"`
  import path in a README or doc, no `doc.go` on a non-main package, no `examples/` directory). TypeScript — a workspace
  package with `private: true`, or a unit not reachable from any `package.json` `exports` / `main`. Python — a
  `_`-prefixed or `internal` package; a distribution with a `Private :: Do Not Upload` classifier; a repository whose
  entry is a web or framework application (`manage.py`, `wsgi.py`, `asgi.py`). **Open** (withdrawn): Go — a module with
  no `main` package and a public module path, or any documented import use; TypeScript — reachable from `exports` /
  `main` without `private: true`; Python — a package a `[project]` / `[tool.poetry]` distribution declares with a public
  import path and none of the closing signals. `__main__.py` and `[project.scripts]` are **not** application signals —
  libraries ship CLIs that way. No release workflows or tags are read.
- **Drop vs withdraw** — two outcomes for a candidate that is not reported. **Drop:** the evidence shows there is no
  finding (no consolidation path exists, a second production instantiation exists, the body is opaque); nothing is
  recorded. **Withdraw:** the evidence could not be completed (a consumer set not closed, a site that could not be
  read, an instantiation set that could not be enumerated); one Scope `Limitation` line is recorded. A repository
  policy that removes a pattern is recorded as its `Policy:` line instead. Neither is ever a Low finding: Severity is
  not a confidence scale.
- **Existence vs construct** — the smell/type ownership test for enums and aliases. No named construct yet (raw
  string compared, bare `str` parameter) → smell-hunter's Primitive Obsession, whose reference names the remedy. A
  constant group, enum, or alias *exists* and is built with the wrong construct → here. Because this skill fires only
  where a construct exists, it never contradicts smell-hunter's remedy on the same site. TypeScript aliases are the
  exception: smell-typescript's brand-or-withdraw rule keeps the alias question there.
- **Equal precision** — the bar every "simpler form" must clear (Over-Powered Type Constructs, Reinvented Utility
  Types, and Duplicated Type Declarations' derivation): on every enumerated use the replacement accepts the same
  inputs, rejects the same inputs, and produces the same or a narrower result. If any use needs the power, no finding.

## What to Hunt

Each category's **Not a finding:** line, and the per-category not-findings in each language reference, list what does
**not** justify a finding on those grounds alone and, where one exists, what would.

### Duplicated Type Declarations

One shape declared twice by hand, where one declaration could follow the other, a runtime value, or a schema.

**Signals** — every one of them *nominates*; none is a threshold:

- Two interfaces, structs, dataclasses, `TypedDict`s, or models with matching member names and types in different
  files
- Create / update / summary / patch variants hand-listed from an entity; a readonly variant added field by field
- An `as const` array or object beside a hand-written union (TypeScript)
- A schema beside a manual type of the same shape
- Parallel `const` blocks or enums for one value set; a `Literal` beside an `Enum`
- The same complex inline type expression (nested generic, long `Callable`, Go func type) repeated at independent
  sites

**Evidence bar:** name the concept both declare; map every member of the derived declaration onto the source (subset,
superset, or a modifier change: optional, readonly, nullable) — the Overlap cell says `mapped/total`; name the
consolidation path (derive or delete-and-use) at equal precision, with every former site of a copy to be deleted read;
show neither copy is a generated or external type. For a repeated inline expression: the independent sites, and that
naming it once reduces concepts.

**Not a finding:** separate request and response types at an API boundary that differ by validation, serialization
tags, or consumer — *is* a finding when both are hand-written, live in one layer serving one boundary, and a
consolidation path at equal precision exists. Two types sharing some members, each with its own members.

**Action:** derive from the source with the named mechanism — the utility type, `(typeof arr)[number]`, the schema
library's inference type in the right role, inheritance, `Required` / `NotRequired` — or delete the copy and use the
survivor. For repeated inline expressions: name it once — an alias; a callable `Protocol` only when keyword arguments
or overloads need it. In Go: embed only where the outer type should carry the method set, an explicit field where the
wire or storage shape allows it, delete-and-use where one struct stands in for the other at every site; when none
fits, drop.

**Severity:** High when the copies have already diverged for the same concept with both live (a member present in
one, absent or differently typed in the other, both consumed); the divergence is named in Evidence.

**Ownership:** the declaration-vs-value test (see Terms). simplicity-hunter keeps repeated logic and repeated runtime
values, and its own rule "duplication derivable from an existing source of truth" for values; two declared types of
one shape, a declared union beside a runtime array, and a manual type beside a schema are here. Values travelling
together with no type are smell-hunter's Data Clumps. Any cross-layer mirror is out of scope here (see Terms). `as
const` recommended to make a value the *derivation source* of a declared union is this category's Action; `as const`
for a value with no parallel declaration stays invariant-hunter's Runtime Checks Promotable to Types, and `satisfies`
in place of an `as T` its Unguarded Type Assertions.

### Generics That Never Vary

A type parameter bound to one concrete type across every instantiation.

**Signals:**

- `Cache[T]` always `Cache[User]`; `Store<T>` with one instantiation
- `Generic[T]` where `T` appears in one field; a parameter used in one position only (return only; one field only)
- "Future-proofing" parameters with no second instantiation
- A generic function whose single call site fixes the type

**Evidence bar:** list every instantiation project-wide (call sites and declarations, inferred included), tests
marked `(test)`; show one concrete production type; the consumer set is closed inside the tree, else withdrawn with a
`Limitation` line. A parameter used in one position only is the same finding when its instantiations agree.

**Action:** remove the parameter; use the concrete type. Reintroduce with the second instantiation. Where a test
instantiates a fake, the Action says how the test survives (a fake of the production type).

**Ownership:** a value-level abstraction — wrapper, manager, factory, interface with no live seam — is
simplicity-hunter's Unnecessary Abstractions; a *type parameter* with one instantiation is here.

### Loose Type Parameter Constraints

A constraint that does not express what the body does with `T`.

**Signals:**

- `[T any]` with `comparable` or method use inside; `switch any(v).(type)` inside `func F[T any]`
- `<T>` / `<T extends unknown>` / `<T extends any>` used as an object
- `TypeVar("T")` where only `int | str` is passed (constraints) or a base class is assumed (`bound=`); PEP 695 `[T]`
  with the same defects
- TypeScript only: a parameter receiving array or object literals whose tuple or literal types a downstream consumer
  re-narrows, and no `const` modifier

**Evidence bar:** name the operation the body performs on `T` that the constraint does not permit — it compares,
indexes, calls methods, type-switches, or bridges with an assertion (`any(v).(fmt.Stringer)`, `(x as any)[k]`,
`cast`); state the tightest constraint every existing instantiation satisfies. Go form: a generic body that
type-switches on `T` — the constraint is `any` and the body enumerates types. TypeScript `const` form: the
re-narrowing consumer, and that the parameter type is an array or object (a scalar `T extends string` already
preserves the literal).

**Not a finding:** `[T any]` / `<T>` / an unbounded `TypeVar` where the body treats `T` as *opaque* — stores, returns,
passes it through, ranges over `[]T` without touching elements. The constraint matches the use, however many callers
pass one shape; that question is Generics That Never Vary.

**Action:** tighten to the stated constraint. Go type switch: concrete functions, an interface, or a union constraint.
TypeScript: add `const` to the parameter (TS 5.0+, read from the lockfile).

**Severity:** Low on a generic with a single caller.

**Ownership:** `any` / `Any` as a *constraint* is here; `any` / `Any` as a *value type* is invariant-hunter's
Type-System Bypasses (Go `any` / `interface{}` as a value type is nobody's). A bypass inside a generic body
(`(o as any)[k]`, `cast(T, x)`, `any(v).(X)`) that a tightened constraint removes is **one** Loose Type Parameter
Constraints finding here; invariant-hunter does not score the same cast.

### Over-Powered Type Constructs *(Python, TypeScript)*

A type-level construct more powerful than any existing use needs.

**Signals:**

- TypeScript: a conditional type nested deep; recursion where a flat union suffices; mapped `as` remapping where
  `Pick` suffices; type-level string arithmetic a runtime function replaces; template-literal metaprogramming
- Python: `ParamSpec` / `Concatenate` decorator typing for one decorated signature where a `Protocol` suffices;
  `@overload` towers with one input→output mapping
- Many type parameters (nomination only)

**Evidence bar:** name the simpler construct and show it types every enumerated instantiation at equal precision.

**Not a finding:** a construct some enumerated use needs — library types, framework constraints, and serialization
boundaries often do.

**Action:** replace with the simpler construct.

**Ownership:** type-level only; simplicity-hunter's Complex Control Flow and Reinvented Primitives are runtime code.
Template literal *overuse* is here; a template literal type *missing* for a structured string domain is
smell-hunter's Primitive Obsession.

### Enum Construct Mechanics

An existing constant group or enum built with the wrong construct, with a consumer that pays for it. Style alone is
not a defect.

**Signals:**

- Go: an `iota` group with no named type (untyped constants accepted anywhere an `int` is); a named constant type
  formatted, logged, or serialized (`%v`, `%d`, `fmt.Sprint`, JSON) with no `String()`
- TypeScript: an `enum` whose members are only ever compared or serialized (a union suffices; supporting evidence:
  value imports of the enum across modules that a type-only union would erase); a numeric `enum` for unordered
  non-flag values that is serialized; `enum` members compared to raw literals with `===`; a single-member `enum`
- Python: members compared by `.value` against raw strings; a single-member `Enum`

**Evidence bar:** anchor at the group; name the defect and the consumer that pays for it — the site that accepts the
untyped constant, the formatting site with no `String()`, the comparison, the serialization.

**Action:** Go: a named type, a `String()` method (`stringer` as vocabulary, never run). TypeScript: a string-literal
union, or an `as const` object with the union derived from it, with the serialization / non-TS-consumer risk named
where the value crosses a boundary and `erasableSyntaxOnly` named where the project sets it. Python: member
comparison (`StrEnum` as vocabulary at 3.11+); drop the single member.

**Severity:** Low for a missing `String()` on a formatted constant type, and for a single-member enum.

**Ownership:** the existence-vs-construct test (see Terms). smell-hunter owns raw values compared with no constant
group and names the remedy per language; this category owns the construct of an existing group and states no
Enum-vs-`Literal` preference for Python beyond the mechanical markers. Validation of external input into an enum is
invariant-hunter's (unguarded type claim at a trust boundary) or security-hunter's (content); a zero sentinel never
checked is invariant-hunter's Zero-Value Traps. Value imports of an enum across modules are supporting evidence here,
never a standalone finding and not boundary-hunter's.

### Alias vs Named Type Mechanics *(Go, Python)*

An alias where a distinct type was meant.

**Signals:**

- Go: `type X = Y` with no migration or compatibility comment and no second name in live use
- Python: two aliases of one primitive (`UserId: TypeAlias = str`, `OrderId: TypeAlias = str`) with a site where one is
  passed where the other is declared — the mixing the alias was meant to prevent

**Evidence bar:** Go: the alias, and the absence of a migration comment and of a second live name. Python: both
aliases and the mixing site.

**Action:** Go: a named type for distinction, or delete the alias. Python: `NewType`.

**Severity:** Low for an alias cleanup.

**Ownership:** identity types with no alias at all (a bare `str` / `string` parameter) are smell-hunter's Primitive
Obsession — this category needs an existing alias. TypeScript aliases stay with smell-typescript's brand-or-withdraw
rule.

### Embedding Antipatterns *(Go)*

An embedding that promotes API surface the outer type's consumers should not have. Forms, evidence bar, Action,
Severity, and Ownership: `references/type-go.md`.

### Reinvented Utility Types *(TypeScript)*

A hand-rolled type equal to a built-in utility. Forms, gates, Action, Severity, and Ownership:
`references/type-typescript.md`.

### Within-skill precedence

One finding per site. On one type parameter: Generics That Never Vary first — removing the parameter
retires every constraint question; otherwise Over-Powered Type Constructs beats Loose Type Parameter Constraints. A
`Literal` beside an `Enum` is Duplicated Type Declarations, cross-referenced from Enum Construct Mechanics.

## Test-code scope

**Test files are excluded from findings.** Test paths are listed in each language reference. The exclusion is **by
path**: a production helper under `tests/` is not audited.

Test files are **read as context**: a test instantiation of a generic is listed in the Instantiations cell and marked
`(test)`; it never counts as variation and never drops a finding, and the Action says how the test survives the
specialization. Test evidence never raises Severity. Cite the test file in the Evidence cell; anchor the finding at
the production declaration.

## Severity and Impact

Every finding carries **both**.

**Severity — behavioral risk if left as-is:**

- **Critical** — never available. Type structure debt is not itself a production defect. A drifted duplicate that is
  already producing wrong behavior names the divergence in Evidence and reports at High; the runtime defect is not
  scored here and this skill does not route it.
- **High** — a live defect a category's **Severity:** line names.
- **Medium** — the default for a finding that clears its bar.
- **Low** — a small mechanical cleanup a category's **Severity:** line names.

**Impact — how much the change is worth:** contextual, never derived from occurrence count. A duplicated entity type
every handler imports is High impact at Medium severity; a phantom parameter on an internal helper is Low.

- **High** — substantial reduction on a type read or changed often
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
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the language scans still
   search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**: without a reference there is no consolidation-path vocabulary, no
   eligibility rule, no scan set, no version gate. Record `excluded — no reference for .<ext>: {count} files` in
   Scope, naming each extension.

3. **Load language references.** For every detected language, read `references/type-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/type-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus the
   test-path exclusion** to that language's files. These subsets are then immutable. Record in Scope: raw manifest
   count, each per-language eligible subset, exclusions with the test paths listed, and
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

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop before
   scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Files outside it, test files and generated files included, are *read* as **context**: finding the canonical
   declaration, enumerating instantiations, reading a promoted method's consumers, and checking every site of a copy
   to be deleted routinely leave any diff scope. Diff and path scope narrow the manifest, never the context reading.

5. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) for stated policies: a chosen
   enum style, a deliberate request/response split, a published package surface, generics kept for a documented
   consumer. A stated policy is respected and acknowledged in the report's `Policy:` line.

6. **Read the version gates** each loaded reference names. A gate the project does not meet removes the Action that
   needs it; the reference says what replaces it.

**No toolchain step.** Run no type checker or linter: none reports these categories.

### Phase 2: Scan for Candidates

Scans produce **candidates only**. For each loaded reference, run its Phase 2 scan block over that language's
eligible list from Phase 1 step 4: restore `GO_FILES=$(cat <run>/go.txt)` (`PY_FILES` from `python.txt`, `TS_FILES`
from `typescript.txt`) in the same call, and skip the block when the list is empty. Diff mode nominates
from the working tree over the manifest files, not from added lines: type structure is a property of the current
code.

Done when every scan in each loaded reference's Phase 2 block has run and every hit is listed as a candidate.

### Phase 3: Enumerate Declarations, Instantiations, and Consumers

For each nominated candidate, project-wide (see Two surfaces):

- **Duplicates**: the canonical declaration and every other hand-written declaration of the concept; the source kind;
  each member mapped; for delete-and-use, every site of the copy to be deleted and whether it accepts the survivor;
  whether either copy is generated or external (then stop: Cross-layer mirror).
- **Generics**: every instantiation — explicit type arguments by scan, inferred ones by reading call sites and
  declarations — with test files marked `(test)`; the operations the body performs on `T`; for an exported symbol,
  whether the package publishes it to consumers outside the tree.
- **Type-level constructs**: every instantiation and what each needs of the construct.
- **Constant groups and enums**: the consumers that accept, compare, format, serialize, or import the members.
- **Aliases**: Go, the comments and the second live name; Python, the sites where the two aliases meet.
- **Embeddings**: the promoted method set, the outer type's own methods, and the subset every consumer in the
  repository calls; exportedness.

Inference bounds this phase: regex finds explicit `<User>`, `[User]`, `Cache[User]` only. Inferred instantiations are
found by reading consumers. Every search in this phase runs on `.` (the repository root), never on `$SCOPE` or a
per-language list: search the symbol's name, then read each hit — e.g. `rg -n -w 'Cache|NewCache' --type go -- .`
for a Go generic, `rg -n -w 'UserSummary' --type ts -- .` for every site of a copy to be deleted. Test files and
generated files are in that search on purpose. When any instantiation or duplicate was found by reading, record an
`Enumeration` line in Scope stating what was searched and how the set was closed. A set that cannot be closed
withdraws the finding with a `Limitation` line. Findings claim the enumerated set only.

### Phase 4: Evaluate Each Finding

For each candidate: apply the category's **Not a finding:** line and the reference's per-category not-findings first;
confirm the category applies in that file's language (the reference's Applicability table); apply the three ownership
tests — declaration vs value, existence vs construct, cross-layer mirror — the closed-consumer-set check, and
within-skill precedence; then clear the category's evidence bar from What to Hunt, the consolidation-path requirement
and equal-precision bar included. Check repository policy: a `Policy:` line withdraws what it names. Run each loaded
reference's Phase 4 block for its language-specific judgment.

Assign **Severity and Impact** to every finding. Nothing is held back; `Audit completed: N findings` counts every
reported finding.

Done when every candidate is a reported finding, a drop, a withdrawal with its `Limitation` line, or a hand-off to its
owning hunter.

### Phase 5: Produce Report

Save as `YYYY-MM-DD-type-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. a party-mode orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line` with the exact declaration and fills every evidence cell
  `references/report-format.md` defines from code read, never inferred.
- **Hand off.** A candidate another hunter owns is cross-referenced, never scored.
