---
name: simplicity-hunter
description: |
  Use when reviewing Go, Python, or TypeScript code for over-engineering, reducing
  complexity after prototyping, enforcing reuse over addition, simplifying before a
  refactor, or auditing a codebase after a library or framework migration.

  Covers duplication, reinvented primitives, avoidable abstractions, dead logic paths,
  over-parameterized APIs, deep nesting, mixed concerns, and coexisting abstraction
  generations left behind by unfinished migrations.
disable-model-invocation: true
---

# Simplicity Hunter

Audit code for **structural complexity** — duplicated logic, abstractions that don't earn their keep, control flow
deeper than needed, mixed concerns. Goal: **the simplest code that preserves intended behavior.**

Supports Go, Python, TypeScript via per-language reference files.

## When to Use

- Reviewing new code for over-engineering or unnecessary indirection
- Reducing complexity after initial prototyping
- Enforcing reuse over addition before merging
- Preparing code for long-term maintainability
- Deduplicating logic across production modules or packages (duplication *within test code* belongs to test-hunter)
- Auditing a codebase after a library or framework migration for unfinished strata

## Quick Reference

Full rules per category in **What to Hunt**; every finding must also clear Not-a-finding and the Phase 5 reporting
gate.

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Duplication | Repeated logic across production functions, modules, packages | Eliminate from an existing source of truth; shared helper is the fallback | Duplication *within test code* → test-hunter; duplicated type declarations → type-hunter |
| Reinvented Primitives | Hand-rolled equivalent of a stdlib / present-dependency primitive | Replace — only if all six gates hold | Non-idiomatic patterns generally → smell-hunter |
| Unnecessary Abstractions | Wrapper, manager, registry, factory serving one call site | Inline | Class/interface *design* → solid-hunter (Go interface pollution stays here); a type parameter that never varies → type-hunter |
| Dead Code Paths | Unreachable branch, zero-call helper, stale flag, guard already guaranteed | Delete, with liveness evidence | Commented-out code → slop-hunter; exported dead symbols → boundary-hunter (Dead Exports); guard on a loose type → invariant-hunter |
| Over-Parameterized APIs | 4+ params, boolean flags, mostly-unused config objects | Split by use case | A boolean whose choice is dispatched at two or more sites on an open set → solid-hunter (Rigid Extension Points) |
| Mixed Concerns | One body fetches AND transforms AND persists/renders | Extract named helpers; parent becomes coordinator | A *type or package* serving two actors → solid-hunter (Responsibility Sprawl) |
| Complex Control Flow | 3+ nesting levels, 4+ branch chains, nested ternaries | Guard clauses, early returns, lookup tables | — |
| Coexisting Generations | Two or more **live**, structurally different solutions to one concern | Name the survivor, give a retirement plan | One concern spread across many files → smell-hunter (Shotgun Surgery) |

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`test-hunter-go`, `doc-hunter-py`, `security-hunter-ts`): route to the one matching the finding's language.

## Core Principles

1. **Default to delete.** The best simplification is removal. Code deletable without changing behavior: delete it.
   Replaceable by an existing helper: replace it.

2. **One canonical path.** When two implementations do the same thing, pick one and remove the other. Avoid "shared
   helper + keep both paths" unless genuinely different consumers require it. When the paths are *near-identical*, the
   remedy is deletion; when they are *different designs that are both in use*, the finding is the unfinished migration
   itself, and the remedy is a retirement plan naming the surviving stratum.

3. **Abstractions must earn their place.** Reject new wrappers, managers, factories unless they reduce total complexity
   through reuse. An abstraction serving one call site is indirection, not simplification.

4. **Flags are complexity multipliers.** Each boolean parameter can double the logic paths. Prefer one linear flow; an
   unavoidable flag requires sharp naming and, when transitional, a removal plan.

5. **Inline the trivial.** Inline pass-through wrappers and indirection layers that add no logic. Measure value by what
   the wrapper adds, not by what it hides. A single-use helper that names a distinct concern is not trivial (see Mixed
   Concerns, Over-simplification guard).

