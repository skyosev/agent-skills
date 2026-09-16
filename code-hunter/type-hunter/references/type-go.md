# Type Hunter — Go reference

Language-specific rules for Go.

## Applicability of the universal categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Duplicated Type Declarations | **yes** | Sibling type only. Consolidation is composition or deletion: embed, explicit field, or delete-and-use. Go has no derivation from a runtime value — a hand-written set of constants beside a slice of the same values is not a finding — and no schema library whose type stands in for a struct |
| Generics That Never Vary | **yes** | Type arguments are almost always inferred at call sites; instantiations are read, not scanned |
| Loose Type Parameter Constraints | **yes** | `[T any]` with `comparable` or method use inside; the Go form: a generic body that type-switches on `T` |
| Over-Powered Type Constructs | **n/a** | Go has no conditional, mapped, or overload constructs. The only type-level power is the constraint, and a type switch inside a generic body is Loose Type Parameter Constraints |
| Enum Construct Mechanics | **yes** | `iota` group with no named type; a named constant type formatted, logged, or serialized with no `String()` |
| Alias vs Named Type Mechanics | **yes** | `type X = Y` only. A method-less named type is Not a finding; there is no named-composite signal |

**Go-only category:** Embedding Antipatterns, defined below.

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. **Never** guess by filename. Scan globs such
as `*.pb.go` / `*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Generated files are still **read as context**: a hand-written struct that mirrors a `.pb.go` message is identified by
reading the message, and the pair is routed to boundary-hunter — never reported here (see Duplicated Type Declarations
below).

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`. Test files are still read as context —
a `Cache[fakeOrder]` in a test is listed in the Instantiations cell marked `(test)` and never counts as variation.

## Go principles

- **Small named types are the language working as designed.** `type UserID string`, `type Config struct{…}` with no
  methods carry a domain name and keep signatures readable. No finding, over a primitive or a composite.
- **Consumer-defined interfaces, not type-level cleverness.** Where TypeScript would derive, Go composes or deletes.
  Never recommend a construct Go cannot express — no `Pick`, no runtime-value derivation, no conditional type.
- **Embedding is composition that promotes.** An embed hands every promoted method and field to the outer type's
  consumers. That is the whole reason Embedding Antipatterns exists and the whole reason "embed the shared struct" is
  not an automatic consolidation path.
- **Type arguments are inferred.** `Max(a, b)`, `NewCache(users)` bind `T` without writing it. Regex finds the
  declaration; the instantiation set is read from call sites.
- **Untyped constants convert freely.** A `const` with no type is accepted anywhere its kind is — the concrete cost of
  an `iota` block with no named type.

## Per-category Go content

### Duplicated Type Declarations — Go consolidation paths

Consolidation is composition or deletion, in this order, and the Action says which and why:

1. **Embed a shared struct** only when the outer type should carry the shared struct's *method set*. An embed promotes
   every method; if the consumers of the outer type should not have them, embedding trades a duplicate for an
   Embedding Antipatterns finding.
2. **An explicit field** (`Base User` or `user User`) when the wire or storage shape allows the nesting — JSON, SQL
   scanning, and protobuf mapping change shape when a flat struct becomes nested. Read the encoders and scanners
   before recommending it.
3. **Delete and use** when one struct can stand in for the other at every site: every former site of the deleted
   struct is read and accepts the survivor. Parallel `const` blocks for one value set are the same path — delete one
   block, use the other.
4. **None fits → withdraw.** A DTO in `api/` with the same fields as a domain struct that has methods, where embedding
   would promote the methods and a field would change the JSON shape, and neither copy can be deleted, is Not a
   finding. Not a Low with "keep in sync".

**Cross-layer mirrors are boundary-hunter's.** A hand-written struct mirroring a `.pb.go` message, an ORM model, or an
SDK type — in any package, with any mapper, whatever the mapper drops or copies — is boundary-hunter's External Type
Leaks / Missing Abstraction Over Externals. Never a source kind here. Duplication is between two hand-written structs.

**Repeated inline expressions.** The same func type (`func(context.Context, *Event) error`) written at independent
sites is a candidate; the Action is one named type. A single unnamed complex type is not a finding.

### Generics That Never Vary — Go forms

`type Cache[T any] struct` used as `Cache[User]` everywhere; a `func Map[T, U any]` whose one call site fixes both.
Instantiations are read from every call site and every field or variable declaration that names the type
(`Cache[User]`, `NewCache[User]()`, and inferred `NewCache(users)`). Tests are marked `(test)`.

