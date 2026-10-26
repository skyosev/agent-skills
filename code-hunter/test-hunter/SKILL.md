---
name: test-hunter
description: Audit Go, Python, or TypeScript tests for whether they can fail — coverage gaps in critical code, tautological tests, inert and weak tests, brittle tests, test double misuse, test setup duplication, flaky test indicators. Defaults to the codebase.
disable-model-invocation: true
---

# Test Hunter

Audit tests for **whether they can fail** — a refund branch no test drives, `want := Total(order)` compared with
`Total(order)`, an `it.skip` the diff added, a fake repository that returns `nil, nil` where the real one returns
`ErrNotFound`, a `time.Sleep` waiting for a goroutine. Goal: **every critical behavior has a test that turns red when
the behavior breaks and stays green when it does not.**

**Not covered (owned by other hunters):** noise inside a test — comments, docs, style, commented-out test code
(→ slop-hunter); unused test helpers and deep nesting in test bodies (→ simplicity-hunter); whether a production
interface that only a double implements should exist (→ simplicity-hunter, solid-hunter); temporal coupling in a test
helper, feature envy in a fixture builder, unrelated responsibilities collected in one test-support module
(→ smell-hunter); a production unit with too many dependencies (→ solid-hunter); production races
(→ invariant-hunter); a dead export whose only consumers are tests (→ boundary-hunter); real credentials or secrets in
fixtures (→ security-hunter). Where ownership is *contested*, the category's **Ownership:** note in What to Hunt is
authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `doc-hunter-py`, `security-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical. Every category
applies in every supported language; each language reference holds its scans, gates, and remedies.

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Coverage Gaps | A branch, limit, error path, or state transition in critical code that no test drives | Name the test to add |
| Tautological Tests | The expected value is fixed by the test or by the code under test | Rewrite with an independent oracle, or delete and name the replacement |
| Inert and Weak Tests | No assertion, an assertion that never executes, or one that accepts a defect's result | Assert the specific outcome; un-skip or delete |
| Brittle Tests | Asserts on implementation detail | Assert the observable outcome |
| Test Double Misuse | A double of owned code diverges from it, or is not bound to the real type | Match the double to the implementation, bind it, or use the real collaborator |
| Test Setup Duplication | The same setup repeated across tests or files | Builder, fixture, or parameterized case |
| Flaky Test Indicators | Result depends on time, order, shared state, a real service, or a leaked resource | Inject, isolate, synchronize |

## Core Principles

1. **A test earns its place when a real bug turns it red.** Every finding clears its category's evidence bar (What to
   Hunt).

2. **Scans and counts nominate; reading decides.** A `time.Sleep`, a `Mock()`, a mock count, a file size, a production
   file with no test file beside it is a location to read, never evidence. No hit count, mock count, or file size is a
   criterion.

3. **Static by default.** Evidence is reasoned from code. The tests run only when the prompt asks (Phase 5); mutation
   tools never run, so hidden defects are reasoned, never executed.

## Terms

- **Test paths** — the shared list every hunter uses, unchanged: Go `*_test.go`; Python `test_*.py`, `*_test.py`,
  `tests/`, `conftest.py`; TypeScript `*.test.*`, `*.spec.*`, `*.e2e.*`, `__tests__/`. Per language, the eligible
  list splits into a **test list** (`$GO_TESTS`, `$PY_TESTS`, `$TS_TESTS`) and a **production list** (`$GO_PROD`,
  `$PY_PROD`, `$TS_PROD`).
- **Subject** — the code under test.
- **Assertion** — any call that fails the test on a wrong result: a framework assertion, a query or request
  expectation that throws (Testing Library `getBy*` / `findBy*`, a Playwright locator action, supertest
  `.expect(201)`), or a helper that reaches one (`t.Fatal`, `pytest.fail`, a helper's `assert`).
- **Unit** — the function, method, or handler that owns a branch, limit, error path, or state transition.
- **Target scope** — the files a finding may anchor at; every other file is read as context (Phase 1 step 4, Two
  surfaces).
- **Owned code** — the project's own production code. The language, its standard library, third-party libraries, the
  test framework, and test doubles are not owned code.
- **Critical code** — code whose wrong result is silent and costly: calculations (money, quantities, time),
  validation and authorization decisions together with the wiring that applies them (the middleware attached to a
  route), state transitions, persistence mappings, parsers of external input, idempotency and deduplication (a
  duplicate charge), destructive operations (delete, retention). Every critical-code claim names the wrong result and
  who pays for it; that is also how a thin wrapper, logging, or a configuration value qualifies (a lowered minimum
  TLS version, a session cookie without `Secure`). Generated code is never critical.
- **Test oracle** — where a test's expected result comes from. An **independent oracle** derives it without running
  or copying the code under test: a specification, a hand-worked example, an invariant, a protocol, a separately
  designed reference.
- **Hidden defect** — a concrete defect in the behavior the test claims to check, for the input the test uses, that
  the test cannot detect *because of where its expected value comes from*. It must follow from the Oracle Trace: a
  subject that returns the expected literal (`return 1750`) is not one, because every example-based test misses it.
- **Blind test** — a test that cannot detect a defect in the behavior it claims to check: tautological (except a
  mirror computation), Absent, Never executes, Weak, or driving that behavior through a double that diverges from the
  real code on it.
  A test is blind for a behavior only when the defect escapes every check the test makes on that behavior:
  `expect(r).toBeDefined()` followed by `expect(r.total).toBe(1750)` is not blind for the total.
- **Breaking refactor** — a behavior-preserving change that turns the test red.
- **Double** — any test stand-in: mock, stub, fake, spy. A **bound double** is one the type system or a spec ties to
  the real type's members and signatures: Go interface satisfaction, a TypeScript double typed as the real interface
  (`satisfies Repo`, `mock<Repo>()`) in a file that a command type-checks (Phase 1 step 5), Python `create_autospec` /
  `autospec=True`. Python `spec` / `spec_set` bind attribute names only; call signatures stay unchecked. A TypeScript
  type assertion (`as Repo`, `as Partial<Repo>`) binds nothing: it compiles on an object that lacks members. A
  **divergent double** is a double of owned code that does something the real code cannot: returns
  a value or shape the real code never returns, omits an error or validation the real code has, or accepts a call the
  real code rejects.

## Not a finding on these grounds alone

- **Style that leaves detection unchanged.** Test names, table layout, a single-entry table, a table field that holds
  one value in every row, and assertion style (`if got != want { t.Errorf(…) }` or an assertion library) are not
  judged.
- **A committed snapshot or golden file, by itself.** Whether someone reviewed it cannot be proven from the code. Only
  a mechanism that rewrites it is Tautological (self-written oracle); a snapshot of private structure, or one too large
  to review for meaning, is Brittle.

## What to Hunt

### Coverage Gaps

A branch, limit, error path, or state transition in critical code that no test drives.

**Signals:**

- A branch of critical code that no test drives: an error return, an `except` / `catch` branch, an authorization deny
  path, a state transition (each valid one and at least one invalid one).
- A boundary that the code itself defines: a `len == 0` branch, a maximum constant, a rounding rule, the last and the
  empty page, a cancelled context that the code checks.
- A coverage pragma on critical code (`# pragma: no cover`; `/* istanbul ignore … */`, `/* c8 ignore … */`,
  `/* v8 ignore … */`) nominates its lines. The pragma hides lines from the coverage report, not from the tests. A
  coverage exclusion in config (each language reference lists its settings) nominates the critical code its patterns
  match, under the same rules.
