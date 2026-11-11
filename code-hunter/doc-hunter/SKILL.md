---
name: doc-hunter
description: Audit Go, Python, or TypeScript code for documentation that fails its reader — unexplained business rules, unnamed algorithms, unexplained workarounds, undocumented contracts, misleading comments and names. Defaults to the codebase.
disable-model-invocation: true
---

# Doc Hunter

Audit code for **documentation that fails its reader** — the places where a reader loses time or is misled because the
code does not say why: `if hours > 6` with no clause behind the 6, a `time.Sleep` before a vendor call with no cause,
a doc that says "returns ErrNotFound" over `return nil, nil`, a `GetRate` that inserts a row. Goal: **every reason a
reader needs before changing the code is in the code, its names, or its comments, and every comment and name is
true.**

**Not covered (owned by other hunters):** redundant comments, verbose docs (`jsdoc/informative-docs` included), vague
`TODO` / `FIXME` / `XXX` work items, hedging, and task history in comments (→ slop-hunter); "what" comments over
non-trivial code (Comments as Deodorant), call order of the project's own API (Temporal Coupling), duration integers,
floating-point money, and raw status strings, also when a comment states the allowed values (Primitive Obsession),
stuttering names (no hunter owns them); comments that justify a nil or zero-value contract, an invariant that a runtime
check already enforces (→ invariant-hunter); comments that justify a discarded error, Go reachable panics, `None` /
`undefined` returned for an error (→ exception-hunter); Go errors discarded by `_ =` (no hunter owns them); empty
catches and discarded promises are not covered here; code that needs a "what" comment, intentional complexity whose
stated reason is stale (→ simplicity-hunter); unused code under `// IMPORTANT: do not remove` (→ boundary-hunter for an
export, else no hunter); an implementation that breaks a *documented* interface contract (→ solid-hunter); Go aliases
without a migration comment (→ type-hunter); generic package names (→ boundary-hunter); doctests and Go `Example`
functions (→ test-hunter); comments that leak secrets (→ security-hunter). Where ownership is *contested*, the
category's **Ownership:** note in What to Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `perf-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical. Every category
applies in every supported language; each language reference holds its scans and remedies.

| Category | Core signal | Required evidence | Action |
| -------- | ----------- | ----------------- | ------ |
| Unexplained Business Rules | A domain threshold, eligibility, rate, or exclusion with no stated source | Why-search | Name the source (clause, regulation, policy) |
| Non-Obvious Algorithms | A named technique, formula, format, or bit layout that the code does not name | The technique, or `unidentified` | Name it in the function or a comment; `unidentified` → the question |
| Unexplained Workarounds | Code shaped by a dependency, platform, or protocol, with the cause unnamed | What is missing: cause, removal condition | State the cause; for a defect, also when the workaround can go |
| Undocumented Contracts | A caller must know something the name and signature do not say; or a comment states an invariant the code could enforce | The clause, the line that establishes it, the caller evidence | Doc comment stating the clause; `enforceable` → the enforcing type, check, or test |
| Misleading Comments and Names | A comment, doc, or name claims what a cited line contradicts | The claim, quoted, and the contradicting line | Correct or delete the text; rename |

## Core Principles

1. **Scans nominate; reading decides.** A scan hit is a line to read, never evidence.

2. **Quote only what the Why-search found.** An invented regulation, cause, link, or fixed version is worse than no
   comment; when the search finds nothing, the Action is the question for the author.

3. **The comment standard below decides what a comment must and must not carry.** Each of its rules names the
   category that hunts it; the comment ownership rule decides which hunter reports a comment.

**The comment standard.** A comment carries only what a reader cannot get from the code. The reader is assumed to read
the code and search the repository's files; a reason found there needs no comment. A comment is warranted for:

- a business rule or decision whose reason is not in the repository → Unexplained Business Rules.
- a constraint set outside the code (a vendor defect, a protocol rule, a contract clause, a regulation). It names its
  source, so that a reader can look it up → Unexplained Business Rules, Unexplained Workarounds.
- the reason for a choice the code does not explain → the three missing-why categories (Terms). Only where the choice
  is a value, a technique, an external constraint, or a domain rule: other design choices (a stable sort, a defensive
  copy) look like ordinary code and have no signal.
- a contract the types cannot state: units, side effects, errors returned, inputs rejected → Undocumented Contracts.

Rules of the standard:

