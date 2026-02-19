---
name: test-hunter
description: |
  Audit Go test code for quality gaps — missing coverage on critical paths, brittle tests
  coupled to implementation, over-mocking, assertion-free tests, missing edge cases,
  table-driven test misuse, and race condition blindness. Focuses on test effectiveness.

  Use when: reviewing Go test suites for reliability, reducing false-positive test failures,
  improving coverage of critical business logic, or cleaning up test debt.
---

# Test Hunter

Audit test code for **quality and coverage gaps** — tests that verify implementation details instead of behavior,
interface-based test doubles so elaborate that nothing real is tested, critical paths with no coverage, and duplicated
setup that makes the suite fragile. The goal: **tests catch real bugs, survive refactors, and cover the paths that
matter most.**

## When to Use

- Reviewing test suites for reliability after frequent false failures
- Improving coverage of critical business logic
- Reducing test maintenance burden (brittle tests, duplicated setup)
- Preparing for a refactor — ensuring tests verify behavior, not implementation
- Auditing test debt after rapid feature development

## Core Principles

1. **Test behavior, not implementation.** A test should verify what the code does, not how it does it. If renaming an
   internal function or reordering private methods breaks a test, the test is coupled to implementation — it will fail
   on safe refactors and pass on real bugs.

2. **Coverage is not confidence.** High line coverage with shallow assertions is worse than focused coverage with
   meaningful assertions on critical paths. Prioritize coverage of business logic, error handling, and edge cases over
   hitting every line.

3. **Prefer real collaborators over test doubles.** Interface-based test doubles are idiomatic in Go, but each one is a
   place where the test diverges from reality. Favor real implementations where possible; use test doubles for external
   boundaries (network, filesystem, clock), not internal packages. If a unit test requires 5+ injected test doubles to
   run, the unit under test has too many dependencies or the test is too isolated.

4. **Tests are code.** They deserve the same quality standards as production code — no duplication, clear naming, and
   readable assertions. A test that requires reading the source to understand what it verifies is a bad test.

5. **Edge cases are where bugs hide.** Empty input, nil, zero, negative numbers, maximum values, Unicode, concurrent
   access, context cancellation — these are the inputs developers forget and users provide.

6. **Table-driven tests are a tool, not a mandate.** Use them when there are genuinely multiple inputs to the same
   logic. A table-driven test with one entry or with entries that exercise fundamentally different code paths is
   misused.

7. **Race detection is non-negotiable.** Go code handling concurrency must be tested with `-race`. Tests that pass
   without `-race` but fail with it are hiding real bugs.

## What to Hunt

### 1. Missing Coverage on Critical Paths

Business logic, error handling, and security-sensitive code with no test coverage.

**Signals:**

- Core domain packages with zero `_test.go` files
- Error return paths with no test exercising them
- Auth/authz logic without tests verifying both allow and deny cases
- Payment, billing, or financial calculation code without test coverage
- State transitions without tests for each valid transition and at least one invalid
- Middleware with no test verifying it blocks unauthorized requests

**Action:** Flag the critical path and its risk level. Recommend specific test cases for the highest-risk gaps.

### 2. Brittle Tests (Implementation Coupling)

Tests that break on safe refactors because they depend on internal details.

**Signals:**

- Assertions on the number of times an internal function was called (via test double counters) where the call count is
  an implementation detail, not a business requirement. (Call-count assertions on boundary interactions — e.g.,
  verifying an email was sent exactly once — may be legitimate when the count is business-significant.)
- Tests that verify the order of internal operations
- Tests that assert on unexported fields via `reflect` or `unsafe`
- Tests that import from internal packages they shouldn't know about
- Tests that assert on exact error message strings instead of error types or `errors.Is`/`errors.As`

**Action:** Rewrite to assert on observable outputs: return values, side effects at boundaries (HTTP responses, DB
state, emitted events), or user-visible behavior.

### 3. Over-Mocking

Tests where so much is replaced with test doubles that the test verifies wiring, not logic.

**Signals:**

- Test file with more interface/mock setup lines than assertion lines
- Interfaces created solely for testing that mirror a single concrete type 1:1
- Package-level test doubles that replace internal packages
- Tests that pass even when the implementation is deleted (because everything is mocked)
- Using a mocking framework (gomock, mockery) for internal collaborators that could run in-process

