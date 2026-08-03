---
name: smell-hunter
description: |
  Use when reviewing Go, Python, or TypeScript code for classic code smells, preparing a
  refactor, auditing code after rapid feature development, or hunting for misplaced
  responsibilities and undermodeled domain concepts.

  Covers feature envy, data clumps, shotgun surgery, temporal coupling, comments as
  deodorant, temporary fields, primitive obsession, god modules, mutable global state,
  anemic domain models, class abuse, and language-specific antipatterns.
disable-model-invocation: true
---

# Smell Hunter

Audit code for **code smells** — structural patterns indicating deeper design problems. Covers selected Fowler/Beck
smells and language-specific antipatterns outside specialized hunters' scope. Goal: **data lives where it's used,
changes are localized, domain concepts are modeled explicitly, language idioms are respected.**

Supports Go, Python, TypeScript via per-language reference files.

**Not covered (owned by other hunters):** long method / mixed concerns, dead code, speculative generality, boolean
parameters, interface pollution, callback hell and unflattened promise chains (→ simplicity-hunter); magic numbers
and missing "why" documentation (→ doc-hunter); alias-vs-named-type mechanics and enum-vs-union design
(→ type-hunter); SOLID violations (→ solid-hunter); module boundary and dependency direction (→ boundary-hunter);
invariant enforcement (→ invariant-hunter); security (→ security-hunter); test quality (→ test-hunter); AI-generated
noise and cosmetic style (→ slop-hunter). Where ownership is *contested* rather than simply elsewhere, that
category's **Ownership:** note in What to Hunt is authoritative.

Smells are symptoms, not diagnoses: each finding indicates a *likely* design problem warranting investigation.
Context decides whether it is a genuine issue or an acceptable trade-off.

## When to Use

- Reviewing structural design problems before a refactor
- Auditing after rapid feature development or prototyping
- Hunting misplaced responsibilities and data
- Identifying missing domain types and abstractions
- Preparing a codebase for long-term maintainability
- Complementing specialized hunters with cross-cutting smell detection

## Quick Reference

Full rules in **What to Hunt**; every finding must also clear Not-a-finding and the Phase 5 reporting gate.
Conditional categories run only where the language reference declares them applicable (see Applicability).

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Feature Envy | Uses more foreign data than its own | Move to the data's owner | — |
| Data Clumps | Same 3+ values travel together across signatures | Extract a named type | Duplication *in test setup* → test-hunter |
| Shotgun Surgery | One logical change edits many unrelated areas | Consolidate the concept | Dependency direction → boundary-hunter; SRP → solid-hunter |
| Temporal Coupling | Call order required, nothing enforces it | Redesign so order is implicit | Constraints that are *staying* → doc-hunter |
| Comments as Deodorant | Comment explains *what* non-trivial code does | Extract, don't annotate | See the comment ownership rule below |
| Temporary Field | Field meaningful in only one code path | Per-state type or a local | — |
| Primitive Obsession | Primitives standing in for domain concepts | Named / branded type, validated construction | Alias mechanics → type-hunter; validated-state brands → invariant-hunter; security brands → security-hunter |
| God Module | One file accumulating unrelated responsibilities | Split by responsibility | Sprawl *in a class* → solid-hunter |
| Mutable Global State | Writes to global state after initialization | Explicit ownership; inject | — |
| Anemic Domain Model | Entity transitions live outside the entity | Move the transition onto the entity | Invariant *enforcement* → invariant-hunter |
| Class Abuse | Class where a function or module would do | Replace with the simpler construct | Class/interface *design* → solid-hunter |

Hunter names are unsuffixed end-state names. Until consolidation completes, live skills are language-suffixed
(`type-hunter-go`, `type-hunter-py`, `type-hunter-ts`, and so on).

## Core Principles

1. **Smells are symptoms, not diseases.** A smell indicates a probable design problem, not a guaranteed one. Evaluate
   in context — some are intentional trade-offs. Goal: awareness, not mechanical elimination.

2. **Follow the data.** Feature envy, data clumps, and primitive obsession all point to misplaced or undermodeled
   data. When data and behavior want to be together, let them. Values that always travel together are a missing type.

3. **One change, one place.** Shotgun surgery is the hallmark of misaligned module boundaries or scattered
   responsibilities. The fix is cohesion.

4. **Comments are not deodorant.** A comment explaining confusing code band-aids a design problem. The fix is clearer
   code — better names, extracted functions, simpler structure — not more comments.

