# Boundary Hunter Tooling — Tool-Assisted Audit Reference

Reference for `boundary-hunter-ts` (linked from its SKILL.md). This workflow is strict: boundary findings must come
from `dependency-cruiser` and `ts-morph`, not grep heuristics. Use it when machine-verifiable evidence is required —
gating CI on architecture contracts, validating refactors, or replacing regex-only boundary audits. For exploratory
reviews, the parent SKILL.md's judgment-based workflow applies instead.

## Scope

- Boundary violations only: dependency direction, cycles, deep imports, export surface leaks
- No type-invariant audit
- No code edits; produce an audit report only

## Tool Roles

1. **`dependency-cruiser`**: dependency graph evidence
   - Runtime and type-only cycles
   - Layer direction violations
   - Deep import violations
   - Fan-in and fan-out hotspots
2. **`ts-morph`**: symbol/API evidence
   - Public export inventory
   - Dead export candidates with real reference counts
   - Exported signatures that leak external package types
   - Exports that expose implementation details

Both tools provide **stronger static evidence than grep** — not completeness. Dynamic access, reflection, and
consumers outside the analyzed project remain invisible to them.

## Preconditions

1. Confirm a TypeScript project root and `tsconfig.json` path.
2. Confirm source roots (for example `{app_source}`, `packages/*/src`).
3. Confirm layer map with the requester before enforcing direction rules.
4. Resolve the tools — in this order, never mutating the project:
   ```bash
   # Prefer an existing local installation
   npm ls dependency-cruiser ts-morph --depth=0
   ```
   If both are present locally, use the project's binaries (`node_modules/.bin/depcruise`).
   If missing, install **explicitly pinned versions into a scratch prefix** — do not modify the project's
   `package.json` or lockfile, and do not run unpinned remote code via `npx --yes`:
   ```bash
   SCRATCH={scratch-dir}   # e.g. the session scratchpad; never the project root
   npm install --prefix "$SCRATCH" dependency-cruiser@{pinned-version} ts-morph@{pinned-version}
   DEPCRUISE="$SCRATCH/node_modules/.bin/depcruise"
   ```
   Place the ts-morph script (Phase 3) under `$SCRATCH` as well so its `require`/`import` of `ts-morph` resolves
   against the scratch `node_modules`. If a project-local install is truly unavoidable, get explicit approval
   first, report the mutation in the audit output, and leave cleanup to the user — do **not** auto-revert
   `package.json`/lockfile with `git checkout`, which can clobber pre-existing uncommitted edits.

Before running the audit, fill these placeholders for the target codebase:

- `{app_source}`: main app source root (for example `src`, `new-app/src`, `packages/app/src`)
- `{domain_layer}`: domain layer segment (for example `domain`, `core/domain`)
- `{application_layer}`: application/use-case layer segment (for example `application`, `use-cases`)
- `{infrastructure_layers_regex}`: infrastructure/edge layers as regex group (for example `(infra|adapters|ui|render)`)
- `{source_roots_regex}`: depcruise include regex for all roots under audit
- `{source_roots_args}`: CLI roots list for depcruise (space-separated)
- `{source_roots_csv}`: comma-separated roots for ts-morph script input
- `{test_exclude_regex}`: test/spec exclusion regex for depcruise

## Audit Workflow

### Phase 1: Encode Architecture Rules for `dependency-cruiser`

Create a temporary rules file (customize path regexes to the current codebase):