- Diff mode: changed production behavior (Phase 4) that no test would detect if the change were reverted, including a
  test added with a fix that does not pin the fix.
- Critical code whose only tests are blind and lie outside the target scope (Within-skill routing).

**Evidence bar:** the Unit cell names why the unit is critical: the wrong result and who pays for it. The Test Search
cell lists the searches run (Phase 3) and their result; when blind tests are the only coverage, it names them and why
each is blind; for a diff-mode fix, it names the test the change added, if any, and why it does not pin the fix. An
edge case is a finding only when the code has the branch, limit, or contract clause that the input exercises. A line
under a coverage pragma or a config exclusion is a finding only when the mapping finds no test that drives it. A
critical unit that no test drives gets one row that lists its untested branches; a unit that some test drives gets one
row per untested branch. A language with no test files anywhere in the repository (Phase 3 finds none) gets
`no tests found: <lang>` in Scope.

**Not a finding:** a generic edge-case checklist (nil, empty, Unicode, maximum, timeout for every function); thin
wrappers, logging, and configuration values with no named consequence; generated code; dependency internals; a
coverage pragma on code that is not critical (`__repr__`), or on lines a test drives; a unit whose tests cannot be
traced, which goes to Scope as `unresolved coverage` (Phase 3).

**Action:** name the test to add: its input and the outcome it asserts. A production defect suspected while tracing is
named in the Action ("suspected: refund rounds before tax at `refund.go:88`; the missing test confirms or clears it");
the finding stays a Coverage Gap.

**Ownership:** coverage pragmas are here, with or without a reason; slop-hunter does not report them.

### Tautological Tests

A test whose assertion is true by construction: the expected side comes from the code under test, from a copy of its
derivation, from the test's own arrangement, from a double's configured value, or from a file the code under test
wrote. It includes **oracle-coupled** tests, whose expected side re-derives the result closely enough to share its
defects.

**Kinds** — the Oracle Trace cell names one:

1. **Subject on both sides** — the expected side calls the code under test, or a production helper it delegates to.
   `assert.Equal(t, x, x)` is the degenerate form. Hidden Defect: any change to the subject.
2. **Mirror computation** — the expected side re-derives the result with the same formula, the same library call the
   code makes, or a copy of the production algorithm. Hidden Defect: a rule that both copies get wrong. The test still
   catches a later change to either copy, so a mirror is never High.
3. **Arrangement echo** — asserts a value the test set, carried to the assertion only by mechanics that are not owned
   code: assignment, a struct or dataclass literal, the framework, a double.
4. **Double echo** — asserts the value a double was configured to return, when the test calls the double directly, or
   when the double is a partial mock that replaces the subject's own member that computes the asserted value.
