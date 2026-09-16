---
name: type-hunter
description: |
  Use when reviewing Go, Python, or TypeScript code for type structure debt: duplicated type
  declarations, generics that never vary or are loosely constrained, over-powered type constructs,
  enum and alias construct mechanics, Go embedding that leaks API surface, and hand-rolled
  TypeScript utility types. Reducing type duplication, simplifying type-level code, or cleaning up
  type definitions after growth. Defaults to the codebase.

  Covers one shape declared twice by hand, a type parameter bound to one concrete type, a
  constraint that does not express what the body does, a construct more powerful than any use
  needs, an existing enum or alias built with the wrong construct, and promoted method sets a
  struct's consumers should not have.
disable-model-invocation: true
---

# Type Hunter

Audit code for **type structure debt** — one shape declared twice by hand, a type parameter that every instantiation
binds to the same type, a constraint that hides what the body does with `T`, a conditional type where an intersection
would do, a constant group with no named type, an alias where a distinct type was meant, an exported struct promoting
`Lock` and `Unlock` to every importer. Goal: **every type is declared once, no more generic than its uses, and built
with the simplest construct that types every existing use at equal precision.**

Supports Go, Python, TypeScript via per-language reference files.

**Not covered (owned by other hunters):** primitives standing in for domain concepts where no named construct exists
yet, values travelling together with no type, a file accumulating unrelated types (→ smell-hunter); package
organization, canonical import paths, and any hand-written mirror of a generated, ORM, SDK, or protobuf type, mapper
included (→ boundary-hunter); optionality, unguarded narrowing, `any` / `Any` as a *value* type, exhaustiveness,
`as const` / `satisfies` adoption for a value with no parallel declaration, validation of external input into an enum,
never-checked zero sentinels (→ invariant-hunter); repeated logic and repeated runtime values, abstractions with one
call site, runtime control flow, reinvented runtime primitives (→ simplicity-hunter); a struct embedding an interface
it implements only partly, interface width (→ solid-hunter); test design and the structure of fixture or mock types
(→ test-hunter; see Test-code scope); documentation restating types (→ slop-hunter); content validation at trust
boundaries (→ security-hunter). Where ownership is *contested*, the category's **Ownership:** note in What to Hunt is
authoritative.

## When to Use

- Reducing type duplication across modules or packages after rapid growth
- Simplifying over-engineered generics or type-level logic
- Reviewing constant groups, enums, and aliases for the construct they are built with
- Cleaning up type definitions after prototyping
- Reviewing Go struct embedding before a package is exported or published

## Quick Reference

Full rules in **What to Hunt**; every finding must also clear Not-a-finding and the category's evidence bar. Category
names are canonical: the heading here, in What to Hunt, and in the report are identical. Six categories are universal
(with per-language applicability, see Applicability); Embedding Antipatterns is Go-only and Reinvented Utility Types is
TypeScript-only.

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Duplicated Type Declarations | One shape declared twice by hand, where one declaration could follow the other, a runtime value, or a schema | Derive with the named mechanism, or delete one copy and use the survivor | Repeated *logic* or repeated *runtime values* → simplicity-hunter (Duplication); values travelling together with no type → smell-hunter (Data Clumps); a mirror of a generated / ORM / SDK / protobuf type → boundary-hunter, always; `as const` with no parallel declared type → invariant-hunter |
| Generics That Never Vary | A type parameter bound to one concrete production type across every instantiation | Remove the parameter; use the concrete type | A value-level wrapper, manager, factory, or interface with no live seam → simplicity-hunter (Unnecessary Abstractions) |
| Loose Type Parameter Constraints | A constraint that does not express what the body does with `T` | Tighten to the operation the body performs; Go type switch → concrete functions, an interface, or a union constraint; TypeScript → `const` type parameter | `any` / `Any` as a *value* type → invariant-hunter (Type-System Bypasses); a cast inside a generic body that a tighter constraint removes is **one finding here** |
| Over-Powered Type Constructs *(Python, TypeScript)* | A type-level construct more powerful than any existing use needs | Replace with the simpler construct at equal precision | Runtime complexity → simplicity-hunter; a template literal type *missing* for a structured string → smell-hunter (Primitive Obsession) |
| Enum Construct Mechanics | An existing constant group or enum built with the wrong construct, with a consumer that pays for it | Go: named type, `String()`; TypeScript: string-literal union or `as const` object with the derived union; Python: member comparison | Raw values compared with no constant group → smell-hunter (Primitive Obsession); validation of external input into the enum → invariant-hunter / security-hunter; a never-checked zero sentinel → invariant-hunter (Zero-Value Traps) |
| Alias vs Named Type Mechanics *(Go, Python)* | An alias where a distinct type was meant | Go: named type, or delete the alias; Python: `NewType` | A bare primitive with no alias → smell-hunter; TypeScript aliases → smell-hunter (brand-or-withdraw) |
| Embedding Antipatterns *(Go)* | An embedding that promotes API surface the outer type's consumers should not have | Unexported field; delegate the used methods | A partly implemented embedded interface → solid-hunter (Broken Substitution); interface width → solid-hunter (Fat Interfaces) |
| Reinvented Utility Types *(TypeScript)* | A hand-rolled type equal to a built-in utility | Replace with the built-in | Hand-rolled *runtime* primitives → simplicity-hunter (Reinvented Primitives) |

