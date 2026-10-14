# Boundary Hunter — TypeScript reference

Contents: Applicability of the categories · Generated-code and test-path eligibility · TypeScript principles · Boundary unit, public entry, export, publication · Layer map, prohibitions, and policy · External types · Emit and erasure · Per-category TypeScript content · Toolchain · Phase 2 — graph build · Phase 3 — TypeScript scans · Phase 5 — TypeScript-specific evaluation

## Applicability of the categories

| Category | Applicable | Reason |
| -------- | ---------- | ------ |
| Dead Exports | **yes** | `export` judged at the unit's entry; a file `export` a sibling inside the unit imports is how files share, never a finding. Consolidated form for `export *`; `knip --include-entry-exports` nominates when present |
| Leaked Internals | **yes** | An exported type or member whose shape is the implementation, with an external consumer touching it |
| Deep Imports | **yes** | Bypassing the barrel, the `exports` field, or a **unit-named** alias. A root wildcard alias (`@/*` → `src/*`) is not an entry; a directory with no barrel, no `exports`, and no unit-named alias has no deep imports at all |
| Dependency Direction Violations | **yes** | **File** edges, so `src/domain/order.ts → src/infra/postgres.ts` inside one workspace package is judged |
| Cyclic Dependencies | **yes** | File graph. Kind by erasure of `import type` and compiler-elided edges, per tsconfig and TypeScript version |
| External Type Leaks | **yes** | External = a `node_modules` specifier that is not a workspace package, except Node builtins, `@types/node`, and `lib.*` types |
| Generic Boundary Names | **yes** | Directory or workspace-package unit. **Never a file**: a 700-line `utils.ts` is smell-hunter's God Module |

## Generated-code and test-path eligibility

A file is generated (ineligible for reporting) only when identified by an authoritative in-file marker where one
exists (`// @generated`, `// Code generated`, GraphQL / protobuf / OpenAPI / Prisma client banners). Scan globs
such as `*.generated.*`, `__generated__/`, `*.g.ts`, `generated/` are approximations for scanning convenience.

Dependency and build trees (`node_modules/`, `dist/`, `build/`, `.next/`, `out/`), lockfiles, and Markdown-only inputs
are also ineligible.

**Test paths are ineligible** (see Test-code scope in SKILL.md): `*.test.*`, `*.spec.*`, `*.e2e.*`, `__tests__/`.

**JavaScript files** (`.js`, `.jsx`, `.mjs`, `.cjs`) are graph nodes (SKILL.md Terms › Import graph): their ESM
`import` and CJS `require` edges are read. Record them under Exclusions with the graph-inclusion note.

## TypeScript principles

- **The unit hierarchy is workspace package → barrel directory → file.** Take the first that applies. A file unit has
  a public surface (its exports) but is never a Generic Boundary Name.
- **An alias is an entry only when it names a unit.** `@org/auth` → `packages/auth` and `@auth` →
  `src/auth/index.ts` are entries. `@/*` → `src/*` and `~/*` are convenience prefixes: nothing imported through them
  is deep on that account, and `@/auth/internal/tokens` is deep only if `src/auth` itself has a barrel.
- **Erasure is a property of the compiler, not of the syntax alone.** The same `import { Foo }` used only in
  annotations is erased by `tsc` defaults and preserved under `verbatimModuleSyntax`. Read the version and the flag
  before classifying any cycle.
- **`exports` is the enforcement mechanism.** `package.json` `exports` makes a deep path a resolution error, which is
  what `internal/` is for Go. A tsconfig `paths` alias enforces nothing; it only names.
- **Components are the edge tier.** `React.FC`, `ReactNode`, and JSX types in a component module are the wrapping
  layer; component typing is not hunted here.

## Boundary unit, public entry, export, publication

- **Boundary unit** — in order: the **workspace package** when its `package.json` `exports` or `main` names an entry;
  else the **directory with a barrel** (`index.ts` / `index.tsx`); else the **file**.
- **Public entry** — the `exports` entry, the barrel, or a tsconfig `paths` alias **that maps to a package root or a
  barrel**. A root wildcard alias is not an entry. A directory with none of the three has no entry, so it has no Deep
  Imports and every file is public.
- **Export** — the `export` keyword, judged at the unit's **entry**. An export a sibling file inside the same unit
  imports is not a finding; an export the entry re-exports and nothing outside imports is.
- **External consumer** — an import from outside the unit in a non-test file, plus string references (a dynamic
  `import()` with a literal specifier, a route or plugin manifest naming the module).
- **Publication** — per SKILL.md Terms › Published unit.

## Layer map, prohibitions, and policy

