# Simplicity Hunter — Go reference

Contents: Generated-code eligibility · Language-only categories · Reinvented Primitives · Dead code — ownership and liveness hooks · Coexisting Generations — Go carve-outs and Phase 4 · Error-handling note · Phase 2 — complexity scans · Phase 3 — Duplication list and exclude

## Generated-code eligibility

**Marker:** a `// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs: `*.pb.go` /
`*_gen.go` / `*_generated.go`. **Vendored:** `vendor/`.

## Language-only categories

### Interface Pollution

Interfaces created for theoretical extensibility rather than actual need.

**Signals:**

- Interface with one implementation and no test double
- Interface that mirrors a concrete struct's full method set

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
- Goroutine its launcher waits for on the next line (`go f()` then `<-done` or `wg.Wait()`)
- Worker pool for a bounded, predictable workload — not when the pool caps concurrency for a limit outside the process
  (a rate limit, a connection pool)
- Channel of channels (metachannel)
- `select` with a single case and no timeout

**Action:** Use the simplest concurrency primitive that works. Mutex for state, channel for communication, goroutine
for actual parallelism.

**Report table:**

| # | Location | Pattern | Simpler Alternative | Severity | Impact | Action |
| - | -------- | ------- | ------------------- | -------- | ------ | ------ |
| 1 | file.go:line | Channel for shared counter | `sync/atomic` | Medium | Medium | Replace |

## Reinvented Primitives

**Version source:** `go.mod` `go` directive (or documented toolchain). A primitive not in the table is gated by the
first `$(go env GOROOT)/api/go1.N.txt` file that lists it.

| Primitive | Toolchain gate |
| --------- | -------------- |
| `errors.Join` | Go 1.20+ |
| `slices.Contains`, `slices.Index`, `slices.Clone`, `slices.DeleteFunc`, `maps.Clone`, `maps.DeleteFunc` | Go 1.21+ |
| `maps.Keys`, `maps.Values`, `slices.Collect`, `slices.Sorted` | Go 1.23+ |

**Signals:** loops that replicate `slices.Contains` / `slices.Index`, `slices.Clone` / `maps.Clone`,
`slices.DeleteFunc` / `maps.DeleteFunc`, or that collect a map's keys or values (`slices.Collect(maps.Keys(m))`,
`slices.Sorted(maps.Keys(m))`); re-implemented `errors.Is` / `errors.As` walks, or hand-rolled multi-error aggregation
where `errors.Join` applies.

**Carve-out:** `strings.Builder` is deliberately **excluded** — it is a performance transformation, usually increases
source-level complexity, and carries a do-not-copy-a-non-zero-Builder constraint.

## Dead code — ownership and liveness hooks

**Ownership:** `_ = x` on a non-error binding, unused parameters, and unused struct fields are slop-hunter's;
`_ = f()` on an error is invariant-hunter's Unchecked Errors. A nil guard the preceding logic already guarantees is
here: Go has no non-optional pointer type, so invariant-hunter's Defensive Access does not apply.

**Liveness hooks** beyond the shared channels (SKILL.md Terms): build tags (`//go:build`, `// +build`); `init`;
`//go:linkname`; cgo `//export`; a run-time interface check (`x.(interface{ validate() error })`) that calls an
unexported method — after the method is deleted the code still compiles, and the call silently stops.

## Coexisting Generations — Go carve-outs and Phase 4

