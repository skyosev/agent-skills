# SOLID Hunter — TypeScript reference

Language-specific rules for TypeScript.

## Applicability of the categories

| Category | Applicable | Unit | Note |
| -------- | ---------- | ---- | ---- |
| Responsibility Sprawl (SRP) | **yes** | class | A module of exported functions is functional style, not a class subject; record the style |
| Rigid Extension Points (OCP) | **yes** | any discriminant: a string-literal union, an enum, a `boolean` parameter | |
| Broken Substitution (LSP) | **yes** | `interface` and abstract-class implementors, and subclasses | Structural typing means a class can satisfy an interface with **no `implements` clause** |
| Fat Interfaces (ISP) | **yes** | `interface`, abstract class | Existence test decides ownership before width |
| Concrete Dependency Chains (DIP) | **yes** | class | |

No TypeScript-only categories.

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when identified by an authoritative in-file marker where one exists
(`// @generated`, `// Code generated`, `/* eslint-disable */ // prettier-ignore` headers emitted by a codegen tool,
GraphQL/protobuf codegen banners) — never by filename guessing. Scan globs such as `*.generated.*`, `__generated__/`,
`*.g.ts`, `generated/` are approximations for scanning convenience.

Dependency and build trees (`node_modules/`, `dist/`, `build/`, `.next/`, `out/`), lockfiles, and Markdown-only inputs
are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*.test.*`, `*.spec.*`, `*.e2e.*`, `__tests__/`. Test
files are still read as context — a hand-written fake proves a seam is live; a test that stubs seven members supports a
width finding.

## TypeScript principles

- **Structural typing is the default seam.** A class satisfies an interface by shape; a shape-compatible fake passes
  with no declaration. This is why injecting the concrete type is a sufficient DIP remedy here.
- **`interface` and `abstract class` are both abstractions.** An abstract class also participates in inheritance, so
  Broken Substitution covers both override contracts and interface satisfaction.
- **Enumeration is bounded.** `implements` clauses and `extends` edges are scannable; **unannotated structural
  implementors are not**. They are found by reading the consumers of the interface, and the report's Scope records the
  gap.
- **Composition roots are explicit or container-provided:** an entry point that constructs and passes, a Nest module's
  `providers`, an InversifyJS container binding, a factory module.

## Per-category TypeScript content

### Responsibility Sprawl — TypeScript forms

Many public methods spanning unrelated concepts; a constructor taking many collaborators; imports from unrelated
modules (ORM, HTTP client, template engine, crypto); vague names with broad scope (`Manager`, `Handler`, `Service`,
`Utils`, `Helper`); methods that never touch the class's fields. Name the actors and give the change scenario that
crosses them. Remedy vocabulary: extract a class per actor; the original delegates or dissolves.

### Rigid Extension Points — TypeScript forms

`switch` / `if-else` chains on a string-literal union or enum discriminant across several modules; a factory with a
growing `switch` and no registry; a `boolean` parameter selecting behavior at several sites. Remedy vocabulary,
smallest first: a `Record<Kind, X>` lookup when the arms select a value; one shared function when the arms differ by a
single call; an interface with one implementation per variant, dispatched through a `Record<Kind, Iface>`, only when
the arms carry behavior.

Exhaustiveness — `default: assertNever(kind)`, typescript-eslint's `switch-exhaustiveness-check` — is
invariant-hunter's and never decides openness here. Four sites that each end in `assertNever` are still a finding when
the set is open.

### Broken Substitution — TypeScript forms

- An override or implementor that throws `NotImplementedError` / `UnsupportedOperationError` on a member the base
  declares as working behavior
- An override that silently returns `null`, `undefined`, or an empty array instead of performing the base behavior
- An override that narrows accepted input, or throws where the base contract implies success
- A consumer branch that compensates: `if (repo instanceof InMemoryRepo) return; // no transactions`

The promise is shown by the interface's doc comment, the abstract method's stated behavior, or a consumer that relies
on it. `if (store instanceof PostgresStore) store.vacuum()` where `vacuum` is outside the contract unlocks an extra —
no finding. Narrowing on a **discriminated union** (`if (node.kind === 'leaf')`, `instanceof` over union members with
no shared behavioral contract) is invariant-hunter's, not here.

### Fat Interfaces — TypeScript forms

Count the declared members. The seam test comes first: an interface no production consumer receives from outside, with
one implementation and no double, is simplicity-hunter's Unnecessary Abstractions. A live seam plus consumers using
disjoint subsets is the finding here — and a Nest or Inversify token that resolves the interface makes the seam live.
Remedy vocabulary: split into role interfaces (`Reader`, `Writer`) and type each consumer with the slice it uses; the
consumer that needs everything keeps the composite.

### Concrete Dependency Chains — TypeScript forms

The finding is a class that **creates and keeps** a service: `this.mailer = new SmtpMailer(cfg.host)` in the
constructor, or a method that news a client per call. A module-level client read inside business logic
(`import { db } from './db'` then `db.query(…)` inside a method) is the global-read form, anchored at the reading
class.

Not findings: `new UserDto(...)`, `new Map()`, a builder, any value construction; `fetch(url)` inside one method on a
URL the method received; a constructor parameter *typed* as a concrete class. A `new Date()` or `Math.random()` inside
business logic is the **Low** form of this finding — a clock or random source the caller cannot control — reported
only when the Evidence names what that costs.

**Action:** accept the dependency as a constructor parameter. A shape-compatible fake already substitutes in
TypeScript, so an interface is recommended only when a second implementation or a test double already exists.

## Framework carve-outs — name the construct

