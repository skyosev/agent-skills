# Test Hunter — Go reference

Contents: Generated-code eligibility · Test list and production list · Framework and version detection · Delegated detectors · Version-gated signals · Language-specific signals · Ginkgo and Gomega · Remedies · Coverage mapping blind spots · Test execution · Evidence path form · Phase 2 — test scans

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
- **Framework:** the standard `testing` package, plus any assertion or spec library that a direct `require` of
  `go.mod` names (`stretchr/testify`, `gotest.tools`, `google/go-cmp`, `onsi/ginkgo/v2`, `onsi/gomega`). A line marked
  `// indirect` names no framework. `go.mod` require lines are exact versions.
- **Doubles:** hand-written fakes, `go.uber.org/mock` or `golang/mock` (gomock), `testify/mock`, mockery-generated
  mocks, counterfeiter fakes.
- **Helpers that remedies name:** `go.uber.org/goleak`, `jonboulle/clockwork`.

```bash
rg -H -n '^go\s+[0-9]' --glob '**/go.mod' -- .
rg -H -n --pcre2 '(stretchr/testify|gotest\.tools|google/go-cmp|onsi/ginkgo/v2|onsi/gomega|go\.uber\.org/mock|golang/mock|vektra/mockery|maxbrunsfeld/counterfeiter|go\.uber\.org/goleak|jonboulle/clockwork)(?!.*// indirect)' --glob '**/go.mod' -- .
```

## Delegated detectors

- **`go vet`** ships with the toolchain and always runs, in each module directory (each `go.mod`):
  `GOPROXY=off go vet -testinggoroutine ./...`. `GOPROXY=off`
  stops a module download; a load failure is `errored`. `testinggoroutine` flags `t.Fatal` called from a goroutine the
  test starts: an Inert and Weak Tests candidate (an assertion in a goroutine), a finding only when the test does not
  wait for that goroutine.
- **golangci-lint** runs only when its config (`.golangci.yml`, `.yaml`, `.toml`, `.json`) enables `testifylint`,
  `tparallel`, or `ginkgolinter`, in each module directory:
  `golangci-lint run ./... | rg '\((testifylint|tparallel|ginkgolinter)\)$'`, never with `--fix`. Only these outputs
  are used:
  - `testifylint` `useless-assert` (`assert.Equal(t, x, x)`) → Tautological Tests (subject on both sides).
  - `testifylint` `error-is-as` (`assert.Error(t, err, ErrX)`) → Inert and Weak Tests (Weak, the error-kind case).
  - `testifylint` `go-require` (`require` in a goroutine) nominates an assertion in a goroutine; a finding only when
    the test does not join that goroutine. A failing `require` in a joined goroutine fails the test.
  - `testifylint` `suite-broken-parallel` (`t.Parallel()` in a testify suite) nominates suite shared state; a finding
    only when tests change suite fields.
  - `tparallel`'s `defer`-teardown check → Flaky Test Indicators. Its "`t.Parallel()` at one level only" check is not a
    finding.
  - `ginkgolinter`: a missing assertion method (`Expect(x)` with no `To`) → Absent. A negated assertion that compares
    a pointer with a value, or values of different types, always passes → Weak. An async assertion on a function call
    (`Eventually(f())`, `Consistently(f())`) samples one value: a candidate for an absence check before an async
    effect. The opt-in `forbid-spec-pollution` nominates container-node initialization (Ginkgo and Gomega). Its style
    rules are not used.

## Version-gated signals

- **Loop-variable capture** (Inert and Weak Tests, Never executes): a `go` line below 1.22, and a `for … range` loop
  whose body calls `t.Run` with a closure that calls `t.Parallel()` and reads the loop variable without a
  per-iteration copy (`tc := tc`). Every subtest runs the last row. From 1.22 each iteration has its own variable: no
  finding.

## Language-specific signals

