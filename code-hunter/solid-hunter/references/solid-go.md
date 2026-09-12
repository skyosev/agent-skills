# SOLID Hunter — Go reference

Language-specific rules for Go.

## Applicability of the categories

| Category | Applicable | Unit | Note |
| -------- | ---------- | ---- | ---- |
| Responsibility Sprawl (SRP) | **yes** | **package** and struct | The package unit applies to functional packages too — a package of plain functions serving persistence AND transport AND rules is a finding |
| Rigid Extension Points (OCP) | **yes** | any discriminant: a string/`iota` kind, a type switch over a sealed interface, a boolean parameter | |
| Broken Substitution (LSP) | **yes** | interface implementations | Go has no inheritance; **implicit satisfaction** is the risk — a type satisfies an interface syntactically without honoring it, and nothing in the code says it meant to |
| Fat Interfaces (ISP) | **yes** | interface | The existence test decides ownership before width: an interface with no live seam is simplicity-hunter's Interface Pollution |
| Concrete Dependency Chains (DIP) | **yes** | struct | |

No Go-only categories.

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. **Never** guess by filename. Scan globs such
as `*.pb.go` / `*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`. Test files are still read as context — a
hand-written fake proves an interface's seam is live; a test that stubs seven members supports a width finding.

## Go principles

- **Accept interfaces, return structs.** A constructor returning a concrete `*T` and accepting small interfaces is the
  idiom, not a DIP violation.
- **Define interfaces at the consumer.** The consumer declares the two methods it needs; the producer never publishes
  a twelve-method interface "for" its callers. This is the Fat Interfaces remedy, not an extra abstraction.
- **Composition over inheritance.** Embedding is composition; there is no base class and no override. LSP applies to
  interface satisfaction only.
- **Explicit wiring in `main()`.** Constructing dependencies at the top and passing them down is the composition root
  working as designed. wire and fx are recognized as roots where already present; neither is recommended for adoption.
- **Optional interfaces are idiomatic.** `if wt, ok := w.(io.WriterTo); ok { … }` with a fallback is capability
  dispatch and never a finding.

## Per-category Go content

### Responsibility Sprawl — Go forms

Two units, evaluated separately:

- **Package.** Named actors whose requests land in the same package: HTTP handlers, SQL, and rate rules in one
  `billing` package is a finding at the package unit even when every file individually looks cohesive, and even when
  the package holds no structs at all. Remedy vocabulary: split into focused packages; the original becomes a thin
  coordinator or dissolves.
- **Struct.** Methods spanning unrelated concepts, a `New*` with many collaborators, methods that never touch the
  struct's fields. A cohesive aggregate whose methods all mutate one entity through one workflow is not a finding.

**Boundary with boundary-hunter-go §7.** Package *naming* (`util`, `common`), name-vs-directory mismatch, deep paths,
and a `models` package of unrelated domains are legibility findings there. Responsibility and change analysis — named
actors, independent reasons to change — is here. Until boundary-hunter unifies, its signal "multiple files in a package
spanning unrelated concerns" double-owns this; cross-reference in the Action cell rather than suppressing either.

### Rigid Extension Points — Go forms

Discriminants: a `kind string` / `iota` constant switched in several packages; a factory `switch` with no registration;
a type switch over a sealed interface used as variant dispatch; a `bool` parameter selecting behavior at two or more
sites. Remedy vocabulary, smallest first: a `map[Kind]X` lookup table when the arms select a value; one shared function
when the arms differ by a single call; an interface with one implementation per variant, dispatched through a
`map[Kind]Iface`, only when the arms carry behavior. Registration in each variant's `init()` is the standard way to
keep the core package ignorant of variants — recommend it only when the map itself is the remedy.

Go has **no compile-time exhaustiveness** for type switches or string kinds, so `default: panic("unreachable")` is the
best available and is never a finding of any hunter. It also never decides openness here.

### Broken Substitution — Go forms

- A method that `panic("not implemented")` or returns a not-supported error while the interface's documentation or a
  consumer implies it works
