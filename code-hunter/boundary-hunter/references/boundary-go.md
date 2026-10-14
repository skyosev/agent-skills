# Boundary Hunter — Go reference

Contents: Applicability of the categories · Generated-code and test-path eligibility · Go principles · Boundary unit, public entry, export, publication · Layer map, prohibitions, and policy · External types · Per-category Go content · Toolchain · Evidence path form · Phase 2 — graph build · Phase 3 — Go scans · Phase 5 — Go-specific evaluation

Language-specific rules for Go.

## Applicability of the categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Dead Exports | **yes** | An uppercase top-level identifier or method. Adds the `package-local only` form: Go is the one language where the export has a cheaper edit than deletion — unexport. Struct fields and reflection-protocol methods are never candidates; an interface-named method is a candidate unless a use-as-interface site exists |
| Leaked Internals | **yes** | An exported field or type whose shape is the implementation, with an external consumer touching it |
| Deep Imports | **yes** | `internal/` makes the crossing form compiler-rejected inside its own subtree, so the Go crossing form is a reached implementation sub-package *not* under `internal/`. Adds the `exposure` form: a sub-package only its parent or the parent's siblings import, in any module |
| Dependency Direction Violations | **yes** | Module edges are package edges; a Go file cannot import from its own package, so there is no intra-unit edge |
| Cyclic Dependencies | **n/a** | The compiler rejects import cycles. A Go cycle is a build error, not an audit finding; nothing here nominates one |
| External Type Leaks | **yes** | External = an import path outside every module of the repository and not stdlib; `golang.org/x/...` is external |
| Generic Boundary Names | **yes** | Package unit. Adds the `clause ≠ directory` form, which only Go has |

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. **Never** guess by filename. Scan globs such
as `*.pb.go` / `*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Generated files are still **read as context**, and their declarations are the **external types** External Type Leaks
judges — a `.pb.go` message is an external type even when the `.proto` lives in this repository (the skill's stated
policy; see SKILL.md Terms).

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`. Test files are still read as context — a
test-only importer is recorded `test only: {file}` and never counts as an external consumer. `package foo_test` is the
public API's consumer, only a test one; the Action never turns it into an internal test.

## Go principles

- **`internal/` is the enforcement mechanism.** It restricts import to the tree rooted at its parent, at compile time.
  That is why the crossing form under `internal/` cannot exist (the compiler already rejected it), and why the
  exposure form is a finding in *any* module: `cmd/api` importing `pkg/crypto/impl` inside one application is exactly
  what `internal/` prevents.
- **Packages are flat and focused.** Never recommend a deep hierarchy to "organize"; the remedy for a generic name is
  a capability name, and the remedy for exposure is `internal/`, not nesting.
- **Unexport is cheap.** A lowercase rename is the whole edit for a package-local-only export, which is why Go has a
  form for it and Python does not.
- **Reflection reaches exported members without an import.** `encoding/json`, `text/template`, `database/sql`, and
  ORMs read struct fields and protocol methods by name. The consumer set for those cannot be closed by reading, so
  they are never Dead Exports candidates.
- **Interfaces are satisfied implicitly.** A method is never "called through the interface" in a way grep can see; the
  use-as-interface search looks for the *type* in an interface position, not for the call.
- **There are no re-exports.** A Go package cannot re-export another package's symbol, so the `re-export` leak form
  in Go is an alias (`type User = pb.User`) or a wrapper type declaration, and "multiple import paths for one concept"
  has no Go form.

## Boundary unit, public entry, export, publication

- **Boundary unit** — the package, identified by its import path.
- **Public entry** — the package path itself. A sub-package that only its parent imports is implementation, not an
  entry.
- **Export** — an uppercase top-level `func`, `type`, `const`, `var`, or method.
  - **Struct fields are never Dead Exports candidates.**
  - **Reflection-protocol method names are never candidates:** `String`, `Error`, `Format`, `GoString`,
    `MarshalJSON`, `UnmarshalJSON`, `MarshalText`, `UnmarshalText`, `MarshalBinary`, `UnmarshalBinary`, `Scan`,
    `Value`.
  - **An interface-named method is a candidate** — a name matching an interface declared or imported anywhere in the
    graph (`Close`, `Read`, `Write`, `ServeHTTP`, `Handle`, a project interface) — **unless a use-as-interface site
    exists**: `var _ io.Closer = (*Store)(nil)`, a conversion `io.Closer(s)`, an argument to a parameter of that
    interface type, a return typed as it, a struct field, slice element, or map value typed as it. A value that
    reaches an `any` / `interface{}` boundary and could be asserted elsewhere is treated as used (abstain).
