---
name: boundary-hunter
description: |
  Use when reviewing Go, Python, or TypeScript code for boundary violations: dead and leaked
  exports, deep imports past a unit's public entry, import edges against the layer map or a stated
  prohibition, runtime and type-only cycles, external types crossing inward, and generic package
  names. Shrinking a public API surface, enforcing encapsulation, untangling layers, or preparing a
  package to be replaceable. Defaults to the codebase.

  Covers an export no consumer outside the unit uses, an export that shows how the unit works,
  a consumer reaching past the barrel or `__init__`, a module edge pointing outward against a
  recorded boundary source, modules importing each other, a third-party type in an inward
  signature, and a unit named for what it contains.
disable-model-invocation: true
---

# Boundary Hunter

Audit code for **boundary violations** — an exported helper no other unit imports, a cache map a consumer ranges
over, an import reaching past a barrel into `internal/`, a domain module importing the Postgres adapter, two modules
importing each other until initialization order decides whether the process starts, `pgx.Tx` in a domain signature, a
`utils` package holding three unrelated capabilities. Goal: **every unit is a black box, replaceable from its public
entry alone.**

Supports Go, Python, TypeScript via per-language reference files.

**Not covered (owned by other hunters):** unused non-exported functions, constants, and branches, and any Python
public name with no importers at all (→ simplicity-hunter Dead Code Paths); unused imports and bindings
(→ slop-hunter); a generic-named *file* and file placement inside a unit (→ smell-hunter God Module in Python and
TypeScript; in Go nobody's — smell-hunter marks God Module n/a for Go); package-level
responsibility and change analysis — named actors, independent reasons to change (→ solid-hunter Responsibility
Sprawl); type-level wiring, self-instantiation, and module-level singleton reads (→ solid-hunter Concrete Dependency
Chains); two hand-written declarations of one shape with a consolidation path (→ type-hunter Duplicated Type
Declarations); a promoted method set from an embed (→ type-hunter Embedding Antipatterns); type-system bypasses at a
boundary layer (→ invariant-hunter); content validation at a trust boundary (→ security-hunter); message chains
inside object design — recorded as an unowned gap, see Test-code scope. Where ownership is *contested*, the
category's **Ownership:** note in What to Hunt is authoritative.

## When to Use

- Shrinking a unit's public surface to what is consumed
- Preparing a package to be replaceable from its public entry alone
- Untangling layers after a feature grew across them
- Chasing an import cycle, an `ImportError`, or a bundler circular-reference warning
- Reviewing whether a third-party or generated type has reached the domain
- Reviewing package and directory names before a module is published or a monorepo is split

## Quick Reference

Full rules in **What to Hunt**; every finding must also clear Not-a-finding and the category's evidence bar. Category
names are canonical: the heading here, in What to Hunt, in the applicability table, and in the report are identical.
Forms are labelled variants inside a category, never separate categories. All seven categories are universal in
definition; Cyclic Dependencies is n/a for Go (the compiler rejects import cycles).

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Dead Exports | An export with no external consumer | Unexport; drop from `__all__`; replace the wildcard with named re-exports | An unused *unexported* function or constant, and a Python public name with no importers anywhere → simplicity-hunter (Dead Code Paths); an unused import or binding → slop-hunter (Trivially Dead Code) |
| Leaked Internals | A consumed export exposing *how* the unit works | Unexport the member; expose the behavior through a method or an owned type | A consumer using more foreign data than its own → smell-hunter (Feature Envy); a promoted `Lock` / `Unlock` from an *embed* → type-hunter (Embedding Antipatterns) |
| Deep Imports | A consumer reaching past the unit's public entry | Import from the entry; expose the symbol there; `internal/` or `exports` to enforce | Nothing; this category is unshared |
| Dependency Direction Violations | A module edge pointing outward against the layer map, or an edge an explicit prohibition names | Move the type to its owner; inject from the composition root; invert only where the language leaves no other break | Type-level wiring and self-instantiation → solid-hunter (Concrete Dependency Chains); one change editing many areas → smell-hunter (Shotgun Surgery) |
| Cyclic Dependencies *(Python, TypeScript)* | Two or more modules importing each other, directly or transitively | Extract the shared concept into a third module, or invert the edge | Nothing; a provable `ImportError` is reported here with the failing site |
| External Type Leaks | An external type crossing inward | An owned type or interface declared in the inward unit, implemented and converted at the edge | A hand-written mirror of a generated / ORM / SDK type → nobody's when it sits in the external's own layer; a bypass with a reason at a boundary → invariant-hunter; content validation → security-hunter |
| Generic Boundary Names | A package or directory unit named for what it contains, not what it provides | Name after the capability; split by capability | A generic-named *file* (`utils.ts`) → smell-hunter (God Module); package responsibility and actors → solid-hunter (Responsibility Sprawl) |

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`test-hunter-go`, `doc-hunter-py`, `security-hunter-ts`): route to the one matching the finding's language.

## Core Principles

1. **A unit is its public entry.** The exported surface is a promise; everything else is implementation. Exports say
   *what the unit provides*, never *how it works*. A consumer that must understand internals to use the API correctly
   is the defect, and the finding is anchored at the export, not at the consumer.

2. **Owned types cross; implementation types stay home.** Data flowing between units is expressed as the language's
   own types, standard-library types, or owned domain types. A cache map, a row struct, a state-machine field, an
   intermediate representation forces every consumer to depend on how the unit works. (No tension with smell-hunter's
   Primitive Obsession: both resolve in owned domain types.)

3. **Direction follows a recorded boundary source, never a guess.** Dependency Direction Violations and External Type
   Leaks exist only where the repository states an ordering (instructions, an ADR, an `import-linter` `layers`
   contract, or conventional sibling directory names) or an explicit prohibition (a `forbidden` contract, an Nx
   constraint, a `mayDependOn` set). Without one, both categories are withdrawn with a Scope line. Tiers are never
   inferred from the graph, from fan-in, or from who imports an external.

4. **Externals stop at the edge.** Third-party and generated types belong in the units that wrap them. The edge layer
   *is* the wrapping layer — its own signatures, re-exports, and conversions are never findings. The finding is the
   crossing: the external type in an inward unit's exported API.