- Make the code say it first: a name, a named constant, a type, a signature. Comment only when that fails. Every
  Action here offers a name or a constant before a comment, wherever one can carry the point. A "what" comment is
  slop-hunter's (trivial code) or smell-hunter's (non-trivial code).
- A workaround for a defect states when it can go → Unexplained Workarounds.
- An invariant the code could enforce belongs in a type, an assertion, or a test, and the comment stays until that
  lands → Undocumented Contracts (`enforceable`).
- Task history (what changed, what was tried, who asked) belongs in the commit or PR → slop-hunter's Hedging and
  Narration.
- A claim in a comment ("used by X", "IMPORTANT: do not remove") is checked, never trusted. A false claim → Misleading
  Comments and Names. A claim the repository cannot settle → no finding.
- A doc is true for every case it covers → Misleading Comments and Names.
- A name says what the thing is or does → Misleading Comments and Names (`name`). One concept has one name in storage,
  code, API, and docs → the same, at mapping sites. A prefix that repeats the package or type → no hunter.

**Comment ownership rule** (shared with slop-hunter and smell-hunter; the first match wins):

- Comment contradicts the code it describes → doc-hunter (Misleading Comments and Names), unless it only justifies a
  construct another hunter audits (a discarded error, a zero-value contract) → that hunter.
- Comment calls the code a hack or a workaround but names no cause → doc-hunter (Unexplained Workarounds).
- Comment states an external constraint but not its source, or a dependency defect but not when the workaround can
  go → doc-hunter (Unexplained Business Rules or Unexplained Workarounds).
- Comment states an invariant that no check enforces and the code could → doc-hunter (Undocumented Contracts:
  enforce it, keep the comment until then), unless a status-string, duration, or money type would enforce it →
  smell-hunter.
- Comment states a "why" the code cannot (a source, an external cause, a contract the types cannot state) and the
  code matches it → no finding.
- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment restates what trivial code does → slop-hunter (delete the redundant comment).
- Comment explains what non-trivial code does → smell-hunter (extract/refactor; the comment is deodorant).

*Trivial* code is one statement or one simple condition whose meaning the comment repeats; a comment that summarizes
two or more statements or a compound condition sits over non-trivial code.

## Terms

- **Why** — the reason a reader needs before changing code safely: the source of a rule, the cause of a workaround,
  the origin of a value. It is not *what* the code does.
- **Missing-why categories** — Unexplained Business Rules, Non-Obvious Algorithms, and Unexplained Workarounds. Their
  findings carry a Why-search result.
- **Doc comment** — Go: a comment immediately before a top-level `package`, `const`, `func`, `type`, or `var`
  declaration, with no blank line between (go.dev/doc/comment). Python: a docstring, the first statement of a module,
  class, or function. TypeScript: a `/** … */` block immediately before a declaration; a `//` comment is never a doc
  comment.
- **Contract** — what a caller must know that the name and the signature do not state: side effects, hidden inputs,
  ownership and lifetime, concurrency safety, the errors or exceptions callers are meant to handle, the inputs it
  rejects, and units or ranges that the name does not state.
- **Business rule** — a domain decision in code: a threshold, eligibility, rate, deadline, or exclusion. Its source is
  a contract clause (a charter-party clause), a regulation, or a product policy.
- **Workaround** — code shaped by a dependency, platform, or protocol, not by the domain. It is either a compensation
  for a defect or quirk, or an order or delay that the dependency requires.
- **Expired comment** — a `TODO` or workaround comment whose stated condition the repository shows is met: the
  dependency version is past the one named, the named flag or symbol is gone, the named date has passed.
- **Why-search** — the fixed procedure whose result every missing-why finding records as evidence (Phase 5).
- **Library unit** — a unit with strong evidence that code outside the repository imports it. Every other unit is
  closed.
  - Go: a package outside `internal/`, in a module that has no `main` package and whose module path's first element
    contains a dot (fetchable by `go get`). Each `go.mod` is judged on its own.
  - TypeScript: a workspace package without `"private": true`. Its public symbols are those exported from the source
    files that its `exports`, `main`, or `types` entries map to. A target under the package tsconfig's `outDir` maps to
    the same path under `rootDir`, with the source extension. A target that maps to no source file leaves the unit
    closed, with a Scope note.
  - Python: none. No in-tree signal separates a library from an application packaged as a wheel: a uv or FastAPI
    service has `[project]` and often `[build-system]`.

  It is narrower than boundary-hunter's Published unit, because here an open unit raises a finding's severity and
  prints a tooling line: `doc.go`, `examples/`, and a README import path open nothing here.
