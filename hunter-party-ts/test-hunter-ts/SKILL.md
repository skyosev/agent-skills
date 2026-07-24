---
name: test-hunter-ts
description: |
  Audit TypeScript test code for quality gaps — missing coverage on critical paths, brittle
  tests coupled to implementation, over-mocking, assertion-free tests, missing edge cases,
  and duplicated test setup. Focuses on test effectiveness, not production code structure.

  Use when: reviewing TypeScript test suites for reliability, reducing false-positive test
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

3. **Mocks are a debt, not a tool.** Every mock is a place where the test diverges from reality. Mock external
   boundaries (network, filesystem, clock), not internal modules. If a unit test requires 5+ mocks to run, the unit
   under test has too many dependencies (solid-hunter territory) or the test is too isolated.

4. **Tests are code.** They deserve the same quality standards as production code — no duplication, clear naming, and
   readable assertions. A test that requires reading the source to understand what it verifies is a bad test.

5. **Edge cases are where bugs hide.** Empty input, null, zero, negative numbers, maximum values, Unicode, concurrent
   access, timeout — these are the inputs developers forget and users provide.

## What to Hunt

### 1. Missing Coverage on Critical Paths

Business logic, error handling, and security-sensitive code with no test coverage.

**Signals:**

- Core domain functions with zero test files or zero imports in test files
- Error handling branches (catch blocks, error returns) with no test exercising them
- Auth/authz logic without tests verifying both allow and deny cases
- Payment, billing, or financial calculation code without test coverage
- State transitions without tests for each valid transition and at least one invalid

**Action:** Flag the critical path and its risk level. Recommend specific test cases for the highest-risk gaps.

### 2. Brittle Tests (Implementation Coupling)

Tests that break on safe refactors because they depend on internal details.

**Signals:**

- Assertions on the number of times an *internal* function was called (`expect(fn).toHaveBeenCalledTimes(3)`) where
  the call count is an implementation detail, not a business requirement. (Call-count assertions on *boundary*
  interactions — e.g., verifying an email was sent exactly once, or a payment API was charged once — may be legitimate
  when the count is business-significant.)
- Tests that verify the order of internal operations
- Snapshot tests on large structures that change frequently
- Tests that import and assert on private/internal modules
- CSS selector or DOM structure assertions that break on styling changes

**Action:** Rewrite to assert on observable outputs: return values, side effects at boundaries (HTTP responses, DB
state, emitted events), or user-visible behavior.

### 3. Over-Mocking

Tests where so much is mocked that the test verifies the mock wiring, not the actual logic.

**Signals:**

- Test file with more mock setup lines than assertion lines
- Mocking internal modules that could run in-process
- Mocking the module under test (partial mocks that bypass the code being tested)
- `jest.mock()` / `vi.mock()` at the top of every test file for internal dependencies
- Tests that pass even when the implementation is deleted (because everything is mocked)

**Action:** Remove mocks on internal modules. Mock only external boundaries (network, filesystem, clock, randomness).
If the unit requires many mocks, consider testing at a higher integration level.

### 4. Assertion-Free and Weak Assertions

Tests that execute code but never verify meaningful outcomes.

**Signals:**

- Test with no `expect()` / `assert()` calls
- Only assertion is `expect(result).toBeDefined()` or `expect(fn).not.toThrow()`
- Assertions on truthiness (`toBeTruthy()`) when a specific value is expected
- `try/catch` in test that swallows assertion errors
- Snapshot tests used as a substitute for specific assertions

**Action:** Add specific assertions on return values, state changes, or side effects. Every test should answer "what
would break if this code had a bug?"

### 5. Missing Edge Case Coverage

Tests that cover the happy path but miss boundary conditions, error cases, and unusual inputs.

**Signals:**

- Only positive test cases (no "should reject invalid input" or "should handle empty list")
- No tests for: empty input, null/undefined, zero, negative numbers, very large values
- No tests for: concurrent access, timeout scenarios, network failures
- No tests for: Unicode input, special characters, injection strings
- Pagination logic tested only for page 1

**Action:** Flag the specific edge cases missing for each function/module. Prioritize by risk: error paths and
boundary conditions in core logic first.