5. **Scans nominate; the graph and reading decide.** `rg 'export \*'`, `go list`, `depcruise --output-type json` find
   candidates. Nothing is a finding until the consumers have been enumerated by reading, the tier has been read from
   a recorded source, the cycle's edges have been classified, and the rewrite test has been answered in words.

6. **Documented coupling is policy, not a finding.** An edge the repository's instructions or a contract
   configuration explicitly permits is withdrawn with a `Policy:` line. Silence is not permission and not
   prohibition: an edge no rule mentions is judged by the map alone.

7. **Never an interface for its own sake.** "Depend on abstractions" is not this skill's principle. Importing a
   concrete type across a boundary is not a finding. The only interface this skill asks for is the one declared in an
   inward unit to keep an external type at the edge, or the last-resort inversion where the language leaves no other
   way to break an outward import.

8. **Respect the language.** Go's flat packages, compiler-enforced `internal/` and cycle prohibition; Python's
   convention-only privacy and import-time execution; TypeScript's barrels, `exports`, and type erasure are each the
   language working as designed. Never recommend an enforcement mechanism the language does not have — Python's
   remedy vocabulary is convention and contracts, not `internal/`.

## Terms

- **Import graph** — one file-level (module-level) import graph, built project-wide. Nodes are Go packages, Python
  modules, TypeScript and JavaScript files; edges are import statements (`import`, `from … import`, `require`,
  `export … from`), each tagged **erased** (type-only: `import type`, a `TYPE_CHECKING` block, an import the compiler
  elides) or **runtime**. Boundary units and layer tiers are annotations on nodes. **Cyclic Dependencies and
  Dependency Direction Violations are judged on module edges** — a cycle is a cycle of files; a direction violation is
  an edge whose endpoints carry different tiers, even inside one workspace package (`src/domain/x.ts →
  src/infra/y.ts`). Dead Exports, Leaked Internals, Deep Imports, and Generic Boundary Names concern a unit's public
  surface and are judged on the projection onto units. JavaScript files (`.js`, `.jsx`, `.mjs`, `.cjs`) are nodes so a
  mixed repository's graph is correct; they are never finding anchors.
- **Boundary unit** — the construct whose exports form an API and whose imports form edges. Go: the package (import
  path). Python: the package (a directory with `__init__.py`), or a standalone module where no package structure
  exists. TypeScript: the workspace package when `package.json` `exports` / `main` names an entry; else the directory
  with a barrel (`index.ts`); else the file. Generic Boundary Names applies to package and directory units only — a
  file is never a "boundary name".
- **Public entry** — the path a consumer is meant to import from. Go: the package path; sub-packages the parent alone
  imports are implementation. Python: an `__init__.py` that re-exports names; independent of any `__init__`, a
  `_`-prefixed module or an `internal` / `_internal` package is implementation. TypeScript: the barrel, the `exports`
  entry, or a tsconfig `paths` alias **that names a unit** — one mapping to a package root or a barrel (`@org/auth` →
  `packages/auth`, `@auth` → `src/auth/index.ts`). A root wildcard (`@/*` → `src/*`, `~/*`) is a convenience prefix,
  not an entry; nothing is deep relative to it. A TypeScript directory with no barrel, no `exports`, and no
  unit-named alias makes every file public and has no Deep Imports.
- **Export** — per language; the full rules are in each reference's "Boundary unit, public entry, export,
  publication" section. Go: an uppercase top-level identifier or method — **struct fields** and **reflection-protocol
  methods** (`String`, `MarshalJSON`, …) are never Dead Exports candidates, because reflection reaches them and the
  set cannot be closed; an interface-named method (`Close`, `ServeHTTP`) **is** a candidate unless a site uses the type
  *as that interface*. Name matching alone abstains from nothing. TypeScript: the `export` keyword, judged at the
  unit's entry. Python: a name in `__all__` or re-exported by a package `__init__.py` — **for Dead Exports only**; a
  plain non-underscore name has no "unexport" edit. Leaked Internals and Deep Imports do not use this gate — a consumed
  non-underscore name is judged by the rewrite test whatever `__all__` says, and a deep import is judged by the path
  reached.
- **External consumer** — a use of the export from outside the boundary unit, in a non-test file. Imports are the
  usual form; **string references also count** (Python entry points in `pyproject`, Django settings strings, plugin
  registries, template names, Go `//go:linkname`, TypeScript dynamic `import()` with a literal). A test-file import is
  recorded (`test only: {file}`) and never counts. A sibling file inside a TypeScript or Python unit is not external.
  In Go, an exported identifier with only package-local use is the `package-local only` form of Dead Exports.
- **Published unit** — a unit whose exports may have consumers outside the tree. **Any evidence of documented import
  use opens the set** (mixed → open → withdrawn). **Closed** (judged in tree): Go — a `main` package; an `internal/`
  path; a package of a module that contains a `main` package **and** whose repository documents no import use (no
  `go get <module path>` line or quoted `"<module path>…"` import path in a README or doc, no `doc.go` on a non-main
  package, no `examples/` directory). TypeScript — a workspace package with `private: true`, or a unit not reachable
  from any `package.json` `exports` / `main`. Python — a `_`-prefixed or `internal` package; a distribution with a
  `Private :: Do Not Upload` classifier; a repository whose entry is a web or framework application (`manage.py`,
  `wsgi.py`, `asgi.py`). **Open** (withdrawn): Go — a module with no `main` package and a public module path, or any
  documented import use; TypeScript — reachable from `exports` / `main` without `private: true`; Python — a package a
  `[project]` / `[tool.poetry]` distribution declares with a public import path and none of the closing signals.
  `__main__.py` and `[project.scripts]` are **not** application signals — libraries ship CLIs that way. No release
  workflows or tags are read. **Only negative claims are withdrawn:** Dead Exports, with one Scope `Limitation` line
  per unit. Leaked Internals with a named in-tree consumer, Deep Imports, Dependency Direction Violations, and External
  Type Leaks are positive observations and are reported in open units.
