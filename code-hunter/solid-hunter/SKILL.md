---
name: solid-hunter
description: Audit Go, Python, or TypeScript code for design that resists change — responsibility sprawl, rigid extension points, broken substitution, fat interfaces, concrete dependency chains. Defaults to the codebase.
disable-model-invocation: true
---

# SOLID Hunter

Audit code for **design that resists change**, in the five SOLID categories below. A finding answers "is this unit
designed for change?"; anything else belongs to another hunter.

**Not covered (owned by other hunters):** whether an abstraction should exist at all, function-body mixed concerns,
boolean parameters dispatched at one site (→ simplicity-hunter); file-level accumulation, misplaced entity
transitions, a class that should be a function, the *write* to a mutable global (→ smell-hunter); exhaustiveness arms
and narrowing on data variant sets (→ invariant-hunter); import direction between layers and external types in domain
signatures (→ boundary-hunter); package naming and directory legibility (→ boundary-hunter); test design
(→ test-hunter); AI-generated noise and cosmetic style (→ slop-hunter). Where ownership is *contested*, the
category's **Ownership:** note in What to Hunt is authoritative. Cross-reference a candidate another hunter owns
instead of scoring it.

Hunter names are unsuffixed. A hunter not installed under that name is installed per language
(`perf-hunter-py`, `doc-hunter-py`, `security-hunter-ts`): route to the one matching the finding's language.

## Quick Reference

Category names are canonical: the heading here, in What to Hunt, and in the report are identical.

| Category | Core signal | Action |
| -------- | ----------- | ------ |
| Responsibility Sprawl (SRP) | One unit serves two or more actors with independent reasons to change | Extract per actor; the original delegates or dissolves |
| Rigid Extension Points (OCP) | Adding a variant to an **open** set edits two or more dispatch sites beyond the variant's definition | The smallest seam that removes the per-site edit |
| Broken Substitution (LSP) | An implementor fails the contract its abstraction promises, or a consumer carries a compensating branch for one implementor | Narrower abstraction or composition; the type stops claiming what it cannot honor |
| Fat Interfaces (ISP) | An interface with a **live seam** forces a production consumer to depend on unrelated capabilities it never calls | Split into role interfaces |
| Concrete Dependency Chains (DIP) | A unit self-instantiates a service dependency, or reads a module/package-level one instead of receiving it | Accept the concrete dependency in the constructor |

## Core Principles

1. **Scans nominate; reading decides.** Nothing is a finding until implementors, consumers, and the composition roots
   have been read. A `&X{}` match, a `switch`, an `isinstance` is a location to inspect, never evidence.

2. **Pragmatism over dogma.** SOLID manages change: report design that creates real maintenance friction. A cosmetic
   departure from a pattern is no finding.

3. **Respect the language.** Calibrate to the audited language's idioms; the loaded reference carries the
   calibration. Go's small consumer-defined interfaces, composition over inheritance, and explicit `main()` wiring,
   Python's duck typing, and TypeScript's structural typing are idiomatic, never findings.

## Terms

- **Unit** — the construct a category is judged on (package, struct, class, interface, ABC/Protocol, abstract class).
  Each language reference's Applicability table names it per category; the category names are unit-neutral.
- **Actor** — a stakeholder or concern whose requests change the code: persistence, transport, billing rules,
  notification. SRP's evidence is *named actors*, never method count.
- **Service dependency** — a collaborator that does I/O or holds process-external state: database, network,
  filesystem, queue, clock, randomness (a client, repository, gateway, mailer). Distinguished from a **value** (DTO,
  dataclass, struct literal, config object, builder, slice, map) and from a pure in-process helper (parser, formatter,
  validator): constructing either is never a DIP finding, and a value is never an ISP subject.