6. **Separate concerns, don't mix them.** A function that fetches data AND transforms it AND logs errors has three
   reasons to change. Split into focused helpers with intent-revealing names.

7. **Flatten, don't nest.** Deep nesting (3+ levels) signals mixed concerns or missing early returns. Use guard clauses
   and early returns to keep the main path at low indentation.

## Terms

- **Live seam** — an abstraction a production consumer receives from outside (handwritten wiring or a container, the
  mechanism is irrelevant), or that a second implementation or a test double uses. An interface only ever constructed
  or returned by the code that implements it, never held as another unit's parameter or field, has **no live seam**.
  No live seam raises an existence question (here); a live seam raises a width question (solid-hunter's Fat
  Interfaces).
- **Nomination** — scan output, a name, a count, or dependency coexistence. It selects code to open; it is never
  evidence. A finding cites what the opened code shows.
- **Stratum** — one generation of a solution to a concern (Coexisting Generations). Live when at least one production
  site uses it.
- **Liveness channels** — ways code is reached besides a direct call: reflection, DI registration, registries,
  entrypoint configuration, plus the channels each language reference adds.
- **Target scope and context** — findings anchor in the manifest (target scope); call sites, canonical helpers, and
  competing strata outside it are read as context.

## Not a finding on these grounds alone

Do not recommend removing or centralizing safety or operational behavior unless every call site retains an equivalent
guarantee. Distinguish a duplicated **mechanism** (often a finding) from required duplicated **enforcement** (not a
finding).

Entries below are conditionals, not category exemptions — each states what does **not** justify a finding and, where a
corresponding structural finding exists, what would:

- **Trust-boundary input validation repeated across sibling handlers** — repetition alone is not the finding; each
  boundary may need independent enforcement. *Is* a finding when the validation logic itself is duplicated and could be
  a single shared schema still invoked at every boundary.
- **Error handling** — do not recommend altering the propagation strategy or collapsing distinct error paths.
  Structural duplication *within* error handling remains reportable.
- **Logging, telemetry, metrics, retries, timeouts, circuit breakers** — presence is operational intent, not
  boilerplate; do not recommend removal. Duplicated configuration, competing policies at different layers, obsolete
  wrapper layers, and dead policy branches *are* findings.
- **Duplication documented as intentional for performance** — not a finding while the rationale holds; reportable only
  if the documented reason is demonstrably stale.
- **Abstractions serving as test seams or DI boundaries** — not indirection while a test double or injector actually
  uses them. An abstraction with **no live seam** (see Terms) *is* a finding.
- **Accessibility affordances** — never a removal target.
- **Clarity over brevity** — denser, cleverer, more compressed code that is harder to read is not a simplification.
  Prefer the clearer shape even at more lines.
- **Over-simplification guard** — do not recommend inlining that erases a name carrying domain meaning, or merging
  distinct responsibilities into one unit.
- **Exhaustiveness arms** — `default: assertNever(x)`, `case _: assert_never(x)`, `default: panic("unreachable")`
  never execute by design. They are compile-time or convention guards, not Dead Code Paths; never a removal target.

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Dead Code Paths").

### Duplication

Repeated logic across production functions, modules, or packages. (Duplication *within test code* — copied setup,
repeated assertion blocks — is test-hunter's finding; do not flag it here. Two *type declarations* of one shape, a
union beside an `as const` array, or a manual type beside a schema are type-hunter's Duplicated Type Declarations;
repeated logic and repeated runtime values stay here.)

**Action — elimination first, evidence over counting:**

1. **Eliminate before extracting.** Duplication derivable from an existing source of truth — a constant, an existing
   map, a generated value — is the finding. A new shared helper is the fallback, not the first move.
2. Where elimination does not apply, a consolidation finding must show the shared unit **reduces total code and total
   concepts** and represents **one stable behavior**, not two behaviors that merely look alike today.