5. **Self-written oracle** — the code under test rewrites the expected file on every run: the project's test command
   or runner config turns on an update (each language reference lists its runners' flags and settings), a Go golden
   update flag defaults to true, a script that runs the production code regenerates a fixture before the tests. A
   helper that writes a missing golden file is the normal bootstrap: it is a finding only when git ignores the
   expected file, so every fresh checkout writes it again. Check each snapshot and golden file the scans found with
   `git check-ignore -- <path>`; it takes paths, not globs.

**Evidence bar:** an **Oracle Trace** — the expected value followed back from the assertion to its source
(`want ← Total(order)`) — and a **Hidden Defect** that follows from it. When no owned code runs between arrangement and
assertion, the Hidden Defect is `any — no owned code runs`, and the Oracle Trace shows that.

**Not a finding:**

- A literal worked example, including a compact calculation that states an independent rule (`2 × 1000 − 250`).
- Property, invariant, and metamorphic assertions; a differential test against an independently designed reference.
- An interaction assertion with meaningful arguments when the interaction is the contract.
- A test of trivial owned code (constructor assignment, a getter): a wrong field assignment makes it fail.
- **Pass-through**: the subject returns what a collaborator double returned, and the test asserts that value. Dropping
  or replacing the value fails the test, so a pass-through test can fully check a forwarding contract. It is Inert and
  Weak Tests (Weak, non-discriminating double) only when the double answers any input, so a subject that forwards the
  wrong argument still passes.
- A **learning test**: input sent through third-party code and checked against a hand-written output.

**Action:** rewrite with an independent oracle — a hand-worked value, a property, a reference — or delete the test and
name the test that replaces it.

### Inert and Weak Tests

A test that cannot fail on a wrong result: it has no assertion, it never runs, its assertion never executes, or its
assertion accepts the result a plausible defect produces. The Kind cell takes one of four values; each language
reference maps its own forms and detector rules to them:

- **Absent** — no assertion (Terms). A bare comparison statement (`x == 1` without `assert`). An assertion that
  checks nothing (Python `assert (x == 1, "msg")`, a tuple that is always true). A Python test whose only check is a
  `return`ed value (`return result == 1`), which pytest only warns about.
- **Never executes**:
  - An assertion inside a `try` whose handler swallows the assertion error (`except Exception`,
    `except AssertionError`, a bare `catch`).
  - An assertion inside an `except` block for an exception the code may not raise: with no exception, it never runs.
  - An un-awaited async assertion (`expect(p).resolves` / `.rejects` without `await` or `return`) under a runner that
    does not await it (TypeScript reference, Config-gated signals).
  - An assertion in a goroutine or callback that the test does not wait for.
  - A conditional assertion: a check nested under a guard on the result
    (`if got != nil { if got.Total != 1750 { t.Errorf(…) } }`), so a nil result skips it. An `if` whose body is the
    failure call is the check itself.
  - An assertion in a loop that is the test's only check, when the test never asserts the collection's length or
    non-emptiness.
  - A test that never runs: an unconditional skip (`t.Skip()`, `@pytest.mark.skip`, `it.skip` / `xit` /
    `describe.skip`), or a form the language reference lists (Go loop-variable capture, a Ginkgo pending spec, a
    Python async test that no plugin handles).
  - A test file that no command in the repository runs, when the repository shows the exclusion: a runner config
    pattern excludes the file (`testPathIgnorePatterns`, Vitest `exclude`, pytest `norecursedirs`), or a command
    deselects its build tag or marker and no command selects it. The commands are those the repository holds: build
    files, package scripts, CI workflows. One row per exclusion, listing its files. A job outside the repository may
    still run them, so the Accepted Defect cell states that boundary: `no command in the repository runs it — read:
    <files>`. Collection that depends on anything else (a config computed in code, a workspace or project file, a
    command the repository does not show) fails closed: the tests count as live, and Scope records `collection not
    resolved: <pattern or files>`. Runner configs are read, never simulated.
  - A focused test (`.only`) that leaves the rest of the file unrun, under a runner that lets it through (TypeScript
    reference, Config-gated signals). The finding anchors at the `.only`. A runner the reference does not name is
    recorded in Scope and gets no finding.
- **Weak**:
  - An existence, truthiness, or type-only check (`is not None`, `toBeDefined()`, `NotNil`) when a specific value is
    determined.
  - A check of `err == nil` that ignores the result.
  - An error path that checks only that some error happened (`err != nil`, `pytest.raises(Exception)`, a bare
    `toThrow()`, a `wantErr` row that only calls `require.Error`) when the error kind is the contract. In testify, an
    argument after `err` is a message, not an error kind: `assert.Error(t, err, ErrNotFound)` checks only `err != nil`.
  - An interaction assertion without arguments (`toHaveBeenCalled()`, `assert_called()`, `mock.Anything`) when the
    arguments are the contract.
  - An absence check on an effect that the subject produces asynchronously, with no wait, flush, or timer advance
    before it (`expect(sendEmail).not.toHaveBeenCalled()` right after a click whose handler awaits first): the check
    runs before the effect can happen. The Accepted Defect is the effect happening after the check, and it cites the
    line where the subject defers the effect.
  - A non-discriminating double: one fake serves both the success and the failure path, or answers any input, so the
    wrong branch or a wrongly forwarded argument also satisfies the assertion.
  - A table or parametrize row that branches into no assertion.
  - An ignored setup error (Go `x, _ := setup()`; an un-awaited setup promise in TypeScript), so the test asserts on
    zero values.
- **Weakened in diff** — diff mode only. The change removed an assertion or a whole test (a deleted test file
  included, Location `<path> (deleted)`), replaced a matcher with a weaker one (`toEqual(x)` → `toBeDefined()`), or
  added a skip, while the behavior the assertion checked still exists and no remaining test checks it. A skip or a
  weaker matcher that the diff added is Weakened in diff when it clears that bar; when another test still checks the
  behavior, judge it as Never executes or Weak. Phase 2's nomination of the same line merges into whichever row
  results.

**Evidence bar:** the **Accepted Defect** — the result a plausible defect in the subject produces that still passes
(`Total returns 0: NotNil passes`). Never executes: why the assertion does not run. Weakened in diff: the line at the
merge base, the working-tree code that still has the behavior it checked, and the search that shows no remaining test
checks it.

**Not a finding:**

- A conditional skip (platform, environment variable, `testing.Short()`).
- A test whose contract is "does not raise or panic": a Go fuzz target, a parser's accept-any-input test.
- `require.Error(t, err); return` when rejection is the whole contract.
- `t.Fatal` in a table loop without `t.Run`: a failing row still turns the test red. Only the later rows' diagnostics
  are lost.
- A loose check next to a specific check on the same value (`toBeDefined()`, then `toBe(1750)` on its total), in the
  same test or in a sibling test that shares its action. Tests that share one action (a Ginkgo `JustBeforeEach`, a
  `beforeEach` or fixture that calls the subject) are judged together: `It("succeeds")` that checks only the error is
  not Weak when a sibling `It` checks the result. The test still counts as coverage of that value.
- Weakened in diff, when the change also removed the behavior the assertion checked.

**Action:** assert the specific outcome; await or return the async assertion; remove the `.only`; un-skip, or delete
the test and name the test that replaces it.

**Ownership:** skipped and focused tests are here, with or without a reason; slop-hunter does not report them.
invariant-hunter routes an ignored error in a test here.

### Brittle Tests

A test that a behavior-preserving change turns red, because it asserts on implementation detail.

**Signals:**

- Call-count or call-order assertions on internal calls.
- Assertions on private state when the same outcome is observable through the public API: Go unexported fields (a
  same-package read, or `reflect` / `unsafe`); Python `_attr` on the subject; TypeScript `(x as any).priv` or
  `x['priv']`.
- Exact message text when the message is not a contract: a Go `err.Error()` string compare instead of `errors.Is` /
  `errors.As`, `pytest.raises(match=…)` on an internal message, `toThrow('exact text')`.
- Log output or a string representation used as a proxy for behavior.
- Generated SQL text.
- DOM structure or CSS selectors where a role-based query exists (TypeScript).
- A snapshot or golden file of private structure, or one so large that a change cannot be reviewed for meaning.
- **Change-detector tests**: the test reads a source file and asserts on its text, or asserts that a removed symbol,
  file, or import stays absent.

**Evidence bar:** a **Breaking Refactor** — `inline applyDiscount into Total: the call-count assertion fails`.

**Not a finding:** call counts at a boundary that the business cares about (one email, one charge, the number of
attempts a retry policy makes); a same-package Go
test that reads unexported state that no exported behavior shows; a call to a private function whose result is checked
against an independent oracle; a message that users see, which is a contract; a log that is the contract (an audit
log); SQL text when producing it is the unit's job (a query builder); a test's imports, whatever they reach.

**Action:** assert the observable outcome: the return value, the stored row, the sent message, the error kind.

### Test Double Misuse

A double of owned code that misrepresents the code it replaces: it diverges from the real implementation, nothing
binds it to the real type, or the subject never reaches it.

**Signals:**

- A divergent double. Example: a fake repository returns `nil, nil` where the real one returns `ErrNotFound`, so the
  subject's not-found path is never exercised.
- A double not bound to the real type: TypeScript `as any`, `as unknown as T`, `as Repo`, or `as Partial<Repo>` on a
  double, an `@ts-expect-error` or `@ts-ignore` above one, an untyped `vi.fn()`, and a typed double in a file that no
  command type-checks (Phase 1 step 5); Python `Mock()` / `MagicMock()`, or `patch()` without `autospec=True`, with no
  `spec` standing in for a project type. Go needs nothing here: the compiler checks interface satisfaction.
- A signature drift that exists now behind a `spec`-only or unbound double, which is a divergence.
- An unreached double: the patch or spy replaces a name the subject never looks up, so the real collaborator runs.
  Python `patch("pkg.billing.charge")` when the subject did `from pkg.billing import charge`; TypeScript
  `vi.spyOn(mod, "fn")` on an ESM export that the subject calls inside its own module.

**Evidence bar:** the Divergence cell cites the real implementation's lines (`repo.go:52 returns ErrNotFound; the fake
returns nil, nil`). The auditor resolves the implementation behind the replaced interface or module; when it cannot,
there is no row. Unreached: the subject's import or call line, and the patch or spy target. An unbound double is a row
only with a drift that exists now; unbound doubles with no drift go to Scope as one line per language
(`unbound doubles without drift: <n> files — <dir> (<n>), …`).

**Which category judges a double:**

- The test calls the double directly, or the double is a partial mock that replaces the subject's own member that
  computes the asserted value → Tautological Tests (double echo).
- The subject forwards the double's value, and the test asserts it → no finding (pass-through); Inert and Weak Tests
  (Weak) only when the double answers any input, so a wrongly forwarded argument also passes.
- One fake serves both the success and the failure path → Inert and Weak Tests (Weak).
- It does what the real code cannot → divergent, here.
- Nothing ties it to the real type → unbound, here.
- The subject never calls it, and nothing asserts a call on it → unreached, here.

**Not a finding:** a faithful double of owned code, whether or not the real code touches I/O; a double of code that is
not owned (an HTTP API, a cloud SDK), whose real behavior cannot be read; a double that returns an error the real code
can return but a test cannot easily provoke; an unreached double that the test asserts a call on, because that
assertion fails. Mocking style is not judged. Mock counts nominate; they are never the criterion.

**Action:** match the double to the implementation, bind it to the real type, point the patch or mock at the name the
subject looks up, or use the real collaborator. When an unreached double lets an external service run, the Action
says so; the same defect is not filed again under Flaky Test Indicators. When a removed double leaves an interface
with no second implementation, the Action names simplicity-hunter's Unnecessary Abstractions check.

**Ownership:** whether a production interface that only a double implements should exist is simplicity-hunter's and
solid-hunter's question; both count the double as a second implementation. A production unit with too many
dependencies is solid-hunter's; this hunter reports the divergent or unbound double at the test, and the two
cross-reference by unit name. invariant-hunter routes `as any` on a mock here.

### Test Setup Duplication

The same setup repeated across tests or files. It is judged here because test code has its own rule: values that each
case depends on are repeated on purpose (Not a finding). Copies have **diverged** when they differ in a value or a
step that the code under test reads.

**Signals:**

- Identical or near-identical setup across tests or files: Go helpers, Python fixtures duplicated across
  `conftest.py` files, TypeScript `beforeEach` blocks.
- Test bodies that differ in one value → a parameterized case.
- Fixture builders duplicated across packages.
- **Data Clumps in test helpers**: the same three or more domain values passed together through several helpers → a
  builder with defaults, so each test states only the values it depends on.

**Evidence bar:** the Locations cell lists every copy.

**Not a finding:** repeated values that each case depends on — the reader must see what matters; test infrastructure
parameters (`t`, `ctx`, a database handle, a client), which are never a clump; size alone.

**Action:** a builder with defaults, a fixture, or a parameterized case.

**Ownership:** simplicity-hunter routes test-code duplication here. smell-hunter routes Data Clumps in test helpers
here. Duplication inside a test-support package outside test paths (Go `internal/testutil`) is simplicity-hunter's,
as production code. Shared mutable state between tests is Flaky Test Indicators.

### Flaky Test Indicators

A test whose result depends on time, order, shared state, a real service, or a leaked resource.

**Signals:**

- Fixed sleeps used to synchronize.
- Wall-clock, timezone, or locale dependence; unseeded randomness; an ambient environment read (`os.Getenv`,
  `os.environ.get`, `process.env`) that the test does not set. The source may sit in production code that the test
  drives: the trace (evidence bar) reaches it there.
- Generated test data (Faker-style factories) when the asserted result depends on the generated value: a unique
  constraint, or a relative date (`faker.date.past()`) that moves with the wall clock.
- Iteration-order dependence: Go map iteration; Python set iteration (string hashing is randomized per process).
- Shared mutable state between tests: package-level variables, module globals, environment variables set without
  restore (`os.Setenv` instead of `t.Setenv`, `os.environ[...]` instead of `monkeypatch.setenv`, `process.env` without
  restore), singletons, session-wide fixtures that tests mutate. Also double state that outlives a test (a
  module-level `vi.fn()` that a test configures, a global assigned directly, a Python patcher started without
  `stop()`), and suite or container state that tests change (testify suite fields, objects built in `beforeAll` or
  `setUpClass`, a Ginkgo variable initialized in a container node). A cleanup setting clears a candidate only for the
  constructs it covers (language reference).
- Parallel execution combined with shared state: Go `t.Parallel()`, Jest and Vitest `concurrent`, pytest-xdist,
  Ginkgo `--procs` (each language reference lists its forms). In Go, also `t.Parallel()` with a `defer` teardown in
  the parent test, which runs before the parallel subtests do.
- Calls to real services from tests that the project marks as unit tests (build tags, markers, file naming).
- Resources that are never released: temp files outside `t.TempDir()` / `tmp_path`, servers and clients that are not
  closed, async sessions in fixtures without teardown, goroutine leaks.
- Go: in-scope code starts goroutines, but the project's test command never passes `-race`: one row per in-scope test
  file that drives that code, because the command file is outside the target scope. The Test cell is the file path;
  the Nondeterminism Source is `no -race in <command file:line>`, or `no -race: no test command found`.
- Retries aimed at a test or its file (`@pytest.mark.flaky`, `jest.retryTimes`, a per-test `retry` option; each
  language reference lists its runners' forms). A retry turns an intermittent failure green, a real intermittent
  regression included. It is not a Nondeterminism Source by itself: it makes the Flaky finding of each test it covers
  High when that test drives critical code, and that row's Nondeterminism Source cell names it. A suite-wide retry
  (`retries` in `playwright.config.*`, `retry` in the Vitest config, a rerun option in the test command) changes no
  severity; Scope records it as `suite-wide retry: <setting> at <file:line>`.

**Evidence bar:** the Nondeterminism Source cell holds two things, as an Oracle Trace does for a tautology:

- **The trace** — the source at `file:line`, followed to what the test checks.
- **The values that change the outcome** — the values of the source that change the check's result, or cause an
  exception or a timeout, read from the check and the source.

Example: `due vs the test's own time.Now(), both cut to the day (billing_test.go:31) ← now.Add(24h) ← time.Now() at
billing.go:40; the two reads fall on different days when the run crosses midnight`. A real service: the call, and the
test errors or times out when the service is down or slow. A leaked resource: what else meets it (a fixed port or
path, a later test, a leak check). A guess about the environment ("CI runs at night") may go in the Action; it is not
evidence.

The missing `-race` row is a policy row: a missing flag fails no run and shows no nondeterminism. It keeps its
evidence (the command line and the code that starts goroutines), and its Pattern cell is `policy: no -race`.

**Not a finding:** a source that reaches no check (a log line, a test deadline, a label nobody asserts); a check that
every value of the source passes (a generated UUID checked with `toMatch(UUID_PATTERN)`); a leak that nothing meets (a
temp file under a unique name); property-based generators (Hypothesis, fast-check, rapid, `testing/quick`, Go
fuzzing), which are random on purpose and report the failing input.

**Action:** inject, isolate, or synchronize, with the remedy the language reference names. A sleep that waits for a
goroutine or a callback → wait on the completion signal the code exposes.

**Ownership:** invariant-hunter routes races, goroutine leaks, and `-race` discipline in tests here; production races
stay invariant-hunter's. smell-hunter routes shared mutable state between tests here.

### Within-skill routing

Precedence decides only between categories that describe the same defect: the same lines and the same cause. A test
with independent defects (a weak assertion and a fixed sleep) gets one row per defect. Each defect is reported once,
under the first category in this order that describes it:

1. Does the test run, and does its assertion execute? No → Inert and Weak Tests (Absent, Never executes).
2. Is the expected value fixed by the subject, a mirror, the arrangement, a double's configuration, or a self-written
   file? Yes → Tautological Tests.
3. Do the test's checks of the behavior, taken together with those of sibling tests that share its action, accept
   the result that a plausible defect in the subject produces? Yes → Inert and Weak Tests (Weak). A double that
   answers any input and an ignored setup error count here, because they widen what the checks accept; a double that
   does what the real code cannot is step 5.
4. Would a behavior-preserving change break it? Yes → Brittle Tests.
5. Does a double of owned code diverge from it, stand unbound to the real type, or go unreached? Yes → Test Double
   Misuse.
6. Does the result depend on a nondeterminism source? Yes → Flaky Test Indicators.
7. Repeated setup → Test Setup Duplication.

Production side: critical behavior that no test drives → Coverage Gaps. Critical behavior that only blind tests drive
→ at those tests, under their category, when they are in the target scope; otherwise a Coverage Gap at the unit that
names them. Never both. The same holds for a critical path that no test drives because a double diverges: Test
Double Misuse at the double when its test is in the target scope, otherwise a Coverage Gap that names the double.
One exception: in diff mode, a fix that no test pins stays a Coverage Gap at the production change, even when the
change added a test; that test gets its own row only when it is blind or weak for what it does check.

## Test-code scope

**Inverted relative to most hunters.** Test files are the main surface for six categories; production files are the
anchor for Coverage Gaps. Both are read as context (Phase 1 step 4, Two surfaces). The test paths (Terms) are used
unchanged. A test-support package outside
test paths (Go `internal/testutil`) is production by path for every hunter: this hunter reads it as context and
anchors no finding there.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is.** The shared definitions apply: Critical is exploitable now, causes data
loss, or breaks behavior on production paths; High is a defect with likely user-visible, security, or reliability
impact; Medium is correctness or maintainability risk without imminent impact; Low is hygiene. **The ceiling is
High:** a missing or blind test breaks nothing by itself, so no finding here is Critical. Applied to tests:

- **High** — the finding leaves a behavior of critical code effectively unprotected: no test drives the behavior, or
  every test that drives it is blind; or a flaky test on critical code carries a retry aimed at that test or its file.
- **Medium** — the default for a finding that is neither High nor Low. Protection is weakened, but something still
  catches regressions: a blind test whose behavior other tests also cover; a mirror computation, even as the only
  coverage; a flaky test without a targeted retry; a divergent double whose path another test drives.
- **Low** — hygiene with no effect on what gets detected: setup duplication whose copies have not diverged.

**Impact — how much the change is worth:** how critical the code is; for code that is not critical, how many tests
share the state, the double, or the setup.

- **High** — critical code
- **Medium** — code that is not critical, with a double, state, or setup that many tests share
- **Low** — clears the evidence bar, but the code is not critical and one or two tests reach it

## Audit Workflow

### Phase 1: Gain Context

**Deleted test files (diff mode).** The call that resolves the scope (step 1) also writes `$DELETED` to
`<run>/deleted.txt`; in party mode, write the deleted-in-diff list from `scope-meta.txt` there. With no deletions the
file is empty: an empty list, not a STOP. Step 2 detects languages from it as well as from the manifest, so a deleted
Python test is seen in a Go-only diff. Deleted paths never enter `scope.txt` or a `<lang>.txt`, so no scan runs
against them; Phase 4 reads the test paths among them at the merge base. A language detected only from `deleted.txt`
loads its reference, for the Test cell's evidence path form, and gets no `<lang>.txt` and no split: steps 4 to 6 and
Phases 2, 3, and 5 skip it.

**Deletions-only run** — no eligible file in scope and at least one deleted test path. It is an exception to both
shared empty-scope stops. When `$SCOPE` is empty, the stop in `references/diff-scope.md` does not apply yet: drop the
deleted paths that are not test paths. If none remain, that stop applies unchanged ("Audit completed: 0 findings —
empty diff scope"). Otherwise the run continues: later calls restore `<run>/deleted.txt` instead of
`<run>/scope.txt`, and an empty restore of it is the STOP. Steps 4 to 6 and Phases 2, 3, and 5 do not run; Phase 4
reads each deleted test, and Phase 6 judges it against the working tree. The only possible finding is Inert and Weak
Tests (Weakened in diff), at `<path> (deleted)`.

1. **Resolve the raw manifest.** Scope may be:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked. Resolve it with
     `references/diff-scope.md`.
   - **Path**: specific files, folders, or packages — `SCOPE=$(git ls-files --cached --others --exclude-standard
     -- <paths>)`, which expands folders to files
   - **Codebase**: the entire project (default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line): `SCOPE=$(cat <snapshot>/scope.txt)`. Read run metadata (base SHA — `$MB` in diff mode —
   surface kind, counts) from `scope-meta.txt` when present. Use the manifest verbatim; the resolution
   above is for standalone runs only.

   **Persist run state.** Shell variables do not survive between tool calls, and `rg … --` with an empty variable
   searches the whole working directory. Create one run directory (`RUN=$(mktemp -d) && echo "$RUN"`) and use the
   printed path literally from then on. Every call starts at the repository root (`cd "$(git rev-parse
   --show-toplevel)"`), because every list holds root-relative paths. Write `$SCOPE` to `<run>/scope.txt` and, in diff mode, `$MB` to `<run>/mb`.
   A later call restores what it uses (`SCOPE=$(cat <run>/scope.txt)`); an empty restore is a STOP, never an empty
   result. If the resolved surface exceeds the context budget, report the file count and ask to narrow or chunk.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section. On a dirty tree, line numbers match no
   commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent: on a mixed scope it stays whole, so every hunter in a
   party audits the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from manifest extensions alone:
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**. Record `excluded — no reference for .<ext>: {count} files` in Scope,
   naming each extension.

