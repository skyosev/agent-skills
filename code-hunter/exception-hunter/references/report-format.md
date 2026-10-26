# Exception Hunter — report format

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else. A category with no findings gets no heading,
table, or "none found" line; a thin report is a valid result.

**Language versions line.** The versions Phase 1 step 5 recorded, with the file each came from. A version that could
not be read is `unknown`.

**Detectors line.** One entry per detector the language reference names, in one of the states of SKILL.md Phase 2.

**Transport boundaries line.** Only when an Untranslated Boundary Errors (`outward`) finding exists: each framework
with its boundary files, and the non-request entry points.

**Tracker line.** Only when Sentry is found. `skipped — attach_stacktrace on` when every event carries a stack.

**Detector adoption** (Go `errcheck`, TypeScript `no-floating-promises`) is a Low entry under Recommendations, with
no table row. `Audit completed` counts findings only.

**Policy line.** Present only when repository instructions withdrew a pattern; quotes the instruction and names the
category and sites it withdrew.

**Evidence cells** follow each category's evidence bar in SKILL.md; this list gives only the form.

- **Kind** (Swallowed Errors) is one of `dropped`, `logged-only`, `defaulted`, `skipped`, `overridden`,
  `never-raised`.
- **Spawn Form** (Orphaned Async Failures) is the discard form: floating call, `void` discard, `async` callback,
  unwrapped `async` route, `create_task` statement, kept task never read, `executor.submit`, `Thread`, `go`
  statement, or `errgroup` `Wait` discarded.
- **Written For** (Overbroad Handling) names the expected failure and its evidence: the narrow type, the mapped value,
  a comment, or the name.
- **Lost** (Broken Error Chains) is one or more of `cause`, `stack`, `traceback`, `Is/As match`. **Matching Caller**
  is the caller that matches the chain, or `—` when the finding is not Go `%v`.
- **Matches By** (Unmatchable Failures) is `message text`, `==`, `type assertion`, `As target`, `nil check`,
  `builtin type`, `generic class`, or `exception group`.
- **Direction** (Untranslated Boundary Errors) is `inward` or `outward`. **Produces → Should** is the status pair for
  a wrong status, or `—` for `inward` and for a transport error that a non-request entry point reaches (the Boundary
  cell names that entry point).
- **Missing** (Poor Error Context) is one of `input`, `step`, `distinct text`, `fixed text`, with who holds it.
- **Reachable From** (Panic and Exit Misuse) is the entry point or `internal only`; **Recovered By** is the `recover`
  between the panic and the process boundary, or `none`.

```md
# Exception Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name}
- {Base: {ref} → merge base {short SHA} — diff scope only}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker / test paths}
- References loaded: {go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — when applicable, naming each extension}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Language versions: {go 1.22 (go.mod) | requires-python >=3.11 | tsconfig lib es2022; node 20 (engines); express 4 + express-async-errors (api/package.json)}
- Detectors: {per detector — `go vet (errorsas, unusedresult): ran — GOPROXY=off go vet -errorsas …` / `golangci-lint (errcheck, errorlint): ran — golangci-lint run --enable-only=errcheck,errorlint …` / `ruff: ran — ruff check --no-fix --output-format=concise …` / `ESLint: skipped — configured, not installed` / `errcheck: ran — in golangci-lint`}
- {Transport boundaries: {framework — files; non-request entry points}}
- {Tracker: {sentry-sdk or @sentry/* version; event_level (Python); attach_stacktrace / attachStacktrace} — message-event check ran}
- {Policy: "{quoted instruction}" — withdraws {category} at {sites}}
- Audit completed: {N} findings

## Findings

### Swallowed Errors

| # | Location | Code | Kind | Failure Dropped | Severity | Impact | Action |
| - | -------- | ---- | ---- | --------------- | -------- | ------ | ------ |
| 1 | store/save.go:40 | `_ = f.Close()` | dropped | Close on a file opened `O_WRONLY`; caller returns nil, the flush result is lost | Critical | Medium | Named result; return the close error |

### Orphaned Async Failures

| # | Location | Code | Spawn Form | Consequence | Severity | Impact | Action |
| - | -------- | ---- | ---------- | ----------- | -------- | ------ | ------ |
| 1 | api/cache.ts:12 | `void refreshCache()` | `void` discard | crash on Node ≥ 15 (no listener and no `--unhandled-rejections` in the repository; the deploy may override it) | High | Medium | `await refreshCache()`, or a `.catch` that handles the failure |

### Overbroad Handling

| # | Location | Handler | Written For | Also Catches | Severity | Impact | Action |
| - | -------- | ------- | ----------- | ------------ | -------- | ------ | ------ |
| 1 | repo/order.py:41 | `except Exception: return None` | NotFound (`None` read as "no order") | `OperationalError` from `session.execute`; caller `create_order()` inserts a second order | Critical | High | `except NoResultFound: return None` |

### Broken Error Chains

| # | Location | Code | Lost | Matching Caller | Severity | Impact | Action |
| - | -------- | ---- | ---- | --------------- | -------- | ------ | ------ |
| 1 | api/orders.ts:88 | `throw new ServiceError("load failed")` | stack, cause | — | Medium | Medium | `{ cause: err }` |

### Unmatchable Failures

| # | Location | Failure Site | Consumer | Matches By | Severity | Impact | Action |
| - | -------- | ------------ | -------- | ---------- | -------- | ------ | ------ |
| 1 | svc/order.py:57 | `raise RepositoryError(str(e))` at repo/order.py:30 | `if "duplicate" in str(e)` at svc/order.py:57 | message text | Medium | Medium | A `DuplicateOrder` subclass; `except DuplicateOrder` |

### Untranslated Boundary Errors

| # | Location | Direction | Failure | Boundary | Produces → Should | Severity | Impact | Action |
| - | -------- | --------- | ------- | -------- | ----------------- | -------- | ------ | ------ |
| 1 | api/order.go:64 | outward | `ErrOrderNotFound` from `svc.Get` | `writeError` maps every error | 500 → 404 | High | High | Map `ErrOrderNotFound` to 404 in `writeError` |

### Double Handling

| # | Location | First Handling | Second Handling | Severity | Impact | Action |
| - | -------- | -------------- | --------------- | -------- | ------ | ------ |
| 1 | svc/load.go:18 | `log.Printf("load: %v", err); return err` | api/middleware.go:30 logs every returned error | Medium | Medium | Return with context; log at the boundary only |

### Poor Error Context

| # | Location | Code | Missing | Severity | Impact | Action |
| - | -------- | ---- | ------- | -------- | ------ | ------ |
| 1 | svc/user.go:44 | `u, err := s.repo.Find(ctx, id)` then `return nil, err` | input: `id`, held by `Get` | Medium | Medium | `fmt.Errorf("find user %s: %w", id, err)` |

### Panic and Exit Misuse

| # | Location | Pattern | Reachable From | Recovered By | Severity | Impact | Action |
| - | -------- | ------- | -------------- | ------------ | -------- | ------ | ------ |
| 1 | api/handler.go:52 | `panic("bad body")` in `go process(body)` | `POST /orders` | none | Critical | High | Return an error; `400` |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```