- **`NotNil` on a value that cannot be nil** (Weak): `assert.NotNil(t, v)` or Gomega `NotTo(BeNil())` when the static
  type of `v` is a struct, not a pointer, interface, map, slice, channel, or function. It always passes. Accepted
  Defect: any result. testifylint does not report it; reading the type decides.
- **Build-tagged test files** (Never executes): a test file with a custom build constraint (`//go:build
  integration`) runs only when a command passes the tag (`-tags integration`). A tag that no command in the repository
  passes is the collection case.
- **`Example` functions and fuzz targets:** an `Example` with an `// Output:` comment is a test; audit it like one. An
  `Example` without an output comment, and a fuzz target with no `f.Add` and no `testdata/fuzz/<Name>/` corpus, never
  run their body under `go test`: no coverage, and no finding by themselves. A fuzz campaign (`-fuzz`) runs one named
  target, outside the normal test command.
- **testify suites** (Flaky, shared state): fields that `SetupSuite` sets and test methods change.
- **goleak:** `goleak.VerifyTestMain` for the package, or `goleak.VerifyNone` in that test, clears a goroutine-leak
  candidate when no ignore option (`IgnoreTopFunction`, `IgnoreCurrent`) matches the goroutine. A check in another
  test, or goleak in `go.mod` alone, clears nothing.
- **Retries:** `gotestsum --rerun-fails` in a test command is suite-wide.

## Ginkgo and Gomega

Applies when a direct `require` of `go.mod` names `onsi/ginkgo/v2` or `onsi/gomega`. A spec (`It`, `Specify`, an
`Entry` row) is a test; the `func Test…` that calls `RunSpecs` is a suite bootstrap. Counterfeiter fakes are the usual
doubles.

- **Census:** the spec scan below. Reading follows helpers that generate specs (a function that calls `It`).
- **Never executes:** an unconditional `Skip(…)`; a pending spec (`PIt`, `PDescribe`, `PContext`, `PWhen`, `PEntry`,
  `PDescribeTable`, `XIt`, `XDescribe`, the `Pending` decorator), unless the project's command passes
  `--fail-on-pending`; a label that every command's `--label-filter` leaves out (the collection case). Focus (`FIt`,
  `FDescribe`, the `Focus` decorator) is not a finding: Ginkgo exits non-zero when it finds programmatic focus.
- **Weak:** `To(HaveOccurred())` when the error kind is the contract; `NotTo(BeNil())` when a value is determined;
  `NotTo(HaveOccurred())` that ignores the result, judged with the specs that share its action; a counterfeiter
  `XxxReturns(…)` that answers every input, when the subject forwards its value and no spec checks `XxxArgsForCall`
  and no `XxxStub` checks the input.
- **Brittle:** `MatchError("text")` and `MatchError(ContainSubstring(…))` compare the message; `MatchError(ErrX)`
  uses `errors.Is` and is fine. Counterfeiter `XxxCallCount()` on an internal call.
- **Divergent doubles:** `XxxReturns(nil, nil)` and `XxxReturnsOnCall(i, nil, nil)`.
- **Flaky:** a variable that a container node declares and initializes, and a spec or setup node changes. The
  container body runs once, so every spec shares the value; Ginkgo does not detect it, and it shows as an
  order-dependent failure under `--randomize-all`. `--procs` runs specs in parallel processes, so the parallel signal
  applies to shared files, ports, and databases.
- **Retries:** `FlakeAttempts(n)` on a spec or container is aimed at it; `--flake-attempts` in a command is
  suite-wide. `MustPassRepeatedly` repeats a passing spec and is not a retry.
- **Remedies:** declare in the container, initialize in `BeforeEach`; `MatchError(ErrX)` for a message match; check
  `XxxArgsForCall(i)`, or set an `XxxStub` that answers only the expected input.

Phase 2 scans for this gate:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
GO_TESTS=$(cat <run>/go-tests.txt); [ -n "$GO_TESTS" ] || exit 1   # STOP: empty restore