- **Layer map** — an ordering of units inward. Sources, in precedence: (1) repository instructions and ADRs
  (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, `docs/**/adr*/`, `docs/**/*adr*.md`, `docs/architecture/` — named files,
  never the whole `docs/` tree); (2) an `import-linter` `layers` contract, the one contract type that *is* an
  ordering; (3) conventional directory names from the fixed inner / middle / edge vocabulary in each reference's
  "Layer map" section — requiring two or more tiers present as **sibling directories under one parent** (`src/domain`
  and `src/infra`) and no name used in two tiers. `service`, `services`, `api`, `app`, and `models` are deliberately
  absent: `service/` names a microservice as often as a middle tier, `api/` holds domain contracts as often as
  transport, `app/` is Next.js's router, `models/` is generic. Recorded as `Layer map: {source} — {mapping}`. Tiers
  annotate nodes by directory, so two files of one workspace package can carry different tiers. The map is never
  guessed from the graph.
- **Boundary source** — what a Dependency Direction Violations or External Type Leaks finding needs before it exists:
  either the layer map (an ordering violated) or an **explicit prohibition** naming the edge or the external — an
  `import-linter` `forbidden` / `independence` contract, a dependency-cruiser `forbidden` rule, an Nx
  module-boundary constraint, a go-arch-lint `mayDependOn` set that excludes the target, a repository instruction.
  **No boundary source → both categories are withdrawn** with a Scope line. A prohibition is evidence for the edge it
  names; it never becomes a tier for any other edge.
- **Policy** — an explicit dependency rule the repository already states: instructions, or a contract configuration
  (`.dependency-cruiser.{js,cjs,mjs,json}`, `dependency-cruiser.config.*`, `eslint-plugin-boundaries` and Nx
  `@nx/enforce-module-boundaries` tags, `[tool.importlinter]` / `.importlinter` contracts of every type,
  `.go-arch-lint.yml`). Policy is evaluated on edges, not turned into tiers: an edge a contract **explicitly permits**
  is withdrawn with a `Policy:` line; an edge a contract **explicitly forbids** is a Dependency Direction Violations
  finding with the rule as its boundary source; an edge no rule mentions is neither permitted nor forbidden. An edge
  instructions forbid and a configuration permits is a finding whose Evidence names the conflict; instructions
  outrank configuration.
- **Inward** — toward the layer map's inner tier. Edge layers *are* the wrapping layer; external types in their own
  signatures are not leaks.
- **External type** — a type whose shape the project does not own. First-party is the whole workspace (every
  repository module, workspace package, and declared package — per-language sets in each reference's "External types"
  section). External is outside that set — third-party and framework packages — **and, as this skill's stated
  policy, code generated from a schema whether or not the project owns the schema** (`.pb.go`, `_pb2`, OpenAPI and
  GraphQL clients, the Prisma client, ORM models). This is an opinion the skill enforces, not a technical fact: a
  generated declaration can be a plain record of the project's own canonical schema, and the policy costs a mirror, a
  mapper, and their upkeep. The skill takes it because the *generator*, not the project, controls the representation —
  wire enums, getters, nullability, optional semantics — and a repository that wants its generated types in the domain
  says so once in instructions (`Policy:`). Not external: the standard library, as each reference defines it.
  Generated files are ineligible for findings and read as context.
- **Mirror and mapper** — a hand-written declaration parallel to an external type, and the function converting between
  them. **The mirror is never a finding here.** The finding is the **crossing**: the external type used inward beside
  the mirror, or a mapper whose output still carries external types or external enum values *when the mapper's output
  is an inward type*. A complete mapper is the remedy working. A field-for-field clone in the *same* layer as the
  external is nobody's finding, by design.
- **Edge** — one import statement from node A to node B, at `file:line`. Cycles, direction violations, and deep
  imports are judged per edge; one finding per edge (see Within-skill precedence).
- **Rewrite test** — the Leaked Internals evidence bar: would a reimplementation of the unit from its *promised
  behavior* alone keep this exported member? Members that usually fail: a cache map, a mutex, a DB row struct, a
  state-machine field, an intermediate representation. The test is about the unit's promise, not the member's kind — a
  parser library whose documented product is its AST passes with that AST; a domain type, a result, an option struct
  pass. The Exposed member cell states the reason; a member whose reason cannot be stated is not a finding.
- **Runtime cycle** — a cycle that still exists after every erased edge is removed from the graph. A cycle that
  disappears when erased edges are removed is **type-only**, even when some of its edges are runtime imports: `A → B`
  runtime plus `B → A` type-only is not a runtime cycle, because after erasure nothing points back. Kind is a property
  of the cycle, never of a single edge.
- **Provable failure** — a runtime cycle's Failure value decided by reading: module `b` has, at module level, a read
  of a binding from cycle partner `a` — `from a import X`, `a.X`, or a call at module level into a function whose body
  reads `a.X` (one hop) — and `a` defines `X` *after* the statement that imports `b`. From the entry that starts at
  `a`, `b` runs while `a` is partially initialized and the read fails (`ImportError` / `AttributeError`; TypeScript
  ESM: a TDZ `ReferenceError` on a `const` or `class` binding). Recorded `provable from {entry}: {site}`. Reads inside
  functions never called at module level are not traced. No interpreter and no bundler runs.
- **Production entry** — an import order production actually uses: the entry module named by `[project.scripts]`,
  `__main__.py`, `manage.py` / `wsgi.py`, a `package.json` `main` / `bin`, a framework's module discovery order, or a
  package `__init__` whose import sequence fixes which partner loads first. A provable failure from a production entry
  is failing today; from any other entry it is order-sensitive and working by luck.
- **Form** — a labelled variant inside one category, carried in the report's Form cell: Dead Exports `zero consumers`
  / `package-local only` (Go) / `test only` / `consolidated barrel` (Python, TypeScript); Deep Imports `crossing` /
  `exposure` (Go); Cyclic Dependencies `runtime` / `type-only`; External Type Leaks `signature` / `re-export` /
  `mapper output`; Generic Boundary Names `generic name` / `clause ≠ directory` (Go). Dependency Direction Violations
  has one form and no Form cell; its Basis cell says whether the map or a prohibition is the boundary source.

## Not a finding on these grounds alone

Conditionals, not category exemptions — each states what does **not** justify a finding and, where one exists, what
would:

- **A concrete type imported across a boundary.** Never a finding. *Is* Dependency Direction Violations when the edge
  points outward against the layer map or a prohibition names it, whatever the type's kind.
- **An external type in an edge-layer unit's own signature, re-export, or conversion** (handler, adapter, repository
  implementation, UI component). The wrapping layer. *Is* External Type Leaks when the same type appears in an inward
  unit's exported API.
- **An external type in any unit's API when no boundary source exists.** Withdrawn, all three forms: without a tier or
  a prohibition the skill cannot tell an adapter from a domain.
- **A standard-library type anywhere** (`context.Context`, `time.Time`, `pathlib.Path`, `Date`, Node builtins with or
  without `node:`, `@types/node`, TypeScript `lib.*` types).
- **A type from another first-party workspace module** (a `go.work` member, a `workspace:*` package, a package the
  repository's `pyproject` declares). Owned; never an external type. *Is* Dependency Direction Violations when the
  edge points outward.
- **A hand-written mirror of a generated / ORM / SDK type with a complete mapper.** The remedy working. *Is* External
  Type Leaks when the external type is used inward beside the mirror, or when the mapper's output still carries
  external types or enum values. A field-for-field clone in the same layer as the external is nobody's finding.
- **An owned type or interface declared in an inward unit, implemented at the edge, and received from the composition
  root.** The External Type Leaks remedy, and a live seam under simplicity-hunter's and solid-hunter's existing
  definitions. *Is* simplicity-hunter's Unnecessary Abstractions when the inward unit constructs the wrapper itself
  and no external type was kept out.
- **A TypeScript or Python `export` consumed only by sibling files inside the unit.** The keyword is how files share.
  *Is* Dead Exports in Go, where the analogue — an exported identifier used only package-locally — has a cheaper form:
  unexport.
- **A Go struct field, or a method with a reflection-protocol name.** `encoding` and `fmt` reach them without an
  import; the set cannot be closed. Never Dead Exports. An interface-named method (`Close`, `Read`, `ServeHTTP`) is
  *not* covered by this bullet: it is a candidate unless a site uses the type as that interface.
- **An export referenced only by string** (entry point, settings, template, registry). The string is the consumer; the
  Consumers cell names it.
- **An open (published) unit's export with zero in-tree consumers.** Withdrawn with a `Limitation` line, never
  reported as "unused internally".
- **A generated file's export.** Generated files are ineligible; their types are the external types the leak category
  judges.
- **An import deferred inside a function.** Nomination only; by itself it neither proves nor excludes an
  initialization hazard — a function called at module level runs during init.
- **A deep import in a test file**, and any test-file edge. Test files are out of scope, not exempt.
- **An import from a TypeScript directory with no barrel, no `exports`, and no unit-named alias**, an import through a
  root wildcard alias (`@/…`), or an import of a Go sub-package of a package that is itself the entry. No deep import
  exists where every file is the entry. Python differs: a `_module` or an `internal` package is deep whatever the
  `__init__` says.
- **A Go package clause differing from its directory** for `package main`, `_test` packages, `/vN` major-version
  directories, and hyphenated directories whose clause drops the hyphen or a `go-` prefix.
- **A generic-named unit with one capability** (`strutil` holding string helpers; `errors` holding error types). *Is*
  Generic Boundary Names when two or more unrelated capabilities are enumerated under the generic name.
- **A generic-named file** (`utils.ts`, `helpers.py`), whatever it holds. smell-hunter's God Module.
- **A Dependency Direction Violations edge a contract configuration explicitly permits**, or repository instructions
  sanction. The `Policy:` line withdraws it. An edge no rule mentions is not permitted by silence.
- **Fan-in or fan-out counts alone.** A hub is a hub. Counts nominate and set Impact; they never decide a finding.
- **An inward unit's private (unexported) use of an external type.** Not External Type Leaks, which judges the
  exported API. A known non-owner.

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Deep Imports"). Fan-in, fan-out, and
occurrence counts nominate and set Impact; they never decide a finding.

### Dead Exports

An export with no external consumer.

**Signals** — every one of them *nominates*; none is a threshold:

- An exported function, type, or constant with zero import sites outside its unit
- An exported constructor for a type nothing outside the unit uses
- A barrel or `__init__` re-export no external module imports
- `export * from './internal'`, `from .impl import *`
- An exported symbol imported only by test files

**Evidence bar:** enumerate consumers project-wide **by reading, not by regex alone** — Go methods and grouped
`const (…)` / `var (…)` blocks defeat line-anchored patterns; TypeScript default, namespace, and aliased imports and
Python `import *` defeat name grep. Search string references (entry points, settings, registries, templates) and mark
them as consumers. Mark test-file consumers `test only`. Struct fields and reflection-protocol methods are never
candidates; an interface-named method is a candidate only when no site uses the type as that interface. Confirm the
unit is closed, else withdraw with a `Limitation` line. Go form: an exported identifier used only inside its own
package. Python and TypeScript consolidated form: a wildcard re-export exposing N dead symbols is **one** row with a
representative symbol and `Occurrences: N`; a consumed member the rewrite test fails (Python: a `_name` the
submodule's `__all__` lists, the only way `import *` carries one) gets its own Leaked Internals row.

**Action:** unexport; remove from `__all__`; replace the wildcard with named re-exports of the public API. Test-only:
the export exists for the test alone, and the Action names the public behavior the test should assert after
unexporting — **never** "make it an internal test". After unexporting, a symbol with no callers at all becomes
simplicity-hunter's next audit — sequential, not double.

**Ownership:** an *exported* symbol with no external consumer is here. An unused *unexported* function or constant,
and a Python non-`__all__` name with no importers anywhere, are simplicity-hunter's Dead Code Paths; unused imports
and bindings are slop-hunter's Trivially Dead Code. A TypeScript `export` in a non-entry file that the entry does not
re-export, with zero importers anywhere, is simplicity-hunter's Dead Code Paths — the analogue of the Python rule. A
member exposed but untouched by any consumer is this category at member granularity, Low; a member a consumer touches
is Leaked Internals.

### Leaked Internals

A consumed export exposing *how* the unit works, not *what* it provides.

**Signals:**

- An exported type with implementation-specific fields — caches, memoization keys, AST nodes, mutexes
- A type whose structure reveals how the unit works rather than what it produces
- A consumer that makes decisions on the imported unit's internal state
- Python: an `__init__.py` re-exporting a `_name`

**Evidence bar:** the exposed member fails the **rewrite test** with the reason stated, **and** at least one external
consumer reads it (Medium) or mutates it (High), named `file:line`. Python judges any consumed non-underscore name,
whatever `__all__` says; for an `__init__.py` re-exporting a `_name`, the stated reason is
`marked private by its own _ prefix`, and no further rewrite test applies. Exposed but untouched → Dead Exports at
member granularity, Low. Reported in open (published) units too — the consumer is in the tree.

**Action:** unexport the member; expose the behavior it served through a method or an owned type. The consumer's
dependence is the reason, cited.

**Ownership:** this category judges the *producer's surface*; smell-hunter's Feature Envy judges the *consumer's
placement*. A consumer reaching an exported member that fails the rewrite test is one finding here, anchored at the
export; members that pass the rewrite test leave the placement question to smell-hunter. An exported struct
*embedding* `sync.Mutex` promotes `Lock` / `Unlock` — type-hunter's Embedding Antipatterns judges that promoted method
set; an exported mutex *field* (`Mu sync.Mutex`) read or locked by an external consumer is here.

### Deep Imports

A consumer reaching past the unit's public entry.

**Signals:**

- `from package._internal import x`, `package.internal.helper`
- `module/internal/helper` bypassing the barrel; `@org/pkg/src/internal/x` bypassing `exports`
- A deep path through a unit-named alias
- Go: a reached implementation sub-package (`service/impl/`, `handler/private/`)
- Go: a sub-package used only by its parent or the parent's siblings (exposure form)

**Evidence bar:** *crossing* form — the consumer's import line, the entry it bypassed (barrel, `exports`, the
`__init__` surface, a unit-named alias, the parent Go package) or the private path reached (`pkg._x`,
`pkg.internal.x`), and the symbol reached. An import through a root wildcard alias bypasses nothing. *Exposure* form
(Go, any module, Low) — a sub-package consumed only by its parent or the parent's siblings, importable from the rest
of the module because it is not under `internal/`, with no outside importer yet. `internal/` restricts import to the
tree rooted at its parent, so in-module packages are exactly what it protects against.

**Action:** import from the entry; expose the needed symbol there. Enforcement vocabulary per language: Go
`internal/`; TypeScript `package.json` `exports`, or a unit-named alias; Python has none — convention and
`import-linter` contracts. Exposure form: move the sub-package under the `internal/` of the nearest common parent of
all its importers.

**Ownership:** unshared. A deep import that is also an outward edge under a boundary source is Dependency Direction
Violations by precedence, with the deep import named in Evidence.

### Dependency Direction Violations

A module edge pointing outward against the layer map, or an edge an explicit prohibition names.

**Signals:**

- A domain unit importing infrastructure, transport, or UI
- A model or entity package importing a handler or controller package
- A `core` package depending on a `feature` package
- An edge a linter contract forbids

**Evidence bar:** the edge at `file:line`; its **Basis** — both endpoints' tiers per the recorded layer map with the
map's source, **or** the prohibition (contract type, file, rule) that names this edge; and that no policy permits it.
Judged on **module edges**, so `src/domain/a.ts → src/infra/b.ts` inside one workspace package is a finding. A
type-only cycle edge crossing layers inward is reported here with the cycle named. **Withdrawn without a boundary
source.**

**Action:** stop the outward import — move the type to the unit that owns it (the Action when the outward import
fetches a domain type defined in an edge unit); pass the value in from the composition root; and only where the
language cannot otherwise break the import (Go, typically) define the interface *in the inward unit* and implement it
at the edge. **Never "define an interface" as the default remedy.**

**Ownership:** solid-hunter's Concrete Dependency Chains is type-level wiring — self-instantiation, a module-level
singleton read; import direction between layers is here, and the last-resort interface is declared in the inward unit,
which is solid-hunter's own DIP shape. smell-hunter routes dependency direction here from Shotgun Surgery.

### Cyclic Dependencies *(Python, TypeScript)*

Two or more modules importing each other, directly or transitively, on the module graph.

**Signals:**

- A → B → A; A → B → C → A
- A barrel or `__init__` that closes a cycle by re-exporting
- A circular-reference error at runtime or from a bundler
- An import deferred inside a function

**Evidence bar:** the cycle path; **Kind** — `runtime` when the cycle survives removal of every erased edge,
`type-only` when it does not; **Failure** — `provable from {entry}: {site}` (see Terms), `observed: {log or test}` (a
cited existing output), or `none observed`. Deferred imports inside functions are a nomination signal only: they
neither prove nor exclude an init hazard. Same-layer type-only cycles are Low, with no "explicitly justified" concept;
cross-layer type-only edges route to Dependency Direction Violations.

**Action:** extract the shared concept into a third module, or invert the edge. A provable cycle's Action names the
entry and the statement that fails.

**Ownership:** unshared. A provable or observed `ImportError` is reported here at Critical with the failing site; no
error hunter scores it.

### External Type Leaks

An external type crossing inward.

**Signals:**

- `gin.Context`, `echo.Context`, `django.http.HttpRequest`, `flask.Request`, `sqlalchemy.Session`, `Express.Request`,
  `pgx.Tx` in an inward signature
- A unit re-exporting a third-party type as its own API
- Switching the library would require changing inward consumers

**Evidence bar:** a **boundary source** for the unit whose API carries the type — its tier per the layer map, or a
prohibition naming that external for that unit's path. `signature` form: an inward unit's exported signature carries
the external type. `re-export` form: an inward unit re-exports or aliases an external type as its own API (`type User
= pb.User`, `export type { User } from '@prisma/client'`). `mapper output` form: a conversion into an inward type
whose result still carries the external type or its enum values. Edge-layer units using, re-exporting, or converting
between external types are the wrapping layer and never a finding — which is why no form runs without a boundary
source. A mirror is never a finding; the crossing beside it is. **Exported API only:** an inward unit's private use of
an external is not this category.

**Action:** first ask whether the external concept belongs in the inward signature at all — transaction plumbing
usually does not. If it does: an owned type or interface **declared in the inward unit**, implemented and converted at
the edge, injected from the composition root, so the edge unit becomes the only importer of the external.

**Ownership:** the resulting seam is live under simplicity-hunter's existing Not-a-finding (an abstraction serving as
a test seam or DI boundary while an injector actually uses it) and solid-hunter's seam definition (a production
consumer receives it from outside); it is not a new exemption. What stays simplicity-hunter's Unnecessary
Abstractions: a wrapper the inward unit constructs itself, with no external type kept out. A hand-written mirror of a
generated / ORM / SDK type is never duplication for type-hunter and never a leak here; only the crossing beside it is.
A type-system bypass with a reason in a boundary layer is invariant-hunter's, content validation at a trust boundary
is security-hunter's, and whether the external *type* crosses inward is here — different questions on adjacent sites.