3. **Occurrence count is supporting evidence, not a gate.** Report it; do not decide on it.

**Signals:** two near-identical bodies differing only in a value or branch; multiple implementations of the same
algorithm; identical non-trivial error-handling or validation *logic* repeated across handlers (see Not-a-finding).

**Scope the claim to the shared region.** Cite what is actually identical after normalization — often one assembly
block, not the whole function. Per-copy validation, policy, and value resolution stay outside the extraction, and the
description must not inflate "one shared block" into "the whole feature lands twice."

**Drifted copies that diverge behaviorally are two findings, not one.** When drift has produced a live behavioral
difference, report the defect as its own finding — standalone, fixed by the minimal edit, dependent on no refactor —
and judge the consolidation separately against the *post-fix* copies. A live divergence is evidence the copies drifted;
it is **not** license to collapse them: if what remains after the one-line fix is copies that genuinely differ in
per-copy policy, the collapse may not clear the reporting gate at all.

### Reinvented Primitives

Project code reimplementing a stdlib (or already-present dependency) primitive with equivalent semantics, when the
toolchain already supports it. Primitive lists and gates live in the language reference.

**Gates — all must hold:**

1. **Toolchain support, cited exactly** — per primitive (not a blanket language-version gate); show the project meets
   it (version source in the language reference).
2. **Dependency policy** — stdlib or already-present dependency only. Never propose adding one.
3. **Exact semantic parity**, including designed-in differences of the primitive.
4. **Edge-case parity** — empty input, nil/null/None/zero default, no-match path, ordering, error path.
5. **Mutability and ownership parity** — must not change who may mutate what.
6. **Demonstrable net reduction in concepts**, not merely in lines.

A version differing on any gate is not a simplification, and not a finding in any hunter. **Action:** replace with the
primitive; do not wrap further.

### Unnecessary Abstractions

Wrappers, managers, registries, factories serving a single call site or adding no logic.

**Signals:** pass-through delegates; single-resource "managers"; one-type factories; single-implementation abstractions
with no live seam (see Terms).

**Ownership — existence, not width.** An interface a production consumer receives from outside (handwritten wiring or
a container, the mechanism is irrelevant), or that a second implementation or a test double uses, is solid-hunter's
Fat Interfaces question, not an existence question. This category owns the interface with **no live seam** (see
Terms) — never received from outside, one implementation, no double: should it exist at all? A *type parameter* that
never varies is type-hunter's Generics That Never Vary; this category owns value-level abstractions. An owned type or
interface that keeps an external type out of an inward unit's signature is boundary-hunter's External Type Leaks
remedy; once injected it is the live seam above. What stays here is a wrapper the unit constructs itself, with no
external type kept out.

**Action:** Inline.

### Dead Code Paths

Unreachable branches, unused internal helpers, stale feature flags, guards already guaranteed by preceding logic or
by the type.

**Ownership:** commented-out code is slop-hunter's Trivially Dead Code, unconditionally — text is not a code path and
has no liveness question. This category owns *live* code that cannot execute or is never called. Unused functions
and constants stay here; in Go, `_ = x` on a non-error binding, unused parameters, and unused struct fields are
slop-hunter's (Python and TypeScript unused parameters are a recorded gap no hunter audits); `_ = f()` on an error is
invariant-hunter's Unchecked Errors.

**Guard ownership with invariant-hunter.** A null / nil / None check the *type already rules out* is here — delete the
guard. A check compensating for an optional type whose value is always present is invariant-hunter's Defensive Access
in Non-Boundary Code — tighten the type; the guard falls away afterwards. Go has no non-optional pointer type and
invariant-hunter's Defensive Access does not apply to Go: a Go nil guard the preceding logic already guarantees is
here. Exhaustiveness arms are never dead code (see Not-a-finding).