3. **Load language references.** For every detected language, read `references/test-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/test-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules to that
   language's files. These subsets are then immutable. Record in Scope: raw manifest count, each per-language
   eligible subset, exclusions, and `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only what each reference's eligibility section lists, and generated files identified by
   each reference's authoritative **in-file marker** — **never** by filename guessing. Test paths stay eligible: they
   are this hunter's main surface.

   Write each subset to `<run>/<lang>.txt` (`go.txt`, `python.txt`, `typescript.txt`). Codebase mode: the single line
   `.`. Diff and path mode: the eligible files, one per line — `comm -12 <(rg --files --type <t> $EXCLUDE | sort)
   <(printf '%s\n' $SCOPE | sort)` with the loaded reference's `--type` and `$EXCLUDE`, minus files carrying a
   generated-code marker (`| while read -r f; do rg -q -m1 '<marker>' "$f" || echo "$f"; done`, the marker regex built
   from the reference's eligibility section); the reference's generated-file globs are the same scan approximation a
   codebase run uses. Filter before scanning: `rg` applies `--type` and `--glob` only while walking a folder and
   searches every file named on its command line. Each scan call restores its list first — `GO_FILES=$(cat
   <run>/go.txt)` (`PY_FILES`, `TS_FILES`) — and the reference blocks pass it as `rg -H … -- $GO_FILES`: given one file,
   `rg` prints no file name unless `-H` is set.

   Then split each list into its test list and its production list with the reference's split block, which writes
   `<run>/<lang>-tests.txt` and `<run>/<lang>-prod.txt`. A list with no files holds `/dev/null`, so a scan over it
   finds nothing and its restore is never empty.

   If **nothing** eligible remains and no deleted test path does: write `Audit completed: 0 findings — no eligible
   source in scope` and stop before scanning. With deleted test paths left, it is a deletions-only run.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Files outside it are *read* as **context**, in both directions: the tests of an in-scope production file and
   the production code of an in-scope test routinely sit outside any diff. Diff and path scope narrow the manifest,
   never the context reading. In diff mode, production files in scope pull in their tests as context; test-quality
   findings anchor only at in-scope test files.

5. **Record the test toolchain** per language, with the reference's detection section: the test framework and its
   version, the double library, and the delegated detectors that the project already configures. A version comes from
   the lockfile or installed metadata. A manifest range (`package.json`, `pyproject.toml`) decides a gate only when
   every version it admits falls on the same side of it. Go reads the `go` line of the module that contains the test.
   An unknown version is recorded (`pytest version: unknown`), and the signals gated on it are skipped.

   TypeScript also records, for each group of test files, whether a checked-in command type-checks them: the command
   runs the compiler on a TypeScript project that includes the files, and the compiler's errors fail the command (the
   TypeScript reference lists the forms). Record `yes` only with that evidence. With `no`, typed doubles of owned code
   in those files are unbound. When the answer cannot be determined, Scope records `type-check of tests not resolved:
   <files>`, and no unbound finding rests on the type check.