**Action:** Remove test doubles on internal packages. Mock only external boundaries (network, filesystem, clock,
randomness). If the unit requires many doubles, consider testing at a higher integration level.

### 4. Assertion-Free and Weak Assertions

Tests that execute code but never verify meaningful outcomes.

**Signals:**

- Test with no `t.Error`, `t.Fatal`, assertion library calls, or comparison checks
- Only assertion is `if err != nil` with no check on the actual result
- Tests that check `err == nil` but ignore the returned value entirely
- `t.Log()` used as a substitute for assertions (printing results instead of checking them)
- Error-path tests that only verify `err != nil` without checking the error type or message

**Action:** Add specific assertions on return values, state changes, or side effects. Every test should answer "what
would break if this code had a bug?"

### 5. Missing Edge Case Coverage

Tests that cover the happy path but miss boundary conditions, error cases, and unusual inputs.

**Signals:**

- Only positive test cases (no "should reject invalid input" or "should handle empty slice")
- No tests for: nil input, empty string, zero value, negative numbers, very large values
- No tests for: context cancellation, timeout scenarios, network failures
- No tests for: Unicode input, special characters, maximum length strings
- No tests for: concurrent access (race conditions) on shared state

**Action:** Flag the specific edge cases missing for each function/package. Prioritize by risk: error paths and
boundary conditions in core logic first.

### 6. Table-Driven Test Misuse

Table-driven tests that are poorly structured, have single entries, or mix unrelated test scenarios.

**Signals:**

