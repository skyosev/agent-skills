---
name: error-hunter-ts
description: |
  Audit TypeScript code for error handling design quality — missing Error hierarchies,
  lost Error.cause chains, return-undefined antipatterns, over-broad try/catch, silent
  suppression, poor error context, framework handler gaps, Result type opportunities,
  and missing error boundaries.

  Use when: reviewing error handling strategy, tightening exception design before deployment,
  auditing error propagation paths, standardizing API error responses, or establishing
  error handling conventions after rapid feature development.
disable-model-invocation: true  
---

# Error Hunter

Audit TypeScript code for **error handling design quality** — whether errors are structured intentionally, propagated
correctly, caught at the right boundaries, and converted to appropriate responses. The goal: **errors are part of the
API contract, error boundaries are clearly defined, and every catch block justifies its existence.**

This skill focuses on *error handling design* — the strategy of how errors are thrown, propagated, caught, and
converted. For type-system enforcement of invariants (`as any`, `@ts-ignore`, loose optionality), see
invariant-hunter-ts. For security implications of error patterns (stack trace leakage, auth bypass on error), see
security-hunter-ts.

## When to Use

- Reviewing error handling strategy before production deployment
- Tightening error design after initial prototyping
- Auditing error propagation paths to ensure domain errors don't leak through layers
- Standardizing API error responses across endpoints
- Establishing error handling conventions for a growing codebase
- Investigating why errors are silently swallowed or produce unhelpful diagnostics
- Preparing a codebase for better observability (structured logging, error tracking)
- Evaluating Result type vs throw-based error handling trade-offs

## Core Principles

1. **Errors are part of the API.** The errors a function can throw are as much part of its contract as its return
   type. Document them, type them, and design them intentionally. TypeScript doesn't have checked exceptions, which
   makes intentional error design even more important.

2. **Hierarchy mirrors the domain.** Error classes should reflect domain concepts (`OrderNotFoundError`,
   `PaymentDeclinedError`), not technical categories (`DatabaseError` leaking from domain). Technical errors belong
   at the infrastructure boundary.

3. **Chain, don't replace.** When wrapping an error, always use `{ cause: originalError }`. The original stack trace
   is the most valuable debugging information — losing it is a bug. ES2022 `Error.cause` is the standard mechanism.

4. **Throw on failure, return on success.** Functions should throw on error and return values on success.
   `T | undefined` return types are for genuinely absent data (not-found is a valid domain outcome), not for errors.
   When explicit error paths are needed, consider a Result/Either type pattern.

5. **Fail loudly in non-boundary code.** Business logic and domain code should let errors propagate. Only catch at
   defined boundaries: API route handlers, middleware, background job runners, CLI entry points.

6. **Every catch block must justify its existence.** A catch is justified if it: (a) recovers meaningfully,
   (b) wraps and re-throws at a boundary, or (c) converts to an appropriate error response. Catch-log-swallow is
   almost never justified.

7. **Standardize error responses.** API error shapes should be consistent across the entire application. Pick one
   format (RFC 7807 Problem Details, or a simple `{ type, title, detail, status }` shape) and use it everywhere.

### Canonical Exceptions

Not every finding requires action. Document these but do not flag as "must-fix":

| Pattern | When Acceptable |
| ------- | --------------- |
| `catch (error)` at API boundary | Top-level handler converting to 500 response |
| `return undefined` for not-found | Repository `.findById()` where absence is a normal outcome |
| Catch-and-log without re-throw | Background job runners with defined retry logic |
| Generic `Error` in pure utilities | Input validation in pure utility functions with no domain context |
| `catch` in test helpers | Test utilities where failure mode doesn't matter |
| `.catch()` on fire-and-forget | Explicitly discarded promises with documented reason |

## What to Hunt

### 1. Missing Error Hierarchy

Flat `throw new Error("...")` instead of domain-specific error classes. No base `ApplicationError`. Error names
without `Error` suffix.