- **Layer map sources**, in precedence: repository instructions and named ADR files; then conventional sibling
  directory names from the fixed vocabulary — inner `domain`, `core`, `entities`; middle `application`, `usecase`,
  `usecases`; edge `infra`, `infrastructure`, `adapters`, `persistence`, `db`, `transport`, `http`, `handlers`,
  `controllers`, `cli`, `ui`, `web`, `components`, `pages`. Tiers annotate **files** by directory.
- **Prohibition sources**: a `forbidden` rule in `.dependency-cruiser.{js,cjs,mjs,json}` / `dependency-cruiser.config.*`;
  an Nx `@nx/enforce-module-boundaries` `depConstraints` entry; an `eslint-plugin-boundaries` rule. Each is evidence
  for the edges it names. **None of them is a layer map** — a tag set is not an ordering.
- **Policy**: the same files where a rule **explicitly permits** an edge, plus repository instructions. An edge no
  rule mentions is neither permitted nor forbidden.

## External types

External = a specifier resolving into `node_modules` that is **not** a workspace package (`workspace:*`, an npm or
pnpm workspace member — those are first-party). **Not external:** Node builtins with or without the `node:` prefix
(`fs`, `node:fs`, `path`), `@types/node`, and TypeScript `lib.*` types (`Date`, `Promise`, `Map`, DOM types).

Marker-generated declarations — `@prisma/client`, OpenAPI and GraphQL codegen outputs, protobuf stubs — are external
types by stated policy, whoever owns the schema.

## Emit and erasure

Read the **resolved TypeScript version** — from `node_modules/typescript/package.json`, else the lockfile, never the
`package.json` range — and the emit flags from `tsconfig.json`:

- **5.0 and later:** the only flag that preserves an otherwise-elidable import is **`verbatimModuleSyntax`**.
  `preserveValueImports` and `importsNotUsedAsValues` are deprecated at 5.0 and have **no effect from 5.5**.
- **Before 5.0:** `preserveValueImports` and `importsNotUsedAsValues: "preserve"` also preserve.
- **Always erased:** `import type { X } from './x'`, `export type { X } from './x'`.
- **Always runtime:** a side-effect import (`import './x'`).
- **`import { type X } from './x'` under `verbatimModuleSyntax`** emits `import {} from './x'` — the module is still
  evaluated, so the edge is **runtime**, unlike `import type`.
- **Default (`tsc`, no preserving flag):** an import whose every binding is used only in type positions is elided, so
  the edge is **erased**.
- **A bundler that ignores tsconfig** (esbuild, swc, Babel) elides by its own rules. When the emit pipeline cannot be
  established from the repository, **withdraw the cycle's Kind** with a `Limitation` line rather than guessing, and
  never run the bundler to find out.

Record the `Emit:` Scope line with what was read.

## Per-category TypeScript content

### Dead Exports — TypeScript forms

- `zero consumers` — the entry exports it and nothing outside the unit imports it, and the unit is closed.
- `test only` — the only importer is a test path.
- `consolidated barrel` — `export * from './internal/helpers'` exposing N symbols nothing outside imports is **one**
  row: a representative symbol, `Occurrences: N`, Action "named re-exports of the public API". A consumed internal
  among them gets its own Leaked Internals row.

**Enumeration caveat:** default imports (`import Foo from …`), namespace imports (`import * as m`), aliased named
imports (`import { a as b }`), and re-export chains defeat name grep. Read the importers; `knip` nominates but does
not decide.

### Leaked Internals — TypeScript forms

An exported type or member whose shape is the implementation, with an external consumer touching it: an exported
`interface CacheEntry` a consumer constructs, an exported mutable module-level `Map` a consumer writes, an exported
AST node type from a unit whose promise is a formatted string. A parser whose documented product *is* its AST passes
the rewrite test.

### Deep Imports — TypeScript forms

- Relative: `import { tokens } from '../auth/internal/tokens'` where `auth/index.ts` exists.
- Cross-package: `import '@org/auth/src/internal/tokens'` where `@org/auth` declares `exports`. The Action is the
  `exports` entry — the mechanism that makes the deep path fail to resolve.
- Unit-named alias: `import { x } from '@auth/internal/x'` where `@auth` → `src/auth/index.ts`.
- **Not deep:** an import through a root wildcard (`@/auth/internal/tokens` with `@/*` → `src/*`) when `src/auth` has
  no barrel; any import from a directory with no barrel, no `exports`, and no unit-named alias.

### Dependency Direction Violations — TypeScript content

**File edges.** A workspace package is not the unit here: `src/domain/order.ts → src/infra/postgres.ts` inside one
package is a finding when both directories carry tiers. The Action order: move the type to its owner; inject from the
composition root; an interface declared **in the inward file's unit** only where the import cannot otherwise be
broken — which in TypeScript is rare, because a type-only import is usually the honest fix and an erased edge is
still an outward edge.