- Table-driven test with only one test case (use a regular test)
- Table entries that exercise fundamentally different code paths (should be separate tests)
- Missing `t.Run()` with named subtests (failures don't identify which case failed)
- Table fields that are always the same value across all entries (unnecessary parameterization)
- Table entries without a `name` field or with unhelpful names like "test1", "test2"

**Action:** Split unrelated cases into separate tests. Add `t.Run()` with descriptive names. Remove single-entry tables.

### 7. Test Setup Duplication and Shared State

Repeated setup, shared fixtures, and copied test blocks that make the suite fragile and hard to maintain.

**Signals:**

- Identical setup code across multiple test functions in the same file
- Test helper functions that construct complex fixtures duplicated in several packages
- Copy-pasted test cases with minor variations
- Package-level `var` in test files that creates shared mutable state between tests
- `TestMain()` that sets up state used across unrelated tests

**Action:** Extract shared setup into focused test helper functions marked with `t.Helper()`. Parameterize repeated
test cases with table-driven tests. Eliminate shared mutable state between tests.

### 8. Flaky Test Indicators

Patterns that cause tests to pass or fail non-deterministically.

**Signals:**

- Hardcoded `time.Sleep` in tests (timing-dependent)
- Tests that depend on system time, timezone, or locale
- Tests that depend on execution order or shared mutable state
- Network calls in unit tests without stubbing
- Assertions on `time.Now()` or random values without seeding
- File system operations without `t.TempDir()` cleanup
- Tests that fail with `-race` flag
- Goroutine leaks (goroutines started but not waited on)

**Action:** Replace timing waits with channel-based synchronization or polling. Inject clocks and random sources. Use
`t.TempDir()` for filesystem tests. Run all concurrent tests with `-race`.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. Identify the test framework conventions: standard `testing` package, `testify`, `gocheck`, or other assertion
   libraries. Note if the project uses `gomock`, `mockery`, or hand-rolled test doubles.
3. Identify critical business logic packages — these are the priority for coverage analysis.

### Phase 2: Scan for Test Quality Signals

```bash
# Test files
rg -l 'func Test' --type go --glob '*_test.go'

# Assertion-free tests (test functions without error/fatal/assert calls)
rg -U 'func Test\w+\(t \*testing\.T\)\s*\{[^}]*\}' --type go --glob '*_test.go'

# Test double density (count interface/mock declarations per test file)
rg -c '(mock|Mock|fake|Fake|stub|Stub)' --type go --glob '*_test.go' --sort path

# Table-driven tests
rg 'tests? :?= \[\]struct|cases :?= \[\]struct|tt\.name|tc\.name' --type go --glob '*_test.go'

# Timing-dependent patterns
rg 'time\.Sleep|time\.After' --type go --glob '*_test.go'

# Shared mutable state in tests
rg '^\s*var\s+\w+' --type go --glob '*_test.go'

# Missing t.Helper() in test helpers
rg 'func\s+\w+\(t \*testing\.(T|B)' --type go --glob '*_test.go'

# Missing t.Run for subtests
rg 'for.*range.*tests|for.*range.*cases' --type go --glob '*_test.go'

# Coverage gaps: source files without corresponding test files
# (compare .go file list to _test.go file list — project-specific)

# Race-sensitive patterns
rg 'go\s+func|go\s+\w+\(' --type go --glob '*_test.go'
```

### Phase 3: Evaluate Coverage Gaps

1. List critical business logic packages (domain, auth, payments, core algorithms).
2. For each: does a corresponding `_test.go` file exist? Does it cover error paths and edge cases?
3. Flag untested critical paths with specific risk assessment.

### Phase 4: Evaluate Test Quality

For each test file:

- **Coupling**: do assertions target behavior (outputs, errors) or implementation (call counts, internal state)?
- **Test doubles**: are they limited to external boundaries, or do they replace internal packages?
- **Assertions**: are they specific and meaningful, or shallow/absent?
- **Edge cases**: does the suite cover boundary conditions and error paths?
- **Flakiness**: are there timing, ordering, or state dependencies?
- **Table-driven**: are table tests well-structured with descriptive names and `t.Run()`?

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-test-hunter-audit.md` in the project's docs folder (or project root if no docs folder exists).

```md
# Test Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Test framework: {standard testing / testify / gocheck / etc.}
- Mocking approach: {hand-rolled / gomock / mockery / none}
- Exclusions: {list}

## Coverage Gaps

| # | Package | Location | Risk | Test File | Action |
| - | ------- | -------- | ---- | --------- | ------ |
| 1 | payment | file:line | High | None | Add tests for charge, refund, and failure paths |

## Findings

### Brittle Tests

| # | Test | Location | Coupling | Action |
| - | ---- | -------- | -------- | ------ |
| 1 | TestProcessOrder | file:line | Asserts mock called 3 times | Assert on returned order state |

### Over-Mocking

| # | Test File | Location | Doubles | Assertions | Action |
| - | --------- | -------- | ------- | ---------- | ------ |
| 1 | user_test.go | file:line | 8 interfaces | 2 assertions | Remove internal mocks, test at integration level |

### Assertion-Free / Weak Assertions

| # | Test | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | TestCreateUser | file:line | Only checks `err == nil` | Assert on specific user fields |

### Missing Edge Cases

| # | Package | Location | Missing Cases | Action |
| - | ------- | -------- | ------------- | ------ |
| 1 | `ValidateEmail()` | file:line | Empty string, Unicode, max length | Add boundary tests |

### Table-Driven Test Issues

| # | Test | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | TestParse | file:line | Single-entry table | Convert to regular test |

### Test Duplication

| # | Pattern | Locations | Action |
| - | ------- | --------- | ------ |
| 1 | Identical user factory in 5 files | file:line, file:line, ... | Extract shared test helper with t.Helper() |

### Flaky Test Indicators

| # | Test | Location | Pattern | Action |
| - | ---- | -------- | ------- | ------ |
| 1 | TestTimeout | file:line | `time.Sleep(1 * time.Second)` | Use channel synchronization |

## Recommendations (Priority Order)

1. **Must-fix**: {missing coverage on critical paths, assertion-free tests, flaky indicators, missing -race testing}
2. **Should-fix**: {brittle tests, over-mocking, missing edge cases}
3. **Consider**: {test duplication, table-driven cleanup, weak assertions on non-critical code}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: test quality and coverage only.** Do not flag production code issues — type safety (→ invariant-hunter),
  type design (→ type-hunter), structural complexity (→ simplicity-hunter), package boundary issues (→ boundary-hunter),
  interface design (→ solid-hunter), missing documentation (→ doc-hunter), security (→ security-hunter), or
  cosmetic style (→ slop-hunter). If a finding doesn't answer "does this test catch real bugs?", it doesn't belong
  here.
- **Evidence required.** Every finding must cite `file/path.go:line` with the exact test code.
- **Risk-based prioritization.** Coverage gaps in payment logic matter more than coverage gaps in a logging utility.
  Weight findings by the business risk of the untested code.
- **Tests for dependencies are out of scope.** Don't flag missing tests for third-party libraries or standard library
  internals. Focus on the project's own business logic and integration points.
- **Pragmatism.** Not every function needs a test. Thin wrappers, trivial getters, and generated code may not
  warrant dedicated tests. Flag gaps where a bug would have real consequences.
