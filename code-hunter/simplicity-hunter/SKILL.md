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
non-idiomatic patterns (→ smell-hunter). A finding that doesn't answer "is this simpler than it could be?" belongs
elsewhere. Where ownership is *contested* rather than simply elsewhere, that category's **Ownership:** note in What to
Hunt is authoritative.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`test-hunter-go`, `doc-hunter-py`, `security-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Duplication | Repeated logic across production functions, modules, packages | Eliminate from an existing source of truth; shared helper is the fallback |
| Reinvented Primitives | Hand-rolled equivalent of a stdlib / present-dependency primitive | Replace — only if all six gates hold |
| Unnecessary Abstractions | Wrapper, manager, registry, factory serving one call site | Inline |
| Dead Code Paths | Unreachable branch, zero-call helper, stale flag, guard already guaranteed | Delete, with liveness evidence |
| Over-Parameterized APIs | 4+ params, boolean flags, mostly-unused config objects | Split by use case |
| Mixed Concerns | One body fetches AND transforms AND persists/renders | Extract named helpers; parent becomes coordinator |
| Complex Control Flow | 3+ nesting levels, 4+ branch chains, nested ternaries | Guard clauses, early returns, lookup tables |
| Coexisting Generations | Two or more **live**, structurally different solutions to one concern | Name the survivor, give a retirement plan |

## Terms

- **Live seam** — an abstraction a production consumer receives from outside (handwritten wiring or a container, the
  mechanism is irrelevant), or that a second implementation or a test double uses. An interface only ever constructed
  or returned by the code that implements it, never held as another unit's parameter or field, has **no live seam**.
- **Nomination** — scan output, a name, a count, or dependency coexistence. It selects code to open; it is never
  evidence. A finding cites what the opened code shows.
- **Stratum** — one generation of a solution to a concern (Coexisting Generations). Live when at least one production
  site uses it.
- **Liveness channels** — ways code is reached besides a direct call: reflection, DI registration, registries,
  entrypoint configuration, plus the channels each language reference adds.

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
3. **Occurrence count is supporting evidence, not a gate.** Report it; decide on the evidence.

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

A version differing on any gate is not a simplification, and not a finding in any hunter. **Action:** replace with the
primitive and call it directly.

### Unnecessary Abstractions

Wrappers, managers, registries, factories serving a single call site or adding no logic.

**Signals:** pass-through delegates; single-resource "managers"; one-type factories; single-implementation abstractions
with no live seam (see Terms). Measure a wrapper's value by what it adds, not by what it hides.

**Ownership — existence, not width.** An abstraction with a live seam (see Terms) is solid-hunter's Fat Interfaces
question, not a finding here. This category owns the interface with **no live seam** — never received from outside,
one implementation, no double: should it exist at all? A *type parameter* that never varies is type-hunter's Generics
That Never Vary; this category owns value-level abstractions. An owned type or interface that keeps an external type
out of an inward unit's signature is boundary-hunter's External Type Leaks remedy; once injected it is a live seam.
What stays here is a wrapper the unit constructs itself, with no external type kept out.

**Action:** Inline.

### Dead Code Paths

Unreachable branches, unused internal helpers, stale feature flags, guards already guaranteed by preceding logic or
by the type.

**Signals:** impossible branches given types/call sites; internal helpers with zero call sites after liveness checks;
flags always on/off; `nil` / `None` / `undefined` checks already guaranteed (see Guard ownership); default/`else` arms
already ruled out.

**Ownership:** commented-out code is slop-hunter's Trivially Dead Code, unconditionally — text is not a code path and
has no liveness question. This category owns *live* code that cannot execute or is never called. Unused functions
and constants stay here; in Go, `_ = x` on a non-error binding, unused parameters, and unused struct fields are
slop-hunter's (Python and TypeScript unused parameters are a recorded gap no hunter audits); `_ = f()` on an error is
invariant-hunter's Unchecked Errors. Exported dead symbols → boundary-hunter's Dead Exports; a Python public name with
no importers anywhere stays here. A TypeScript `export` in a non-entry file that its unit's entry does not re-export,
with zero importers anywhere, is here — the Python rule's analogue.

**Guard ownership with invariant-hunter.** A null / nil / None check the *type already rules out* is here — delete the
guard. A check compensating for an optional type whose value is always present is invariant-hunter's Defensive Access
in Non-Boundary Code — tighten the type; the guard falls away afterwards. Go has no non-optional pointer type and
invariant-hunter's Defensive Access does not apply to Go: a Go nil guard the preceding logic already guarantees is
here.

**Not a finding:** exhaustiveness arms — `default: assertNever(x)`, `case _: assert_never(x)`,
`default: panic("unreachable")` never execute by design. They are compile-time or convention guards; keep them.

**Liveness is mandatory.** Check runtime reachability beyond call sites through the liveness channels (see Terms).

**History is conditional.** Consult history when the code looks deliberate, unusual, or externally reachable.
Chesterton's Fence applies where there is a fence; history can be shallow, absent, or misleading.

**Evidence:** cite channels *relevant to this symbol* and what they showed — not a recited checklist.

**Action:** Delete. If uncertain, flag with evidence of zero usage via the channels checked.

### Over-Parameterized APIs

Functions with many parameters, boolean flags, or option/config objects creating a combinatorial explosion.
**Ownership:** boolean-parameter findings live here. solid-hunter claims only a boolean whose choice is **dispatched
at two or more sites on an open set** — a two-member discriminant meeting the full Rigid Extension Points bar. A
boolean dispatched at one site is here however likely it looks to grow.

**Signals:**

- **4+ parameters** — nomination only. A finding requires judgment on cohesion, call-site readability, and actual
  branching — not the count alone.
- Booleans creating branching burden, ambiguous call sites, or reachable combinations readers must reason about.
  Caller count is not a complexity measure.
- Option/config objects with mostly unused fields; catch-all kwargs / options pass-throughs.

**Action:** Split by use case, or reduce to parameters callers actually use. A flag that must stay needs sharp naming
and, when transitional, a removal plan.

### Mixed Concerns

Single functions handling multiple unrelated responsibilities. **Ownership:** a *type or package* serving two actors
with independent reasons to change is solid-hunter's Responsibility Sprawl; this category owns the function body.

**Signals:** fetch AND transform AND persist/render in one body; long functions (50+ lines) with distinct sections;
methods or module bodies spanning abstraction levels.

**Not a finding:** a dispatcher/coordinator function whose sole job is to route on a discriminant and delegate each
case — that is its single responsibility. It is a finding only when case arms also contain substantial inline business
logic.

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

2. **Detect languages** from manifest extensions alone:
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

For each loaded language reference, run its Phase 2 scan block on that language's eligible list (Phase 1 step 4).
Judge each finding under the rules of its own file's language — including language-only categories the reference
appends. Done when every scan in each loaded reference's Phase 2 block has run and every hit is listed as a candidate.

### Phase 3: Scan for Duplication

1. **Seeds.** Build the Duplication list with the reference's Phase 3 block: the eligible list minus test paths (see
   Test-code scope).
2. **Search.** For each non-trivial function in a seed file, pick one or two distinctive lines — a literal, a call
   chain, an error message, an unusual condition — and search them project-wide:
   `rg -F -n '<line>' --type <t> $DUP_EXCLUDE .`. Hits outside the target scope are context; the finding anchors at
   the in-scope copy.
3. **Compare.** Open every hit's enclosing body and compare after normalizing names and values. Cite only the region
   that matches (see Duplication: Scope the claim to the shared region).

Done when every seed function has been searched and every hit's body compared.

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

**Platform-guarantee rule (flag only with evidence).** When recommending removal because "the platform / framework /
middleware already guarantees it," name the owning layer, show removal preserves every output, error, side effect and
ordering, and cite the proof. Without that evidence, drop the finding — this class over-fires.

Assign **Severity and Impact** to every finding. `Audit completed: N findings` counts every reported finding.

Done when every candidate is a reported finding, dropped, or handed off to its owning hunter.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-simplicity-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name
(e.g. `fable-5`) — in `docs/` (or the repository root when there is no `docs/`). If the caller specifies
an output path or return mode (e.g. the party-hunter orchestrator), it overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line` with the exact code.
- **Public API shape may change.** Report a simplification that changes an exported API like any other finding,
  whatever its backward-compatibility cost.
