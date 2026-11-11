# Doc Hunter — Go reference

Contents: Applicability · Generated-code and test-path eligibility · Doc-comment form · Public symbol and Library unit · Delegated to tools · Phase 2 — doc scans · Diff mode — removed symbols · Remedies · Evidence path form

## Applicability

| Category | Applicable | Go note |
| -------- | ---------- | ------- |
| Unexplained Business Rules | **yes** | Thresholds in comparisons and in `const` declarations; a source comment on the `const` covers its uses |
| Non-Obvious Algorithms | **yes** | `regexp` patterns and bit operations (`<<`, `>>`, `&^`, `^`) |
| Unexplained Workarounds | **yes** | `time.Sleep` and timers, `runtime.GOOS` branches; build-constraint files that are the normal per-platform split (`file_linux.go`) are not findings |
| Undocumented Contracts | **yes** | Sentinel and typed errors that callers match; exported types whose methods lock a mutex or use atomics; `ctx.Value` and environment reads outside `package main`. Nil semantics and zero-value contracts are invariant-hunter's; reachable panics are exception-hunter's |
| Misleading Comments and Names | **yes** | Doc links `[Name]`; struct tags as mapping sites (`IsDisabled` with `db:"is_hidden" json:"archived"`); expiry against `go.mod` |

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs such as `*.pb.go` / `*_gen.go` /
`*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`.

## Doc-comment form

From go.dev/doc/comment:

- **Attachment:** a doc comment is the comment immediately before a top-level `package`, `const`, `func`, `type`, or
  `var` declaration, with no blank line between. A comment separated by a blank line documents nothing.
- **Starts with the name:** `// Parse returns …` above `func Parse`.
- **Package comment:** `// Package x …`, once per package.
- **Booleans:** a function that returns a boolean is documented with "reports whether".
- **Deprecation:** a paragraph that starts with `Deprecated:`.
- **Doc links:** `[Name]`, `[*Name]`, `[pkg.Name]`, `[Name.Method]`; each resolves to a declaration.
- **Concurrency:** a type is assumed safe for use by one goroutine at a time. "If a type provides stronger guarantees,
  the doc comment should state them."

## Public symbol and Library unit

A public symbol is a capitalized (exported) identifier. The package comment counts once per package.

Library unit: SKILL.md Terms. A `main` package counts only when `go build` builds it: files under `testdata/`,
`vendor/`, or a directory starting with `_`, and files tagged `//go:build ignore` (a `go:generate` program) are not
packages of the module. Attribute each hit to its nearest `go.mod`:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
rg -H -n '^module\s' --glob '**/go.mod' -- .                                    # module path per go.mod
rg -l --type go --glob '!**/vendor/**' --glob '!**/testdata/**' --glob '!**/_*/**' --glob '!**/*_test.go' \
  '^package main$' -- . | xargs -r rg --files-without-match '^//go:build ignore'          # main packages
```

## Delegated to tools

- golangci-lint: a numeric literal with no name (`mnd`); an exported symbol's doc comment that does not start with
  its name, as when it names another symbol (staticcheck `ST1020`, `ST1021`, `ST1022`).
- golangci-lint's `revive`, only when a Library unit is in scope (SKILL.md Terms): an exported symbol or a package
  with no doc comment (`exported`, `package-comments`).

## Phase 2 — doc scans

`$GO_FILES` is this language's eligible list, restored from `<run>/go.txt` (SKILL.md Phase 1 step 4).

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
GO_FILES=$(cat <run>/go.txt); [ -n "$GO_FILES" ] || exit 1          # STOP: empty restore
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Non-Obvious Algorithms: regular expressions, bit operations
rg -H -n 'regexp\.(MustCompile|Compile|MatchString|Match)(POSIX)?\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n '<<|>>|&\^|\^' --type go $EXCLUDE -- $GO_FILES

# Unexplained Workarounds: delays and timers, platform branches, comments that call the code a hack or a workaround
# (whatever the marker: `// XXX: workaround …` matches)
rg -H -n 'time\.(Sleep|After|NewTimer|NewTicker|Tick)\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n 'runtime\.(GOOS|GOARCH|Version)' --type go $EXCLUDE -- $GO_FILES
rg -H -n '//.*(?i)\b(hack|work ?around)\b' --type go $EXCLUDE -- $GO_FILES

# Undocumented Contracts: hidden inputs and concurrency
# (read whether the field sits on an exported type)
rg -H -n 'ctx\.Value\(|os\.(Getenv|LookupEnv)\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n 'sync\.(RW)?Mutex|atomic\.' --type go $EXCLUDE -- $GO_FILES

# Misleading Comments and Names: doc links in comment lines (resolve each by name); expiry conditions
rg -H -n '//.*\[\*?(\w+\.)?[A-Z]\w*(\.\w+)?\]' --type go $EXCLUDE -- $GO_FILES
rg -H -n '//.*(?i)\b(until|after|once|remove|drop|when)\b.*(\bv?\d+\.\d+(\.\d+)?\b|\b\d{4}-\d{2}(-\d{2})?\b)' --type go $EXCLUDE -- $GO_FILES
```

**Expiry.** A comment needs a condition word and a version or a date, so "retry after network failure" is not
nominated. A version is compared with the module's `require` line in `go.mod`; a `replace` of the same module makes it
unresolved: no finding. A date is compared with today's date.

**Blind spots:**

- A bare `&` is address-of, so the bit-operation scan leaves it out.
- No scan nominates a defect comment without the words "hack" or "workaround" (`// XXX: Safari drops the event`), a
  business rule, a comparator, a third-party call order, a side effect, or a name that the body contradicts. Reading
  finds them.

## Diff mode — removed symbols

Declaration patterns, applied to the removed lines of `git diff -U0 "$MB"` (`references/diff-mode.md`) and, without the
leading `-`, to each deleted `.go` path at the merge base:

- `^-func (\([^)]*\) )?(\w+)` — functions and methods; a method's identity is `Type.Method`.
- `^-type (\w+)`.
- `^-(const|var) (\w+)` — single-line declarations.
- `^-\s*(\w+)\s*=` inside `const` and `var` groups.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
MB=$(cat <run>/mb); [ -n "$MB" ] || exit 1                          # STOP: empty restore
GO_FILES=$(cat <run>/go.txt 2>/dev/null)                            # none in a deletions-only run
[ -z "$GO_FILES" ] || git diff -U0 "$MB" -- $GO_FILES | rg '^\+\+\+ |^-func (\([^)]*\) )?(\w+)|^-type (\w+)|^-(const|var) (\w+)|^-\s*(\w+)\s*='
git show "$MB:<deleted path>" | rg -n '^func (\([^)]*\) )?(\w+)|^type (\w+)|^(const|var) (\w+)|^\s*(\w+)\s*='   # once per deleted .go path

# References to one removed name in the repository's Go comments. NAME is the name, or Type\.Method for a method.
rg -H -n --type go "//.*(\[\*?(\w+\.)?$NAME\]|\`$NAME\`)" -- .
# A bare word counts only when the name has an inner capital, an underscore, or a digit
rg -H -n --type go "//.*\b$NAME\b" -- .
```

## Remedies

- **Constants:** typed and named, the unit in the type (`const pollEvery = 200 * time.Millisecond`,
  `const retryBackoff = 1.5`).
- **Doc comments:** in the forms above — the name first, "reports whether" for a boolean, a `Deprecated:` paragraph,
  doc links that resolve, and the concurrency guarantee on a type that provides one.

## Evidence path form

Location is `file:line`. A symbol is `pkg.Type.Method` (`store.Store.Close`), or `pkg.Func`.