6. **Identify the critical code** in scope (Terms). Name each critical unit and why it is critical; Coverage Gaps
   candidates come from reading these units: their branches, limits, error paths, and state transitions. In diff and
   path mode, that is every critical unit in the in-scope production files, not only the changed lines. When the
   in-scope files fit the context budget but their context (tests, real implementations of doubles) does not, read
   each critical unit's tests before other context. Done when every in-scope production file is classed as holding
   named critical units, or none, and every branch, limit, error path, and state transition of each named unit is
   listed as a Coverage Gaps candidate.

### Phase 2: Scan for Candidates

Scans, counts, and detector output **nominate**; nothing is a finding until Phase 6 has read the test and the code it
drives. For each loaded reference, run its Phase 2 scan block: test-quality scans on the test list, coverage-pragma
scans on the production list. Run each delegated detector the loaded reference says to run, with its read-only
command, and record `ran`, `skipped — <reason>`, or `errored — <message>` in Scope; an errored detector's candidates
are not used. Diff mode nominates from the working tree over the manifest files: whether a test can fail is a property
of the current code. The diff itself is Phase 4's.

Done when every scan in each loaded reference's Phase 2 block has run, every detector the loaded references name has
its Scope line, and every hit is listed as a candidate.

### Phase 3: Map Tests and Production Code