# Inert and Weak Tests: spec census, skips and pending specs
rg -H -n --pcre2 '^\s*(It|Specify|Entry)\(' -- $GO_TESTS
rg -H -n --pcre2 '^\s*Skip\(|\b(P|X)(It|Describe|Context|When|Entry|DescribeTable)\(|\bPending\b' -- $GO_TESTS
# Weak: error and nil existence checks, fakes that answer any input
rg -H -n --pcre2 '\.(To|Should)\(HaveOccurred\(\)\)|\.(NotTo|ToNot|ShouldNot)\((BeNil|HaveOccurred)\(\)\)|\.\w+Returns(OnCall)?\(' -- $GO_TESTS
# Tautological Tests: an Equal-family matcher whose expected value is a call, not a nested matcher
rg -H -n --pcre2 '\b(Equal|BeEquivalentTo|BeIdenticalTo)\(\s*(?!(Contain|Have|Be|Match|Consist|Point|With|Satisfy|And|Or|Not|Equal|Receive|Succeed|Panic)\w*\()[\w.]+\(' -- $GO_TESTS
# Brittle Tests: message matches, call counts
rg -H -n --pcre2 'MatchError\(\s*("|ContainSubstring)|\w+CallCount\(\)' -- $GO_TESTS
# Test Double Misuse: fakes that answer nil, nil
rg -H -n --pcre2 'Returns(OnCall)?\(\s*(\d+,\s*)?nil,\s*nil\s*\)' -- $GO_TESTS
# Flaky Test Indicators: targeted retries (container-node state is read from each spec's container)
rg -H -n 'FlakeAttempts\(' -- $GO_TESTS
```

## Remedies

- `go` ≥ 1.25: `testing/synctest` (`synctest.Test`) for code that depends on time or starts goroutines the test cannot
  join, and only when they block durably inside the bubble (channels, timers, `sync.WaitGroup`), not on I/O or a
  mutex.
- `t.Setenv` for `os.Setenv`; `t.TempDir()` for `os.MkdirTemp` / `os.CreateTemp`; `t.Cleanup` for a parent `defer`
  with parallel subtests; `errors.Is` / `errors.As` for a message compare; `assert.ErrorIs` for an error kind passed
  as a message; an injected clock (clockwork when installed) for `time.Now()`; `-race` in the project's test command;
  `goleak.VerifyNone(t)` or `goleak.VerifyTestMain(m)`, when installed, for a goroutine leak.

## Coverage mapping blind spots

The symbol search misses these entry points:

- A method called through an interface: search the interface method name as well as the concrete one.
- A handler driven through a router or `httptest`: search the route path string.
- Code reached by reflection, `//go:linkname`, or a generated client (gRPC): search the RPC or method name.
- A CLI driven by running the built binary (`exec.Command`): search the command name.
- testify suites (`suite.Run`): test methods on the suite type, not `func Test…` functions.
- Ginkgo specs: `It` and `Entry` blocks, not `func Test…` functions.
- Build-tagged test files (`//go:build integration`) count as coverage when a command passes the tag.
- Another module of a multi-module repository (`go.work`): search each module.

## Test execution

- **Command:** the project's own (a Makefile target, a CI step that runs `go test` or `ginkgo run`); with none,
  `go test ./...`.
- **Coverage output:** `-coverprofile=<run>/cover.out` on `go test`; `--cover --coverprofile=cover.out
  --output-dir=<run>` on `ginkgo run`, which merges the profiles of all suites into one file (`--coverprofile` takes a
  file name, not a path).
- **What a profile covers:** only the packages the command tests (each with its `_test` package), or the `-coverpkg`
  list when the project's own command passes one; code that another package's tests drive is absent from it. Tags
  come from `-tags`; filters are `-run`, `-skip`, `-short`, and Ginkgo `--focus`, `--skip`, `--label-filter`. The
  command still runs unchanged: no added `-coverpkg`.