**Liveness is mandatory.** Check runtime reachability beyond call sites through the liveness channels (see Terms).
Exported dead symbols → boundary-hunter's Dead Exports; a Python public name with no importers anywhere stays here. A
TypeScript `export` in a non-entry file that its unit's entry does not re-export, with zero importers anywhere, is here
(Dead Code Paths) — the Python rule's analogue.

**History is conditional.** Consult history when the code looks deliberate, unusual, or externally reachable.
Chesterton's Fence applies where there is a fence; history can be shallow, absent, or misleading.

**Evidence:** cite channels *relevant to this symbol* and what they showed — not a recited checklist.

**Signals:** impossible branches given types/call sites; internal helpers with zero call sites after liveness checks;
flags always on/off; `nil` / `None` / `undefined` checks already guaranteed by preceding logic or by the type (outside
Go, a check on a type that is still optional → invariant-hunter); default/`else` arms already ruled out — except
exhaustiveness arms, which stay.

**Action:** Delete. If uncertain, flag with evidence of zero usage via the channels checked.

### Over-Parameterized APIs

Functions with many parameters, boolean flags, or option/config objects creating a combinatorial explosion.
**Ownership:** boolean-parameter findings live here. solid-hunter claims only a boolean whose choice is **dispatched
at two or more sites on an open set** — a two-member discriminant meeting the full Rigid Extension Points bar. A
boolean dispatched at one site is here however likely it looks to grow. smell-hunter does not flag them.

**Signals:**

- **4+ parameters** — nomination only. A finding requires judgment on cohesion, call-site readability, and actual
  branching — not the count alone.
- Booleans creating branching burden, ambiguous call sites, or reachable combinations readers must reason about.
  Caller count is not a complexity measure.
- Option/config objects with mostly unused fields; catch-all kwargs / options pass-throughs.

**Action:** Split by use case, or reduce to parameters callers actually use.

### Mixed Concerns

Single functions handling multiple unrelated responsibilities. **Ownership:** a *type or package* serving two actors
with independent reasons to change is solid-hunter's Responsibility Sprawl; this category owns the function body.

**Signals:** fetch AND transform AND persist/render in one body; long functions (50+ lines) with distinct sections;
methods or module bodies spanning abstraction levels.

**Do not flag: dispatcher/coordinator functions** whose sole job is to route on a discriminant and delegate each case.
That IS their single responsibility. Flag only when case arms also contain substantial inline business logic.

**Action:** Extract each concern into a named helper; the parent becomes a coordinator.

### Complex Control Flow

Deep nesting, nested conditionals/ternaries, long branch chains, convoluted loops. Async/promise signals → TypeScript
reference.

**Signals:** 3+ nesting levels; `if`/`else if`/`elif` chains with 4+ branches; loop bodies with embedded conditionals;
nested ternaries or conditional expressions.

**Action:** Flatten with guard clauses and early returns; prefer switch/map lookups or explicit branches; extract
complex loop bodies.

### Coexisting Generations

Two or more **live**, structurally different solutions to the same concern, left by an unfinished migration (lava
layers).

**Every stratum must be live.** This category covers only designs that genuinely differ *and* are all in use — the
case whose remedy is a migration, not a deletion (see Within-skill precedence).

**Ownership:** one concern spread across many files is smell-hunter's Shotgun Surgery; many generations on one concern
are here. An external type used inward with no wrapper is boundary-hunter's External Type Leaks; two wrappers of
different vintage are here.

**Evidence required.** Names and dependency coexistence *nominate only*. A finding needs: identical responsibility
(not merely overlapping domain); intended replacement (migration, deprecation naming a successor, changelog/commit
trail); overlapping supported use cases; survivor chosen on **capability and project intent**. Recency and recent
call-site choice may nominate; they do not decide.

**Action:** Report strata, name the survivor, recommend a retirement plan (which call sites move; which stratum deletes
once empty). Never rewrite — the surviving generation is already written — and never recommend a third generation.

### Within-skill precedence

One finding per site. The Evidence cell of the reported finding names the other reading in one clause.