**Signals:**

- `throw new Error("Order not found")` used for domain-specific error conditions
- `throw new TypeError("...")` or `throw new RangeError("...")` used for domain errors instead of domain-specific
  classes
- No custom Error subclasses in the project despite non-trivial domain logic
- Error class names without `Error` suffix (inconsistent naming convention)
- No base `ApplicationError` or `DomainError` for the project's error hierarchy
- Error classes that don't extend `Error` (or extend it incorrectly — missing `name` property, broken prototype chain)

**Action:** Create a domain error hierarchy: `ApplicationError` → `NotFoundError`, `ValidationError`,
`AuthorizationError`, etc. Use `Error` suffix consistently. Keep the hierarchy shallow (2–3 levels max). Set the
`name` property in constructors for reliable `instanceof` checks after minification.

### 2. Missing Error Cause Chaining

`throw new DomainError(...)` inside `catch` without `{ cause: originalError }`, losing the original stack trace and
context.

**Signals:**

- `catch (error) { throw new ServiceError(...) }` without `{ cause: error }`
- Error wrapping at layer boundaries (service catching infrastructure errors) without preserving the cause
- `catch (error) { throw error }` that loses type information without adding context
- Log messages that reconstruct error info via `String(error)` because the cause chain was lost upstream
- Custom error constructors that don't accept or forward a `cause` option

**Action:** Use `{ cause: originalError }` in the Error options parameter (ES2022): `throw new ServiceError("msg",
{ cause: originalError })`. Ensure custom Error classes pass options through to `super()`. Use
`throw new Error("msg", { cause: null })` only when deliberately suppressing the chain (rare — document the reason).

### 3. Return-Undefined Antipattern

Functions returning `undefined` on error instead of throwing, conflating "not found" with "error" with "no result."

**Signals:**

- `return undefined` inside catch blocks
- Functions with `T | undefined` return type where `undefined` means both "not found" and "error"
- Caller code doing `if (result === undefined)` without knowing why the result is absent
- Functions that return `undefined` on infrastructure failures (DB connection error, timeout) instead of throwing
- Mixed return patterns: same function returns `undefined` on some errors and throws on others

**Action:** Throw specific errors for error conditions. Use `T | undefined` only for genuinely absent data (e.g.,
repository `findById` returning `undefined` for a missing record). Consider Result type patterns for explicit error
paths where exceptions are too heavyweight.

### 4. Over-Broad Try/Catch

Try blocks wrapping too many statements when only one can throw the caught error. Catching `unknown` when a specific
type check is appropriate.

**Signals:**

- `try` blocks spanning 10+ lines
- `catch (error)` in non-boundary code with no type narrowing
- `catch (error) { /* nothing */ }` or `catch (error) { console.log(error) }` without recovery
- Catching at a level where only one of many statements can actually fail
- Try/catch wrapping an entire function body instead of the specific risky operation

**Action:** Narrow try blocks to the minimum statements that can throw. Use type narrowing in catch blocks
(`if (error instanceof SpecificError)`). Keep broad `catch` only at defined error boundaries (top-level handlers,
middleware).

### 5. Silent Error Suppression

Empty catch blocks, catch-and-log-only patterns, or catch-and-return-default patterns that swallow errors without
recovery or re-throw.

**Signals:**

- `catch (error) { }` (empty)
- `catch (error) { console.error(error) }` with no re-throw and no recovery logic
- `return []` or `return {}` or `return null` as silent fallbacks in catch blocks
- `.catch(() => undefined)` on promises without documented reason
- `continue` in catch blocks inside loops, silently skipping failed items without reporting
- Swallowed promise rejections: `promise.catch(noop)` or `void promise`

**Action:** Either recover meaningfully or re-throw. At error boundaries (middleware, top-level handlers), catch and
convert to appropriate response. Elsewhere, let errors propagate.

### 6. Poor Error Context

