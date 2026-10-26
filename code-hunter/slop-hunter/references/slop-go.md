# Slop Hunter — Go reference

Contents: Generated-code eligibility · Language-only categories · Per-category Go markers · Formatter · Idiom calibration · Phase 2 — slop scans · Phase 5 — Go-specific evaluation

## Generated-code eligibility

Generated-code marker: a `// Code generated … DO NOT EDIT.` line before the first non-comment text. Vendored trees
(`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible. Test files (`*_test.go`) are
eligible.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
CANDIDATES=$(cat <run>/scope.txt)              # diff / path: already a file list
# codebase:  CANDIDATES=$(rg --files --type go)
GO_FILES=$(printf '%s\n' $CANDIDATES | rg '\.go$' | rg -v '^vendor/|/vendor/|(^|/)testdata/' \
  | while read -r f; do rg -q -m1 '^// Code generated .* DO NOT EDIT\.$' "$f" || echo "$f"; done)
[ -n "$GO_FILES" ] && printf '%s\n' "$GO_FILES" > <run>/go.txt   # no eligible Go file → no go.txt, no Go scans
```

## Language-only categories

### Unnecessary Error Wrapping

Error wrapping that adds words, not context.

**Signals:**

- `return fmt.Errorf("error: %w", err)` — the word "error" adds nothing
- `return fmt.Errorf("failed to X: failed to Y: %w", err)` — the message already carries the inner context
- Wrapping at every level of the call stack, producing
  `"failed to process: failed to validate: failed to parse: invalid syntax"`
- A message repeating the function name: `func Save() { return fmt.Errorf("Save: %w", err) }`
- Wrapping a wrap at one call site: `fmt.Errorf("failed to do X: %w", fmt.Errorf("error doing X: %w", err))`

**Action:** Wrap once, where the context is meaningful — the operation or resource the caller cannot infer. Let
`errors.Is` / `errors.As` handle the chain.

**Ownership:** slop-hunter owns *redundancy* of the wrapping messages; invariant-hunter's Error Chain Correctness
owns *correctness* of the chain (`%w` vs `%v`, `Unwrap`, `errors.Is` / `errors.As`). The two compose: wrap correctly, and wrap once.

**Report table:**

| # | Location | Pattern | Severity | Impact | Action |
| - | -------- | ------- | -------- | ------ | ------ |
| 1 | store/save.go:31 | `fmt.Errorf("error: %w", err)` | Low | Low | `fmt.Errorf("save order %s: %w", id, err)` |

## Per-category Go markers

### Redundant Comments

Comment syntax is `//`. Godoc convention: a doc comment on an exported symbol starts with the symbol's name. That
opening is convention, not slop — see Verbose Documentation.

### Verbose Documentation

- Godoc on an unexported function restating its name or body
- `// param: name - the name` style parameter prose
- Godoc describing the implementation instead of the behavior
- Godoc on an interface method that restates the method name

### Style Drift

- Import grouping that breaks the project's pattern (standard library / third-party / internal)
- Error variable named `error`, `e`, or `ex` where the project uses `err`
- `Create*` constructors where the project uses `New*`, or the reverse
- Receiver naming that breaks the project's pattern (single-letter vs. word)
- A different error-wrapping library than the project's (`errors.Wrap` where the project uses `fmt.Errorf("…: %w")`)
- Idioms from other languages: `GetX()` for `X()`, `toString()` for `String()`, `userId` for `userID`
- `gofmt` output on touched lines (see Formatter)

### Trivially Dead Code

Go's compiler rejects unused imports and unused local variables, so those never appear in compiling code and
`//nolint` cannot hide them. What Go does allow:

- `_ = x` silencing a non-error binding the author meant to use
- Unused function parameters (after a refactor)
- Unused struct fields
- Bare `//nolint` or `//nolint:<linter>` with no trailing `// reason`
- Commented-out code; `TODO` / `FIXME` without owner, ticket, or condition

Not a finding: `import _ "pkg"` for side effects; `var _ Iface = (*T)(nil)` compile-time assertions; `_ = x` where
the project's lint config requires it for an intentionally ignored return; a parameter whose signature is fixed by an
interface, function type, or callback (`ServeHTTP(w, r)` that ignores `r`); a struct field that carries a struct tag
or is exported — reflection and other packages read it.

### Hedging and Narration

Narration logging: `log.Print*` / `log.*` / `slog.*` / `zap` / `logrus` calls whose message is `entering`,
`exiting`, `starting`, `finished`, `begin`, `end`, `here`, or a function name with no operational payload.

## Formatter

**Adoption:** always — `gofmt` is canonical and needs no adoption evidence.

**Execution:** `gofmt -l $GO_FILES`. Passing the eligible list is the exclusion mechanism; `gofmt -l .` would list
vendored and generated files. Not installed means `gofmt` is not on `PATH`. A parse error is `errored`.

In diff mode, `gofmt -d <file>` gives the violating lines. Convention cell: `gofmt, touched line`.

`goimports` is not `gofmt`: treat it as a formatter only when the project invokes it, then run `goimports -l`.

## Idiom calibration

Baseline rung 4 (the Style Drift order in SKILL.md): Effective Go and the Go Code Review Comments wiki. `gofmt`
output is not a style choice.

Repeated `if err != nil` is Go working as designed, never drift.

## Phase 2 — slop scans

```bash
# ---- Every call: restore run state ----
cd "$(git rev-parse --show-toplevel)" || exit 1
GO_FILES=$(cat <run>/go.txt); [ -n "$GO_FILES" ] || exit 1   # STOP: empty restore

# ---- Diff mode: added lines only ----
MB=$(cat <run>/mb); [ -n "$MB" ] || exit 1                     # STOP: empty restore
# Patterns are anchored right after the leading +; start with .* to match anywhere on the line.
D() { git diff -U0 "$MB" -- $GO_FILES | rg "^\+\+\+ |^@@|^\+($1)"; }

D '\s*//'                                                      # comments and godoc (classify manually)
D '.*\b(TODO|FIXME|XXX)\b'                                     # placeholder markers
D '.*//\s*nolint'                                              # suppressions (check for a trailing reason)
D '\s*_\s*=\s*\w'                                              # blank-identifier silencing
D '.*fmt\.Errorf\("(error|failed|err|[A-Z]\w+: )'               # error-wrapping candidates
D '.*(log|slog|logger|zap|logrus)\.\w+\(\s*"(entering|exiting|starting|finished|begin|end|here)'   # narration
D '.*(?i)(might need|for safety|new, improved|improved version)'                                   # hedging

# Removed lines, with file and hunk headers: a removed use of a parameter or struct field nominates a Phase 4 candidate
git diff -U0 "$MB" -- $GO_FILES | rg '^(\+\+\+ |@@|-)' | rg -v '^--- (a/|/dev/null)'

# ---- Whole-file scans ----
# path / codebase: F=$GO_FILES    diff (untracked files): F=$(git ls-files --others --exclude-standard -- $GO_FILES)
W() { [ -z "$F" ] || rg -nH "$@" -- $F; }                       # empty F must not search the whole tree
W '^\s*//'                                                     # comments (classify manually)
W -B1 '^func\s+(\([^)]*\)\s*)?[a-z]'                           # godoc on unexported functions and methods
W '\b(TODO|FIXME|XXX)\b'
W '//\s*nolint'
W '^\s*_\s*=\s*\w'
W 'fmt\.Errorf\("(error|failed|err|[A-Z]\w+: )'
W '(log|slog|logger|zap|logrus)\.\w+\(\s*"(entering|exiting|starting|finished|begin|end|here)'
W -i 'might need|for safety|new, improved|improved version'

# ---- Formatter (Phase 3) ----
gofmt -l $GO_FILES
```

## Phase 5 — Go-specific evaluation

For each `fmt.Errorf` candidate:

- Does the message add something the caller cannot infer — the operation, the resource, an identifier? If it only
  says "error" or "failed", it is redundant.
- Is the inner error already wrapped with the same context one frame down? Report the outer wrap.
- Is `%v` used where the chain needs `%w`? That is invariant-hunter's Error Chain Correctness — cross-reference, do
  not score.

For each `//nolint`:

- Is there a trailing reason? Bare → Trivially Dead Code. Is the suppressed linter reporting something real
  (`errcheck` on a dropped error)? Then the noise hides a finding (SKILL.md Severity). Score only the bare
  suppression; cross-reference the dropped error to invariant-hunter's Unchecked Errors.

For each `_ = x`:

- Does the right-hand side return an `error`? Then it is invariant-hunter's Unchecked Errors — cross-reference, do
  not score. Otherwise: is `x` a result the author meant to use, or an intentional discard the lint config demands?

For each doc comment on an unexported symbol:

- Does it say anything the name and signature do not? If not, Verbose Documentation.
