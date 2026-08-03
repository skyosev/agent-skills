---
name: simplicity-hunter
description: |
  Audit Go, Python, and TypeScript code for unnecessary structural complexity —
  duplication, reinvented primitives, avoidable abstractions, dead logic paths,
  over-parameterized APIs, deep nesting, mixed concerns, and coexisting abstraction
  generations left behind by unfinished migrations. Recommends the simplest shape
  that preserves intended behavior.

  Use when: reviewing code for over-engineering, reducing complexity after
  prototyping, enforcing reuse over addition, simplifying before a refactor, or
  auditing a codebase after a library or framework migration.
disable-model-invocation: true
---

# Simplicity Hunter

Audit code for **structural complexity** — places where logic is duplicated, abstractions don't earn their keep,
control flow is deeper than it needs to be, or concerns are mixed. The goal: **the simplest code that preserves
intended behavior.**

Supports Go, Python, and TypeScript via per-language reference files.

## When to Use

- Reviewing new code for over-engineering or unnecessary indirection
- Reducing complexity after initial prototyping
- Enforcing reuse over addition before merging
- Preparing code for long-term maintainability
- Deduplicating logic across production modules or packages (duplication *within test code* belongs to test-hunter)
- Auditing a codebase after a library or framework migration for unfinished strata

## Core Principles

1. **Default to delete.** The best simplification is removal. If code can be deleted without changing behavior, delete
   it. If it can be replaced by an existing helper, replace it.

2. **One canonical path.** When two implementations do the same thing, pick one and remove the other. Avoid "shared
   helper + keep both paths" unless required by genuinely different consumers. When the two paths are *near-identical*,
   the remedy is deletion; when they are *different designs that are both in use*, the finding is the unfinished
   migration itself, and the remedy is a retirement plan naming the stratum that survives.

3. **Abstractions must earn their place.** Reject new wrappers, managers, and factories unless they reduce total
   complexity through reuse. An abstraction that serves one call site is indirection, not simplification.

4. **Flags are complexity multipliers.** Each boolean parameter can double the logic paths. Prefer one linear flow; if
   a flag is unavoidable, require sharp naming and a removal plan when the flag is transitional.

5. **Inline the trivial.** Pass-through wrappers, single-use helpers, and indirection layers that add no logic should be
   inlined. Measure value by what the wrapper adds, not by what it hides.

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
- **Abstractions serving as test seams or DI boundaries** — not indirection while a test double or injector actually uses
  them. A seam with **no** consumer *is* a finding.
- **Accessibility affordances** — never a removal target.
- **Clarity over brevity** — denser, cleverer, or more compressed code that is harder to read is not a simplification.
  Prefer the clearer shape even when it uses more lines.
- **Over-simplification guard** — do not recommend inlining that erases a name carrying domain meaning, or merging
  distinct responsibilities into one unit.

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Dead Code Paths").

### Duplication