- **NestJS `@Injectable()`** — `constructor(private mailer: SmtpMailer)` on an `@Injectable()` class is container
  injection: the module's `providers` array is the composition root, and a provider-resolved dependency counts as a
  live seam. A Nest service with thirty methods across four actors is still Responsibility Sprawl; only the injected
  constructor is exempt.
- **InversifyJS** — `@injectable()` / `@inject(TOKEN)` and `container.bind(...)`: bindings are roots.
- **Angular** — `@Component`, `@Directive`, and lifecycle hooks (`ngOnInit`, `ngOnDestroy`) prescribe the shape: the
  members' existence and signatures are exempt; their bodies are evaluated normally. Constructor injection through the
  Angular injector is container injection.
- **React** — hooks and components are functions; functional style, not class subjects.

Naming the construct is required. "This project uses Nest" does not exempt a service that news its own client.

## Evidence path form

Cite findings as `file/path.ts:line` (`.tsx`, `.mts`, `.cts` as applicable).

## Phase 2 — solid scans

Test files are **excluded** (see Test-code scope in SKILL.md). Every scan takes the eligible TypeScript list. **Scans
nominate only.**

```bash
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/build/** --glob !**/.next/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Responsibility Sprawl: classes and their constructors (then read the members and name the actors)
rg -n 'class\s+\w+' --type ts $EXCLUDE -- $SCOPE
rg -n 'constructor\s*\(' --type ts $EXCLUDE -- $SCOPE

# Fat Interfaces / Broken Substitution: abstractions and their declared members
rg -n 'interface\s+\w+|abstract\s+class\s+\w+' --type ts $EXCLUDE -- $SCOPE
rg -n 'abstract\s+\w+\s*\(' --type ts $EXCLUDE -- $SCOPE

# Broken Substitution: declared edges (implements/extends) — structural implementors are NOT found here
rg -n 'implements\s+\w+|extends\s+\w+' --type ts $EXCLUDE -- $SCOPE
rg -n -i 'not.?implemented|unsupported' --type ts $EXCLUDE -- $SCOPE
rg -n 'instanceof\s+\w+' --type ts $EXCLUDE -- $SCOPE

# Rigid Extension Points: discriminant switches, literal unions, boolean parameters
rg -n 'switch\s*\(' --type ts $EXCLUDE -- $SCOPE
rg -n --pcre2 "type\s+\w+\s*=\s*'[^']+'\s*\|" --type ts $EXCLUDE -- $SCOPE
rg -n --pcre2 '\(\s*[^)]*\b\w+\s*:\s*boolean\b' --type ts $EXCLUDE -- $SCOPE

# Concrete Dependency Chains: construction sites (fires on value types too — filter while reading)
rg -n 'new\s+[A-Z]\w*\(' --type ts $EXCLUDE -- $SCOPE

# Concrete Dependency Chains: module-level clients (then find the methods that read them)
rg -n --pcre2 '^(export\s+)?const\s+\w+\s*=\s*new\s+[A-Z]\w*\(' --type ts $EXCLUDE -- $SCOPE

# Composition-root nomination (behavior decides; these only point the search)
rg -n '@Module\(|providers\s*:|container\.bind|@Injectable\(|@injectable\(' --type ts $EXCLUDE -- $SCOPE
```

## Phase 4 — TypeScript-specific evaluation

For each `new X(...)` nominated:

- Is `X` a service — does it do I/O or hold process-external state? A DTO, `Map`, or builder is not.
- Is the enclosing function a module registration, container binding, or entry-point wiring? → composition root.
- Does the unit **keep** the object, or hand it to another constructor? Handed on → root.
- Is the constructor `@Injectable()`-injected, or an Angular injector parameter? → not created by the unit.
- What can the caller not control — host, credentials, timeout, clock, randomness? Name it, or there is no finding.

For each interface / abstract class:

- Is the seam live — received from outside by a production consumer, resolved by a Nest provider or Inversify binding,
  a second implementation, or a hand-written fake? No → simplicity-hunter; cross-reference, do not score.
- Live: which consumers call which subset, and are the unused members unrelated to the used ones?
- **Enumerate implementors by reading consumers, not only by `implements`.** Structural satisfaction leaves no marker.
  Record in Scope what was searched and that implementors outside the searched consumers — external packages
  included — are not found.

For each thrown not-implemented / silent-nullish override:

- What does the base promise (doc comment, abstract member, a relying consumer), and does a consumer holding the
  abstraction reach this member? Reachability sets Severity, not ownership.
- Apply the within-skill routing before choosing between Broken Substitution and Fat Interfaces.

For each `instanceof` in a consumer:

- Contract type (interface, abstract class with overridable behavior) or data variant set (discriminated union
  members, classes used purely as shapes)? Variant set → invariant-hunter.
- Does the branch compensate for a broken promise, or unlock an extra outside the contract?

For each `switch` on a discriminant:

- List every site project-wide. One site → no finding.
- Arms sharing one responsibility, or heterogeneous? Heterogeneous → recommend exhaustiveness per site, raise nothing.
- `git log -S "'<variant literal>'"` — did a variant addition touch two or more of the listed sites? No → withdraw.
  `assertNever` arms at every site change nothing about this test.

For each `boolean` parameter:

- Dispatched at two or more sites on a set shown open? → Rigid Extension Points. One site → simplicity-hunter's
  Over-Parameterized APIs; cross-reference.

For each class in scope:

- Which actors do its members serve? Two with independent reasons to change → finding. Methods that all mutate one
  entity through one workflow → cohesive aggregate, no finding.
- Is a framework construct prescribing the shape? Name it; the body is still evaluated.
