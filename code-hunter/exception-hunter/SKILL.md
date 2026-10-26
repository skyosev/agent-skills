---
name: exception-hunter
description: Audit Go, Python, or TypeScript code for failure handling that hides, misreports, or loses failures — swallowed errors, orphaned async work, overbroad handlers, broken error chains, unmatchable failures, untranslated boundary errors, double handling, poor error context, panic and exit misuse. Defaults to the codebase.
disable-model-invocation: true
---

# Exception Hunter

Audit code for **failure handling that hides, misreports, or loses failures** — a failure that is raised,
propagated, caught, or converted by accident instead of on purpose: `except Exception: return None` in a `find_order`
whose caller then creates a second order, `_ = tx.Commit()`, a floating `save()` promise in a handler that returns
200, `fmt.Errorf("load %s: %v", p, err)` under a caller that matches with `errors.Is`. Goal: **every failure reaches
code that acts on it, keeps the cause and the identity its readers need, and gets the status its kind calls for.**

In this skill, an **exception** is any failure a callee reports: a Go `error` value, a Python exception, a TypeScript
thrown value or promise rejection. Go panics are named panics.

**Not covered (owned by other hunters):** nil dereferences (a result used before its error is checked included),
zero-value traps, context misuse, races, type-system bypasses (one inside a `catch` included), an unnarrowed catch
binding, exhaustiveness of a data variant set (a `default` arm that does nothing) (→ invariant-hunter); redundant
wrapping words, linter suppressions (→ slop-hunter); duplicated error-handling code, reinvented `errors.Is` /
`errors.As` walks, hand-rolled `errors.Join`, scattered `.catch()` calls (→ simplicity-hunter; `if err != nil`
repetition is never complexity); not-implemented panics, throws, and raises in implementors, silent zero returns in
one implementor of a contract type (→ solid-hunter's Broken Substitution); documentation of the failures callers
match — `Raises:`, `@throws`, Go sentinels — when the design is sound (→ doc-hunter); `init()` that can fail
(→ smell-hunter's `init()` Abuse); import edges, external types in exported signatures, a provable `ImportError` from
an import cycle (→ boundary-hunter); error handling inside tests, missing error-path tests (→ test-hunter); internal
detail in error responses and logs, auth decisions that fail open on an error (→ security-hunter). Where ownership is
*contested*, the category's **Ownership:** note in What to Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `security-hunter-go`, `security-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical. Each language
reference holds its scans, detectors, version gates, and transport frameworks.

| Category | Core signal | Required evidence | Action |
| -------- | ----------- | ----------------- | ------ |
| Swallowed Errors | A received failure that no code acts on | The failure dropped, and what the caller gets instead | Propagate, or recover with a stated reason |
| Orphaned Async Failures | Async work whose failure has no observer | The spawn site, and that no await, result read, or handler exists | Await, keep and read the task or future, or use a group |
| Overbroad Handling | A handler that acts on failures it was not written for | The expected failure, and one other failure that reaches the handler | Narrow the catch to the expected failure; let the rest propagate |
| Broken Error Chains | Wrapping or reporting that drops the cause, stack, or traceback | What is lost; for Go `%v`, the caller that matches the chain | `%w`, `Unwrap`, `{ cause }`, `from`, `logger.exception` |
| Unmatchable Failures | A caller must tell a failure apart and cannot, except by text or a wrong type | The consumer and how it matches | Sentinel or typed failure; `errors.Is` / `errors.As`; a specific exception class |
| Untranslated Boundary Errors | A failure crosses a layer in the wrong vocabulary | Direction, the failure, the boundary; for `outward`, the status produced and the status its kind calls for | Translate in the adapter; map at the transport boundary |
| Double Handling | One failure handled at more than one layer | Both handling sites | Log at the boundary or return; not both |
| Poor Error Context | The final message cannot name the failing step or input | The missing step or input, and who holds it | Add the operation and the identifying input once, at the layer that holds it |
| Panic and Exit Misuse | A panic or process exit for a failure that external input or the environment can cause | The entry point that reaches it, and what recovers it | Return an error; keep panic for violated internal invariants |

## Core Principles

1. **Scans and detectors nominate; reading decides.** Nothing is a finding until Phase 4 has read the handler, the
   failure's source, and the path to the boundary.
2. **Every handler has a job.** Recover, translate, add context, or report at a boundary. A handler that does none of
   these is the finding. A handler that does its job for failures it was not written for is Overbroad Handling.
3. **Handle once.** One layer reports a failure; the others pass it on with context.
4. **Expected failures carry identity when a caller branches on them.** A sentinel, a type, or a class, never
   message text.
5. **Translate at the edges.** The adapter translates external failures; the transport boundary maps domain failures
   to statuses; nothing in between decides either. One exception: a transport error raised in a unit that only the
   request path reaches (Untranslated Boundary Errors).
6. **Respect the language.** Go errors are values that wrap with `%w` and match with `errors.Is` / `errors.As`. Python
   chains implicitly. TypeScript chains only through `cause`. Severity follows what the language actually loses.

## Terms

- **Handler** — code that receives a failure: an `except` / `catch` block, a `.catch()` callback, an
  `if err != nil` block, a `recover()` call, a framework error handler.
- **Expected failure** — the failure a handler was written for. Evidence, in order: the narrow type it names
  (`except KeyError`, `errors.Is(err, sql.ErrNoRows)`), the value it maps the failure to (`None` that callers read as
  not-found), a comment, the function's name (`find_or_create`).
- **Adapter** — a unit that calls an external library's operations (opens the session, runs the query, sends the
  request) for the rest of the code. It is the adapter for the calls it makes, and translating their failures is its
  job. A library can have several (an order repository and a user repository). A unit that matches a failure from a
  call another unit made is outside the adapter, however many adapters exist. A unit that imports the library only
  to catch its exception types is not an adapter. When no unit wraps the library for others, each caller is the
  adapter for its own calls, and there is no inward finding (Untranslated Boundary Errors does not ask to create a
  layer).
- **Transport boundary** — code that turns a result into a protocol response: an HTTP handler, middleware, or
  registered exception handler; a gRPC method or interceptor; a queue consumer's ack or nack; a CLI's exit code.
- **Process boundary** — where a failure has no caller to go to: `main`, a goroutine's top function, a thread target,
  a worker loop, a task runner.
- **Write path** — code whose failure leaves persisted or sent state wrong: a DB write or commit, a file write or
  close, a message publish, a payment or e-mail call.
- **Message event** — a Sentry event with a message and no stack trace or exception, so Sentry groups it by message.
  Sentry groups an event by its stack trace first, then by exception type and value, and by message only when
  neither exists; the message fallback uses the text without its parameters when it has them (Sentry event-grouping
  docs). Python: a `logger.error` / `logger.critical` record without `exc_info`, which the default logging
  integration (`event_level=ERROR`) turns into an event, in a project with `sentry-sdk` whose `sentry_sdk.init` does
  not set `attach_stacktrace=True` or replace `event_level`. TypeScript: `Sentry.captureMessage` with `@sentry/*` and
  no `attachStacktrace: true`. `logger.exception` and `exc_info=True` attach a stack and are never message events. Go
  has no message-event check.
- **Cancellation** — a stop the caller asked for, not a failure: Go `context.Canceled`, and `DeadlineExceeded` from a
  deadline the caller set (the incoming request's context); Python `asyncio.CancelledError` of the current task;
  TypeScript `AbortError` / `signal.aborted`; an HTTP client disconnect. A timeout this code sets for its own
  outbound call is a failure, not a cancellation.
- **Target scope** — the files a finding may anchor at; every other file is read as context (Phase 1 step 4, Two
  surfaces).

## What to Hunt

### Swallowed Errors

A failure the code received — a caught exception, a non-nil `err`, a rejected promise — and then neither handled,
propagated, nor reported. The caller gets a success-shaped result.

**Kinds** (the report's Kind column):

- `dropped` — nothing happens: `except: pass`, `catch {}`, `if err != nil {}`, `_ = f()` on an error, a Go call whose
  error return is ignored by arity, `.catch(() => {})`.
- `logged-only` — logged, then the code continues as on success.
- `defaulted` — replaced by `None`, `[]`, `{}`, `0`, `false`, a nil error (`if err != nil { return nil }`).
- `skipped` — `continue` in a loop; only the first of several collected errors returned; `gather(...,
  return_exceptions=True)` or `Promise.allSettled` whose failures are never read; Go `rows.Err()` / `scanner.Err()`
  not read after the loop.
- `overridden` — a later statement replaces it: `return`, `break`, or `continue` in `finally`; a named `err` result
  overwritten in a `defer`; an `err` assigned again before it is read (`err = foo(); err = bar()`; ineffassign
  nominates, errcheck does not, because the first error was assigned); `recover()` whose value is discarded.
- `never-raised` — an exception or error built and never raised or returned: `ValueError("x")` as a statement,
  `new Error("x");`, `errors.New("x")` with the result unused.

**Signals:** the kinds above; each language reference's scans carry the markers. Go also: `defer f.Close()` on a
write path; `if err != nil` checked but the error is not used on any branch.

**Not a finding:**

- A best-effort operation whose comment states why the failure is safe to drop, and the code confirms it: `Close` on a
  file opened read-only, a logger flush, a metrics or telemetry emit, a cache fill. The comment is a claim to verify.
  It is a finding on a write path whatever the comment says, and with no comment.
- A degraded fallback that logs at warn level and says why in a comment (a stale cache served while the origin is
  down).
- Loop termination by contract: `io.EOF`, `StopIteration`, `StopAsyncIteration`.
- `contextlib.suppress(FileNotFoundError)` around a delete-if-exists, and other single, named failures whose
  suppression is the intent.
- Writes that cannot fail by contract: `bytes.Buffer`, `strings.Builder`, `hash.Hash` `Write`. errcheck excludes them
  by default.
- A process-boundary catch-all that logs once and continues the loop with the next independent item (a queue
  consumer that nacks the message).
- A dropped error from writing an HTTP response body (`fmt.Fprintf(w, …)`, `w.Write(…)`). The first write has
  committed the status, so the handler cannot repair the response; a streaming handler that keeps writing after a
  failed write is accepted. This reason covers response writes only, never a file write or a publish.
- `CancelledError` caught while joining a task this code cancelled itself (`task.cancel()`, then `await task`), when
  the join still re-raises the current task's own cancellation (`if asyncio.current_task().cancelling(): raise`,
  3.11+). `with suppress(CancelledError): await task` also swallows a cancellation of the current task that arrives
  during the join, so it is a finding.

**Evidence bar:** the Failure Dropped cell names the callee and the failure it can report. For `defaulted`, it also
names what the caller does with the default (`None` → caller creates a new order). For a justifying comment, it names
the code that confirms or contradicts it.

**Action:** propagate; or recover with a comment that states why the failure is safe; on a Go write path, capture the
`Close` error in a named result.

**Ownership:** `_ = x` on a non-error binding is slop-hunter's Trivially Dead Code. Suppressing the current task's
own cancellation (`CancelledError` caught and not re-raised) is here: it breaks the caller's cancellation. A Go
`return nil, nil` with no error received is not here: it is an absence contract (doc-hunter's Undocumented
Contracts; a nil dereference that follows is invariant-hunter's Nil Pointer Risks). A `return nil, nil` in one
implementor of an interface whose contract promises a value or an error is solid-hunter's Broken Substitution.

### Orphaned Async Failures

Async work started with no path for its failure to reach code that acts on it.

**Signals:**

- TypeScript: a floating promise (an un-awaited call to an `async` function, a `.then()` chain with no terminal
  handler); an `async` callback passed where the caller ignores the returned promise (`forEach(async …)`,
  `setTimeout(async …)`, an emitter `.on(…, async …)`); an `async` Express 4 route handler in a package with no
  async wrapper (Express 5 forwards the rejection, so it is not a finding there); `void promise` whose callee can
  reject (`void` changes nothing about the rejection; typescript-eslint's docs say so).
- Python: `asyncio.create_task` / `ensure_future` whose result is not kept (the event loop holds only a weak reference,
  so the task can also vanish mid-run); a kept task or future that is never awaited or read; `executor.submit()`
  whose future's `.result()` / `.exception()` is never read; a `threading.Thread` target that can raise, with no path
  back to the spawner.
- Go: `go f(…)` where `f` returns an error (the `go` statement discards it); an `errgroup.Group` whose `Wait()` result
  is discarded.

**Not a finding:** a discarded promise (`void` or not) whose callee catches every failure itself and does not
rethrow, confirmed by reading the callee, not by a comment; a promise with a terminal `.catch` that handles it; a
task kept in a set and drained by a supervisor that logs its failures; a goroutine whose body handles its own error
(the body's handling is judged by the other categories); `go f()` where `f`'s error is one errcheck excludes by
default (`go fmt.Println(…)`).

**Evidence bar:** the spawn site, and the search that found no await, result read, terminal handler, or group. For a
discarded promise, the callee line that can reject. The Consequence cell names what happens: a crash (Node ≥ 15
default), the recorded listener's action or `--unhandled-rejections` mode (Phase 1 step 5), a lost task, or a
goroutine's dropped error.

**Action:** await it; keep the task and read its result; use a task group (`asyncio.TaskGroup`, `errgroup`); for an
intentional discard, a `.catch` that handles the failure, or a supervisor that logs.

**Ownership:** a goroutine body that receives an error and drops it is Swallowed Errors; `go f()` that discards the
error by construction is here. A panic in a spawned goroutine is Panic and Exit Misuse.

### Overbroad Handling

A handler written for one failure that also catches others and treats them the same way.

**Signals:**

- A catch-all mapped to one meaning: `except Exception: return None` where `None` means not-found; Go
  `if err != nil { return nil, ErrNotFound }` with no `errors.Is(err, sql.ErrNoRows)`; `catch { return null }` in a
  `findById`. A lost connection becomes a missing record.
- A `try` body with several calls whose failures need different handling, under one handler. The line count is not
  evidence.
- Bare `except:` or `except BaseException` that catches `KeyboardInterrupt`, `SystemExit`, or (since Python 3.8)
  `asyncio.CancelledError`.
- A retry that catches failures it cannot fix by retrying: `autoretry_for=(Exception,)`, tenacity `@retry` with no
  `retry=` (its default retries every exception), `retryIf: () => true`, a retry around a non-idempotent write.
  Attempt limits, backoff, and jitter are not judged.
- A cancellation (Terms; a deadline counts only when the caller set it) logged at error level. No other log-level
  choice is judged.

**Not a finding:**

- A catch-all at a transport or process boundary that logs once and converts to a 500, a nack, or an exit code. A
  cancellation it logs at error level is still a finding (routing rule 6).
- A catch-all inside the adapter that translates every failure into the adapter's own failure and keeps the cause
  (`except Exception as e: raise RepositoryError(…) from e`). It claims no narrower meaning; the same handler raising
  `OrderNotFound` is a finding.
- A `try` body whose failures all need the same handling.
- A retry around an idempotent call whose every failure the code shows is transient.

**Evidence bar:** the Written For cell names the expected failure and which evidence from Terms gave it (the narrow
type, the mapped value, a comment, or the name). With none, it is not Overbroad Handling: routing rule 1 decides.
The Also Catches cell names one other failure that reaches the handler: a statement in the `try` body, or a failure
the callee documents or returns.

**Action:** narrow the handler to the expected failure (`except KeyError`, `errors.Is`, `instanceof`); let every other
failure propagate; classify before retrying.

**Ownership:** a handler with no expected failure that drops everything is Swallowed Errors (within-skill routing).

### Broken Error Chains

Existing information about a failure — its cause, stack, or traceback — is lost while the failure is wrapped,
converted, or reported.

**Signals:**

- Go: `fmt.Errorf` with `%v` (or no verb) where a caller matches the chain with `errors.Is` / `errors.As`; a custom
  error type that wraps another error and has no `Unwrap()`; `errors.New(err.Error())`.
- Python: `raise X(str(e))` outside the `except` block that caught `e` (a stored error raised later); `raise X from
  None` with no reason; `logger.error(str(e))` / `logger.error(f"… {e}")` at the site that handles the failure (the
  traceback is gone).
- TypeScript: `throw new X(…)` inside `catch` without `{ cause }`; a custom error class whose constructor does not pass
  `options` to `super`, when a call site passes `{ cause }` to it; `throw "string"` or `Promise.reject(nonError)` (no
  stack is captured); `console.error(e.message)` / `logger.error(e.message)` at the handling site (stack and cause
  dropped).
- Every language: a failure converted into a Result or error object without its cause
  (`catch (e) { return err(new AppError("Database error")) }`).

**Not a finding:**

- A deliberate break at a published boundary (Go: `fmt.Errorf("%w: %v", ErrPublic, err)` keeps callers off internal
  types); `from None` with a reason.
- Go `%v` with no caller that matches the chain. Go's guidance is to wrap with `%w` only to expose the cause to
  callers; withholding it keeps an abstraction boundary.
- Python `raise X` inside `except` without `from`, unless a caller reads `__cause__`. Python keeps the original as
  `__context__` and prints its traceback; only `__cause__` and the joining sentence differ.
- A custom error class that drops `options` while no call site passes `{ cause }` to it.

**Evidence bar:** the Lost cell names what is gone (`cause`, `stack`, `traceback`, `Is/As match`). For Go `%v`, the
Matching Caller cell names the caller that matches the chain; none → no finding.

**Action:** `%w`; implement `Unwrap`; `{ cause: e }` and forward `options` to `super`; `raise … from e`;
`logger.exception` or `exc_info=True`; throw `Error` instances only.

**Ownership:** wrapping-message *redundancy* (`fmt.Errorf("error: %w", err)`, a wrap at every layer) is slop-hunter's
Unnecessary Error Wrapping. Matching (`==`, string comparison) is Unmatchable Failures. The three compose: wrap with
the cause, wrap once, match by identity.

### Unmatchable Failures

A caller needs to tell a failure apart, and the failure gives it no identity to match: only its message text, or an
identity check that wrapping breaks.

**Signals:**

- Matching by text: Go `err.Error() == "…"`, `strings.Contains(err.Error(), …)`; Python `"duplicate" in str(e)`,
  `e.args[0] == …`; TypeScript `e.message.includes(…)`, `e.message === …`.
- Go identity checks that wrapping breaks: `err == ErrX`, `err.(*T)`, `switch err.(type)` on an error a callee wraps
  (errorlint nominates); an `errors.As` target whose pointer or value form does not match the error's receiver (vet's
  `errorsas` catches only a non-pointer target).
- Go success that looks like failure, or failure that looks like success, with no consumer needed (every
  `err != nil` check is one): a nil sentinel (`var ErrX error`, never set, so `return ErrX` reports success); a
  typed nil returned as `error` (`var e *MyErr; return e`, so `err != nil` is always true). staticcheck SA4023
  nominates the typed nil through a caller's comparison; there is no scan (the Go reference's Detectors).
- Go `var ErrX = "…"` (a string): callers can match it only as text, so it is consumer-gated like any text match.
  `var ErrX = fmt.Errorf("…")` with no `%w` is a valid sentinel: `==` and `errors.Is` match it. Not a finding.
- A generic failure (`raise Exception(…)`, `throw new Error(…)`, an inline `errors.New(…)`) at a site whose caller
  must branch on its kind.
- Python: a domain failure raised as a builtin (`KeyError` for a missing order) that a caller catches together with the
  same builtin from library code; a plain `except ValueError` around `asyncio.TaskGroup` or a 3.11+ API that raises
  `ExceptionGroup` (it never matches; `except*` does).

**Not a finding:**

- A documented code field: Node `err.code === 'ENOENT'`, Python `e.errno`, gRPC `status.Code(err)`, an HTTP status on a
  response error. Matching a library's code outside its adapter is Untranslated Boundary Errors.
- `err == io.EOF` from a direct `io.Reader.Read`: the `io.Reader` contract returns `io.EOF` unwrapped.
- A generic failure that no caller branches on. Not every failure needs a class.

**Evidence bar:** the Consumer cell names the caller that branches on the failure, or the boundary that cannot map it
and so returns 500. No consumer → no finding. For a nil sentinel or a typed nil, the Consumer cell names one
`err != nil` check that gets the wrong answer. Location is the consumer's match site; a nil sentinel or a typed nil
is filed at the failure site's `return` and cites one consumer. Only the Location must be in the target scope; the
other site is read as context.

**Action:** a sentinel (`errors.New`) or a typed error with `errors.Is` / `errors.As` (`errors.AsType` from Go 1.26); a
specific exception class; `except*` for exception groups; Go: initialize the sentinel with `errors.New`, and return
a literal `nil` on success instead of a typed pointer.

**Ownership:** documenting which failures callers match is doc-hunter's Undocumented Contracts; doc-hunter reports it
only when the design is sound. A sibling hand-rolling an `errors.Unwrap` walk is simplicity-hunter's Reinvented
Primitives. Base classes and an `Error` suffix with no consumer are style, never a finding here.

### Untranslated Boundary Errors

A failure crosses a layer in the vocabulary of the wrong layer. Two directions (the report's Direction column):

- `inward` — an external library's failure, type, or code is caught or matched outside its adapter: `except
  IntegrityError` in a service, `errors.Is(err, pgx.ErrNoRows)` in a handler, `err.code === 'P2025'` in a route.
- `outward` — the transport boundary maps a failure to the wrong status, or a non-transport unit decides the status:
  - an expected domain failure reaching the generic 500 (NotFound → 500);
  - every failure mapped to one 4xx (`catch { res.status(400) }`), which hides real 500s;
  - gRPC `codes.Internal` (or `Unknown`) for a not-found or invalid-argument failure;
  - a transport error (FastAPI `HTTPException`, Django `Http404`, NestJS `HttpException` and its subclasses, tRPC
    `TRPCError`, a Go function returning `http.Status*` values) raised in a unit that a non-request entry point (a
    worker, a CLI command, a scheduled job) also reaches. The worker or CLI gets an HTTP error it cannot map.

**Not a finding:**

- Matching inside the adapter. That is the adapter's job.
- A library that no unit wraps for others: each caller is the adapter for its own calls (Terms). The skill does
  not ask to create layers.
- A transport error raised on the request path in a unit that no non-request entry point reaches. FastAPI,
  Starlette, Django, and NestJS map it wherever it is raised, and a Go handler passes a returned `http.Status*`
  through, so no repository policy is needed to allow it.
- A status choice the kind leaves open (400 or 422 for invalid input, 401 or 403 at the edge between them) that
  follows the convention of the project's other handlers.

**Evidence bar:** `inward`: the library the failure comes from, the adapter that exists for it, and the catch site
outside it. `outward` wrong status: the failure's origin, the boundary path it takes, the status it produces, and the
status it should produce. The status is wrong when the kind fixes it (an expected failure → never 500 or `Internal`;
not-found → 404 or `NotFound`; conflict → 409 or `AlreadyExists`), or when this site disagrees with a convention the
other handlers share. `outward` transport error: the raise site and the non-request entry point that reaches it.

**Action:** translate the external failure into a domain failure in the adapter; map domain failures to statuses at
the transport boundary only (one registered handler or one mapping function).

**Ownership:** an import edge from a domain unit to an in-repo infrastructure unit is boundary-hunter's Dependency
Direction Violations. An external type in an inward unit's exported signature is boundary-hunter's External Type
Leaks. Internal detail in an error response body (stack, SQL, path, `err.Error()` sent to the client) is
security-hunter's. Error-response shape and `Content-Type` are not judged. Here: the failure's translation and its
status.

### Double Handling

One failure handled at more than one layer, so it is logged several times or caught and re-raised for nothing.

**Signals:**

- Log and propagate: `log.Printf(…, err); return err`; `logger.exception(…); raise`; `console.error(e); throw e`.
- A catch that only re-raises the same failure: `catch (e) { throw e }`, `except X: raise` (ruff TRY203, ESLint
  `no-useless-catch`).

**Not a finding:**

- A log line that records a different event: a retry attempt at debug or warn level, a degraded fallback.
- A log at a process boundary where returning is impossible (a goroutine's top function, a thread target).
- A re-raise after a cleanup the handler does first (rollback, release).

**Evidence bar:** the First Handling and Second Handling cells. For log-and-propagate, the second site is the layer
that logs the same failure again: the boundary handler, or the framework's documented default (Uvicorn logs an
unhandled exception; Go `net/http` does not log a returned error, because handlers return none).

**Action:** return (with context) or log at the boundary; not both. Delete a catch that only re-raises.

**Ownership:** duplicated error-handling code across functions is simplicity-hunter's.

### Poor Error Context

The final message cannot name the failing step or the failing input, or it puts identifying values where a grouping
tracker needs fixed text.

**Signals:**

- A message that names no input: `errors.New("failed to parse")`, `raise ValueError("invalid input")`,
  `throw new Error("invalid")`.
- Go: an error returned unchanged across a package boundary, when the caller holds an identifying input that the
  callee's message lacks (`u, err := s.repo.Find(ctx, id)` then `return nil, err`). wrapcheck nominates.
- Two return sites in one function or module with the same message text.
- A message event (Terms) whose message is interpolated: `logger.error(f"job {job_id} failed")`,
  ``Sentry.captureMessage(`job ${id} failed`)``. Under default message grouping, interpolated ids can split one
  failure into many Sentry issues. A fingerprint set where the code shows it (the call's scope, a `before_send` in
  the init) overrides that grouping: not a finding. Grouping rules configured in Sentry itself are not checked.

**Not a finding:**

- A fixed message whose callers on the path add the input (a sentinel or `errors.New("record not found")` that the
  caller wraps with the id). The context belongs at the layer that holds it, and that layer supplies it.
- A wrap that would repeat what the inner error says: `*os.PathError` names the operation and the path.
- An error that must stay unwrapped by contract: `io.EOF` from an `io.Reader`.
- A missing step in Python and TypeScript: the traceback or stack names it. There, `input` and `fixed text` (a
  message event) are the only Missing values.
- Interpolated values in an error value (`fmt.Errorf("load %s: %w", id, err)`), or in a log call that attaches a
  stack (`logger.exception`, `exc_info=True`): Sentry groups those by stack.
- `logger.error("job %s failed", job_id)`: Sentry groups by the unformatted text.

**Evidence bar:** the Missing cell names what is missing (`input`, `step`, `distinct text`, `fixed text`) and who holds
it (the caller's variable). For a message event, the Scope's Tracker line.

**Action:** add the operation and the identifying input once, at the layer that holds it
(`fmt.Errorf("load order %s: %w", id, err)`; Python 3.11+ `e.add_note(…)` then a bare `raise`; a custom error with the
field a reader uses); for a message event, Python `%`-style arguments (`logger.error("job %s failed", job_id)`), and
TypeScript fixed text with the values in `extra`.

**Ownership:** words that add nothing (`fmt.Errorf("error: %w", err)`, `"failed to X: failed to Y"`) are slop-hunter's
Unnecessary Error Wrapping. Here: information that is missing.

### Panic and Exit Misuse

A panic or process exit for a failure that external input or the environment can cause, or a `recover` used to carry
on.

**Signals:**

- Go: `panic` on input validation or an I/O, DB, or network failure; `panic` in library code on a failure that a
  caller's input can cause; `log.Fatal` / `os.Exit` outside `main` and `init`; a `Must*` helper on runtime input;
  `recover` that continues normal execution; a panic in a goroutine that a handler spawns, with no `recover` in it;
  a `recover` in HTTP middleware that does not re-panic `http.ErrAbortHandler` (net/http uses that panic to abort a
  response on purpose; swallowing it logs a false panic and writes to an aborted response).
- Python: `sys.exit` / `os._exit` outside the entry point (`__main__`, a `[project.scripts]` target, a CLI command
  function).
- TypeScript: `process.exit` outside the entry point (`bin`, `main`, a CLI command).

**Not a finding:**

- `recover` at the top of a goroutine or in request middleware that turns a panic into an error response.
- `panic` in `init()` or a constructor when repository instructions endorse it (cite the policy). It is a finding when
  external input reaches it, whatever the policy.
- `Must*` on a compile-time constant (`regexp.MustCompile("^a+$")`).
- `default: panic("unreachable")` on a sealed type switch.
- A not-implemented panic or throw in an implementor: solid-hunter's Broken Substitution.

**Evidence bar:** the Reachable From cell names the entry point (a handler, an exported function, `init`) or
`internal only`. The Recovered By cell names the `recover` between the panic and the process boundary, or `none`.
`net/http` recovers handler panics on the serving goroutine (it logs `http: panic serving` and drops the connection),
so a panic is Critical only on a goroutine the handler spawns, or under a server with no built-in recovery (gRPC
without a recovery interceptor, a custom listener). Nothing recovers `log.Fatal` or `os.Exit`.

**Action:** return an error for anything external callers reach; keep `panic` for unreachable code and violated
internal invariants, with a message that names what was found; limit `recover` to goroutine tops and request
middleware; exit only from the entry point.

**Ownership:** `init()` that can fail is smell-hunter's `init()` Abuse; the panic inside it is here only when external
input reaches it.

### Within-skill routing

One site, one finding. The rules, in order:

1. **Expected failure decides Overbroad vs Swallowed.** A handler with an expected failure (Terms) that also
   catches others → Overbroad Handling. A handler with none that drops the failure → Swallowed Errors.
   `except Exception: return None` in `find_by_id` → Overbroad (`None` means not-found). The same line in `sync_all` →
   Swallowed (`defaulted`).
2. **Log then default is Swallowed.** A handler that logs and returns a default is `logged-only` or `defaulted`, never
   Double Handling. Double Handling needs the failure to propagate after the log.
3. **External identity outside the adapter is Untranslated.** An external library's failure matched by text or code
   outside its adapter → Untranslated Boundary Errors (`inward`). An internal failure matched by text → Unmatchable
   Failures. A failure that reaches the generic 500: no identity to map → Unmatchable Failures; an identity the
   boundary does not map → Untranslated Boundary Errors (`outward`).
4. **A dropped cause wins over missing input.** A wrap that drops the cause and names no input → Broken Error Chains;
   the Action also adds the input.
5. **Go goroutines.** `go f()` discarding `f`'s error → Orphaned Async Failures. A goroutine body that drops an error
   it received → Swallowed Errors. A panic in a spawned goroutine → Panic and Exit Misuse.
6. **Cancellation** (Terms: the current task's own, or the caller's deadline). Caught and not re-raised →
   Swallowed Errors. Logged at error level, then propagated or handled → Overbroad Handling.
7. **A justifying comment** is judged with its site, in the category of the site. It is never a separate finding.
8. **A `catch` that cannot run** (TypeScript `return promise` without `await` inside its `try`; return-await
   nominates). The caller gets the rejection untouched. File it at the `return`, in the category of what the catch
   does: translation → Untranslated Boundary Errors; added context → Poor Error Context. A catch that logs or
   recovers is a finding only where the escaped rejection causes a defect at the caller, in that defect's category.
   Action: `return await`.
9. **A log call that drops the traceback or stack** (`logger.error(str(e))`, `logger.error(e.message)`) in a handler
   that is a Swallowed Errors or Double Handling finding → that category; its Action also logs the error with its
   stack. Broken Error Chains takes the log call only when the handler is otherwise correct.

## Applicability

All nine categories apply in Go, Python, and TypeScript. Each language reference's Applicability table states the
language's markers; Panic and Exit Misuse in Python and TypeScript covers exit calls only.

## Test-code scope

**Test files are excluded from every category.** Error handling inside a test (a `try` / `catch` that makes the test
pass whatever happens, an ignored `err` in a test) is test-hunter's Inert and Weak Tests. A missing test for an error
path is test-hunter's Coverage Gaps. Test paths are listed in each language reference. The exclusion is by path: a
helper imported by production code from a non-test path is audited; a production helper under `tests/` is not.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is.** It measures consequence, not confidence.

- **Critical** — the finding names the triggering failure, the wrong outcome (data loss; corrupted or duplicated
  state; success reported for a failed write; a process crash from external input), and why nothing contains it.
  Examples: `_ = tx.Commit()` or `defer f.Close()` on a write path whose caller reports success;
  `except Exception: return None` in `find_order` whose caller creates a new order on `None`, so a DB outage creates
  duplicates; a floating `save()` promise in a handler that returns 200; a panic on request input in a goroutine the
  handler spawns.
- **High** — a silent wrong result or a wrong status awaiting the first failure: a read path that swallows a failure
  and returns empty; any error mapped to not-found or 404; `%v` where a caller matches with `errors.Is`; a swallowed
  `CancelledError` (the task can no longer be cancelled); an expected domain failure that reaches the generic 500; an
  Orphaned Async Failure off the write path; a typed nil or nil sentinel returned as `error`.
- **Medium** — the failure is handled correctly, and diagnosing it costs more than it should: a cause, stack, or
  traceback lost (TypeScript without `cause`, `logger.error(str(e))`, a thrown string); a failure logged twice; a
  message with no input crossing a module boundary; an untranslated external failure with correct behavior today; a
  transport error raised in a unit that a worker or CLI also reaches.
- **Low** — hygiene and adoption: a cancellation logged at error level; an interpolated message event; adopting
  `errcheck` or `no-floating-promises`.

Critical needs the caller's behavior. A caller outside the target scope is read as context; when it cannot be found,
the finding states the consequence as unknown and takes High at most.

**Impact — how much the change is worth:** defect exposure reduced, cognitive burden reduced, surface affected.
Contextual; never derived from occurrence count.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

## Audit Workflow

### Phase 1: Gain Context

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

2. **Detect languages** from file extensions alone: the manifest's, or in codebase mode those of
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the scans still search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**. Record `excluded — no reference for .<ext>: {count} files` in Scope,
   naming each extension.

3. **Load language references.** For every detected language, read `references/exception-<lang>.md` from the
   directory this SKILL.md was read from (e.g. `references/exception-go.md`). **Fail closed:** if a required
   reference cannot be read, **stop and report**.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus
   the test-path exclusion** to that language's files. These subsets are then immutable. Record in Scope: raw
   manifest count, each per-language eligible subset, exclusions with the test paths listed, and
   `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, Markdown-only inputs, test paths, and generated files
   identified by each reference's authoritative **in-file marker** — **never** by filename guessing.

   Write each subset to `<run>/<lang>.txt` (`go.txt`, `python.txt`, `typescript.txt`). Codebase mode: the single line
   `.`. Diff and path mode: the eligible files, one per line — `comm -12 <(rg --files --type <t> $EXCLUDE | sort)
   <(printf '%s\n' $SCOPE | sort)` with the loaded reference's `--type` and `$EXCLUDE`, minus files carrying a
   generated-code marker (`| while read -r f; do rg -q -m1 '<marker>' "$f" || echo "$f"; done`, the marker regex built
   from the reference's eligibility section); the reference's generated-file globs are the same scan approximation a
   codebase run uses. Filter before scanning: `rg` applies `--type` and `--glob` only while walking a folder and
   searches every file named on its command line. Each scan call restores its list first — `GO_FILES=$(cat
   <run>/go.txt)` (`PY_FILES`, `TS_FILES`) — and the reference blocks pass it as `rg -H … -- $GO_FILES`: given one file,
   `rg` prints no file name unless `-H` is set.

   The lists are `$GO_FILES`, `$PY_FILES`, and `$TS_FILES`. A language with no eligible file gets no `<lang>.txt`.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop
   before scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Files outside it, test files included, are *read* as **context**: callers, the boundary a failure reaches,
   the adapter, the framework's registered handlers. Diff and path scope narrow the manifest, never the context
   reading.

5. **Record the failure-handling context** per language (report-format.md says which Scope lines print):
   - **Language versions** that gate a remedy or a consequence: the `go` directive in `go.mod`; `requires-python`
     (or the lockfile's interpreter); tsconfig `target` and `lib`; the Node major from `engines.node` or `.nvmrc`,
     else `unknown`. Per `package.json` that depends on `express`: its major version and whether it loads an async
     wrapper (`express-async-errors`, or a local wrapper applied to the routes). A remedy is proposed only when the
     recorded version supports it (each reference's version gates). With a version `unknown`, the Action names the
     version the remedy needs.
   - **Rejection handling** (TypeScript): a process-level `unhandledRejection` listener, and a
     `--unhandled-rejections` mode set where the repository shows it (package scripts, `NODE_OPTIONS` in a
     Dockerfile or deploy file): `rg -n -- '--unhandled-rejections'` over the repository. Both decide an orphaned
     rejection's consequence: `warn`, `warn-with-error-code`, and `none` continue without a listener, `strict`
     crashes even with one, and otherwise a listener replaces the crash with whatever it does. The Consequence cell
     says which. Deployment settings outside the repository are not searched; with none visible, the cell names the
     default and says the deploy may override it.
   - **Transport boundaries:** the transport frameworks and their boundary files (handlers, middleware, registered
     exception handlers; each reference's Transport frameworks section), and the non-request entry points (workers,
     CLI commands, scheduled jobs) from which Phase 4 traces transport errors. With no entry point recorded, every
     transport-error candidate closes at once.
   - **Tracker:** the Sentry setup that decides message events (Terms), or none.

6. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) for a stated error policy: panic in
   constructors or `init`, a named adapter layer, a sanctioned best-effort list. A stated policy is respected; one
   that withdraws a pattern is named in the report's `Policy:` line. Only a panic policy has an override: a panic
   that external input reaches is a finding whatever the policy says (Panic and Exit Misuse).

### Phase 2: Run Detectors

Run each detector the loaded reference's Detectors section names, under the condition that section states (for
most detectors: the project configures it), with the reference's read-only command and the project's own config. A
detector is never installed, fetched, or reconfigured. Its output nominates. Keep only diagnostics whose file is
in the language's eligible list; in codebase mode, where the list is `.`, drop diagnostics on test paths and on
paths the reference's `$EXCLUDE` globs match. Record one entry per detector on the Scope's Detectors line:

- `ran — <command>`. A run that printed its diagnostics is `ran`, whatever its exit code.
- `ran — new issues only — <command>`, when the project config limits the run to new issues. Its silence is not
  coverage.
- `skipped — not configured`, `skipped — no error-relevant rules enabled`, or `skipped — configured, not installed`.
- `errored — <message>`, when the detector stopped before analysis (a config, load, or option error). Its output is
  not used.

Done when every detector the loaded references name has its Detectors entry, and every kept diagnostic is listed as a
candidate.

### Phase 3: Scan for Candidates

For each language that has a `<run>/<lang>.txt`, run the loaded reference's Phase 3 scan block over that list,
restored in the same call (Phase 1 step 4). Every hit is a candidate. Diff mode nominates from the working tree of
the manifest files, not from added lines: error handling is a property of the current code.

**Boundary pass.** Each recorded transport boundary's error mapping (the registered handler or mapping function;
with none, each handler's error branch) is also one candidate, so a wrong status needs no regex hit.

Done when every scan in each loaded reference's Phase 3 block has run, every boundary mapping is listed, and every
hit is listed as a candidate.

### Phase 4: Trace Each Candidate

For each candidate, read the handler, the `try` body or the callee, and the path to the boundary: who calls it, where
the failure is logged, what status it produces. This is where Overbroad Handling finds the second failure, Double
Handling finds the second handling site, Unmatchable Failures finds its consumer, and Untranslated Boundary Errors
finds its boundary. Tracing reads beyond the manifest in every mode.

Done when every candidate is either dismissed at its site by a named Not-a-finding case or reference Phase 5
question, or has its handler, its failure's source, and its path to the boundary read.

### Phase 5: Evaluate Each Candidate

For each candidate: apply the category's **Not a finding:** lines and the loaded reference's Not-a-finding list;
apply the within-skill routing (if it moved the candidate, apply the routed category's lines too); cross-reference a
candidate that an **Ownership:** note gives to another hunter; clear the category's evidence bar; check repository
policy (Phase 1 step 6). Run each loaded reference's Phase 5 block.

Assign **Severity and Impact** to every finding. Nothing is held back; `Audit completed: N findings` counts every
reported finding.

Done when every candidate is a reported finding, dismissed by a named Not-a-finding case, or handed off to its
owning hunter.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-exception-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or
return mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched. Every detector runs with its
  read-only flags, so `git status` shows only the report file after the run.
- **Evidence required.** Every finding cites `file:line` with the exact code, and the category's evidence cells,
  named in `references/report-format.md`, are filled from code read, never inferred.
- **Comments are claims; the code is evidence.** A justifying comment (`// read-only; close error carries nothing`)
  is checked against the code — here, the open mode — never trusted.
- **One site, one finding.** When two categories describe the same code, the within-skill routing picks one, and the
  other is cross-referenced.
- **Never install.** Run only tools the project already has; a tool that is configured but absent is `skipped`,
  never fetched.
- **Hand off.** A candidate another hunter owns is cross-referenced to that hunter and not scored here.