- **Critical code** — code whose wrong result is silent and costly: calculations (money, quantities, time),
  validation and authorization decisions together with the wiring that applies them (the middleware attached to a
  route), state transitions, persistence mappings, parsers of external input, idempotency and deduplication (a
  duplicate charge), destructive operations (delete, retention). Every critical-code claim names the wrong result and
  who pays for it; that is also how a thin wrapper, logging, or a configuration value qualifies (a lowered minimum
  TLS version, a session cookie without `Secure`). Generated code is never critical.
- **Target scope** — the files a finding may anchor at; every other file is read as context (Phase 1 step 4, Two
  surfaces).

## Not a finding on these grounds alone

Applies to every category; each category adds its own **Not a finding:** line.

- **A scan hit.** It nominates a line to read (Core Principles).
- **A vague or generic name** (`data`, `handle`, `process`). A name finding needs a cited line that contradicts the
  name's claim.
- **A claim the repository cannot settle** (an external client, another service).
- **A missing example.** No finding asks for an example function or a usage example.
- **Error message text and Markdown.** Error message text is runtime output, not a doc. READMEs, ADRs, diagrams, and
  other Markdown are read as context (Why-search step 4), never audited.

## What to Hunt

### Unexplained Business Rules

A domain threshold, eligibility, rate, or exclusion with no stated source.

**Signals:**

- A comparison against a literal or a named constant whose name gives no source: `if hours > 6`,
  `const minNotice = 26` with no clause.
- An eligibility check that combines several conditions, and no comment states the rule they implement.
- A rate, percentage, or deadline in a calculation on critical code.
- A comment that gives the rule an outside origin but no source a reader can look up: `// contractual minimum`,
  `// per regulation`. A source is a clause, an article, a policy document, or a ticket.

**Not a finding:**

- The source is stated at the declaration (`const noticeHours = 26 // SUPPLYTIME 2017 cl. 12`). Its uses are not
  findings.
- A rule whose name states it fully (`isWeekendOrHoliday`).
- Domain vocabulary that the repository defines (glossary, README).

**Evidence bar:** the Open Question ("which clause sets 6 h?") and the Why-search result.

**Action:**

- Why-search found a reason → a name that states the rule (`minWeatherHours`), and a comment at its declaration that
  cites the source ("from 3f2a1c: SUPPLYTIME cl. 12").
