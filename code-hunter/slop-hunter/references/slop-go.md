# Slop Hunter — Go reference

Language-specific rules for Go. Every universal category applies; one language-only category is added below.

## Generated-code eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. **Never** guess by filename. Scan globs
such as `*.pb.go` / `*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the
marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

Slop-hunter runs no scan globs: `$GO_FILES` is the eligible list itself, so `foo_gen.go` without a marker is scanned
and a marked file is not. Test files (`*_test.go`) are eligible.

```bash
# Diff / path mode: filter the manifest. Codebase mode: enumerate first.
# [ codebase ] CANDIDATES=$(rg --files --type go -- .)
GO_FILES=$(printf '%s\n' $CANDIDATES | rg '\.go$' | rg -v '^vendor/|/vendor/|(^|/)testdata/' \
  | while read -r f; do rg -q -m1 '^// Code generated .* DO NOT EDIT\.$' "$f" || echo "$f"; done)
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

Exported symbols keep their summary line (`// Foo does …` is the convention). Strip only what restates the
signature beyond it.

### Style Drift

- Import grouping that breaks the project's pattern (standard library / third-party / internal)
- Error variable named `error`, `e`, or `ex` where the project uses `err`
- `Create*` constructors where the project uses `New*`, or the reverse
- Receiver naming that breaks the project's pattern (single-letter vs. word)
- A different error-wrapping library than the project's (`errors.Wrap` where the project uses `fmt.Errorf("…: %w")`)
- Idioms from other languages: `GetX()` for `X()`, `toString()` for `String()`, `userName` for `username`
- `gofmt` output on touched lines (see Formatter)

**Ownership:** naming drift introduced by the change is here; *stuttering* (`user.UserName`) as a package-design
smell is smell-hunter's Stuttering Names.

### Trivially Dead Code

Go's compiler rejects unused imports and unused local variables, so those never appear in compiling code and
`//nolint` cannot hide them. What Go does allow:

- `_ = x` silencing a non-error binding the author meant to use — here. `_ = f()` where `f` returns an `error` is
  invariant-hunter's Unchecked Errors
- Unused function parameters (after a refactor) — here
- Unused struct fields — here
- Bare `//nolint` or `//nolint:<linter>` with no trailing `// reason`
- Commented-out code; `TODO` / `FIXME` without owner, ticket, or condition

Not a finding: `import _ "pkg"` for side effects; `var _ Iface = (*T)(nil)` compile-time assertions; `_ = x` where
the project's lint config requires it for an intentionally ignored return.

Unused functions and constants → simplicity-hunter Dead Code Paths. Exported dead symbols → boundary-hunter.

### Hedging and Narration

Narration logging: `log.Print*` / `log.*` / `slog.*` / `zap` / `logrus` calls whose message is `entering`,
`exiting`, `starting`, `finished`, `begin`, `end`, `here`, or a function name with no operational payload.

## Formatter

**Adoption:** `gofmt` is canonical. It runs on every Go file with no adoption evidence required — the Go exception to
the adoption rule.

**Execution:** `gofmt -l $GO_FILES`. Passing the eligible list is the exclusion mechanism; `gofmt -l .` would list
vendored and generated files. If `gofmt` is not on `PATH`, record `skipped — gofmt not installed`. A non-zero exit
with a parse error is `errored — <message>`.

In diff mode, `gofmt -d <file>` gives the violating lines; keep only those inside a `@@` range of
`git diff -U0 "$MB" -- <file>`. Convention cell: `gofmt, touched line`.

`goimports` is not `gofmt`: treat it as a formatter only when the project invokes it, then run `goimports -l`.

## Idiom calibration

Precedence: `gofmt` > project conventions > Effective Go and the Go Code Review Comments wiki. `gofmt` is not a
style choice. Project conventions (naming, error handling, import grouping) come next. Fall back to standard Go
idioms only when the project has no established convention; when it has none and the guide is silent, record
`baseline uncertain`.

Repeated `if err != nil` is Go working as designed, never drift. A `//nolint` with a reason is a decision, not slop.

## Evidence path form

Cite findings as `file/path.go:line`.

## Phase 2 — slop scans

All scans take `$GO_FILES`. Diff mode keeps `@@` hunk headers so each `+` line maps to a working-tree line number;
untracked files have no diff and use the path-mode commands.

```bash
# ---- Diff mode: added lines only ----
# Patterns are anchored right after the leading +; start with .* to match anywhere on the line.
D() { git diff -U0 "$MB" -- $GO_FILES | rg "^@@|^\+($1)"; }

D '\s*//'                                                      # comments and godoc (classify manually)
D '.*\b(TODO|FIXME|HACK|XXX)\b'                                # placeholder markers
D '.*//\s*nolint'                                              # suppressions (check for a trailing reason)
D '\s*_\s*=\s*\w'                                              # blank-identifier silencing
D '.*fmt\.Errorf\("(error|failed|err|[A-Z]\w+: )'               # error-wrapping candidates
D '.*(log|slog|logger|zap|logrus)\.\w+\(\s*"(entering|exiting|starting|finished|begin|end|here)'   # narration
D '.*(?i)(workaround|might need|for safety|new, improved|improved version)'                        # hedging

# Removed lines: a removed use of a still-imported package nominates a Phase 4 candidate
git diff -U0 "$MB" -- $GO_FILES | rg '^-' | rg -v '^---'

# ---- Path / codebase mode: whole eligible files ----
rg -n '^\s*//' -- $GO_FILES                                    # comments (classify manually)
rg -n -B1 '^func\s+[a-z]' -- $GO_FILES                         # godoc on unexported functions
rg -n '\b(TODO|FIXME|HACK|XXX)\b' -- $GO_FILES
rg -n '//\s*nolint' -- $GO_FILES
rg -n '^\s*_\s*=\s*\w' -- $GO_FILES
rg -n 'fmt\.Errorf\("(error|failed|err|[A-Z]\w+: )' -- $GO_FILES
rg -n '(log|slog|logger|zap|logrus)\.\w+\(\s*"(entering|exiting|starting|finished|begin|end|here)' -- $GO_FILES
rg -n -i 'workaround|might need|for safety|new, improved|improved version' -- $GO_FILES

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
  (`errcheck` on a dropped error)? Severity Medium: the noise hides a finding.

For each `_ = x`:

- Does the right-hand side return an `error`? Then it is invariant-hunter's Unchecked Errors — cross-reference, do
  not score. Otherwise: is `x` a result the author meant to use, or an intentional discard the lint config demands?

For each doc comment on an unexported symbol:

- Does it say anything the name and signature do not? If not, Verbose Documentation.

For each drifted name:

- Is it introduced by the change (here) or a package-wide stutter (smell-hunter)?