**/vN carve-out.** Exempt only when the governing `go.mod` — root or nested — declares a `module` path whose final
element is the matching `/vN` (Go's major-version module rule from v2 onward). Neither a directory *named* `v2` nor the
mere presence of a nested `go.mod` proves a major-version module.

**Nomination signals:** overlapping `go.mod` dependencies solving one concern; `io/ioutil` beside `os` / `io`;
`golang.org/x/exp/slices` or `golang.org/x/exp/maps` beside the stdlib `slices` / `maps`; `// Deprecated:` on symbols
with live importers; `legacy/` / `old/` package directories whose older path still has importers; two or more role
types for the same concept, all still constructed somewhere; environment- or config-selected parallel implementations
where both branches are reachable.

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

**Linter rules** (golangci-lint): revive `argument-limit` and `flag-parameter` → Over-Parameterized APIs; `funlen` →
Mixed Concerns; `gocognit`, `nestif` → Complex Control Flow; `dupl` → Duplication; `unused` → Dead Code Paths.
golangci-lint takes packages, not a list of files: run it on the packages that hold the eligible files.

**Modernizer** (Go 1.26+ toolchain): `go fix -diff -slicescontains -mapsloop ./...` prints a patch and edits nothing.
It checks the Go version of each file, which satisfies the toolchain gate, and skips generated files; it exits 1 when
the patch is not empty. Each hunk in the eligible list nominates Reinvented Primitives.

**Regex scans.** Restore the eligible list first: `GO_FILES=$(cat <run>/go.txt); [ -n "$GO_FILES" ] || exit 1`.

```bash
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Deep nesting (4+ tabs: 3 levels inside a function)
rg -Hn '^\t{4,}\S' --type go $EXCLUDE -- $GO_FILES

# Boolean parameters (one-line signatures)
rg -Hn --pcre2 '^func\s+(\([^)]*\)\s*)?\w+(\[[^\]]*\])?\([^)]*\b\w+\s+bool[,)]' --type go $EXCLUDE -- $GO_FILES

# Functions with 4+ parameters (counts commas; one-line or split signatures)
rg -Hn -U --pcre2 'func\s+(\([^)]*\)\s*)?\w+(\[[^\]]*\])?\((?:(?:[^()\[\],]|\([^()]*\)|\[[^\[\]]*\])*,){3,}\s*[^\s)]' --type go $EXCLUDE -- $GO_FILES

# Interfaces (Interface Pollution candidates: count implementations)
rg -Hn 'type\s+\w+\s+interface' --type go $EXCLUDE -- $GO_FILES

# Unexported functions and methods whose name appears once in the repository (Dead Code candidates)
rg -oNI '\b[a-z_]\w*\b' --type go . | sort | uniq -c | awk '$1 == 1 {print $2}' > <run>/once.txt
rg -Hno --pcre2 '^func\s+(\([^)]*\)\s*)?\K[a-z_]\w*' --type go $EXCLUDE -- $GO_FILES | awk -F: 'NR == FNR {once[$1]; next} $3 in once' <run>/once.txt -

# Channel complexity; goroutines the launcher waits for on the next line (Channel & Goroutine Overuse)
rg -Hn 'chan\s+chan|<-\s*<-' --type go $EXCLUDE -- $GO_FILES
rg -Hn -U --pcre2 '(\bgo\s+[\w.]+\(.*\)|^\s*\}\(.*\))\s*\n\s*(<-\s*\w|\w+\.Wait\(\))' --type go $EXCLUDE -- $GO_FILES

# Reinvented-primitive candidates: hand-rolled forms, not existing uses (confirm toolchain + parity before reporting)
rg -Hn -U --pcre2 'for _, (\w+) := range [^{]+\{\s*\n\s*if \1 == ' --type go $EXCLUDE -- $GO_FILES  # slices.Contains / Index
rg -Hn 'errors\.Unwrap\(' --type go $EXCLUDE -- $GO_FILES                                        # errors.Is / As walk
rg -Hn --pcre2 '\w+\s*=\s*append\(\w+,\s*err\)' --type go $EXCLUDE -- $GO_FILES                  # errors.Join
```

## Phase 3 — Duplication list and exclude

Run in the same call as the Phase 2 `EXCLUDE` line (shell state does not persist between calls).

```bash
DUP_EXCLUDE="$EXCLUDE --glob !**/*_test.go"
# Seeds: codebase mode ($GO_FILES is .) enumerates; diff and path mode filter the eligible list.
if [ "$GO_FILES" = . ]; then DUP_FILES=$(rg --files --type go $DUP_EXCLUDE .)
else DUP_FILES=$(printf '%s\n' $GO_FILES | grep -v '_test\.go$'); fi
```
