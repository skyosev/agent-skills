---
name: simplicity-hunter
description: Audit Go, Python, or TypeScript code for over-engineering — duplication, reinvented primitives, unnecessary abstractions, dead code paths, over-parameterized APIs, mixed concerns, complex control flow, coexisting generations. Defaults to the codebase.
disable-model-invocation: true
---

# Simplicity Hunter

Audit code for **structural complexity** — duplicated logic, abstractions that don't earn their keep, control flow
deeper than needed, mixed concerns. Goal: **the simplest code that preserves intended behavior** — default to delete.

**Not covered (owned by other hunters):** class and interface *design* (→ solid-hunter; Go interface pollution stays
here); invariant enforcement (→ invariant-hunter); type structure (→ type-hunter); module boundaries and exports
(→ boundary-hunter); documentation (→ doc-hunter); security (→ security-hunter); test quality and test-code
duplication (→ test-hunter); cosmetic style and commented-out code, in every mode (→ slop-hunter); broader
non-idiomatic patterns (→ smell-hunter); performance — over-engineered code is here, under-optimized code is
perf-hunter's; error-handling policy — what to catch, how to convert and propagate (→ exception-hunter; duplicated
error-handling code stays here). A finding that doesn't answer "is this simpler than it could be?" belongs
elsewhere. Where ownership is *contested* rather than simply elsewhere, that category's **Ownership:** note in What to
Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `perf-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Duplication | Repeated logic across production functions, modules, packages | Eliminate from an existing source of truth; shared helper is the fallback |
| Reinvented Primitives | Hand-rolled equivalent of a stdlib / present-dependency primitive | Replace — only if all six gates hold |
| Unnecessary Abstractions | Wrapper, manager, registry, factory serving one call site | Inline |
| Dead Code Paths | Unreachable branch, zero-call helper, stale flag, guard already guaranteed | Delete, with liveness evidence |
| Over-Parameterized APIs | 4+ params, boolean flags, constant arguments, mostly-unused config objects | Split by use case |
| Mixed Concerns | One body fetches AND transforms AND persists/renders | Extract named helpers; parent becomes coordinator |
| Complex Control Flow | 3+ nesting levels, 4+ branch chains, nested ternaries, dense expressions | Guard clauses, early returns, lookup tables, named steps |
| Coexisting Generations | Two or more **live**, structurally different solutions to one concern | Name the survivor, give a retirement plan |

## Terms

- **Live seam** — an abstraction a production consumer receives from outside (handwritten wiring or a container, the
  mechanism is irrelevant), or that a second implementation or a test double uses. An interface only ever constructed
  or returned by the code that implements it, never held as another unit's parameter or field, has **no live seam**.
- **Nomination** — scan or linter output, a name, a count, or dependency coexistence. It selects code to open; it is
  never evidence. A finding cites what the opened code shows.
- **Stratum** — one generation of a solution to a concern (Coexisting Generations). Live when at least one production
  site uses it.
- **Liveness channels** — ways code is reached besides a direct call: reflection, DI registration, registries,
  entrypoint configuration, plus the hooks each language reference lists. A method that any interface in the
  repository names is live. A finding on code that a listed hook could reach is withdrawn unless that hook was checked.
- **Essential complexity** — branches that map one-to-one to the cases of a named external rule: one per charter-party
  clause type, tax regime, or protocol state. The code is exactly as complex as the rule. What the code adds on top —
  the same mapping written twice, or an ad-hoc encoding of it — is accidental and stays reportable.
- **Published unit** — boundary-hunter's definition, copied here: **any evidence of documented import use opens the
  set** (mixed → open → withdrawn). **Closed** (judged in tree): Go — a `main` package; an `internal/` path; a package
  of a module that contains a `main` package **and** whose repository documents no import use (no `go get <module
  path>` line or quoted `"<module path>…"` import path in a README or doc, no `doc.go` on a non-main package, no
  `examples/` directory). TypeScript — a workspace package with `private: true`, or a unit not reachable from any
  `package.json` `exports` / `main`. Python — a `_`-prefixed or `internal` package; a distribution with a
  `Private :: Do Not Upload` classifier; a repository whose entry is a web or framework application (`manage.py`,
  `wsgi.py`, `asgi.py`). **Open** (withdrawn): Go — a module with no `main` package and a public module path, or any
  documented import use; TypeScript — reachable from `exports` / `main` without `private: true`; Python — a package a
  `[project]` / `[tool.poetry]` distribution declares with a public import path and none of the closing signals.
  `__main__.py` and `[project.scripts]` are **not** application signals — libraries ship CLIs that way. No release
  workflows or tags are read. The question is asked per exported symbol, from the unit that exports it. On an open
  unit, the claims that need every consumer are **withdrawn**, with one Scope `Limitation` line per unit: a dead public
  name (Dead Code Paths), an interface with no live seam (Unnecessary Abstractions, Interface Pollution), and a
  parameter every caller passes the same value (Over-Parameterized APIs).

## Not a finding on these grounds alone

Remove or centralize safety or operational behavior only when every call site keeps an equivalent guarantee.
Distinguish a duplicated **mechanism** (often a finding) from required duplicated **enforcement** (not a finding).

- **Error handling** — keep the propagation strategy and distinct error paths. Structural duplication *within* error
  handling remains reportable.
- **Logging, telemetry, metrics, retries, timeouts, circuit breakers** — presence is operational intent, not
  boilerplate; keep it. Duplicated configuration, competing policies at different layers, obsolete wrapper layers, and
  dead policy branches *are* findings.
- **Complexity documented as intentional** — in repository instructions or comments (e.g. duplication for
  performance): not a finding while the rationale holds; reportable only if the documented reason is demonstrably
  stale.
- **Essential complexity** (Terms) — keep it, documented or not; only its accidental part is a finding.
- **Accessibility affordances** — never a removal target.
- **Clarity over brevity** — denser, cleverer, more compressed code that is harder to read is not a simplification.
  Prefer the clearer shape even at more lines.
- **Over-simplification guard** — keep names that carry domain meaning, and keep distinct responsibilities in
  distinct units, when inlining or merging.

## What to Hunt

### Duplication

Repeated logic across production functions, modules, or packages. **Ownership:** two *type declarations* of one
shape, a union beside an `as const` array, or a manual type beside a schema are type-hunter's Duplicated Type
Declarations; repeated logic and repeated runtime values stay here. Test code: see Test-code scope.

**Action — elimination first, evidence over counting:**

1. **Eliminate before extracting.** Duplication derivable from an existing source of truth — a constant, an existing
   map, a generated value — is the finding. A new shared helper is the fallback, not the first move. When two
   implementations do the same thing, keep one and delete the other; a shared helper that keeps both paths needs
   genuinely different consumers.
2. Where elimination does not apply, a consolidation finding must show the shared unit **reduces total code and total
   concepts** and represents **one stable behavior**, not two behaviors that merely look alike today.
   The Action writes the shared unit's signature. Each of these is evidence of two behaviors; the row note answers it,
   or the finding is dropped:
   - a callback, or a flag whose values run different steps (a side parameter that selects the mirror image of one
     test is one behavior);
   - a message, hint or tolerance that differs per caller;
   - a caller that must transform its input (reverse or mirror a row, map a list) before the call.

   When two findings change one function, judge their Actions together: one must not undo the other.
3. **Occurrence count is supporting evidence, not a gate.** Report it; decide on the evidence.
4. **Complete the set.** A consolidation names one home. The Action lists every copy, found by the quantity that the
   copies judge (the field and the comparison, Phase 3 step 2), not by a constant's name or value. Each copy is in the
   Action or has a reason to stay. A scope-out that holds for whole rules ("different rules") is checked clause by
   clause: two rules can share a clause, and that clause is its own candidate. When the home already holds a helper
   for that clause, the Action says whether the new unit uses it, and if not, why not.

**Signals:** two near-identical bodies differing only in a value or branch; multiple implementations of the same
algorithm; identical non-trivial error-handling or validation *logic* repeated across handlers.

**Not a finding:** trust-boundary input validation repeated across sibling handlers — each boundary may need
independent enforcement. It *is* a finding when the validation logic itself is duplicated and could be a single shared
schema still invoked at every boundary.

**Scope the claim to the shared region.** Cite what is actually identical after normalization — often one assembly
block, not the whole function. Per-copy validation, policy, and value resolution stay outside the extraction, and the
description must not inflate "one shared block" into "the whole feature lands twice."

**Drifted copies that diverge behaviorally are two findings, not one.** When drift has produced a live behavioral
difference, report the defect as its own finding — standalone, fixed by the minimal edit, dependent on no refactor —
and judge the consolidation separately against the *post-fix* copies. A live divergence is evidence the copies drifted;
it is **not** license to collapse them: if what remains after the one-line fix is copies that genuinely differ in
per-copy policy, the collapse may not clear the reporting gate at all.

**Probe a writer and its checker.** When code that writes a value and code that checks the stored form enforce one
rule (a builder and the validator of what it builds), and the comparison finds a difference between them (the order
of steps, a tolerance, how a message prints a value), write one probe in the run directory and run it. The probe
states the relation that it tests:

- **The checker accepts what the writer produces.** A checker can also test context that the writer cannot see,
  such as the parent or the siblings. Put the value in a context that passes those tests, and name the check that
  rejects it. A rejection by a check that needs that context is design. Any other rejection is a defect finding
  under the rule above.
- **Both reject the same inputs, or report the same error first.** This relation holds only where code, a comment or
  a test says that the two agree. Where nothing says so, a difference only nominates. Where a test pins the
  difference, it is design.

Take the inputs from the difference: the values on each side of a tolerance edge, and the input types that the two
message paths print differently. A probe changes no source file. When no runner that the project has can run it,
write "probe blocked" in the row note. The language reference names the runner.

**Readers of a tolerated value.** When an Action changes how a value is tolerated or normalized (a snap, an epsilon,
rounding), search the readers of the value by operand (Phase 3 step 2). The Action names the value that is stored and
each reader found, with the form that the reader expects: a band or an exact value. Do not write an Action that makes
one check tolerate a value that a reader compares exactly. Keep the minimal edit to the drifted copy. When a reader
still disagrees with what a check accepts, write the counterexample in the row note, and mark that part "remedy
unresolved".

### Reinvented Primitives

Project code reimplementing a stdlib (or already-present dependency) primitive with equivalent semantics, when the
toolchain already supports it. Primitive lists and gates live in the language reference.

**Gates — all must hold:**

1. **Toolchain support, cited exactly** — per primitive (not a blanket language-version gate); show the project meets
   it (version source in the language reference).
2. **Dependency policy** — stdlib or an already-present dependency only.
3. **Exact semantic parity**, including designed-in differences of the primitive.
4. **Edge-case parity** — empty input, nil/null/None/zero default, no-match path, ordering, error path.
5. **Mutability and ownership parity** — must not change who may mutate what.
6. **Demonstrable net reduction in concepts**, not merely in lines.

A version differing on any gate is not a Reinvented Primitives finding. **Action:** replace with the primitive and call
it directly.

### Unnecessary Abstractions

Wrappers, managers, registries, factories serving a single call site or adding no logic, and speculative generality:
layers built for callers that do not exist.

**Signals:** pass-through delegates; single-resource "managers"; one-type factories; single-implementation abstractions
with no live seam (see Terms). Measure a wrapper's value by what it adds, not by what it hides.

**Ownership — existence, not width.** An abstraction with a live seam (see Terms) is solid-hunter's Fat Interfaces
question, not a finding here. This category owns the interface with **no live seam** — never received from outside,
one implementation, no double: should it exist at all? A *type parameter* that never varies is type-hunter's Generics
That Never Vary; this category owns value-level abstractions. An owned type or interface that keeps an external type
out of an inward unit's signature is boundary-hunter's External Type Leaks remedy; once injected it is a live seam.
What stays here is a wrapper the unit constructs itself, with no external type kept out. smell-hunter's Class Abuse
asks whether a class should be a function; this category asks whether the layer should exist at all. When the layer
should go, the finding is here; when only its form changes, it is Class Abuse.

**Action:** Inline.

### Dead Code Paths

Unreachable branches, unused internal helpers, stale feature flags, guards already guaranteed by preceding logic or
by the type.

**Signals:** impossible branches given types/call sites; internal helpers with zero call sites after liveness checks;
flags always on/off, shown by evidence in the repository — a constant, a config file, or a default nothing overrides
(a flag whose value lives outside the repository, such as in a remote flag service, is withdrawn); `nil` / `None` /
`undefined` checks already guaranteed (see Guard ownership); default/`else` arms already ruled out.

**Ownership:** commented-out code is slop-hunter's Trivially Dead Code, unconditionally — text is not a code path and
has no liveness question. This category owns *live* code that cannot execute or is never called: unused functions and
constants. Exported dead symbols → boundary-hunter's Dead Exports. The language reference's Dead code section splits
unused bindings, parameters, and fields, and names the exported dead symbols that stay here.

**Guard ownership with invariant-hunter.** A null / nil / None check the *type already rules out* is here — delete the
guard. A check compensating for an optional type whose value is always present is invariant-hunter's Defensive Access
in Non-Boundary Code — tighten the type; the guard falls away afterwards.

**Not a finding:** exhaustiveness arms — `default: assertNever(x)`, `case _: assert_never(x)`,
`default: panic("unreachable")` never execute by design. They are compile-time or convention guards; keep them.

**Liveness is mandatory.** Check runtime reachability beyond call sites through the liveness channels (see Terms).

**History is conditional.** Consult history when the code looks deliberate, unusual, or externally reachable.
Chesterton's Fence applies where there is a fence; history can be shallow, absent, or misleading.

**Evidence:** cite channels *relevant to this symbol* and what they showed — not a recited checklist.

**Action:** Delete. An uncertain dead-code finding is withdrawn, with one Scope `Limitation` line.

### Over-Parameterized APIs

Functions with many parameters, boolean flags, or option/config objects creating a combinatorial explosion.
**Ownership:** boolean-parameter findings live here. solid-hunter claims only a boolean whose choice is **dispatched
at two or more sites on an open set** — a two-member discriminant meeting the full Rigid Extension Points bar. A
boolean dispatched at one site is here however likely it looks to grow.

**Signals:**

- **4+ parameters** (Go's `ctx context.Context` does not count) — nomination only. A finding requires judgment on
  cohesion, call-site readability, and actual branching — not the count alone.
- Booleans creating branching burden, ambiguous call sites, or reachable combinations readers must reason about.
  Caller count is not a complexity measure.
- Option/config objects with mostly unused fields; catch-all kwargs / options pass-throughs.
- **Constant arguments** — a parameter every caller passes with the same value (nil, zero, or one constant). The
  finding cites every call site.

**Action:** Split by use case, or reduce to parameters callers actually use. A flag that must stay needs sharp naming
and, when transitional, a removal plan.

### Mixed Concerns

Single functions handling multiple unrelated responsibilities. **Ownership:** a *type or package* serving two actors
with independent reasons to change is solid-hunter's Responsibility Sprawl; this category owns the function body.

**Signals:** fetch AND transform AND persist/render in one body; long functions (50+ lines) with distinct sections;
methods or module bodies spanning abstraction levels.

**Not a finding:** a dispatcher/coordinator function whose sole job is to route on a discriminant and delegate each
case — that is its single responsibility. It is a finding only when case arms also contain substantial inline business
logic. A long function with one concern: length only nominates.

**Action:** Extract each concern into a named helper; the parent becomes a coordinator.

### Complex Control Flow

Deep nesting, nested conditionals/ternaries, long branch chains, convoluted loops. Async/promise signals → TypeScript
reference.

**Signals:** 3+ nesting levels; `if`/`else if`/`elif` chains with 4+ branches; loop bodies with two or more
conditionals; nested ternaries or conditional expressions; dense expressions — a `reduce` with a spread accumulator, a
long chain of inline lambdas, plus the forms the language reference adds.

**Action:** Flatten with guard clauses and early returns; prefer switch/map lookups or explicit branches; extract
complex loop bodies; split dense expressions into named intermediate steps.

### Coexisting Generations

Two or more **live**, structurally different solutions to the same concern, left by an unfinished migration (lava
layers). The remedy is a migration, not a deletion (see Within-skill precedence).

**Ownership:** one concern spread across many files is smell-hunter's Shotgun Surgery; many generations on one concern
are here. An external type used inward with no wrapper is boundary-hunter's External Type Leaks; two wrappers of
different vintage are here.

**Evidence required.** Names and dependency coexistence *nominate only*. A finding needs: identical responsibility
(not merely overlapping domain); intended replacement (migration, deprecation naming a successor, changelog/commit
trail); overlapping supported use cases; survivor chosen on **capability and project intent**. Recency
(`git log -1 --format=%as -- <path>`) and recent call-site choice may nominate; they do not decide.

**Severity:** default **Medium**; raise to **High** when strata *behave* differently, not merely when they coexist.

**Action:** Report strata, name the survivor, recommend a retirement plan (which call sites move; which stratum deletes
once empty). The survivor is already written: the remedy moves call sites onto it and adds no new generation.

### Within-skill precedence

One finding per site. The reported finding's row note (report format) names the other reading in one clause.

- **Go interface with no live seam** → Interface Pollution (simplicity-go.md), never also Unnecessary Abstractions.
- **A function that mixes concerns and nests 3+ levels** → Mixed Concerns; name the nesting in its row note.
  Extracting the concerns usually flattens it.
- **A function with one call site whose name states one concern of its caller** stays. It is the result of Mixed
  Concerns, not an Unnecessary Abstraction.
- **Strata:** zero live sites → Dead Code Paths; near-identical bodies → Duplication; otherwise Coexisting
  Generations.
- **Flags:** always on or always off → Dead Code Paths; both branches live with no removal plan → Coexisting
  Generations.

## Test-code scope

Test files are **in scope** for every category **except Duplication**. Test-code duplication belongs to test-hunter.
Test paths are listed in each language reference's Phase 3 block.

## Severity and Impact

Every finding carries **both**; they answer different questions.

**Severity — behavioral risk if left as-is:**

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths. Structural complexity is
  rarely Critical on its own: only when a duplicated or dead path actively produces wrong production behavior.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk. A dead branch that never executes is Low however ugly it is.

**Impact — how much the change is worth:** defect exposure, cognitive burden, affected surface. Contextual; never
derived from nesting depth, occurrence count, or pattern alone. That same never-executed dead branch, sitting in a hot
and frequently-read file, is High impact.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the reporting gate but touches a small, rarely hit surface

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
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the language scans still
   search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**: without a reference there is no eligibility rule, no scan set, no
   Duplication exclude. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming
   each extension.

3. **Load language references.** For every detected language, read `references/simplicity-<lang>.md` from the
   directory this SKILL.md was read from (e.g. `references/simplicity-go.md`). **Fail closed:** if a required
   reference cannot be read, **stop and report**.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules to that
   language's files. These subsets are then immutable. Record in Scope: raw manifest count, each per-language eligible
   count, exclusions, and `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, documentation / Markdown-only inputs, and generated files —
   identified by each reference's in-file marker and by its generated-file globs. A handwritten file named like a
   generated one is dropped too, a declared limitation. TypeScript has no standard marker, so there the globs are the
   only rule. Codebase mode runs no marker filter before scanning; Phase 5 checks the marker on every anchor file.

   Write each subset to `<run>/<lang>.txt` (`go.txt`, `python.txt`, `typescript.txt`). Codebase mode: the single line
   `.`. Diff and path mode: the eligible files, one per line — `comm -12 <(rg --files --type <t> $EXCLUDE | sort)
   <(printf '%s\n' $SCOPE | sort)` with the loaded reference's `--type` and `$EXCLUDE`, minus files carrying a
   generated-code marker (`| while read -r f; do rg -q -m1 '<marker>' "$f" || echo "$f"; done`, the marker regex built
   from the reference's eligibility section); the reference's generated-file globs are the same scan approximation a
   codebase run uses. Filter before scanning: `rg` applies `--type` and `--glob` only while walking a folder and
   searches every file named on its command line. Each scan call restores its list first — `GO_FILES=$(cat
   <run>/go.txt)` (`PY_FILES`, `TS_FILES`) — and the reference blocks pass it as `rg -H … -- $GO_FILES`: given one file,
   `rg` prints no file name unless `-H` is set.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop before
   scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Related files may still be *read* as **context** (call sites, canonical helpers, competing strata).

5. **Read repository instructions** when present (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, project convention docs)
   for stated design decisions, intentional complexity, toolchain conventions. Note helpers, utilities, and
   intentional duplication for performance before scanning.

### Phase 2: Scan for Complexity Signals

For each loaded language reference, nominate candidates on that language's eligible list (Phase 1 step 4) from the
three sources its Phase 2 block names:

1. **Project linter.** When the project invokes a linter itself — package scripts, `Makefile`, pre-commit, CI; a config
   file alone is not adoption — run that same command without its fix option. Keep the findings that anchor in the
   eligible list, for the rules the reference maps to categories. Use only the rules the project enables; never install
   a tool. Record one Scope outcome per linter: **ran**, **skipped** (not adopted, or not installed), **errored**.
   An inline suppression of a complexity rule nominates its function: open it, and read the comment on the marker
   line and on the line above. When that comment documents a deferral, record it in Scope (Complexity documented as
   intentional). Record a command's result only for the files that it checks: a gate that diffs against a base ref
   checks only the changed files, and a clone detector checks only clones above its size floor. Neither counts as a
   seed search.
2. **Toolchain modernizer**, where the reference names one.
3. **Regex scans.** Approximate: they miss and over-match, so they only nominate.

A scan with many hits runs first with `-c` (hits per file); open the files with the most hits first. Group hits by
enclosing function: one function is one candidate. Judge each finding under the rules of its own file's language —
including language-only categories the reference appends. Done when every source has run or has its Scope outcome, and
every hit belongs to a candidate.

### Phase 3: Scan for Duplication

1. **Seeds.** Build the Duplication list with the reference's Phase 3 block: the eligible list minus test paths (see
   Test-code scope).
