# Boundary Hunter — report format

Read at Phase 6. Severity and Impact *definitions* live in SKILL.md; this file is the template and the per-category
table schemas.

The report is, in order: `## Scope`; `## Findings` with one `###` section per category that has at least one finding;
`## Recommendations (Priority Order)`. Unbraced Scope lines appear on every run that reaches scanning; a `{braced}`
line appears only when its condition holds. A run that stops early (empty scope, no eligible source) writes the Scope
lines resolved so far and its `Audit completed` line, nothing else.

**Column ceiling.** No table carries more than eight columns beyond the `#` index, and Severity and Impact are two of
them. When a category needs more detail, trim an existing column rather than appending.

**Layer map and Prohibitions lines.** `Layer map: {source} — {mapping}` (e.g. `Layer map: CLAUDE.md — domain <
application < infra`) or `Layer map: none`. `Prohibitions: {contract type, file}` per source, or `Prohibitions: none`.
When **both** are none, add `Dependency Direction Violations and External Type Leaks not evaluated — no boundary
source`; those two categories then have no tables.

**Graph line.** `Graph: {N nodes, M edges, E erased, U units} from {go list / import scan / depcruise}` — one per
language when several are in scope. Erased counts type-only edges (`import type`, `TYPE_CHECKING`, compiler-elided).

**Emit line.** TypeScript only: `Emit: TypeScript {version} — {verbatimModuleSyntax / default elision / not
established}`, read from the installed package or the lockfile, and `tsconfig.json`. `not established` (a
bundler-only build with no readable emit settings) withdraws cycle Kind with a `Limitation` line per cycle.

**Toolchain lines.** One per tool per language, in the form `<tool>: ran — <command>, <version>, <coverage>` /
`skipped — not installed` / `skipped — not configured` / `errored — <message>`. Every tool here is a **nominator**;
no finding is tool output. `knip` run without `--include-entry-exports` is recorded as such — without the flag it
skips exactly the unit-entry surface Dead Exports judges. `depcruise` against a config without
`tsPreCompilationDeps: true` has no type-only edges in its graph; the line says the classification was read from
source and `viaOnly` was not relied on.

**Enumeration line.** Present whenever consumers were found by reading rather than by scan — which is the normal
case. States what was searched (import forms read, string references searched, the use-as-interface search) and how
the set was closed. Findings claim the enumerated set only.

**Limitation lines.** One per **open (published) unit** whose Dead Exports were withdrawn:
`Limitation: {unit} open; {the signal that opened it}; consumer set not closed`. One per **cycle with no eligible
in-scope anchor** (every in-scope edge is a JavaScript file): `Limitation: cycle {path} — no eligible in-scope edge`.
One per **cycle whose Kind could not be established**: `Limitation: cycle {path} — emit pipeline not established`. One
per candidate withdrawn because a consumer set or a tier could not be closed. A withdrawal is never a Low finding.

**Policy line.** Present only when repository instructions or a contract configuration explicitly permitted an edge or
sanctioned a coupling; quotes the instruction or names the rule, and names the category and sites it withdrew. A
conflict — instructions forbid, a configuration permits — is *not* a Policy line: the finding stands and its Evidence
cell names the conflict.

**Evidence cells.**

- **Consumers** (Dead Exports) is `0`, `test only: {file}`, `package-local: N sites` (Go), or `string:
  {file:line}` — never a bare count where a form applies. **Export** carries the representative symbol and
  `Occurrences: N` for the consolidated barrel form.
- **Exposed member** (Leaked Internals) names the member **and** the rewrite-test reason in one cell (`Cache — a
  cache is implementation, not the unit's promise`). **Consumer** is `{file:line} reads` or `{file:line} mutates`;
  mutation is what makes the finding High.
- **Public entry** (Deep Imports) is what should have been imported, or `none yet — exposure` for the Go exposure
  form.
- **Basis** (Dependency Direction Violations) is `map: {tier} → {tier}, {source}` or `prohibition: {contract type},
  {file}, "{rule}"`. Nothing else is a basis.