Map both directions, project-wide:

- For each in-scope critical production unit: the tests that drive it — symbol references, route paths, command
  names, the distinguishing input of each branch. The search runs over the whole repository, not only the test list,
  so a test outside the shared test paths (Django `tests.py`, Cypress `*.cy.ts`) still counts as coverage. Also
  search every entry point in the language reference's Coverage mapping blind spots list. A unit with no test
  reference of its own is mapped through its callers, up to an entry point that tests drive; the branch's
  distinguishing input then decides whether a test reaches the branch. Each search and its result go in the Test
  Search cell.
- For each in-scope test: the production code it drives, and the real implementation behind each double of owned
  code.

A unit whose tests cannot be traced (reached only through an entry point the search cannot resolve: DI, reflection, a
generated client) is recorded in Scope as `unresolved coverage: <unit> — <reason>`. It is not a finding. A call chain
up to a tested entry point resolves, so it is mapped, not recorded.

A test counts as coverage only when it runs and can fail. A file that no command runs (Never executes) is no
coverage, nor is a form the language reference lists as not coverage (an expected-failure test, a Go `Example` without
an output comment, a fuzz target with no seed).

Done when every Coverage Gaps candidate has a Test Search result (the tests that drive that branch, or none) or its
unit has an `unresolved coverage` line, and every in-scope test has the production code it drives and, for each double
of owned code, its real implementation or a note that it is unresolved.