- Why-search found nothing → the Action is the question for the author ("state the source of 6 h; none found in code,
  docs, or 4 commits").

### Non-Obvious Algorithms

A named technique, formula, format, or bit layout that the code does not name.

**Signals:**

- A known formula or technique that the code does not name: haversine, Luhn, compound interest, a varint, CRC, or
  base-N encoding.
- Bit manipulation outside plain flag checks.
- A regular expression that validates a format defined elsewhere (an IMO number, IBAN, ISO 8601 duration), with
  neither a name nor a reference.
- A comparator with tie-break rules.

**Not a finding:**

- A function or constant name that names the technique (`haversineKm`, `imoPattern`).
- A simple regex (a prefix, a single character class).

**Ownership:** multi-step transformations whose intermediate goal is unclear need a "what", which is
simplicity-hunter's (Mixed Concerns, extraction), or smell-hunter's when a comment is present (Comments as
Deodorant).

**Evidence bar:** the Technique (its name, or `unidentified`) and the Why-search result. A technique is identified
only when the cited lines compute its defining formula; code that only resembles it is `unidentified`.

**Action:**

- Technique identified → name it in the function name; a comment only when a name cannot carry it. Cite its source
  (spec, RFC, paper) only when the Why-search found one.
- `unidentified` → the Action is the question to the author ("which formula is this?", or "is this X?" for a
  resemblance), and proposes no name.

### Unexplained Workarounds

Code shaped by a dependency, platform, or protocol, with the cause unnamed.

**Kinds:** `defect` (compensates for a bug or quirk in a dependency or platform), `imposed order` (a dependency
requires an order), `timing` (a delay or retry that compensates for an external behavior), `platform branch` (a branch
on OS, browser, runtime, or library version). A platform branch or a delay that compensates for a defect is kind
`defect`, so it needs its removal condition.

**Signals:**

- A sleep, delay, retry, or timeout with no stated cause.
- A branch on platform, user agent, runtime version, or library version.
- A comment that calls the code a hack or a workaround without naming the cause, whatever its marker (`HACK`, `XXX`,
  `TODO`, `FIXME`, or none).
- A comment that names a dependency defect the code works around, but not when the workaround can go.
- Defensive code for a case the types rule out, when it compensates for a dependency (otherwise it is
  no hunter's, or invariant-hunter's Defensive Access).
- An order of calls on a third-party object that breaks if reordered, when the dependency's documentation does not
  present it as standard use, with no comment. Example: subscribe only after connect, on a client that drops earlier
  subscriptions.

**Not a finding:**

- A comment that names the cause concretely and, for kind `defect`, when the workaround can go. "Remove when
  <dependency> fixes <defect>" is a removal condition. A tracker link is quoted when the Why-search finds one; it is
  never required, because a vendor defect may have no public issue.
- An order the dependency documents as standard use (flush before close, unlock after lock).
- Build-constraint files that are the normal per-platform split (`file_linux.go`).

**Ownership:** an order of the project's own API is smell-hunter's Temporal Coupling. A workaround for the project's
own design is smell-hunter's Comments as Deodorant. Vague `TODO` / `FIXME` / `XXX` comments that do not call the code
a hack or a workaround, and name no defect, are slop-hunter's work items. A `# type: ignore` without a reason is not
covered here.

**Evidence bar:** Missing — the cause, or for `defect` the removal condition — and the Why-search result.

**Action:** state the cause. For `defect`, also state when the workaround can go, with the tracker link when the
Why-search found one.

### Undocumented Contracts

A caller must know something the name and signature do not say; or a comment states an invariant the code could
enforce.

**Kinds:** `missing` (no text states the clause), `enforceable` (a comment states it, and no check enforces it although
the code could).

**Signals:**

- **Side effects** that the name and signature do not show: the function mutates an argument, writes to storage or
  the network, or changes global state. The name is neutral here (`apply`, `process`); a name that claims the
  opposite is a Misleading Comments and Names finding (`name`).
- **Hidden inputs**: the function reads a context value, an environment variable, or a global that callers must set.
- **Ownership and lifetime**: the caller must close the result, or must not keep or mutate a returned slice, buffer,
  or map.
- **Concurrency**: Go — an exported type whose methods lock a mutex or use atomics, with no statement of what is safe
  for concurrent use. Python — a class used from threads.
- **Errors and exceptions** that callers are meant to handle: a Go sentinel or typed error that callers match; a
  Python exception that callers catch; a TypeScript `throw` that callers catch. These count only when the error design
  itself is sound.
- **Boundary handling and rejected inputs** with a caller-visible effect: empty input returns all rows, not none; the
  end date is inclusive; a negative amount, which the type allows, returns an error. A doc whose sentence covers that
  input and states another result is a Misleading Comments and Names finding (`false`): "returns body truncated to
  maxBytes" over a `maxBytes <= 0` branch that returns the whole body.
- **Interface contracts**: two implementations of an owned interface differ on a caller-visible point (one returns
  `ErrNotFound`, the other `nil, nil`), and no doc states which is the contract.
- **Units or ranges** of a parameter or a return that the name does not state, when a line in the body fixes them
  (`p / 100`, `metres / 1852`). That line is Established At.
- **Enforceable** (kind `enforceable`): a comment or doc states an invariant that no check enforces, and a type, a
  check at construction, or an assertion could: `// ids is never empty`, `// pct is 0–100`.

**Not a finding:**

- A side effect that the name's verb states (`Save`, `Delete`, `Send`, `Close`), or a write by a method of a type whose
  name names the store (`UserRepo`).
- A hidden input read in an entry point or a configuration module: Go `package main`, a TypeScript entry file, a
  Python settings module or a pydantic `BaseSettings` class.

**Ownership:**

- Call order of the project's own API → smell-hunter's Temporal Coupling.
- Integers for durations and floating-point money → smell-hunter's Primitive Obsession (its own signals). So is an
  `enforceable` comment that a status-string, duration, or money type would enforce.
- An invariant that a runtime check already enforces, when a type could carry it → invariant-hunter's Runtime Checks
  Promotable to Types.
- Go nil semantics and zero-value contracts → invariant-hunter (Nil Pointer Risks, Zero-Value Traps).
- Error design: a failure returned as `None`, `undefined`, or a zero value, a reachable panic → exception-hunter. An
  empty catch and a discarded Go error are no hunter's.
- An implementation that breaks an interface contract a doc *does* state → solid-hunter's LSP finding.

**Evidence bar:**

- the Contract Clause.
- Established At: the line that creates the behavior.
- Caller Evidence, from a search for the symbol's callers (`rg -n -w '<symbol>' -- .`): a caller that ignores or
  contradicts the clause (cite it); else the symbol is an export of a Library unit; else the reason a caller cannot
  see the clause from the name and signature.
- For `enforceable`: the Contract Clause cell starts with `enforceable:` and quotes the comment, Established At is the
  comment's line, and Caller Evidence is a path that can break the invariant unchecked (a caller, a parse, or a
  constructor that admits the value).