- **Composition root** — a function that builds dependencies and passes them *into other units' constructors*, and
  never stores or calls them itself: Go `main()`, wire/fx providers; Python app factory, container module, `Depends`
  providers; TypeScript entry point, Nest module, container registration. Direct instantiation there is wiring, never
  a finding. The distinguishing evidence is **who keeps the object**: a root hands it on; a unit's own constructor
  (`NewSvc`, `__init__`, `constructor`) that builds a service and stores it in the unit's field is
  self-instantiation, whatever file it lives in.

## Not a finding on these grounds alone

- **Functional-style code** — plain functions and closures are not struct/class subjects: no finding demands that
  objects be introduced. Record the style (Phase 1 step 6). In a primarily functional codebase Broken Substitution,
  Fat Interfaces, Concrete Dependency Chains, and struct/class-level Responsibility Sprawl fire only where structs,
  classes and interfaces exist; Rigid Extension Points and Go package-level Responsibility Sprawl fire regardless — a
  package of functions serving persistence AND transport AND rules is Responsibility Sprawl at the package unit.
- **A constructor parameter a named framework construct injects** (Nest `@Injectable` constructor injection, FastAPI
  `Depends`, wire/fx providers) — the container is the composition root. The construct must be named; "this project
  uses Nest" is not evidence.
- **A method shape a named framework construct prescribes** (Django class-based view handlers, Angular lifecycle
  hooks) — the member's existence and signature are exempt. Its body is evaluated normally: a `get()` that also sends
  email and writes an audit log is sprawl in the body — simplicity-hunter's Mixed Concerns — not a mandated shape.
  *Is* a Responsibility Sprawl finding when members *outside* the prescribed shape serve a second actor.

## What to Hunt

### Responsibility Sprawl (SRP)

One unit serving two or more actors with independent reasons to change. Two responsibilities that always change
together are one responsibility.

**Signals** — every one of them *nominates*; none is a threshold:

- Many public methods spanning unrelated concepts
- Many constructor dependencies
- Imports from many unrelated modules or packages (persistence, HTTP, formatting, crypto)
- Vague names with broad scope: `Manager`, `Handler`, `Service`, `Utils`, `Helper`
- Methods that do not share the unit's fields — half the methods untouched by half the state
- A test that needs many mocks to run the unit (read as context)

**Evidence bar:** name each actor and the members belonging to it, and give a change scenario for one actor that
touches members belonging to another.

**Not a finding:** a cohesive aggregate with many methods — methods that all operate on the same data for one
workflow, or form one transaction boundary (mutation + rule + audit that are inseparable). *Is* a finding when two
named actors can change independently.

**Action:** extract per actor; the original delegates or dissolves.

**Ownership:** split by unit. A class (and, in Go, a package or struct) serving two actors is here. A *file*
accumulating unrelated responsibilities is smell-hunter's God Module. A class that should be a function is
smell-hunter's Class Abuse; the placement of entity transitions is smell-hunter's Anemic Domain Model. A *function
body* mixing fetch, transform and persist is simplicity-hunter's Mixed Concerns. Package *naming and directory
legibility* (`util`, `common`, name/directory mismatch, `models` of unrelated domains) is boundary-hunter's Generic
Boundary Names; Go package-level responsibility analysis, including multiple files in a package spanning unrelated
concerns, stays here.

### Rigid Extension Points (OCP)

Adding a variant to an **open** set requires editing two or more dispatch sites beyond the variant's definition.

**Open variant set** — the OCP evidence test. A set is *open* when **this set** has paid the extension cost: a
variant added in history (the `git log -S` test, Phase 3) touched two or more of the listed dispatch sites, or the
diff under review adds a variant and touches them now. Openness is shown, never predicted. A sibling registry
elsewhere, a plugin architecture in another subsystem, or a discriminant sourced from configuration or external input
*nominates* the history check; none proves that this set needs an extension point.

**Signals:**