### Generic Boundary Names

A package or directory unit named for what it contains, not what it provides.

**Signals:**

- A unit named `util`, `utils`, `common`, `helpers`, `shared`, `misc`, `base`, `models`, `types`, `lib`
- A Go package clause that does not match its directory
- A `models` package holding types for unrelated domains

**Evidence bar:** *generic name* form — the unit's name is in the generic list **and** its exports span two or more
unrelated capabilities, enumerated. One capability under a generic-ish name (`strutil` with string helpers only) is
not a finding. Never a file. Go *clause ≠ directory* form — the package clause differs from the directory name,
excluding `main`, `_test` packages, major-version directories (`/v2`), and hyphenated directories (`go-foo` → `foo`).

**Action:** name the unit after the capability; split by capability where two or more were enumerated.

**Ownership:** the *file* unit is smell-hunter's God Module in Python and TypeScript (`utils.ts`, `helpers.py`), and so
is file placement inside a unit; in Go a file and its placement are nobody's — smell-hunter marks God Module n/a for
Go. The *name* of a package or module directory is here. Responsibility and change analysis
of a package — named actors, independent reasons to change, "multiple files spanning unrelated concerns" — is
solid-hunter's Responsibility Sprawl, including the split's design.

### Within-skill precedence

Per import edge: a Cyclic Dependencies finding whose Failure is `provable` or `observed` > Dependency Direction
Violations > Cyclic Dependencies with Failure `none observed` > Deep Imports. Per exported member: a member failing
the rewrite test with a consumer touching it is Leaked Internals; exposed but untouched is Dead Exports at member
granularity. The reported finding's Evidence cell names the other readings in one clause, or its Action cell where
the table has no Evidence column.