- **External consumer** — an import of the package from another package, in a non-test file; plus string references
  (`//go:linkname`, a name in a code-generation directive or a registry keyed by string).
- **Publication per unit** — **closed** (judged in tree): a `main` package; any package under an `internal/` path; a
  package of a module that contains a `main` package **and** whose repository documents no import use. **Open**
  (Dead Exports withdrawn with a `Limitation` line): a module with no `main` package and a public module path, or
  **any** documented import use — a `go get <module path>` line or a quoted `"<module path>…"` import path in a
  README or doc, a `doc.go` on a non-main package, an `examples/` directory. Mixed evidence opens. No tags, releases,
  or CI workflows are read.

## Layer map, prohibitions, and policy

- **Layer map sources**, in precedence: repository instructions and named ADR files; then conventional sibling
  directory names from the fixed vocabulary — inner `domain`, `core`, `entities`; middle `application`, `usecase`,
  `usecases`; edge `infra`, `infrastructure`, `adapters`, `persistence`, `db`, `transport`, `http`, `handlers`,
  `controllers`, `cli`, `cmd`, `ui`, `web`. `cmd` is an edge-tier name in Go. Two or more tiers must be present as
  **sibling directories under one parent**, with no name used in two tiers. `service`, `services`, `api`, `app`, and
  `models` are not vocabulary. Go has no `import-linter` equivalent that expresses an ordering.
- **Prohibition sources**: `.go-arch-lint.yml` — a component's `mayDependOn` set that excludes the target, or a
  `cannotDependOn` entry naming it. The rule is evidence for the edge it names and never becomes a tier.
- **Policy**: `.go-arch-lint.yml` entries that explicitly permit an edge, and repository instructions. An edge no rule
  mentions is neither permitted nor forbidden.

## External types

External = an import path outside **every** module of the repository (all `go.mod` files, all `go.work` members) and
not in the standard library. `golang.org/x/...` is external: it is versioned and released separately from the
toolchain. A module in the same `go.work` or a second `go.mod` of this repository is **first-party** — a type from it
is never an External Type Leak, though an edge to it is still judged for direction.

Marker-generated declarations (`.pb.go` messages and enums, mock and client stubs) are external types by stated
policy, whoever owns the schema.

## Per-category Go content

### Dead Exports — Go forms and the census caveat

**The export census cannot be built by line-anchored regex.** `rg 'func\s+[A-Z]|type\s+[A-Z]|var\s+[A-Z]|const\s+[A-Z]'`
misses exported **methods** (`func (s *Store) Close()`) and every member of a grouped `const (…)` / `var (…)` block —
the dominant forms of both. Enumerate the exported surface by **reading declarations**; the scan is a discovery aid.

Forms:

- `zero consumers` — no package outside imports the identifier, and the unit is closed.
- `package-local only` — the identifier is used, but only inside its own package. The Action is the lowercase rename.
- `test only` — the only importer is a `*_test.go` file (including `package foo_test`). Low; the Action names the
  public behavior the test should assert after unexporting.

A candidate whose unit is open is **withdrawn** with `Limitation: {package} open; {signal}; consumer set not closed`.

### Leaked Internals — Go forms

An exported field or type whose shape is the implementation, with an external consumer touching it: `Mu sync.Mutex`
locked by an importer, `Cache map[string]*Conn` ranged over, an exported state enum an importer switches on to decide
its own behavior. Reads are Medium, writes High.

**Not here:** a struct *embedding* `sync.Mutex`, which promotes `Lock` / `Unlock` — type-hunter's Embedding
Antipatterns judges the promoted method set. An exported `Config` struct a consumer reads passes the rewrite test: the
configuration *is* the unit's promise.

### Deep Imports — Go forms

- `crossing` — an import of an implementation sub-package from outside its parent: `service/impl`, `handler/private`,
  `pkg/auth/tokens` where `pkg/auth` is the entry. Under `internal/` this form cannot occur; the compiler rejects it,
  and a package that *is* reachable is by definition not protected. The Public entry cell names the parent package.