**Closed consumer set per exported symbol.** For an exported generic, read how the module is published: a `main`
package, an internal module, or an `internal/` path closes the set; a module other repositories import (the go.mod
module path is a published import path with tagged versions, or the symbol sits in a package the module documents as
its API) does not. Withdraw with a `Limitation` line; do not classify the repository.

Action vocabulary: remove the parameter, the concrete type in its place; the test's fake becomes a fake of the
production type.

### Loose Type Parameter Constraints — Go forms

- `[T any]` whose body uses `==` or a map key → `comparable`
- `[T any]` whose body compares with `<` → `cmp.Ordered` (**Go 1.21+**, read `go` directive in `go.mod`; below 1.21,
  `golang.org/x/exp/constraints.Ordered` if already a dependency, else a hand-written union constraint)
- `[T any]` whose body calls a method through `any(v).(fmt.Stringer)` or `any(v).(X)` → the interface as the constraint
- **The type-switch form**: `func Encode[T any](v T)` whose body is `switch any(v).(type)` over concrete cases. The
  constraint is `any` and the body enumerates types — the generic is a disguised set of functions. Action: concrete
  functions per case, an interface the cases implement, or a union constraint (`~int | ~string`) when the cases are
  the union's members and the body's operations are permitted on all of them.

**Not Loose:** an opaque body — stores `T`, returns `T`, passes it through, ranges over `[]T` without touching
elements. However many callers pass one type, that is Generics That Never Vary.

**Precedence with invariant-hunter:** `any(v).(X)` inside a generic body that a constraint removes is one finding here.
`payload.(map[string]any)` on decoded JSON is invariant-hunter's, not a constraint question.

### Enum Construct Mechanics — Go forms

- **`iota` group with no named type.** `const ( Active = iota; Inactive )` yields untyped integer constants accepted
  anywhere an `int` is. The paying consumer is a function or field that accepts the value — `SetStatus(s int)`,
  `Status: 3`. Action: `type Status int`; the first constant takes the type (`Active Status = iota`).
- **Named constant type with no `String()`, formatted somewhere.** `type Status int` with `iota` and a
  `log.Printf("%v", s)`, `fmt.Sprint(s)`, `%d` in a user-facing message, or JSON encoding of the raw integer. The
  paying consumer is the formatting or serialization site. Action: a `String()` method; `stringer` is vocabulary
  (`//go:generate stringer -type=Status`), never run. No formatting site → no finding.
- **Not findings:** gaps or manual values inside an `iota` block (the specification's own examples do both); a zero
  sentinel `Unknown = 0` never checked (→ invariant-hunter Zero-Value Traps); `Status(n)` from a request body with no
  range check (→ invariant-hunter; content → security-hunter); a raw `if s == "active"` with no constant group
  (→ smell-hunter Primitive Obsession).

### Alias vs Named Type Mechanics — Go forms

`type X = Y` (the `=` is the alias) with no `// Deprecated:` or migration comment and no second name in live use.
`type UserID = string` prevents nothing: it *is* `string`. Action: `type UserID string` for distinction, or delete
the alias. A `// Deprecated: use domain.UserID` comment, or both names live during a visible rename, is the alias
working as designed. A method-less named type (`type UserID string`, `type Config struct{…}`) is Not a finding; the
source skill's "adds nothing" signal is withdrawn.

## Go-only category

### Embedding Antipatterns

An embedding that promotes API surface the outer type's consumers should not have.

**Forms and evidence bar:**

1. **`sync.Mutex` / `sync.RWMutex` embedded in an exported struct** (`type Server struct { sync.Mutex; … }`). `Lock`
   and `Unlock` are promoted to every importer. Evidence: the struct is exported, and the mutex is embedded rather
   than a field. Severity High.
2. **Promoted methods that conflict or exceed use.** `type Client struct { *http.Client }` promotes `Do`, `Get`,
   `Head`, `Post`, `PostForm`, `CloseIdleConnections`; if every consumer in the repository calls `Do` only, the
   promoted surface is `6 / 1`. Evidence: the promoted set, the outer type's own methods where they collide, and the
   used subset per consumer; the consumer set closed inside the tree, else withdrawn with a `Limitation` line.

**Action:** an unexported field (`mu sync.Mutex`; `c *http.Client`) and explicit delegation of the used methods.

**Not findings:** a mutex embedded in an *unexported* struct, or held as an unexported field — a deliberately narrower
line than golangci-lint's `embeddedstructfieldcheck`, which flags every embedded mutex; kept as the source skill's
choice, and stated here so it reads as a choice and not a blind spot. Embedding that promotes exactly what the
consumers call (`type reader struct { io.Reader }` whose consumers read). A struct embedding an interface it implements
only partly, with the embed left nil — solid-hunter's Broken Substitution (the nil embed panics on the unimplemented
member); cross-reference, do not score.