- A silent zero return — `return nil, nil` where the contract promises a value or an error
- An implementor that narrows accepted input, or returns errors where the contract implies success
- A consumer branch that compensates: `if _, ok := store.(*memStore); ok { skipTx = true }`

**Implicit satisfaction** is why the contract must be named from the interface's documentation, its consumers, or a
doc comment on the method — not from the method name. When the interface is undocumented and the branch merely adds an
extra (`Vacuum` outside `Store`), there is no finding.

A bare `store.(*memStore)` in a compensating role is **one** finding here, with the guard form noted in Action;
invariant-hunter does not also score it. `payload.(map[string]any)` on decoded JSON is invariant-hunter's, not a
contract type at all.

### Fat Interfaces — Go forms

The seam test first: an interface only ever returned by the package that implements it, never held as a parameter or
struct field by another package, with one implementation and no fake, is simplicity-hunter's Interface Pollution. A
seam is live when a consumer receives it as a parameter or field — handwritten wiring, a wire provider, an fx provider,
all count — or when a second implementation or a hand-written fake exists.

The Action is **define it at the consumer**: `type userReader interface { Get(ctx, id) (*User, error) }` in the
consuming package, the producer's concrete type satisfying it implicitly. An interface a single consumer uses fully
stays as it is.

### Concrete Dependency Chains — Go forms

The finding is a struct that **creates and keeps** a service: `func NewSvc() *Svc { return &Svc{m: &SmtpMailer{Host:
cfg.Host}} }` — the caller cannot choose the host, and a test cannot substitute the mailer. A function that builds a
dependency and hands it to another constructor without storing or calling it is a composition root, whatever file it
sits in: `func NewApp(cfg Config) *App { return &App{svc: NewSvc(&SmtpMailer{Host: cfg.Host})} }` is wiring.

Package-level services read inside methods — `func (s *Svc) Do() { rows := db.Query(…) }` over a package-level
`var db *sql.DB` — are the global-read form, anchored at `Svc`. A `SetDB` that reassigns the global is smell-hunter's
Mutable Global State at its own site; cross-reference.

**Action in Go, precisely.** Inject the concrete type: `func NewSvc(m *SmtpMailer) *Svc`. A Go concrete pointer
parameter cannot accept a fake, so the Action records the consequence — a future test double will need a
consumer-defined interface, introduced with the test that needs it — without recommending the interface now. Recommend
an interface immediately only when a second implementation or a fake already exists.

Not findings: `&Config{}`, `[]T{}`, `map[K]V{}`, a builder, any struct with no methods; `os.Open(path)` or
`http.NewRequest` inside one method on input the method received — resource use, not a collaborator.

## Composition roots and framework carve-outs

- A composition root is identified by **behavior**: it constructs, wires, and returns or runs; it decides nothing
  about the domain. `cmd/` and `main.go` *nominate* the search — a `main.go` that also computes prices has a root
  (its wiring function) and an audited unit (its pricing function).
- **wire** — a `//go:build wireinject` file, `wire.Build(…)`, or a generated `wire_gen.go`: provider functions are
  roots. **fx** — `fx.Provide`, `fx.Invoke`, `fx.New`: providers are roots and an fx-resolved dependency counts as a
  live seam for the existence test.
- Naming the construct is required. "The project uses fx" does not exempt a constructor that builds its own client.

## Evidence path form

Cite findings as `file/path.go:line`.

## Phase 2 — solid scans

Test files are **excluded** (see Test-code scope in SKILL.md). Every scan takes the eligible Go list; generated-code
globs approximate the authoritative marker. **Scans nominate only** — every DIP pattern below also fires on value
types, and each construction pattern misses cases the others catch, which is why all four run.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Responsibility Sprawl: structs and their constructors (then read the members and name the actors)
rg -n 'type\s+\w+\s+struct' --type go $EXCLUDE -- $SCOPE
rg -n '^func\s+New\w*\(' --type go $EXCLUDE -- $SCOPE

# Responsibility Sprawl at the package unit: imports per package (then group by concern)
rg -n -U --pcre2 '^import\s*\((?s).*?\)' --type go $EXCLUDE -- $SCOPE

