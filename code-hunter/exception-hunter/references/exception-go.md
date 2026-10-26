# Exception Hunter — Go reference

Contents: Applicability · Generated-code and test-path eligibility · Language facts and version gates · Not a finding on these grounds alone — Go · Transport frameworks · Detectors · Phase 3 — exception scans · Phase 5 — Go-specific evaluation

## Applicability

| Category | Applicable | Go note |
| -------- | ---------- | ------- |
| Swallowed Errors | **yes** | `_ = f()` on an error; an error return ignored by arity (errcheck); an empty `if err != nil {}`; a nil error returned after `err != nil`; `defer x.Close()` on a write path; `rows.Err()` / `scanner.Err()` not read; a named `err` overwritten in a `defer` |
| Orphaned Async Failures | **yes** | `go f()` where `f` returns an error; an `errgroup.Group` whose `Wait()` result is discarded |
| Overbroad Handling | **yes** | `if err != nil` mapped to a not-found sentinel with no `errors.Is`; cancellation logged at error level; retry wrappers |
| Broken Error Chains | **yes** | `%v` with a matching caller; a wrapping type with no `Unwrap()`; `errors.New(err.Error())` |
| Unmatchable Failures | **yes** | text matching; `==` or a type assertion on a wrapped error; string and nil sentinels; a typed nil (SA4023) |
| Untranslated Boundary Errors | **yes** | driver sentinels and types outside the adapter; `http.Status*` and `codes.*` mappings |
| Double Handling | **yes** | log and return |
| Poor Error Context | **yes** | an error from another package returned unchanged; fixed `errors.New` / `fmt.Errorf` text |
| Panic and Exit Misuse | **yes** | `panic`, `recover`, `log.Fatal`, `os.Exit`, `Must*` |

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs such as `*.pb.go` /
`*_gen.go` / `*_generated.go` are approximations for scanning convenience; eligibility uses the marker.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*_test.go`.

## Language facts and version gates

The version is the `go` directive in `go.mod`. A remedy is proposed only when that version supports it.

- `%w`, `errors.Is`, and `errors.As`: Go 1.13.
- `errors.Join`, and several `%w` in one `fmt.Errorf`: Go 1.20.
- `errors.AsType`: Go 1.26.

## Not a finding on these grounds alone — Go

- **`_ = f()` with a justifying comment that the code confirms** — `Close` on a file opened read-only, a logger
  flush. The comment is evidence to verify, not an exemption: *is* a finding on a write path whatever the comment
  says, and with no comment.
- **`recover` at the top of a goroutine or in request middleware** that turns a panic into an error response.
- **`panic` in `init()` or in constructors when the project's instructions endorse it.** Cite the policy in Scope.
  *Is* a finding when external input reaches it, whatever the policy.
- **`err == io.EOF` after a direct `io.Reader.Read`**: the `io.Reader` contract returns `io.EOF` unwrapped, and a wrap
  around it breaks callers.
- **`bytes.Buffer`, `strings.Builder`, and `hash.Hash` writes**: they cannot fail by contract.
- **A wrap that repeats `*os.PathError`** (`fmt.Errorf("open %s: %w", path, err)` around `os.Open(path)`): the inner
  error already names the operation and the path. The repeated words are slop-hunter's Unnecessary Error Wrapping.
- **A dropped error from writing an HTTP response body** (`fmt.Fprintf(w, …)`, `w.Write(…)`): the first write has
  committed the status.

## Transport frameworks

- **`net/http`**: a handler writes its status itself and returns no error, so `net/http` does not log a returned
  error. It recovers handler panics on the serving goroutine; `http.ErrAbortHandler` is a panic it uses on purpose to
  abort a response, and a recovery middleware must re-panic it.
- **gin**: `gin.Recovery()` recovers panics; `c.Error(err)` attaches an error for a middleware to map.
- **echo**: `HTTPErrorHandler` maps every returned error to a response.
- **gRPC**: `status.Error(codes.X, …)` sets the code. There is no built-in panic recovery: a recovery interceptor is
  needed.
- **connect-go**: `connect.NewError(connect.CodeX, err)` sets the code.

## Detectors

Checked on golangci-lint 2.12.2, go1.26.8. Each runs with the project's flags and config, read-only.

**go vet**, when a Go toolchain is on `PATH` and packages load: vet is part of the standard toolchain. It takes
packages as golangci-lint's "Packages, not files" bullet says.

```bash
cd <module directory> || exit 1
GOPROXY=off go vet -errorsas -unusedresult -unusedresult.funcs=errors.New,fmt.Errorf <package dirs>
```

- `errorsas` reports a non-pointer or non-error target of `errors.As` → Unmatchable Failures.
- `unusedresult` nominates `never-raised` (Swallowed Errors). Its default list also holds `fmt.Sprintf`,
  `context.WithCancel`, and most of `slices` and `maps`, so the flag narrows it to the two error constructors. A
  discarded `context.WithCancel` is invariant-hunter's Context Misuse.
- `GOPROXY=off` stops the go command from downloading missing modules: a load failure is `errored`, never a fetch.

**errcheck**, standalone (the project's own invocation: a Makefile target, a CI step) or in golangci-lint's enabled
set (its entry is then `ran — in golangci-lint`), with the project's flags. Options that change what it sees are
part of the Scope line: `-blank` (off by default: blank assignments are then *not* checked), `-asserts`, `-exclude`
lists.

**golangci-lint** runs only when the project configures it (`.golangci.yml`, `.yaml`, `.toml`, `.json`), in each
module directory (each `go.mod`).

- **Enabled set:** the error-relevant linters below among those `golangci-lint linters` lists under "Enabled by your
  configuration linters". An empty set → `skipped — no error-relevant rules enabled`. `--enable-only` with a linter
  outside the configured set would enable it, so it gets only configured linters.
- **New issues only:** when the project config sets `issues.new`, `new-from-rev`, `new-from-merge-base`, or
  `new-from-patch`, the run reports only new issues. Record `ran — new issues only`.
- **Packages, not files:** golangci-lint runs on packages. Codebase mode passes `./...`; diff and path mode pass the
  directories of `$GO_FILES`. Every mode keeps only the issues whose file is in `$GO_FILES`.

```bash
cd <module directory> || exit 1
golangci-lint linters                       # read the "Enabled by your configuration linters" section
golangci-lint run --enable-only=<enabled set> --fix=false --allow-serial-runners --uniq-by-line=false \
  --max-issues-per-linter=0 --max-same-issues=0 --output.text.path=stdout \
  <--output.<format>.path=/dev/null for every other format under output.formats> <package dirs>