5. **Model the domain.** A string that is an email address, two floats that are a coordinate, parameters that always
   appear together — these are domain concepts begging for a type.

6. **Use the language, don't fight it.** Every supported language has constructs that eliminate whole smell
   categories. Prefer idiomatic design over transplanted patterns; the language reference carries the calibration.
   Replacing a project implementation with an equivalent *existing* primitive is simplicity-hunter's Reinvented
   Primitives — smell-hunter owns broader non-idiomatic design, not that substitution.

7. **Refactor incrementally.** Split by responsibility, not size. Abstract only when needed (wait for the second use
   case). Preserve behavior first — add tests before restructuring.

## Not a finding on these grounds alone

Conditionals, not category exemptions — each states what does **not** justify a finding and, where a corresponding
finding exists, what would:

- **A read-only lookup table with no write path** — a global holding an effectively-constant map or slice is not
  Mutable Global State. The smell is writes after initialization, not the declaration keyword. *Is* a finding when
  any assignment to it exists outside its declaration.
- **Genuine DTOs, config objects, and wire types** — a data carrier with no behavior is not an Anemic Domain Model.
  *Is* a finding when the type is a domain entity whose transitions were extracted elsewhere.
- **Data plus functions, where behavior is not expressed as methods** — not an Anemic Domain Model. Method syntax is
  not the bar; misplaced transitions are.
- **A data clump appearing twice** — repetition alone does not justify a new type. Occurrence count is supporting
  evidence, not a gate: report it, do not decide on it. *Is* a finding when the group has an obvious domain name and
  every site would consume the extracted type.
- **Feature envy in a utility function** — a helper deliberately written over a foreign type is not misplaced. *Is* a
  finding when the function's name and purpose belong to the type it envies.
- **Two same-typed parameters that cannot be transposed in practice** — adjacent `string` parameters are not
  Primitive Obsession when call sites cannot plausibly swap them (different shapes, one always literal, compile-time
  keyed). *Is* a finding when a swap would type-check and silently change behavior.
- **A class with real state and multiple methods** — not Class Abuse. That is what classes are for.
- **A shape the specific framework construct mandates** — exempt only the shape the named construct requires, and
  name the construct. "This project uses Nest" is not evidence; "Angular `@Component` must be a class" is. Framework
  carve-outs are listed per language in the reference.

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Temporary Field").

### Feature Envy

Uses more data from another module, package, or type than from its own receiver, local state, or scope.

**Signals:**

- Method on type A mostly accessing type B's fields/methods (B passed as a parameter)
- Destructures a foreign object, operates on most of its members
- Helper in module A operating only on module B's types
- Receives an object, calls 3+ of its methods, uses none of its own state
- Name says it belongs to the type it operates on, not the module it lives in

**Action:** Move it to the module owning the data, minding import cycles and the language's rules on where methods
may be defined. Uses two types equally? Consider extracting the shared data into its own type.

### Data Clumps

The same group of parameters or fields that always travel together across signatures or type definitions.

**Signals:**

- 3+ parameters recurring together across signatures (`host`, `port`, `scheme`; `latitude`, `longitude`, `altitude`)
- Multiple types carrying the same field subset (`street`, `city`, `zip`, `country`)
- Related values passed individually instead of as one type
- A logical sub-group inside a larger type (`start_date`, `end_date`, `timezone` in a config)

**Action:** Extract a named type, replacing the individual parameters/fields. Signature-only clumps become a
parameter type; clumps across type definitions become a shared composed type. Remedy vocabulary is per-language —
see the reference.

**Test-code boundary:** duplicated *test setup* data is test-hunter's "Test Setup Duplication and Shared State" — do
not flag it here.

### Shotgun Surgery

One logical change requires edits across many unrelated files or areas.

**Signals:**

- Adding one field to a domain type touches 5+ files (handlers, validators, mappers, serializers, tests)
- Adding a variant touches every scattered switch/`if`-chain rather than one registry
- One config concept, feature flags included, spans config, middleware, handlers, and templates
- Renaming a concept means find-and-replace across the codebase

**Action:** Consolidate the scattered responsibility — registry or map-based dispatch instead of scattered switch
cases; generation or schema-derived types for per-variant boilerplate; one area owning the concept end-to-end.

**Evidence rule (the one exception to a purely in-file anchor).** The finding still anchors to an **in-scope source
location**: the concrete site edited per variant — the switch, the mapper, the registration list. Commit hashes and
subjects are *supporting* evidence. History alone is not a location; a finding with only commit hashes is not
reportable. Detection is Phase 4.

