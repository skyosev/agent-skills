# Exception Hunter — Go reference

Contents: Applicability · Generated-code and test-path eligibility · Language facts and version gates · Not a finding on these grounds alone — Go · Transport frameworks · Delegated to tools · Phase 2 — exception scans · Phase 4 — Go-specific evaluation

## Applicability

| Category | Applicable | Go note |
| -------- | ---------- | ------- |
| Swallowed Errors | **yes** | an `err` checked and then used on no branch; a default returned after `err != nil` by a function with no error result; `scanner.Err()` not read; a named `err` overwritten in a `defer`; a discarded `recover()` |
| Orphaned Async Failures | no | `go f()` and a discarded `errgroup` `Wait()` are in Delegated to tools |
| Overbroad Handling | **yes** | `if err != nil` mapped to a not-found sentinel with no `errors.Is`; cancellation logged at error level; retry wrappers |
| Broken Error Chains | **yes** | a wrapping type with no `Unwrap()`; `errors.New(err.Error())` |
| Unmatchable Failures | **yes** | text matching; string and nil sentinels; an inline `errors.New` where a caller branches |
| Untranslated Boundary Errors | **yes** | driver sentinels and types outside the adapter; `http.Status*` and `codes.*` mappings |
| Double Handling | **yes** | log and return |
| Poor Error Context | **yes** | fixed `errors.New` / `fmt.Errorf` text |
| Panic and Exit Misuse | **yes** | `panic`, `recover`, `Must*` |

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

- **`recover` at the top of a goroutine or in request middleware** that turns a panic into an error response.
- **`panic` in `init()` or in constructors when the project's instructions endorse it.** Cite the policy in Scope.
  *Is* a finding when external input reaches it, whatever the policy.
- **A wrap that repeats `*os.PathError`** (`fmt.Errorf("open %s: %w", path, err)` around `os.Open(path)`): the inner
  error already names the operation and the path. The repeated words are slop-hunter's Unnecessary Error Wrapping.

## Transport frameworks

- **`net/http`**: a handler writes its status itself and returns no error, so `net/http` does not log a returned
  error. It recovers handler panics on the serving goroutine; `http.ErrAbortHandler` is a panic it uses on purpose to
  abort a response, and a recovery middleware must re-panic it.
- **gin**: `gin.Recovery()` recovers panics; `c.Error(err)` attaches an error for a middleware to map.
- **echo**: `HTTPErrorHandler` maps every returned error to a response.
- **gRPC**: `status.Error(codes.X, …)` sets the code. There is no built-in panic recovery: a recovery interceptor is
  needed.
- **connect-go**: `connect.NewError(connect.CodeX, err)` sets the code.

## Delegated to tools

- golangci-lint: an error ignored by `_ =` or by arity, a discarded `go f()` or `errgroup` `Wait()`, a write-path
  `Close` (`errcheck` with `check-blank: true`); an empty `if err != nil {}` (revive `empty-block`); a nil error
  returned after `err != nil` (`nilerr`); `rows.Err()` not read (`rowserrcheck`); an `err` overwritten before it is
  read (`ineffassign`); `%v` where `%w` keeps the chain, and `==` or a type assertion on an error (`errorlint`); an
  error from another package returned unwrapped (`wrapcheck`); a typed nil returned as `error` (staticcheck
  `SA4023`); `os.Exit` or `log.Fatal` outside `main` and `init` (revive `deep-exit`); a wrong `errors.As` target and
  an unused `errors.New` result (`govet` `errorsas`, `unusedresult`).

## Phase 2 — exception scans

`$GO_FILES` is this language's eligible list, restored from `<run>/go.txt` (SKILL.md Phase 1 step 4). Generated-code
globs in `$EXCLUDE` approximate the authoritative marker.