**Action:**

- For a unit or a range, a name that states it (`ratePct`, `distanceNm`); a doc comment is the alternative. For any
  other clause, a doc comment stating it, in the language's convention.
- `enforceable` → name the enforcement (a type, a check at construction, an assertion, or a test), and keep the
  comment until it lands.
- Interface contracts: the Action names both behaviors; the author picks the contract, and the other implementation
  changes.

### Misleading Comments and Names

A comment, doc, or name claims what a cited line contradicts.

**Kinds:** `stale` (true once, false now), `false` (contradicts the code), `expired` (its stated condition is met),
`name` (a name whose claim the code contradicts).

**Signals:**

- A comment or doc that describes behavior the code does not have: "rounds up" over code that rounds down; "returns
  ErrNotFound" over `return nil, nil`.
- A reference to a symbol that no longer exists: a Go doc link `[Name]`, a `Name()` mention, a TypeScript `@see Name`.
- An expired `TODO` or workaround comment: it names a version or a date that the repository shows is past.
- A usage or dependency claim that a repository search refutes: `// used by the billing job`, `// IMPORTANT: the
  importer relies on this order`, when no such use exists.
- A doc that is true for only some of the cases it covers: it names one cause of an error that two paths return, or
  describes one branch of a function that has two.
- A name whose claim the body contradicts:
  - a query verb (`get`, `find`, `is`, `has`) on a function with an effect beyond the read: it persists a record,
    sends a command (an email, a published event, a request that changes remote state), or mutates an input
    argument. Part of the read, so no contradiction: a request that only reads (`http.Client.Get` sends a GET), an
    output argument the signature shows (`out *User`), a cache fill, lazy initialization, logging, metrics.
  - a plural name with a singular result, or the reverse.
  - a boolean whose polarity its assignments invert (`disabled` set `true` when active).
  - a unit suffix the value contradicts (`timeoutMs` that holds seconds).
- One concept under two names at a mapping site, where both names sit on one line: a Go struct tag, a pydantic
  `alias=`, a SQLAlchemy `Column("…")`, a TypeScript mapping object. Example: `IsDisabled` with `db:"is_hidden"` and
  `json:"archived"`. Contradicted At is that line.

**Not a finding:**

- A change of case or naming convention at a mapping site (`UserID` ↔ `user_id`), or a wire name kept for existing
  clients and marked deprecated.
- A `TODO` with an owner, ticket, or condition that is not yet met.

**Ownership:**

- A false comment whose only role is to justify a construct that another hunter audits. The construct is the defect,
  and its owner reports it:
  - `// IMPORTANT: do not remove` over code that nothing uses → boundary-hunter for an unused export;
    other unused code is no hunter's.
  - a zero-value contract → invariant-hunter; a swallowed error → exception-hunter.
  - an alias's migration comment → type-hunter.
  - intentional complexity → simplicity-hunter.
- A vague or generic name → boundary-hunter's Generic Boundary Names (packages), or not a finding.
- Naming convention drift → slop-hunter's Style Drift.
- Stuttering → no hunter.

**Evidence bar:** the Claim, quoted, and Contradicted At, the line or lines that contradict it. For `expired`, the
repository fact (the `go.mod` line, the lockfile version, the date). In diff mode, the change that made the text
untrue.

**Action:**

- `stale` / `false` → correct the text, or delete it when the code says it.
- `expired` → the stated condition is met; confirm the defect is gone, then remove the workaround and its comment.
  Otherwise update the condition. A version past the one named shows the condition fired, not that removal is safe.
- `name` → rename at all call sites.