2. **Search.** For each non-trivial function in a seed file, pick one or two distinctive lines — a literal, a call
   chain, an error message, an unusual condition — and search them project-wide:
   `rg -F -n '<line>' --type <t> $DUP_EXCLUDE .`. Hits outside the target scope are context; the finding anchors at
   the in-scope copy.

   A short predicate is often written again with another receiver, destructured, or split over two lines. A search
   for one copy's line then finds only that copy. Also search each comparison with its receiver removed, as a fixed
   string: `rg -F -n '<field> <operator> <operand>' --type <t> $DUP_EXCLUDE .` (for example
   `'rightHeightRatio === 1'`, or `'shortHeightRatio -'` for a difference).

   **Declared copies.** A comment that names another function as the source or the mirror of its code ("Mirrors
   placeLeftTallShed", "as in renderToSVG") nominates the pair. Open the named function, follow its calls to the code
   that the comment describes, and compare as in step 3. The language reference's Phase 3 block holds the scan.
3. **Compare.** Open every hit's enclosing body and compare after normalizing names and values. Cite only the region
   that matches (see Duplication: Scope the claim to the shared region).

A clone check in the project's lint run (Phase 2) nominates too. Record
`Duplication coverage: {searched} of {total} seed functions searched` in Scope; Duplication findings claim only the
searched seeds. Done when every seed function has been searched and every hit's body compared, or the coverage line
records where the search stopped.

### Phase 4: Scan for Coexisting Generations — codebase and path scope only

**Scope gate.** This phase needs a view of the whole repository:

- **Codebase scope** — run it fully.
- **Path scope** — run it. Findings anchor inside the target path; the rest of the repository is read as *context*.
- **Diff scope** — skip it and write the `Coexisting generations: skipped` Scope line; the skip has no diff-only
  substitute.

For each loaded language, run that reference's Phase 4 block. These scans nominate candidates only; apply the
Coexisting Generations evidence bar, then Within-skill precedence, before raising a finding. Done when every nominated
stratum has a project-wide liveness verdict and is a candidate or dismissed.

### Phase 5: Evaluate Each Finding

**Reporting gate.** Report only when the proposed change demonstrably reduces total concepts, duplicated behavior, or
control-flow burden enough to outweigh new indirection and behavioral risk.

For each candidate: apply the general Not a finding list and the category's own **Not a finding:** line first; clear the
category's evidence bar in What to Hunt and the reporting gate; choose the simplest elimination. Re-open every
signature a remedy cites: each parameter, arity, and adjacency it relies on must exist as written.

**Remedy check (every Action that adds, splits, moves or inlines code).** An executor builds the Action as written,
so the Action is a spec. Write each clause below that applies to the Action; write "none" when the search finds
nothing:

1. **Reuses** (the Action adds a type, helper or constant): the existing unit of the same shape (the same fields, the
   same clauses, or the same value for the same quantity), and whether the Action uses it in place of a new one. If
   not, why not: the same shape can carry a different meaning. Duplication rule 1 applies to the remedy too.
2. **Shared locals** (an extraction): each local that the old body computes once and that two or more new units
   read, and how each new unit gets it: as a parameter, from one helper beside the new units, or computed again,
   with the reason.
3. **Call sites** (the Action changes a signature): each call site, tests included, and each import that the Action
   adds (`from.ts → to.ts`).
4. **Lost callers** (a merge, a move or an inline): each unit whose call sites or importers fall to one or zero. At
   zero, apply the liveness channels and the published-unit rule (Terms) before the Action deletes the unit or
   removes its `export`. At one, Within-skill precedence decides whether the unit stays.

**Generated anchors.** A candidate whose anchor file carries the reference's generated-code marker is reported once, at
the generator input (config, template, or schema) when that input is in the target scope, and dropped otherwise.

**Behavior parity (every remedy).** The remedy keeps every output, every error (its code, the values its message
names, and which error wins), every side effect and its order, and the blocking and concurrency behavior. The Action
ends with one parity clause. "Order stays", "output unchanged" or "traced" alone is not a parity clause:

- **Error order:** each caller's checks in order, now and after. A shared unit cannot take checks from both sides of a
  check that stays in the caller. In a loop, say whether each check runs per item or over all items.
- **Outputs:** the test, snapshot set or probe that shows parity, and the inputs it covers. Inputs that one caller
  rejects can still come from another caller.
- **Contracts:** every direct caller, tests included, defines the contract. One caller's precondition does not make a
  branch dead. An Action that deletes a test which pins the behavior changes the contract, and says so.

Mark the clause **shown** when the audit's own evidence shows the claim before and after, and name the inputs it
covers: a trace of each caller's checks, or a probe that runs the old and the new form on the same inputs. A test
that was read shows what it covers, and the current code run as it is shows the current behavior; neither shows
that the remedy keeps it. Mark the clause **to verify** when the claim waits for a check that must run on the built
remedy, and name the check. When the audit can neither show parity nor name such a check, the Action says what
changes, or the finding is dropped. An Action rewritten after review gets this check again.

**Platform-guarantee rule (flag only with evidence).** When recommending removal because "the platform / framework /
middleware already guarantees it," name the owning layer and cite the proof that it keeps that parity. Without that
evidence, drop the finding — this class over-fires.

Assign **Severity and Impact** to every finding. `Audit completed: N findings` counts every reported finding.

Done when every candidate is a reported finding, dropped, withdrawn with its `Limitation` line, or handed off to its
owning hunter.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in `docs/` (or the repository root when there is no `docs/`). If the caller specifies
an output path or return mode (e.g. a party-mode orchestrator), it overrides this default.

**Merging a split run.** When one audit is split across agents (by folder or by language) and merged into one report,
copy each finding's Action cell and row note, or derive them again from the code. An edit may remove repetition, but
not a condition, a site or evidence. When two runs report one site, keep the claim whose every site clears the
evidence bar; a wider claim does not win because it covers more. In Scope, keep each command result with the run that
it covers, and add the coverage counts without counting a seed twice.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line`, and its row note holds the exact code.
  A comment, commit or defect record used as evidence is quoted in the row note, and is cited only when its subject
  is the code that the finding cites. A claim about a whole set ("every other pair", "no caller", "all copies") lists
  the members it was checked on, or is removed. A count of call sites or tests to change lists each one, with its
  reason.
- **Public API shape may change.** Report a simplification that changes an exported API like any other finding,
  whatever its backward-compatibility cost.