Hunter names are unsuffixed end-state names. Until consolidation completes, live skills are language-suffixed
(`boundary-hunter-go`, `test-hunter-py`, `security-hunter-ts`, and so on).

## Core Principles

1. **Declare once; consolidate.** Two hand-written declarations of one shape are a maintenance trap: a change to one
   must be replicated in the other. The finding names the concept, maps every member, and names the consolidation
   path — a derivation that preserves the shape, or deleting one copy and using the other. Where the language offers
   neither for the variant at hand, there is no finding; "keep in sync" is not an Action.

2. **Generics must vary.** A type parameter every instantiation binds to the same concrete type is indirection, not
   abstraction. The evidence is the enumerated instantiation set, tests marked and never counted as variation.

3. **Constraints document intent.** `[T any]`, `<T>`, an unbounded `TypeVar` say nothing. The constraint should state
   what the body does with `T`; a body that compares, indexes, calls methods, type-switches, or bridges with an
   assertion has outgrown its constraint. A body that treats `T` as opaque has not, however many callers pass one
   shape — that is the generics-must-vary question.

4. **Simplest construct at equal precision.** A conditional type, a recursive type, an `@overload` tower, a
   `ParamSpec`, a hand-rolled mapped type earns its place only where a simpler form loses precision on some existing
   use. The replacement must accept the same inputs, reject the same inputs, and yield the same or a narrower result
   on every enumerated use. If any use needs the power, no finding.

5. **Structure, not enforcement.** This skill asks whether a type is declared once, no more generic than its uses, and
   built with the right construct. Whether the code *guarantees* an invariant — optionality, narrowing, bypasses,
   exhaustiveness — is invariant-hunter's question. Whether a primitive *should become* a domain type is
   smell-hunter's.

6. **Consumers pay; counts nominate.** An enum built with the wrong construct is a finding when a consumer pays for it
   — an untyped constant accepted where an `int` is, a formatted type with no `String()`, a `.value` comparison. Style
   alone is not a defect. Occurrence counts, member counts, and parameter counts nominate candidates and never decide
   a finding.

7. **Respect the language.** Go's small named types, consumer-defined interfaces, and composition are the language
   working as designed; Go has no derivation from a runtime value and no type-level constructs beyond constraints.
   TypeScript's structural typing makes plain aliases interchangeable, so alias mechanics are not judged there.
   Python's consolidation paths are weaker than TypeScript's; the reference names the ones that exist. Never recommend
   a type-level solution the language cannot express.

8. **Scans nominate; reading decides.** `rg 'iota'`, `rg 'TypeVar\('`, `rg 'enum\s+\w+'` find every group. Nothing is
   a finding until the canonical declaration, every instantiation, every promoted-member consumer, and every site of a
   copy to be deleted have been read.

## Terms

- **Type structure debt** — the skill's question: is this type declared once, no more generic than its uses, built
  with the simplest construct that types every existing use at equal precision? Not "does the code enforce this
  invariant" (invariant-hunter) and not "is this primitive a missing domain type" (smell-hunter).
- **Declaration vs value** — the simplicity/type ownership test. Repeated *logic or runtime values* across functions
  is simplicity-hunter's Duplication. Two *type declarations* of one shape — interface, type alias, struct, dataclass,
  `TypedDict`, Pydantic model, enum, union — are this skill's Duplicated Type Declarations, whatever the language. A
  hand-written union parallel to a runtime array is a declaration duplicating a value: here, in a language that can
  derive the union from the value (TypeScript); elsewhere Not a finding.
- **Source kind** — where the canonical declaration lives: *sibling type* (the other hand-written declaration),
  *runtime value* (`as const` array or object), *schema* (Zod, io-ts, Valibot, ArkType, TypeBox, Pydantic, msgspec —
  whatever the project already has). Named in the report's Source cell. A *generated or external type* (`.pb.go`,
  OpenAPI client, Prisma, ORM model, SDK type) is never a source kind here — see Cross-layer mirror.
