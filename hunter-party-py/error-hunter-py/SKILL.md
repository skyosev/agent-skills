---
name: error-hunter-py
description: |
  Audit Python code for error handling design quality — missing exception hierarchies, lost
  exception chains, return-None antipatterns, over-broad try/except, silent suppression,
  poor exception context, framework handler gaps, and missing error boundaries.

  Use when: reviewing error handling strategy, tightening exception design before deployment,
  auditing error propagation paths, standardizing API error responses, or establishing
  error handling conventions after rapid feature development.
---

# Error Hunter

Audit Python code for **error handling design quality** — whether exceptions are structured intentionally, propagated
correctly, caught at the right boundaries, and converted to appropriate responses. The goal: **exceptions are part of
the API contract, error boundaries are clearly defined, and every except block justifies its existence.**

This skill focuses on *error handling design* — the strategy of how errors are raised, propagated, caught, and
converted. For type-system enforcement of invariants (`Any`, `cast()`, `# type: ignore`), see invariant-hunter-py.
For security implications of error patterns (stack trace leakage, auth bypass on error), see security-hunter-py.

## When to Use

- Reviewing error handling strategy before production deployment
- Tightening exception design after initial prototyping
- Auditing error propagation paths to ensure domain exceptions don't leak through layers
- Standardizing API error responses across endpoints
- Establishing error handling conventions for a growing codebase
- Investigating why errors are silently swallowed or produce unhelpful diagnostics
- Preparing a codebase for better observability (structured logging, error tracking)

## Core Principles

1. **Exceptions are part of the API.** The exceptions a function raises are as much part of its contract as its return
   type. Document them, type them, and design them intentionally.

2. **Hierarchy mirrors the domain.** Exception classes should reflect domain concepts (`OrderNotFoundError`,
   `PaymentDeclinedError`), not technical categories (`DatabaseError` leaking from domain). Technical exceptions belong
   at the infrastructure boundary.

3. **Chain, don't replace.** When wrapping an exception, always use `raise X from Y`. The original traceback is the
   most valuable debugging information — losing it is a bug.

4. **Raise, don't return None.** Functions should raise on failure and return values on success. `Optional` return
   types are for genuinely absent data (not-found is a valid domain outcome), not for errors. When explicit error paths
   are needed, consider a Result type pattern.

5. **Fail loudly in non-boundary code.** Business logic and domain code should let exceptions propagate. Only catch at
   defined boundaries: API handlers, middleware, background task runners, CLI entry points.

6. **Every except block must justify its existence.** A catch is justified if it: (a) recovers meaningfully,
   (b) wraps and re-raises at a boundary, or (c) converts to an appropriate error response. Catch-log-swallow is
   almost never justified.

7. **Standardize error responses.** API error shapes should be consistent across the entire application. Pick one
   format (RFC 7807 Problem Details, or a simple `{"type", "title", "detail", "status"}` shape) and use it everywhere.

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| `except Exception` at API boundary | Top-level handler converting to 500 response |
| `return None` for not-found | Repository `.find_by_id()` where absence is a normal outcome |
| Catch-and-log without re-raise | Background task runners with defined retry logic |
| Generic `ValueError` | Input validation in pure utility functions with no domain context |
| `except Exception` in test helpers | Test utilities where failure mode doesn't matter |

## What to Hunt

### 1. Missing Exception Hierarchy

Flat `raise Exception("...")` instead of domain-specific exception classes. No base `ApplicationError`. Exception names
without `Error` suffix.

**Signals:**

- `raise Exception(` used for domain-specific error conditions
- `raise ValueError("generic message")` used for domain errors instead of domain-specific exceptions
- No custom exception classes in the project despite non-trivial domain logic
- Exception class names without `Error` suffix (inconsistent naming convention)
- No base `ApplicationError` or `DomainError` for the project's exception hierarchy

**Action:** Create a domain exception hierarchy: `ApplicationError` → `NotFoundError`, `ValidationError`,
`AuthorizationError`, etc. Use `Error` suffix consistently. Keep the hierarchy shallow (2-3 levels max).

