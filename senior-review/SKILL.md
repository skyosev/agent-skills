---
name: senior-review
description: Strict senior-engineer review of a codebase, path or branch diff for design, over-engineering, failure handling, naming, tests and spec fit, saved as a report.
disable-model-invocation: true
---

# Senior Review

Review the scope as a strict senior engineer and write a report. Every finding cites `file:line`, quotes the code, and proposes a concrete fix with its trade-off. The code stays unchanged.

## 1. Pin the scope

The prompt names the surface: a branch diff, paths, or (default) the whole codebase. For a diff:
```bash
BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)
git diff "$(git merge-base HEAD "$BASE")"...HEAD
git log --oneline "$BASE"..HEAD
```

An empty diff ends the review here. A diff finding must be caused by the diff: untouched code is in scope only where the diff makes it wrong (a caller of a changed function, a sibling the diff forgot).

## 2. Load standards, spec and languages

- **Standards**: every file in the repo that documents how code is written: `CLAUDE.md` / `AGENTS.md` at the root and in each directory holding reviewed files, `CONTRIBUTING.md`, `CODING_STANDARDS.md`, testing guides. A rule covers its own directory and below. A documented repo rule overrides the lens in step 3 where they conflict.
- **Spec** (diff scope): issue references in commit messages, the PR title and body (`gh pr view`), a path the user passed, a spec under `docs/` matching the branch name. When none exists, the Spec section is skipped and Scope says so.
- **Languages**: hold each file to its own language's idioms and conventions. A language's verbose idioms (Go's explicit error checks, Java's checked exceptions) are idioms, not findings.

## 3. Apply the lens

Read every file in scope and apply every section below to it. Fowler smell names in parentheses are labels to use in findings.

For a large scope, dispatch one subagent per lens section, pasting it that section, the scope, and the standards list.

### Design

- **Fix the state, not the reader.** A reader guards against state that should never exist (empty, half-built, duplicate) instead of the writer preventing it at creation or normalizing it in the constructor. An invariant the data store could declare (primary key, unique key, NOT NULL with a valid default) is enforced in application code instead. A view returns a value every query must patch. A guard that explains when the bad state is harmless, or relies on an invariant enforced elsewhere, marks the fix in the wrong place.
- **Reshape, don't add beside.** A new function sits next to an existing one and every caller calls both as a pair, each taking its own lock or doing its own lookup. A branch returns a placeholder (empty value, stub object) that callers never read, so the return type is wrong.
- **One owner per decision** (Duplicated Code). The same default, fallback, conversion, validation, parse, constant or lookup appears in two layers. Data is encoded only to be decoded again. Data the caller already holds is fetched again by ID. Two functions or types differ in one field. A stored value is derivable from data already held. Code turned lenient to absorb input that is wrong at its source (a misspelled config key, a bad manifest).
- **Dependencies point inward.** Domain code imports I/O, a file format, a framework or a service. A domain type is named after the tool that fills it. Storage-only fields (`created_at`, join keys) sit on domain types no domain rule reads them from. Shared code holds one integration's or vendor's names, statuses or special cases. A business decision lives in a query or loader. An interface is declared beside its only implementation instead of in its consumer, with more methods than the consumer calls. A check or loop sits in the composition root instead of the component it concerns.
- **Idiomatic code.** A pattern fights the language: hidden dependencies (globals, init side effects) where explicit ones are idiomatic, inheritance where composition fits, a module layout nested deeper than its responsibilities.
- Also label: Feature Envy, Data Clumps, Primitive Obsession, Repeated Switches, Shotgun Surgery, Divergent Change, Message Chains, Refused Bequest. These are judgement calls: write "possible Feature Envy".

### Over-engineering: name the consumer

Every parameter, field, method, endpoint, config value, flag, migration and fallback has a consumer: code that reads it, or a stated requirement.

- A parameter every caller passes as nil, zero or the same constant.
- A field written but never read, or read only by tests.
- A guard, filter or special case lacking either an input on which it changes the result, or code that writes that input. A test that builds the input by hand is not that writer.
- Public visibility with no caller outside the module; a test is not that caller.
- A layer that only forwards (Middle Man): a wrapper around one call, a type that only delegates, a once-called helper hiding no detail. A factory, manager or registry with one product. Configuration or plugins for behaviour that never varies. A generic solution for one concrete case (Speculative Generality).
- An old flow left in place after a new one replaced it.
- Defaults copied from a ported dependency (timeout, retry count, sampling) that nobody chose.
- A migration, backfill or compatibility shim with no real data or clients to act on.
- A public contract (API field, event, file format) with real clients changed by removal or rename instead of by addition plus deprecation.
- Tell-tales: "for completeness", "for parity", "in case we need it later", a suppressed unused-code warning, an unexplained copied number.

### Failure handling