- **Consolidation path** — the concrete fix a Duplicated Type Declarations finding must name; one of two. (a) A
  *type-level derivation* that preserves the shape: TypeScript `Pick` / `Omit` / `Partial` / `Readonly` /
  intersection, `(typeof arr)[number]`, the installed schema library's inference type in the right role; Go embedding
  a shared struct where the outer type should carry its method set, otherwise an explicit field where the wire or
  storage shape allows it; Python inheritance of `TypedDict`, dataclass, or Pydantic model, `Required` / `NotRequired`
  for omittable-key variants. (b) *Delete and use*: one copy is deleted and the other used directly, which requires that
  every former site of the deleted copy accepts the surviving one. **A finding requires one of the two.** Where neither
  exists for the variant at hand, the duplicate is Not a finding — not a Low with "keep in sync". Pydantic can build
  optional variants at runtime; that produces no static field types and is not a path here.
- **Cross-layer mirror** — a hand-written declaration mirroring a generated, ORM, SDK, or protobuf type, with or
  without a mapper and whatever the mapper does. boundary-hunter's External Type Leaks and Missing Abstraction Over
  Externals own that relationship, mapper quality included; never duplication here, because the only "fix" this skill
  could name puts the external type where boundary-hunter says it must not go. Duplication is between two
  *hand-written* declarations whose consolidation path exists.
- **Instantiation** — one concrete binding of a type parameter, found project-wide by reading call sites and
  declarations, not by regex: TypeScript and Python infer arguments without writing them, Go writes them rarely at
  call sites. Test-file instantiations are recorded and marked `(test)` but never counted as variation.
- **Closed consumer set** — invariant-hunter's per-symbol rule, reused for every usage-based narrowing (Generics That
  Never Vary, Over-Powered Type Constructs, Embedding Antipatterns' used-subset argument). In application code the
  repository is the world and export alone is no limit. A symbol that a library publishes for consumers outside the
  tree, whose instantiations or callers therefore cannot be enumerated, is **withdrawn** and recorded as a Scope
  `Limitation` line. No repository-wide classification; the question is asked per exported symbol, read from how the
  package is published and used.
- **Existence vs construct** — the smell/type ownership test for enums and aliases. No named construct yet (raw
  string compared, bare `str` parameter) → smell-hunter's Primitive Obsession, whose reference names the remedy. A
  constant group, enum, or alias *exists* and is built with the wrong construct → here. Because this skill fires only
  where a construct exists, it never contradicts smell-hunter's remedy on the same site. TypeScript aliases are the
  exception: smell-typescript's brand-or-withdraw rule keeps the alias question there.
