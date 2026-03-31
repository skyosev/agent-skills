---
name: test-hunter-py
description: |
  Audit Python test code for quality gaps — missing coverage on critical paths, brittle
  tests coupled to implementation, over-mocking, assertion-free tests, missing edge cases,
  and duplicated test setup. Focuses on test effectiveness, not production code structure.

  Use when: reviewing Python test suites for reliability, reducing false-positive test
  failures, improving coverage of critical business logic, or cleaning up test debt.
disable-model-invocation: true  
---

# Test Hunter

Audit test code for **quality and coverage gaps** — tests that verify implementation details instead of behavior,
mocking so aggressively that nothing real is tested, critical paths with no coverage, and duplicated setup that makes
the suite fragile. The goal: **tests catch real bugs, survive refactors, and cover the paths that matter most.**

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

2. **Coverage is not confidence.** 100% line coverage with shallow assertions is worse than 70% coverage with
   meaningful assertions on critical paths. Prioritize coverage of business logic, error handling, and edge cases over
   hitting every line.

3. **Mocks are costly.** Every mock is a place where the test diverges from reality. Mock external
   boundaries (network, filesystem, clock), not internal modules. Internal seam mocking can be legitimate
   (e.g., isolating a slow subsystem, testing error paths that are hard to trigger), but each mock is a maintenance
   cost and a potential false-confidence point. If a unit test requires 5+ mocks to run, the unit under test has too
   many dependencies (solid-hunter territory) or the test is too isolated.

4. **Tests are code.** They deserve the same quality standards as production code — no duplication, clear naming, and
   readable assertions. A test that requires reading the source to understand what it verifies is a bad test.

5. **Edge cases are where bugs hide.** Empty input, `None`, zero, negative numbers, maximum values, Unicode, concurrent
   access, timeout — these are the inputs developers forget and users provide.

## What to Hunt

### 1. Missing Coverage on Critical Paths

Business logic, error handling, and security-sensitive code with no test coverage.

**Signals:**

- Core domain functions with no corresponding test coverage (check `coverage.py` reports when available;
  fall back to searching for test file imports as a heuristic, but note this is unreliable with pytest's
  discovery model and black-box integration tests)
- Error handling branches (`except` blocks, error returns) with no test exercising them
- Auth/authz logic without tests verifying both allow and deny cases
- Payment, billing, or financial calculation code without test coverage
- State transitions without tests for each valid transition and at least one invalid

**Action:** Flag the critical path and its risk level. Recommend specific test cases for the highest-risk gaps.

### 2. Brittle Tests (Implementation Coupling)

Tests that break on safe refactors because they depend on internal details.

**Signals:**

- Assertions on the number of times an *internal* function was called (`mock.assert_called_once()`) where the call
  count is an implementation detail, not a business requirement. (Call-count assertions on *boundary* interactions —
  e.g., verifying an email was sent exactly once, or a payment API was charged once — may be legitimate when the count
  is business-significant.)
- Tests that verify the order of internal operations
- Tests that import and assert on private/internal modules (`_` prefixed)
- Tests that assert on string representations or log output as a proxy for behavior
- Tests coupled to specific database query structure

**Action:** Rewrite to assert on observable outputs: return values, side effects at boundaries (HTTP responses, DB
state, emitted events), or user-visible behavior.

### 3. Over-Mocking

Tests where so much is mocked that the test verifies the mock wiring, not the actual logic.

**Signals:**

- Test function with more `patch()`/`Mock()` setup lines than assertion lines
- Mocking internal modules that could run in-process
- Mocking the module under test (partial mocks that bypass the code being tested)
- `@patch` decorators stacked 3+ deep on a single test function
- Tests that pass even when the implementation is deleted (because everything is mocked)

**Action:** Remove mocks on internal modules. Mock only external boundaries (network, filesystem, clock, randomness).
If the unit requires many mocks, consider testing at a higher integration level.

### 4. Assertion-Free and Weak Assertions

Tests that execute code but never verify meaningful outcomes.

**Signals:**

- Test with no `assert` statement or `pytest.raises()` call
- Only assertion is `assert result is not None` or `assert not raises`
- Assertions on truthiness (`assert result`) when a specific value is expected
- `try/except` in test that swallows assertion errors
- Tests that only check the type of the result, not its content

**Action:** Add specific assertions on return values, state changes, or side effects. Every test should answer "what
would break if this code had a bug?"

### 5. Missing Edge Case Coverage

Tests that cover the happy path but miss boundary conditions, error cases, and unusual inputs.

**Signals:**