```js
// {scratch-dir}/{agent-name}-depcruise.boundary.cjs
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
    // Fill placeholders before running:
    // {app_source}, {domain_layer}, {application_layer},
    // {infrastructure_layers_regex}, {source_roots_regex}, {test_exclude_regex}
    forbidden: [
        {
            // Flags only cycles that are not purely type-only. `viaOnly` matches against
            // ALL modules in the cycle; a bare `to.dependencyTypesNot` would filter only the
            // directly examined edge and misclassify mixed cycles.
            name: 'no-circular-at-runtime',
            severity: 'error',
            from: {},
            to: {
                circular: true,
                viaOnly: { dependencyTypesNot: ['type-only'] }
            }
        },
        {
            // Complement: cycles consisting purely of type-only edges (triage separately)
            name: 'no-circular-type-only',
            severity: 'warn',
            from: {},
            to: { circular: true }
        },
        {
            name: 'no-domain-to-application',
            severity: 'error',
            from: { path: '^{app_source}/{domain_layer}' },
            to: { path: '^{app_source}/{application_layer}' }
        },
        {
            name: 'no-domain-to-infra',
            severity: 'error',
            from: { path: '^{app_source}/{domain_layer}' },
            to: { path: '^{app_source}/{infrastructure_layers_regex}' }
        },
        {
            name: 'no-application-to-infra',
            severity: 'warn',
            from: { path: '^{app_source}/{application_layer}' },
            to: { path: '^{app_source}/{infrastructure_layers_regex}' }
        },
        {
            // Cross-MODULE deep imports only. The `from` capture group + `$1` in `to.pathNot`
            // exempts same-module sibling imports; a bare `path: '^{app_source}/.+/.+'` from
            // anywhere would flag virtually every import two directories deep.
            // Where package.json `exports` or tsconfig aliases define real entrypoints, derive
            // the allowed paths from those instead.
            name: 'no-deep-imports',
            severity: 'warn',
            from: { path: '^{app_source}/([^/]+)/' },
            to: {
                path: '^{app_source}/[^/]+/.+',
                pathNot: '^{app_source}/$1/|/index\\.ts$'
            }
        }
    ],
    options: {
        tsConfig: { fileName: 'tsconfig.json' },
        doNotFollow: { path: 'node_modules' },
        includeOnly: '{source_roots_regex}',
        exclude: {
            path: '{test_exclude_regex}'
        }
    }
};
```

Cycles flagged by `no-circular-at-runtime` are runtime findings; cycles flagged **only** by `no-circular-type-only`
are type-only findings. The must-fix/should-fix triage below depends on this distinction, so verify both rules fire
as expected on a known cycle before trusting the classification.

### Phase 2: Run Graph Analysis

`$DEPCRUISE` is the resolved binary from Preconditions (project-local or scratch-prefix — never bare `npx`).

```bash
# Human-readable rule breaches
"$DEPCRUISE" --config {scratch-dir}/{agent-name}-depcruise.boundary.cjs --output-type err-long {source_roots_args} \
  > {scratch-dir}/{agent-name}-depcruise.boundary.err.txt

# Full machine-readable graph (for cycle/fan-in/fan-out analysis)
"$DEPCRUISE" --config {scratch-dir}/{agent-name}-depcruise.boundary.cjs --output-type json {source_roots_args} \
  > {scratch-dir}/{agent-name}-depcruise.boundary.json
```

Required outputs from this phase:

- Rule violations by rule name (`no-circular-at-runtime`, direction rules, deep imports)
- Runtime cycles vs type-only cycles
- Module fan-in/fan-out list (top 10 each)

### Phase 3: Run `ts-morph` Export Surface Audit

Write and run a temporary `ts-morph` script (placed under the scratch prefix) that outputs JSON evidence. The
script must:

1. Load the project from `tsconfig.json`.
2. Identify module entry files (`index.ts` and package entrypoints from `exports`).
3. Enumerate exported declarations for each module.
4. For each exported symbol, count references outside the declaring module.
5. Flag dead export candidates (`externalConsumers = 0`).
6. Flag exported signatures that include types imported from package specifiers (non-relative imports).
7. Emit `file:line` for each finding.

**Library caveat:** zero references *inside the audited project* does not prove a published library's export is
dead — external consumers are invisible to this analysis. Exempt package-entrypoint exports (anything reachable
from `package.json` `exports`/`main`/`types`) from the dead-export table, or label them "unused internally" rather
than "dead".