## Applicability

Seven categories are universal in definition; each language reference declares them applicable or not, with the
reason. **A language with no reference is not supported** — its files are excluded, never implicitly audited.

| Category | Go | Python | TypeScript |
| -------- | -- | ------ | ---------- |
| Dead Exports | yes — adds the `package-local only` form | yes — `__all__` and `__init__` re-exports only | yes — `export` at the unit's entry |
| Leaked Internals | yes | yes — adds an `__init__` re-exporting a `_name` | yes |
| Deep Imports | yes — adds the `exposure` form | yes — no enforcement mechanism | yes |
| Dependency Direction Violations | yes — package edges | yes — module edges | yes — file edges |
| Cyclic Dependencies | **n/a** — the compiler rejects import cycles | yes | yes |
| External Type Leaks | yes | yes | yes |
| Generic Boundary Names | yes — adds the `clause ≠ directory` form | yes | yes — never a file |

There are no language-only categories: Go's extra forms live inside universal categories.

## Test-code scope

**Test files are excluded from findings.**
Paths per language: Go `*_test.go`; Python `test_*.py`, `*_test.py`, `tests/`, `conftest.py`; TypeScript `*.test.*`,
`*.spec.*`, `*.e2e.*`, `__tests__/`. The exclusion is **by path**.

Test files are **read as context**:

- A test-file import of an export is recorded in the Consumers cell as `test only: {file}` and never counts as an
  external consumer. The resulting Dead Exports finding is Low, and its Action names the public behavior the test
  should assert once the member is unexported. The Action never recommends converting to a white-box test: this
  skill's identity is that the public API suffices, and `package foo_test` is that API's consumer, only a test one.
- Test-file deep imports and test-file edges are never findings and never close a reported cycle.

Test evidence never raises Severity. Anchor the finding at the production declaration or edge.

**Recorded gap:** Fowler's Message Chains (the Law of Demeter) has no owner in the unified suite. At
the boundary the defect is already judged — a return exposing a third unit's internal type is Leaked Internals at the
export, a return of another unit's public type is legitimate dependency — but chains inside object design are neither.
smell-hunter is the candidate.

## Severity and Impact

Every finding carries **both**, per the sibling definitions. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is:**

- **Critical** — one form only: a runtime Cyclic Dependencies finding whose Failure is `provable` **from a production
  entry**, or `observed` (a cited existing log or test output). The Failure cell names the entry and the failing
  statement. Nothing else reaches Critical, and nothing is executed to get there.
- **High** — a runtime cycle whose Failure is `provable` from an entry not shown to be a production entry
  (order-sensitive: it works today because production happens to load the partner first, and Evidence names that
  order); a Dependency Direction Violations edge from the inner tier outward, or one an explicit prohibition names; an
  External Type Leak in an inner-tier API; a Leaked Internals member an external consumer mutates.
- **Medium** — the default for a finding that clears its bar: dead exports with zero consumers, leaked internals a
  consumer reads, deep imports (crossing form), a runtime cycle with no module-level read of a partner binding
  (structural coupling in any import order — the position of the imports, module-level or deferred, plays no part),
  external type leaks in the middle tier.
- **Low** — generic boundary names, `clause ≠ directory`, the Go exposure form, test-only exports, same-layer
  type-only cycles, a dead export at member granularity, a consolidated barrel row whose symbols are all unconsumed.

