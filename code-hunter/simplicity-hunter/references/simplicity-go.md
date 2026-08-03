# Simplicity Hunter — Go reference

Language-specific rules for Go.

## Generated-code eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. **Never** guess by filename. Scan globs such
as `*.pb.go` / `*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Vendored trees (`vendor/`), lockfiles, and Markdown-only inputs are also ineligible.

## Language-only categories

### Interface Pollution

Interfaces created for theoretical extensibility rather than actual need. (Core principle flavoured for Go: an
interface that serves one call site and has one implementation is indirection, not simplification.)

**Signals:**

- Interface with one implementation and no test double
- Interface defined in the same package as its only implementation
- Interface that mirrors a concrete struct's full method set
- "Just in case" interfaces that have existed for months without a second implementation

**Action:** Remove the interface and use the concrete type. Introduce the interface when a second implementation or
test double is actually needed.

**Report table:**

| # | Location | Interface | Implementations | Severity | Impact | Action |
| - | -------- | --------- | --------------- | -------- | ------ | ------ |
| 1 | file.go:line | `Processor` | 1 (no test doubles) | Medium | Medium | Remove, use concrete type |

### Channel & Goroutine Overuse

Concurrency patterns more complex than the problem requires. (Core principle: **channels are not always the answer.**
A mutex protecting a map is simpler than a channel-based worker pattern for simple state. Use channels for
communication, mutexes for state protection.)

**Signals:**

- Channel used where a mutex-protected variable would suffice
- Goroutine launched for a single synchronous operation
- Worker pool pattern for a bounded, predictable workload
- Channel of channels (metachannel)
- `select` with a single case and no timeout

**Action:** Use the simplest concurrency primitive that works. Mutex for state, channel for communication, goroutine
for actual parallelism.

**Report table:**

| # | Location | Pattern | Simpler Alternative | Severity | Impact | Action |
| - | -------- | ------- | ------------------- | -------- | ------ | ------ |
| 1 | file.go:line | Channel for shared counter | `sync/atomic` | Medium | Medium | Replace |

## Reinvented Primitives

**Version source:** `go.mod` `go` directive (or documented toolchain).

| Primitive | Toolchain gate |
| --------- | -------------- |
| `errors.Join` | Go 1.20+ |
| `slices` / `maps` stdlib packages | Go 1.21+ |

**Signals:** loops that replicate `slices` / `maps` helpers (contains, clone, delete-func, keyed collect) where those
packages are available; re-implemented `errors.Is` / `errors.As` walks, or hand-rolled multi-error aggregation where
`errors.Join` applies.

**Carve-out:** `strings.Builder` is deliberately **excluded** — it is a performance transformation, usually increases
source-level complexity, and carries a do-not-copy-a-non-zero-Builder constraint.

## Dead-code liveness channels

Beyond call sites: reflection, DI registration, registries, entrypoint configuration, and Go build tags
(`//go:build`, `// +build`). Cite channels relevant to *this* symbol.

## Coexisting Generations — Go carve-outs and Phase 4

**/vN carve-out.** Exempt only when the governing `go.mod` — root or nested — declares a `module` path whose final
element is the matching `/vN` (Go's major-version module rule from v2 onward). Neither a directory *named* `v2` nor the
mere presence of a nested `go.mod` proves a major-version module.

**Nomination signals:** overlapping `go.mod` dependencies solving one concern; `// Deprecated:` on symbols with live
importers; `legacy/` / `old/` package directories whose older path still has importers; two or more role types for the
same concept, all still constructed somewhere; environment- or config-selected parallel implementations where both
branches are reachable.

### Phase 4 scans

```bash
# 1. Read go.mod files (root and nested); list overlapping-concern dependencies. Apply /vN carve-out only when a
#    governing module path's final element matches /vN.

# 2. Generation-named paths and symbols
rg -l --type go 'Legacy|Deprecated|Old' --glob '!**/vendor/**' .
find . -type d \( -name legacy -o -name old \) \
  -not -path '*/vendor/*' -not -path '*/.git/*'

# 3. Deprecation markers
rg -n --type go '// Deprecated:' --glob '!**/vendor/**' .
```

Confirm liveness for every candidate stratum across the whole project. Nominate survivors on capability and project
intent; `git log -1 --format=%as -- <path>` and recent call-site choice nominate only.

## Error-handling note

Idiomatic `if err != nil` repetition is not complexity (complements the shared Error handling Not-a-finding). Flag only
when error handling creates genuinely deep indentation or duplicated non-trivial construction/wrapping logic.

## Evidence path form

Cite findings as `file/path.go:line`.

## Phase 2 — complexity scans

Test files are included (complexity in tests is in scope). Duplication excludes them — see Phase 3 exclude below.

```bash
# Generated-code globs approximate the authoritative marker (eligibility uses the marker).
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Deep nesting (4+ indentation levels, tab-indented)
rg '^\t{4,}\S' --type go $EXCLUDE -- $SCOPE

# Boolean parameters
rg --pcre2 '\w+\s+bool[,)]' --type go $EXCLUDE -- $SCOPE

# Functions with many parameters
rg --pcre2 'func\s+(\(\w+\s+\*?\w+\)\s+)?\w+\([^)]{80,}\)' --type go $EXCLUDE -- $SCOPE

# Interfaces with single implementation (Interface Pollution candidates)
rg 'type\s+\w+\s+interface' --type go $EXCLUDE -- $SCOPE

# Unused unexported functions (Dead Code candidates)
rg 'func\s+[a-z]\w+\(' --type go $EXCLUDE -- $SCOPE

# Channel complexity / goroutine launches (Channel & Goroutine Overuse)
rg 'chan\s+chan|<-\s*<-' --type go $EXCLUDE -- $SCOPE
rg 'go\s+func|go\s+\w+\(' --type go $EXCLUDE -- $SCOPE

# Reinvented-primitive candidates (confirm toolchain + semantic parity before reporting)
rg 'errors\.Is|errors\.As|errors\.Join' --type go $EXCLUDE -- $SCOPE
rg 'slices\.|maps\.' --type go $EXCLUDE -- $SCOPE
```

## Phase 3 — Duplication exclude

```bash
DUP_EXCLUDE="$EXCLUDE --glob '!**/*_test.go'"
# Run duplication searches with $DUP_EXCLUDE so test-code duplication stays with test-hunter.
```