- `switch` / `if-elif` / `if-else` on a discriminant in several sites
- A factory with a growing switch and no registration mechanism
- Hard-coded strategy selection (`if typ == "email" { sendEmail() } else if typ == "sms" { sendSMS() }`)
- A **boolean parameter** — a two-member discriminant held to the same bar: its choice dispatched at two or more
  sites, the set shown open

**Evidence bar:** list **every** dispatch site (enumerated project-wide, not from the manifest alone); show the arms
share **one responsibility** (the registry gate); show the set is **open**. No openness evidence: withdraw.

**Registry gate.** A registry or dispatch table is the remedy only where the scattered arms share one responsibility —
near-identical bodies answering the same question. Sites that serve different consumers with deliberately different
answers (one resolves a template, one a rate limit, one an icon) do not consolidate: a record spanning them becomes a
heterogeneous bag of weak callbacks. There, recommend the cheap standalone fix — exhaustive dispatch with
`assertNever`-style arms so the next variant is a compile error — and raise no finding here.

**Not a finding:** exhaustiveness arms, present or absent. The arms make each addition a compile error; they do not
remove the cost of editing every site — an open set with arms at every site and scattered dispatch is still a finding,
and a set with no openness evidence is withdrawn however many sites switch on it. A single dispatch site consuming a
foreign result type to answer its own question — one site is not scattered dispatch, and a registry for one consumer
is gold plating.

**Action:** the smallest seam that removes the per-site edit — a lookup table when the arms only select a value, a
shared function when the arms differ by one call, an interface with one implementation per variant only when the arms
carry behavior. The Action states **what each added concept removes**, so the net benefit is defensible: an interface,
N implementations and a registry replace one switch with N+2 units, and a remedy that cannot argue the net is not
recommended — the finding then names the cost instead.

**Ownership:** three-way split by the openness test. Here: scattered dispatch on an **open variant set** whose arms
share one responsibility. smell-hunter's Shotgun Surgery keeps **non-variant** scattering — adding a field touches
mappers, validators and serializers; a config concept spanning layers; a rename that is find-and-replace — including
scattering only git history reveals. invariant-hunter keeps **exhaustiveness**: the missing arm, no design change
(Leaky Discriminated Unions in Python and TypeScript; in Go no hunter scores it, see `solid-go.md`). The last two are
orthogonal to this one; a single union can carry one finding of each at different anchors. A boolean dispatched at
one site is simplicity-hunter's Over-Parameterized APIs.

### Broken Substitution (LSP)

An implementor fails the contract its abstraction promises, or a consumer carries a compensating branch for one
implementor.

**Contract type vs data variant** — the LSP/invariant ownership test. A *contract type* is a behavioral abstraction
with methods (interface, ABC, Protocol, abstract class). A *data variant set* is a union of shapes (TypeScript
discriminated-union members, `Literal`-discriminated dataclasses, a Go sealed interface over data structs). For a
base class carrying both fields and methods: if the base declares abstract or overridable behavior the consumer
calls, it is a contract type; a dataclass hierarchy with no overridable methods is a data variant set.

**Compensating branch** — a consumer branch that exists because one implementor cannot honor the contract (skip the
transaction for `InMemoryRepo`, catch the not-implemented error from `ReadOnlyStore`). The consumer form of the
finding.

**Signals:**

- Not-implemented / unsupported throws, raises, or panics in an implementing member
- A silent zero return or no-op instead of the promised behavior
- Narrowed preconditions — the implementor rejects input the abstraction accepts
- Widened error cases — the implementor fails where the contract implies success
- Consumer `isinstance` / `instanceof` / `x.(T)` / type switch **on a contract type** — this nominates only; the
  branch must *compensate* for a contract failure to be a finding

**Evidence bar:** name the promised behavior — shown by the contract's documentation, its abstract method's stated
behavior, or a consumer that relies on it; a method's name alone is not a promise — the implementor that breaks it and
how (throws/panics not-implemented, silent zero/no-op, narrowed input, widened errors), and whether a consumer holding
the abstraction has a path to the broken member. For the consumer form: the compensating branch, the guarantee it
gives up, and the implementor it compensates for.