### Phase 4: Read the Diff — diff mode only

Read the removed lines in test files for assertions the change removed or weakened, the added lines for new skips,
each deleted test path in `<run>/deleted.txt` at the merge base, and the changed lines in production files:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
MB=$(cat <run>/mb); [ -n "$MB" ] || exit 1                          # STOP: empty restore
TESTS=$(cat <run>/*-tests.txt 2>/dev/null | grep -vx /dev/null)     # none in a deletions-only run
PROD=$(cat <run>/*-prod.txt 2>/dev/null | grep -vx /dev/null)
[ -z "$TESTS" ] || git diff -U0 "$MB" -- $TESTS                     # removed assertions, added skips
[ -z "$PROD" ] || git diff -U0 "$MB" -- $PROD                       # changed production behavior
git show "$MB:<deleted test path>"                                  # once per deleted test path
```

Each removed or weakened assertion, added skip, and deleted test is a Weakened in diff candidate: find the production
code it checked, and run Phase 3's search for the remaining tests that drive that code here, also when Phase 3
skipped that language or did not run. Each changed hunk in critical code is
a Coverage Gaps candidate for the reverted-change signal. Path mode skips this phase.

Done when every removed assertion, added skip, and deleted test path is listed as a candidate with the production code
it checked and the remaining tests that drive that code, and every changed hunk in critical code is listed.

### Phase 5: Execute Tests — on request only

**Default: static.** Every category's evidence is reasoned from code; execution only supports it. Without a request in
the prompt, record `test execution: not requested` and skip this phase. On request, read `references/test-execution.md`
and follow it.

### Phase 6: Evaluate Each Finding

For each candidate, in the working tree: apply the general Not-a-finding list and the category's own Not-a-finding
line first; apply the within-skill routing, and if it moved the candidate, the routed category's Not-a-finding line
too; clear the category's evidence bar; then apply the loaded reference's version-gated and config-gated signals.

Work in this order, so that a run the context budget cuts short has judged what matters most: candidates at critical
units first, then tests with a targeted-scan hit, then tests that only the census nominates. When the budget ends
first, Scope records `not assessed: <n> tests, <m> units — context budget`, so the report says that it is partial.

Assign **Severity and Impact** to every finding. Nothing is held back; `Audit completed: N findings` counts every
reported finding.

Done when every candidate is a reported finding, dropped under a named Not-a-finding case or a failed evidence bar,
skipped on an unknown version, handed off to its owning hunter, or counted in the `not assessed` line.

### Phase 7: Produce Report

Save as `YYYY-MM-DD-test-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched. A requested test run is the one
  command that may write, and Scope lists every path it changed.
- **Never install.** Run only tools the project already has. A delegated detector runs only when the project
  configures it, with read-only flags; mutation tools never run.
- **Evidence required.** Every finding cites `file:line` with the exact test or production code, and its category's
  evidence cell is filled from the code read. A Hidden Defect, Accepted Defect, or Breaking Refactor is reasoned from
  that code and names the lines it follows from.
- **One defect, one finding.** The within-skill routing decides the category; a defect owned by another hunter is
  cross-referenced to it and not scored here.