### Temporal Coupling

Operations that must be called in a specific order, with nothing in the API enforcing it.

**Signals:**

- `Init`/`Setup`/`Configure` methods that must precede `Run`/`Process`
- Docs or comments saying "must call X before Y" — evidence *of* the smell, not an exemption
- Panic, nil dereference, or undefined behavior when methods run out of order
- A builder whose `Build()` can be called before required fields are set
- State-machine transitions valid only from certain states, unenforced by the API

**Action:** Make the order implicit — constructors returning fully initialized values, builders that validate at
`Build()`, per-state types exposing only valid transitions, dependencies accepted at construction rather than via
setters.

**Ownership:** the coupling and its redesign are owned here. doc-hunter covers only constraints that are *staying*
(redesign rejected or out of scope) and need documenting — a comment is the fallback, not the fix.

### Comments as Deodorant

Comments explaining *what* confusing code does rather than *why* — masking a design problem instead of fixing it.

**Comment ownership rule** (stated identically in doc-hunter, slop-hunter, and smell-hunter):

- Comment absent and the "why" non-obvious → doc-hunter (add the missing "why" comment).
- Comment present and the code trivial → slop-hunter (delete the redundant comment).
- Comment present and the code non-trivial → smell-hunter (extract/refactor; the comment is deodorant).

**Signals:**

- `// Convert the user data to the format expected by the billing system` above a 20-line block that should be an
  extracted `toBillingFormat()`
- Comments explaining complex boolean expressions instead of extracting named helpers
- Inline comments at each step of a long function, creating "sections" that should be separate functions
- Comments explaining workarounds for the code's *own* design rather than external constraints
- `// This is confusing because...` — writing this comment means refactor instead

**Action:** Extract the commented block into an intent-revealing function; replace complex expressions with named
variables or helpers; split long functions at the comment boundaries. Keep only *why* comments — business rules,
external constraints, third-party workarounds.

### Temporary Field

Fields meaningful only in certain states or operations — set for one code path, nil/None/undefined for all others.

**Signals:**

- Set in one method and read in another, meaningless in the rest
- Optional fields existing because the type serves multiple contexts with different data requirements
- Fields documented "only valid when X is true" or "set only during processing"
- Fields like `tempResult`, `cachedData`, `lastError` serving a single transient use

**Action:** Extract them into a separate type used only where needed. If the type represents multiple states, use a
discriminated pattern — one type per state — or a method-local variable instead of a field.

### Primitive Obsession *(conditional)*

Primitive types for domain concepts deserving their own named or branded types.

**Ownership:** primitive obsession as *domain modeling* is owned here; type-hunter keeps only alias-vs-named-type
*mechanics*. Boolean parameters belong to simplicity-hunter. Brands encoding *validated* state
(parse-don't-validate) belong to invariant-hunter; brands for security-sensitive strings (SQL fragments, HTML,
paths) belong to security-hunter. Cross-reference instead of duplicating.

**Signals:**

- Bare strings for IDs, emails, URLs, currencies, or status codes
- Two same-typed parameters that could be accidentally swapped (`Transfer(from, to string, amount int)`)
- Validation for a "typed" string scattered across call sites instead of enforced at construction
- Floating-point money
- Integers for durations without unit clarity
- Raw string comparisons for status/state instead of typed constants or unions

**Action:** Define a domain type with validating construction, so the type system prevents mixing. Remedy vocabulary
is per-language — see the reference.

### God Module *(conditional)*

A single source file accumulating unrelated responsibilities — the dumping ground for everything.

**Ownership:** scoped to the file/module unit. Responsibility accumulation *within a class* is solid-hunter's God
Class; package-level organization is boundary-hunter's.

**Signals:**

- Unrelated functionality, or functions spanning different domain concepts, in one file — line count nominates,
  unrelated responsibilities decide
- Names like `utils`, `helpers`, `common`, `misc` with unbounded scope
- A file imported by nearly every other file
- Package entry files carrying business logic instead of re-exports

**Action:** Split by responsibility; each file gets one clear purpose. Genuinely shared utilities group by domain
concept (`string_utils`, `date_utils`).

### Mutable Global State *(conditional)*

Globals holding mutable state, creating hidden coupling and test interference. **The smell is writes after
initialization**, not the declaration keyword — see Not-a-finding.

**Signals:**