- Only positive test cases (no "should reject invalid input" or "should handle empty list")
- No tests for: empty input, `None`, zero, negative numbers, very large values
- No tests for: concurrent access, timeout scenarios, network failures
- No tests for: Unicode input, special characters, injection strings
- Pagination logic tested only for page 1
- No tests for boundary values (off-by-one: 0, 1, max-1, max)

**Action:** Flag the specific edge cases missing for each function/module. Prioritize by risk: error paths and
boundary conditions in core logic first.

### 6. Test Duplication and Setup Bloat

Repeated setup, shared fixtures, and copied test blocks that make the suite fragile and hard to maintain.

**Signals:**

- Identical `@pytest.fixture` definitions across multiple test files
- Test factory functions that construct complex objects duplicated in several places
- Copy-pasted test cases with minor variations (only one value changes)
- Global test state shared between tests (order-dependent tests)
- `conftest.py` files over 200 lines
- Repeated `@patch` decorators across many test functions in same file

**Action:** Extract shared setup into focused fixtures or factory functions in `conftest.py`. Parameterize repeated
test cases with `@pytest.mark.parametrize`. Eliminate shared mutable state between tests.

### 7. Flaky Test Indicators

Patterns that cause tests to pass or fail non-deterministically.

**Signals:**

- Hardcoded `time.sleep()` / `asyncio.sleep()` in tests (timing-dependent)
- Tests that depend on system time, timezone, or locale
- Tests that depend on execution order or shared mutable state
- Network calls in unit tests without mocking
- Assertions on `datetime.now()` or random values without seeding/freezing
- File system operations without cleanup (leftover state between runs)
- Tests that depend on dict ordering (guaranteed in CPython 3.7+ but may indicate fragility)

**Action:** Replace timing waits with polling/event-based assertions. Freeze time with `freezegun` or
`unittest.mock.patch`. Isolate tests from shared state and external dependencies. Use `tmp_path` fixture for file
operations.

### 8. Async Test Antipatterns

Patterns specific to async Python testing that cause silent skips, resource leaks, or false passes.

**Signals:**

- `async def test_*` without `@pytest.mark.asyncio` decorator (test is collected but never awaited — silently passes
  without executing the body). Only applies when `asyncio_mode` is not set to `"auto"` in `pyproject.toml`/`conftest.py`
- Async fixtures (`async def` in `@pytest.fixture`) without `@pytest_asyncio.fixture` (fixture returns a coroutine
  object instead of the resolved value)
- `asyncio.run()` called inside a test function that already runs in an event loop (nested event loop error, or
  masked by `nest_asyncio`)
- Async resources opened in fixtures without cleanup: `session = AsyncSession()` yielded but not closed/rolled-back
  in the `finally`/`yield` teardown
- Missing `pytest-asyncio` `mode` configuration causing inconsistent behavior between `strict` and `auto` modes
  across the test suite
- `aiohttp.ClientSession()` or `httpx.AsyncClient()` created in test body without `async with` (resource leak)
- Sync mock (`MagicMock`) used where `AsyncMock` is needed — mock returns a `MagicMock` object instead of awaiting

**Action:** Use `@pytest.mark.asyncio` or configure `asyncio_mode = "auto"`. Use `@pytest_asyncio.fixture` for async
fixtures. Wrap async resources in `async with` in test bodies and fixture teardown. Use `AsyncMock` for async
interfaces. Verify tests actually execute by adding a deliberate failure and confirming it's caught.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed on the current branch vs base (`main`/`master`)
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project
   If unspecified, default to **codebase**. For diff mode, resolve the file list:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
   SCOPE=$(git diff --name-only $(git merge-base HEAD $BASE)...HEAD)
   ```
   Constrain all subsequent scans to the resolved surface.
2. Identify the test framework (pytest, unittest, nose2) and test file conventions (`test_*.py`, `*_test.py`,
   `tests/` directories).
3. Identify critical business logic modules — these are the priority for coverage analysis.

### Phase 2: Scan for Test Quality Signals

```bash
# Test files
rg -l '(def test_|class Test)' --type py --glob '**/*test*'

# Assertion-free tests (test functions without assert/raises — verify manually)
rg -U 'def test_\w+\s*\([^)]*\)\s*:' --type py --glob '**/*test*'

# Mock density (count patch/Mock calls per file)
rg -c '(@patch|Mock\(|MagicMock\(|patch\()' --type py --glob '**/*test*' --sort path

# Stack of patches
rg --pcre2 '(@patch.*\n){3,}' --type py --glob '**/*test*'

# Timing-dependent patterns
rg 'time\.sleep|asyncio\.sleep' --type py --glob '**/*test*'

# Shared mutable state in tests
rg '(global\s|module-level.*=)' --type py --glob '**/*test*'

# Coverage gaps: source files without corresponding test files
# (compare src file list to test file list — project-specific)