Repeated logic across production functions, modules, or packages. (Duplication *within test code* — copied setup,
repeated assertion blocks — is test-hunter's finding; do not flag it here.)

**Action — elimination first, evidence over counting:**

1. **Eliminate before extracting.** If the duplication can be derived from an existing source of truth — a constant,
   an existing map, a generated value — that is the finding. A new shared helper is the fallback, not the first move.
2. Where elimination does not apply, a consolidation finding must show the shared unit **reduces total code and total
   concepts** and represents **one stable behavior**, not two behaviors that merely look alike today.
3. **Occurrence count is supporting evidence, not a gate.** Report it; do not decide on it.

**Signals:** two near-identical bodies differing only in a value or branch; multiple implementations of the same
algorithm; identical non-trivial error-handling or validation *logic* repeated across handlers (see Not-a-finding).

### Reinvented Primitives

Project code that reimplements a stdlib (or already-present dependency) primitive with equivalent semantics, when the
toolchain already supports it. Primitive lists and gates live in the language reference.

**Gates — all must hold:**

1. **Toolchain support, cited exactly** — per primitive (not a blanket language-version gate); show the project meets
   it (version source in the language reference).
2. **Dependency policy** — stdlib or already-present dependency only. Never propose adding one.
3. **Exact semantic parity**, including designed-in differences of the primitive.
4. **Edge-case parity** — empty input, nil/null/None/zero default, no-match path, ordering, error path.
5. **Mutability and ownership parity** — must not change who may mutate what.
6. **Demonstrable net reduction in concepts**, not merely in lines.

A version that differs on any gate is not a simplification. **Action:** replace with the primitive; do not wrap further.

### Unnecessary Abstractions

Wrappers, managers, registries, or factories that serve a single call site or add no logic.

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

Functions with many parameters, boolean flags, or option/config objects that create a combinatorial explosion.
**Ownership:** boolean-parameter findings live here. solid-hunter claims only booleans that select between behaviors
that will grow variants (OCP setup); smell-hunter does not flag them.

**Signals:**

- **4+ parameters** — nomination only. A finding requires judgment on cohesion, call-site readability, and actual
  branching — not the count alone.
- Booleans that create branching burden, ambiguous call sites, or reachable combinations readers must reason about.
  Count nominates; demonstrated complexity decides. Caller count is not a complexity measure.
- Option/config objects with mostly unused fields; catch-all kwargs / options pass-throughs.

**Action:** Split by use case, or reduce to parameters callers actually use.

### Mixed Concerns

Single functions or types that handle multiple unrelated responsibilities.

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

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve the raw manifest.** The prompt may specify the scope as:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, and untracked
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project (the default when unspecified; set `SCOPE=.`)

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
   for stated design decisions, intentional complexity, and toolchain conventions. Note helpers, utilities, and
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

For each signal: apply Not-a-finding first; clear the reporting gate; choose the simplest elimination. Public API shape
may change; intended runtime behavior must still be preserved — do **not** default to follow-up merely because an
exported/public API changes. Coexisting Generations: all strata live and designs differ; survivor = capability/intent.
Reinvented primitives: all six gates with a cited toolchain requirement.

**Platform-guarantee rule (flag only with evidence).** When recommending removal because "the platform / framework /
middleware already guarantees it," name the owning layer, show removal preserves every output, error, side effect and
ordering, and cite the proof. Without that evidence, do not raise the finding — this class over-fires.

**Severity vs Impact — both required on every finding.**

- **Severity** — behavioral risk if left as-is. A dead branch that never executes is Low severity however ugly it is.
- **Impact** — how much the change is worth (defect exposure, cognitive burden, affected surface). That same dead
  branch in a hot, frequently-read file can be High impact.

Impact bands (contextual; never by nesting depth, occurrence count, or pattern alone): **High** — substantial reduction
on code read/changed often; **Medium** — clear improvement on a moderately reached surface; **Low** — clears the gate
but touches a small, rarely hit surface.

Nothing is held back; `Audit completed: N findings` counts every reported finding. Recommendations group by Severity,
then by Impact within each group.

### Phase 6: Produce Report

## Output Format

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in the project's docs folder (or project root if no docs folder exists). If the caller specifies
an output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Severity levels, used for per-finding labels and the Recommendations grouping:

- **Critical** — exploitable now, causes data loss, or breaks behavior on production paths.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

Language-only categories appended by a reference (today: Interface Pollution, Channel & Goroutine Overuse) use the
table schemas supplied in that reference. Omit any category heading with zero findings.

```md
# Simplicity Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker}
- References loaded: {go, python, typescript as present}
- {no reference for .<ext> — language-specific categories skipped — when applicable}
- {Deleted in diff: {list} — only for diff scope with deletions}
- {Coexisting generations: skipped — requires codebase or path scope — only for diff scope}
- Audit completed: {N} findings

## Findings

### Duplication

| # | Locations | Description | Severity | Impact | Action |
| - | --------- | ----------- | -------- | ------ | ------ |
| 1 | a:10, b:20 | Near-identical validation | Medium | High | Eliminate via existing schema |

### Reinvented Primitives

| # | Location | Hand-rolled | Primitive | Toolchain | Severity | Impact | Action |
| - | -------- | ----------- | --------- | --------- | -------- | ------ | ------ |
| 1 | file:line | loop contains | `slices.Contains` | go 1.21 | Low | Medium | Replace |

### Unnecessary Abstractions

| # | Location | Abstraction | Consumers | Severity | Impact | Action |
| - | -------- | ----------- | --------- | -------- | ------ | ------ |
| 1 | file:line | `ConfigManager` | 1 | Medium | Medium | Inline |

### Dead Code Paths

| # | Location | Code | Evidence | Severity | Impact | Action |
| - | -------- | ---- | -------- | -------- | ------ | ------ |
| 1 | file:line | `legacyHandler()` | 0 call sites; not in registry | Low | High | Delete |

### Over-Parameterized APIs

| # | Location | Function | Params | Severity | Impact | Action |
| - | -------- | -------- | ------ | -------- | ------ | ------ |
| 1 | file:line | `render(...)` | 5 (3 bools) | Medium | Medium | Split by use case |

### Mixed Concerns

| # | Location | Function | Concerns | Severity | Impact | Action |
| - | -------- | -------- | -------- | -------- | ------ | ------ |
| 1 | file:line | `processOrder()` | fetch + transform + log | Medium | Medium | Extract 3 helpers |

### Complex Control Flow

| # | Location | Pattern | Depth | Severity | Impact | Action |
| - | -------- | ------- | ----- | -------- | ------ | ------ |
| 1 | file:line | Nested if/else | 4 | Low | Low | Flatten with guards |

### Coexisting Generations

| # | Concern | Strata | Live evidence | Survivor (capability/intent) | Severity | Impact | Action |
| - | ------- | ------ | ------------- | ---------------------------- | -------- | ------ | ------ |
| 1 | HTTP | a:12 (axios), b:8 (fetch) | migration names axios; 14 vs 3 | axios — intent | Medium | High | Move 3; drop fetch |

## Recommendations (Priority Order)

Group by severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low).
```

(Structural complexity is rarely Critical on its own — Critical only when a duplicated or dead path actively produces
wrong production behavior. Coexisting generations default to **Medium**; raise to **High** when strata *behave*
differently, not merely when they coexist.)

## Operating Constraints

- **No code edits.** This skill produces an audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only categories with findings. Omit a heading, table, or list entirely when it
  would contain zero items — do not include empty tables, placeholder subsections, or negative statements like "no dead
  exports", "none found", or "no issues". Execution status is exempt: the "Audit completed: N findings" line, and the
  coexisting-generations skip line when the scope is a diff, are always present in the Scope section even at zero
  findings.
- **Scope: structural complexity only.** If a finding doesn't answer "is this simpler than it could be?", it belongs
  elsewhere. Boundaries (unsuffixed end-state names): invariant-hunter, type-hunter, boundary-hunter, solid-hunter
  (class/interface *design*; Go interface *pollution* stays here), doc-hunter, security-hunter, test-hunter (test
  quality and test-code duplication), slop-hunter (cosmetic style; when it runs jointly it may own commented-out text
  — standalone, commented-out alternate implementations remain Dead Code Paths here), smell-hunter (broader
  non-idiomatic patterns; reinvented-primitive *replacement* stays here when all six gates hold).
- **Coexisting generations: adjacent categories.** Shotgun surgery → smell-hunter; many generations on one concern →
  here. External with no wrapper → boundary-hunter Missing Abstraction; two wrappers of different vintage → here.
  Always-on/off flag → Dead Code Paths; both branches live with no removal plan → Coexisting Generations.
- **Retire, don't rewrite.** Move call sites onto an existing stratum and delete the others. Never recommend a third
  generation.
- **Evidence required.** Every finding cites `file:line` (see language reference for path form). Coexisting Generations
  cites file:line and a live import/call site for *every* stratum. Dead-code evidence cites only channels relevant to
  that symbol. Reinvented primitives cite the primitive, toolchain requirement, and parity evidence.
- **Reuse over addition.** Prefer existing helpers or deletion over new code.
- **Preserve behavior.** Never alter what the code does — only how it's structured. Public API shape may change; do not
  defer findings on backward-compatibility grounds.
- **Pragmatism.** Not every abstraction is wrong. Flag, assess, and acknowledge intentional complexity.
