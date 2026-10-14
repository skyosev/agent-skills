# Simplicity Hunter — Go reference

Contents: Generated-code eligibility · Language-only categories · Reinvented Primitives · Dead-code liveness channels · Coexisting Generations — Go carve-outs and Phase 4 · Error-handling note · Phase 2 — complexity scans · Phase 3 — Duplication list and exclude

## Generated-code eligibility

**Marker:** a `// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs: `*.pb.go` /
`*_gen.go` / `*_generated.go`. **Vendored:** `vendor/`.

## Language-only categories

### Interface Pollution

Interfaces created for theoretical extensibility rather than actual need.

**Signals:**

- Interface with one implementation and no test double
- Interface defined in the same package as its only implementation
- Interface that mirrors a concrete struct's full method set
- "Just in case" interfaces that have existed for months without a second implementation

**Ownership — existence, not width.** An interface with a live seam (SKILL.md Terms; in Go the outside wiring may be
handwritten or a wire or fx provider) is solid-hunter's Fat Interfaces question. This category owns the interface with
**no live seam**: never held as another package's parameter or field, one implementation, no fake.

**Action:** Remove the interface and use the concrete type. Introduce the interface when a second implementation or
test double is actually needed.

**Report table:**

| # | Location | Interface | Implementations | Severity | Impact | Action |
| - | -------- | --------- | --------------- | -------- | ------ | ------ |
| 1 | file.go:line | `Processor` | 1 (no test doubles) | Medium | Medium | Remove, use concrete type |

### Channel & Goroutine Overuse

Concurrency patterns more complex than the problem requires. A mutex protecting a map is simpler than a
channel-based worker pattern for simple state.

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

Beyond the shared channels (SKILL.md Terms): Go build tags (`//go:build`, `// +build`).

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

## Error-handling note

Idiomatic `if err != nil` repetition is not complexity (complements the shared Error handling Not-a-finding). Flag only
when error handling creates genuinely deep indentation or duplicated non-trivial construction/wrapping logic.

## Phase 2 — complexity scans

Restore the eligible list first: `GO_FILES=$(cat <run>/go.txt); [ -n "$GO_FILES" ] || exit 1`.

```bash
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Deep nesting (4+ indentation levels, tab-indented)
rg -H '^\t{4,}\S' --type go $EXCLUDE -- $GO_FILES

# Boolean parameters
rg -H --pcre2 '\w+\s+bool[,)]' --type go $EXCLUDE -- $GO_FILES

# Functions with many parameters
rg -H --pcre2 'func\s+(\(\w+\s+\*?\w+\)\s+)?\w+\([^)]{80,}\)' --type go $EXCLUDE -- $GO_FILES

# Interfaces with single implementation (Interface Pollution candidates)
rg -H 'type\s+\w+\s+interface' --type go $EXCLUDE -- $GO_FILES

# Unused unexported functions (Dead Code candidates)
rg -H 'func\s+[a-z]\w+\(' --type go $EXCLUDE -- $GO_FILES

# Channel complexity / goroutine launches (Channel & Goroutine Overuse)
rg -H 'chan\s+chan|<-\s*<-' --type go $EXCLUDE -- $GO_FILES
rg -H 'go\s+func|go\s+\w+\(' --type go $EXCLUDE -- $GO_FILES

# Reinvented-primitive candidates: hand-rolled forms, not existing uses (confirm toolchain + parity before reporting)
rg -H -U --pcre2 'for _, (\w+) := range [^{]+\{\s*\n\s*if \1 == ' --type go $EXCLUDE -- $GO_FILES  # slices.Contains / Index
rg -H 'errors\.Unwrap\(' --type go $EXCLUDE -- $GO_FILES                                        # errors.Is / As walk
rg -H --pcre2 '\w+\s*=\s*append\(\w+,\s*err\)' --type go $EXCLUDE -- $GO_FILES                  # errors.Join
```

## Phase 3 — Duplication list and exclude

Run in the same call as the Phase 2 `EXCLUDE` line (shell state does not persist between calls).

```bash
DUP_EXCLUDE="$EXCLUDE --glob !**/*_test.go"
# Seeds: codebase mode ($GO_FILES is .) enumerates; diff and path mode filter the eligible list.
if [ "$GO_FILES" = . ]; then DUP_FILES=$(rg --files --type go $DUP_EXCLUDE .)
else DUP_FILES=$(printf '%s\n' $GO_FILES | grep -v '_test\.go$'); fi
```