- **Make failure and absence explicit.** An error discarded, or logged followed by `return 0` / empty. Not-found returned as an empty value. A `default` branch that silently does nothing, with no comment saying why. Any error treated as not-found. Input from outside the process (request, file, message) able to crash it instead of becoming a validation error. Expected failures (not found, invalid, conflict) sharing one generic error instead of distinct types mapped at the boundary (404, 400, 409; only the unexpected becomes 500). A missing value stored as zero where zero is also valid; a nullable type where no reader treats absence differently. Only the first element of a list handled.
- **Errors say what and where.** An error returned unchanged across a module boundary. A message naming no input (file, row, ID, key). Two return sites with identical text. Identifying values in message text where an error tracker groups by message (they belong in structured fields). One failure logged and returned, so several layers log it. A log level that does not match how expected the event is.

### Names and comments

- **Names tell the truth.** A name the behaviour has outgrown (`Get` returning a list, `disabled` meaning "active only"). One concept with different names across database, code, API and docs. A prefix repeating the package or enclosing type. A message or doc true for only one of the cases it covers.
- **Comments say what the code cannot.** A comment restating the code or walking through the algorithm. Task history ("now uses", "changed to", "on client feedback"). An `IMPORTANT` or "used by X" claim that the code contradicts: verify it. An external constraint (vendor bug, protocol rule, regulation) without its source; a workaround without its removal condition. An invariant a type, assertion or test could enforce. A doc comment missing units, side effects or errors the signature cannot state.

### Tests: each can go red

For each test, name the code change that turns it red. Flag the test when none exists.

- Asserts call counts, call order or mock calls where the caller-visible outcome (return value, stored row, sent message) is the contract.
- Expected value computed by the code under test, or round-tripped through the same structs that parse it.
- Asserts a value the test itself assigned, or that a double returns what it was told; a double that answers any argument where the subject passes its result through.
- Failure path untested: that later steps did not run and nothing was stored.
- Test data stating more than the case depends on, where a shared builder or fixture exists.
- Depends on state another test created.
- Production code reshaped to suit a test.
- Tests a removed symbol stays removed, a source file's text, the language's own library, or that a non-nullable ID is not null. A test title that names a behaviour the assertions don't check.
- Coverage and level: critical paths and edge cases untested; unit tests for logic, integration tests for boundaries, end-to-end for critical flows; mocks at internal seams coupling tests to implementation; brittle setup. The project's testing guide, when one exists, is followed.

### Diff scope only

**Every hunk serves the change.**

- A hunk the stated goal does not need: a changed deploy trigger, a reformatted file, a rename in otherwise untouched code.
- A removed or weakened assertion with no reason in the PR description.
- Debug code, commented-out code, comments or TODOs the change made untrue.
- A field, handler or setting silently dropped by a merge or automated migration: check every removed line.
- A missing sibling: the change adds a variant (enum value, message type, state) or changes how a concept is built, and a place that lists or builds its siblings was not updated. Search for those places.

**Spec**, when one was found: requirements missing or partial; behaviour nobody asked for (scope creep); requirements implemented wrongly. Quote the spec line.

### Repo standards

A violation of a rule loaded in step 2: cite the file and quote the rule.

## 4. Verify each finding

Re-open the cited code and _refute_ the finding: search for the consumer you claim is missing, the earlier layer you claim duplicates the decision, the test you claim is absent. Keep only findings that survive. Also drop: in diff scope, issues the diff did not cause; what a linter or compiler already enforces; code silenced on purpose with a stated reason; the language's own idioms; nitpicks a senior engineer would let pass.

## 5. Write the report

Save as `YYYY-MM-DD-senior-review-{model}.md` in the project's `docs/` folder, or the project root when there is none. Write a heading, section or list only when it holds at least one item; a clean area is simply absent from the report.

````md
# Senior Review — {date}

## Scope

- Surface: {diff <base>..HEAD | path | codebase}
- Files: {count, or list when under 15}
- Standards read: {files}
- Spec: {source, or "none found"}
- Exclusions: {what was skipped and why}

## Spec

- **Missing**: {requirement} — "{quoted spec line}"
- **Scope creep**: {behaviour} at `file:line`
- **Wrong**: {requirement} at `file:line` — "{quoted spec line}"

## Must-fix

### 1. {Rule or smell}: {one-line claim}

`path/to/file.ext:42`
```{lang}
{the exact code}
```
**Why:** {consequence, concretely}
**Fix:** {the change}
**Trade-off:** {what it costs, or "none"}

## Should-fix

## Consider
````

Severity:
- **Must-fix**: wrong behaviour, data loss, a hidden failure, a missing spec requirement, a critical path with no test able to fail.
- **Should-fix**: a design violation that makes the next change harder, over-engineering, a misaligned test level, a non-idiomatic pattern.
- **Consider**: minor simplifications, naming, test ergonomics, documentation gaps.

Number findings across the whole report.
