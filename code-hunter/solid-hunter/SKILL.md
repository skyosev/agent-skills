---
name: solid-hunter
description: |
  Use when reviewing Go, Python, or TypeScript code for SOLID violations: responsibility
  sprawl, rigid extension points, broken substitution, fat interfaces, and self-instantiated
  dependencies. Sharpening package, class, and interface design before extension, reducing
  coupling between units, or improving testability. Defaults to the codebase.

  Covers one unit serving several actors, variant dispatch scattered across an open set,
  implementors that cannot honor the contract they claim, interfaces forcing consumers to
  carry capabilities they never call, and units that build or globally read their own I/O
  dependencies.
disable-model-invocation: true
---

# SOLID Hunter

Audit code for **design that resists change** — a unit serving two actors at once, a variant set whose every addition
edits the same scattered dispatch sites, an implementor that cannot honor the contract it claims, an interface that
forces its consumers to carry capabilities they never call, a unit that builds its own database client instead of
receiving it. Goal: **units have one set of stakeholders, variants extend without editing existing dispatch,
implementors honor what their abstraction promises, consumers depend only on the capabilities they use, and
collaborators arrive from outside.**

Supports Go, Python, TypeScript via per-language reference files.

**Not covered (owned by other hunters):** whether an abstraction should exist at all, function-body mixed concerns,
boolean parameters dispatched at one site (→ simplicity-hunter); file-level accumulation, misplaced entity
transitions, a class that should be a function, the *write* to a mutable global (→ smell-hunter); exhaustiveness arms
and narrowing on data variant sets (→ invariant-hunter); import direction between layers and external types in domain
signatures (→ boundary-hunter); package naming and directory legibility (→ boundary-hunter); test design
(→ test-hunter); AI-generated noise and cosmetic style (→ slop-hunter). Where ownership is *contested*, the
category's **Ownership:** note in What to Hunt is authoritative.

## When to Use

- Sharpening package, class, and interface responsibilities after prototyping
- Preparing a codebase for extension with new variants or strategies
- Reducing coupling between services, packages, or layers
- Improving testability by moving collaborators out of constructors
- Reviewing a type hierarchy or interface set before a refactor

## Quick Reference

Full rules in **What to Hunt**; every finding must also clear Not-a-finding and the category's evidence bar. Category
names are canonical: the heading here, in What to Hunt, and in the report are identical. The *unit* each category is
judged on is named per language (see Applicability).

| Category | Core signal | Action | Belongs to another hunter |
| -------- | ----------- | ------ | ------------------------- |
| Responsibility Sprawl (SRP) | One unit serves two or more actors with independent reasons to change | Extract per actor; the original delegates or dissolves | File-level accumulation → smell-hunter (God Module); a class that should be a function → smell-hunter (Class Abuse); a *function body* mixing fetch, transform and persist → simplicity-hunter (Mixed Concerns); package naming → boundary-hunter |
| Rigid Extension Points (OCP) | Adding a variant to an **open** set edits two or more dispatch sites beyond the variant's definition | The smallest seam that removes the per-site edit | Non-variant scattering → smell-hunter (Shotgun Surgery); a missing exhaustiveness arm → invariant-hunter (Leaky Discriminated Unions); a boolean dispatched at one site → simplicity-hunter (Over-Parameterized APIs) |
| Broken Substitution (LSP) | An implementor fails the contract its abstraction promises, or a consumer carries a compensating branch for one implementor | Narrower abstraction or composition; the type stops claiming what it cannot honor | Narrowing on a **data variant set**, and assertions from `any` / open data → invariant-hunter |
| Fat Interfaces (ISP) | An interface with a **live seam** forces a production consumer to depend on unrelated capabilities it never calls | Split into role interfaces; Go: define at the consumer | No live seam — should it exist at all? → simplicity-hunter (Unnecessary Abstractions; Go Interface Pollution) |
| Concrete Dependency Chains (DIP) | A unit self-instantiates a service dependency that does I/O, or reads a module/package-level one instead of receiving it | Accept the concrete dependency in the constructor | The *write* to a global after initialization → smell-hunter (Mutable Global State); import direction between layers → boundary-hunter |

Hunter names are unsuffixed end-state names. Until consolidation completes, live skills are language-suffixed
(`boundary-hunter-go`, `test-hunter-py`, `type-hunter-ts`, and so on).

## Core Principles

1. **Single Responsibility (SRP).** A unit should have one set of stakeholders. Its evidence is *named actors* —
   persistence, transport, billing rules, notification — not method count. Two responsibilities that always change
   together are one responsibility.