- **Equal precision** — the bar every "simpler form" must clear (Over-Powered Type Constructs, Reinvented Utility
  Types, and Duplicated Type Declarations' derivation): on every enumerated use the replacement accepts the same
  inputs, rejects the same inputs, and produces the same or a narrower result. `A & B` is not `DeepMerge<A, B>` when
  a member exists in both with different types (the intersection yields `never`); `int | str` is not an `@overload`
  tower that maps `int → int` and `str → str`.
- **Within-skill precedence** — one finding per site. On one type parameter, Generics That Never Vary wins (removing
  the parameter retires the constraint question); otherwise Over-Powered Type Constructs beats Loose Type Parameter
  Constraints. A `Literal` beside an `Enum` is Duplicated Type Declarations, cross-referenced from Enum Construct
  Mechanics, never both.
- **Target scope and context** — findings anchor in the manifest; the canonical declaration, every instantiation,
  every consumer of a promoted method, every site of a copy to be deleted, and test files are read wherever they live.

## Not a finding on these grounds alone

Conditionals, not category exemptions — each states what does **not** justify a finding and, where one exists, what
would:

- **Separate request and response types at an API boundary** that differ by validation, serialization tags, or
  consumer. *Is* Duplicated Type Declarations when both are hand-written, live in one layer serving one boundary, and
  a consolidation path at equal precision exists.
- **Any hand-written type mirroring a generated, ORM, SDK, or protobuf type**, with or without a mapper, whatever the
  mapper does. boundary-hunter's, always.
- **Two types sharing some members, each with its own.** Not duplicates. Members that travel together as parameters
  with no type at all are smell-hunter's Data Clumps.
- **A duplicate with no consolidation path in this language** (a Python patch type with every field optional over a
  dataclass or model; a Pydantic model beside a `TypedDict` where neither can be deleted; a Go or Python union parallel
  to a runtime sequence; a Go DTO where embedding leaks methods and a field changes the wire shape). No finding at any
  severity.
- **An exported symbol whose consumer set cannot be closed inside the tree** (a library's published generic, struct,
  or embedded surface). Withdrawn with a Scope `Limitation` line; the same symbol unexported, or in application code,
  is judged.
- **A generic whose second instantiation is a test.** Still Generics That Never Vary; the test is cited and the Action
  says how it survives. A second *production* instantiation withdraws the finding.
- **`[T any]` / `<T>` / an unbounded `TypeVar` where the body treats `T` as opaque** (stores, returns, passes
  through). The constraint matches the use, however many callers pass one shape — that question is Generics That Never
  Vary. *Is* Loose Type Parameter Constraints when the body compares, indexes, calls methods, type-switches, or bridges
  with an assertion.
- **A type-level construct one existing use needs.** Library types, framework constraints, and serialization
  boundaries may need conditional or recursive types; if any enumerated use requires the power, or the simpler form
  loses precision on any use, no finding.
- **A hand-rolled utility with different semantics from the built-in** (`DeepPartial`, a non-distributive `Exclude`,
  a `Pick` that errors on missing keys). Not reinvention.
- **Raw strings compared with no constant group** — smell-hunter's Primitive Obsession; this skill needs an existing
  construct.
- **A bare `str` / `string` parameter for an identifier with no alias declared** — smell-hunter's. *Is* Alias vs Named
  Type Mechanics when two aliases of the primitive exist and are mixed at a site.
- **A Python `class X(str, Enum)`** by itself; **a Go named constant type with no `String()`** that is never
  formatted, logged, or serialized; **gaps or manual values inside an `iota` block**. No consumer pays; no finding.
- **A TypeScript `enum` with reverse mapping in use, bitwise flags, or non-TS consumers** named in the code or its
  serialization; **a `const enum`** as such. Not Enum Construct Mechanics; the Action's risk clause exists for the
  borderline.
- **A Go `type X = Y` alias with a deprecation or migration comment**, or during a visible rename (both names in live
  use). Not a finding.
- **A method-less Go named type**, over a primitive or a composite. Not a finding.
- **A `sync.Mutex` embedded in an unexported struct**, or held as an unexported field. Not Embedding Antipatterns — a
  deliberately narrower line than the current linter view (see the Go reference).
- **Embedding that promotes exactly what the consumers call** (an `io.Reader` embed on a type whose consumers read).
  The language working as designed.
- **`as const` on a config object with no parallel declared type** — invariant-hunter's adoption finding, not
  duplication.
- **A pattern in a test file** — never a finding; test files are out of scope, not exempt (see Test-code scope).

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Enum Construct Mechanics").

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

**Action:** derive from the source with the named mechanism — the utility type, `(typeof arr)[number]`, the schema
library's inference type in the right role, inheritance, `Required` / `NotRequired` — or delete the copy and use the
survivor. For repeated inline expressions: name it once — an alias; a callable `Protocol` only when keyword arguments
or overloads need it. In Go: embed only where the outer type should carry the method set, an explicit field where the
wire or storage shape allows it, delete-and-use where one struct stands in for the other at every site; when none
fits, withdraw.

**Ownership:** the declaration-vs-value test (see Terms). simplicity-hunter keeps repeated logic and repeated runtime
values, and its own rule "duplication derivable from an existing source of truth" for values; two declared types of
one shape, a declared union beside a runtime array, and a manual type beside a schema are here. Values travelling
together with no type are smell-hunter's Data Clumps. Any cross-layer mirror is boundary-hunter's, mapper included
(see Terms). `as const` recommended to make a value the *derivation source* of a declared union is this category's
Action; `as const` / `satisfies` for a value with no parallel declaration stays invariant-hunter's Runtime Checks
Promotable to Types. A `Literal` beside an `Enum` is reported here and cross-referenced from Enum Construct
Mechanics.

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
simplicity-hunter's Unnecessary Abstractions; a *type parameter* with one instantiation is here. On one parameter this
category takes precedence over Loose Type Parameter Constraints: removing the parameter retires the constraint
question.

### Loose Type Parameter Constraints

A constraint that does not express what the body does with `T`.

**Signals:**

- `[T any]` with `comparable` or method use inside; `switch any(v).(type)` inside `func F[T any]`
- `<T>` / `<T extends unknown>` / `<T extends any>` used as an object
- `TypeVar("T")` where only `int | str` is passed (constraints) or a base class is assumed (`bound=`); PEP 695 `[T]`
  with the same defects
- TypeScript only: a parameter receiving array or object literals whose tuple or literal types a downstream consumer
  re-narrows, and no `const` modifier

**Evidence bar:** name the operation the body performs on `T` that the constraint does not permit, or the bridge that
makes it compile (`any(v).(fmt.Stringer)`, `(x as any)[k]`, `cast`); state the tightest constraint every existing
instantiation satisfies. Go form: a generic body that type-switches on `T` — the constraint is `any` and the body
enumerates types. TypeScript `const` form: the re-narrowing consumer, and that the parameter type is an array or object
(a scalar `T extends string` already preserves the literal).

**Action:** tighten to the stated constraint. Go type switch: concrete functions, an interface, or a union constraint.
TypeScript: add `const` to the parameter (TS 5.0+, read from the lockfile).

**Ownership:** `any` / `Any` as a *constraint* is here; `any` / `Any` as a *value type* is invariant-hunter's
Type-System Bypasses (Go `any` / `interface{}` as a value type is nobody's, as invariant-hunter recorded). Precedence
for the overlap: a bypass inside a generic body (`(o as any)[k]`, `cast(T, x)`, `any(v).(X)`) that a tightened
constraint removes is **one** Loose Type Parameter Constraints finding here; invariant-hunter does not score the same
cast. An opaque body is never Loose (see Not-a-finding).

### Over-Powered Type Constructs *(Python, TypeScript)*

A type-level construct more powerful than any existing use needs.

**Signals:**

- TypeScript: a conditional type nested deep; recursion where a flat union suffices; mapped `as` remapping where
  `Pick` suffices; type-level string arithmetic a runtime function replaces; template-literal metaprogramming
- Python: `ParamSpec` / `Concatenate` decorator typing for one decorated signature where a `Protocol` suffices;
  `@overload` towers with one input→output mapping
- Many type parameters (nomination only)

**Evidence bar:** name the simpler construct and show it types every enumerated instantiation at equal precision; if
any use needs the power, no finding. Parameter count nominates only.

**Action:** replace with the simpler construct. Where the power is needed (library types, framework constraints,
serialization boundaries), no finding.

**Ownership:** type-level only; simplicity-hunter's Complex Control Flow and Reinvented Primitives are runtime code.
Template literal *overuse* is here; a template literal type *missing* for a structured string domain is
smell-hunter's Primitive Obsession. On one type parameter, Generics That Never Vary wins first; otherwise this category
beats Loose Type Parameter Constraints. Not applicable to Go, which has no type-level constructs beyond constraints —
the Go type-switch form is Loose Type Parameter Constraints.

### Enum Construct Mechanics

An existing constant group or enum built with the wrong construct, with a consumer that pays for it.

**Signals:**

- Go: an `iota` group with no named type (untyped constants accepted anywhere an `int` is); a named constant type
  formatted, logged, or serialized (`%v`, `%d`, `fmt.Sprint`, JSON) with no `String()`
- TypeScript: an `enum` whose members are only ever compared or serialized (a union suffices; supporting evidence:
  value imports of the enum across modules that a type-only union would erase); a numeric `enum` for unordered
  non-flag values that is serialized; `enum` members compared to raw literals with `===`; a single-member `enum`
- Python: members compared by `.value` against raw strings; a single-member `Enum`; a `Literal[...]` parallel to an
  `Enum` (reported as Duplicated Type Declarations, cross-referenced)

**Evidence bar:** anchor at the group; name the defect and the consumer that pays for it — the site that accepts the
untyped constant, the formatting site with no `String()`, the comparison, the serialization.

**Action:** Go: a named type, a `String()` method (`stringer` as vocabulary, never run). TypeScript: a string-literal
union, or an `as const` object with the union derived from it, with the serialization / non-TS-consumer risk named
where the value crosses a boundary and `erasableSyntaxOnly` named where the project sets it. Python: member
comparison (`StrEnum` as vocabulary at 3.11+); drop the single member.

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

**Ownership:** identity types with no alias at all are smell-hunter's Primitive Obsession — this category needs an
existing alias. Not applicable to TypeScript: structural typing makes plain aliases interchangeable, and
smell-typescript's brand-or-withdraw rule keeps the alias question there.

### Embedding Antipatterns *(Go)*

An embedding that promotes API surface the outer type's consumers should not have. Defined in full in
`references/type-go.md`; summarized here so the category set is complete in one place.

**Evidence bar:** (1) `sync.Mutex` / `sync.RWMutex` embedded (not a field) in an exported struct — `Lock` / `Unlock`
callable by every importer; (2) an embedded type whose promoted methods conflict with the outer type's own or exceed
what any consumer in the repository calls — enumerate the promoted set and the used subset; consumer set closed, else
withdrawn.

**Action:** an unexported field; delegate the used methods explicitly.

**Ownership:** a struct embedding an interface it implements only partly, leaving the embed nil, is solid-hunter's
Broken Substitution however the panic is reached. Interface *width* is solid-hunter's Fat Interfaces; this category
judges a *struct's* promoted method set.

### Reinvented Utility Types *(TypeScript)*

A hand-rolled type equal to a built-in utility. Defined in full in `references/type-typescript.md`; summarized here.

**Evidence bar:** the built-in named; the project's TypeScript version (lockfile) supports it (gate 1); exact semantic
parity including homomorphic modifier preservation (gate 3) — `DeepPartial` is not `Partial`, a distributive variant
is not `Exclude` unless the built-in is also distributive there; net concept reduction (gate 6). simplicity-hunter's
gates 2, 4, 5 are moot at type level.

**Action:** replace with the built-in.

**Ownership:** simplicity-typescript's primitive list has no utility types; unclaimed, kept here.

### Within-skill precedence

One finding per site (see Terms). On one type parameter: Generics That Never Vary first — removing the parameter
retires every constraint question; otherwise Over-Powered Type Constructs beats Loose Type Parameter Constraints. A
`Literal` beside an `Enum` is Duplicated Type Declarations, cross-referenced from Enum Construct Mechanics. The
Evidence cell of whichever is reported names the other reading in one clause.

## Applicability

Six categories are universal in definition; each language reference declares them applicable or not, with the reason.
**A language with no reference is not supported** — its files are excluded, never implicitly audited.

| Category | Go | Python | TypeScript |
| -------- | -- | ------ | ---------- |
| Duplicated Type Declarations | yes — sibling type (embed / field / delete-and-use); no runtime-value derivation exists | yes — sibling type (inheritance, `Required` / `NotRequired`, delete-and-use for `Literal` beside `Enum` and duplicate aliases); schema only where the model can replace the copy; no runtime-value derivation exists, so a `Literal` beside a tuple is Not a finding | yes — sibling type, runtime value, schema |
| Generics That Never Vary | yes | yes — `TypeVar` / `Generic`, PEP 695 | yes |
| Loose Type Parameter Constraints | yes — `any` / over-wide interface constraint; type switch on `T` | yes — unbounded `TypeVar`, missing `bound=` / constraints | yes — plus the missing `const` type parameter signal |
| Over-Powered Type Constructs | **n/a** — no conditional, mapped, or overload constructs; the type-switch form is Loose Type Parameter Constraints | yes — `ParamSpec` / `Concatenate` where a `Protocol` suffices, overload towers | yes |
| Enum Construct Mechanics | yes — `iota` with no named type, `String()` on a formatted type | yes — `.value` comparison, single member | yes — `enum` vs union, numeric non-flag serialized, `===` to raw literals, single member |
| Alias vs Named Type Mechanics | yes — `type X = Y` only | yes — two aliases of one primitive mixed | **n/a** — structural typing; brand-or-withdraw is smell-typescript's rule |

Language-only categories: Embedding Antipatterns (Go), Reinvented Utility Types (TypeScript). Python has none.

## Test-code scope

**Test files are excluded from findings** — the deviation invariant-hunter and solid-hunter record. Test paths per
language: Go `*_test.go`; Python `test_*.py`, `*_test.py`, `tests/`, `conftest.py`; TypeScript `*.test.*`,
`*.spec.*`, `*.e2e.*`, `__tests__/`. The exclusion is **by path**: a production helper under `tests/` is not audited.

**Recorded gap:** the design of a fixture type, a mock's generic helper, or a test-local duplicate of a production
shape has no owner. test-hunter owns setup duplication, over-mocking, and coverage, not type structure inside tests;
recorded here the way invariant-hunter recorded test-file suppressions, resolved at test-hunter's unification.

Test files are **read as context**:

- A test instantiation of a generic is listed in the Instantiations cell and marked `(test)`; it never counts as
  variation and never withdraws a finding, and the Action says how the test survives the specialization.
- A test double that is the only second implementor of an embedded interface is recorded the same way.

Test evidence never raises Severity. Cite the test file in the Evidence cell; anchor the finding at the production
declaration.

## Severity and Impact

Every finding carries **both**, per the sibling definitions. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is:**

- **Critical** — never available. Type structure debt is not itself a production defect. A drifted duplicate that is
  already producing wrong behavior names the divergence in Evidence and reports at High; the runtime defect is not
  scored here and this skill does not route it.
- **High** — a Duplicated Type Declarations finding whose copies have already diverged for the same concept with both
  copies live (a member present in one, absent or differently typed in the other, both consumed); an exported struct
  promoting `Lock` / `Unlock` to importers.
- **Medium** — the default for a finding that clears its bar.
- **Low** — a missing `String()` on a formatted constant type; an alias cleanup; a loose constraint on a generic with
  a single caller; a reinvented utility; a single-member enum.

A candidate that fails its evidence bar or matches a Not-a-finding conditional produces **no finding at any severity**.
Severity is never a confidence scale: an uncertain finding — an instantiation set that could not be closed, a
consolidation path not verified at every site — is withdrawn with a `Limitation` line, never downgraded.

**Impact — how much the change is worth:** contextual, never derived from occurrence count. A duplicated entity type
every handler imports is High impact at Medium severity; a phantom parameter on an internal helper is Low.

- **High** — substantial reduction on a type read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

Recommendations group by Severity (High → Medium → Low), then by Impact within each group.

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
   included — is **excluded, not audited**: without a reference there is no consolidation-path vocabulary, no
   eligibility rule, no scan set, no version gate. Record `excluded — no reference for .<ext>: {count} files` in
   Scope, naming each extension.

3. **Load language references.** For every detected language, read `references/type-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/type-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**; do not continue with the universal categories only.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus the
   test-path exclusion** to that language's files. These subsets are then immutable. Record in Scope: raw manifest
   count, each per-language eligible subset, exclusions with the test paths listed, and
   `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, Markdown-only inputs, test paths, and generated files
   identified by each reference's authoritative **in-file marker** — **never** by filename guessing.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop before
   scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Files outside it, test files and generated files included, are *read* as **context**: finding the canonical
   declaration, enumerating instantiations, reading a promoted method's consumers, and checking every site of a copy
   to be deleted routinely leave any diff scope. Diff and path scope narrow the manifest, never the context reading.

5. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) for stated policies: a chosen
   enum style, a deliberate request/response split, a published package surface, generics kept for a documented
   consumer. A stated policy is respected and acknowledged in the report's `Policy:` line.

6. **Read the version gates** each loaded reference names: Go from `go.mod` (`cmp.Ordered` needs 1.21+); Python from
   `pyproject.toml` `requires-python` (`StrEnum` 3.11+, PEP 695 and the `type` statement 3.12+); TypeScript from the
   lockfile (`const` type parameters 5.0, `Awaited` 4.5) and `tsconfig.json` (`erasableSyntaxOnly`, 5.8). A gate
   the project does not meet removes the Action that needs it; the reference says what replaces it.

**No toolchain step.** `tsc`, `mypy`, `pyright`, and `go vet` report none of these categories. Linters that nominate
related patterns exist (`@typescript-eslint/no-unnecessary-type-parameters`, golangci-lint
`embeddedstructfieldcheck`) and are neither run nor required; `stringer` is remedy vocabulary, never run. The report
carries no Toolchain lines.

### Phase 2: Scan for Candidates

Scans produce **candidates only**. For each loaded reference, run its Phase 2 scan block against that language's
eligible subset (`SCOPE=.` in codebase mode). Pass an explicit path to **every** `rg` invocation. Diff mode nominates
from the working tree over the manifest files, not from added lines: type structure is a property of the current
code.

### Phase 3: Enumerate Declarations, Instantiations, and Consumers

Project-wide, regardless of scope — the canonical declaration, the instantiations, and the consumers of a promoted
method live outside any diff. For each nominated candidate:

- **Duplicates**: the canonical declaration and every other hand-written declaration of the concept; the source kind;
  each member mapped; for delete-and-use, every site of the copy to be deleted and whether it accepts the survivor;
  whether either copy is generated or external (then boundary-hunter's, stop).
- **Generics**: every instantiation — explicit type arguments by scan, inferred ones by reading call sites and
  declarations — with test files marked `(test)`; the operations the body performs on `T`; for an exported symbol,
  whether the package publishes it to consumers outside the tree.
- **Type-level constructs**: every instantiation and what each needs of the construct.
- **Constant groups and enums**: the consumers that accept, compare, format, serialize, or import the members.
- **Aliases**: Go, the comments and the second live name; Python, the sites where the two aliases meet.
- **Embeddings**: the promoted method set, the outer type's own methods, and the subset every consumer in the
  repository calls; exportedness.

Inference bounds this phase: regex finds explicit `<User>`, `[User]`, `Cache[User]` only. Inferred instantiations are
found by reading consumers. Record in Scope an `Enumeration` line stating what was searched and how the set was
closed; a set that cannot be closed withdraws the finding with a `Limitation` line. Findings claim the enumerated set
only.

### Phase 4: Evaluate Each Finding

For each candidate: apply **Not-a-finding** first; confirm the category applies in that file's language (see
Applicability); apply the four ownership tests — declaration vs value, existence vs construct, cross-layer mirror,
closed consumer set — and within-skill precedence; then clear the category's evidence bar from What to Hunt, the
consolidation-path requirement and equal-precision bar included. Check repository policy: a `Policy:` line withdraws
what it names. Run each loaded reference's Phase 4 block for its language-specific judgment.

Assign **Severity and Impact** to every finding (both required; they diverge). One finding per site. Nothing is held
back; `Audit completed: N findings` counts every reported finding.

### Phase 5: Produce Report

Save as `YYYY-MM-DD-type-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if none exists). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "Eight of ten fields match — duplication" | Name the concept, map every member, and name the consolidation path at equal precision. No path in this language, no finding. |
| "The domain type mirrors the Prisma model" | A mirror of a generated, ORM, SDK, or protobuf type is boundary-hunter's, whatever the mapper does. Never a source kind here. |
| "Embed the shared struct to fix the duplicate" | Does the outer type want the method set? Otherwise a field; otherwise delete-and-use; otherwise withdraw. An embed that leaks surface is a new finding. |
| "Keep them in sync — report it Low" | A duplicate with no consolidation path is Not a finding at any severity. |
| "Every caller passes `User`, so `T` is too loose" | That is Generics That Never Vary, not Loose. An opaque body's constraint matches its use. |
| "`T any` with one call site — loose constraint" | What does the body *do* with `T`? Compare, index, call, switch, bridge? Name the operation or there is no Loose finding. |
| "The generic has a second instantiation in a test" | Tests never count as variation. Cite the test; the Action says how it survives. |
| "The package is a library, so generics are exempt" | Per symbol, not per repository. Is *this* symbol published to consumers outside the tree? Then withdraw with a `Limitation`; otherwise judge it. |
| "`(o as any)[k]` — invariant-hunter's bypass" | Inside a generic body that a tighter constraint fixes, it is one Loose Type Parameter Constraints finding here. Do not score it twice. |
| "`DeepMerge` is four levels deep — replace with `A & B`" | Equal precision on every use: a key in both with different types makes `A & B` yield `never`. Then no finding. |
| "The overload tower is a union" | `int → int`, `str → str` is a mapping a union loses. Only a form that keeps every mapping on every use is simpler. |
| "`class Color(str, Enum)` — should be `StrEnum`" | Availability is not a defect. `StrEnum` is vocabulary inside a `.value` comparison finding. |
| "`iota` with a gap — fragile enum" | The specification shows gaps and manual values as intended. Which consumer pays? None, no finding. |
| "No `String()` on the constant type" | Is the type formatted, logged, or serialized anywhere? No consumer pays, no finding. |
| "`if s == \"active\"` — enum mechanics" | Is there a constant group? No → smell-hunter's Primitive Obsession. This skill needs an existing construct. |
| "`type UserId = string` in TypeScript — alias mechanics" | Not applicable: structural typing, and smell-typescript's brand-or-withdraw rule owns it. |
| "`type UserID string` has no methods — adds nothing" | A method-less named type is Not a finding, over a primitive or a composite. |
| "The struct embeds `sync.Mutex`" | Exported, and embedded rather than a field? Then High. Unexported or a field: no finding, by a stated choice. |
| "The embed leaves `Store` nil and `Delete` panics" | solid-hunter's Broken Substitution. Cross-reference, do not score. |
| "The 400-line `types.ts` mixes everything" | smell-hunter's God Module. Type organization is not a category here. |
| "I'm not sure the instantiation set is closed, so I'll report it at Low" | Severity is not confidence. Withdraw it with a `Limitation` line. |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do the universal categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** Audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only *categories* with findings. Omit a category heading, table, or list
  entirely when it would contain zero items — no empty tables, placeholder subsections, or negative statements like
  "none found" or "no issues". The Scope section is not a category and is filled in from the template every run,
  including any `Enumeration`, `Limitation`, and `Policy:` lines.
- **Scope: type structure only.** A finding that doesn't answer "is this type declared once, no more generic than its
  uses, and built with the right construct?" belongs to another hunter. Contested boundaries are resolved at the
  category that owns them: each **Ownership:** note in What to Hunt states what is kept here and what routes away.
- **Evidence required.** Every finding cites `file:line` (path form per the language reference) with the exact
  declaration, and the category's evidence cells — Overlap and Path, Instantiations, Body requires, Simpler form,
  Defect, Mixing site, Promoted surface, Built-in — are filled, never inferred.
- **One finding per site.** When two categories describe the same code, the within-skill precedence rule picks the
  primary one and the Evidence cell names the other reading.
- **Handoff, not duplication.** When a candidate belongs to another hunter — a mirror of a generated type, a raw
  string with no constant group, a partly implemented embed, an `as const` with no parallel type — cross-reference it
  and do not score it here.
- **Respect the language.** Calibrate to the audited language's constructs — the reference carries the calibration.
  Never recommend a derivation or type-level construct the language cannot express, and never recommend a construct
  a version gate the project does not meet requires.