- **Go interface with no live seam** → Interface Pollution (simplicity-go.md), never also Unnecessary Abstractions.
- **A function that mixes concerns and nests 3+ levels** → Mixed Concerns; name the nesting in its Description.
  Extracting the concerns usually flattens it.
- **Strata:** zero live sites → Dead Code Paths; near-identical bodies → Duplication; otherwise Coexisting
  Generations.
- **Flags:** always on or always off → Dead Code Paths; both branches live with no removal plan → Coexisting
  Generations.

## Test-code scope

Test files are **in scope** for every category **except Duplication**. Test-code duplication belongs to test-hunter.
Each language reference's scan profile enforces this: the Duplication scan excludes test paths; other scans do not.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

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

Coexisting Generations default to **Medium** severity; raise to **High** when strata *behave* differently, not merely
when they coexist.

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
   surface kind, counts) from `scope-meta.txt` when present. Use the manifest verbatim; do not re-resolve. The
   resolution above is for standalone runs only.

   **Persist run state.** Shell variables do not survive between tool calls, and `rg … --` with an empty variable
   searches the whole working directory. Create one run directory (`RUN=$(mktemp -d) && echo "$RUN"`) and use the
   printed path literally from then on. Every call starts at the repository root (`cd "$(git rev-parse
   --show-toplevel)"`), because every list holds root-relative paths. Write `$SCOPE` to `<run>/scope.txt` and, in diff mode, `$MB` to `<run>/mb`.
   A later call restores what it uses (`SCOPE=$(cat <run>/scope.txt)`); an empty restore is a STOP, never an empty
   result. If the resolved surface exceeds the context budget, report the file count and ask to narrow or chunk.

   **Record provenance.** Capture `git rev-parse --short HEAD` and whether the working tree is dirty
   (`git status --porcelain -- $SCOPE`); both go in the report's Scope section. On a dirty tree, line numbers match no
   commit — state that findings must be re-located by symbol name.

   The raw manifest is **immutable** and language-independent. Do not redefine it on a mixed scope — silently
   narrowing breaks the party guarantee that all hunters audit the same surface.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion
   word-splits on spaces; whitespace paths are a declared limitation.

2. **Detect languages** from manifest extensions alone:
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   **Supported languages are Go, Python, and TypeScript.** Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs`
   included — is **excluded, not audited**: without a reference there is no eligibility rule, no scan set, no
   Duplication exclude, no evidence form. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming
   each extension.

3. **Load language references.** For every detected language, read `references/simplicity-<lang>.md` from the
   directory this SKILL.md was read from (e.g. `references/simplicity-go.md`). **Fail closed:** if a required
   reference cannot be read, **stop and report**; do not continue with shared categories only.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules to that
   language's files. These subsets are then immutable. Record in Scope: raw manifest count, each per-language eligible
   subset, exclusions, and `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, documentation / Markdown-only inputs, and generated files
   identified by each reference's authoritative in-file marker — **never** by filename guessing. Scan globs in
   references are approximations for scanning convenience; eligibility for reporting uses the marker rule.

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

For each loaded language reference, run its Phase 2 scan block on that language's eligible list — `$GO_FILES`,
`$PY_FILES`, `$TS_FILES`, restored from `<run>/<lang>.txt` (Phase 1 step 4). **Every** `rg` invocation takes that list
after `--`; never `$SCOPE`. Judge each finding under the rules of its own file's language — including language-only
categories the reference appends.

### Phase 3: Scan for Duplication

1. **Seeds.** Build the Duplication list with the reference's Phase 3 block: the eligible list minus test paths (see
   Test-code scope).
2. **Search.** For each non-trivial function in a seed file, pick one or two distinctive lines — a literal, a call
   chain, an error message, an unusual condition — and search them project-wide:
   `rg -F -n '<line>' --type <t> $DUP_EXCLUDE .`. Hits outside the target scope are context; the finding anchors at
   the in-scope copy.
3. **Compare.** Open every hit's enclosing body and compare after normalizing names and values. Cite only the region
   that matches (see Duplication: Scope the claim to the shared region).