Errors with bare string messages lacking relevant data, or generic messages that don't help diagnose the issue.

**Signals:**

- `throw new Error("invalid input")` without saying which input or what constraint was violated
- Error classes with only a `message` property and no structured data
- `String(error)` or `(error as Error).message` in log messages instead of logging full error objects
- Errors that lose the original input values (no `orderId`, `fieldName`, etc. as properties)
- Error messages that say "something went wrong" or "unexpected error" without actionable detail
- Errors thrown without `Error` objects: `throw "string"` or `throw 404`

**Action:** Add context properties to custom error classes (`orderId`, `fieldName`, etc.). Use structured logging
that captures the full error (including `cause` chain). Include the invalid value and expected constraint in error
messages. Always throw `Error` instances, never primitives.

### 7. Framework Error Handler Gaps

Missing or inconsistent mapping between domain errors and HTTP/API responses. Error handlers that leak internal
details.

**Signals:**

- No global error handler middleware in Express (`app.use((err, req, res, next) => ...)`)
- No exception filters in NestJS (`@Catch()` decorators) for domain error types
- No `error.tsx` or API error handling in Next.js route handlers
- Handler returning 500 for all domain errors instead of appropriate status codes
- Stack traces or internal paths in production error responses
- Inconsistent error response shapes (`{ error: ... }` vs `{ message: ... }` vs `{ detail: ... }`)
- Domain errors that bubble up as unhandled 500s at the API boundary
- Different error response formats from different endpoints
- Missing `Content-Type: application/json` on error responses

**Action:** Register error handlers for each domain error type. Standardize error response shape (consider RFC 7807
Problem Details). Strip internal details in production. Map domain errors to appropriate HTTP status codes (e.g.,
`NotFoundError` → 404, `ValidationError` → 400/422, `AuthorizationError` → 403).

### 8. Missing Error Boundary Definition

No clear separation between where errors should propagate and where they should be caught and converted. Error
handling scattered without a strategy.

**Signals:**

- Try/catch at every level of the call stack (defensive programming)
- No clear boundary layer (middleware, top-level handler) that catches and converts
- Domain code catching infrastructure errors directly (e.g., `catch (error) { if (error.code === 'P2025') }` with
  raw Prisma error codes in service layer)
- Mixed error types at the API boundary (some return HTTP errors, others throw domain errors that bubble up as 500s)
- Service layer catching and re-throwing the same error type without adding context
- GraphQL resolvers with inconsistent error handling (some throw, some return error objects)

**Action:** Define explicit error boundaries: API boundary (convert to HTTP/GraphQL response), service boundary
(convert infrastructure errors to domain errors), infrastructure boundary (wrap external errors). Let errors
propagate through layers where no conversion is needed.

### 9. Promise Error Handling Gaps

Unhandled promise rejections, missing `.catch()` on fire-and-forget promises, and `async` functions called without
`await` or error handling.

**Signals:**

- `async` function called without `await` and no `.catch()` handler
- `Promise.all()` without considering partial failure handling (`Promise.allSettled()`)
- Missing `unhandledRejection` process handler in Node.js entry point
- Event handlers that are `async` but the caller doesn't handle the returned promise
- Express route handlers that are `async` without `try/catch` or an async wrapper middleware
- `.then()` chains without a terminal `.catch()`

**Action:** Always `await` or attach `.catch()` to promises. Use `Promise.allSettled()` when partial failures
should not reject the aggregate. Add `unhandledRejection` handler at process level. Wrap Express async handlers
with middleware that forwards rejections to `next(error)`.

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

2. Identify error boundaries: API route handlers, middleware, CLI entry points, background job runners, event
   listeners, webhook handlers, GraphQL resolvers. These are the places where errors should be caught and converted.

3. Identify the current error hierarchy: custom Error subclasses, base classes, naming conventions.