### 6. Test Duplication and Setup Bloat

Repeated setup, shared fixtures, and copied test blocks that make the suite fragile and hard to maintain.
Duplication *within test code* is owned here (simplicity-hunter owns duplication across production code and
excludes test files).

**Signals:**

- Identical `beforeEach` blocks across multiple test files
- Test helper functions that construct complex fixtures duplicated in several places
- Copy-pasted test cases with minor variations (only one value changes)
- Global test state shared between tests (order-dependent tests)
- Test utility files over 200 lines

**Action:** Extract shared setup into focused test factories or builders. Parameterize repeated test cases with
`test.each` / `it.each`. Eliminate shared mutable state between tests.

### 7. Flaky Test Indicators

Patterns that cause tests to pass or fail non-deterministically.

**Signals:**

- Hardcoded `setTimeout` / `sleep` in tests (timing-dependent)
- Tests that depend on system time, timezone, or locale
- Tests that depend on execution order or shared mutable state
- Network calls in unit tests without mocking
- Assertions on `Date.now()` or random values without seeding
- File system operations without cleanup (leftover state between runs)
- HTTP servers, database clients, or connections created in tests without `close()` in `afterAll`/`afterEach`
  (leaks state between runs and hangs test processes)

**Action:** Replace timing waits with polling/event-based assertions. Mock `Date.now()` and random sources. Isolate
tests from shared state and external dependencies. Close every server/client opened by a test in a teardown hook.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve audit surface.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or layers
   - **Codebase**: the entire project (the default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot (a resolved file list), use it verbatim and do
   not re-resolve. The resolution below applies to standalone runs only.

   For diff mode, resolve fail-closed:
   ```bash
   BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
   if [ -z "$BASE" ]; then
     for b in origin/main origin/master main master; do
       git rev-parse -q --verify "$b" >/dev/null && BASE=$b && break
     done
   fi
   # If BASE is still empty: STOP. Ask for an explicit base. Do not continue.

   SCOPE=$( { git diff --name-only --diff-filter=d "$BASE"...HEAD;
              git diff --name-only --diff-filter=d HEAD;
              git ls-files --others --exclude-standard; } | sort -u )
   DELETED=$( { git diff --name-only --diff-filter=D "$BASE"...HEAD;
                git diff --name-only --diff-filter=D HEAD; } | sort -u )
   ```
   If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope",
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop — deleted test files are themselves
   coverage-relevant context. If the resolved surface exceeds what can be read within the context budget, report
   the file count and ask to narrow or chunk.

   **Two surfaces.** Findings are reported only against the **target scope** (`$SCOPE`) — every finding anchors
   (file:line) there. The prod-to-test mapping is inherently two-sided **context**: for in-scope production files,
   read their tests even when the tests are outside the scope (and vice versa); anchor coverage-gap findings at
   the in-scope file.
2. Identify the test framework (Jest, Vitest, Mocha, Playwright, etc.) and test file conventions.
3. Identify critical business logic modules — these are the priority for coverage analysis.

### Phase 2: Scan for Test Quality Signals

Run every scan against the target scope (`SCOPE=.` in codebase mode). Test *discovery* deliberately has no test
exclusions — this hunter audits the files the other hunters exclude.

```bash
# Base exclusions only: dependencies, build output, generated code — tests stay in
EXCLUDE_BASE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/**'

# Test-discovery globs — covers *.test.*, *.spec.*, __tests__/ directories, and *.e2e.* (Playwright et al.)
TESTS='--glob **/*.test.* --glob **/*.spec.* --glob **/__tests__/** --glob **/*.e2e.*'

# Test files
rg -l '(describe|it|test)\s*\(' --type ts $EXCLUDE_BASE $TESTS -- $SCOPE

# Short test bodies — inspect manually. This CANNOT detect the absence of assertions
# (a regex has no per-test-block AST view); the durable detector is the `expect-expect`
# rule from eslint-plugin-jest / eslint-plugin-vitest. Use its output if configured;
# otherwise recommend enabling it in the report — do not install or reconfigure lint.
rg -U 'it\s*\([^)]+,\s*(async\s+)?(\([^)]*\)\s*=>|function)\s*\{[^}]*\}' --type ts $EXCLUDE_BASE $TESTS -- $SCOPE

# Mock density (count mock calls per file)
rg -c '(jest|vi)\.(mock|fn|spyOn)' --type ts $EXCLUDE_BASE $TESTS --sort path -- $SCOPE

# Snapshot tests
rg 'toMatchSnapshot|toMatchInlineSnapshot' --type ts $EXCLUDE_BASE $TESTS -- $SCOPE

# Timing-dependent patterns
rg 'setTimeout|sleep|delay|waitFor' --type ts $EXCLUDE_BASE $TESTS -- $SCOPE

# Module-level mutable state in test files (word-bounded so 'outlet'/'variable' don't match)
rg '\b(let|var)\s+\w+' --type ts $EXCLUDE_BASE $TESTS -- $SCOPE

# Unclosed servers/clients in tests (check for close() in afterAll/afterEach)
rg 'listen\(|createServer\(|new PrismaClient\(|new Redis\(' --type ts $EXCLUDE_BASE $TESTS -- $SCOPE

# Coverage gaps: source files without corresponding test files
# (compare src file list to test file list — project-specific)
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

Save as `YYYY-MM-DD-test-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies an
output path (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels (including the Risk column) and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

```md
# Test Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Test framework: {Jest / Vitest / Mocha / etc.}
- Exclusions: {list}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Audit completed: {N} findings

## Coverage Gaps

| # | Module | Location | Risk | Test File | Action |
| - | ------ | -------- | ---- | --------- | ------ |
| 1 | PaymentService | file:line | High | None | Add tests for charge, refund, and failure paths |

## Findings

### Brittle Tests

| # | Test | Location | Coupling | Action |
| - | ---- | -------- | -------- | ------ |
| 1 | "should process order" | file:line | Asserts `save` called 3 times | Assert on returned order state |

### Over-Mocking

| # | Test File | Location | Mocks | Assertions | Action |
| - | --------- | -------- | ----- | ---------- | ------ |
| 1 | user.test.ts | file:line | 8 mocks | 2 assertions | Remove internal mocks, test at integration level |

### Assertion-Free / Weak Assertions

| # | Test | Location | Issue | Action |
| - | ---- | -------- | ----- | ------ |
| 1 | "should create user" | file:line | Only checks `toBeDefined()` | Assert on specific user fields |

### Missing Edge Cases

| # | Module | Location | Missing Cases | Action |
| - | ------ | -------- | ------------- | ------ |
| 1 | `validateEmail()` | file:line | Empty string, Unicode, max length | Add boundary tests |

### Test Duplication

| # | Pattern | Locations | Action |
| - | ------- | --------- | ------ |
| 1 | Identical user factory in 5 files | file:line, file:line, ... | Extract shared test factory |

### Flaky Test Indicators

| # | Test | Location | Pattern | Action |
| - | ---- | -------- | ------- | ------ |
| 1 | "should timeout" | file:line | `setTimeout(1000)` | Use fake timers or polling |

## Recommendations (Priority Order)

1. **Critical**: {zero coverage on payment/auth/data-integrity paths where a bug ships silently}
2. **High**: {missing coverage on critical paths, assertion-free tests, flaky indicators}
3. **Medium**: {brittle tests, over-mocking, missing edge cases}
4. **Low**: {test duplication, snapshot overuse, weak assertions on non-critical code}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line in the Scope section is always present, even at zero findings.
- **Scope: test quality and coverage only.** If a finding doesn't answer "does this test catch real bugs?", it
  belongs to another hunter — do not flag it here. Duplication within test code is owned here; duplication across
  production code is simplicity-hunter's.
- **Evidence required.** Every finding must cite `file/path.ext:line` with the exact test code.
- **Risk-based prioritization.** Coverage gaps in payment logic matter more than coverage gaps in a logging utility.
  Weight findings by the business risk of the untested code.
- **Tests for dependencies are out of scope.** Don't flag missing tests for third-party libraries or framework
  internals. Focus on the project's own business logic and integration points.
- **Pragmatism.** Not every function needs a test. Thin wrappers, trivial getters, and one-line utilities may not
  warrant dedicated tests. Flag gaps where a bug would have real consequences.
