---
name: smell-hunter
description: Audit Go, Python, or TypeScript code for code smells — feature envy, data clumps, shotgun surgery, temporal coupling, primitive obsession, god modules, global state, anemic models, class abuse. Defaults to the codebase.
disable-model-invocation: true
---

# Smell Hunter

Audit code for **code smells** — structural patterns indicating deeper design problems. Covers selected Fowler/Beck
smells and language-specific antipatterns outside specialized hunters' scope. Goal: **data lives where it's used,
changes are localized, domain concepts are modeled explicitly, language idioms are respected.**

**Not covered (owned by other hunters):** long method / mixed concerns, dead code, speculative generality, boolean
parameters, interface pollution, callback hell and unflattened promise chains, replacing a project implementation with
an equivalent existing primitive (Reinvented Primitives) (→ simplicity-hunter); magic numbers and missing "why"
documentation (→ doc-hunter); the construct of an existing enum, constant group, or Go/Python alias (→ type-hunter);
SOLID violations (→ solid-hunter); module boundary and dependency direction (→ boundary-hunter); invariant enforcement
(→ invariant-hunter); security (→ security-hunter); test quality (→ test-hunter); AI-generated noise and cosmetic
style (→ slop-hunter).

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `security-hunter-go`, `security-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Feature Envy | Uses more foreign data than its own | Move to the data's owner |
| Data Clumps | Same 3+ values travel together across signatures | Extract a named type |
| Shotgun Surgery | One logical change edits many unrelated areas | Consolidate the concept |
| Temporal Coupling | Call order required, nothing enforces it | Redesign so order is implicit |
| Comments as Deodorant | Comment explains *what* non-trivial code does | Extract, don't annotate |
| Temporary Field | Field meaningful in only one code path | Per-state type or a local |
| Primitive Obsession *(conditional)* | Primitives standing in for domain concepts | Named / branded type, validated construction |
| God Module *(conditional)* | One file accumulating unrelated responsibilities | Split by responsibility |
| Mutable Global State *(conditional)* | Writes to global state after initialization | Explicit ownership; inject |
| Anemic Domain Model *(conditional)* | Entity transitions live outside the entity | Move the transition onto the entity |
| Class Abuse *(conditional)* | Class where a function or module would do | Replace with the simpler construct |

## Not a finding on these grounds alone

- **A shape the specific framework construct mandates** — exempt only the shape the named construct requires, and
  name the construct. "This project uses Nest" is not evidence; "Angular `@Component` must be a class" is. Framework
  carve-outs are listed per language in the reference.

## What to Hunt

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

**Not a finding:**

- **A utility function** — a helper deliberately written over a foreign type is not misplaced. *Is* a finding when
  the function's name and purpose belong to the type it envies.
- **Switching on a foreign type's discriminant to answer the home module's own question** — consuming another
  module's result type is what result types are for; the function belongs with the *policy* it implements, not the
  data it reads. Moving it would make the data's module depend on one consumer's policy. "Drops one import" is not a
  gain worth reporting.

**Ownership:** this category judges the consumer's *placement*. A consumer reaching an exported *implementation*
member — a cache, a row struct, a mutex — is boundary-hunter's Leaked Internals, anchored at the export; members that
pass its rewrite test leave the placement question here.

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

**Evidence: read every cited signature.** The group must appear in each signature the finding lists — verified by
opening them, not inferred from names. Count the parameters as written; a claimed adjacency, arity, or field that
does not exist voids the finding. A group present in only one signature is at most an over-parameterized API
(→ simplicity-hunter), not a clump.

**If the justification is an invariant between the fields, the remedy must enforce it.** A plain record only stores
the values together; recommend a factory or validating constructor that derives the dependent field, so the invariant
moves from a comment into the construction path. Grouping without either a real transposition risk or an enforced
invariant is convenience, not safety — say which one the extraction buys.

**Not a finding: a clump appearing twice** — repetition alone does not justify a new type. Occurrence count is
supporting evidence, not a gate: report it; the domain name and the consuming sites decide. *Is* a finding when the group has an obvious
domain name and every site would consume the extracted type.

### Shotgun Surgery

One logical change requires edits across many unrelated files or areas. An **area** is the folder holding the file —
neutral on purpose: a Go package is not a module, and a Python module is not a package.

**Signals:**

- Adding one field to a domain type touches 5+ files (handlers, validators, mappers, serializers, tests)
- One config concept, feature flags included, spans config, middleware, handlers, and templates
- Renaming a concept means find-and-replace across the codebase

**Action:** Consolidate the scattered responsibility — generation or schema-derived types for per-field
boilerplate; one area owning the concept end-to-end.

**Ownership:** **variant dispatch is solid-hunter's.** A variant added to an open set that edits every scattered
switch or `if`-chain is solid-hunter's Rigid Extension Points, which carries the registry gate and the openness test;
route it. Dependency direction is boundary-hunter's Dependency Direction Violations. This category keeps
**non-variant** scattering: a field addition rippling through mappers, validators and serializers; a config concept
spanning layers; a rename that is find-and-replace — including the scattering only git history reveals (Phase 4),
where no shared discriminant exists to dispatch on.

**Evidence rule (the one exception to a purely in-file anchor).** The finding still anchors to an **in-scope source
location**: the concrete site edited per change — the mapper, the validator, the registration list. Commit hashes and
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

**Ownership:** the coupling and its redesign are owned here. An order that a protocol, a third-party library, the OS, or
a framework imposes on the project's code is doc-hunter's Unexplained Workarounds. A wrapper the project writes around
such an order is the project's own API, and stays here. The construction test with invariant-hunter, Go only: a type
that can be *constructed* invalid — zero value usable, no constructor — is invariant-hunter's Zero-Value Traps; a
validly constructed value whose *methods* must be called in order (`Init` before `Run`, `Build` before required setters)
is here. In Python and TypeScript the construction test does not route away; both cases stay here.

### Comments as Deodorant

Comments explaining *what* confusing code does rather than *why* — masking a design problem instead of fixing it.

**Comment ownership rule:**

- Comment contradicts the code it describes → doc-hunter (Misleading Comments and Names), unless it only justifies a
  construct another hunter audits (a discarded error, a type-system bypass) → that hunter.
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

**Ownership:** the discriminant test with invariant-hunter. **No discriminant exists yet** — optional fields
meaningful in different states, mutually exclusive optionals, "only valid when X" — is here, and the remedy introduces
the per-state type. **A discriminant exists** and fields leak across variants, a parallel flag duplicates it, or a
switch lacks an exhaustiveness arm → invariant-hunter's Leaky Discriminated Unions. The transfer is Python and
TypeScript only: for Go, where that category is n/a, a tagged struct with fields meaningful only in some states stays
here whether or not a tag exists.

**Enumerate the producers before recommending a type split.** When every producer of the type already pairs the field
correctly and only a hand-built value could reach the bad state, the finding is Low and the remedy is the minimal
guard at the consumer — a variant split with one producer and one consumer is gold plating. Recommend the split only
when a second valid state or a second producer/consumer actually exists.

### Primitive Obsession *(conditional)*

Primitive types for domain concepts deserving their own named or branded types.

**Ownership:** primitive obsession as *domain modeling* is owned here; this category needs a primitive with **no named
construct yet**. An existing constant group or enum built with the wrong construct is type-hunter's Enum Construct
Mechanics; an existing Go or Python alias used as an identity type is its Alias vs Named Type Mechanics; TypeScript
aliases stay here under brand-or-withdraw. Boolean parameters belong to simplicity-hunter. Brands encoding
*validated* state (parse-don't-validate) belong to invariant-hunter; brands for security-sensitive strings (SQL
fragments, HTML, paths) belong to security-hunter.

**Signals:**

- Bare strings for IDs, emails, URLs, currencies, or status codes
- Two same-typed parameters that could be accidentally swapped (`Transfer(from, to string, amount int)`)
- Validation for a "typed" string scattered across call sites instead of enforced at construction
- Floating-point money
- Integers for durations without unit clarity
- Raw string comparisons for status/state instead of typed constants or unions

**Action:** Define a domain type with validating construction, so the type system prevents mixing. Remedy vocabulary
is per-language — see the reference.

**Not a finding: two same-typed parameters that cannot be transposed in practice** — adjacent `string` parameters
are not Primitive Obsession when call sites cannot plausibly swap them (different shapes, one always literal,
compile-time keyed). *Is* a finding when a swap would type-check and silently change behavior.

### God Module *(conditional)*

A single source file accumulating unrelated responsibilities — the dumping ground for everything.

**Ownership:** scoped to the file/module unit. Responsibility accumulation *within a class* is solid-hunter's
Responsibility Sprawl; a generic-named *package or module directory* is boundary-hunter's Generic Boundary Names;
package-level responsibility sprawl is solid-hunter's.

**Signals:**

- Unrelated functionality, or functions spanning different domain concepts, in one file — line count nominates,
  unrelated responsibilities decide
- Names like `utils`, `helpers`, `common`, `misc` with unbounded scope
- A file imported by nearly every other file
- Package entry files carrying business logic instead of re-exports

**Evidence:** enumerate the unrelated responsibilities by name; fewer than two named is not a finding.

**Action:** Split by responsibility; each file gets one clear purpose. Genuinely shared utilities group by domain
concept (`string_utils`, `date_utils`).

**Calibration.** A small, cohesive module carrying one minor misplaced group — a few constants whose sole importer is
one other file — is *misplaced locality*, not a God Module. In diff mode, when the diff touches either file, report it
at Low/Low with an opportunistic action ("move when either file is next edited"); otherwise omit it. The God Module
label on a 100-line file is noise.

### Mutable Global State *(conditional)*

Globals holding mutable state, creating hidden coupling and test interference.

**Write after initialization** — a rebinding *or* an in-place mutation (element store, append, mutating method
call) of a global that can run after package or module initialization finishes. Go `init()` and package-level
initializers, Python and TypeScript module top level are initialization; a lazy first-use assignment is not. The
smell is a write after initialization, not the declaration keyword.

**Signals:**

- A global connection, client, cache, or logger written to or replaced at runtime
- A global default config mutated by a `SetConfig`-style function
- Lazily-initialized global singletons holding state
- A global lock protecting global state (a sign the state should be owned by something)

**Action:** Move state into instances passed via dependency injection. Where a global lifetime is genuinely required,
construct it in the composition root and inject it explicitly. A unit that *reads* the global instead of receiving it is
solid-hunter's Concrete Dependency Chains, anchored at the consumer — this category anchors at the global's
declaration and write sites. Two anchors, one finding each, cross-referenced.

**Not a finding: a read-only lookup table with no write path** — a global holding an effectively-constant map or
slice. *Is* a finding when a write after initialization exists.

**Singleton split (with Class Abuse).** A *stateful* singleton is a Mutable Global State finding; the remedy is
explicit ownership and injection — **never** "replace with a module-level instance", which preserves the global
lifetime and merely removes the wrapper. A *stateless*, namespace-shaped singleton is a Class Abuse finding, remedied
by module-level functions.

### Anemic Domain Model *(conditional)*

Domain entities whose state transitions live outside the entity, in services that mutate it from outside. An
*entity* is a domain type with identity whose state changes through named transitions (`order.ship()`,
`user.suspend()`). A *data carrier* — DTO, config object, wire, request or response type, ORM row mapper — moves
values across a boundary and has no transitions. This category judges entities only.

**Ownership:** this category owns *placement of transitions*. Entity-invariant *enforcement* routes to
invariant-hunter.

**A finding requires at least one of** — shape alone is never enough:

- Transitions for one entity scattered across multiple services
- Entity fields mutated externally (`order.status = "shipped"`) where the entity could own the transition
  (`order.ship()`)
- Tell-don't-ask at call sites: interrogate entity state, then act, repeatedly

Name at least one misplaced transition and where it lives now; cite each external field assignment.

**Not a finding:** a data carrier with no behavior (*is* a finding when the type is a domain entity whose transitions
were extracted elsewhere); data plus functions where behavior is not expressed as methods — method syntax is not the
bar, misplaced transitions are.

**Action:** Move the transition onto the entity. Keep services as orchestrators between entities, not the sole home
of domain logic.

### Class Abuse *(conditional)*

A class where a plain function, closure, or module would be simpler and more idiomatic.

**Ownership:** class and interface *design* is solid-hunter's; this category asks only whether a class is needed.
Whether the layer should exist at all is simplicity-hunter's Unnecessary Abstractions: when the layer should go, the
finding is there; when only its form changes, it is here.

**Signals:**

- Constructor plus one public method (a function in disguise)
- Only static methods (a module in disguise)
- No state — all methods are pure functions over their parameters, or the class merely groups related functions
- Constructor that just assigns parameters to fields with no validation or logic
- Stateless "Service" classes receiving all data through method parameters

**Action:** Single-method class → exported function (closure for dependencies); static-only or stateless class →
module with named function exports; stateless singleton → module-level functions; state-holding class with meaningful
behavior → keep it, it is the right tool.

**Evidence:** confirm statelessness by reading the type.

**Not a finding: a class with real state and multiple methods** — that is what classes are for.

### Within-skill precedence

**One site, one finding.** When two categories here read the same site, the first matching rule decides the
category, and the Evidence cell names the other reading in one clause:

- A function outside a domain entity performing one of its state transitions → Anemic Domain Model, not Feature
  Envy. Feature Envy keeps envy of data that is not an entity's transition.
- Three or more values travelling together → Data Clumps, whose Evidence names any swap risk. Exactly two same-typed
  values a caller could swap → Primitive Obsession.
- A stateful singleton → Mutable Global State; a stateless one → Class Abuse (the singleton split).

## Applicability

Six categories are universal. The five marked *(conditional)* run only where each language reference's Applicability
table says yes; a language with no reference is not supported. Language-only categories are defined entirely in their
reference: `init()` Abuse, Stuttering Names and Pointer Out-Parameters (Go); Mutable Default Arguments (Python).

## Test-code scope

Test files are **in scope** for every category except the two test-hunter claims:

- **Data Clumps in test setup** → test-hunter's Test Setup Duplication
- **Shared mutable state between tests** → test-hunter's Flaky Test Indicators

Everything else applies: a temporal-coupling trap in a test helper, feature envy in a fixture builder, and a
temporary field on a test harness type are all reportable here. Test paths are listed in each language reference,
whose scan profile enforces this split.

**One overlap to route deliberately.** Setup repeated across test files is test-hunter's Test Setup Duplication;
*unrelated responsibilities collected in one test-support module* is God Module here. Cross-reference; one site, one
finding.

## Severity and Impact

Every finding carries **both**. They answer different questions and routinely diverge. Calibrate both to the code's
criticality and change frequency: a smell in a prototype is less urgent than one in a payment system.

**Severity — behavioral risk if left as-is:**

- **Critical** — *actively producing wrong behavior* on a production path (swappable primitive IDs already mixed up;
  a mutable default already leaking state between calls). Smells are rarely Critical.
- **High** — a defect with likely user-visible, security, or reliability impact if left unaddressed.
- **Medium** — correctness or maintainability risk without imminent impact.
- **Low** — hygiene; no behavioral risk.

**Impact — how much the change is worth:** defect exposure reduced, cognitive burden reduced, affected surface.
Contextual; never derived from occurrence count or pattern alone. A data clump across 9 request-handler signatures is
High impact at Low severity: every handler author reads it.

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
   `git ls-files --cached --others --exclude-standard` (Scope records only their counts; the scans still search `.`):
   - `.go` → go
   - `.py`, `.pyi` → python
   - `.ts`, `.tsx`, `.mts`, `.cts` → typescript

   Every other extension — `.js`, `.jsx`, `.mjs`, `.cjs` included — is **excluded, not audited**: without a reference
   there is no eligibility rule, no scan set, no evidence form, no remedy vocabulary. Record
   `excluded — no reference for .<ext>: {count} files` in Scope, naming each extension.

3. **Load language references.** For every detected language, read `references/smell-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/smell-go.md`). **Fail closed:** if a required reference cannot be
   read, stop and report.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules to that
   language's files. These subsets are then immutable. Record in Scope: raw manifest count, each per-language
   eligible subset, exclusions, and `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only what each reference's eligibility section lists, and generated files identified by
   each reference's authoritative **in-file marker** — **never** by filename guessing. Scan globs in
   references are approximations for scanning convenience; reporting eligibility uses the marker rule.

   Write each subset to `<run>/<lang>.txt` (`go.txt`, `python.txt`, `typescript.txt`). Codebase mode: the single line
   `.`. Diff and path mode: the eligible files, one per line — `comm -12 <(rg --files --type <t> $EXCLUDE | sort)
   <(printf '%s\n' $SCOPE | sort)` with the loaded reference's `--type` and `$EXCLUDE`, minus files carrying a
   generated-code marker (`| while read -r f; do rg -q -m1 '<marker>' "$f" || echo "$f"; done`, the marker regex built
   from the reference's eligibility section); the reference's generated-file globs are the same scan approximation a
   codebase run uses. Filter before scanning: `rg` applies `--type` and `--glob` only while walking a folder and
   searches every file named on its command line. Each scan call restores its list first — `GO_FILES=$(cat
   <run>/go.txt)` (`PY_FILES`, `TS_FILES`) — and the reference blocks pass it as `rg -H … -- $GO_FILES`: given one file,
   `rg` prints no file name unless `-H` is set.

   If **nothing** eligible remains: write `Audit completed: 0 findings — no eligible source in scope` and stop
   before scanning.

   **Two surfaces.** Findings are reported only against the **target scope** — every finding anchors (`file:line`)
   there. Related files may still be *read* as **context**: judging Feature Envy or a Data Clump routinely requires
   reading the envied type's module.

5. **Read repository instructions** when present (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`, convention docs) for
   stated design decisions, framework constraints, and naming conventions. Then name the project's core
   entities, value objects and operations, and its conventions for type design and module organization; Anemic
   Domain Model, Primitive Obsession, and God Module judgment uses this list.

### Phase 2: Scan for Smell Candidates

Scan hits **nominate** candidates; Phases 3–5 decide. For each loaded reference, run its Phase 2 scan block against
that language's eligible list from Phase 1 step 4, and judge each candidate under the rules of its own file's
language — including language-only categories the reference appends.

Done when every scan in each loaded reference's Phase 2 block has run and every hit — each `comments-<lang>.txt`
read page by page to its last line — is listed as a candidate.

### Phase 3: Evaluate Feature Envy and Data Clumps

For every Feature Envy candidate, open the body and count the members it touches on its own state versus the foreign
type (the Own/Foreign column). For every Data Clumps candidate, open every signature that carries the group and count
its parameters as written.

Done when every Feature Envy candidate has its own/foreign count and every Data Clumps candidate its per-signature
count, or is dropped under its category's Not-a-finding line.

### Phase 4: Evaluate Shotgun Surgery — once per audit

Run the pipeline in `references/history.md` once — git history has no language dimension. The signal is many
*unrelated* areas changing together for one logical change, not churn on a single file. Anchor each finding by the
Shotgun Surgery evidence rule.

### Phase 5: Evaluate Each Finding

**Reporting gate.** Report only when the smell points at a design problem worth naming — the proposed change reduces
misplacement, scattering, or hidden coupling enough to outweigh its churn.

For each candidate: apply the general Not-a-finding list and the category's own Not-a-finding line first; confirm
the category is applicable to that file's language; clear the gate; then apply the per-category evidence bar from
What to Hunt. Run each loaded reference's Phase 5 block for its language-only categories and language-specific
judgment.

Assign **Severity and Impact** to every finding. Nothing is held back; `Audit completed: N findings` counts every
reported finding.

Done when every candidate is a reported finding, dropped under a named Not-a-finding line or the reporting gate, or
routed to its owning hunter.

### Phase 6: Produce Report

Save as `YYYY-MM-DD-smell-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line` with the exact code.
- **Respect the language.** Idiomatic constructs are not smells. Calibrate to the audited language's conventions —
  the reference carries the calibration — not to patterns from another language.
- **Routing.** Each category's **Ownership:** note is authoritative where ownership is contested; follow it.
  Cross-reference the sibling by skill and exact category name, and leave its scoring to it.
- **Score behavior, not API churn.** When a recommendation would affect serialization behavior, introduce import
  cycles, or collide with a framework constraint, note the risk in the Action column — those are *behavior*. A change
  to exported API shape leaves the finding's severity and timing unchanged: never downgrade, defer, or soften on it.
