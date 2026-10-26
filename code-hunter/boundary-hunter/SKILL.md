---
name: boundary-hunter
description: Audit Go, Python, or TypeScript code for boundary violations — dead exports, leaked internals, deep imports, dependency direction violations, import cycles, external type leaks, generic boundary names. Defaults to the codebase.
disable-model-invocation: true
---

# Boundary Hunter

Audit code for **boundary violations** — an exported helper no other unit imports, a cache map a consumer ranges
over, an import reaching past a barrel into `internal/`, a domain module importing the Postgres adapter, two modules
importing each other until initialization order decides whether the process starts, `pgx.Tx` in a domain signature, a
`utils` package holding three unrelated capabilities. Goal: **every unit is a black box, replaceable from its public
entry alone.**

**Not covered (owned by other hunters):** unused non-exported functions, constants, and branches, and any Python
public name with no importers at all (→ simplicity-hunter Dead Code Paths); unused imports and bindings
(→ slop-hunter); a generic-named *file* and file placement inside a unit (→ smell-hunter God Module in Python and
TypeScript; in Go nobody's); package-level responsibility and change analysis — named actors, independent reasons to
change (→ solid-hunter Responsibility Sprawl); type-level wiring, self-instantiation, and module-level singleton reads
(→ solid-hunter Concrete Dependency Chains); two hand-written declarations of one shape with a consolidation path
(→ type-hunter Duplicated Type Declarations); a promoted method set from an embed (→ type-hunter Embedding
Antipatterns); type-system bypasses at a boundary layer (→ invariant-hunter); content validation at a trust boundary
(→ security-hunter); message chains inside object design (no hunter owns them). Where ownership is *contested*, the
category's **Ownership:** note in What to Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `security-hunter-go`, `security-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical. *(conditional)*
marks a category that is n/a in some language; each language reference's Applicability table says where and why.

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Dead Exports | An export with no external consumer | Unexport; drop from `__all__`; replace the wildcard with named re-exports |
| Leaked Internals | A consumed export exposing *how* the unit works | Unexport the member; expose the behavior through a method or an owned type |
| Deep Imports | A consumer reaching past the unit's public entry | Import from the entry; expose the symbol there; `internal/` or `exports` to enforce |
| Dependency Direction Violations | A module edge pointing outward against the layer map, or an edge an explicit prohibition names | Move the type to its owner; inject from the composition root; invert only where the language leaves no other break |
| Cyclic Dependencies *(conditional)* | Two or more modules importing each other, directly or transitively | Extract the shared concept into a third module, or invert the edge |
| External Type Leaks | An external type crossing inward | An owned type or interface declared in the inward unit, implemented and converted at the edge |
| Generic Boundary Names | A package or directory unit named for what it contains, not what it provides | Name after the capability; split by capability |

## Core Principles

1. **Scans and counts nominate; reading decides.** `rg 'export \*'`, `go list`, `depcruise --output-type json`, and
   every other tool find candidates; fan-in, fan-out, and occurrence counts nominate and set Impact. Nothing is a
   finding until the consumers have been enumerated by reading, the tier has been read from a recorded source, the
   cycle's edges have been classified, and the rewrite test has been answered in words.

2. **Interfaces at two sites only.** The skill asks for an interface only when it is declared in an inward unit to
   keep an external type at the edge, or as the last-resort inversion where the language leaves no other way to break
   an outward import. A concrete type imported across a boundary is fine; the edge is Dependency Direction Violations
   only when it points outward against the layer map or a prohibition names it.

3. **Respect the language.** Calibrate every remedy to the language's own enforcement: Go `internal/`; TypeScript
   `exports` or a unit-named alias; Python convention and `import-linter` contracts. The loaded reference carries the
   calibration.

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
- **Boundary unit**, **public entry**, **export** — the construct whose exports form an API and whose imports form
  edges; the path a consumer is meant to import from; the members the unit offers outside itself. Each language
  defines all three, and the members that are never Dead Exports candidates, in its reference's "Boundary unit,
  public entry, export, publication" section.
- **External consumer** — a use of the export from outside the boundary unit, in a non-test file. Imports are the
  usual form; **string references also count** (Python entry points in `pyproject`, Django settings strings, plugin
  registries, template names, Go `//go:linkname`, TypeScript dynamic `import()` with a literal). A test-file import is
  recorded (`test only: {file}`) and never counts.
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
  annotate nodes by directory, so two files of one workspace package can carry different tiers. Tiers are read from a
  recorded source — never inferred from the graph, from fan-in, or from who imports an external.
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
- **Edge** — one import statement from node A to node B, at `file:line`. Cycles, direction violations, and deep
  imports are judged per edge; one finding per edge (see Within-skill precedence).
- **Rewrite test** — the Leaked Internals evidence bar: would a reimplementation of the unit from its *promised
  behavior* alone keep this exported member? Members that usually fail: a cache map, a mutex, a DB row struct, a
  state-machine field, an intermediate representation. The test is about the unit's promise, not the member's kind — a
  parser library whose documented product is its AST passes with that AST; a domain type, a result, an option struct
  pass. The Exposed member cell states the reason; a member whose reason cannot be stated is not a finding.
- **Form** — a labelled variant inside one category, carried in the report's Form cell: Dead Exports `zero consumers`
  / `package-local only` (Go) / `test only` / `consolidated barrel` (Python, TypeScript); Deep Imports `crossing` /
  `exposure` (Go); Cyclic Dependencies `runtime` / `type-only`; External Type Leaks `signature` / `re-export` /
  `mapper output`; Generic Boundary Names `generic name` / `clause ≠ directory` (Go). Dependency Direction Violations
  has one form and no Form cell; its Basis cell says whether the map or a prohibition is the boundary source.

## What to Hunt

### Dead Exports

An export with no external consumer.

**Signals:**

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

**Not a finding:** a TypeScript or Python `export` consumed only by sibling files inside the unit — the keyword is how
files share. Go's analogue, an exported identifier used only package-locally, *is* the `package-local only` form.

**Action:** unexport; remove from `__all__`; replace the wildcard with named re-exports of the public API. Test-only:
the export exists for the test alone, and the Action names the public behavior the test should assert after
unexporting. After unexporting, a symbol with no callers at all becomes simplicity-hunter's next audit — sequential,
not double.

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
export; members that pass the rewrite test leave the placement question to smell-hunter. smell-hunter's Primitive
Obsession points at the same remedy — owned domain types — so the two never conflict. An exported struct
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
`pkg.internal.x`), and the symbol reached. *Exposure* form (Go, any module, Low) — a sub-package consumed only by its
parent or the parent's siblings, importable from the rest of the module because it is not under `internal/`, with no
outside importer yet. `internal/` restricts import to the tree rooted at its parent, so in-module packages are exactly
what it protects against.