A candidate that fails its evidence bar or matches a Not-a-finding conditional produces **no finding at any severity**.
Severity is never a confidence scale: a consumer set that could not be closed, a tier that could not be assigned, a
publication status left mixed, a cycle Kind that depends on an emit setting that could not be read — **withdrawn** with
a `Limitation` line, never downgraded. When precedence consolidates two readings of one edge, the strongest
demonstrated consequence sets Severity; that is why a provable cycle outranks a direction violation.

**Impact — how much the change is worth:** contextual; the affected unit's fan-in is the primary evidence, cited in
the Evidence cell, or in the Action cell where the table has none. A leak in a unit thirty units import is High
impact at Medium severity; a dead export in a leaf is Low.

- **High** — substantial reduction on a unit imported or changed often
- **Medium** — clear improvement on a moderately reached unit
- **Low** — clears the evidence bar but touches a leaf or a rarely changed unit

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

   **Supported languages are Go, Python, and TypeScript.** Every other extension is **excluded, not audited**:
   without a reference there is no unit definition, no entry rule, no export vocabulary, no eligibility rule.
   JavaScript (`.js`, `.jsx`, `.mjs`, `.cjs`) is the one extension that is still **read into the import graph** —
   its ESM `import` and CJS `require` edges keep a mixed repository's graph correct — but a `.js` file is never a
   finding anchor. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming each extension, and
   note the JavaScript graph inclusion.