- `exposure` — a sub-package imported only by its parent or the parent's siblings, not under `internal/`, with no
  outside importer yet. Low, in **any** module: `internal/` restricts import to the tree rooted at its parent, so
  in-module packages are exactly what it protects against. Action: move it under the `internal/` of the nearest
  common parent of all its importers — `pkg/crypto/internal/impl` when only `pkg/crypto` imports it,
  `pkg/internal/impl` when `pkg/auth` imports it too. Public entry cell: `none yet — exposure`.

A Go sub-package of a package that is itself the entry (a package with no parent API, imported directly by design) is
not a deep import.

### Dependency Direction Violations — Go content

Package edges. The Action order is: move the type to the package that owns it; pass the value in from `cmd/`; and
only where the import cannot otherwise be broken, an interface **declared in the inward package** and implemented at
the edge. Go is the language where the last-resort inversion is most often the real answer, because there is no other
way to break a compile-time import — but it is still last, and it is never phrased as "define an interface in the
lower layer".

### External Type Leaks — Go content

- `signature` — an exported func, method, field, or type in an inward package whose signature names an external type:
  `func (r *Repo) Save(ctx context.Context, tx pgx.Tx) error`. `context.Context` and `time.Time` are stdlib and never
  leaks; `pgx.Tx` is.
- `re-export` — `type User = pb.User`, or an exported type whose definition is an external type, declared in an
  inward package.
- `mapper output` — `func toDomain(u pb.User) domain.User` whose result still carries `pb.Status` in a field, or
  returns external enum values.

Edge-tier packages (`infra/*`, `transport/*`, `cmd/*`) using or converting these types are the wrapping layer and are
never findings. A `userRow` struct inside `infra/postgres` cloning a `pb.User` is nobody's finding — type-hunter
refuses it (no consolidation path that keeps the external out), and there is no crossing here.

### Generic Boundary Names — Go forms

- `generic name` — a package named `util`, `utils`, `common`, `helpers`, `shared`, `misc`, `base`, `models`, `types`,
  `lib` **and** exporting two or more unrelated capabilities, enumerated in the Capabilities cell. `strutil` holding
  string helpers only is not a finding.
- `clause ≠ directory` — the `package` clause differs from the directory name. **Exceptions:** `package main`; a
  `_test` package; a major-version directory (`/v2`, `/v3`); a hyphenated directory whose clause drops the hyphen or a
  `go-` prefix (`go-redis` → `redis`, `my-pkg` → `mypkg`).

A package spanning persistence, HTTP, and pricing across ten files is **solid-hunter's** Responsibility Sprawl, not a
finding here; this category judges the name.

## Toolchain

`go list` is the graph source and is **always attempted** — it ships with the toolchain and is never an install:

```bash
go list -test=false -f '{{.ImportPath}} {{join .Imports " "}}' ./...
```

Module resolution can need the network, and build errors or unresolvable tags make it fail. On failure, build the
graph from the import scan below and record `go list: errored — {message}; graph from import scan (build tags not
resolved)`. Findings then claim the scanned graph.

No other tool is run. `golang.org/x/tools/cmd/deadcode` is **dropped**: it needs installing, and RTA over `main`
packages is not a symbol census — it says nothing about exported types, constants, or variables, and cannot establish
deadness for a library. `go-arch-lint` is read as a **configuration** (`.go-arch-lint.yml`), never executed.

## Evidence path form

Cite findings as `file/path.go:line`. Anchor Generic Boundary Names and the exposure form at the package clause line
of the unit's first file in sorted order (`pkg/crypto/impl/impl.go:1`).

## Phase 2 — graph build

Nodes are packages (import paths), edges are the `Imports` lists from `go list`, or `import` blocks from the scan. All
Go edges are **runtime**: Go has no type-only import. Annotate each package with its directory tier where a layer map
exists, and with `internal/` membership.