4. Identify the framework(s) in use (Express, Fastify, NestJS, Next.js, tRPC, Hono) — error handling patterns are
   framework-specific.

### Phase 2: Scan for Error Handling Signals

```bash
EXCLUDE='--glob !**/*.test.* --glob !**/*.spec.* --glob !**/node_modules/** --glob !**/dist/**'

# Error hierarchy
rg 'class\s+\w+Error\s+extends' --type ts $EXCLUDE
rg 'throw new Error\(' --type ts $EXCLUDE
rg 'throw new TypeError\(' --type ts $EXCLUDE

# Missing cause chaining
rg -U 'catch\s*\([^)]*\)\s*\{[^}]*throw new' --type ts $EXCLUDE

# Return-undefined in catch
rg -U 'catch\s*\([^)]*\)\s*\{[^}]*return (undefined|null)' --type ts $EXCLUDE

# Broad/empty catch blocks
rg -U 'catch\s*\([^)]*\)\s*\{\s*\}' --type ts $EXCLUDE
rg -U 'catch\s*\([^)]*\)\s*\{\s*console\.(log|error)' --type ts $EXCLUDE

# Silent suppression via .catch()
rg '\.catch\s*\(\s*\(\s*\)\s*=>' --type ts $EXCLUDE
rg '\.catch\s*\(\s*noop\s*\)' --type ts $EXCLUDE

# Throw non-Error values
rg --pcre2 'throw\s+["\x27`\d]' --type ts $EXCLUDE

# Error handler registrations
rg 'app\.use\(.*err.*req.*res.*next' --type ts $EXCLUDE
rg '@Catch\(' --type ts $EXCLUDE
rg 'onError|errorHandler|handleError' --type ts $EXCLUDE

# Error.cause usage (adoption check)
rg 'cause:' --type ts $EXCLUDE | rg -v 'node_modules'

# Promise handling
rg -U 'async\s+\w+.*\{[^}]*\}(?!.*\.(catch|then))' --type ts $EXCLUDE
rg 'unhandledRejection' --type ts $EXCLUDE