Run the script and persist output:

```bash
node {scratch-dir}/{agent-name}-ts-morph-boundary-audit.mjs \
  --tsconfig tsconfig.json \
  --roots {source_roots_csv} \
  --out {scratch-dir}/{agent-name}-tsmorph.boundary.json
```

### Phase 4: Correlate and Classify Findings

Correlate both artifacts before reporting:

- A depcruise direction violation + ts-morph external type leak in the same module = stronger evidence, higher priority
- A ts-morph dead export without graph pressure = lower priority cleanup
- Runtime cycles are **must-fix**
- Type-only cycles in same-layer co-evolving modules are **should-fix** unless explicitly justified

## Output Format

This reference feeds the parent skill's report. Standalone, save as
`Y-m-d-boundary-audit-tooling-{model-name}.md` (for example under `docs/dev-specs/`); in a boundary-hunter run,
merge the findings into its report instead. Severity uses the suite's Critical / High / Medium / Low definitions
from the parent SKILL.md.

```md
# Boundary Audit (Tool-Assisted) — {date}

## Context

- tsconfig: {path}
- Source roots: {list}
- Layer map used: {list}
- depcruise config: {scratch-dir}/{agent-name}-depcruise.boundary.cjs
- Artifacts:
  - {scratch-dir}/{agent-name}-depcruise.boundary.err.txt
  - {scratch-dir}/{agent-name}-depcruise.boundary.json
  - {scratch-dir}/{agent-name}-tsmorph.boundary.json

## Dependency Graph Findings (`dependency-cruiser`)

### Runtime Cycles (Must-Fix)

- {A -> B -> A} ({files})

### Type-Only Cycles (Needs Justification or Fix)

- {A -> B -> A} ({files}, justification={yes/no})

### Direction Violations

- {ruleName}: {from} -> {to} ({file:line})

### Deep Imports

- {consumer} imports {internal/path} ({file:line})

### High Fan-In / Fan-Out

- Fan-in: {module, count}
- Fan-out: {module, count}

## Export Surface Findings (`ts-morph`)

### Dead Export Candidates

| # | Module | Export | Kind | External Consumers | Entrypoint-Exempt? | Evidence  |
| - | ------ | ------ | ---- | ------------------ | ------------------ | --------- |
| 1 | ...    | ...    | ...  | 0                  | no                 | file:line |

### External Type Leaks in Public Signatures

| # | Module | Export | External Type | Layer                         | Evidence  |
| - | ------ | ------ | ------------- | ----------------------------- | --------- |
| 1 | ...    | ...    | ...           | {domain_or_application_layer} | file:line |

### Leaked Implementation Types

| # | Module | Export | Why Internal | Evidence  |
| - | ------ | ------ | ------------ | --------- |
| 1 | ...    | ...    | ...          | file:line |

## Recommendations (Priority Order)

1. **Critical / High**: runtime cycles, inward direction violations, external type leaks into `{domain_layer}` /
   `{application_layer}` APIs
2. **Medium**: type-only cycles without justification, deep imports, dead exports with zero consumers (and not
   entrypoint-exempt)
3. **Low**: API simplification for replaceability and fan-out reduction
```

## Operating Constraints

- **Tool-derived findings**: boundary findings must be derived from `dependency-cruiser` and `ts-morph` outputs.
- **No grep-only evidence**: regex search can help orient exploration but is insufficient as proof in this
  workflow. (The parent SKILL.md's grep-based phases are the exploratory alternative, not part of this one.)
- **Evidence required**: every finding includes `file:line` and artifact source.
- **Architecture-first**: do not enforce direction rules without an explicit layer map.
- **No project mutation**: tools run from an existing local install or a pinned scratch prefix; any unavoidable
  project-local install needs approval and is reported.
- **No implementation edits**: this workflow ends at an audit report.