- A global connection, client, cache, or logger written to or replaced at runtime
- A global default config mutated by a `SetConfig`-style function
- Lazily-initialized global singletons holding state
- A global lock protecting global state (a sign the state should be owned by something)

**Action:** Move state into instances passed via dependency injection. Where a global lifetime is genuinely required,
construct it in the composition root and inject it explicitly. Constants and immutable globals are fine.

**Singleton split (with Class Abuse).** A *stateful* singleton is a Mutable Global State finding; the remedy is
explicit ownership and injection — **never** "replace with a module-level instance", which preserves the global
lifetime and merely removes the wrapper. A *stateless*, namespace-shaped singleton is a Class Abuse finding, remedied
by module-level functions. One finding per site, cross-referenced — never both.

### Anemic Domain Model *(conditional)*

Domain entities whose state transitions live outside the entity, in services that mutate it from outside.

**Ownership:** this category owns *placement of transitions*. Entity-invariant *enforcement* routes to
invariant-hunter.

**A finding requires at least one of** — shape alone is never enough:

- Transitions for one entity scattered across multiple services
- Entity fields mutated externally (`order.status = "shipped"`) where the entity could own the transition
  (`order.ship()`)
- Tell-don't-ask at call sites: interrogate entity state, then act, repeatedly

**Action:** Move the transition onto the entity. Keep services as orchestrators between entities, not the sole home
of domain logic.

### Class Abuse *(conditional)*

A class where a plain function, closure, or module would be simpler and more idiomatic.

**Signals:**

- Constructor plus one public method (a function in disguise)
- Only static methods (a module in disguise)
- No state — all methods are pure functions over their parameters, or the class merely groups related functions
- Constructor that just assigns parameters to fields with no validation or logic
- Stateless "Service" classes receiving all data through method parameters

**Action:** Single-method class → exported function (closure for dependencies); static-only or stateless class →
module with named function exports; stateless singleton → module-level functions (a *stateful* singleton is Mutable
Global State — see the singleton split); state-holding class with meaningful behavior → keep it, it is the right
tool.

## Applicability

Six categories are universal. Five are conditional: defined once above, declared applicable or not by each language
reference, with the reason. **A language with no reference is not supported** — its files are excluded, never
implicitly audited.

| Conditional category | Go | Python | TypeScript |
| -------------------- | -- | ------ | ---------- |
| Primitive Obsession | yes | yes | yes |
| God Module | **n/a** — package organization is boundary-hunter's; a Go file is not a module | yes | yes |
| Mutable Global State | yes | yes | yes |
| Anemic Domain Model | **n/a** — functional domain logic over immutable data is idiomatic Go, blessed by solid-hunter | yes | yes |
| Class Abuse | **n/a** — no classes | yes | yes |

Language-only categories are defined entirely in their reference: `init()` Abuse and Stuttering Names (Go); Mutable
Default Arguments (Python).

## Test-code scope

Test files are **in scope** for every category except the two test-hunter explicitly claims — its test-duplication
and setup section, titled "Test Setup Duplication and Shared State" in Go and "Test Duplication and Setup Bloat" in
Python and TypeScript:

- **Data Clumps in test setup** → test-hunter
- **Shared mutable state between tests** → test-hunter

Everything else applies: a temporal-coupling trap in a test helper, feature envy in a fixture builder, and a
temporary field on a test harness type are all reportable here. Each language reference's scan profile enforces this
split.

**One overlap to route deliberately.** test-hunter nominates oversized test-utility files under setup bloat.
*Duplication or bulk* is test-hunter's; *unrelated responsibilities collected in one test-support module* is God
Module here. Cross-reference; never report both.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is:**

- **Critical** — *actively producing wrong behavior* on a production path (swappable primitive IDs already mixed up;
  a mutable default already leaking state between calls). Smells are rarely Critical.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk. A stuttering name is Low however widespread.

**Impact — how much the change is worth:** defect exposure reduced, cognitive burden reduced, affected surface.
Contextual; never derived from occurrence count or pattern alone. A data clump in 9 signatures is High impact at Low
severity.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the reporting gate but touches a small, rarely hit surface

Recommendations group by Severity (Critical → High → Medium → Low), then by Impact within each group.

## Audit Workflow

### Phase 1: Gain Context