**Not a finding:** capability dispatch with a fallback — checking for an optional interface (`io.WriterTo` in
`io.Copy`, a `Flusher`, a `SupportsBatch` Protocol) and falling back to the base contract when absent; *is* a finding
when the branch exists because an implementor cannot honor what the base contract promises. A concrete-type check
that only unlocks an extra (`if pg, ok := store.(*PostgresStore); ok { pg.Vacuum() }` where `Vacuum` is outside
`Store`'s contract) — nothing in the contract is broken, and the consumer constructs nothing and reads no global, so
it is no DIP finding either.

**Action:** a narrower abstraction or composition — the type stops claiming what it cannot honor. Where the consumer
branch stays for now, the Action names the guard form.

**Ownership:** narrowing on a contract type to special-case an implementor is here, **whatever the guard form** — a
bare `x.(T)` in that role is one Broken Substitution finding, the guard noted in Action, and the only finding at that
site. Narrowing on a data variant set, guarded or not, and assertions from `any` / open data (JSON, config,
`interface{}` payloads) are invariant-hunter's: Leaky Discriminated Unions in Python and TypeScript; in Go, Unguarded
Type Assertions judges only the guard (see `solid-go.md`).

### Fat Interfaces (ISP)

An interface with a live seam forces a production consumer to depend on unrelated capabilities it never calls.

**Existence vs width** — the ISP/simplicity ownership test for an interface. A seam is *live* when a production
consumer receives the interface from outside — through handwritten wiring or a container, the mechanism is
irrelevant — or when a second implementation or a test double exists. An interface with **no live seam** (only ever
returned by the code that implements it, or never held as a parameter or field) raises an existence question.
**Width** is judged per affected consumer: a consumer forced to depend on capabilities it never calls that are
*unrelated* to the ones it does (write alongside read, admin alongside runtime).

**Signals:**

- Consumers calling a small subset of a wide interface
- Read and write bundled where some consumers only read; runtime and admin capabilities on one type
- One interface for an entire subsystem
- Implementors or fakes carrying stubs (supporting evidence only)
- A consumer-side interface mirroring a dependency's full API — only when the existence test routes it here

**Evidence bar:** name **each affected consumer** and the subset it calls, and the unrelated capabilities it is forced
to carry. A stubbing implementor or fake is supporting evidence, never the sole proof: a fake stubbing seven members
with a single consumer that uses all twelve proves nothing about production width.

**Action:** split into role interfaces. One consumer that uses everything keeps a composite — it does not close the
finding; the others get role interfaces.

**Ownership:** no live seam → simplicity-hunter (Unnecessary Abstractions; in Go, Interface Pollution) — an existence
question, never a finding here. Live seam → here, judged per affected consumer.

### Concrete Dependency Chains (DIP)

A unit self-instantiates a service dependency — creates it inside a constructor or method — or reads a
module/package-level one instead of receiving it.

**Signals:**

- `new X()` / `X()` / `&X{}` / `pkg.X{}` / `NewX()` of a **service** inside a constructor or method
- `self.client = EmailClient()` in `__init__`; `this.mailer = new SmtpMailer()` in a constructor
- A package/module-level service read inside business logic
- Static or classmethod calls to a concrete utility that holds state or does I/O

**Evidence bar:** name the instantiation or global-read site inside the unit and the service dependency it creates or
reads; confirm the unit is **not** a composition root (who keeps the object — see Terms); and state **what the caller
cannot control as a result**: the configuration or endpoint chosen inside, the clock or randomness, the lifecycle of a
shared resource.

**Not a finding:** direct instantiation in a composition root — wiring, in every language. A constructor parameter
*typed* as a concrete class — the finding is the unit **creating** the dependency. A stdlib handle opened and closed
inside one method on a path or address the method received (`os.Open(path)`, `open(path)`) — resource use, not a
collaborator.

**Action:** accept the concrete dependency in the constructor. Recommend an **abstraction** only when a second
implementation or a test double already exists — an imagined double justifies none.

**Ownership:** type-level wiring only. Import direction between layers, and external types in domain signatures, are
boundary-hunter's Dependency Direction Violations and External Type Leaks — a domain module importing a
driver package directly, with no instantiation inside a type, is not a finding here. Whether a *resulting* interface
should exist is simplicity-hunter's question, which this category answers in advance by injecting the concrete type.
The **write** to a global after initialization is smell-hunter's Mutable Global State at the global's own site; the
**read inside a unit's logic** is here, anchored at the consumer. Two anchors, one finding each, cross-referenced.

### Within-skill routing — Broken Substitution vs Fat Interfaces

The same stub fires both: `ReadOnlyStore.Save()` panicking is an implementor failing its contract (LSP) and an
interface forcing a stub (ISP). Each category clears its own bar first. When both clear:

- **Broken Substitution** when the implementor is held as the abstraction by some consumer. Reachability of the broken
  member sets Severity (High reached, Medium held but unreached) — it does not decide ownership.
- **Fat Interfaces**, anchored at the interface, when the implementor is never held as the abstraction and an affected
  consumer shows the split.

The Evidence cell of whichever is reported names the other reading in one clause, so the reader sees why it was not
chosen.

## Applicability

All five categories apply in every supported language; only the unit changes (see Terms).

## Test-code scope

**Test files are excluded from findings.** Test paths are listed in each language reference. The exclusion is **by
path**: a production helper under `tests/` is not audited.

Test files are **read as context**:

- A hand-written double proves a seam is live — which routes an interface to Fat Interfaces rather than to
  simplicity-hunter.
- A fake with ten no-op members supports a width finding the production consumers must carry on their own.
- A test that patches a module-level client in order to construct a unit confirms self-instantiation and records the
  friction in the Evidence cell.

Cite the test file in the Evidence cell; anchor the finding at the production type.

## Severity and Impact

Every finding carries **both**.

**Severity — behavioral risk if left as-is:**

- **Critical** — all four parts named: the triggering call, the violated contract, the downstream consequence (data
  loss, crash, corrupted state), and why nothing contains it. A `Save` that silently no-ops on an implementor a
  production write path reaches, with the caller reporting success. A reachable throw that a caller catches and
  handles is not Critical. **Only Broken Substitution can reach Critical.**
- **High** — a reachable Broken Substitution short of the Critical bar: the implementor is registered or injected as
  the abstraction and a consumer path reaches the broken member; the consequence is stated, or stated as unknown.
- **Medium** — the default for the other four categories once they clear their evidence bar, and for a Broken
  Substitution whose break is not reachable through the abstraction today.
- **Low** — a finding that clears its bar with the smallest consequence: one affected consumer carrying one unused
  member; a hidden clock or random source with no configuration behind it.

A pattern that fails its evidence bar or matches a Not-a-finding conditional produces **no finding at any severity**.
Test friction (patching, skipping) is Evidence and raises Impact; it never sets Severity. Severity is never a
confidence scale: an uncertain finding is **withdrawn**, not downgraded.

**Impact — how much the change is worth:** contextual, never derived from method or site count. A sprawl in the type
every handler touches is High impact at Medium severity.

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
   included — is **excluded, not audited**: without a reference there is no unit vocabulary, no eligibility rule, no
   scan set, no remedy vocabulary. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming each
   extension.

3. **Load language references.** For every detected language, read `references/solid-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/solid-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus the
   test-path exclusion** to that language's files. A file counts as generated only by the reference's authoritative
   **in-file marker**, never by its filename. These subsets are then immutable. Record in Scope: raw manifest count,
   each per-language eligible subset, exclusions with the test paths listed, and
   `References loaded: {go, python, typescript as present}`.

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
   there. Files outside it, test files included, are *read* as **context**: enumerating an interface's consumers, an
   abstraction's implementors, or a discriminant's dispatch sites routinely leaves any diff scope. Diff and path scope
   narrow the manifest, never the context reading.

5. **Read repository instructions** (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) for stated policies: the architecture
   style the project chose, framework conventions, sanctioned wiring mechanisms, layers that are deliberately
   concrete. A stated policy is respected and acknowledged in the report's `Policy:` line.

6. **Identify the composition root(s) and the architecture style.** Roots are identified by **what a function does** —
   constructs, wires, returns or runs, decides nothing about the domain — not by path; `cmd/`, `main.go`, an app
   factory, a container module, a Nest module nominate the search. Existing wire / fx / container wiring is
   recognized as a root; neither is recommended for adoption. Record the style in Scope as
   `Architecture style: {struct-based / class-based / mixed / functional (limited findings)}`; a functional style
   limits which categories fire (see Not a finding: functional-style code).

### Phase 2: Scan for Candidates

For each loaded reference, run every scan in its Phase 2 block against that language's eligible list from Phase 1
step 4; each hit is a candidate. Diff mode nominates from the working tree over the manifest files, not from added
lines: design is a property of the current code.

Done when every scan in each loaded reference's Phase 2 block has run and every hit is listed as a candidate.

### Phase 3: Enumerate Implementors, Consumers, and Dispatch Sites

Project-wide, across the context surface (Phase 1 step 4, Two surfaces). For each nominated unit:

- **Abstractions**: every implementor, every production consumer, every test double, and for each consumer the subset
  of members it calls.
- **Discriminants**: every dispatch site, and the history test (or the diff under review) — did a variant addition
  touch two or more of them? `git log -S'<token>' --name-only --format='%h %ad %s' --date=short -- .`, where
  `<token>` is the variant as written at the dispatch sites: the enum member or constant name, or the literal without
  its quotes (so single- and double-quoted code both match). Pickaxe lists, per commit, only the files where that
  token's count changed; compare them with the dispatch-site list.
- **Units**: every collaborator the unit stores, where each one is created, and which composition root (if any) builds
  it.
- **Actors**: who asks for changes to each member — inferred from the member's concern (persistence, transport,
  rules, notification), corroborated by history where it is available.

Structural typing bounds this phase: regex finds `implements` clauses and explicit subclassing only. Unannotated
structural implementors (TypeScript, Python `Protocol`) are found by reading the interface's consumers. Record in
Scope what was searched and that implementors outside the searched consumers — external packages included — are not
found; findings claim the enumerated set only.

### Phase 4: Evaluate Each Finding

For each candidate: apply the general Not-a-finding list and the category's own **Not a finding:** line first; apply
the three ownership tests — contract type vs data variant (Broken Substitution), open variant set (Rigid Extension
Points), existence vs width (Fat Interfaces) — and the within-skill routing between Broken Substitution and Fat
Interfaces; then clear the category's evidence bar from What to Hunt, judged with the loaded reference's per-category
forms and framework carve-outs. A `Policy:` line (Phase 1 step 5) withdraws the pattern it names.

Assign **Severity and Impact** to every finding. `Audit completed: N findings` counts every reported finding.

Done when every candidate is a reported finding, a withdrawal, or a hand-off to its owning hunter.

### Phase 5: Produce Report

Save as `YYYY-MM-DD-solid-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in `docs/` (or the repository root when there is no `docs/`). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Operating Constraints

- **Report only.** The audit report is the deliverable; source files stay untouched.
- **Evidence required.** Every finding cites `file:line` with the exact code, and the category's evidence cell —
  Actors, Dispatch sites, Violation, Evidence, Form — is filled from code read in Phase 3: never left blank, never
  asserted without a cited member or site.
- **One site, one finding.** When two categories describe the same code, pick the primary one and cross-reference. The
  Broken Substitution / Fat Interfaces routing rule is the worked example.
