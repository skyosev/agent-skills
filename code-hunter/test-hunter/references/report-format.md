# Test Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

A deletions-only run's Scope holds the lines of Phase 1 steps 1 to 3, `References loaded`, `Deleted in diff`, and
`Audit completed`. Findings and Recommendations follow as on any other run.

**Test toolchain lines.** `Test framework` lists, per language, the framework and its version with the version's
source, and the `go` line for Go; `Doubles` lists, per language, the double library. An unknown version names the
signals it skipped: `pytest version: unknown — skipped: async test that no plugin handles`.

**Detectors line.** One entry per delegated detector the language reference names: `<detector>: ran — <command>` /
`skipped — not configured` / `skipped — configured, not installed` / `errored — <message>`. Output of an errored
detector is not used.

**Test execution line.** `not requested` / `ran — <command>` / `ran — <command>: <n> failed` / `skipped — no test
command` / `skipped — command updates snapshots` / `errored — timed out` / `errored — <message>`. After a run,
every path whose status or content changed is listed.

**Evidence cells** follow each category's evidence bar in SKILL.md. Location is `file:line`; a deleted test is
`<path> (deleted)`. Test names the test in the language reference's evidence path form; a per-file row (unbound
doubles, a missing `-race`) gives the file path. Test Search is `none` or the tests found. Oracle Trace ends with the
kind in parentheses. Kind is `Absent`, `Never executes`, `Weak`, or `Weakened in diff`.

```md
# Test Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name}
- {Base: {ref} → merge base {short SHA} — diff scope only}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists, each split into test list and production list}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker}
- References loaded: {go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — naming each extension}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Test framework: {per language — `go: testing + testify v1.9.0 (go.mod), go 1.25` / `python: pytest 8.4.1 (uv.lock), pytest-asyncio 0.24 strict` / `typescript: vitest 2.1.8 (pnpm-lock.yaml)`}
- Doubles: {per language — `go: hand-written fakes, gomock` / `python: unittest.mock` / `typescript: vi.fn`}
- {<framework> version: unknown — skipped: {gated signals}}
- Detectors: {per language — `go vet -testinggoroutine: ran — GOPROXY=off go vet -testinggoroutine ./...` / `golangci-lint testifylint: skipped — not configured` / `ruff: errored — <message>`}
- Critical units: {count} — {names}
- Test execution: {not requested / ran — <command> / ran — <command>: <n> failed / skipped — no test command / skipped — command updates snapshots / errored — timed out / errored — <message>}
- {Paths changed by the test run: {list}}
- {Failed tests: {list} — when the run had failures}
- {no tests found: <lang>}
- {unresolved coverage: {unit} — {reason}}
- {focused test under {runner}: {file:line} — runner not covered; no finding}
- Audit completed: {N} findings

## Findings

### Coverage Gaps

| # | Location | Unit | Untested Behavior | Test Search | Severity | Impact | Action |
| - | -------- | ---- | ----------------- | ----------- | -------- | ------ | ------ |
| 1 | auth/policy.go:58 | `Authorize` — authorization decision | deny path when the role lacks `refund:write` | `rg -w Authorize`: policy_test.go:12 (allow path only); route `"/v1/refunds"`: none | High | High | Add `TestAuthorizeDeniesRefundWithoutScope`: role `viewer` → `ErrForbidden` |
| 2 | billing/refund.py:41 | `compute_refund` — money calculation | partial refund after tax | `rg -w compute_refund`: tests/test_refund.py:9, blind (expected value from `compute_refund` itself) | High | Medium | Add a case with a hand-worked value: 40.00 net returned + 20% tax → 48.00; suspected: rounds before tax at refund.py:52 |

### Tautological Tests

| # | Location | Test | Oracle Trace | Hidden Defect | Severity | Impact | Action |
| - | -------- | ---- | ------------ | ------------- | -------- | ------ | ------ |
| 1 | order_test.go:41 | `TestTotal` | want ← Total(order) (subject on both sides) | any change to Total, e.g. dropping the discount, stays green | High | Medium | Replace want with 1750 from the worked example 2 × 1000 − 250 |
| 2 | price.test.ts:18 | `price › applies VAT` | expected ← `net * (1 + VAT_RATE)`, the formula at price.ts:9 (mirror computation) | a wrong VAT rule shared by both copies stays green | Medium | Medium | Assert 120.00 for a net of 100.00 at 20% |

### Inert and Weak Tests

| # | Location | Test | Kind | Accepted Defect | Severity | Impact | Action |
| - | -------- | ---- | ---- | --------------- | -------- | ------ | ------ |
| 1 | user.test.ts:30 | `user › loads profile` | Never executes | `expect(load()).resolves` without `await` under Jest: the test ends before the assertion runs | Medium | Medium | `await expect(load()).resolves.toEqual(profile)` |
| 2 | auth_test.go (deleted) | `TestRefundRequiresScope` | Weakened in diff | `ErrorIs(err, ErrForbidden)` at merge base auth_test.go:31; the deny path is still at auth/policy.go:58; `rg -w Authorize`: policy_test.go:12, allow path only | High | High | Restore the test, or name the test that replaces it |

### Brittle Tests

| # | Location | Test | Coupling | Breaking Refactor | Severity | Impact | Action |
| - | -------- | ---- | -------- | ----------------- | -------- | ------ | ------ |
| 1 | tests/test_order.py:77 | `tests/test_order.py::test_total` | `apply_discount` call count | inline `apply_discount` into `total`: the count assertion fails | Medium | Medium | Assert the returned total |

### Test Double Misuse

| # | Location | Test | Double | Divergence | Severity | Impact | Action |
| - | -------- | ---- | ------ | ---------- | -------- | ------ | ------ |
| 1 | store/order_test.go:22 | `TestLoadOrder` | `fakeRepo.Find` | store/repo.go:52 returns `ErrNotFound`; the fake returns `nil, nil`, so the not-found path never runs | High | Medium | Return `ErrNotFound` from the fake for unknown IDs |
| 2 | tests/test_mailer.py:8 | `tests/test_mailer.py` | `MagicMock()` for `Mailer` | unbound: no `spec` at lines 8, 31, 47 | Low | Low | `create_autospec(Mailer)` |

### Test Setup Duplication

| # | Pattern | Locations | Severity | Impact | Action |
| - | ------- | --------- | -------- | ------ | ------ |
| 1 | Same order builder | order_test.go:12, invoice_test.go:9, refund_test.go:15 | Low | Medium | One `newTestOrder(t, opts...)` builder with defaults |

### Flaky Test Indicators

| # | Location | Test | Pattern | Nondeterminism Source | Severity | Impact | Action |
| - | -------- | ---- | ------- | --------------------- | -------- | ------ | ------ |
| 1 | worker_test.go:33 | `TestWorkerDrains` | `time.Sleep(100 * time.Millisecond)` | scheduling of the goroutine started at worker.go:40 | Medium | Medium | Wait on the `done` channel `Start` returns |

## Recommendations (Priority Order)

Group by Severity (High → Medium → Low). Within each group, order by Impact (High → Medium → Low). Each
recommendation names the test to add, rewrite, or delete, and the defect it will catch or the drift it prevents.
```
