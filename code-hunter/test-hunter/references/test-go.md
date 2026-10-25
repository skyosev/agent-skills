# Test Hunter — Go reference

Contents: Generated-code eligibility · Test list and production list · Framework and version detection · Delegated detectors · Version-gated signals · Remedies · Coverage mapping blind spots · Test execution · Evidence path form · Phase 2 — test scans

## Generated-code eligibility

A file is generated (ineligible for reporting) only when it carries an authoritative in-file marker: a
`// Code generated … DO NOT EDIT.` line before the first non-comment text. Scan globs such as `*.pb.go` /
`*_gen.go` / `*_generated.go` approximate it.

Vendored trees (`vendor/`), `testdata/`, lockfiles, and Markdown-only inputs are also ineligible. Test files
(`*_test.go`) are eligible.

## Test list and production list

Test files are `*_test.go`; every other eligible file is production. Run once, after `<run>/go.txt` is written:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
GO_FILES=$(cat <run>/go.txt); [ -n "$GO_FILES" ] || exit 1          # STOP: empty restore
EXCLUDE='--glob !**/vendor/** --glob !**/testdata/** --glob !**/*.pb.go --glob !**/*_gen.go --glob !**/*_generated.go'
[ "$GO_FILES" = . ] && GO_FILES=$(rg --files --type go $EXCLUDE -- .)   # codebase mode: enumerate
printf '%s\n' $GO_FILES | grep '_test\.go$' > <run>/go-tests.txt || echo /dev/null > <run>/go-tests.txt
printf '%s\n' $GO_FILES | grep -v '_test\.go$' > <run>/go-prod.txt || echo /dev/null > <run>/go-prod.txt
```

## Framework and version detection

- **Go version:** the `go` line of the `go.mod` that contains the test (the nearest one above it), not the `toolchain`
  line.
- **Framework:** the standard `testing` package, plus any assertion library `go.mod` requires (`stretchr/testify`,
  `gotest.tools`, `google/go-cmp`). `go.mod` require lines are exact versions.
- **Doubles:** hand-written fakes, `go.uber.org/mock` or `golang/mock` (gomock), `testify/mock`, mockery-generated
  mocks.

```bash
rg -H -n '^go\s+[0-9]' --glob '**/go.mod' -- .
rg -H -n 'stretchr/testify|gotest\.tools|google/go-cmp|go\.uber\.org/mock|golang/mock|vektra/mockery' --glob '**/go.mod' -- .
```

## Delegated detectors

- **`go vet`** ships with the toolchain and always runs, in each module directory (each `go.mod`):
  `GOPROXY=off go vet -testinggoroutine ./...`. `GOPROXY=off`
  stops a module download; a load failure is `errored`. `testinggoroutine` flags `t.Fatal` called from a goroutine the
  test starts: an Inert and Weak Tests candidate (an assertion in a goroutine), a finding only when the test does not
  wait for that goroutine.
- **golangci-lint** runs only when its config (`.golangci.yml`, `.yaml`, `.toml`, `.json`) enables `testifylint` or
  `tparallel`, in each module directory: `golangci-lint run ./... | rg '\((testifylint|tparallel)\)$'`, never with `--fix`. Only these outputs
  are used:
  - `testifylint` `useless-assert` (`assert.Equal(t, x, x)`) → Tautological Tests (subject on both sides).
  - `tparallel`'s `defer`-teardown check → Flaky Test Indicators. Its "`t.Parallel()` at one level only" check is not a
    finding.

## Version-gated signals

- **Loop-variable capture** (Inert and Weak Tests, Never executes): a `go` line below 1.22, and a `for … range` loop
  whose body calls `t.Run` with a closure that calls `t.Parallel()` and reads the loop variable without a
  per-iteration copy (`tc := tc`). Every subtest runs the last row. From 1.22 each iteration has its own variable: no
  finding.

## Remedies

- `go` ≥ 1.25: `testing/synctest` (`synctest.Test`) for code that depends on time or starts goroutines the test cannot
  join, and only when they block durably inside the bubble (channels, timers, `sync.WaitGroup`), not on I/O or a
  mutex.
- `t.Setenv` for `os.Setenv`; `t.TempDir()` for `os.MkdirTemp` / `os.CreateTemp`; `t.Cleanup` for a parent `defer`
  with parallel subtests; `errors.Is` / `errors.As` for a message compare; an injected clock for `time.Now()`; `-race`
  in the project's test command.

## Coverage mapping blind spots

The symbol search misses these entry points:

- A method called through an interface: search the interface method name as well as the concrete one.
- A handler driven through a router or `httptest`: search the route path string.
- Code reached by reflection, `//go:linkname`, or a generated client (gRPC): search the RPC or method name.
- A CLI driven by running the built binary (`exec.Command`): search the command name.
- testify suites (`suite.Run`): test methods on the suite type, not `func Test…` functions.
- Build-tagged test files (`//go:build integration`) count as coverage; they run only with the tag.
- Another module of a multi-module repository (`go.work`): search each module.