# Error response shapes
rg --pcre2 'res\.(status|json|send)\(.*error|message|detail' --type ts $EXCLUDE
```

### Phase 3: Evaluate Error Design

1. **Hierarchy depth:** Is there a base `ApplicationError`? Do domain errors extend it? Is the hierarchy shallow
   (2–3 levels) or excessively deep?
2. **Naming conventions:** Do all custom errors use the `Error` suffix? Are names domain-specific
   (`OrderNotFoundError`) or generic (`CustomError`)?
3. **Context properties:** Do error classes carry structured data (`orderId`, `fieldName`) or just string messages?
4. **Cause chain support:** Do custom error constructors accept and forward `{ cause }` options?

### Phase 4: Trace Error Propagation

For each domain error, trace from throw site to final handling:

1. Where is the error thrown?
2. Is it caught anywhere between the throw site and the boundary?
3. If caught, is it wrapped with `{ cause }`? Is context added?
4. At the boundary, is it converted to an appropriate response?

Flag errors that: propagate unhandled to a generic 500, are caught and swallowed mid-stack, or lose their cause
chain during wrapping.

### Phase 5: Evaluate Error Boundaries

1. Are boundaries clearly defined? (One place per layer where errors are caught and converted.)
2. Do infrastructure errors leak through boundaries? (e.g., Prisma `P2025` error code checked in a route handler.)
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
- Framework: {Express / Fastify / NestJS / Next.js / tRPC / etc.}
- Exclusions: {list}

## Error Boundary Map

| # | Boundary | Location | Type | Handles |
| - | -------- | -------- | ---- | ------- |
| 1 | Global middleware | file:line | Top-level | All unhandled → 500 |
| 2 | POST /api/orders | file:line | Endpoint | OrderNotFoundError → 404 |

## Error Hierarchy

{Current hierarchy tree, or "No custom error classes found"}

## Findings

### Missing Error Hierarchy

| # | Location | Current | Suggested | Severity |
| - | -------- | ------- | --------- | -------- |
| 1 | file:line | `throw new Error("Order not found")` | `throw new OrderNotFoundError(orderId)` | High |

### Missing Error Cause Chaining

| # | Location | Outer Error | Inner Error | Action |
| - | -------- | ----------- | ----------- | ------ |
| 1 | file:line | `throw new ServiceError(...)` | `catch (dbError)` | Add `{ cause: dbError }` |

### Return-Undefined Antipattern

| # | Location | Function | Returns Undefined When | Action |
| - | -------- | -------- | ---------------------- | ------ |
| 1 | file:line | `getOrder()` | DB error + not found (conflated) | Split: throw on error, undefined on not-found |

### Over-Broad Try/Catch

| # | Location | Try Block Lines | Caught Type | Action |
| - | -------- | --------------- | ----------- | ------ |
| 1 | file:line | 15 | `unknown` | Narrow to 2 lines, check `instanceof ValidationError` |

### Silent Error Suppression

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `catch (error) { }` | Remove or add recovery logic |

### Poor Error Context

| # | Location | Error | Missing Context | Action |
| - | -------- | ----- | --------------- | ------ |
| 1 | file:line | `new Error("invalid")` | Which value? What constraint? | Include value and expected range |

### Framework Error Handler Gaps

| # | Error Type | Expected Status | Current Handling | Action |
| - | ---------- | --------------- | ---------------- | ------ |
| 1 | `OrderNotFoundError` | 404 | Unhandled (500) | Register error handler |

### Missing Error Boundaries

| # | Location | Issue | Action |
| - | -------- | ----- | ------ |
| 1 | file:line | Service code checks raw Prisma error codes | Wrap in repository layer |

### Promise Error Handling Gaps

| # | Location | Pattern | Action |
| - | -------- | ------- | ------ |
| 1 | file:line | `async` handler without try/catch or wrapper | Add async error wrapper middleware |

## Recommendations (Priority Order)

1. **Must-fix**: {silent suppression, missing cause chaining, unhandled domain errors at API boundary, promise gaps}
2. **Should-fix**: {missing hierarchy, return-undefined antipattern, over-broad try/catch}
3. **Consider**: {error response standardization, Result type adoption, poor error context}
```

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **Scope: error handling design only.** Do not flag type invariants (→ invariant-hunter-ts), type design
  (→ type-hunter-ts), structural complexity (→ simplicity-hunter-ts), module boundary issues (→ boundary-hunter-ts),
  class/interface design (→ solid-hunter-ts), missing documentation (→ doc-hunter-ts), security patterns other than
  error-related (→ security-hunter-ts), test quality (→ test-hunter-ts), or cosmetic style (→ slop-hunter-ts). If a
  finding doesn't answer "is this error handling well-designed?", it doesn't belong here.
- **Boundary with invariant-hunter**: invariant-hunter owns type-system bypasses (`as any`, `@ts-ignore`,
  `@ts-expect-error`) and loose optionality from a type-enforcement perspective. Error-hunter owns how errors are
  structured, propagated, caught, and converted — the *design* of the error handling strategy. If the finding is about
  an empty `catch` suppressing an error, it belongs here. If the finding is about `as any` without justification, it
  belongs in invariant-hunter.
- **Evidence required.** Every finding must cite `file/path.ts:line` with the exact code.
- **Framework awareness.** Error handling patterns differ by framework. Express uses `(err, req, res, next)` middleware.
  NestJS uses `@Catch()` exception filters. Next.js uses `error.tsx` boundaries. Fastify uses `setErrorHandler()`.
  Flag gaps relative to the framework's intended error handling mechanism.
- **Pragmatism.** Not every catch block is wrong. Background jobs, retry loops, and graceful degradation may
  legitimately catch and handle. Flag only when the catch block adds no value or actively harms debuggability.