# Weak assertions
rg 'assert\s+\w+\s+is not None$|assert\s+result$|assert\s+True$' --type py --glob '**/*test*'

# Async test antipatterns
rg 'async def test_' --type py --glob '**/*test*'                     # async test functions
rg '@pytest.mark.asyncio' --type py --glob '**/*test*'                # marked tests
rg 'asyncio\.run\(' --type py --glob '**/*test*'                      # nested event loop risk
rg 'MagicMock\(' --type py --glob '**/*test*'                         # may need AsyncMock
rg 'asyncio_mode' --glob '**/pyproject.toml' --glob '**/conftest.py'  # mode configuration
```

### Phase 3: Evaluate Coverage Gaps

1. List critical business logic modules (domain, auth, payments, core algorithms).
2. For each: does a corresponding test file exist? Does it cover error paths and edge cases?
3. Flag untested critical paths with specific risk assessment.

### Phase 4: Evaluate Test Quality

For each test file:

- **Coupling**: do assertions target behavior (outputs, side effects) or implementation (call counts, internal state)?
- **Mocking**: are mocks limited to external boundaries, or are internal modules mocked?
- **Assertions**: are they specific and meaningful, or shallow/absent?
- **Edge cases**: does the suite cover boundary conditions and error paths?
- **Flakiness**: are there timing, ordering, or state dependencies?

### Phase 5: Produce Report

## Output Format

Save as `YYYY-MM-DD-test-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs folder
exists).

```md
# Test Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Test framework: {pytest / unittest / nose2 / etc.}
- Exclusions: {list}

## Coverage Gaps

| # | Module | Location | Risk | Test File | Action |
| - | ------ | -------- | ---- | --------- | ------ |
| 1 | PaymentService | file:line | High | None | Add tests for charge, refund, and failure paths |

## Findings

### Brittle Tests

| # | Test | Location | Coupling | Action |
| - | ---- | -------- | -------- | ------ |
| 1 | `test_process_order` | file:line | Asserts `save` called 3 times | Assert on returned order state |

### Over-Mocking

| # | Test File | Location | Mocks | Assertions | Action |
| - | --------- | -------- | ----- | ---------- | ------ |
| 1 | test_user.py | file:line | 8 @patch | 2 assertions | Remove internal mocks, test at integration level |

### Assertion-Free / Weak Assertions

| # | Test | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | `test_create_user` | file:line | Only checks `is not None` | Assert on specific user fields |

### Missing Edge Cases

| # | Module | Location | Missing Cases | Action |
| - | ------ | -------- | ------------- | ------ |
| 1 | `validate_email()` | file:line | Empty string, Unicode, max length | Add boundary tests |

### Test Duplication

| # | Pattern | Locations | Action |
| - | ------- | --------- | ------ |
| 1 | Identical user factory in 5 files | file:line, file:line, ... | Extract shared fixture to conftest.py |

### Flaky Test Indicators

| # | Test | Location | Pattern | Action |
| - | ---- | -------- | ------- | ------ |
| 1 | `test_timeout` | file:line | `time.sleep(1)` | Use freezegun or event-based assertion |

### Async Test Antipatterns

| # | Test | Location | Pattern | Action |
| - | ---- | -------- | ------- | ------ |
| 1 | `test_fetch_data` | file:line | Missing `@pytest.mark.asyncio` | Add decorator or configure `asyncio_mode = "auto"` |

## Recommendations (Priority Order)

1. **Must-fix**: {missing coverage on critical paths, assertion-free tests, flaky indicators}
2. **Should-fix**: {brittle tests, over-mocking, missing edge cases}
3. **Consider**: {test duplication, weak assertions on non-critical code, async test cleanup}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: test quality and coverage only.** Do not flag production code issues — type invariants (→ invariant-hunter-py),
  type design (→ type-hunter-py), structural complexity (→ simplicity-hunter-py), module boundary issues
  (→ boundary-hunter-py), class/interface design (→ solid-hunter-py), missing documentation (→ doc-hunter-py), security
  (→ security-hunter-py), or cosmetic style (→ slop-hunter-py). If a finding doesn't answer "does this test catch real
  bugs?", it doesn't belong here.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact test code.
- **Risk-based prioritization.** Coverage gaps in payment logic matter more than coverage gaps in a logging utility.
  Weight findings by the business risk of the untested code.
- **Tests for dependencies are out of scope.** Don't flag missing tests for third-party libraries or framework
  internals. Focus on the project's own business logic and integration points.
- **Pragmatism.** Not every function needs a test. Thin wrappers, trivial properties, and one-line utilities may not
  warrant dedicated tests. Flag gaps where a bug would have real consequences.