```

- `--fix=false` is required: a config with `issues.fix: true` makes `golangci-lint run` rewrite files.
- `--allow-serial-runners`: party mode runs several golangci-lint instances. By default a second instance that fails
  to take the file lock exits with an error. With the flag it waits.
- `--uniq-by-line=false`: the default (`true`) drops a second linter's issue on the same line.
- `--max-issues-per-linter=0 --max-same-issues=0`: the default caps (50 issues per linter, 3 identical issues)
  truncate nominations.
- `--output.<format>.path=/dev/null` for every format the config sets under `output.formats`: a configured output
  file is still written when text goes to stdout. A config with `output.formats.json.path: report.json` created
  `report.json`, and `--output.json.path=/dev/null` stopped it.

Error-relevant linters and what they nominate:

- `errcheck` → Swallowed Errors.
- `ineffassign`, on an `err` variable only → Swallowed Errors (`overridden`). It is in golangci-lint's default set.
- `staticcheck`, SA4023 only → Unmatchable Failures (typed nil). Keep `SA4023` and `SA4023(related information)`
  lines: the first is the caller's comparison ("this comparison is always true"), the second names the function.
  Other staticcheck codes are dropped from the output. A function that no analyzed caller compares to nil gets no
  diagnostic, and there is no scan for it.
- `nilerr` (returns nil although `err != nil`) → Swallowed Errors (`defaulted`).
- `rowserrcheck` → Swallowed Errors (`rows.Err()`).
- `errorlint` → Unmatchable Failures (`==`, type assertions on errors) and Broken Error Chains (`%v`).
- `err113` → Unmatchable Failures (dynamic errors compared). It also reports every inline `errors.New`; those are
  findings only with a consumer.
- `wrapcheck` → Poor Error Context (an external error returned unwrapped).
- `nilnil` is not used: `return nil, nil` with no error received is not this hunter's.
- `errname` is not used: naming is style.

**Outcome rules:**

- `errcheck` not configured → one Low recommendation to adopt it; regex sees only the explicit `_ =` form, never an
  implicitly ignored return.
- `errcheck` configured but not installed, or run with `-blank` off → state the coverage limit; recommend nothing.
- No other linter is recommended.

## Phase 3 — exception scans

`$GO_FILES` is this language's eligible list, restored from `<run>/go.txt` (SKILL.md Phase 1 step 4). Generated-code
globs in `$EXCLUDE` approximate the authoritative marker.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Swallowed Errors: explicit discards; implicit discards are errcheck's
rg -H -n '\b_\s*=\s*\w+[\w.]*\(' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors: deferred Close (then read the open mode)
rg -H -n 'defer\s+\w+(\.\w+)*\.Close\(\)' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors: empty handler; a nil error returned after err != nil (return nil / 0, nil / "", nil); no `if`
# anchor, so the inline form `if _, err := f(); err != nil {` matches
rg -H -n -U --pcre2 '\berr\s*!=\s*nil\s*\{\s*\}' --type go $EXCLUDE -- $GO_FILES
rg -H -n -U --pcre2 '\berr\s*!=\s*nil\s*\{\s*return(\s+(?:[^\n,]+,\s*)*nil)?\s*\}' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors (logged-only) and Double Handling: a handler that logs first (then read whether it returns,
# continues, or defaults)
rg -H -n -U --pcre2 '\berr\s*!=\s*nil\s*\{\s*(log|slog|[\w.]*[lL]og(ger)?)\.\w+\(' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors (overridden): a deferred assignment to the named err (errors.Join(err, …) keeps it)
rg -H -n -U --pcre2 'defer\s+func\(\)\s*\{\s*err\s*=\s*+(?!errors\.Join\(\s*err\b)' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors: iteration errors (then look for .Err() after the loop)
rg -H -n --pcre2 'for\s+\w+\.(Next|Scan)\(\)' --type go $EXCLUDE -- $GO_FILES
# Orphaned Async Failures: go statement on a named call (then check that it returns error); errgroup Wait as a statement
rg -H -n --pcre2 '^\s*go\s+(?!func\b)[\w.]+\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '^\s*[\w.]+\.Wait\(\)\s*$' --type go $EXCLUDE -- $GO_FILES
# Overbroad Handling: any error mapped to a not-found sentinel
rg -H -n -U --pcre2 '\berr\s*!=\s*nil\s*\{\s*return\s+[^\n]*\bErr\w*(NotFound|NoRows|Missing)\w*' --type go $EXCLUDE -- $GO_FILES
# Overbroad Handling: cancellation (then check whose deadline and the log level); retry wrappers
rg -H -n 'context\.(Canceled|DeadlineExceeded)' --type go $EXCLUDE -- $GO_FILES
rg -H -n -i 'retry|backoff' --type go $EXCLUDE -- $GO_FILES
# Broken Error Chains: %v with no %w on the line (then find a matching caller); custom error types (then look for
# Unwrap)
rg -H -n --pcre2 'fmt\.Errorf\((?!.*%w).*%v' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 'func\s+\(\w+\s+\*?\w+\)\s+Error\(\)\s+string' --type go $EXCLUDE -- $GO_FILES
# Unmatchable Failures: text matching; identity checks wrapping breaks; string and nil sentinels; typed nil is
# SA4023's
rg -H -n --pcre2 '\berr\w*\.Error\(\)\s*[!=]=|strings\.(Contains|HasPrefix|HasSuffix|EqualFold)\(\s*\w*[eE]rr\w*\.Error\(\)' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '\berr\w*\s*[!=]=\s*[\w.]*Err\w*|[\w.]*Err\w*\s*[!=]=\s*err\b' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '\berr\w*\.\(\*?[\w.]+\)|\berr\w*\.\(type\)' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '^\s*(var\s+)?Err\w+\s*(=\s*"|error\s*$)' --type go $EXCLUDE -- $GO_FILES
# Untranslated Boundary Errors: driver sentinels and types (then compare the unit with the adapter)
rg -H -n --pcre2 '\b(sql|pgx|gorm|mongo|redis)\.(ErrNoRows|ErrRecordNotFound|ErrNoDocuments|Nil)\b|\*pgconn\.PgError' --type go $EXCLUDE -- $GO_FILES
# Untranslated Boundary Errors: the generic 500 / Internal (then list which expected failures reach it); the boundary
# files' error mappings are candidates from the boundary pass without a scan
rg -H -n --pcre2 'http\.StatusInternalServerError|codes\.(Internal|Unknown)\b' --type go $EXCLUDE -- $GO_FILES
# Double Handling: the log-first handler scan above
# Poor Error Context: an error from another unit returned unchanged (then check what the caller holds)
rg -H -n -U --pcre2 '(?m)^\s*(?:\w+,\s*)*err\s*:?=\s*[\w.]+\.[A-Z]\w*\([^\n]*\)\n\s*if\s+err\s*!=\s*nil\s*\{\n\s*return\s+(?:[^\n]*,\s*)?err\s*\n' --type go $EXCLUDE -- $GO_FILES
# Poor Error Context: fixed messages (then judge whether they name an input; find duplicates)
rg -H -n --pcre2 'errors\.New\("[^"]*"\)|fmt\.Errorf\("[^%"]*"\)' --type go $EXCLUDE -- $GO_FILES
# Panic and Exit Misuse
rg -H -n '\bpanic\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n '\brecover\(\)' --type go $EXCLUDE -- $GO_FILES
rg -H -n 'log\.Fatal|os\.Exit' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '\bfunc\s+[mM]ust\w*\(' --type go $EXCLUDE -- $GO_FILES
```

Blind spots: implicitly ignored returns (errcheck); an `err` overwritten before it is read (ineffassign); a typed
nil (SA4023, and only through an analyzed caller's comparison); a deferred overwrite inside an `if` in the deferred
body (reading); a handler whose first statement is neither a return nor a log call (reading, from another nomination);
the unchanged-return scan's inline form `if x, err := a.B(); err != nil { return …, err }` (wrapcheck, or reading); a
non-handler function returning `http.Status*` values (reading, from the boundary pass); a `Wait()` hit may be a
`sync.WaitGroup` (returns nothing; drop when reading).

## Phase 5 — Go-specific evaluation

- For each `_ = f()`: does `f` return an `error`? No → slop-hunter's `_ = x`; cross-reference. Yes → is there a
  comment, and does the code confirm it (open mode, callee semantics)? A write-path `Close` is a finding whatever the
  comment says.
- For each `fmt.Errorf` with `%v`: name a caller that matches the chain. None → no finding. A redundant message
  rather than a wrong verb → slop-hunter.
- For each `defer x.Close()`: is `x` opened for writing, and does the caller report success after it?
- For each `for rows.Next()` / `for scanner.Scan()`: is `.Err()` read after the loop?
- For each `go f(…)`: does `f` return an `error` that errcheck does not exclude by default, and is it lost? No →
  drop. A goroutine body that drops an error it received → Swallowed Errors (routing rule 5).
- For each `.Wait()` statement: is the receiver an `errgroup.Group` (returns an error) or a `sync.WaitGroup` (drop)?
- For each log-first handler: does it return the error (Double Handling), continue as on success (`logged-only`),
  return a default (`defaulted`, routing rule 2), or record a different event (not a finding)?
- For each deferred `err =`: can `err` already be non-nil when the defer runs, and does the assignment replace it?
- For each `context.DeadlineExceeded` / `context.Canceled` site: is the deadline the caller's (the request context)
  or one this code set for an outbound call (a failure; any log level is fine)?
- For each `panic`: is it reachable from a trust boundary? Does policy endorse this site? Is there a `recover`
  between it and the process boundary, including `net/http`'s own on the handler goroutine?
- For each `recover` in HTTP middleware: does it re-panic `http.ErrAbortHandler`?
- For each identity check on an error: does any callee on the path wrap it?
- For each `StatusInternalServerError` / `codes.Internal` site and each boundary error mapping: which expected
  failures reach it?