**Ownership:** interface width per consumer is solid-hunter's Fat Interfaces; this category judges a struct's
promoted method set.

## Evidence path form

Cite findings as `file/path.go:line`.

## Phase 2 — type scans

Test files are **excluded** (see Test-code scope in SKILL.md). Every scan takes the eligible Go list; generated-code
globs approximate the authoritative marker. **Scans nominate only** — `rg 'iota'` finds every constant group, the
struct census finds every struct; the reading phase carries the load.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Duplicated Type Declarations: struct census (then compare field sets by concept, project-wide)
rg -n 'type\s+\w+\s+struct' --type go $EXCLUDE -- $SCOPE

# Duplicated Type Declarations: repeated func types written inline
rg -n --pcre2 '\bfunc\([^)]*\)\s*(\(?[\w.*\[\], ]+\)?)?\s*[,)\]{]' --type go $EXCLUDE -- $SCOPE

# Generics That Never Vary / Loose Type Parameter Constraints: type parameter lists (declarations only —
# instantiations are read from call sites)
rg -n --pcre2 '^(type|func(\s*\([^)]*\))?)\s+\w+\[[^\]]*\b(any|comparable|~|\w+\.\w+|interface)\b' --type go $EXCLUDE -- $SCOPE

# Loose Type Parameter Constraints, Go form: a type switch on a type parameter inside a generic body
rg -n 'switch\s+\w*\s*:?=?\s*any\(' --type go $EXCLUDE -- $SCOPE
rg -n 'any\(\w+\)\.\(' --type go $EXCLUDE -- $SCOPE

# Enum Construct Mechanics: iota groups (then read the block for a named type, and the formatting sites)
rg -n 'iota' --type go $EXCLUDE -- $SCOPE

# Alias vs Named Type Mechanics: aliases only (no named-composite scan)
rg -n 'type\s+\w+\s*=' --type go $EXCLUDE -- $SCOPE

# Embedding Antipatterns: mutex nomination (exportedness and embed-vs-field are read)
rg -n 'sync\.(Mutex|RWMutex)' --type go $EXCLUDE -- $SCOPE
```

**Embedding has no reliable scan.** Bare-identifier patterns inside a struct body match `return`, `break`, `continue`;
qualified embeds (`sync.Mutex`, `pkg.Client`) defeat case anchoring. Enumerate the `type X struct` sites above and read
their bodies.

**Version gate:** `grep -m1 '^go ' go.mod` — `cmp.Ordered` needs 1.21+.

## Phase 4 — Go-specific evaluation

For each pair of structs nominated as duplicates:

- Is either a mirror of a `.pb.go`, ORM, or SDK type? → boundary-hunter; stop.
- Name the concept and map every field. Then, in order: does the outer type want the shared method set (embed)? Does
  the wire or storage shape allow nesting (field)? Does every site of one copy accept the other (delete-and-use)?
  None → withdraw.
- Both copies live and already diverged (a field in one, absent or differently typed in the other, both consumed)?
  → High, divergence named in Evidence.

For each type parameter:

- Enumerate instantiations from call sites and declarations, tests marked. One production type, set closed → Generics
  That Never Vary; the Action names the test fake's replacement. Exported and published outside the tree → withdraw
  with a `Limitation`.
- What does the body do with `T`? Opaque → no Loose finding. `==`, `<`, a method through `any(v).(X)`, a type switch
  → Loose, with the tightest constraint every instantiation satisfies and the `go.mod` gate checked for
  `cmp.Ordered`.

For each `iota` block:

- Is there a named type? No → which consumer accepts the untyped constant? Name it or there is no finding.
- Named type: is it formatted, logged, or serialized anywhere with no `String()`? Name the site or there is no
  finding.
- Gaps, manual values, an unchecked zero sentinel, a missing range check → not here.

For each alias:

- `=` present, no migration comment, no second live name → finding. Otherwise no finding. `type X Y` without `=` is
  a named type and never a finding here.

For each struct with an embedded field:

- Exported struct embedding a mutex → High. Unexported, or a field → no finding.
- Enumerate promoted methods and the subset each consumer calls; collisions with the outer type's own methods. Used
  subset smaller than promoted set, consumer set closed → finding. Consumers read exactly the promoted set → no
  finding. Embedded interface left nil → solid-hunter.