When the text states the intended behavior and the code is wrong, the Action says "code or text is wrong; the author
decides" and names the callers that rely on the text.

### Within-skill routing

One site, one finding. The first matching rule wins:

1. Text (comment, doc, or name) is present and contradicted by the code or by the repository → Misleading Comments
   and Names, unless the text states only an invariant on a value (`// ids is never empty`) and the contradiction is
   a path that passes or admits that value → rule 6 (`enforceable`). Text that says a check enforces the invariant
   ("already validated") stays here.
2. The code is shaped by a dependency, platform, or protocol → Unexplained Workarounds.
3. A literal or branch encodes a domain decision → Unexplained Business Rules. A technique's own constants (the Earth
   radius in haversine, a CRC polynomial) are not domain decisions; a domain parameter inside a technique (the rate in
   a compound-interest formula) is.
4. The code implements a nameable technique → Non-Obvious Algorithms (its own constants are part of this row).
5. A literal that fixes the unit of a parameter or a return whose name does not state it (`metres / 1852`) → rule 6,
   with the literal's line as Established At and the unit in the name as the Action. Any other literal is not covered
   here.
6. Caller-facing behavior not in the name or signature, or an invariant stated only in a comment that the code could
   enforce → Undocumented Contracts.

## Test-code scope

**Test files are excluded from findings in every category.** Test paths are listed in each language reference. The
exclusion is **by path**: a production helper under `tests/` is not audited.

Literals in tests are expected values, which test-hunter wants hand-written; noise in tests is slop-hunter's.
Executable docs — Python doctests under `--doctest-modules`, Go `Example` functions — are tests and test-hunter's. A
docstring example that no runner executes is production text, and a stale one is a Misleading Comments and Names
finding.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is.** The shared definitions apply: Critical is exploitable now, causes data
loss, or breaks behavior on production paths; High is a defect with likely user-visible, security, or reliability
impact; Medium is correctness or maintainability risk without imminent impact; Low is hygiene. **The ceiling is
High:** a missing or false text breaks nothing by itself, so no finding here is Critical. Applied to documentation:

- **High** — a demonstrated victim: a reader already acted on the gap or the false text, and the result is wrong.
  Three forms count: a caller in the repository that ignores or contradicts an undocumented contract; one that relies
  on a misleading comment or name; a cited path that passes a value an `enforceable` comment forbids (a literal, an
  unfiltered branch). Name the wrong result. When the caller's defect falls in another hunter's category,
  cross-reference that hunter.
- **Medium** — any of:
  - misleading text on code that has callers or changes often, with no demonstrated victim.
  - a missing why on a business rule, workaround, or algorithm in critical code.
  - an undocumented contract on an export of a Library unit.
- **Low** — everything else: a missing why in code that is not critical, an unidentified domain question where the
  auditor cannot tell whether a domain reader would pause (also in critical code), an `enforceable` contract whose cited
  path only admits a violating value (the comment already informs the reader).

**Impact — how much the change is worth:** callers and importers of the symbol, how often the file changes
(`git log --since=12.months --oneline -- <file> | wc -l`), and whether the code is critical. Breadth is evidence,
never the derivation.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

## Audit Workflow

### Phase 1: Gain Context

**Diff mode** reads `references/diff-mode.md` before step 1. It records deleted source paths, makes a deletions-only
diff an exception to the empty-scope stops, and holds the Phase 3 diff reading.

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
   result. If the resolved surface exceeds the context budget, report the file count and ask to narrow. Narrowing is
   the only known recovery: on a 13 600-line Go scope, a whole-codebase run found about half the sites of a run scoped
   to one directory, and splitting the reading over agents did not recover them. With nobody to ask, do one of two
   things and say which in Scope: read alone as far as the budget allows and record what is left as `not read: <n>
   files — context budget`, or split the reading over sub-agents and record the split as `Read split: <n> agents by
   <directory|file list> — merged by this session`. A report with neither line claims that one reader read every file.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section. On a dirty tree, line numbers match no
   commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent: on a mixed scope it stays whole, so every hunter in a
   party audits the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from file extensions alone: the manifest's, or in codebase mode those of
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the language scans still
   search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**: without a reference there is no doc-comment form, no eligibility rule, no
   scan set. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming each
   extension.