### Cyclic Dependencies — TypeScript content

- **Kind** — remove every erased edge (per the Emit rules above). The cycle survives → `runtime`; it disappears →
  `type-only`, **including** a cycle of one runtime and one `import type` edge.
- **`depcruise` as classifier** — when `depcruise` is present, a rule with
  `viaOnly: { dependencyTypesNot: ['type-only'] }` matches exactly the cycles whose every edge survives erasure,
  which is this definition. It is **valid only when the project's configuration sets `tsPreCompilationDeps: true`**;
  otherwise the graph contains no type-only edges at all and the classification is read from source. The Toolchain
  line says which.
- **Failure `provable`** — a module-level read of a partner's `const` or `class` binding before its initialization on
  the named entry path: ESM hoists the declaration but leaves the binding in the temporal dead zone, so the read
  throws `ReferenceError`. `function` declarations hoist fully and do not fail. Recorded `provable from {entry}:
  {file:line}`.
- **Production entry**: the `package.json` `main` / `bin` / `exports` entry, a framework's route or page discovery
  order.
- Cross-layer type-only edges → Dependency Direction Violations, with the cycle named in Evidence.
- A cycle every one of whose in-scope edges sits in a JavaScript file has **no eligible anchor**: report no row and
  write `Limitation: cycle {path} — no eligible in-scope edge`.

### External Type Leaks — TypeScript content

- `signature` — an inward unit's exported function, method, or type carrying an external type:
  `function checkout(req: Express.Request)` in `application/`.
- `re-export` — `export type { User } from '@prisma/client'`, `export { Prisma } from '@prisma/client'`, or
  `type User = PrismaUser` in an inward unit.
- `mapper output` — `toDomain(row: PrismaUser): Order` whose result still carries a Prisma enum or nested type.

`React.FC` in `components/` and `Express.Request` in `http/` are the wrapping layer — never findings. A
`PrismaUser` import inside `domain/user.ts` beside a hand-written `User` **is** a finding: the crossing, not the
mirror.

### Generic Boundary Names — TypeScript content

A directory or workspace-package unit named `util`, `utils`, `common`, `helpers`, `shared`, `misc`, `base`, `models`,
`types`, `lib` **and** exporting two or more unrelated capabilities, enumerated. `src/shared/` holding date helpers, a
feature-flag client, and a currency formatter is the common form. **Never a file** — `utils.ts` of any size is
smell-hunter's God Module.

## Toolchain

Present-only, from `node_modules/.bin`, read-only, never installed and never given a written configuration:

```bash
# <source roots>: the workspace package directories, else the tsconfig `include` roots (e.g. `src`, `packages`)

# Graph + cycles, against the PROJECT'S OWN config
node_modules/.bin/depcruise --output-type json --config <project config> <source roots>

# Only when depcruise is absent. madge reads only .js unless --extensions names the TypeScript ones
node_modules/.bin/madge --circular --json --extensions ts,tsx,mts,cts,js,jsx,mjs,cjs --ts-config tsconfig.json <source roots>

# Dead Exports nominations — the flag is required
node_modules/.bin/knip --include-entry-exports
```

`knip` without `--include-entry-exports` skips exports of entry files, which is exactly the unit-entry surface Dead
Exports judges; when the project's own script omits the flag, the Toolchain line records that it was added for this
read-only run. `madge` duplicates `depcruise` and is used only in its absence. Every tool here nominates; no finding
is tool output.

## Phase 2 — graph build

Nodes are files (`.ts`, `.tsx`, `.mts`, `.cts`, plus `.js`, `.jsx`, `.mjs`, `.cjs` as non-anchoring nodes). Edges are
`import`, `export … from`, `import()` with a literal specifier, and `require()`. Resolve relative paths, tsconfig
`paths` aliases, and workspace package names to files. Tag each edge **erased** or **runtime** per the Emit rules.
Project nodes onto units for the four surface categories; keep file edges for direction and cycles.

The graph scans keep generated files: a generated client that imports a hand-written module is its consumer. The
`from` scan runs multiline (`-U`) so a
wrapped `import {` list reports from its first line.

```bash
GRAPH_EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/build/** --glob !**/.next/** --glob !**/out/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/**'

# Edges with a `from` clause: imports and re-exports, single- or multi-line
rg -n -U --pcre2 "^\s*(import|export)\s[^;'\"=()]*?\bfrom\s+['\"][^'\"]+['\"]" --type ts --type js $GRAPH_EXCLUDE -- .

# Side-effect imports (always runtime), require(), and import() with a literal
rg -n --pcre2 "^\s*import\s+['\"]|require\(['\"]|import\(['\"]" --type ts --type js $GRAPH_EXCLUDE -- .

# Erased-edge candidates (classification needs the Emit line)
rg -n --pcre2 "^\s*(import|export)\s+type\s" --type ts $GRAPH_EXCLUDE -- .
rg -n -U --pcre2 "import\s*\{[^}]*\btype\s" --type ts $GRAPH_EXCLUDE -- .
```