## Test execution

- **Command:** the project's own (a Makefile target, a CI step that runs `go test`); with none, `go test ./...`.
- **Coverage output:** `-coverprofile=<run>/cover.out` on the `go test` invocation.
- **Update flags:** a golden flag (conventionally `-update`) passed to the tests, or one that defaults to true
  (`flag.Bool("update", true, …)`).

## Evidence path form

The Test cell is the name `go test -run` matches: `TestTotal/with_discount` (spaces in a subtest name become `_`); a
testify suite method is `TestOrderSuite/TestTotal`.

## Phase 2 — test scans

Go has no coverage pragma. Go's retry annotation is
`gotestsum --rerun-fails` in a test command, which the last scan finds.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
GO_TESTS=$(cat <run>/go-tests.txt); GO_PROD=$(cat <run>/go-prod.txt)
[ -n "$GO_TESTS" ] && [ -n "$GO_PROD" ] || exit 1                    # STOP: empty restore

# Tautological Tests: expected values computed by a call (trace each to the subject); golden update flags
rg -H -n --pcre2 '\b(want|exp|expected)\w*\s*:?=\s*[\w.]+\(' -- $GO_TESTS
rg -H -n 'flag\.Bool\(\s*"update' -- $GO_TESTS

# Inert and Weak Tests: test functions (read each body for its checks), skips, goroutines, conditional checks
rg -H -n '^func (Test|Fuzz)\w*\(' -- $GO_TESTS
rg -H -n '\bt\.Skip(f|Now)?\(' -- $GO_TESTS
rg -H -n '\bgo\s+(func\b|\w+\()' -- $GO_TESTS
rg -H -n --pcre2 '^\s*if\s+(?!err\b)\w+\s*!=\s*nil\s*\{' -- $GO_TESTS
# Weak: existence-only checks, any-argument matchers, ignored results and ignored setup errors
rg -H -n '(assert|require)\.(NotNil|NotEmpty|True|Error)\(|mock\.Anything|gomock\.Any\(\)' -- $GO_TESTS
rg -H -n --pcre2 '^\s*(_,\s*err|\w+,\s*_)\s*:?=' -- $GO_TESTS
# Loop-variable capture: parallel subtests (then read the go line and the loop)
rg -H -n '\bt\.Parallel\(\)' -- $GO_TESTS

# Brittle Tests: message compares, private-state reads, call counts and order, SQL text, change detectors
rg -H -n --pcre2 '\.Error\(\)\s*(==|!=)|EqualError\(|ErrorContains\(|strings\.Contains\(\w+\.Error\(\)' -- $GO_TESTS
rg -H -n '\breflect\.(ValueOf|Indirect|NewAt)\b|\bunsafe\.' -- $GO_TESTS
rg -H -n '\.Times\(|gomock\.InOrder|AssertNumberOfCalls' -- $GO_TESTS
rg -H -n 'ExpectQuery\(|ExpectExec\(' -- $GO_TESTS
rg -H -n --pcre2 'os\.ReadFile\(\s*"[^"]*\.go"|"go/parser"' -- $GO_TESTS

# Test Double Misuse: doubles that answer nil, nil (compare each with the real implementation)
rg -H -n --pcre2 'return\s+nil,\s*nil\b|\.Return\(\s*nil,\s*nil\s*\)' -- $GO_TESTS

# Test Setup Duplication: helper and builder census (compare bodies across files)
rg -H -n --pcre2 '^func\s+(new|make|build|setup)\w*\(' -- $GO_TESTS
rg -H -n '^func TestMain\(' -- $GO_TESTS

# Flaky Test Indicators: sleeps, clocks, randomness, environment, package-level state, real services,
# unreleased resources, parallel teardown
rg -H -n 'time\.Sleep\(|time\.After\(' -- $GO_TESTS
rg -H -n 'time\.Now\(\)|time\.Local\b|math/rand' -- $GO_TESTS
rg -H -n 'os\.(Setenv|Unsetenv|Chdir)\(' -- $GO_TESTS
rg -H -n '^var\s' -- $GO_TESTS
rg -H -n --pcre2 'http\.(Get|Post)\(\s*"https?://|net\.Dial\(|sql\.Open\(' -- $GO_TESTS
rg -H -n 'os\.(CreateTemp|MkdirTemp)\(|ioutil\.Temp(File|Dir)\(|httptest\.New(TLS)?Server\(' -- $GO_TESTS
rg -H -n '^\s*defer\s' -- $GO_TESTS
# -race: goroutines in production code, and the project's test commands (does any pass -race?)
rg -H -n '\bgo\s+(func\b|\w+\()' -- $GO_PROD
rg -H -n --hidden 'go test|gotestsum' --glob '**/Makefile' --glob '**/*.mk' --glob '.github/workflows/**' --glob '**/justfile' --glob '**/Taskfile*' -- .
```