2. **Open/Closed (OCP).** A variant set that has already paid the extension cost should stop paying it. The finding is
   not "a switch exists"; it is "this set is open, and each addition edits the same scattered sites".

3. **Liskov Substitution (LSP).** An implementor must honor what its abstraction promises. A promise is shown by the
   contract's documentation, its abstract method's stated behavior, or a consumer that relies on it — a method's name
   alone is not a promise.

4. **Interface Segregation (ISP).** No consumer should be forced to depend on capabilities it never calls. Width is
   judged per affected consumer, at an interface that has a live seam; whether the interface should exist at all is a
   different question and a different hunter's.

5. **Dependency Inversion (DIP).** A unit should receive its collaborators, not build them. The finding is
   *self-instantiation* of an I/O dependency, and the remedy is injecting the concrete type — an abstraction only when
   a second implementation or a test double already exists.

6. **Pragmatism over dogma.** SOLID manages change; it does not chase purity. A cohesive aggregate with fourteen
   methods, an interface every consumer uses fully, a closed variant set switched in three places — none is a finding.
   A candidate that fails its evidence bar is withdrawn, not reported at Low.

7. **Respect the language.** Go's small consumer-defined interfaces, composition over inheritance, and explicit
   `main()` wiring are the language working as designed; so are Python's duck typing and TypeScript's structural
   typing. Calibrate to the audited language, never to transplanted Java/C# patterns. Framework-mandated shapes are
   exempt only when the construct is named.

8. **Scans nominate; reading decides.** Nothing is a finding until implementors, consumers, and the composition roots
   have been read. A `&X{}` match, a `switch`, an `isinstance` is a location to inspect, never evidence.

## Terms

- **Unit** — the construct a principle is judged on in a given language. Go: package (SRP), struct (SRP, DIP),
  interface (ISP, LSP). Python: class (SRP, DIP), ABC/Protocol (ISP, LSP). TypeScript: class (SRP, DIP), `interface`
  and abstract class (ISP, LSP). Named in each language reference; the category names are unit-neutral.
- **Actor** — a stakeholder or concern whose requests change the code: persistence, transport, billing rules,
  notification. SRP's evidence is *named actors*, never method count.
- **Service dependency** — a collaborator that represents behavior (client, repository, gateway, clock, mailer).
  Distinguished from a **value** (DTO, dataclass, struct literal, builder, slice, map), whose direct construction is
  never a DIP finding.
- **Composition root** — a function that builds dependencies and passes them *into other units' constructors*, and
  never stores or calls them itself: Go `main()`, wire/fx providers; Python app factory, container module, `Depends`
  providers; TypeScript entry point, Nest module, container registration. Direct instantiation there is wiring, never
  a finding. The distinguishing evidence is **who keeps the object**: a root hands it on; a unit's own constructor
  (`NewSvc`, `__init__`, `constructor`) that builds a service and stores it in the unit's field is
  self-instantiation, whatever file it lives in.
- **Contract type vs data variant** — the LSP/invariant ownership test. A *contract type* is a behavioral abstraction
  with methods (interface, ABC, Protocol, abstract class). A *data variant set* is a union of shapes (TypeScript
  discriminated-union members, `Literal`-discriminated dataclasses, Go tagged structs). Consumer narrowing on a
  contract type to special-case an implementor is here; narrowing on a data variant set is invariant-hunter's. For a
  base class carrying both fields and methods: if the base declares abstract or overridable behavior the consumer
  calls, it is a contract type; a dataclass hierarchy with no overridable methods is a data variant set.
- **Open variant set** — the OCP evidence test. A set is *open* when **this set** has paid the extension cost: a
  variant added in history (`git log -S` on the discriminant) touched two or more of the listed dispatch sites, or the
  diff under review adds a variant and touches them now. A sibling registry elsewhere, a plugin architecture in
  another subsystem, or a discriminant sourced from configuration or external input *nominates* the history check;
  none proves that this set needs an extension point. Exhaustiveness is a separate property: a set can be open and
  still carry `assertNever` arms at every site. The arms make each addition a compile error; they do not remove the
  cost of editing every site. Missing exhaustiveness is invariant-hunter's; extension cost is here; the same union can
  carry one finding of each, at different anchors.