1. **Resolve the raw manifest.** Scope may be:
   - **Diff**: files changed relative to the base branch — committed, staged, unstaged, untracked
   - **Path**: specific files, folders, or packages
   - **Codebase**: the entire project (default when unspecified; set `SCOPE=.`)

   **Party mode:** when the orchestrator supplies a scope snapshot, treat `scope.txt` as a **file manifest only**
   (one path per line). Read run metadata (base SHA, surface kind, counts) from `scope-meta.txt` when present. Use
   the manifest verbatim; do not re-resolve. The resolution below is for standalone runs only.

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
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop. If the resolved surface exceeds the context
   budget, report the file count and ask to narrow or chunk.

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
   evidence form, no remedy vocabulary. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming
   each extension. A language becomes supported when its reference defines those four things.

3. **Load language references.** For every detected language, read `references/smell-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/smell-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**; do not continue with shared categories only.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules to that
   language's files. These subsets are then immutable. Record in Scope: raw manifest count, each per-language
   eligible subset, exclusions, and `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, documentation / Markdown-only inputs, and generated files
   identified by each reference's authoritative **in-file marker** — **never** by filename guessing. Scan globs in
   references are approximations for scanning convenience; reporting eligibility uses the marker rule.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop
   before scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Related files may still be *read* as **context**: judging Feature Envy or a Data Clump routinely requires
   reading the envied type's module.

5. **Read repository instructions** when present (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, convention docs) for
   stated design decisions, framework constraints, and naming conventions. Then understand the project's domain
   model — core entities, value objects, operations — and its conventions for type design and module organization.
   Both feed Anemic Domain Model, Primitive Obsession, and God Module judgment.

### Phase 2: Scan for Smell Candidates

Scans produce **candidates only** — each match needs manual validation in Phases 3–5 before becoming a finding.
Expect many regex false positives; the value is surfacing locations to inspect.

For each loaded reference, run its Phase 2 scan block against that language's eligible subset (`SCOPE=.` in codebase
mode). Pass an explicit path (`-- $SCOPE` or `.`) to **every** `rg` invocation. Judge each finding under the rules of
its own file's language — including language-only categories the reference appends.

### Phase 3: Evaluate Feature Envy and Data Clumps

For each function with cross-module data access:

- Does it access more members from another type than from its own state?
- Would moving it to the other type's module improve cohesion?
- Is it a deliberate utility over a foreign type (see Not-a-finding)?

For each function with 4+ parameters:

- Do the same parameters appear together in other signatures? At how many sites?
- Is there a named domain concept these parameters represent?
- Is the site test setup (→ test-hunter)?

### Phase 4: Evaluate Shotgun Surgery — once per audit

Detected from git history, so it has no language dimension: run **once**, not once per loaded reference. High churn
on a single file is not shotgun surgery — the signal is many *unrelated* areas changing together for one logical
change.

```bash
# 1. Restrict history to commits that touch at least one manifest file. Everything downstream
#    is then in-scope by construction. In codebase mode ($SCOPE=.) this is every commit.
CO=$(mktemp)
for c in $(git log --pretty=format:'%h' -200 -- $SCOPE); do
  # 2. Retain hash, subject, and the commit's FULL file list — evidence must survive to the report.
  git show --pretty=format:'@@@ %h %s' --name-only "$c"
done > "$CO"

# 3. Count directory PAIRS, not whole sets, so partially overlapping commits still co-occur.
awk '
  function flush(   n, i, j, t, k, p) {
    n = 0; for (p in dirs) k[++n] = p
    for (i = 1; i < n; i++) for (j = i + 1; j <= n; j++)
      if (k[j] < k[i]) { t = k[i]; k[i] = k[j]; k[j] = t }
    for (i = 1; i < n; i++) for (j = i + 1; j <= n; j++) print k[i] " <-> " k[j]
    delete dirs
  }
  /^@@@ / { flush(); next }
  NF { d = $0; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = "."; dirs[d] = 1 }
  END { flush() }
' "$CO" | sort | uniq -c | sort -rn | head -30

# 4. Nominate commits touching 4+ directories, hash and subject intact.
awk '
  function flush(   n, p) {
    if (hdr != "") { n = 0; for (p in dirs) n++; if (n >= 4) print n "\t" hdr }
    delete dirs; hdr = ""
  }
  /^@@@ / { flush(); hdr = substr($0, 5); next }
  NF { d = $0; if (d ~ /\//) sub(/\/[^\/]*$/, "", d); else d = "."; dirs[d] = 1 }
  END { flush() }
' "$CO" | sort -rn | head -20
```

