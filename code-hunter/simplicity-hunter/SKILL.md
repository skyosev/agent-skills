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
| Duplication | Repeated logic across production functions, modules, packages | Eliminate from an existing source of truth; shared helper is the fallback | Duplication *within test code* → test-hunter |
| Reinvented Primitives | Hand-rolled equivalent of a stdlib / present-dependency primitive | Replace — only if all six gates hold | Non-idiomatic patterns generally → smell-hunter |
| Unnecessary Abstractions | Wrapper, manager, registry, factory serving one call site | Inline | Class/interface *design* → solid-hunter (Go interface pollution stays here) |
| Dead Code Paths | Unreachable branch, zero-call helper, stale flag, commented-out alternate | Delete, with liveness evidence | Exported dead symbols → boundary-hunter |
| Over-Parameterized APIs | 4+ params, boolean flags, mostly-unused config objects | Split by use case | Booleans selecting behaviors that will grow variants → solid-hunter |
| Mixed Concerns | One body fetches AND transforms AND persists/renders | Extract named helpers; parent becomes coordinator | — |
| Complex Control Flow | 3+ nesting levels, 4+ branch chains, nested ternaries | Guard clauses, early returns, lookup tables | — |
| Coexisting Generations | Two or more **live**, structurally different solutions to one concern | Name the survivor, give a retirement plan | One concern spread across many files → smell-hunter (shotgun surgery) |

Hunter names throughout are unsuffixed end-state names. Until consolidation completes, live skills are
language-suffixed (`test-hunter-go`, `test-hunter-py`, `test-hunter-ts`, and so on).

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

5. **Inline the trivial.** Inline pass-through wrappers, single-use helpers, indirection layers adding no logic. Measure
   value by what the wrapper adds, not by what it hides.

6. **Separate concerns, don't mix them.** A function that fetches data AND transforms it AND logs errors has three
   reasons to change. Split into focused helpers with intent-revealing names.

7. **Flatten, don't nest.** Deep nesting (3+ levels) signals mixed concerns or missing early returns. Use guard clauses
   and early returns to keep the main path at low indentation.

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
  uses them. A seam with **no** consumer *is* a finding.
- **Accessibility affordances** — never a removal target.
- **Clarity over brevity** — denser, cleverer, more compressed code that is harder to read is not a simplification.
  Prefer the clearer shape even at more lines.
- **Over-simplification guard** — do not recommend inlining that erases a name carrying domain meaning, or merging
  distinct responsibilities into one unit.

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Dead Code Paths").

### Duplication