4. Prefer elimination from an existing source of truth over proposing a new shared helper.

### Phase 4: Scan for Coexisting Generations — codebase and path scope only

**Scope gate.** This phase needs a view of the whole repository:

- **Codebase scope** — run it fully.
- **Path scope** — run it. Findings anchor inside the target path; the rest of the repository is read as *context*.
- **Diff scope** — **skip it.** Record the skip in Scope — do not omit it silently, and do not substitute a narrower
  diff-only heuristic.

For each loaded language, run that reference's Phase 4 block. These scans nominate candidates only; apply the
Coexisting Generations evidence bar, then Within-skill precedence, before raising a finding.

### Phase 5: Evaluate Each Finding

**Reporting gate.** Report only when the proposed change demonstrably reduces total concepts, duplicated behavior, or
control-flow burden enough to outweigh new indirection and behavioral risk.

For each signal: apply Not-a-finding first; clear the category's evidence bar in What to Hunt and the reporting gate;
choose the simplest elimination.

**Platform-guarantee rule (flag only with evidence).** When recommending removal because "the platform / framework /
middleware already guarantees it," name the owning layer, show removal preserves every output, error, side effect and
ordering, and cite the proof. Without that evidence, do not raise the finding — this class over-fires.

Assign **Severity and Impact** to every finding (see the section above — both are required, and they diverge).

Nothing is held back; `Audit completed: N findings` counts every reported finding.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in `docs/` (or the repository root when there is no `docs/`). If the caller specifies
an output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "The scan shows two matches — I'll cite both file:line" | Two `rg` hits are a nomination. Open both bodies before writing a finding; scan output is not evidence. |
| "This helper has no call sites" | Grep is not liveness. Reflection, DI, registries, entrypoint config, and the language reference's channels come first. |
| "Five parameters, that's a finding" | Count nominates; demonstrated branching or call-site confusion decides. Caller count is not a complexity measure. |
| "This validation is repeated across four handlers" | Repetition at trust boundaries is enforcement, not duplication. A finding only if the *logic* could be one shared schema still invoked at every boundary. |
| "The framework already guarantees this, so the check is redundant" | Name the owning layer and cite the proof, or drop it. This class over-fires. |
| "These two names look like old and new — that's a lava layer" | Names and dependency coexistence nominate only. No identical responsibility plus intended-replacement trail, no finding. |
| "One copy is buggy — collapsing all three fixes it" | The bug is its own finding with its own minimal fix. Judge the collapse against the post-fix copies; it may not clear the gate. |
| "The proposal names the parameters — good enough" | Re-open the cited signature first. Every parameter, arity, and adjacency the remedy relies on must exist as written; a remedy built on a misread signature is a false positive. |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "This is denser and fewer lines" | Fewer lines that read worse is not a simplification. Concepts, not lines. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do shared categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **The report is the template.** `references/report-format.md` fixes the shape: Scope, then one section per
  category with at least one finding, then Recommendations. A category with no findings gets no heading, table,
  or "none found" line.
- **Scope: structural complexity only.** A finding that doesn't answer "is this simpler than it could be?" belongs
  elsewhere. Boundaries: invariant-hunter, type-hunter, boundary-hunter, solid-hunter
  (class/interface *design*; Go interface *pollution* stays here), doc-hunter, security-hunter, test-hunter (test
  quality and test-code duplication), slop-hunter (cosmetic style and commented-out code, in every mode),
  smell-hunter (broader non-idiomatic patterns).
- **Evidence required.** Every finding cites `file:line` (see language reference for path form); per-category evidence
  bars are in What to Hunt.
- **Preserve behavior.** Never alter what the code does — only how it's structured. Public API shape may change; do not
  defer findings on backward-compatibility grounds, and do not default to follow-up merely because an exported API
  changes.
- **Intentional complexity.** Complexity that repository instructions or comments document as intentional is a
  Not-a-finding check, not a report line.
