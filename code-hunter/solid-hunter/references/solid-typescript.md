# SOLID Hunter — TypeScript reference

Contents: Applicability of the categories · Generated-code and test-path eligibility · TypeScript principles · Per-category TypeScript content · Framework carve-outs — name the construct · Phase 2 — solid scans

## Applicability of the categories

| Category | Applicable | Unit | Note |
| -------- | ---------- | ---- | ---- |
| Responsibility Sprawl (SRP) | **yes** | class | A module of exported functions is functional style, not a class subject; record the style |
| Rigid Extension Points (OCP) | **yes** | any discriminant: a string-literal union, an enum, a `boolean` parameter | |
| Broken Substitution (LSP) | **yes** | `interface` and abstract-class implementors, and subclasses | Structural typing means a class can satisfy an interface with **no `implements` clause** |
| Fat Interfaces (ISP) | **yes** | `interface`, abstract class | Existence test decides ownership before width |
| Concrete Dependency Chains (DIP) | **yes** | class | |

## Generated-code and test-path eligibility

Generated-code markers, where one exists: `// @generated`, `// Code generated`, `/* eslint-disable */ //
prettier-ignore` headers emitted by a codegen tool, GraphQL/protobuf codegen banners. The scan globs `*.generated.*`,
`__generated__/`, `*.g.ts`, `generated/` approximate them.

Dependency and build trees (`node_modules/`, `dist/`, `build/`, `.next/`, `out/`), lockfiles, and Markdown-only inputs
are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*.test.*`, `*.spec.*`, `*.e2e.*`, `__tests__/`.

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

`if (store instanceof PostgresStore) store.vacuum()` where `vacuum` is outside the contract unlocks an extra —
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

## Phase 2 — solid scans

`$TS_FILES` is this language's eligible list, restored from `<run>/typescript.txt` (SKILL.md Phase 1 step 4); test
files are already out of it. A scan that needs a narrower list derives it by filtering that list, e.g.
`printf '%s\n' $TS_FILES | grep -v '\.spec\.ts$'`. That works for `.` too, because the globs then apply. **Scans
nominate only.**

```bash
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/build/** --glob !**/.next/** --glob !**/out/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Responsibility Sprawl: classes and their constructors (then read the members and name the actors)
rg -H -n 'class\s+\w+' --type ts $EXCLUDE -- $TS_FILES
rg -H -n 'constructor\s*\(' --type ts $EXCLUDE -- $TS_FILES

# Fat Interfaces / Broken Substitution: abstractions and their declared members
rg -H -n 'interface\s+\w+|abstract\s+class\s+\w+' --type ts $EXCLUDE -- $TS_FILES
rg -H -n 'abstract\s+\w+\s*\(' --type ts $EXCLUDE -- $TS_FILES

# Broken Substitution: declared edges (implements/extends) — structural implementors are NOT found here
rg -H -n 'implements\s+\w+|extends\s+\w+' --type ts $EXCLUDE -- $TS_FILES
rg -H -n -i 'not.?implemented|unsupported' --type ts $EXCLUDE -- $TS_FILES
rg -H -n 'instanceof\s+\w+' --type ts $EXCLUDE -- $TS_FILES

# Rigid Extension Points: discriminant switches, literal unions, boolean parameters
rg -H -n 'switch\s*\(' --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 "type\s+\w+\s*=\s*'[^']+'\s*\|" --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 '\(\s*[^)]*\b\w+\s*:\s*boolean\b' --type ts $EXCLUDE -- $TS_FILES

# Concrete Dependency Chains: construction sites (fires on value types too — filter while reading)
rg -H -n 'new\s+[A-Z]\w*\(' --type ts $EXCLUDE -- $TS_FILES

# Concrete Dependency Chains: module-level clients (then find the methods that read them)
rg -H -n --pcre2 '^(export\s+)?const\s+\w+\s*=\s*new\s+[A-Z]\w*\(' --type ts $EXCLUDE -- $TS_FILES

# Composition-root nomination (behavior decides; these only point the search)
rg -H -n '@Module\(|providers\s*:|container\.bind|@Injectable\(|@injectable\(' --type ts $EXCLUDE -- $TS_FILES
```