### 2. Missing Exception Chaining

`raise X` inside `except Y` without `from Y`, losing the original traceback and context.

**Signals:**

- `except SomeError: raise OtherError(...)` without `from`
- `raise` followed by a different exception type with no chaining
- Exception wrapping at layer boundaries (service catching infrastructure errors) without `from original_error`
- Log messages that reconstruct exception info via `str(e)` because the chain was lost upstream

**Action:** Add `from original_error` to preserve the exception chain. Use `raise X from None` only when deliberately
suppressing the chain (rare — document the reason).

### 3. Return-None Antipattern

Functions returning `None` on error instead of raising, conflating "not found" with "error" with "no result."

**Signals:**

- `return None` inside except blocks
- Functions with `-> Optional[X]` where `None` means both "not found" and "error"
- Caller code doing `if result is None` without knowing why the result is absent
- Functions that return `None` on infrastructure failures (DB connection error, timeout) instead of raising
- Mixed return patterns: same function returns `None` on some errors and raises on others

**Action:** Raise specific exceptions for errors. Use `Optional` only for genuinely absent data (e.g., repository
`find_by_id` returning `None` for a missing record). Consider Result type patterns for explicit error paths where
exceptions are too heavy.

### 4. Over-Broad Try/Except

Try blocks wrapping too many statements when only one can raise the caught exception. Catching `Exception` when a
specific type is appropriate.

**Signals:**

- `try:` blocks spanning 10+ lines
- `except Exception:` in non-boundary code
- `except Exception as e: pass` or `except Exception as e: log(e)` without recovery
- Catching base `Exception` where `ValueError`, `KeyError`, `TypeError` etc. would be specific enough
- Try/except wrapping an entire function body instead of the specific risky operation

**Action:** Narrow try blocks to the minimum statements that can raise. Catch specific exception types. Keep
`except Exception` only at defined error boundaries (top-level handlers, middleware).

### 5. Silent Error Suppression

Bare `except:`, `except Exception: pass`, catch-and-log-only patterns that swallow errors without recovery or re-raise.

**Signals:**

- `except:` (bare)
- `except Exception: pass`
- `except Exception as e: logger.error(str(e))` with no re-raise and no recovery logic
- `return []` or `return {}` or `return None` as silent fallbacks in except blocks
- `continue` in except blocks inside loops, silently skipping failed items without reporting

**Action:** Either recover meaningfully or re-raise. At error boundaries (middleware, top-level handlers), catch and
convert to appropriate response. Elsewhere, let exceptions propagate.

### 6. Poor Exception Context

Exceptions with bare string messages lacking relevant data attributes, or generic messages that don't help diagnose
the issue.

**Signals:**

- `raise ValueError("invalid input")` without saying which input or what constraint was violated
- Exception classes with only a string message and no data attributes
- `str(e)` in log messages instead of `logger.exception()`
- Exceptions that lose the original input values (no `order_id`, `field_name`, etc. on the exception)
- Error messages that say "something went wrong" or "unexpected error" without actionable detail

**Action:** Add context attributes to exception classes (`order_id`, `field_name`, etc.). Use
`logger.exception("msg")` to capture traceback. Include the invalid value and expected constraint in error messages.
Design exception classes with `__init__` that accepts structured data, not just a message string.

### 7. Framework Error Handler Gaps

Missing or inconsistent mapping between domain exceptions and HTTP/API responses. Exception handlers that leak
internal details.

**Signals:**

- No `@app.exception_handler()` (FastAPI) or `@app.errorhandler()` (Flask) registrations for domain exceptions
- Handler returning `500` for all domain errors instead of appropriate status codes
- Stack traces in production error responses
- Inconsistent error response shapes (`{"error": ...}` vs `{"detail": ...}` vs `{"message": ...}`)
- Domain exceptions that bubble up as unhandled 500s at the API boundary
- Different error response formats from different endpoints