Merge commits list no files under `git show --name-only` and drop out naturally. For each nominated commit ask: one
logical change scattered across unrelated areas, or a legitimate cross-cutting concern? A recurring directory pair
across multiple commits is the structural-coupling signal; a single commit is not a pattern.

**Before reporting, satisfy the evidence rule** (see Shotgun Surgery): name the in-scope source location edited per
variant. Commits are supporting evidence, not the anchor.

### Phase 5: Evaluate Each Finding

**Reporting gate.** Report only when the smell points at a design problem worth naming — the proposed change reduces
misplacement, scattering, or hidden coupling enough to outweigh its churn.

For each candidate: apply Not-a-finding first; confirm the category is applicable to that file's language; clear the
gate; then apply the per-category evidence bar from What to Hunt. Run each loaded reference's Phase 5 block for its
language-only categories and language-specific judgment.

Conditional categories carry explicit gates scan output cannot satisfy:

- **Primitive Obsession** — a swap must be plausible and silent at a real call site.
- **God Module** — unrelated responsibilities, enumerated. Line count nominates only.
- **Mutable Global State** — a write path after initialization must exist.
- **Anemic Domain Model** — at least one of the three evidence conditions, not shape.
- **Class Abuse** — statelessness confirmed by reading the type, and the singleton split applied.

Assign **Severity and Impact** to every finding (both required; they diverge). Nothing is held back;
`Audit completed: N findings` counts every reported finding.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-smell-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if none exists). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas. Language-only categories
appended by a language reference use the table schemas supplied in that reference.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "The regex matched, so it's feature envy" | Scan output is a nomination. Open the body and count what it touches. |
| "This class has one method — Class Abuse" | Does it hold state? A stateful one-method class is not the smell. |
| "These 6 files always change together" | One commit is not a pattern. And where is the in-scope anchor the finding cites? |
| "`utils.py` is 700 lines — God Module" | Line count nominates. Enumerate the unrelated responsibilities or drop it. |
| "The comment explains the code, so it's deodorant" | Only when the code is non-trivial. Trivial → slop-hunter; absent → doc-hunter. |
| "This is a global" | Is there a write path after initialization? A read-only table is not the smell. |
| "It's a Nest project, so the class shape is mandated" | Which construct requires it? Providers support `useValue` / `useFactory` / tokens. |
| "The entity has no methods" | Which transition is misplaced, and where does it live now? Shape is not the bar. |
| "There's a comment saying 'call Init first'" | That is evidence *of* temporal coupling, not an exemption from it. |
| "I'll flag it in both categories" | One finding per site, cross-referenced. Stateful singleton → Mutable Global State only. |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do shared categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** Audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only *categories* with findings. Omit a category heading, table, or list
  entirely when it would contain zero items — no empty tables, placeholder subsections, or negative statements like
  "none found" or "no issues". The Scope section is not a category and is filled in from the template every run.
- **Scope: classic code smells and language-specific antipatterns only.** A finding that doesn't answer "is this a
  structural smell?" belongs to another hunter — do not flag it here. Contested boundaries are resolved at the
  category that owns them: each **Ownership:** note in What to Hunt states what is kept here and what routes away.
- **Evidence required.** Every finding cites `file:line` (path form per the language reference) with the exact code.
  The single exception is Shotgun Surgery's supporting commit evidence, which supplements — never replaces — an
  in-scope anchor.
- **One finding per site.** When two categories describe the same code, pick the primary one and cross-reference.
  The singleton split is the worked example.
- **Context matters.** A smell in a prototype is less urgent than one in a payment system. Calibrate Severity and
  Impact to the code's criticality and change frequency.
- **Pragmatism.** Report the smell, assess the cost/benefit in the Action column, and let the team decide whether to
  act.
- **Respect the language.** Idiomatic constructs are not smells. Calibrate to the audited language's conventions —
  the reference carries the calibration — not to patterns from another language.
- **Handoff, not duplication.** Smell-hunter owns *symptom detection*; the root-cause fix may belong to
  boundary-hunter (dependency direction), solid-hunter (SRP), or simplicity-hunter (mixed concerns). When a finding
  clearly belongs to another hunter's domain, cross-reference it and do not duplicate the analysis. When the smell is
  the primary signal and no other hunter covers the detection method, own the finding.
- **Assess refactoring risk briefly, but never defer on API shape.** When a recommendation would affect
  serialization behavior, introduce import cycles, or collide with a framework constraint, note the risk in the
  Action column — those are *behavior*. A change to exported API shape is **not** grounds to downgrade, defer, or
  soften a finding.