- **Update flags:** a golden flag passed to the tests (`-update`, `-golden`, `-regen`, `-rewrite`), one that
  defaults to true (`flag.Bool("update", true, …)`), or an environment switch set in the command (`UPDATE_GOLDEN`,
  `UPDATE_SNAPSHOTS`).

## Evidence path form

The Test cell is the name `go test -run` matches: `TestTotal/with_discount` (spaces in a subtest name become `_`); a
testify suite method is `TestOrderSuite/TestTotal`. A Ginkgo spec is its full text as `--focus` matches it (container
texts, then the `It` or `Entry` text), with its `file:line`: `Order Total applies the discount (order_test.go:41)`.

## Phase 2 — test scans

Go has no coverage pragma. When the Ginkgo gate holds, also run the block in Ginkgo and Gomega.

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
GO_TESTS=$(cat <run>/go-tests.txt); GO_PROD=$(cat <run>/go-prod.txt)
[ -n "$GO_TESTS" ] && [ -n "$GO_PROD" ] || exit 1                    # STOP: empty restore

# Tautological Tests: expected values computed by a call (trace each to the subject): struct fields, multi-assign,
# an expected argument that is a call; golden update flags and switches
rg -H -n --pcre2 '\b(want|exp|expected)([A-Z_]\w*)?\s*(,\s*\w+\s*)?(:|:?=)\s*[\w.]+\(' -- $GO_TESTS
rg -H -n --pcre2 '\b((assert|require)\.(Equal|EqualValues|Exactly)\(\s*t,|cmp\.Diff\(|if\s+\w+\s*!=)\s*[\w.]+\(' -- $GO_TESTS
rg -H -n --pcre2 'flag\.Bool\(\s*"(update|golden|regen|rewrite)|UPDATE_(SNAPSHOTS|GOLDEN)' -- $GO_TESTS

# Inert and Weak Tests: tests, fuzz targets, examples (read each body for its checks), skips, build tags, goroutines,
# conditional checks
rg -H -n '^func (Test|Fuzz|Example)\w*\(' -- $GO_TESTS
rg -H -n '\bt\.Skip(f|Now)?\(' -- $GO_TESTS
rg -H -n '^//go:build' -- $GO_TESTS
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

# Flaky Test Indicators: sleeps, clocks, randomness, environment, package-level and suite state, real services,
# unreleased resources, parallel teardown (defer only in files that run parallel tests)
rg -H -n 'time\.Sleep\(|time\.After\(' -- $GO_TESTS
rg -H -n 'time\.Now\(\)|time\.Local\b|math/rand' -- $GO_TESTS
rg -H -n 'os\.(Setenv|Unsetenv|Chdir)\(' -- $GO_TESTS
rg -H -n '^var\s' -- $GO_TESTS
rg -H -n --pcre2 'func \(\w+ \*\w+\) Setup(Suite|Test)\(' -- $GO_TESTS
rg -H -n --pcre2 'http\.(Get|Post)\(\s*"https?://|net\.Dial\(|sql\.Open\(' -- $GO_TESTS
rg -H -n 'os\.(CreateTemp|MkdirTemp)\(|ioutil\.Temp(File|Dir)\(|httptest\.New(TLS)?Server\(' -- $GO_TESTS
rg -l '\bt\.Parallel\(\)' -- $GO_TESTS | xargs -r rg -H -n '^\s*defer\s' --
# -race: goroutines in production code, and the project's test commands (does any pass -race or --race? which
# custom tags and filters does each pass? does any rerun failures?)
rg -H -n '\bgo\s+(func\b|\w+\()' -- $GO_PROD
rg -H -n --hidden 'go test|gotestsum|ginkgo' --glob '**/Makefile' --glob '**/*.mk' --glob '.github/workflows/**' --glob '**/justfile' --glob '**/Taskfile*' -- .
```