- **Existence vs width** — the ISP/simplicity ownership test for an interface. An interface with **no live seam**
  raises an existence question: simplicity's. A seam is *live* when a production consumer receives the interface from
  outside — through handwritten wiring or a container, the mechanism is irrelevant — or when a second implementation
  or a test double exists. Everything else (an interface only ever returned by the code that implements it, or never
  held as a parameter or field) is an existence question. **Width** is judged per affected consumer: a consumer forced
  to depend on capabilities it never calls that are *unrelated* to the ones it does (write alongside read, admin
  alongside runtime). One consumer using everything does not erase the finding; the Action keeps a composite for it
  and adds role interfaces for the others. A fake stubbing members is supporting evidence, never the sole proof.
- **Self-instantiation** — a type creating its own service dependency inside a constructor or method, or reading a
  module/package-level service instead of receiving it. The DIP finding. A service dependency here does I/O or holds
  process-external state: database, network, filesystem, queue, clock, randomness. A pure in-process helper (parser,
  formatter, validator) constructed internally is not one. Nor is a stdlib handle opened and closed inside one method
  on a path or address the method received (`os.Open(path)`, `open(path)`): that is resource use, not a collaborator.
- **Compensating branch** — a consumer branch that exists because one implementor cannot honor the contract (skip the
  transaction for `InMemoryRepo`, catch the not-implemented error from `ReadOnlyStore`). The consumer form of the LSP
  finding. Distinct from **capability dispatch**: checking for an optional interface and falling back to the base
  contract when absent (`io.WriterTo` in `io.Copy`) is the language working as designed.
- **Target scope and context** — findings anchor in the manifest; implementors, consumers, and test doubles outside it
  are read to judge them.

## Not a finding on these grounds alone

Conditionals, not category exemptions — each states what does **not** justify a finding and, where one exists, what
would:

- **A cohesive aggregate with many methods.** Methods that all operate on the same data for one workflow, or form one
  transaction boundary (mutation + rule + audit that are inseparable), are one responsibility. *Is* a finding when two
  named actors can change independently.
- **Value types, DTOs, dataclasses, config objects, builders** — they are the data; never DIP or ISP subjects. Direct
  construction of them is never self-instantiation.
- **Functional-style code** — plain functions and closures are not struct/class subjects: no DIP, ISP, LSP, or
  struct-level SRP finding demands that objects be introduced. Recorded as architecture style. Go package-level SRP
  still applies: a package of functions serving persistence AND transport AND rules is Responsibility Sprawl at the
  package unit regardless of style.
- **Exhaustiveness arms** — their presence or absence never decides OCP. A missing arm is invariant-hunter's. A set
  with arms at every site is still Rigid Extension Points when it is open and dispatch is scattered; a set with no
  evidence of openness is not a finding however many sites switch on it — withdraw, do not report at Low.
- **Capability dispatch with a fallback** — checking for an optional interface (`io.WriterTo`, a `Flusher`, a
  `SupportsBatch` Protocol) and falling back to the base contract when absent. Not Broken Substitution. *Is* when the
  branch exists because an implementor cannot honor what the base contract promises.