## Phase 3 — TypeScript scans

`$TS_FILES` is this language's eligible list, restored from `<run>/typescript.txt` (SKILL.md Phase 1 step 4).

```bash
EXCLUDE='--glob !**/node_modules/** --glob !**/dist/** --glob !**/build/** --glob !**/.next/** --glob !**/*.test.* --glob !**/*.spec.* --glob !**/*.e2e.* --glob !**/__tests__/** --glob !**/*.generated.* --glob !**/__generated__/** --glob !**/*.g.ts --glob !**/generated/**'

# Dead Exports: the entry surface, and wildcard re-exports
rg -H -n --pcre2 "^\s*export\s+(async\s+)?(function|const|class|enum|type|interface|default)" --type ts $EXCLUDE -- $TS_FILES
rg -H -n --pcre2 "^\s*export\s+\*\s+from" --type ts $EXCLUDE -- $TS_FILES

# Deep Imports: paths past a barrel (substitute the unit's own directory name and aliases)
rg -H -n --pcre2 "from\s+['\"][^'\"]*/(internal|private|impl|src)/" --type ts $EXCLUDE -- $TS_FILES

# Entries, units, and publication — project-wide
rg -n '"exports"|"main"|"private"|"workspaces"' --glob '**/package.json' --glob '!**/node_modules/**' -- .
rg -n '"paths"|"verbatimModuleSyntax"|"preserveValueImports"|"importsNotUsedAsValues"' --glob '**/tsconfig*.json' --glob '!**/node_modules/**' -- .

# Resolved TypeScript version: the installed package, else the lockfile entries (the `version` line follows each)
rg -n -m1 '"version"' -- node_modules/typescript/package.json
rg -n -A3 'node_modules/typescript"|^\s*/?"?typescript@|^\s+typescript:$' -- package-lock.json pnpm-lock.yaml yarn.lock 2>/dev/null

# External Type Leaks: bare-specifier imports (then read the importing file's tier)
rg -H -n --pcre2 "from\s+['\"][^.'\"][^'\"]*['\"]" --type ts $EXCLUDE -- $TS_FILES

# Contracts and policy — project-wide; --hidden reaches .dependency-cruiser.* and .eslintrc*
rg -n --hidden 'forbidden|depConstraints|boundaries/element-types' --glob '**/.dependency-cruiser.*' --glob '**/dependency-cruiser.config.*' --glob '**/eslint.config.*' --glob '**/.eslintrc*' --glob '**/nx.json' --glob '**/project.json' --glob '!**/node_modules/**' -- .
```

## Phase 5 — TypeScript-specific evaluation

For each unit:

- Which entry applies — `exports`, barrel, unit-named alias, or none? A unit with no entry has **no Deep Imports**.
- `private: true`, or unreachable from `exports` / `main` → closed. Otherwise open → withdraw Dead Exports with a
  `Limitation` line; other categories still report.

For each export at an entry:

- Importers outside the unit, read (default, namespace, aliased, and re-export chains included), string references
  searched? None → Dead Exports (consolidated when it arrived through `export *`). Only tests → `test only`.
- Consumed, and does a member fail the rewrite test with a statable reason? → Leaked Internals.
- Consumed only by a sibling file inside the same unit → no finding.

For each import edge:

- Past an entry that exists → Deep Imports. Through a root wildcard, or into a directory with no entry → no finding.
- Endpoints carry different tiers under a recorded map, or a `forbidden` / `depConstraints` rule names the edge →
  Dependency Direction Violations (file edges, so intra-package crossings count). Explicitly permitted → `Policy:`.

For each cycle:

- Classify every edge with the Emit rules; remove erased edges. Survives → `runtime`; gone → `type-only`.
- Emit pipeline not establishable → withdraw Kind with a `Limitation` line.
- `runtime`: a module-level read of a partner's `const` / `class` binding before initialization on the entry path →
  `provable`, with the entry named and whether it is a production entry. Otherwise `none observed`.
- Every in-scope edge in a JavaScript file → no anchor; `Limitation` line.

For each exported declaration in an inward-tier unit (boundary source required):

- Carries a `node_modules` specifier's type that is not a workspace package, not a Node builtin, not `@types/node`,
  not `lib.*`, or carries a marker-generated type → `signature`; an alias or `export type … from` of one →
  `re-export`; a conversion still carrying one → `mapper output`. Edge tier (components, http, adapters), or no
  boundary source → no finding.