3. **Load language references.** For every detected language, read `references/boundary-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/boundary-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**; do not continue with the universal categories only.

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
   there. The import graph, consumers, tiers, and publication evidence are *read* as **context** wherever they live:
   a unit's consumers, a cycle's partner, and a layer's other side routinely sit outside any diff. Diff and path
   scope narrow the manifest, never the context reading. A finding anchors at the export declaration, the consumer's
   import line, the leaking signature, or the package clause. A cycle has no privileged edge; it anchors at any
   eligible in-scope edge of the cycle, the first in sorted path order when several qualify.

5. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) and the named ADR paths for the
   **layer map**, **explicit prohibitions**, and **policy**: a stated layering, a sanctioned coupling, a generated
   type the project deliberately puts in its domain, a package documented as published. Then read the contract
   configurations each reference names. Record `Layer map: {source} — {mapping}` or `Layer map: none`,
   `Prohibitions: {source files}` or `Prohibitions: none`, and any `Policy:` lines. **With neither a map nor a
   prohibition, Dependency Direction Violations and External Type Leaks are not evaluated** — record the Scope line
   and judge the other five categories. This step precedes the toolchain so no command runs against the project's
   own instructions.

6. **Record the toolchain — present-only, never installed.** Run each loaded reference's Toolchain section and write
   one `Toolchain:` line per tool with the exact invocation. Four outcomes per tool: **ran** (command, version,
   coverage), **skipped — not installed**, **skipped — not configured**, **errored**. Nothing is installed, no
   configuration is written into the project, and no tool output is a finding — every tool here is a nominator.

7. **Read the emit settings** when TypeScript is in scope, per the TypeScript reference's "Emit and erasure" section,
   and record the `Emit:` line. Where the emit pipeline cannot be established, cycle Kind is withdrawn per candidate
   with a `Limitation` line, never guessed.

### Phase 2: Build the Import Graph

Project-wide, whatever the scope. One file-level graph, each edge tagged **erased** or **runtime** per the language
reference: Go from `go list` (or the import scan on failure); Python and TypeScript from import scans, with the
present graph tool as a nominator and cross-check. Graph scans run on `.` — never on the step-4 lists — and keep
generated files, which are context and can be consumers. Annotate nodes with their boundary unit and, where a layer
map exists, their tier. Record `Graph: {N nodes, M edges, E erased, U units} from {source}` in Scope. JavaScript files are
nodes; they carry no unit annotation and anchor nothing.

### Phase 3: Scan and Nominate

Scans produce **candidates only**. For each loaded reference, run its Phase 3 scan block against that language's
step-4 list (`<run>/go.txt`, `python.txt`, `typescript.txt`, restored as `$GO_FILES`, `$PY_FILES`, `$TS_FILES`;
the single path `.` in codebase mode). Pass an explicit path to **every** `rg` invocation. Diff mode nominates
from the working tree over the manifest files, not from added lines: a boundary is a property of the current code.

### Phase 4: Enumerate

For each nominated candidate, project-wide:

- **Exports**: every consumer — imports read, not grepped; string references searched; test-file consumers marked
  `test only`; Go package-local uses counted; the interface-named-method search for a use-as-interface site.
- **Units**: the unit's public entry, and its **publication** per the Published-unit rule, with the signals read.
- **Edges**: both endpoints' tiers from the recorded map, or the prohibition that names the edge; any policy that
  permits it.
- **Cycles**: every edge of the cycle classified erased or runtime; the Kind; the module-level partner reads and the
  definition order that make a failure provable; the entry, and whether it is a production entry.
- **Externals**: whether the specifier is first-party, stdlib, or external; whether the carrying declaration is in the
  unit's *exported* API; the mirror and the mapper where one exists.

Record in Scope an `Enumeration:` line whenever consumers were found by reading rather than by scan, stating what was
searched and how the set was closed. A set that cannot be closed **withdraws** the finding with a `Limitation` line.
Findings claim the enumerated set only.

### Phase 5: Evaluate Each Finding

For each candidate: apply **Not-a-finding** first; confirm the category applies in that file's language (see
Applicability); apply the ownership tests — the export definition per language, the rewrite test, the publication
rule, the boundary-source rule, the mirror answer — and within-skill precedence; then clear the category's evidence
bar from What to Hunt. Check policy: a `Policy:` line withdraws what it names. Run each loaded reference's Phase 5
block for its language-specific judgment.

Assign **Severity and Impact** to every finding (both required; they diverge). One finding per edge and per exported
member. Nothing is held back; `Audit completed: N findings` counts every reported finding.

**The zero-findings line is reached only when no category has a candidate** — no export, no module-graph cycle, no
module edge between different tiers or named by a prohibition, no deep import, no external type in an exported
signature, no generic-named unit. It is never keyed on cross-unit edges: two files inside one barrel directory
importing each other are a cycle candidate although the projection onto units shows no edge at all.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-boundary-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "`domain/` importing `infra/` — obvious violation" | Where is the layer map recorded? Instructions, an `import-linter` `layers` contract, or sibling directories from the fixed vocabulary. No boundary source, no finding. |
| "The directory is called `service/`, so it is the application tier" | `service`, `api`, `app`, `models` are not vocabulary. They name a microservice, a contracts package, a router, and everything. |
| "The linter config lists these tags, so that is the layering" | A contract permits or forbids *edges*. A `forbidden` rule is evidence for the edge it names; it never becomes a tier for any other edge. |
| "No rule mentions this edge, so the project allows it" | Silence is not permission. Judge it against the map; `Policy:` needs an explicit permission. |
| "`grep` found no importers — dead export" | Default, namespace, and aliased TypeScript imports, Python `import *`, Go grouped `const (…)` blocks and methods all defeat name grep. Enumerate by reading, and search string references too. |
| "It is exported and nothing in the repo uses it" | Is the unit closed? A published library's export withdraws with a `Limitation` — never "unused internally". |
| "`Close()` has no callers — dead export" | Is the type ever used *as* `io.Closer` — assigned, converted, passed, returned, stored? Then no finding. Name matching alone abstains from nothing. |
| "`MarshalJSON` has no callers" | A reflection protocol. `encoding/json` reaches it without an import; never a candidate. |
| "The exported struct field is unused" | Struct fields are never Dead Exports. Reflection reaches them and the set cannot be closed. |
| "The barrel re-exports twelve dead symbols — twelve findings" | One consolidated row with a representative symbol and `Occurrences: 12`. A consumed `_name` among them gets its own Leaked Internals row. |
| "The export leaks a cache — Leaked Internals" | Does a consumer *touch* it? Exposed but untouched is Dead Exports at member granularity, Low. |
| "A cache field is always implementation" | State the rewrite-test reason against the unit's *promise*. A parser whose product is its AST keeps the AST. No reason statable, no finding. |
| "One edge is a value import, so the cycle is runtime" | Kind is a property of the cycle: does it survive removal of every erased edge? `A → B` runtime plus `B → A` type-only does not. |
| "A cycle with deferred imports is safer" | Import placement decides nothing. A function called at module level runs during init. Medium either way unless a read is provable. |
| "The cycle will blow up at import time" | Provable means a module-level read of a partner binding defined *after* the partner's own import, from a named entry. Otherwise `none observed`. |
| "I'll run `python -c 'import a'` to confirm" | No project code is executed. The failure is read, or cited from an existing log. |
| "The cycle is Critical" | Only from a **production** entry, or with an observed log. From another entry it is High, with the order production uses named. |
| "`@/utils/internal/x` bypasses the barrel" | `@/*` → `src/*` is a root wildcard: a prefix, not an entry. Nothing is deep relative to it. |
| "The domain mirrors the Prisma model — leak" | The mirror is never a finding. The crossing is: the external used inward beside it, or a mapper output still carrying it. |
| "`.proto` is ours, so `pb.User` is first-party" | Stated policy: generated code is external whoever owns the schema. A `Policy:` sentence in instructions opts out. |
| "`React.FC` in a component — external leak" | Components are the edge tier. The wrapping layer's own signatures are never leaks. |
| "Define an interface so the domain does not import the adapter" | Not the default remedy. Move the type to its owner, or inject from the composition root. An interface only where the language leaves no other break — and it is declared in the *inward* unit. |
| "`pkg/utils` is a generic name" | Enumerate two or more unrelated capabilities. One capability under a generic-ish name is no finding. |
| "The 700-line `utils.ts` is a generic boundary name" | A file is never a boundary unit. smell-hunter's God Module. |
| "The package spans persistence, HTTP, and pricing" | solid-hunter's Responsibility Sprawl. This skill judges the *name*, not the responsibilities. |
| "The consumer walks `a.b.c.d` across a boundary" | Message Chains has no owner in this suite; recorded as a gap. Only an exposed internal *type* is a finding here. |
| "I'm not sure the tier is right, so I'll report it Low" | Severity is not confidence. Withdraw it with a `Limitation` line. |
| "The report looks thin — I'll list what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "I'll `npm i -D dependency-cruiser` first" | Nothing is installed. Absent tool: `skipped — not installed`, and the graph is read. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do the universal categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** Audit report only. Implementation is a separate step.
- **The report is the template.** `references/report-format.md` fixes the shape: Scope, then one section per
  category with at least one finding, then Recommendations. A category with no findings gets no heading, table,
  or "none found" line.
- **Scope: boundary cleanliness only.** A finding that doesn't answer "is this unit a black box, replaceable from its
  public entry?" belongs to another hunter. Contested boundaries are resolved at the category that owns them: each
  **Ownership:** note in What to Hunt states what is kept here and what routes away.
- **Evidence required.** Every finding cites `file:line` (path form per the language reference) with the exact
  declaration, import statement, or signature, and the category's evidence cells — Consumers, Exposed member, Public
  entry, Basis, Kind and Failure, Form and boundary source, Capabilities — are filled, never inferred.
- **One finding per edge and per member.** When two categories describe the same edge or the same exported member,
  within-skill precedence picks the primary one and the Evidence cell (else the Action cell) names the other reading.
- **Never install; never execute project code.** Tools are used only when the project already has them. No cycle is
  reproduced by importing a module, no bundler is run to establish emit, no scratch prefix is created.
- **Boundary sources are read, never guessed.** No tier is inferred from the graph, from fan-in, from who imports an
  external, or from a directory name outside the fixed vocabulary. With no map and no prohibition, both dependent
  categories are withdrawn with a Scope line.
- **Documented coupling is `Policy:`.** A coupling the repository states as intentional is acknowledged and
  withdrawn, not reported; a conflict between instructions and a configuration is reported with the conflict named,
  instructions outranking configuration.
- **Handoff, not duplication.** When a candidate belongs to another hunter — an unexported dead function, a
  generic-named file, a package spanning responsibilities, a mirror with a complete mapper — cross-reference it and
  do not score it here.
- **Respect the language.** Calibrate to the audited language's enforcement mechanisms; the reference carries the
  calibration. Never recommend `internal/` in Python, a barrel in Go, or a cycle remedy for a language whose compiler
  already rejects cycles.