Repeated logic across production functions, modules, or packages. (Duplication *within test code* — copied setup,
repeated assertion blocks — is test-hunter's finding; do not flag it here.)

**Action — elimination first, evidence over counting:**

1. **Eliminate before extracting.** Duplication derivable from an existing source of truth — a constant, an existing
   map, a generated value — is the finding. A new shared helper is the fallback, not the first move.
2. Where elimination does not apply, a consolidation finding must show the shared unit **reduces total code and total
   concepts** and represents **one stable behavior**, not two behaviors that merely look alike today.
3. **Occurrence count is supporting evidence, not a gate.** Report it; do not decide on it.

**Signals:** two near-identical bodies differing only in a value or branch; multiple implementations of the same
algorithm; identical non-trivial error-handling or validation *logic* repeated across handlers (see Not-a-finding).

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

A version differing on any gate is not a simplification. **Action:** replace with the primitive; do not wrap further.

### Unnecessary Abstractions

Wrappers, managers, registries, factories serving a single call site or adding no logic.

**Signals:** pass-through delegates; single-resource "managers"; one-type factories; single-implementation abstractions
with no test double and no plan for more (unless a live test seam / DI boundary — see Not-a-finding).

**Action:** Inline. If it exists for testability, note that and keep if justified.

### Dead Code Paths

Unreachable branches, unused internal helpers, stale feature flags, leftover or commented-out alternate
implementations.

**Liveness is mandatory.** Check runtime reachability beyond call sites — reflection, DI registration, registries,
entrypoint configuration, and language-specific channels in the reference. Exported dead symbols → boundary-hunter.

**History is conditional.** Consult history when the code looks deliberate, unusual, or externally reachable.
Chesterton's Fence applies where there is a fence; history can be shallow, absent, or misleading.

**Evidence:** cite channels *relevant to this symbol* and what they showed — not a recited checklist.

**Signals:** impossible branches given types/call sites; internal helpers with zero call sites after liveness checks;
flags always on/off; commented-out alternate implementations; default/`else` arms already ruled out.

**Action:** Delete. If uncertain, flag with evidence of zero usage via the channels checked.

### Over-Parameterized APIs

Functions with many parameters, boolean flags, or option/config objects creating a combinatorial explosion.
**Ownership:** boolean-parameter findings live here. solid-hunter claims only booleans selecting between behaviors that
will grow variants (OCP setup); smell-hunter does not flag them.

**Signals:**

- **4+ parameters** — nomination only. A finding requires judgment on cohesion, call-site readability, and actual
  branching — not the count alone.
- Booleans creating branching burden, ambiguous call sites, or reachable combinations readers must reason about.
  Count nominates; demonstrated complexity decides. Caller count is not a complexity measure.
- Option/config objects with mostly unused fields; catch-all kwargs / options pass-throughs.

**Action:** Split by use case, or reduce to parameters callers actually use.

### Mixed Concerns

Single functions or types handling multiple unrelated responsibilities.

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

### Coexisting Generations (Lava Layers)

Two or more **live**, structurally different solutions to the same concern, left by an unfinished migration.

**Every stratum must be live.** Zero call sites → Dead Code Paths. Near-identical bodies → Duplication. This category
covers only designs that genuinely differ *and* are all in use — the case whose remedy is a migration, not a deletion.

**Evidence required.** Names and dependency coexistence *nominate only*. A finding needs: identical responsibility
(not merely overlapping domain); intended replacement (migration, deprecation naming a successor, changelog/commit
trail); overlapping supported use cases; survivor chosen on **capability and project intent**. Recency and recent
call-site choice may nominate; they do not decide.

**Action:** Report strata, name the survivor, recommend a retirement plan (which call sites move; which stratum deletes
once empty). Never rewrite — the surviving generation is already written.

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

Recommendations group by Severity (Critical → High → Medium → Low), then by Impact within each group.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve the raw manifest.** The prompt may specify scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project (default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line). Read run metadata (base SHA, surface kind, counts) from `scope-meta.txt` when present. Use the
   manifest verbatim and do not re-resolve. The resolution below applies to standalone runs only.

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
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop. If the resolved surface exceeds what can be
   read within the context budget, report the file count and ask to narrow or chunk.

   The raw manifest is **immutable** and language-independent. Do not redefine it on a mixed scope — silently
   narrowing would break the party guarantee that all hunters audit the same surface. Mechanical-churn detection
   (formatting, lint autofix, mass rename) requires diff content, not a file list — **optional inspection, never a
   gate**.

   **Whitespace in paths is unsupported.** The newline-delimited manifest plus `-- $SCOPE` shell expansion word-splits
   on spaces; paths containing whitespace are a declared limitation.

2. **Detect languages** from manifest extensions alone:
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   `.js` / `.jsx` / `.mjs` / `.cjs` are **out of scope**. Unsupported extensions (`.rs`, `.java`, …) stay in the
   manifest and are audited under shared categories only — record
   `no reference for .<ext> — language-specific categories skipped` in Scope.

3. **Load language references.** For every detected language, read `references/simplicity-<lang>.md` from the
   directory this SKILL.md was read from (e.g. `references/simplicity-go.md`). **Fail closed:** if a required
   reference cannot be read, **stop and report**; do not continue with shared categories only.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules to that
   language's files. These subsets are then immutable. Record in Scope: raw manifest count, each per-language eligible
   subset, exclusions, and `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, documentation / Markdown-only inputs, and generated files
   identified by each reference's authoritative in-file marker — **never** by filename guessing. Scan globs in
   references are approximations for scanning convenience; eligibility for reporting uses the marker rule.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop before
   scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Related files may still be *read* as **context** (call sites, canonical helpers, competing strata).

5. **Read repository instructions** when present (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, project convention docs)
   for stated design decisions, intentional complexity, toolchain conventions. Note helpers, utilities, and
   intentional duplication for performance before scanning.

### Phase 2: Scan for Complexity Signals

For each loaded language reference, run its Phase 2 scan block against that language's eligible subset (`SCOPE=.` in
codebase mode). Pass an explicit path (`-- $SCOPE` or `.`) to **every** `rg` invocation. Judge each finding under the
rules of its own file's language — including language-only categories the reference appends.

### Phase 3: Scan for Duplication

1. Identify repeated patterns across files using targeted searches. Apply each reference's **Duplication exclude**
   profile so test paths are omitted (see Test-code scope).
2. Look for multiple implementations of the same logic with minor variations.
3. Prefer elimination from an existing source of truth over proposing a new shared helper.

### Phase 4: Scan for Coexisting Generations — codebase and path scope only

**Scope gate.** This phase needs a view of the whole repository:

- **Codebase scope** — run it fully.
- **Path scope** — run it. Findings anchor inside the target path; the rest of the repository is read as *context*.
- **Diff scope** — **skip it.** Record the skip in Scope — do not omit it silently, and do not substitute a narrower
  diff-only heuristic.

For each loaded language, run that reference's Phase 4 block. These scans nominate candidates only; apply the shared
evidence bar above before raising a finding. A stratum with zero live sites is a Dead Code Paths finding, not
Coexisting Generations. Near-identical bodies reclassify to Duplication.

### Phase 5: Evaluate Each Finding

**Reporting gate.** Report only when the proposed change demonstrably reduces total concepts, duplicated behavior, or
control-flow burden enough to outweigh new indirection and behavioral risk.

For each signal: apply Not-a-finding first; clear the reporting gate; choose the simplest elimination. Coexisting
Generations: all strata live and designs differ; survivor = capability/intent. Reinvented primitives: all six gates
with a cited toolchain requirement.

**Platform-guarantee rule (flag only with evidence).** When recommending removal because "the platform / framework /
middleware already guarantees it," name the owning layer, show removal preserves every output, error, side effect and
ordering, and cite the proof. Without that evidence, do not raise the finding — this class over-fires.

Assign **Severity and Impact** to every finding (see the section above — both are required, and they diverge).

Nothing is held back; `Audit completed: N findings` counts every reported finding.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies
an output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas. Language-only categories
appended by a language reference (today: Interface Pollution, Channel & Goroutine Overuse) use the table schemas
supplied in that reference.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "The scan shows two matches — I'll cite both file:line" | Two `rg` hits are a nomination. Open both bodies before writing a finding; scan output is not evidence. |
| "This helper has no call sites" | Grep is not liveness. Reflection, DI, registries, entrypoint config, and the language reference's channels come first. |
| "Five parameters, that's a finding" | Count nominates; demonstrated branching or call-site confusion decides. Caller count is not a complexity measure. |
| "This validation is repeated across four handlers" | Repetition at trust boundaries is enforcement, not duplication. A finding only if the *logic* could be one shared schema still invoked at every boundary. |
| "The framework already guarantees this, so the check is redundant" | Name the owning layer and cite the proof, or drop it. This class over-fires. |
| "These two names look like old and new — that's a lava layer" | Names and dependency coexistence nominate only. No identical responsibility plus intended-replacement trail, no finding. |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "This is denser and fewer lines" | Fewer lines that read worse is not a simplification. Concepts, not lines. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do shared categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it
  would contain zero items — no empty tables, placeholder subsections, or negative statements like "no dead
  exports", "none found", "no issues". Execution status is exempt: the "Audit completed: N findings" line, and the
  coexisting-generations skip line when the scope is a diff, are always present in the Scope section even at zero
  findings.
- **Scope: structural complexity only.** A finding that doesn't answer "is this simpler than it could be?" belongs
  elsewhere. Boundaries: invariant-hunter, type-hunter, boundary-hunter, solid-hunter
  (class/interface *design*; Go interface *pollution* stays here), doc-hunter, security-hunter, test-hunter (test
  quality and test-code duplication), slop-hunter (cosmetic style; when it runs jointly it may own commented-out text
  — standalone, commented-out alternate implementations remain Dead Code Paths here), smell-hunter (broader
  non-idiomatic patterns; reinvented-primitive *replacement* stays here when all six gates hold).
- **Coexisting generations: adjacent categories.** Shotgun surgery → smell-hunter; many generations on one concern →
  here. External with no wrapper → boundary-hunter Missing Abstraction; two wrappers of different vintage → here.
  Always-on/off flag → Dead Code Paths; both branches live with no removal plan → Coexisting Generations.
- **Retire, don't rewrite.** Move call sites onto an existing stratum and delete the others. Never recommend a third
  generation.
- **Evidence required.** Every finding cites `file:line` (see language reference for path form); per-category evidence
  bars are in What to Hunt.
- **Preserve behavior.** Never alter what the code does — only how it's structured. Public API shape may change; do not
  defer findings on backward-compatibility grounds, and do not default to follow-up merely because an exported API
  changes.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity.