# Fat Interfaces / Broken Substitution: interface declarations (then enumerate implementors and consumers)
rg -n 'type\s+\w+\s+interface' --type go $EXCLUDE -- $SCOPE

# Rigid Extension Points: switches on a discriminant, and type switches used as variant dispatch
rg -n 'switch\s+\w' --type go $EXCLUDE -- $SCOPE
rg -n 'switch\s+(\w+\s*:=\s*)?\w+\.\(type\)' --type go $EXCLUDE -- $SCOPE

# Rigid Extension Points: boolean parameters (a two-member discriminant; same bar as any other)
rg -n --pcre2 'func\s+\w+\([^)]*\b\w+\s+bool\b' --type go $EXCLUDE -- $SCOPE

# Broken Substitution: not-implemented implementors, and consumer branches on a concrete type
rg -n -i 'not.?implemented|unsupported' --type go $EXCLUDE -- $SCOPE
rg -n '\.\(\*?[\w.]+\)' --type go $EXCLUDE -- $SCOPE | rg -v '\.\(type\)'

# Concrete Dependency Chains: construction sites — four patterns, each catching what the others miss,
# all of them firing on value types. Filter to types WITH methods while reading.
rg -n '&\w+\{' --type go $EXCLUDE -- $SCOPE
rg -n '\w+\.\w+\{' --type go $EXCLUDE -- $SCOPE
rg -n 'new\(' --type go $EXCLUDE -- $SCOPE
rg -n 'New\w+\(' --type go $EXCLUDE -- $SCOPE

# Concrete Dependency Chains: package-level services (then find the methods that read them)
rg -n --pcre2 '^var\s+\w+\s+\*?(sql|http|redis|kafka|s3|grpc)\.' --type go $EXCLUDE -- $SCOPE

# Composition-root nomination (behavior decides; these only point the search)
rg -n 'func\s+main\(\)|wire\.Build|fx\.(Provide|Invoke|New)' --type go $EXCLUDE -- $SCOPE
```

**Embedding has no reliable scan.** Bare-identifier patterns inside a struct body match `return`, `break`, `continue`;
qualified embeds (`sync.Mutex`, `pkg.Client`) defeat case anchoring. Enumerate the `type X struct` sites above and read
their bodies.

## Phase 4 — Go-specific evaluation

For each construction site nominated:

- Does the constructed type have methods, and do any of them do I/O or hold process-external state? No → value, not a
  finding.
- Does the enclosing function **keep** the object — store it in a field, call it — or hand it to another constructor?
  Handed on → composition root, not a finding, whatever the file.
- Is the enclosing function a wire/fx provider or `main()`'s wiring? → root.
- What can the caller not control as a result — the host, the timeout, the clock, a shared pool's lifecycle? Name it,
  or there is no finding.

For each interface:

- Is the seam live — received from outside by a production consumer, an fx/wire-resolved dependency, a second
  implementation, or a hand-written fake? No → simplicity-hunter's Interface Pollution; cross-reference, do not score.
- Live: which consumers call which subset, and are the unused members *unrelated* to the used ones? One consumer
  using everything does not close the finding.
- Do any implementors panic or stub a member? Apply the within-skill routing before choosing the category.

For each type assertion or type switch on an interface:

- Is the asserted-from type a **contract type** (methods, implementors) or a **data variant set** (tagged structs)?
  Variant set → invariant-hunter.
- Does the branch **compensate** for a broken promise, or unlock an extra outside the contract? Extra → no finding.
- Optional-interface check with a fallback → capability dispatch, no finding.

For each switch on a discriminant:

- List every site project-wide. One site → no finding.
- Do the arms share one responsibility? Heterogeneous → recommend exhaustiveness per site, raise nothing.
- `git log -S '<discriminant value>' -- .` — did adding a variant touch two or more of the listed sites? No history
  evidence and no variant-adding diff → withdraw.

For each package in scope:

- Which actors do its files serve, and which members belong to each? Two actors with independent reasons to change →
  finding at the package unit, including for a package of plain functions.
- Is the concern instead naming or directory placement? → boundary-hunter.
