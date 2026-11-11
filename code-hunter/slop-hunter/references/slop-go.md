# Slop Hunter — Go reference

Contents: Generated-code eligibility · Language-only categories · Per-category Go markers · Delegated to tools · Idiom calibration · Phase 2 — slop scans · Phase 3 — Go-specific evaluation

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

**Ownership:** slop-hunter owns *redundancy* of the wrapping messages; exception-hunter owns a dropped cause (Broken
Error Chains), matching (Unmatchable Failures), and a message that names no input (Poor Error Context). They compose:
wrap with the cause, wrap once, match by identity.

**With Style Drift:** a redundant wrap that also uses another wrapping library than the project's is one
Unnecessary Error Wrapping row. If its Action keeps a wrap, the wrap uses the project's library. That call gets no
Style Drift row.

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

- Error variable named `error`, `e`, or `ex` where the project uses `err`
- `Create*` constructors where the project uses `New*`, or the reverse
- Receiver naming that breaks the project's pattern (single-letter vs. word)
- A different error-wrapping library than the project's (`errors.Wrap` where the project uses `fmt.Errorf("…: %w")`)
- Idioms from other languages: `GetX()` for `X()`, `toString()` for `String()`

### Trivially Dead Code

- `_ = x` silencing a non-error binding the author meant to use
- Bare `//nolint` or `//nolint:<linter>` with no trailing `// reason`; bare `// #nosec` or `// #nosec <rule>`
- `TODO` / `FIXME` without owner, ticket, or condition

Not a finding: `import _ "pkg"` for side effects; `var _ Iface = (*T)(nil)` compile-time assertions; `_ = x` where
the project's lint config requires it for an intentionally ignored return.

### Hedging and Narration

Narration logging: `log.Print*` / `log.*` / `slog.*` / `zap` / `logrus` calls whose message is `entering`,
`exiting`, `starting`, `finished`, `begin`, `end`, `here`, or a function name with no operational payload.

## Delegated to tools

- golangci-lint: unformatted code (formatter `gofmt` or `gofumpt`); import grouping (formatter `gci` with the
  project's sections, or `goimports` with `local-prefixes`); naming case and initialisms such as `userId` (staticcheck
  `ST1003`); commented-out code (gocritic `commentedOutCode`); unused parameters (revive `unused-parameter`); unused
  struct fields (`unused`); a `//nolint` that suppresses nothing (`nolintlint` with `allow-unused: false`).

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
D '.*//\s*(nolint|#nosec)'                                     # suppressions (check for a trailing reason)
D '\s*_\s*=\s*\w'                                              # blank-identifier silencing
D '.*fmt\.Errorf\("(error|failed|err|[A-Z]\w+: )'               # error-wrapping candidates
D '.*(log|slog|logger|zap|logrus)\.\w+\(\s*"(entering|exiting|starting|finished|begin|end|here)'   # narration
D '.*(?i)(might need|for safety|new, improved|improved version)'                                   # hedging

# ---- Whole-file scans ----
# path / codebase: F=$GO_FILES    diff (untracked files): F=$(git ls-files --others --exclude-standard -- $GO_FILES)
W() { [ -z "$F" ] || rg -nH "$@" -- $F; }                       # empty F must not search the whole tree
W '^\s*//'                                                     # comments (classify manually)
W -B1 '^func\s+(\([^)]*\)\s*)?[a-z]'                           # godoc on unexported functions and methods
W '\b(TODO|FIXME|XXX)\b'
W '//\s*(nolint|#nosec)'
W '^\s*_\s*=\s*\w'
W 'fmt\.Errorf\("(error|failed|err|[A-Z]\w+: )'
W '(log|slog|logger|zap|logrus)\.\w+\(\s*"(entering|exiting|starting|finished|begin|end|here)'
W -i 'might need|for safety|new, improved|improved version'
```

## Phase 3 — Go-specific evaluation

For each `fmt.Errorf` candidate:

- Does the message add something the caller cannot infer — the operation, the resource, an identifier? If it only
  says "error" or "failed", it is redundant.
- Is the inner error already wrapped with the same context one frame down? Report the outer wrap.
- Is `%v` used where a caller matches the chain? That is not covered here; do not score.

For each `//nolint` or `#nosec`:

- Is there a trailing reason? Bare → Trivially Dead Code. Is the suppressed linter reporting something real
  (`errcheck` on a dropped error)? Then the noise hides a finding (SKILL.md Severity). Score only the bare
  suppression; cross-reference a real gosec finding to security-hunter.

For each `_ = x`:

- Does the right-hand side return an `error`? Then it is not covered here; drop it. Otherwise: is `x` a result the author meant to use, or an intentional discard the lint config demands?

For each doc comment on an unexported symbol:

- Does it say anything the name and signature do not? If not, Verbose Documentation.