**Action:** Register exception handlers for each domain exception type. Standardize error response shape. Strip
internal details in production. Map domain exceptions to appropriate HTTP status codes (e.g., `NotFoundError` → 404,
`ValidationError` → 422, `AuthorizationError` → 403).

### 8. Missing Error Boundary Definition

No clear separation between where errors should propagate and where they should be caught and converted. Error
handling scattered without a strategy.

**Signals:**

- Try/except at every level of the call stack (defensive programming)
- No clear boundary layer (middleware, top-level handler) that catches and converts
- Domain code catching infrastructure exceptions directly (e.g., `except SQLAlchemyError` in domain layer)
- Mixed exception types at the API boundary (some return HTTP errors, others raise domain exceptions that bubble up
  as 500s)
- Service layer catching and re-raising the same exception type without adding context

**Action:** Define explicit error boundaries: API boundary (convert to HTTP response), service boundary (convert
infrastructure errors to domain errors), infrastructure boundary (wrap external errors). Let exceptions propagate
through layers where no conversion is needed.

## Audit Workflow

### Phase 1: Map Error Boundaries

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

2. Identify error boundaries: API route handlers, middleware, CLI entry points, background task runners, event
   listeners, webhook handlers. These are the places where exceptions should be caught and converted.

3. Identify the current exception hierarchy: custom exception classes, base classes, naming conventions.

### Phase 2: Scan for Error Handling Signals

```bash
EXCLUDE='--glob !**/*_test.py --glob !**/test_*.py --glob !**/tests/** --glob !**/venv/** --glob !**/.venv/**'

# Exception hierarchy
rg 'class\s+\w+(Error|Exception)\s*\(' --type py $EXCLUDE
rg 'raise\s+Exception\(' --type py $EXCLUDE
rg 'raise\s+ValueError\(' --type py $EXCLUDE

# Missing chaining
rg -U 'except\s+\w+.*:\s*\n\s*raise\s+\w+' --type py $EXCLUDE

# Return-None in except
rg -U 'except.*:\s*\n\s*return None' --type py $EXCLUDE

# Broad try/except
rg --pcre2 'except\s*:' --type py $EXCLUDE
rg --pcre2 'except\s+Exception\s*:' --type py $EXCLUDE
rg --pcre2 'except\s+Exception\s+as\s+\w+\s*:\s*$' --type py $EXCLUDE

# Silent suppression
rg -U 'except.*:\s*\n\s*pass' --type py $EXCLUDE

# Error handler registrations
rg 'exception_handler|errorhandler|ExceptionMiddleware' --type py $EXCLUDE

# Logging patterns
rg 'logger\.(error|warning).*str\(.*\)' --type py $EXCLUDE
rg 'logger\.exception' --type py $EXCLUDE
```

### Phase 3: Evaluate Exception Design

1. **Hierarchy depth:** Is there a base `ApplicationError`? Do domain exceptions extend it? Is the hierarchy shallow
   (2-3 levels) or excessively deep?
2. **Naming conventions:** Do all custom exceptions use the `Error` suffix? Are names domain-specific
   (`OrderNotFoundError`) or generic (`CustomError`)?
3. **Context attributes:** Do exception classes carry structured data (`order_id`, `field_name`) or just string
   messages?

### Phase 4: Trace Error Propagation

For each domain error, trace from raise site to final handling:

1. Where is the exception raised?
2. Is it caught anywhere between the raise site and the boundary?
3. If caught, is it wrapped with `from`? Is context added?
4. At the boundary, is it converted to an appropriate response?

Flag exceptions that: propagate unhandled to a generic 500, are caught and swallowed mid-stack, or lose their chain
during wrapping.

### Phase 5: Evaluate Error Boundaries