3. **Load language references.** For every detected language, read `references/doc-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/doc-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus the
   test-path exclusion** to that language's files. These subsets are then immutable. Record in Scope: raw manifest
   count, each per-language eligible subset, exclusions with the test paths listed, and
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

   The lists are `$GO_FILES`, `$PY_FILES`, and `$TS_FILES`, with no test/production split: test paths are not
   eligible. A language with no eligible file gets no `<lang>.txt`.

   If **nothing** eligible remains and no deleted source path does: write `Audit completed: 0 findings — no eligible
   source in scope` and stop before scanning. With deleted source paths left, it is a deletions-only run
   (`references/diff-mode.md`).

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Files outside it are *read* as **context**: callers (for contract evidence), interface implementations,
   repository docs, and git history. Diff and path scope narrow the manifest, never the context reading.

5. **Record the documentation context** per language, in Scope:
   - **Doc style:** Go godoc; Python, ruff's `[tool.ruff.lint.pydocstyle] convention`, else the dominant style in
     nearby docstrings (Google, NumPy, Sphinx); TypeScript, TSDoc or JSDoc.
   - **Library units:** classify each unit in scope as `library` or `closed`, with its evidence (Terms; the
     reference's Public symbol section). Scope lists each library unit and each unit that holds an Undocumented
     Contracts candidate.
   - **History:** `full`; `shallow` when `git rev-parse --is-shallow-repository` prints `true`; `unavailable` when no
     git history can be read.

### Phase 2: Scan for Candidates

For each language that has a `<run>/<lang>.txt`, run the loaded reference's Phase 2 scan block over that list: restore
`GO_FILES=$(cat <run>/go.txt)` (`PY_FILES` from `python.txt`, `TS_FILES` from `typescript.txt`) in the same call.
Diff mode scans the working tree of the manifest files; the changed-line restriction (`references/diff-mode.md`)
decides which hits can be reported.

Done when every scan in each loaded reference's Phase 2 block has run and every hit is listed as a candidate.

### Phase 3: Read

Reading finds what no scan matches; each find becomes a candidate with its line.

**What to read.** Diff mode: each changed hunk with its enclosing declaration, the nominations, and the removed-symbol
search, all in `references/diff-mode.md`. Path mode: every file in the `<lang>.txt` lists, in full. Codebase mode:
every file in `<run>/read.txt`, in full. Build it first, per language, with the reference's `--type`, `$EXCLUDE`, and
generated-code marker, and drop the Phase 2 hits outside it:

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1
rg --files --type <t> $EXCLUDE -- . | while read -r f; do rg -q -m1 '<marker>' "$f" || echo "$f"; done >> <run>/read.txt
```

If the list does not fit the context budget, stop under Phase 1's rule: report the file count and ask to narrow.
When the user says to continue, read files with critical code first, then files with a scan hit,
then the rest, and record the files left as `not read: <n> files — context budget` in Scope.

**Reading checklist**, applied to every read file (diff mode: to every hunk and nomination):

1. Each comment and doc comment against its code; each claim in it against the repository; each invariant it states
   against the checks that enforce it.
2. Each function, boolean, and unit-suffixed name against its body and assignments; each mapping site (a struct tag,
   an alias, a column name) for one concept under two names.
3. Each literal and comparison in a condition or calculation, single digits included.
4. Each formula, bit operation, regular expression, and comparator.
5. Each delay, retry, platform branch, and order of calls on a third-party object.
6. Each function's effects, hidden inputs, returned resources, errors, boundary handling, and units.
7. The loaded reference's Blind spots.

Done when every file on the list (diff mode: every hunk and nomination) is read with items 1–7 applied, or counted in
`not read`; diff mode's removed-symbol search is done; and every scan hit and reading result is listed as a
candidate with its line.

### Phase 4: Route Each Candidate

For each candidate, at its site:

1. Apply the general Not-a-finding list and the category's **Not a finding:** line. In diff mode, apply the
   changed-line restriction (`references/diff-mode.md`).
2. Apply the within-skill routing. If it moved the candidate, apply the routed category's **Not a finding:** line too.
3. Cross-reference a candidate that an **Ownership:** note or the comment ownership rule gives to another hunter; it
   is not scored.

Done when every candidate is kept in one category, dropped under a named Not-a-finding case, or handed off.

### Phase 5: Why-search, Evidence, and Severity