**Not a finding:** an import from a unit with no public entry (a TypeScript directory with no barrel, no `exports`,
and no unit-named alias), an import through a root wildcard alias (`@/…`), or an import of a Go sub-package of a
package that is itself the entry — where every file is the entry, nothing is deep. A Python `_module` or `internal`
package is deep whatever its `__init__` says.

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
at the edge.

**Ownership:** solid-hunter's Concrete Dependency Chains is type-level wiring — self-instantiation, a module-level
singleton read; import direction between layers is here, and the last-resort interface is declared in the inward unit,
which is solid-hunter's own DIP shape. smell-hunter routes dependency direction here from Shotgun Surgery; one change
editing many areas stays smell-hunter's Shotgun Surgery.

### Cyclic Dependencies *(Python, TypeScript)*

Two or more modules importing each other, directly or transitively, on the module graph.

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

**Signals:**

- A → B → A; A → B → C → A
- A barrel or `__init__` that closes a cycle by re-exporting
- A circular-reference error at runtime or from a bundler
- An import deferred inside a function

**Evidence bar:** the cycle path; **Kind** — `runtime` when the cycle survives removal of every erased edge,
`type-only` when it does not; **Failure** — `provable from {entry}: {site}` (above), `observed: {log or test}` (a
cited existing output), or `none observed`. Deferred imports inside functions are a nomination signal only: they
neither prove nor exclude an init hazard. Same-layer type-only cycles are Low, with no "explicitly justified" concept;
cross-layer type-only edges route to Dependency Direction Violations.

**Action:** extract the shared concept into a third module, or invert the edge. A provable cycle's Action names the
entry and the statement that fails.

**Ownership:** unshared. A provable or observed `ImportError` is reported here at Critical with the failing site;
exception-hunter does not score it.

### External Type Leaks

An external type crossing inward.

- **Mirror and mapper** — a hand-written declaration parallel to an external type, and the function converting
  between them. **The mirror is never a finding here.** The finding is the **crossing**: the external type used inward
  beside the mirror, or a mapper whose output still carries external types or external enum values *when the mapper's
  output is an inward type*. A complete mapper is the remedy working. A field-for-field clone in the *same* layer as
  the external is nobody's finding, by design.

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
source. **Exported API only:** an inward unit's private use of an external is not this category.

**Action:** first ask whether the external concept belongs in the inward signature at all — transaction plumbing
usually does not. If it does: an owned type or interface **declared in the inward unit**, implemented and converted at
the edge, injected from the composition root, so the edge unit becomes the only importer of the external.

**Ownership:** the resulting seam is live under simplicity-hunter's existing Not-a-finding (an abstraction serving as
a test seam or DI boundary while an injector actually uses it) and solid-hunter's seam definition (a production
consumer receives it from outside); it is not a new exemption. What stays simplicity-hunter's Unnecessary
Abstractions: a wrapper the inward unit constructs itself, with no external type kept out. A hand-written mirror of a
generated / ORM / SDK type is never duplication for type-hunter. A type-system bypass with a reason in a boundary
layer is invariant-hunter's, content validation at a trust boundary is security-hunter's, and whether the external
*type* crosses inward is here — different questions on adjacent sites.

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

## Test-code scope