1. Are boundaries clearly defined? (One place per layer where exceptions are caught and converted.)
2. Do domain exceptions leak through boundaries? (e.g., `SQLAlchemyError` reaching the API handler.)
3. Is the error response shape consistent across all endpoints?
4. Do error handlers strip internal details in production?

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-error-hunter-audit-{$LLM-name}.md` in the project's docs folder (or project root if no docs
folder exists).

```md
# Error Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files: {count or list}
- Exclusions: {list}

## Error Boundary Map

| # | Boundary | Location | Type | Handles |
| - | -------- | -------- | ---- | ------- |
| 1 | API middleware | file:line | Top-level | All unhandled → 500 |
| 2 | POST /api/orders | file:line | Endpoint | OrderNotFound → 404 |

## Exception Hierarchy

{Current hierarchy tree, or "No custom exceptions found"}

## Findings

### Missing Exception Hierarchy

| # | Location | Current | Suggested | Severity |
| - | -------- | ------- | --------- | -------- |
| 1 | file:line | `raise Exception("Order not found")` | `raise OrderNotFoundError(order_id)` | High |

### Missing Exception Chaining

| # | Location | Outer Exception | Inner Exception | Action |
| - | -------- | --------------- | --------------- | ------ |
| 1 | file:line | `raise ServiceError(...)` | `except DBError` | Add `from e` |

### Return-None Antipattern

| # | Location | Function | Returns None When | Action |
| - | -------- | -------- | ----------------- | ------ |
| 1 | file:line | `get_order()` | DB error + not found (conflated) | Split: raise on error, None on not-found |

### Over-Broad Try/Except

| # | Location | Try Block Lines | Caught Type | Action |
| - | -------- | --------------- | ----------- | ------ |
| 1 | file:line | 15 | `Exception` | Narrow to 2 lines, catch `ValueError` |

### Silent Error Suppression

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `except Exception: pass` | Remove or add recovery logic |

### Poor Exception Context

| # | Location | Exception | Missing Context | Action |
| - | -------- | --------- | --------------- | ------ |
| 1 | file:line | `ValueError("invalid")` | Which value? What constraint? | Include value and expected range |

### Framework Error Handler Gaps

| # | Exception Type | Expected Status | Current Handling | Action |
| - | -------------- | --------------- | ---------------- | ------ |
| 1 | `OrderNotFoundError` | 404 | Unhandled (500) | Register exception handler |

### Missing Error Boundaries

| # | Location | Issue | Action |
| - | -------- | ----- | ------ |
| 1 | file:line | Domain code catches `SQLAlchemyError` directly | Wrap in repository layer |

## Recommendations (Priority Order)

1. **Must-fix**: {silent suppression, missing chaining, unhandled domain exceptions at API boundary}
2. **Should-fix**: {missing hierarchy, return-None antipattern, over-broad try/except}
3. **Consider**: {error response standardization, Result type adoption, poor exception context}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: error handling design only.** Do not flag type invariants (→ invariant-hunter-py), type design
  (→ type-hunter-py), structural complexity (→ simplicity-hunter-py), module boundary issues (→ boundary-hunter-py),
  class/interface design (→ solid-hunter-py), missing documentation (→ doc-hunter-py), security patterns other than
  error-related (→ security-hunter-py), test quality (→ test-hunter-py), or cosmetic style (→ slop-hunter-py). If a
  finding doesn't answer "is this error handling well-designed?", it doesn't belong here.
- **Boundary with invariant-hunter**: invariant-hunter owns type-system bypasses (`Any`, `cast()`,
  `# type: ignore`) and loose optionality from a type-enforcement perspective. Error-hunter owns how exceptions are
  structured, propagated, caught, and converted — the *design* of the error handling strategy. If the finding is about
  a `bare except:` suppressing an invariant, it belongs here. If the finding is about `# type: ignore` without
  justification, it belongs in invariant-hunter.
- **Evidence required.** Every finding must cite `file/path.py:line` with the exact code.
- **Pragmatism.** Not every function needs a custom exception class. Small scripts, utility functions, and prototype
  code may appropriately use built-in exceptions. Flag patterns that create real debugging difficulty or maintenance
  burden, not theoretical impurity.