Run the **Why-search** on each surviving candidate in a missing-why category. It looks for what the candidate lacks:
the source (Unexplained Business Rules), the technique's name or reference (Non-Obvious
Algorithms), the cause, or for kind `defect` the removal condition (Unexplained Workarounds). Steps run in order and
stop at the first that supplies it. The Why-Search cell has one entry per step that ran, under the step's label, with
what it found:

1. `names` — the site: names of the enclosing function, variables, constants, and types.
2. `comment` — the line, the enclosing block, the declaration's doc comment, the package or module doc.
3. `link` — an issue, ADR, or spec that a comment points to. A file in the repository is read. An external link
   counts as present and is not fetched.
4. `repo docs` — repository docs that name the enclosing symbol, never the value (`6` matches every list and date):
   `rg -n -w '<symbol>' -g '*.md' -- .`.
5. `history`, unless the history state is `unavailable`. On a shallow clone it runs on the history that exists, and
   the cell says `shallow`. `git log -L` reads the file at a commit, not the working tree: on a dirty file a
   working-tree line number names another line, or exceeds the file and aborts (`fatal: file a.go has only 5 lines`).
   So map the candidate's key line (the literal, the condition, the call) first:
   - `git blame --porcelain -L <n>,<n> -- <file>`. The first output line is `<hash> <orig-line> <line> …`; the
     `filename` line gives the path in that commit.
   - A zero hash, or blame failing with `fatal: no such path '<file>' in HEAD` (an untracked file) →
     `history: skipped — line not committed`. The line's text is new, or an uncommitted edit of an older line
     (`h > 6` edited to `6 < h` gives a zero hash). The cell means "not searched", never "no reason": an edited line's
     reason may sit in an older commit. The Action's question goes to the author, who holds the edit.
   - Any other blame failure → `history: errored — <message>`.
   - Otherwise `git log -L <orig-line>,<orig-line>:<path> <hash> -s --format='%h %s%n%b' -n 20`. Read until a
     message supplies what the candidate lacks. When all 20 state none, record
     `history: 20 commits, no reason (cap)`. The window is 20 because later commits on the same line (a reformat, a
     rename) push the commit that states the reason out of a small window.

For each missing-why category, the step that supplied what the candidate lacks decides:

- Step 1 or 2 (a name, or a comment on the line, the block, the declaration's doc, or the package doc): not a
  finding.
- Step 3 (a pointer in a comment): not a finding. The comment cites its source, which is what the comment standard
  asks.
- Step 4 (a repository doc that names the enclosing symbol): not a finding. A reason that a search of the repository
  finds needs no comment (the comment standard), and a search for the symbol finds this doc. The doc must state it for
  this code; a doc that only names the symbol clears nothing.
- Step 5 only (a commit message): still a finding. A search of the files does not reach it, and a squash or a later
  rewrite of the line buries it. The Action quotes it with its hash. Severity is unchanged.
- No step: the Action is the question to the author (Core Principle 2).
- Suggested comments carry constraints, not task history ("changed to", "on client feedback"). History in a comment
  is slop-hunter's Hedging and Narration.

Then clear each category's evidence bar from What to Hunt, and assign **Severity and Impact** to every finding.
Nothing is held back; `Audit completed: N findings` counts every reported finding.

Done when every missing-why finding's Why-Search cell has an entry for each of steps 1–5, with the history entry in one
of the states above; every other finding meets its category's evidence bar; every finding has Severity and Impact; and
every dropped candidate names the step, Not-a-finding case, or evidence bar that dropped it, or the hunter it was handed
to.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-doc-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. a party-mode orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

**Delegated to tools.** Each loaded reference's `## Delegated to tools` section names, one line per tool, the classes
of defect this hunter leaves to that tool. Do not hunt those classes, run the tool, or read its configuration. Check
only whether the tool is set up, with one `rg` per tool: its configuration file, its section in a shared file
(`[tool.ruff]` in `pyproject.toml`), or its name in a CI workflow. End `## Recommendations (Priority Order)` with the
bold label `**Tooling.**`, the sentence `This hunter does not check the classes below.`, and every line of the loaded
sections, each prefixed `not found, adopt:` or `found, confirm these are on:`. A line that states a condition prints
only when the condition holds. The block prints on every run, also when every tool is set up: a tool can be set up
with a rule off, and naming the rule costs one line.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line` with the exact text and fills every evidence cell
  `references/report-format.md` defines from code read, never inferred.
- **One site, one finding.** The within-skill routing decides the category; a candidate another hunter owns is
  cross-referenced to it, never scored.