Both commands read the whole project (`.`), whatever the scope. The fallback keeps generated files: they are context,
and a generated file (Wire's `wire_gen.go`) can be the only consumer of an export.

```bash
# Graph (preferred) — one line per package: import path, then its imports
go list -test=false -f '{{.ImportPath}} {{join .Imports " "}}' ./...

# Graph fallback when go list fails — import lines and the 30 lines after each `import (`
rg -n -A 30 '^\s*(import\s+\(|import\s+")' --type go --glob '!**/vendor/**' --glob '!**/testdata/**' --glob '!**/*_test.go' -- .
```

## Phase 3 — Go scans

`$GO_FILES` is this language's eligible list, restored from `<run>/go.txt` (SKILL.md Phase 1 step 4). Test files are
**excluded**. **Scans nominate only.**

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Dead Exports: export census — a discovery aid only. Misses methods and grouped const/var members;
# enumerate the exported surface by reading declarations.
rg -H -n 'func\s+[A-Z]|type\s+[A-Z]|var\s+[A-Z]|const\s+[A-Z]' --type go $EXCLUDE -- $GO_FILES

# Dead Exports: exported methods (the form the census above misses)
rg -H -n --pcre2 '^func\s+\([^)]+\)\s+[A-Z]\w*\(' --type go $EXCLUDE -- $GO_FILES

# Dead Exports: grouped declaration blocks (read the members)
rg -H -n --pcre2 '^(const|var)\s*\($' --type go $EXCLUDE -- $GO_FILES

# Leaked Internals: exported fields whose types are implementation shapes
rg -H -n --pcre2 '^\s+[A-Z]\w*\s+(sync\.(Mutex|RWMutex|Map)|map\[|chan\s|\*?bytes\.Buffer)' --type go $EXCLUDE -- $GO_FILES

# Deep Imports: imports reaching implementation sub-packages
rg -H -n --pcre2 '"[^"]+/(impl|internal|private|detail)(/[^"]+)?"' --type go $EXCLUDE -- $GO_FILES

# External Type Leaks: type aliases to an imported package's type (re-export form)
rg -H -n --pcre2 '^type\s+[A-Z]\w*\s*=\s*\w+\.' --type go $EXCLUDE -- $GO_FILES

# Generic Boundary Names: package clauses (compare with the directory; read the exports for capabilities)
rg -H -n '^package\s+\w+' --type go $EXCLUDE -- $GO_FILES

# Publication signals — project-wide, one pass per module (root go.mod, go.work members, nested modules)
for m in $(rg --files --glob '**/go.mod' --glob '!**/vendor/**' -- .); do
  MODPATH=$(awk '/^module /{print $2; exit}' "$m")
  [ -n "$MODPATH" ] || continue
  rg -n -F -e "go get $MODPATH" -e "\"$MODPATH" --glob '*.md' --glob '*.rst' -- .
done
rg -n --pcre2 '^package\s+(?!main\b)' --glob '**/doc.go' -- .
ls -d examples/ 2>/dev/null
```

**Use-as-interface search** (per interface-named method candidate, project-wide, reading not grepping): the type in a
`var _ I = ` assertion, a conversion, a parameter, a return, a field, a slice element, or a map value typed as an
interface declaring that method.

## Phase 5 — Go-specific evaluation

For each exported identifier nominated:

- A struct field, or a reflection-protocol method name? → no finding.
- An interface-named method? → is there a use-as-interface site, or does the value reach an `any` boundary? Either
  → no finding. Neither → candidate.
- Consumers outside the package, read (not grepped), string references included? None and the unit is **closed** →
  `zero consumers`. Only inside its own package → `package-local only`. Only `*_test.go` → `test only`, Low. Unit
  **open** → withdraw with a `Limitation` line.
- Consumed, and does the member fail the rewrite test with a statable reason? → Leaked Internals instead; reads
  Medium, writes High.

For each import edge:

- Both endpoints' tiers recorded, and the edge points outward? Or does a `.go-arch-lint.yml` rule name it? → Dependency
  Direction Violations, Basis filled. No boundary source → nothing.
- Does it reach an implementation sub-package from outside its parent? → Deep Imports `crossing`, unless direction
  already took the edge by precedence.
- Does a rule explicitly permit it? → `Policy:`, withdrawn.

For each package:

- Only its parent or the parent's siblings import it, and it is not under `internal/` → Deep Imports `exposure`, Low.
- Generic name, and two or more unrelated capabilities enumerated → Generic Boundary Names.
- Clause ≠ directory, and none of the four exceptions → `clause ≠ directory`, Low.
- Responsibilities spanning actors → solid-hunter; cross-reference, do not score.

For each exported signature in an inward-tier package (boundary source required):

- Does it name an external type — outside every module of the repository, not stdlib, or marker-generated? →
  `signature`. An alias or a type defined as an external → `re-export`. A conversion whose result still carries the
  external → `mapper output`. Edge tier → no finding. No boundary source → no finding, all forms.

Cyclic Dependencies is **n/a**: a Go import cycle does not compile, and nothing nominates one.