- **A concrete-type check that only unlocks an extra** (`if pg, ok := store.(*PostgresStore); ok { pg.Vacuum() }`
  where `Vacuum` is outside `Store`'s contract) — not Broken Substitution: nothing in the contract is broken. Not DIP
  either: the consumer constructs nothing and reads no global. No finding.
- **A single dispatch site consuming a foreign result type** to answer its own question — one site is not scattered
  dispatch, and a registry for one consumer is gold plating.
- **Heterogeneous dispatch arms** — sites that serve different consumers with deliberately different answers do not
  consolidate (the registry gate). Recommend exhaustiveness at each site, not a registry. Not a Rigid Extension Points
  finding.
- **Direct instantiation in a composition root** — wiring, in every language. Also: a constructor parameter *typed* as
  a concrete class is not a finding by itself; it is a finding only when the unit **creates** the dependency.
- **A constructor parameter a named framework construct injects** (Nest `@Injectable` constructor injection, FastAPI
  `Depends`, wire/fx providers) — the container is the composition root. The construct must be named; "this project
  uses Nest" is not evidence.
- **A method shape a named framework construct prescribes** (Django class-based view handlers, Angular lifecycle
  hooks) — the member's existence and signature are exempt. Its body is evaluated normally: a `get()` that also sends
  email and writes an audit log is sprawl in the body — simplicity-hunter's Mixed Concerns — not a mandated shape.
  *Is* a Responsibility Sprawl finding when members *outside* the prescribed shape serve a second actor.
- **An interface with no live seam** (never received by a consumer from outside, no double, one implementation) —
  simplicity-hunter's (should it exist?). Never a Fat Interfaces finding here.
- **Narrowing on a data variant set** — invariant-hunter's, whether guarded or not.
- **A global service that is written after initialization** — the write is smell-hunter's Mutable Global State at the
  declaration/write site. The *read inside a unit's logic* is Concrete Dependency Chains here, anchored at the
  consumer. Two anchors, one finding each, cross-referenced; neither reports the other's site.
- **Go small interfaces defined at the consumer, composition over inheritance, explicit `main()` wiring** — the
  language working as designed.
- **A pattern in a test file** — never a finding; test files are out of scope, not exempt (see Test-code scope).

## What to Hunt

Categories are named, not numbered. Cross-references use category names (e.g. "→ Fat Interfaces").

### Responsibility Sprawl (SRP)

One unit serving two or more actors with independent reasons to change.

**Signals** — every one of them *nominates*; none is a threshold:

- Many public methods spanning unrelated concepts
- Many constructor dependencies
- Imports from many unrelated modules or packages (persistence, HTTP, formatting, crypto)
- Vague names with broad scope: `Manager`, `Handler`, `Service`, `Utils`, `Helper`
- Methods that do not share the unit's fields — half the methods untouched by half the state
- Go adds the **package** unit: a package serving persistence AND transport AND rules
- A test that needs many mocks to run the unit (read from context; test-hunter already points here)

**Evidence bar:** name each actor and the members belonging to it, and give a change scenario for one actor that
touches members belonging to another.

**Action:** extract per actor; the original delegates or dissolves.

**Ownership:** split by unit. A class (and, in Go, a package or struct) serving two actors is here. A *file*
accumulating unrelated responsibilities is smell-hunter's God Module. A class that should be a function is
smell-hunter's Class Abuse; the placement of entity transitions is smell-hunter's Anemic Domain Model. A *function
body* mixing fetch, transform and persist is simplicity-hunter's Mixed Concerns. Package *naming and directory
legibility* (`util`, `common`, name/directory mismatch, `models` of unrelated domains) is boundary-hunter's; Go
package-level responsibility analysis stays here. Until boundary-hunter unifies, its Go §7 signal "multiple files in
a package spanning unrelated concerns" double-owns this; cross-reference rather than suppress.

### Rigid Extension Points (OCP)

Adding a variant to an **open** set requires editing two or more dispatch sites beyond the variant's definition.

**Signals:**

- `switch` / `if-elif` / `if-else` on a discriminant in several sites
- A factory with a growing switch and no registration mechanism
- Hard-coded strategy selection (`if typ == "email" { sendEmail() } else if typ == "sms" { sendSMS() }`)
- A **boolean parameter** is a two-member discriminant and meets exactly the same bar: its choice dispatched at two or
  more sites, the set shown open. There is no separate boolean path and no "will grow" carve-out

**Evidence bar:** list **every** dispatch site (enumerated project-wide, not from the manifest alone); show the arms
share **one responsibility** (the registry gate); show the set is **open** by the history test — a variant added in
history touched two or more of the listed sites, or the diff under review adds one and touches them now. No openness
evidence, no finding: withdraw, do not report at Low.

**Registry gate.** A registry or dispatch table is the remedy only where the scattered arms share one responsibility —
near-identical bodies answering the same question. Sites that serve different consumers with deliberately different
answers (one resolves a template, one a rate limit, one an icon) do not consolidate: a record spanning them becomes a
heterogeneous bag of weak callbacks. There, recommend the cheap standalone fix — exhaustive dispatch with
`assertNever`-style arms so the next variant is a compile error — and raise no finding here.

**Action:** the smallest seam that removes the per-site edit — a lookup table when the arms only select a value, a
shared function when the arms differ by one call, an interface with one implementation per variant only when the arms
carry behavior. The Action states **what each added concept removes**, so the net benefit is defensible: an interface,
N implementations and a registry replace one switch with N+2 units, and a remedy that cannot argue the net is not
recommended — the finding then names the cost instead.

**Ownership:** three-way split by the openness test. Here: scattered dispatch on an **open variant set** whose arms
share one responsibility. smell-hunter's Shotgun Surgery keeps **non-variant** scattering — adding a field touches
mappers, validators and serializers; a config concept spanning layers; a rename that is find-and-replace — including
scattering only git history reveals. invariant-hunter keeps **exhaustiveness**: the missing arm, no design change. The
last two are orthogonal to this one; a single union can carry one finding of each at different anchors. A boolean
dispatched at one site is simplicity-hunter's Over-Parameterized APIs however likely it looks to grow.

### Broken Substitution (LSP)

An implementor fails the contract its abstraction promises, or a consumer carries a compensating branch for one
implementor.

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

**Action:** a narrower abstraction or composition — the type stops claiming what it cannot honor. Where the consumer
branch stays for now, the Action names the guard form; guardedness is a note, never a second finding.

**Ownership:** the contract-type vs data-variant test (see Terms). Narrowing on a contract type to special-case an
implementor is here, **whatever the guard form** — a bare `x.(T)` in that role is one Broken Substitution finding with
the guard noted in Action, not an additional invariant-hunter finding. Narrowing on a data variant set, and assertions
from `any` / open data (JSON, config, `interface{}` payloads), stay invariant-hunter's. Capability dispatch and
concrete checks that only unlock an extra are not findings (see Not-a-finding).

### Fat Interfaces (ISP)

An interface with a live seam forces a production consumer to depend on unrelated capabilities it never calls.

**Signals:**

- Consumers calling a small subset of a wide interface
- Read and write bundled where some consumers only read; runtime and admin capabilities on one type
- One interface for an entire subsystem
- Implementors or fakes carrying stubs (supporting evidence only)
- A consumer-side interface mirroring a dependency's full API — only when the existence test routes it here

**Evidence bar:** name **each affected consumer** and the subset it calls, and the unrelated capabilities it is forced
to carry. A stubbing implementor or fake is supporting evidence, never the sole proof: a fake stubbing seven members
with a single consumer that uses all twelve proves nothing about production width.

**Action:** split into role interfaces; in Go, define them at the consumer. One consumer that uses everything keeps a
composite; the others get role interfaces.

**Ownership:** the existence-vs-width test (see Terms). No live seam → simplicity-hunter (Unnecessary Abstractions;
in Go, Interface Pollution) — an existence question, never a finding here. Live seam → here, judged per affected
consumer.

### Concrete Dependency Chains (DIP)

A unit self-instantiates a service dependency that does I/O, or reads a module/package-level one instead of receiving
it.

**Signals:**

- `new X()` / `X()` / `&X{}` / `pkg.X{}` / `NewX()` of a **service** inside a constructor or method
- `self.client = EmailClient()` in `__init__`; `this.mailer = new SmtpMailer()` in a constructor
- A package/module-level service read inside business logic
- Static or classmethod calls to a concrete utility that holds state or does I/O

**Evidence bar:** name the instantiation or global-read site inside the unit; show the dependency does I/O or holds
process-external state; confirm the unit is **not** a composition root (who keeps the object — see Terms); and state
**what the caller cannot control as a result**: the configuration or endpoint chosen inside, the clock or randomness,
the lifecycle of a shared resource.

**Action:** accept the concrete dependency in the constructor. Recommend an **abstraction** only when a second
implementation or a test double already exists — naming an imagined double does not justify one. In Go a concrete
pointer parameter cannot accept a fake, so the Action states that a future double will need a consumer-defined
interface, introduced with the test that needs it: a recorded consequence, not a recommendation.

**Ownership:** type-level wiring only. Import direction between layers, and external types in domain signatures, are
boundary-hunter's Dependency Direction Violations and Missing Abstraction Over Externals — a domain module importing a
driver package directly, with no instantiation inside a type, is not a finding here. Whether a *resulting* interface
should exist is simplicity-hunter's question, which this category answers in advance by injecting the concrete type.
The **write** to a global after initialization is smell-hunter's Mutable Global State at the global's own site; the
**read inside a unit's logic** is here, anchored at the consumer.

### Within-skill routing — Broken Substitution vs Fat Interfaces

The same stub fires both: `ReadOnlyStore.Save()` panicking is an implementor failing its contract (LSP) and an
interface forcing a stub (ISP). Each category clears its own bar first; a site that clears neither is no finding. When
both clear:

- **Broken Substitution** when the implementor is held as the abstraction by some consumer. Reachability of the broken
  member sets Severity (High reached, Medium held but unreached) — it does not decide ownership.
- **Fat Interfaces**, anchored at the interface, when the implementor is never held as the abstraction and an affected
  consumer shows the split.

The Evidence cell of whichever is reported names the other reading in one clause, so the reader sees why it was not
chosen. One finding per site.

## Applicability

All five categories are universal and applicable in every supported language; what changes is the **unit**. **A
language with no reference is not supported** — its files are excluded, never implicitly audited.

| Category | Go | Python | TypeScript |
| -------- | -- | ------ | ---------- |
| Responsibility Sprawl (SRP) | yes — **package** and struct | yes — class | yes — class |
| Rigid Extension Points (OCP) | yes — any discriminant, booleans included | yes | yes |
| Broken Substitution (LSP) | yes — interface implementations (no inheritance; implicit satisfaction is the risk) | yes — ABC/Protocol implementors and subclasses | yes — `interface` / abstract-class implementors and subclasses |
| Fat Interfaces (ISP) | yes — interface | yes — ABC/Protocol | yes — `interface`, abstract class |
| Concrete Dependency Chains (DIP) | yes — struct | yes — class | yes — class |

There are no language-only categories: no supported language has a SOLID defect the others lack, and none is invented.

## Test-code scope

**Test files are excluded from findings** — the same deviation invariant-hunter records. The design of a test class or
fixture is not a SOLID question. Test paths per language: Go `*_test.go`; Python `test_*.py`, `*_test.py`, `tests/`,
`conftest.py`; TypeScript `*.test.*`, `*.spec.*`, `*.e2e.*`, `__tests__/`. The exclusion is **by path**: a production
helper under `tests/` is not audited.

Test files are **read as context**:

- A hand-written double proves a seam is live — which routes an interface to Fat Interfaces rather than to
  simplicity-hunter.
- A fake with ten no-op members supports a width finding the production consumers must carry on their own.
- A test that patches a module-level client in order to construct a unit confirms self-instantiation and records the
  friction in the Evidence cell.

Test evidence never raises Severity. Cite the test file in the Evidence cell; anchor the finding at the production
type.

## Severity and Impact

Every finding carries **both**, per the sibling definitions. They answer different questions and routinely diverge.

**Severity — behavioral risk if left as-is:**

- **Critical** — all four parts named: the triggering call, the violated contract, the downstream consequence (data
  loss, crash, corrupted state), and why nothing contains it. A `Save` that silently no-ops on an implementor a
  production write path reaches, with the caller reporting success. A reachable throw that a caller catches and
  handles is not Critical. **Only Broken Substitution can reach Critical.**
- **High** — a Broken Substitution awaiting its first call: the implementor is registered or injected as the
  abstraction and a consumer path reaches the broken member; the consequence is stated, or stated as unknown.
- **Medium** — the default for the other four categories once they clear their evidence bar, and for a Broken
  Substitution whose break is not reachable through the abstraction today.
- **Low** — a finding that clears its bar with the smallest consequence: one affected consumer carrying one unused
  member; a hidden clock or random source with no configuration behind it.

A pattern that fails its evidence bar or matches a Not-a-finding conditional produces **no finding at any severity**.
Test friction (patching, skipping) is Evidence and raises Impact; it never sets Severity. Severity is never a
confidence scale: an uncertain finding is withdrawn, not downgraded.

**Impact — how much the change is worth:** contextual, never derived from method or site count. A sprawl in the type
every handler touches is High impact at Medium severity.

- **High** — substantial reduction on code read or changed often
- **Medium** — clear improvement on a moderately reached surface
- **Low** — clears the evidence bar but touches a small, rarely hit surface

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
   BASE=$(git symbolic-ref -q refs/remotes/origin/HEAD | sed 's@^refs/remotes/@@')
   git rev-parse -q --verify "$BASE^{commit}" >/dev/null 2>&1 || BASE=
   if [ -z "$BASE" ]; then
     for b in origin/main origin/master main master; do
       git rev-parse -q --verify "$b^{commit}" >/dev/null && BASE=$b && break
     done
   fi
   # BASE still empty: STOP and ask for an explicit base. Do not continue.
   MB=$(git merge-base "$BASE" HEAD) || exit 1                        # STOP: no merge base
   CHANGED=$(git diff --name-only --diff-filter=d "$MB") || exit 1    # STOP: diff failed
   UNTRACKED=$(git ls-files --others --exclude-standard) || exit 1    # STOP: ls-files failed
   DELETED=$(git diff --name-only --diff-filter=D "$MB") || exit 1    # STOP: diff failed
   SCOPE=$(printf '%s\n%s\n' "$CHANGED" "$UNTRACKED" | sed '/^$/d' | sort -u)
   ```
   Every command that supplies audit data is checked; only the base-discovery probes may fail, because failure
   there means "try the next candidate". One diff from the merge base to the working tree covers committed, staged,
   and unstaged changes. A file that existed at the merge base and is gone from the working tree lands in
   `$DELETED`; a file added after the merge base and deleted again appears nowhere. A failed command is never an
   empty scope.

   If `$SCOPE` is empty, run no scans: write the report with "Audit completed: 0 findings — empty diff scope",
   listing `$DELETED` under "Deleted in diff" if non-empty, and stop. If the resolved surface exceeds the context
   budget, report the file count and ask to narrow or chunk.

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
   included — is **excluded, not audited**: without a reference there is no unit vocabulary, no eligibility rule, no
   scan set, no remedy vocabulary. Record `excluded — no reference for .<ext>: {count} files` in Scope, naming each
   extension.

3. **Load language references.** For every detected language, read `references/solid-<lang>.md` from the directory
   this SKILL.md was read from (e.g. `references/solid-go.md`). **Fail closed:** if a required reference cannot be
   read, **stop and report**; do not continue with the universal categories only.

4. **Derive per-language eligible subsets** by applying each reference's generated-code and vendoring rules **plus the
   test-path exclusion** to that language's files. These subsets are then immutable. Record in Scope: raw manifest
   count, each per-language eligible subset, exclusions with the test paths listed, and
   `References loaded: {go, python, typescript as present}`.

   Drop from eligibility only: vendored trees, lockfiles, Markdown-only inputs, test paths, and generated files
   identified by each reference's authoritative **in-file marker** — **never** by filename guessing.

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
   `Architecture style: {struct-based / class-based / mixed / functional (limited findings)}`. In a primarily
   functional codebase the struct/class categories fire only where structs, classes and interfaces exist, and Go
   package-level Responsibility Sprawl fires regardless.

**No toolchain step.** No supported language has a SOLID analyzer a project would configure; none is invented, and
nothing is installed. The report carries no Toolchain lines.

### Phase 2: Scan for Candidates

Scans produce **candidates only**. For each loaded reference, run its Phase 2 scan block against that language's
eligible subset (`SCOPE=.` in codebase mode). Pass an explicit path to **every** `rg` invocation. Diff mode nominates
from the working tree over the manifest files, not from added lines: design is a property of the current code.

### Phase 3: Enumerate Implementors, Consumers, and Dispatch Sites

Project-wide, regardless of scope — an interface's consumers and a discriminant's dispatch sites live outside any
diff. For each nominated unit:

- **Abstractions**: every implementor, every production consumer, every test double, and for each consumer the subset
  of members it calls.
- **Discriminants**: every dispatch site, and the history test — `git log -S '<discriminant value>'` (or the diff
  under review) to see whether a variant addition touched two or more of them.
- **Units**: every collaborator the unit stores, where each one is created, and which composition root (if any) builds
  it.
- **Actors**: who asks for changes to each member — inferred from the member's concern (persistence, transport,
  rules, notification), corroborated by history where it is available.

Structural typing bounds this phase: regex finds `implements` clauses and explicit subclassing only. Unannotated
structural implementors (TypeScript, Python `Protocol`) are found by reading the interface's consumers. Record in
Scope what was searched and that implementors outside the searched consumers — external packages included — are not
found; findings claim the enumerated set only.

### Phase 4: Evaluate Each Finding

For each candidate: apply **Not-a-finding** first; confirm the unit exists in that file's language (see
Applicability); apply the three ownership tests — contract type vs data variant, open vs closed, existence vs width —
and the within-skill routing between Broken Substitution and Fat Interfaces; then clear the category's evidence bar
from What to Hunt. Check repository policy: a `Policy:` line withdraws what it names. Run each loaded reference's
Phase 4 block for its language-specific judgment.

Assign **Severity and Impact** to every finding (both required; they diverge). One finding per site. Nothing is held
back; `Audit completed: N findings` counts every reported finding.

### Phase 5: Produce Report

Save as `YYYY-MM-DD-solid-hunter-audit-{model-name}.md` — `{model-name}` is the executing model's short name (e.g.
`fable-5`) — in the project's docs folder (or project root if none exists). A caller-specified output path or return
mode (e.g. the party-hunter orchestrator) overrides this default.

Read `references/report-format.md` for the report template and per-category table schemas.

## Red Flags — stop and re-check

| Thought | Reality |
| ------- | ------- |
| "This class has thirty methods — sprawl" | Name the actors and the members of each, and a change scenario for one that touches another's. No named actors, no finding. |
| "Seven switch sites — recommend a registry" | Do the arms share one responsibility with near-identical bodies? Heterogeneous consumers don't consolidate — recommend exhaustiveness per site and raise nothing here. |
| "Every site has an `assertNever` arm, so it's fine" | Arms never decide OCP. Is the set open, and is dispatch scattered? Then it is still a finding. |
| "The set obviously will grow" | Openness is shown, not predicted: a variant added in history touching two or more of these sites, or this diff doing it. Otherwise withdraw. |
| "There's a sibling registry elsewhere, so this set is open" | That nominates the history check; it proves nothing about *this* set. |
| "The consumer calls `isinstance(x, Y)` — LSP" | Contract type or data variant? And does the branch compensate for a broken promise, or just unlock an extra? |
| "It's a bare `x.(T)`, so invariant-hunter also scores it" | Narrowing on a contract type to special-case an implementor is one finding here, with the guard form noted in Action. |
| "This interface has twelve methods and one implementation — ISP" | Existence first: no live seam → simplicity-hunter. Live seam → name the affected consumers and their subsets. |
| "The fake stubs seven members — Fat Interfaces" | A fake is supporting evidence. Which *production* consumer is forced to carry what it never calls? |
| "The scan matched `&X{}` — DIP" | Is it a value type? Does it do I/O? Is the enclosing function a composition root? Does the unit *keep* it? |
| "It's built in `wiring.go`, so it's wiring" | Path decides nothing. Who keeps the object — handed on to another constructor (root) or stored in this unit's field (finding)? |
| "The constructor takes a concrete `*SmtpMailer`" | A concrete *parameter* is not a finding. Creation is. |
| "This project uses Nest, so the constructor is injected" | Name the construct — `@Injectable`, `Depends`, an fx provider. "Uses Nest" is not evidence. |
| "The implementor panics, so it's both LSP and ISP" | Each bar first, then the routing rule: held as the abstraction → Broken Substitution; never held → Fat Interfaces. One finding, the other reading named in Evidence. |
| "The domain package imports the Postgres driver" | Import direction is boundary-hunter's. No instantiation inside a type, no finding here. |
| "The unit reads a package-level `db`" | Finding here, anchored at the consumer. The `SetDB` that reassigns it is smell-hunter's — cross-reference, don't score it. |
| "The remedy is an interface plus five strategies plus a registry" | State what each added concept removes. If the net cannot be argued, name the cost instead and recommend nothing. |
| "I'm not sure, so I'll report it at Low" | Severity is not confidence. Withdraw it. |
| "The codebase is functional — I'll recommend introducing services" | Functional style is not a violation. Record the style; only Go package-level sprawl still fires. |
| "The report looks thin — I'll note what I checked and found clean" | Zero-finding sections are omitted. A thin report is a valid result. |
| "I'll just fix it while I'm here" | No code edits. The report is the deliverable. |
| "The language reference won't load — I'll do the universal categories only" | Fail closed. Stop and report. |

## Operating Constraints

- **No code edits.** Audit report only. Implementation is a separate step.
- **No empty finding sections.** Include only *categories* with findings. Omit a category heading, table, or list
  entirely when it would contain zero items — no empty tables, placeholder subsections, or negative statements like
  "none found" or "no issues". The Scope section is not a category and is filled in from the template every run,
  including the Architecture style line and any `Policy:` line.
- **Scope: type, interface, and package design for change.** A finding that doesn't answer "is this unit designed for
  change?" belongs to another hunter. Contested boundaries are resolved at the category that owns them: each
  **Ownership:** note in What to Hunt states what is kept here and what routes away.
- **Evidence required.** Every finding cites `file:line` (path form per the language reference) with the exact code,
  and the category's evidence cell — Actors, Dispatch sites, Violation, Evidence, Form — is filled, never inferred.
- **One finding per site.** When two categories describe the same code, pick the primary one and cross-reference. The
  Broken Substitution / Fat Interfaces routing rule is the worked example.
- **Pragmatism over dogma.** Flag design that creates real maintenance friction, not cosmetic deviation from a
  pattern. A unit with two responsibilities that always change together is fine; an interface every consumer uses
  fully is fine.
- **Respect the language.** Calibrate to the audited language's idioms — the reference carries the calibration — not
  to patterns transplanted from another. A framework-mandated shape is exempt only when the construct is named.
- **Handoff, not duplication.** When a candidate belongs to another hunter — an interface with no seam, a missing
  exhaustiveness arm, a mutable global's write site, an import-direction violation — cross-reference it and do not
  score it here.