- **Kind** and **Failure** (Cyclic Dependencies): Kind is `runtime` or `type-only`, decided by whether the cycle
  survives removal of every erased edge. Failure is `provable from {entry}: {file:line}`, `observed: {log or test}`,
  or `none observed`. The **Cycle** cell marks erased edges (`a.ts → b.ts → a.ts (erased)`).
- **Unit and boundary source** (External Type Leaks) carries the unit and why it is judged inward: its tier and the
  map, or the prohibition. **External type** names the package, not only the symbol.
- **Capabilities** (Generic Boundary Names) enumerates the two or more unrelated capabilities found under the name;
  one capability is no finding and no row.

When within-skill precedence chose one reading of an edge or a member over another, the reported finding's Evidence
cell names the other readings in one clause; a table with no Evidence column carries that clause, and the fan-in that
sets Impact, in its Action cell. A cycle anchors at any eligible in-scope edge — the first in sorted path
order when several qualify; there is no privileged closing edge. Generic Boundary Names and the Go exposure form have
no natural `file:line`: anchor at the package clause, `__init__.py:1`, or `index.ts:1`, else the first file of the
unit in sorted order.

```md
# Boundary Hunter Audit — {date}

## Scope

- Surface: {diff / path / codebase}
- Commit: {short SHA}{, dirty working tree — line numbers match no commit; re-locate findings by symbol name}
- {Base: {ref} → merge base {short SHA} — diff scope only}
- Files (raw manifest): {count or list}
- Eligible: {per-language counts or lists}
- Exclusions: {list — vendored / lockfile / md-only / generated-by-marker / test paths}
- References loaded: {go, python, typescript as present}
- {excluded — no reference for .<ext>: {count} files — naming each extension; JavaScript files are graph nodes only, never anchors}
- {Deleted in diff: {list} — only for diff scope with deletions}
- Layer map: {source} — {mapping} | none
- Prohibitions: {contract type, file} | none
- {Dependency Direction Violations and External Type Leaks not evaluated — no boundary source}
- Graph: {N nodes, M edges, E erased, U units} from {source}
- {Emit: TypeScript {version} — {flag / default elision / not established}}
- Toolchain: {per language — `go list: ran — go list -test=false ./..., go1.26, 84 packages` / `lint-imports: skipped — not configured` / `depcruise: ran — depcruise --output-type json src, 16.3, project config; tsPreCompilationDeps off — type-only edges read from source` / `knip: skipped — not installed`}
- {Enumeration: read every import of {unit} (named, default, namespace, aliased, wildcard); searched string references in pyproject.toml, settings/*.py; use-as-interface search for {method}; set closed by {how}}
- {Limitation: {unit} open; README documents `go get` — consumer set not closed}
- {Policy: "{quoted instruction or rule}" — withdraws {category} at {sites}}
- Audit completed: {N} findings

## Findings

### Dead Exports

| # | Location | Unit | Export | Form | Consumers | Severity | Impact | Action |
| - | -------- | ---- | ------ | ---- | --------- | -------- | ------ | ------ |
| 1 | pkg/auth/token.go:31 | `pkg/auth` | `HelperFn` | zero consumers | 0 | Medium | Low | Unexport to `helperFn`; no importer outside `pkg/auth` |
| 2 | orders/index.ts:4 | `orders` | `export * from './internal/helpers'` — `formatRow`, `Occurrences: 5` | consolidated barrel | 0 | Low | Medium | Replace the wildcard with named re-exports of the public API; five symbols leave the surface |
| 3 | cache/cache.go:12 | `cache` | `NewCache` | test only | test only: cache/cache_test.go:9 | Low | Low | Unexport; `cache_test` asserts the cached value through `Get`, which stays public |

### Leaked Internals

| # | Location | Unit | Export | Exposed member | Consumer | Severity | Impact | Action |
| - | -------- | ---- | ------ | -------------- | -------- | -------- | ------ | ------ |
| 1 | server/server.go:14 | `server` | `Server` | `Cache map[string]*Conn` — a connection cache is implementation, not the server's promise | other.go:40 reads | Medium | High | Unexport the field; expose `Conn(id)`; 30 packages import `server` |
| 2 | index/index.py:8 | `index` | `build_index` | returns `_Index` dict — the internal representation, not the documented product | api/search.py:22 mutates | High | Medium | Return an owned `Index` type; the consumer's write becomes a method |

### Deep Imports

| # | Location | Consumer unit | Imported path | Public entry | Form | Severity | Impact | Action |
| - | -------- | ------------- | ------------- | ------------ | ---- | -------- | ------ | ------ |
| 1 | billing/invoice.ts:3 | `billing` | `../auth/internal/tokens` | `auth` (auth/index.ts) | crossing | Medium | Medium | Import from `auth`; re-export `tokens` there if it is public, else expose the behavior |
| 2 | pkg/crypto/impl/impl.go:1 | `pkg/crypto` | — | none yet — exposure | exposure | Low | Low | Move to `pkg/crypto/internal/impl`; only the parent imports it, and the compiler would keep it that way. Were `pkg/auth` an importer too, the target would be `pkg/internal/impl` |

### Dependency Direction Violations

| # | Location | Edge | Basis | Evidence | Severity | Impact | Action |
| - | -------- | ---- | ----- | -------- | -------- | ------ | ------ |
| 1 | domain/order.go:7 | `domain/order` → `infra/postgres` | map: domain → infra, CLAUDE.md | also a deep import of `infra/postgres/internal`; fan-in 12 | High | High | `OrderRow` belongs to `infra`; move the mapping there and pass the domain type in from `cmd/api` |
| 2 | stuff/report.py:4 | `stuff.report` → `things.export` | prohibition: forbidden, .importlinter, "stuff may not import things" | no layer map; the contract names this edge | High | Medium | Move the shared constant into a third module both import |

### Cyclic Dependencies

| # | Location | Cycle | Kind | Failure | Evidence | Severity | Impact | Action |
| - | -------- | ----- | ---- | ------- | -------- | -------- | ------ | ------ |
| 1 | b.py:1 | `a.py → b.py → a.py` | runtime | provable from a (`[project.scripts] cli = a:main`): b.py:1 reads `X`, defined at a.py:12 after `import b` at a.py:2 | — | Critical | High | Move `X` into a third module both import, or define it above `import b` |
| 2 | src/orders/order.ts:2 | `orders/order.ts → orders/line.ts → orders/order.ts (erased)` | type-only | none observed | same layer; a cross-layer type-only cycle is reported as Dependency Direction Violations instead | Low | Low | Move the shared `OrderId` type into `orders/ids.ts`, which both import |

### External Type Leaks

| # | Location | Unit and boundary source | External type | Form | Severity | Impact | Action |
| - | -------- | ------------------------ | ------------- | ---- | -------- | ------ | ------ |
| 1 | domain/user/repo.go:18 | `domain/user` — inner tier, map from CLAUDE.md | `pgx.Tx` (github.com/jackc/pgx/v5) | signature | High | High | Does a transaction belong in the domain signature at all? If it does, a `Tx` interface declared in `domain/user`, implemented in `infra/postgres`, injected from `cmd/api` |
| 2 | domain/user/user.go:5 | `domain/user` — inner tier, map from CLAUDE.md | `pb.User` (gen/proto) | re-export | High | Medium | `type User = pb.User` makes the generated shape the domain's API; declare `User` and convert in `infra/grpc` |

### Generic Boundary Names

| # | Location | Unit | Capabilities | Form | Severity | Impact | Action |
| - | -------- | ---- | ------------ | ---- | -------- | ------ | ------ |
| 1 | pkg/util/util.go:1 | `pkg/util` | string padding; HTTP retry; money rounding | generic name | Low | Medium | Split into `strpad`, `httpretry`, `money`; each name states what it provides |
| 2 | storage/store.go:1 | `storage` | — | clause ≠ directory | Low | Low | Rename the directory to `store`, or the clause to `storage`; importers read one name and write the other |

## Recommendations (Priority Order)

Group by Severity (Critical → High → Medium → Low). Within each group, order by Impact (High → Medium → Low). Each
recommendation names the edit and what it removes; an Action that changes a published surface, a serialized shape, or
an initialization order names the risk.
```