**Test files are excluded from findings.** Test paths are listed in each language reference; the exclusion is **by
path**.

Test files are **read as context**:

- A test-file import of an export is recorded in the Consumers cell as `test only: {file}` and never counts as an
  external consumer; the result is the Dead Exports `test only` form.
- Test-file deep imports and test-file edges are never findings and never close a reported cycle.

Test evidence never raises Severity. Anchor the finding at the production declaration or edge.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

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

A candidate that fails its evidence bar or matches a Not-a-finding line produces **no finding at any severity**.
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

   **Supported languages are Go, Python, and TypeScript.** Every other extension is **excluded, not audited**.
   JavaScript (`.js`, `.jsx`, `.mjs`, `.cjs`) files still enter the import graph as non-anchoring nodes (Terms).
   Record `excluded — no reference for .<ext>: {count} files` in Scope, naming each extension, and note the
   JavaScript graph inclusion.

3. **Load language references.** For every detected language, read `references/boundary-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/boundary-go.md`). **Fail closed:** if a required reference cannot be
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
   there. The import graph, consumers, tiers, and publication evidence are *read* as **context** wherever they live:
   a unit's consumers, a cycle's partner, and a layer's other side routinely sit outside any diff. Diff and path
   scope narrow the manifest, never the context reading. A finding anchors at the export declaration, the consumer's
   import line, the leaking signature, or the package clause; report-format.md gives the cycle and unit anchors.

5. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) and the named ADR paths for the
   **layer map**, **explicit prohibitions**, and **policy**: a stated layering, a sanctioned coupling, a generated
   type the project deliberately puts in its domain, a package documented as published. Then read the contract
   configurations each reference names. Record `Layer map: {source} — {mapping}` or `Layer map: none`,
   `Prohibitions: {source files}` or `Prohibitions: none`, and any `Policy:` lines. **With neither a map nor a
   prohibition, Dependency Direction Violations and External Type Leaks are not evaluated** — record the Scope line
   and judge the other five categories.

6. **Record the toolchain — present-only.** Run each loaded reference's Toolchain section with the tools the project
   already has, writing no configuration into the project, and write one `Toolchain:` line per tool with the exact
   invocation, in the form `references/report-format.md` gives.

7. **Read the emit settings** when TypeScript is in scope, per the TypeScript reference's "Emit and erasure" section,
   and record the `Emit:` line. Where the emit pipeline cannot be established, cycle Kind is withdrawn per candidate
   with a `Limitation` line, never guessed.

### Phase 2: Build the Import Graph

Project-wide, whatever the scope. One file-level graph, each edge tagged **erased** or **runtime** per the language
reference: Go from `go list` (or the import scan on failure); Python and TypeScript from import scans, with the
present graph tool as a nominator and cross-check. Graph scans run on `.` — never on the step-4 lists — and keep
generated files, which are context and can be consumers. Annotate nodes with their boundary unit and, where a layer
map exists, their tier. Record `Graph: {N nodes, M edges, E erased, U units} from {source}` in Scope.

### Phase 3: Scan and Nominate

Scans produce **candidates only**. For each loaded reference, run its Phase 3 scan block against that language's
step-4 list (`<run>/go.txt`, `python.txt`, `typescript.txt`, restored as `$GO_FILES`, `$PY_FILES`, `$TS_FILES`;
the single path `.` in codebase mode). Pass an explicit path to **every** `rg` invocation. Diff mode nominates
from the working tree over the manifest files, not from added lines: a boundary is a property of the current code.

Done when every scan in each loaded reference's Phase 3 block has run and every hit is listed as a candidate.

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

For each candidate: apply the category's own **Not a finding:** line first, where it has one; confirm the category
applies in that file's language (the loaded reference's Applicability table); apply the ownership tests — the export
definition per language, the rewrite test, the publication rule, the boundary-source rule, the mirror answer — and
within-skill precedence; then clear the category's evidence bar from What to Hunt. Check policy: a `Policy:` line withdraws what it names. Run each loaded reference's Phase 5
block for its language-specific judgment.

Assign **Severity and Impact** to every finding. One finding per edge and per exported member. Nothing is held back; `Audit completed: N findings` counts every reported finding.

**The zero-findings line is reached only when no category has a candidate** — no export, no module-graph cycle, no
module edge between different tiers or named by a prohibition, no deep import, no external type in an exported
signature, no generic-named unit. It is never keyed on cross-unit edges: two files inside one barrel directory
importing each other are a cycle candidate although the projection onto units shows no edge at all.

Done when every candidate is a reported finding, a withdrawal (`Limitation` or `Policy:` line), a drop (failed
evidence bar or a Not-a-finding line), or a hand-off to its owning hunter.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-boundary-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Read; never install or execute.** Use only tools the project already has. Establish a cycle's failure and the
  emit pipeline by reading code and existing logs — never by importing a project module or running a bundler.
- **Evidence from reading.** Every finding cites `file:line` with the exact declaration, import statement, or
  signature, and fills its category's evidence cells from what was read, never by inference.