```bash
EXCLUDE='--glob !**/*_test.go --glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'

# Swallowed Errors (defaulted): values that do not return `err`, or a bare return, after err != nil (then read whether
# the function has an error result); no `if` anchor, so the inline form `if _, err := f(); err != nil {` matches
rg -H -n -U --pcre2 '\berr\s*!=\s*nil\s*\{\s*return(\s+(?![^\n}]*\b[eE]rr)[^\n}]+)?\s*\}' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors (logged-only) and Double Handling: a handler that logs first (then read whether it returns,
# continues, or defaults)
rg -H -n -U --pcre2 '\berr\s*!=\s*nil\s*\{\s*(log|slog|[\w.]*[lL]og(ger)?)\.\w+\(' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors (overridden): a deferred assignment to the named err (errors.Join(err, …) keeps it)
rg -H -n -U --pcre2 'defer\s+func\(\)\s*\{\s*err\s*=\s*+(?!errors\.Join\(\s*err\b)' --type go $EXCLUDE -- $GO_FILES
# Swallowed Errors: scanner loops (then look for .Err() after the loop)
rg -H -n 'for\s+\w+\.Scan\(\)' --type go $EXCLUDE -- $GO_FILES
# Overbroad Handling: any error mapped to a not-found sentinel
rg -H -n -U --pcre2 '\berr\s*!=\s*nil\s*\{\s*return\s+[^\n]*\bErr\w*(NotFound|NoRows|Missing)\w*' --type go $EXCLUDE -- $GO_FILES
# Overbroad Handling: cancellation (then check whose deadline and the log level); retry wrappers
rg -H -n 'context\.(Canceled|DeadlineExceeded)' --type go $EXCLUDE -- $GO_FILES
rg -H -n -i 'retry|backoff' --type go $EXCLUDE -- $GO_FILES
# Broken Error Chains: custom error types (then look for Unwrap)
rg -H -n --pcre2 'func\s+\(\w+\s+\*?\w+\)\s+Error\(\)\s+string' --type go $EXCLUDE -- $GO_FILES
# Unmatchable Failures: text matching; string and nil sentinels
rg -H -n --pcre2 '\berr\w*\.Error\(\)\s*[!=]=|strings\.(Contains|HasPrefix|HasSuffix|EqualFold)\(\s*\w*[eE]rr\w*\.Error\(\)' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '^\s*(var\s+)?Err\w+\s*(=\s*"|error\s*$)' --type go $EXCLUDE -- $GO_FILES
# Untranslated Boundary Errors: driver sentinels and types (then compare the unit with the adapter)
rg -H -n --pcre2 '\b(sql|pgx|gorm|mongo|redis)\.(ErrNoRows|ErrRecordNotFound|ErrNoDocuments|Nil)\b|\*pgconn\.PgError' --type go $EXCLUDE -- $GO_FILES
# Untranslated Boundary Errors: the generic 500 / Internal (then list which expected failures reach it); the boundary
# files' error mappings are candidates from the boundary pass without a scan
rg -H -n --pcre2 'http\.StatusInternalServerError|codes\.(Internal|Unknown)\b' --type go $EXCLUDE -- $GO_FILES
# Double Handling: the log-first handler scan above
# Poor Error Context: fixed messages (then judge whether they name an input; find duplicates)
rg -H -n --pcre2 'errors\.New\("[^"]*"\)|fmt\.Errorf\("[^%"]*"\)' --type go $EXCLUDE -- $GO_FILES
# Panic and Exit Misuse
rg -H -n '\bpanic\(' --type go $EXCLUDE -- $GO_FILES
rg -H -n '\brecover\(\)' --type go $EXCLUDE -- $GO_FILES
rg -H -n --pcre2 '\bfunc\s+[mM]ust\w*\(' --type go $EXCLUDE -- $GO_FILES
```

Blind spots: a deferred overwrite inside an `if` in the deferred body (reading); a handler whose first statement is
neither a return nor a log call (reading, from another nomination); a non-handler function returning `http.Status*`
values (reading, from the boundary pass).

## Phase 4 — Go-specific evaluation

- For each return after `err != nil`: does the function have an `error` result? Yes → drop. No → does the caller
  read the default as success (`defaulted`)?
- For each `for scanner.Scan()`: is `.Err()` read after the loop?
- For each log-first handler: does it return the error (Double Handling), continue as on success (`logged-only`),
  return a default (`defaulted`, routing rule 2), or record a different event (not a finding)?
- For each deferred `err =`: can `err` already be non-nil when the defer runs, and does the assignment replace it?
- For each `context.DeadlineExceeded` / `context.Canceled` site: is the deadline the caller's (the request context)
  or one this code set for an outbound call (a failure; any log level is fine)?
- For each `panic`: is it reachable from a trust boundary? Does policy endorse this site? Is there a `recover`
  between it and the process boundary, including `net/http`'s own on the handler goroutine?
- For each `recover` in HTTP middleware: does it re-panic `http.ErrAbortHandler`?
- For each `StatusInternalServerError` / `codes.Internal` site and each boundary error mapping: which expected
  failures reach it?
